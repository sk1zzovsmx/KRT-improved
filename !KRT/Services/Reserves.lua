-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Events = feature.Events or addon.Events
local C = feature.C
local Options = feature.Options or addon.Options
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Services = feature.Services or addon.Services
local Item = feature.Item or addon.Item

local tconcat, twipe = table.concat, table.wipe
local pairs, ipairs, type, next = pairs, ipairs, type, next
local format = string.format

local tostring, tonumber = tostring, tonumber

local InternalEvents = Events.Internal

-- =========== Reserves Module  =========== --
-- Manages item reserves, import, and display.
do
    addon.Services.Reserves = addon.Services.Reserves or {}
    local module = addon.Services.Reserves
    local Service = module
    local ImportHelpers = assert(module._Import, "Reserves import helpers are not initialized")
    local DisplayHelpers = assert(module._Display, "Reserves display helpers are not initialized")
    local importParser = assert(ImportHelpers.BuildParser and ImportHelpers.BuildParser(), "Missing Reserves import parser")
    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON
    local reserveListClearedKey = "StrReserve" .. "ListCleared"

    -- ----- Internal state ----- --
    local reservesData = {}
    local persistedReservesData = {}
    local reservesByItemID = {}
    local reservesByItemPlayer = {}
    local playerItemsByName = {}
    local reservesDisplayList = {}
    local reservesDirty = false
    local importMode = nil -- 'multi' or 'plus'
    local pendingItemInfo = {}
    local pendingItemCount = 0
    local pendingDisplayRefreshHandle = nil
    local pendingDisplayRefreshQueued = false
    local pendingDisplayRefreshDelaySeconds = 0.05
    local collapsedBossGroups = {}
    local grouped = {}
    local syncedCacheMeta = nil
    local syncedCacheActive = false
    local RebuildIndex
    local hasPendingItem

    -- ----- Private helpers ----- --

    local function isDebugEnabled()
        return addon.hasDebug ~= nil
    end

    local function normalizeImportMode(mode)
        return (mode == "plus") and "plus" or "multi"
    end

    local function importModeToOptionValue(mode)
        return (normalizeImportMode(mode) == "plus") and 1 or 0
    end

    local function setImportMode(mode, syncOptions)
        local resolved = normalizeImportMode(mode)
        importMode = resolved

        if syncOptions ~= false then
            local value = importModeToOptionValue(resolved)
            Options.SetOption("srImportMode", value)
        end

        return importMode
    end

    local RESERVE_ENTRY_PERSISTED_FIELDS = {
        "rawID",
        "itemLink",
        "itemName",
        "itemIcon",
        "quantity",
        "class",
        "spec",
        "note",
        "plus",
        "source",
    }

    local function resolvePlayerNameDisplay(playerKey, player, fallbackName)
        local candidate = fallbackName
        if type(player) == "table" then
            candidate = player.playerNameDisplay or player.original or candidate
        end
        if candidate == nil or candidate == "" then
            candidate = playerKey
        end
        if Strings and Strings.NormalizeName then
            candidate = Strings.NormalizeName(candidate, true)
        elseif Strings and Strings.TrimText then
            candidate = Strings.TrimText(candidate, true)
        else
            candidate = tostring(candidate or "")
        end
        if candidate == nil or candidate == "" then
            return "?"
        end
        return candidate
    end

    local function copyReserveEntryForSave(src)
        if type(src) ~= "table" or not src.rawID then
            return nil
        end

        local dst = {}
        for i = 1, #RESERVE_ENTRY_PERSISTED_FIELDS do
            local key = RESERVE_ENTRY_PERSISTED_FIELDS[i]
            local value = src[key]
            if value ~= nil then
                dst[key] = value
            end
        end

        dst.quantity = tonumber(dst.quantity) or 1
        if dst.quantity < 1 then
            dst.quantity = 1
        end
        dst.plus = tonumber(dst.plus) or 0
        return dst
    end

    local function warnLegacyReservesPayload(phaseTag, stats)
        local originalCount = tonumber(stats.playersWithLegacyOriginal) or 0
        local rowPlayerCount = tonumber(stats.rowsWithLegacyPlayerField) or 0
        local droppedRows = tonumber(stats.droppedRows) or 0
        local mergedPlayers = tonumber(stats.mergedPlayerKeys) or 0
        if originalCount == 0 and rowPlayerCount == 0 and droppedRows == 0 and mergedPlayers == 0 then
            return
        end

        local template = Diag.W and Diag.W.LogReservesLegacyFieldsDetected
        if type(template) == "string" then
            addon:warn(template:format(tostring(phaseTag or "?"), originalCount, rowPlayerCount, droppedRows, mergedPlayers))
            return
        end

        addon:warn(
            ("[Reserves] Legacy fields phase=%s original=%d rowPlayer=%d dropped=%d merged=%d"):format(
                tostring(phaseTag or "?"),
                originalCount,
                rowPlayerCount,
                droppedRows,
                mergedPlayers
            )
        )
    end

    local function buildRuntimeReservesData(sourceData, phaseTag)
        local normalized = {}
        local stats = {
            playersWithLegacyOriginal = 0,
            rowsWithLegacyPlayerField = 0,
            droppedRows = 0,
            mergedPlayerKeys = 0,
        }

        for rawPlayerKey, player in pairs(sourceData or {}) do
            if type(player) == "table" then
                local displayName = resolvePlayerNameDisplay(rawPlayerKey, player, rawPlayerKey)
                local playerKey = Strings.NormalizeLower(displayName, true) or Strings.NormalizeLower(rawPlayerKey, true) or rawPlayerKey
                if type(playerKey) ~= "string" then
                    playerKey = tostring(rawPlayerKey or "")
                end
                if playerKey == "" then
                    playerKey = "?"
                end

                local container = normalized[playerKey]
                local hadContainer = (container ~= nil)
                if not container then
                    container = {
                        playerNameDisplay = displayName,
                        reserves = {},
                    }
                    normalized[playerKey] = container
                elseif not container.playerNameDisplay or container.playerNameDisplay == "?" then
                    container.playerNameDisplay = displayName
                end

                if player.original ~= nil then
                    stats.playersWithLegacyOriginal = stats.playersWithLegacyOriginal + 1
                end
                if hadContainer and rawPlayerKey ~= playerKey then
                    stats.mergedPlayerKeys = stats.mergedPlayerKeys + 1
                end

                local rows = player.reserves
                if type(rows) == "table" then
                    for i = 1, #rows do
                        local row = rows[i]
                        if type(row) == "table" and row.player ~= nil then
                            stats.rowsWithLegacyPlayerField = stats.rowsWithLegacyPlayerField + 1
                        end

                        local copied = copyReserveEntryForSave(row)
                        if copied then
                            container.reserves[#container.reserves + 1] = copied
                        else
                            stats.droppedRows = stats.droppedRows + 1
                        end
                    end
                end
            end
        end

        if phaseTag == "load" or phaseTag == "save" then
            warnLegacyReservesPayload(phaseTag, stats)
        end

        return normalized
    end

    local function copyReservesData(sourceData, target)
        twipe(target)
        for playerKey, player in pairs(sourceData or {}) do
            target[playerKey] = player
        end
    end

    local function applyRuntimeReservesData(sourceData, phaseTag, target)
        local normalized = buildRuntimeReservesData(sourceData, phaseTag)
        copyReservesData(normalized, target or reservesData)
        return normalized
    end

    local function buildSavedReservesData(sourceData)
        local normalized = {}

        for playerKey, player in pairs(sourceData or {}) do
            if type(player) == "table" then
                local persistedPlayerName = resolvePlayerNameDisplay(playerKey, player, playerKey)
                local container = normalized[persistedPlayerName]
                if not container then
                    container = { reserves = {} }
                    normalized[persistedPlayerName] = container
                end

                local rows = player.reserves
                if type(rows) == "table" then
                    for i = 1, #rows do
                        local copied = copyReserveEntryForSave(rows[i])
                        if copied then
                            container.reserves[#container.reserves + 1] = copied
                        end
                    end
                end
            end
        end

        return normalized
    end

    local function markPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if not itemId then
            return nil
        end
        local pending = pendingItemInfo[itemId]
        if not pending then
            pending = {
                nameReady = false,
                iconReady = false,
                name = nil,
                link = nil,
                icon = nil,
                requestHandle = nil,
            }
            pendingItemInfo[itemId] = pending
            pendingItemCount = pendingItemCount + 1
            if isDebugEnabled() then
                addon:debug(Diag.D.LogReservesTrackPending:format(itemId, pendingItemCount))
            end
        end
        if type(name) == "string" and name ~= "" then
            pending.name = name
        end
        if type(link) == "string" and link ~= "" then
            pending.link = link
        end
        if type(icon) == "string" and icon ~= "" then
            pending.icon = icon
        end
        if hasName then
            pending.nameReady = true
        end
        if hasIcon then
            pending.iconReady = true
        end
        return pending
    end

    local function getPendingItemInfo(pending)
        if not pending then
            return nil
        end
        return pending.name, pending.link, pending.icon
    end

    local function notifyReservesDataChanged(reason, raidId, mode, nPlayers)
        Bus.TriggerEvent(InternalEvents.ReservesDataChanged, reason, raidId, mode, nPlayers)
    end

    local function countReserves(sourceData)
        local players = 0
        local entries = 0
        for _, player in pairs(sourceData or {}) do
            if type(player) == "table" then
                players = players + 1
                local rows = player.reserves
                if type(rows) == "table" then
                    entries = entries + #rows
                end
            end
        end
        return players, entries
    end

    local function buildReservesChecksum(sourceData, mode)
        local parts = { normalizeImportMode(mode) }
        for playerKey, player in pairs(sourceData or {}) do
            if type(player) == "table" then
                parts[#parts + 1] = tostring(playerKey)
                parts[#parts + 1] = tostring(player.playerNameDisplay or "")
                local rows = player.reserves
                if type(rows) == "table" then
                    for i = 1, #rows do
                        local row = rows[i]
                        if type(row) == "table" then
                            parts[#parts + 1] = tostring(row.rawID or "")
                            parts[#parts + 1] = tostring(row.quantity or "")
                            parts[#parts + 1] = tostring(row.plus or "")
                            parts[#parts + 1] = tostring(row.class or "")
                        end
                    end
                end
            end
        end
        local text = tconcat(parts, "|")
        local checksum = 0
        for i = 1, #text do
            checksum = (checksum + (text:byte(i) * i)) % 1000000007
        end
        return tostring(checksum)
    end

    local function getActiveSyncMetadata()
        local players, entries = countReserves(reservesData)
        return {
            source = syncedCacheActive and (syncedCacheMeta and syncedCacheMeta.source or L.StrUnknown) or "local",
            checksum = syncedCacheActive and (syncedCacheMeta and syncedCacheMeta.checksum) or buildReservesChecksum(reservesData, importMode),
            mode = normalizeImportMode(importMode),
            players = players,
            entries = entries,
            runtime = syncedCacheActive == true,
        }
    end

    local function rebuildReserveIndexes(reason, raidId, mode, nPlayers)
        if not RebuildIndex then
            return false
        end
        RebuildIndex()
        if reason then
            notifyReservesDataChanged(reason, raidId, mode, nPlayers)
        end
        return true
    end

    local function clearDisplayRefreshQueue()
        if pendingDisplayRefreshHandle then
            addon.CancelTimer(pendingDisplayRefreshHandle, true)
            pendingDisplayRefreshHandle = nil
        end
        pendingDisplayRefreshQueued = false
    end

    local function flushDisplayRefresh()
        if pendingDisplayRefreshHandle then
            addon.CancelTimer(pendingDisplayRefreshHandle, true)
            pendingDisplayRefreshHandle = nil
        end
        if pendingDisplayRefreshQueued ~= true or not RebuildIndex then
            return false
        end
        pendingDisplayRefreshQueued = false
        return rebuildReserveIndexes("iteminfo-batch")
    end

    local function scheduleDisplayRefresh(forceImmediate)
        pendingDisplayRefreshQueued = true
        if forceImmediate then
            return flushDisplayRefresh()
        end
        if pendingDisplayRefreshHandle then
            return false
        end
        pendingDisplayRefreshHandle = addon.NewTimer(pendingDisplayRefreshDelaySeconds, function()
            pendingDisplayRefreshHandle = nil
            flushDisplayRefresh()
        end)
        return false
    end

    local function completePendingItem(itemId)
        if not itemId or not pendingItemInfo[itemId] then
            return
        end
        pendingItemInfo[itemId] = nil
        if pendingItemCount > 0 then
            pendingItemCount = pendingItemCount - 1
        end
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesItemReady:format(itemId, pendingItemCount))
        end
        if pendingItemCount == 0 then
            if isDebugEnabled() then
                addon:debug(Diag.D.LogReservesPendingComplete)
            end
            scheduleDisplayRefresh(true)
            return
        end
        scheduleDisplayRefresh(false)
    end

    local function visitReserveEntriesByItemId(itemId, visitFn)
        if not itemId or type(visitFn) ~= "function" then
            return false
        end

        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local reserveEntry = list[i]
                if type(reserveEntry) == "table" and reserveEntry.rawID == itemId then
                    if visitFn(reserveEntry) == true then
                        return true
                    end
                end
            end
            return false
        end

        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for i = 1, #player.reserves do
                    local reserveEntry = player.reserves[i]
                    if type(reserveEntry) == "table" and reserveEntry.rawID == itemId then
                        if visitFn(reserveEntry) == true then
                            return true
                        end
                    end
                end
            end
        end

        return false
    end

    local function getDisplayContext()
        return {
            reservesData = reservesData,
            reservesByItemID = reservesByItemID,
            reservesByItemPlayer = reservesByItemPlayer,
            playerItemsByName = playerItemsByName,
            reservesDisplayList = reservesDisplayList,
            grouped = grouped,
            collapsedBossGroups = collapsedBossGroups,
            resolvePlayerNameDisplay = resolvePlayerNameDisplay,
            getReserveEntryForItem = function(itemId, playerName)
                return Service:GetReserveEntryForItem(itemId, playerName)
            end,
            getPlusForItem = function(itemId, playerName)
                return Service:GetPlusForItem(itemId, playerName)
            end,
            isPlusSystem = function()
                return Service:IsPlusSystem()
            end,
            isMultiReserve = function()
                return Service:IsMultiReserve()
            end,
            getRaidService = function()
                return Services.Raid
            end,
            getCurrentRaid = function()
                return addon.Core and addon.Core.GetCurrentRaid and addon.Core.GetCurrentRaid() or nil
            end,
            setDirty = function(value)
                reservesDirty = value == true
            end,
            isDirty = function()
                return reservesDirty == true
            end,
        }
    end

    RebuildIndex = function()
        DisplayHelpers.RebuildIndex(getDisplayContext())
    end

    -- ----- Public methods ----- --

    -- ----- Saved Data Management ----- --

    function Service:Save(contextTag)
        local canonical = applyRuntimeReservesData(persistedReservesData, contextTag or "save", persistedReservesData)
        if not syncedCacheActive then
            copyReservesData(canonical, reservesData)
        end
        rebuildReserveIndexes()
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesSaveEntries:format(addon.tLength(reservesData)))
        end
        KRT_Reserves = buildSavedReservesData(canonical)
    end

    function Service:Load()
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesLoadData:format(tostring(KRT_Reserves ~= nil)))
        end
        clearDisplayRefreshQueue()
        local savedReserves = (type(KRT_Reserves) == "table") and KRT_Reserves or {}
        local normalized = applyRuntimeReservesData(savedReserves, "load", persistedReservesData)
        if not syncedCacheActive then
            copyReservesData(normalized, reservesData)
        end

        importMode = nil
        setImportMode(self:GetImportMode(), true)

        rebuildReserveIndexes()
    end

    function Service:ResetSaved()
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesResetSaved)
        end
        clearDisplayRefreshQueue()
        KRT_Reserves = nil
        twipe(persistedReservesData)
        twipe(reservesData)
        syncedCacheMeta = nil
        syncedCacheActive = false
        rebuildReserveIndexes("clear")
        local clearMessage = L[reserveListClearedKey]
        if clearMessage then
            addon:info(clearMessage)
        end
    end

    function Service:HasData()
        return next(reservesData) ~= nil
    end

    function Service:IsLocalDataAvailable()
        return next(persistedReservesData) ~= nil
    end

    function Service:HasItemReserves(itemId)
        if not itemId then
            return false
        end
        local list = reservesByItemID[itemId]
        return type(list) == "table" and #list > 0
    end

    -- ----- Reserve Data Handling ----- --

    function Service:GetReserve(playerName)
        if type(playerName) ~= "string" then
            return nil
        end
        local player = Strings.NormalizeLower(playerName)
        local reserve = reservesData[player]

        -- Log when the function is called and show the reserve for the player
        if isDebugEnabled() then
            if reserve then
                addon:debug(Diag.D.LogReservesPlayerFound:format(playerName, tostring(reserve)))
            else
                addon:debug(Diag.D.LogReservesPlayerNotFound:format(playerName))
            end
        end

        return reserve
    end

    function Service:GetPlayerReserveEntries(playerName)
        local reserve = self:GetReserve(playerName)
        if type(reserve) ~= "table" or type(reserve.reserves) ~= "table" then
            return {}
        end

        local entries = {}
        for i = 1, #reserve.reserves do
            local row = reserve.reserves[i]
            if type(row) == "table" then
                entries[#entries + 1] = row
            end
        end
        return entries
    end

    -- Get all reserves:
    function Service:GetAllReserves()
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesFetchAll:format(addon.tLength(reservesData)))
        end
        return reservesData
    end

    -- Parse imported text (SoftRes CSV)
    -- mode: "multi" (multi-reserve enabled; Plus ignored) or "plus" (priority; requires 1 item per player)
    function Service:GetImportMode()
        if importMode == nil then
            local inferred

            -- Infer import mode from loaded data when possible.
            -- If we detect any multi-item or quantity>1 entries, treat it as Multi-reserve.
            for _, player in pairs(reservesData) do
                if type(player) == "table" and type(player.reserves) == "table" then
                    if #player.reserves > 1 then
                        inferred = "multi"
                        break
                    end
                    for i = 1, #player.reserves do
                        local reserveEntry = player.reserves[i]
                        local quantity = (type(reserveEntry) == "table" and tonumber(reserveEntry.quantity)) or 1
                        if quantity and quantity > 1 then
                            inferred = "multi"
                            break
                        end
                    end
                end
                if inferred == "multi" then
                    break
                end
            end

            if not inferred then
                local optionValue = addon.options and addon.options.srImportMode
                inferred = (optionValue == 1) and "plus" or "multi"
            end

            setImportMode(inferred, false)
        end
        return importMode
    end

    function Service:SetImportMode(mode, syncOptions)
        return setImportMode(mode, syncOptions)
    end

    function Service:IsPlusSystem()
        return Service:GetImportMode() == "plus"
    end

    function Service:IsMultiReserve()
        return Service:GetImportMode() == "multi"
    end

    -- Strategy-based CSV parsing moved to Services/Reserves/Import.lua.
    local updateReserveItemData

    local function requestReserveItemInfo(itemId, pending)
        if not itemId or not Item or type(Item.RequestItemInfo) ~= "function" then
            return false
        end
        if pending and pending.requestHandle and not pending.requestHandle:IsCancelled() then
            return true
        end

        local handle
        handle = Item.RequestItemInfo(itemId, function(snapshot, ok)
            local current = pendingItemInfo[itemId]
            if not current or current.requestHandle ~= handle then
                return
            end
            current.requestHandle = nil

            if ok ~= true or type(snapshot) ~= "table" then
                return
            end

            local name = snapshot.itemName
            local link = snapshot.itemLink
            local icon = snapshot.itemTexture
            if (type(icon) ~= "string" or icon == "") and type(GetItemIcon) == "function" then
                local fetchedIcon = GetItemIcon(itemId)
                if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                    icon = fetchedIcon
                end
            end

            local hasName = type(name) == "string" and name ~= "" and type(link) == "string" and link ~= ""
            local hasIcon = type(icon) == "string" and icon ~= ""
            if hasName then
                updateReserveItemData(itemId, name, link, icon)
            end
            markPendingItem(itemId, hasName, hasIcon, name, link, icon)
            if hasName and hasIcon then
                if isDebugEnabled() then
                    addon:debug(Diag.D.LogReservesItemInfoReady:format(itemId, name))
                end
                completePendingItem(itemId)
            end
        end)

        if handle then
            local current = pendingItemInfo[itemId]
            if current then
                current.requestHandle = handle
            end
            return true
        end
        return false
    end

    function Service:ParseImport(text, mode, opts)
        return importParser.ParseImport(self, text, mode, opts)
    end

    function Service:ApplyImport(parsed, raidId, opts)
        if type(parsed) ~= "table" or type(parsed.reservesData) ~= "table" then
            return false, "INVALID_PARSED"
        end

        clearDisplayRefreshQueue()
        local mode = (parsed.mode == "plus" or parsed.mode == "multi") and parsed.mode or self:GetImportMode()
        applyRuntimeReservesData(parsed.reservesData, "import", persistedReservesData)
        copyReservesData(persistedReservesData, reservesData)
        syncedCacheMeta = nil
        syncedCacheActive = false
        setImportMode(mode, true)
        self:Save()

        local nPlayers = tonumber(parsed.nPlayers) or addon.tLength(reservesData)
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesParseComplete:format(nPlayers))
        end
        if not (opts and opts.silentInfo) then
            addon:info(format(L.SuccessReservesParsed, tostring(nPlayers)))
            local stats = parsed.importStats or {}
            addon:info(L.MsgReservesImportRows:format(tonumber(stats.validRows) or 0, tonumber(stats.skippedRows) or 0))
        end

        local reason = (opts and opts.reason) or "import"
        Bus.TriggerEvent(InternalEvents.ReservesDataChanged, reason, raidId, mode, nPlayers)
        return true, nPlayers
    end

    -- ----- Item Info Querying ----- --
    function Service:QueryItemInfo(itemId)
        if not itemId then
            return
        end
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesQueryItemInfo:format(itemId))
        end
        local pending = pendingItemInfo[itemId]
        local name, link, icon = getPendingItemInfo(pending)
        local hasName = type(name) == "string" and name ~= "" and type(link) == "string" and link ~= ""
        local hasIcon = type(icon) == "string" and icon ~= ""

        if not hasName then
            local fetchedName, fetchedLink, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
            if type(fetchedName) == "string" and fetchedName ~= "" then
                name = fetchedName
            end
            if type(fetchedLink) == "string" and fetchedLink ~= "" then
                link = fetchedLink
            end
            if type(tex) == "string" and tex ~= "" then
                icon = icon or tex
            end
        end

        if not hasIcon then
            local fetchedIcon = GetItemIcon(itemId)
            if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                icon = fetchedIcon
            end
        end

        hasName = type(name) == "string" and name ~= "" and type(link) == "string" and link ~= ""
        hasIcon = type(icon) == "string" and icon ~= ""
        if hasName then
            updateReserveItemData(itemId, name, link, icon)
        end
        pending = markPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if hasName and hasIcon then
            if isDebugEnabled() then
                addon:debug(Diag.D.LogReservesItemInfoReady:format(itemId, name))
            end
            completePendingItem(itemId)
            return true
        end

        requestReserveItemInfo(itemId, pending)

        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesItemInfoPendingQuery:format(itemId))
        end
        return false
    end

    -- Query all missing items for reserves
    function Service:QueryMissingItems(silent, primeFn)
        local seen = {}
        local count = 0
        local updated = false
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesQueryMissingItems)
        end
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for _, r in ipairs(player.reserves) do
                    local itemId = r.rawID
                    if itemId and not seen[itemId] and (not r.itemLink or not r.itemIcon) then
                        seen[itemId] = true
                        if not self:QueryItemInfo(itemId) then
                            if type(primeFn) == "function" then
                                primeFn(itemId)
                            end
                            count = count + 1
                        else
                            updated = true
                        end
                    end
                end
            end
        end
        if not silent then
            if count > 0 then
                addon:info(L.MsgReserveItemsRequested, count)
            else
                addon:info(L.MsgReserveItemsReady)
            end
        end
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesMissingItems:format(count))
            addon:debug(Diag.D.LogSRQueryMissingItems:format(tostring(updated), count))
        end
        return updated, count
    end

    -- Update reserve item data
    updateReserveItemData = function(itemId, itemName, itemLink, itemIcon)
        if not itemId then
            return
        end
        local icon = itemIcon
        if (type(icon) ~= "string" or icon == "") and itemName then
            icon = fallbackIcon
        end
        reservesDirty = true

        visitReserveEntriesByItemId(itemId, function(reserveEntry)
            reserveEntry.itemName = itemName
            reserveEntry.itemLink = itemLink
            reserveEntry.itemIcon = icon
            return false
        end)

        scheduleDisplayRefresh(false)

        return icon
    end

    -- Get reserve count for a specific item for a player
    function Service:GetReserveCountForItem(itemId, playerName)
        local r = self:GetReserveEntryForItem(itemId, playerName)
        if not r then
            return 0
        end
        return tonumber(r.quantity) or 1
    end

    -- Gets the reserve entry table for a specific item for a player (or nil).
    function Service:GetReserveEntryForItem(itemId, playerName)
        if not itemId or not playerName then
            return nil
        end
        local playerKey = Strings.NormalizeLower(playerName, true)
        if not playerKey then
            return nil
        end

        local byP = reservesByItemPlayer[itemId]
        if type(byP) == "table" then
            local r = byP[playerKey]
            if r then
                return r
            end
        end

        -- Fallback (should be rare if indices are up to date)
        local entry = reservesData[playerKey]
        if not entry then
            return nil
        end
        for _, r in ipairs(entry.reserves or {}) do
            if r and r.rawID == itemId then
                return r
            end
        end
        return nil
    end

    -- Gets the "Plus" value for a reserved item for a player (0 if missing).
    function Service:GetPlusForItem(itemId, playerName)
        -- Plus values are meaningful only in Plus System mode.
        if self:GetImportMode() ~= "plus" then
            return 0
        end
        local r = self:GetReserveEntryForItem(itemId, playerName)
        return (r and tonumber(r.plus)) or 0
    end

    -- Returns true if the item has any multi-reserve entry (quantity > 1).
    -- When true, SR "Plus priority" should be disabled for this item.
    function Service:HasMultiReserveForItem(itemId)
        if self:GetImportMode() ~= "multi" then
            return false
        end
        if not itemId then
            return false
        end
        return visitReserveEntriesByItemId(itemId, function(reserveEntry)
            local quantity = tonumber(reserveEntry.quantity) or 1
            return quantity > 1
        end)
    end

    -- Returns true when at least one reserve player for the item is present in
    -- the current raid (or in raidNum when provided).
    -- If raid context is unavailable, keeps backward-compatible behavior and
    -- treats any reserve entry as eligible.
    function Service:HasCurrentRaidPlayersForItem(itemId, raidNum)
        return DisplayHelpers.HasCurrentRaidPlayersForItem(getDisplayContext(), itemId, raidNum)
    end

    -- ----- SR Announcement Formatting ----- --

    -- Returns a list of formatted player tokens for an item.
    -- useColor:
    --   true/nil -> UI rendering (class colors)
    --   false    -> chat-safe rendering (no class color codes)
    -- showPlus:
    --   true/nil -> include "(P+N)" when Plus System is enabled
    --   false    -> hide Plus suffixes from formatted player tokens
    -- showMulti:
    --   true/nil -> include "(xN)" when Multi-reserve is enabled
    --   false    -> hide multi-reserve count suffixes from player tokens
    -- onlyCurrentRaidPlayers:
    --   true -> include only players present in the current raid (or raidNum if provided)
    -- raidNum:
    --   optional explicit raid id used when onlyCurrentRaidPlayers is true
    function Service:GetPlayersForItem(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
        return DisplayHelpers.GetPlayersForItem(getDisplayContext(), itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
    end

    -- Returns the formatted player list for an item (comma-separated).
    -- useColor, showPlus, showMulti, onlyCurrentRaidPlayers, and raidNum
    -- follow the same rules as GetPlayersForItem.
    function Service:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesFormatPlayers:format(itemId))
        end
        local list = self:GetPlayersForItem(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
        -- Log the list of players found for the item
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesPlayersList:format(itemId, tconcat(list, ", ")))
        end
        return #list > 0 and tconcat(list, ", ") or ""
    end

    function Service:GetDisplayList()
        return DisplayHelpers.GetDisplayList(getDisplayContext())
    end

    function Service:GetSyncMetadata()
        return getActiveSyncMetadata()
    end

    function Service:GetSyncPayload()
        return persistedReservesData, getActiveSyncMetadata()
    end

    function Service:SetSyncedReservesData(sourceData, meta)
        if self:IsLocalDataAvailable() then
            return false, "local_data_present"
        end

        local normalized = applyRuntimeReservesData(sourceData, "sync", reservesData)
        local mode = normalizeImportMode(meta and meta.mode)
        setImportMode(mode, false)

        local players, entries = countReserves(normalized)
        syncedCacheMeta = {
            source = tostring((meta and meta.source) or L.StrUnknown),
            checksum = tostring((meta and meta.checksum) or buildReservesChecksum(normalized, mode)),
            mode = mode,
            players = players,
            entries = entries,
            runtime = true,
        }
        syncedCacheActive = true
        rebuildReserveIndexes("sync", nil, mode, players)
        return true
    end

    function Service:DeleteSyncedReservesCache()
        if not syncedCacheActive then
            return false
        end
        syncedCacheMeta = nil
        syncedCacheActive = false
        copyReservesData(persistedReservesData, reservesData)
        rebuildReserveIndexes("sync-clear", nil, importMode, addon.tLength(reservesData))
        return true
    end

    function Service:IsSourceCollapsed(source)
        if not source then
            return false
        end
        return collapsedBossGroups[source] == true
    end

    function Service:ToggleSourceCollapsed(source)
        if not source then
            return false
        end
        local nextState = not (collapsedBossGroups[source] == true)
        collapsedBossGroups[source] = nextState
        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesToggleCollapse:format(source, tostring(nextState)))
        end
        return nextState
    end

    hasPendingItem = function(itemId)
        if not itemId then
            return false
        end
        return pendingItemInfo[itemId] ~= nil
    end

    Service._HasPendingItem = hasPendingItem
end
