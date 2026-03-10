-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Events = feature.Events or addon.Events or {}
local C = feature.C
local Options = feature.Options or addon.Options
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Services = feature.Services or addon.Services or {}

local tconcat, twipe = table.concat, table.wipe
local pairs, ipairs, type, next = pairs, ipairs, type, next
local format = string.format

local tostring, tonumber = tostring, tonumber

local InternalEvents = Events.Internal

-- =========== Reserves Module  =========== --
-- Manages item reserves, import, and display.
do
    addon.Services = addon.Services or {}
    addon.Services.Reserves = addon.Services.Reserves or {}
    local module = addon.Services.Reserves
    module.Service = module.Service or {}
    local Service = module.Service
    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON
    local reserveListClearedKey = "StrReserve" .. "ListCleared"

    -- ----- Internal state ----- --
    local reservesData = {}
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
    local RebuildIndex

    -- ----- Private helpers ----- --

    local playerTextTemp = {}

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

    local function applyRuntimeReservesData(sourceData, phaseTag)
        local normalized = buildRuntimeReservesData(sourceData, phaseTag)
        twipe(reservesData)
        for playerKey, player in pairs(normalized) do
            reservesData[playerKey] = player
        end
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
            }
            pendingItemInfo[itemId] = pending
            pendingItemCount = pendingItemCount + 1
            addon:debug(Diag.D.LogReservesTrackPending:format(itemId, pendingItemCount))
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
        RebuildIndex()
        Bus.TriggerEvent(InternalEvents.ReservesDataChanged, "iteminfo-batch")
        return true
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
        addon:debug(Diag.D.LogReservesItemReady:format(itemId, pendingItemCount))
        if pendingItemCount == 0 then
            addon:debug(Diag.D.LogReservesPendingComplete)
            scheduleDisplayRefresh(true)
            return
        end
        scheduleDisplayRefresh(false)
    end

    -- SoftRes exports class names like "Warrior", "Death Knight", etc.
    -- Normalize them to WoW class tokens (e.g. "WARRIOR", "DEATHKNIGHT") so we can use C.CLASS_COLORS.
    local function normalizeClassToken(className)
        if not className then
            return nil
        end
        local token = tostring(className):upper()
        token = token:gsub("%s+", ""):gsub("%-", "")
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then
            return token
        end
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
            return token
        end
        return nil
    end

    local function getClassColorStr(className)
        local token = normalizeClassToken(className) or "UNKNOWN"
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then
            return token, C.CLASS_COLORS[token]
        end
        local _, _, _, colorStr = addon.GetClassColor(token)
        return token, colorStr
    end

    local function colorizeReserveName(itemId, playerName, className)
        if not playerName then
            return playerName
        end

        local cls = className
        if (not cls or cls == "") and itemId then
            local r = Service:GetReserveEntryForItem(itemId, playerName)
            cls = r and r.class
        end
        local raidService = Services.Raid
        if (not cls or cls == "") and raidService and raidService.GetPlayerClass then
            cls = raidService:GetPlayerClass(playerName)
        end
        if not cls or cls == "" then
            return playerName
        end

        local _, colorStr = getClassColorStr(cls)
        if colorStr and colorStr ~= "ffffffff" then
            return "|c" .. colorStr .. playerName .. "|r"
        end
        return playerName
    end

    local function addReservePlayer(data, rOrName, countOverride, fallbackName)
        if not data.players then
            data.players = {}
        end
        if not data.playerCounts then
            data.playerCounts = {}
        end
        if not data.playerMeta then
            data.playerMeta = {}
        end

        local name, count, cls, plus
        if type(rOrName) == "table" then
            name = rOrName.playerNameDisplay or fallbackName or "?"
            count = tonumber(rOrName.quantity) or 1
            cls = rOrName.class
            plus = tonumber(rOrName.plus) or 0
        else
            name = rOrName or "?"
            count = tonumber(countOverride) or 1
        end
        count = count or 1

        local existing = data.playerCounts[name]
        if existing then
            data.playerCounts[name] = existing + count
        else
            data.players[#data.players + 1] = name
            data.playerCounts[name] = count
        end

        local meta = data.playerMeta[name]
        if not meta then
            meta = { plus = 0, class = nil }
            data.playerMeta[name] = meta
        end
        if cls and cls ~= "" and (not meta.class or meta.class == "") then
            meta.class = cls
        end
        if plus and plus > (meta.plus or 0) then
            meta.plus = plus
        end
    end

    local function getMetaForPlayer(metaByName, itemId, playerName)
        local meta = metaByName and metaByName[playerName]
        if meta and (meta.class or meta.plus) then
            return meta
        end

        -- Fallback: resolve from index (keeps compatibility even if meta isn't passed).
        if not meta then
            meta = { plus = 0, class = nil }
        end
        if itemId and playerName then
            local r = Service:GetReserveEntryForItem(itemId, playerName)
            if r then
                if r.class and r.class ~= "" and (not meta.class or meta.class == "") then
                    meta.class = r.class
                end
                local p = tonumber(r.plus) or 0
                if p > (meta.plus or 0) then
                    meta.plus = p
                end
            end
            local raidService = Services.Raid
            if (not meta.class or meta.class == "") and raidService and raidService.GetPlayerClass then
                meta.class = raidService:GetPlayerClass(playerName)
            end
        end
        return meta
    end

    -- Formats a single player token for display.
    -- useColor:
    --   true/nil -> UI rendering (class colors enabled)
    --   false    -> chat-safe rendering (no class color codes)
    local function formatReservePlayerName(itemId, name, count, metaByName, useColor, showPlus, showMulti)
        local meta = getMetaForPlayer(metaByName, itemId, name)
        local out
        if useColor == false then
            out = name
        else
            out = colorizeReserveName(itemId, name, meta and meta.class)
        end

        if showMulti ~= false and Service:IsMultiReserve() and count and count > 1 then
            out = out .. format(L.StrReserveCountSuffix, count)
        end

        if showPlus ~= false and Service:IsPlusSystem() and itemId then
            local p = (meta and tonumber(meta.plus)) or Service:GetPlusForItem(itemId, name) or 0
            if p and p > 0 then
                out = out .. format(" (P+%d)", p)
            end
        end

        return out
    end

    local function sortPlayersForDisplay(itemId, players, counts, metaByName)
        if not players then
            return
        end

        if Service:IsPlusSystem() and itemId then
            table.sort(players, function(a, b)
                local am = getMetaForPlayer(metaByName, itemId, a)
                local bm = getMetaForPlayer(metaByName, itemId, b)
                local ap = (am and tonumber(am.plus)) or 0
                local bp = (bm and tonumber(bm.plus)) or 0
                if ap ~= bp then
                    return ap > bp
                end
                return tostring(a) < tostring(b)
            end)
        elseif Service:IsMultiReserve() and counts then
            -- Optional: show higher quantities first for readability.
            table.sort(players, function(a, b)
                local aq = counts[a] or 1
                local bq = counts[b] or 1
                if aq ~= bq then
                    return aq > bq
                end
                return tostring(a) < tostring(b)
            end)
        end
    end

    local function buildPlayerTokens(itemId, players, counts, metaByName, useColor, showPlus, showMulti)
        if not players then
            return {}
        end
        sortPlayersForDisplay(itemId, players, counts, metaByName)
        twipe(playerTextTemp)
        for i = 1, #players do
            local name = players[i]
            playerTextTemp[#playerTextTemp + 1] = formatReservePlayerName(itemId, name, counts and counts[name] or 1, metaByName, useColor, showPlus, showMulti)
        end
        return playerTextTemp
    end

    -- How many player tokens we show inline in the Reserve List row before truncating.
    -- Long lists are rendered in a dedicated tooltip on the players line.
    local RESERVE_ROW_MAX_PLAYERS_INLINE = 6

    local function formatReservePlayerNameBase(itemId, name, metaByName)
        local meta = getMetaForPlayer(metaByName, itemId, name)
        return colorizeReserveName(itemId, name, meta and meta.class)
    end

    local function buildPlayersTooltipLines(itemId, players, counts, metaByName, shownCount, hiddenCount)
        local lines = {}
        local total = players and #players or 0
        lines[#lines + 1] = format(L.StrReservesTooltipTotal, total)
        if hiddenCount and hiddenCount > 0 and shownCount and shownCount > 0 then
            lines[#lines + 1] = format(L.StrReservesTooltipShownHidden, shownCount, hiddenCount)
        end

        if not players or total == 0 then
            return lines
        end

        if Service:IsPlusSystem() and itemId then
            -- Group by plus value (desc)
            local groups, keys = {}, {}
            for i = 1, #players do
                local name = players[i]
                local meta = getMetaForPlayer(metaByName, itemId, name)
                local p = (meta and tonumber(meta.plus)) or 0
                if groups[p] == nil then
                    groups[p] = {}
                    keys[#keys + 1] = p
                end
                groups[p][#groups[p] + 1] = formatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b)
                return a > b
            end)
            for i = 1, #keys do
                local p = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipPlus, p, tconcat(groups[p], ", "))
            end
        elseif Service:IsMultiReserve() and counts then
            -- Group by quantity (desc)
            local groups, keys = {}, {}
            for i = 1, #players do
                local name = players[i]
                local q = counts[name] or 1
                if groups[q] == nil then
                    groups[q] = {}
                    keys[#keys + 1] = q
                end
                groups[q][#groups[q] + 1] = formatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b)
                return a > b
            end)
            for i = 1, #keys do
                local q = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipQuantity, q, tconcat(groups[q], ", "))
            end
        else
            -- Fallback: just list names
            local names = {}
            for i = 1, #players do
                names[i] = formatReservePlayerNameBase(itemId, players[i], metaByName)
            end
            lines[#lines + 1] = tconcat(names, ", ")
        end

        return lines
    end

    local function buildPlayersText(itemId, players, counts, metaByName)
        if not players then
            return "", {}, ""
        end
        buildPlayerTokens(itemId, players, counts, metaByName)
        local total = #playerTextTemp
        local shown = total
        if RESERVE_ROW_MAX_PLAYERS_INLINE and RESERVE_ROW_MAX_PLAYERS_INLINE > 0 then
            shown = math.min(total, RESERVE_ROW_MAX_PLAYERS_INLINE)
        end
        local hidden = total - shown
        local shortText = tconcat(playerTextTemp, ", ", 1, shown)
        if hidden > 0 then
            shortText = shortText .. format(L.StrReservesPlayersHiddenSuffix, hidden)
        end
        local fullText = tconcat(playerTextTemp, ", ")
        local tooltipLines = buildPlayersTooltipLines(itemId, players, counts, metaByName, shown, hidden)
        return shortText, tooltipLines, fullText
    end

    local function getReserveSource(source)
        if source and source ~= "" then
            return source
        end
        return L.StrUnknown
    end

    function Service:FormatReserveItemIdLabel(itemId)
        return format(L.StrReservesItemIdLabel, tostring(itemId or "?"))
    end

    -- Kept for potential future tooltip/source variants.
    function Service:FormatReserveDroppedBy(source)
        if not source or source == "" then
            return nil
        end
        return format(L.StrReservesTooltipDroppedBy, source)
    end

    function Service:FormatReserveItemFallback(itemId)
        return format(L.StrReservesItemFallback, tostring(itemId or "?"))
    end

    RebuildIndex = function()
        twipe(reservesByItemID)
        twipe(reservesByItemPlayer)
        twipe(playerItemsByName)
        reservesDirty = true

        -- Build fast lookup indices
        for playerKey, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                local playerName = resolvePlayerNameDisplay(playerKey, player)
                player.playerNameDisplay = playerName
                player.original = nil
                local normalizedPlayer = Strings.NormalizeLower(playerName, true) or playerKey
                playerItemsByName[normalizedPlayer] = playerItemsByName[normalizedPlayer] or {}

                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID then
                        r.player = nil
                        r.playerNameDisplay = playerName
                        local itemId = r.rawID

                        local list = reservesByItemID[itemId]
                        if not list then
                            list = {}
                            reservesByItemID[itemId] = list
                        end
                        list[#list + 1] = r

                        local byP = reservesByItemPlayer[itemId]
                        if not byP then
                            byP = {}
                            reservesByItemPlayer[itemId] = byP
                        end
                        byP[normalizedPlayer] = r
                        playerItemsByName[normalizedPlayer][itemId] = true
                    end
                end
            end
        end

        twipe(reservesDisplayList)
        twipe(grouped)
        for itemId, list in pairs(reservesByItemID) do
            if type(list) == "table" then
                for i = 1, #list do
                    local r = list[i]
                    if type(r) == "table" then
                        local source = getReserveSource(r.source)

                        local bySource = grouped[source]
                        if not bySource then
                            bySource = {}
                            grouped[source] = bySource
                            if collapsedBossGroups[source] == nil then
                                collapsedBossGroups[source] = false
                            end
                        end

                        local data = bySource[itemId]
                        if not data then
                            data = {
                                itemId = itemId,
                                itemLink = r.itemLink,
                                itemName = r.itemName,
                                itemIcon = r.itemIcon,
                                source = source,
                                players = {},
                                playerCounts = {},
                                playerMeta = {},
                            }
                            bySource[itemId] = data
                        end

                        addReservePlayer(data, r)
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, data in pairs(byItem) do
                data.playersText, data.playersTooltipLines, data.playersTextFull = buildPlayersText(data.itemId, data.players, data.playerCounts, data.playerMeta)
                data.players = nil
                data.playerCounts = nil
                data.playerMeta = nil
                reservesDisplayList[#reservesDisplayList + 1] = data
            end
        end
    end

    -- ----- Public methods ----- --

    -- ----- Saved Data Management ----- --

    function Service:Save(contextTag)
        local canonical = applyRuntimeReservesData(reservesData, contextTag or "save")
        RebuildIndex()
        addon:debug(Diag.D.LogReservesSaveEntries:format(addon.tLength(reservesData)))
        KRT_Reserves = buildSavedReservesData(canonical)
    end

    function Service:Load()
        addon:debug(Diag.D.LogReservesLoadData:format(tostring(KRT_Reserves ~= nil)))
        clearDisplayRefreshQueue()
        local savedReserves = (type(KRT_Reserves) == "table") and KRT_Reserves or {}
        applyRuntimeReservesData(savedReserves, "load")

        -- Infer import mode from saved data when possible.
        -- If we detect any multi-item or quantity>1 entries, treat it as Multi-reserve.
        importMode = nil
        local inferred
        for _, p in pairs(reservesData) do
            if type(p) == "table" and type(p.reserves) == "table" then
                if #p.reserves > 1 then
                    inferred = "multi"
                    break
                end
                for i = 1, #p.reserves do
                    local r = p.reserves[i]
                    local qty = (type(r) == "table" and tonumber(r.quantity)) or 1
                    if qty and qty > 1 then
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
            local v = addon.options and addon.options.srImportMode
            inferred = (v == 1) and "plus" or "multi"
        end
        setImportMode(inferred, true)

        RebuildIndex()
    end

    function Service:ResetSaved()
        addon:debug(Diag.D.LogReservesResetSaved)
        clearDisplayRefreshQueue()
        KRT_Reserves = nil
        twipe(reservesData)
        RebuildIndex()
        Bus.TriggerEvent(InternalEvents.ReservesDataChanged, "clear")
        local clearMessage = L[reserveListClearedKey]
        if clearMessage then
            addon:info(clearMessage)
        end
    end

    function Service:HasData()
        return next(reservesData) ~= nil
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
        if reserve then
            addon:debug(Diag.D.LogReservesPlayerFound:format(playerName, tostring(reserve)))
        else
            addon:debug(Diag.D.LogReservesPlayerNotFound:format(playerName))
        end

        return reserve
    end

    -- Get all reserves:
    function Service:GetAllReserves()
        addon:debug(Diag.D.LogReservesFetchAll:format(addon.tLength(reservesData)))
        return reservesData
    end

    -- Parse imported text (SoftRes CSV)
    -- mode: "multi" (multi-reserve enabled; Plus ignored) or "plus" (priority; requires 1 item per player)
    function Service:GetImportMode()
        if importMode == nil then
            local v = addon.options and addon.options.srImportMode
            setImportMode((v == 1) and "plus" or "multi", false)
        end
        return importMode
    end

    function Service:SetImportMode(mode, syncOptions)
        return setImportMode(mode, syncOptions)
    end

    function Service:IsPlusSystem()
        return self:GetImportMode() == "plus"
    end

    function Service:IsMultiReserve()
        return self:GetImportMode() == "multi"
    end

    -- Strategy objects to keep Plus/Multi behaviors isolated.
    local importStrategies = {}

    local function cleanCSVField(field)
        if not field then
            return nil
        end
        return Strings.TrimText(field:gsub('^"(.-)"$', "%1"), true)
    end

    local function splitCSVLine(line)
        local out, field = {}, ""
        local inQuotes = false
        local i = 1
        while i <= #line do
            local ch = line:sub(i, i)
            if ch == '"' then
                local nextCh = line:sub(i + 1, i + 1)
                if inQuotes and nextCh == '"' then
                    field = field .. '"'
                    i = i + 1
                else
                    inQuotes = not inQuotes
                end
            elseif ch == "," and not inQuotes then
                out[#out + 1] = field
                field = ""
            else
                field = field .. ch
            end
            i = i + 1
        end
        out[#out + 1] = field
        return out
    end

    local function buildHeaderMap(fields)
        local map = {}
        for i = 1, #fields do
            local key = cleanCSVField(fields[i])
            if key and key ~= "" then
                map[Strings.NormalizeLower(key)] = i
            end
        end
        -- Consider it a header only if it includes key columns.
        if map["itemid"] and map["name"] then
            return map, true
        end
        return map, false
    end

    local function getField(fields, headerMap, key, fallbackIndex)
        if headerMap and headerMap[key] then
            return fields[headerMap[key]]
        end
        return fields[fallbackIndex]
    end

    local function readCSVField(fields, headerMap, key, fallbackIndex)
        return cleanCSVField(getField(fields, headerMap, key, fallbackIndex))
    end

    local function normalizeOptionalCSVField(value)
        if value == nil or value == "" then
            return nil
        end
        return value
    end

    local function buildParsedCSVRow(fields, headerMap)
        local itemIdStr = readCSVField(fields, headerMap, "itemid", 2)
        local source = readCSVField(fields, headerMap, "from", 3)
        local playerName = readCSVField(fields, headerMap, "name", 4)
        local className = readCSVField(fields, headerMap, "class", 5)
        local spec = readCSVField(fields, headerMap, "spec", 6)
        local note = readCSVField(fields, headerMap, "note", 7)
        local plus = readCSVField(fields, headerMap, "plus", 8)

        local itemId = tonumber(itemIdStr)
        local playerKey = Strings.NormalizeLower(playerName, true)
        if not itemId or not playerKey then
            return nil
        end

        return {
            itemId = itemId,
            player = playerName,
            playerKey = playerKey,
            source = normalizeOptionalCSVField(source),
            class = normalizeOptionalCSVField(className),
            spec = normalizeOptionalCSVField(spec),
            note = normalizeOptionalCSVField(note),
            plus = tonumber(plus) or 0,
        }
    end

    local function appendParsedCSVRow(rows, fields, headerMap, line, logSkipped)
        local row = buildParsedCSVRow(fields, headerMap)
        if row then
            rows[#rows + 1] = row
            return true
        end
        if logSkipped then
            addon:debug(Diag.D.LogSRParseSkippedLine:format(tostring(line)))
        end
        return false
    end

    local function parseCSVRows(csv)
        local rows = {}
        local headerMap = nil
        local firstLine = true
        local stats = {
            headerDetected = false,
            totalLines = 0,
            dataLines = 0,
            validRows = 0,
            skippedRows = 0,
        }

        for line in csv:gmatch("[^\n]+") do
            stats.totalLines = stats.totalLines + 1
            line = line:gsub("\r$", "")
            if firstLine then
                firstLine = false
                local maybeHeader = splitCSVLine(line)
                local map, isHeader = buildHeaderMap(maybeHeader)
                if isHeader then
                    stats.headerDetected = true
                    headerMap = map
                else
                    -- No header detected: treat first line as data
                    stats.dataLines = stats.dataLines + 1
                    if appendParsedCSVRow(rows, maybeHeader, headerMap, line, false) then
                        stats.validRows = stats.validRows + 1
                    else
                        stats.skippedRows = stats.skippedRows + 1
                    end
                end
            else
                stats.dataLines = stats.dataLines + 1
                local fields = splitCSVLine(line)
                if appendParsedCSVRow(rows, fields, headerMap, line, true) then
                    stats.validRows = stats.validRows + 1
                else
                    stats.skippedRows = stats.skippedRows + 1
                end
            end
        end

        return rows, stats
    end
    local function validatePlusRows(rows)
        -- Plus System requires exactly 1 reserve entry per player (SoftRes set to 1 SR per player).
        -- If a player appears more than once (even for the same item), it means a multi-reserve CSV was pasted.
        local seen = {}
        for i = 1, #rows do
            local row = rows[i]
            local rec = seen[row.playerKey]
            if not rec then
                seen[row.playerKey] = { itemId = row.itemId, player = row.player, count = 1 }
            else
                rec.count = (rec.count or 1) + 1
                if rec.itemId ~= row.itemId then
                    return false,
                        "CSV_WRONG_FOR_PLUS",
                        {
                            player = row.player,
                            reason = "multi_item",
                            first = rec.itemId,
                            second = row.itemId,
                            count = rec.count,
                        }
                end
                return false,
                    "CSV_WRONG_FOR_PLUS",
                    {
                        player = row.player,
                        reason = "duplicate",
                        itemId = row.itemId,
                        count = rec.count,
                    }
            end
        end
        return true
    end

    local function aggregateRows(rows, allowMulti)
        local newReservesData = {}
        local byItemPerPlayer = {}

        for i = 1, #rows do
            local row = rows[i]
            local pKey = row.playerKey

            local container = newReservesData[pKey]
            if not container then
                container = {
                    playerNameDisplay = row.player,
                    reserves = {},
                }
                newReservesData[pKey] = container
                byItemPerPlayer[pKey] = {}
            end

            local idx = byItemPerPlayer[pKey]
            local entry = idx[row.itemId]
            if entry then
                if allowMulti then
                    entry.quantity = (tonumber(entry.quantity) or 1) + 1
                else
                    entry.quantity = 1
                end
                local p = tonumber(row.plus) or 0
                if p > (tonumber(entry.plus) or 0) then
                    entry.plus = p
                end
            else
                entry = {
                    rawID = row.itemId,
                    itemLink = nil,
                    itemName = nil,
                    itemIcon = nil,
                    quantity = 1,
                    class = row.class,
                    spec = row.spec,
                    note = row.note,
                    plus = tonumber(row.plus) or 0,
                    source = row.source,
                }
                idx[row.itemId] = entry
                container.reserves[#container.reserves + 1] = entry
            end
        end

        return newReservesData
    end

    importStrategies.multi = {
        id = "multi",
        Validate = function(rows)
            return true
        end,
        Aggregate = function(rows)
            return aggregateRows(rows, true)
        end,
    }

    importStrategies.plus = {
        id = "plus",
        Validate = validatePlusRows,
        Aggregate = function(rows)
            return aggregateRows(rows, false)
        end,
    }

    function Service:GetImportStrategy(mode)
        mode = (mode == "plus" or mode == "multi") and mode or self:GetImportMode()
        return importStrategies[mode] or importStrategies.multi
    end

    function Service:ParseImport(text, mode, opts)
        if type(text) ~= "string" or not text:match("%S") then
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return nil, "EMPTY"
        end

        local resolvedMode = (mode == "plus" or mode == "multi") and mode or self:GetImportMode()
        local strategy = self:GetImportStrategy(resolvedMode)

        addon:debug(Diag.D.LogReservesParseStart)

        local rows, importStats = parseCSVRows(text)
        if not rows or #rows == 0 then
            addon:warn(L.WarnNoValidRows)
            return nil, "NO_ROWS"
        end

        importStats = importStats or {}
        addon:debug(
            Diag.D.LogReservesImportRows:format(
                tonumber(importStats.validRows) or #rows,
                tonumber(importStats.skippedRows) or 0,
                tostring(importStats.headerDetected),
                tonumber(importStats.dataLines) or 0
            )
        )
        if importStats.headerDetected ~= true and (tonumber(importStats.skippedRows) or 0) > 0 then
            addon:warn(L.WarnReservesHeaderHint)
        end

        local ok, errCode, errData = strategy.Validate(rows)
        if not ok then
            addon:debug(
                Diag.D.LogReservesImportWrongModePlus and Diag.D.LogReservesImportWrongModePlus:format(tostring(errData and errData.player))
                    or ("Wrong CSV for Plus System: " .. tostring(errData and errData.player))
            )
            return nil, errCode or "CSV_INVALID", errData
        end

        local newReservesData = strategy.Aggregate(rows)
        local parsed = {
            mode = resolvedMode,
            reservesData = newReservesData,
            nPlayers = addon.tLength(newReservesData),
            opts = opts,
            importStats = importStats,
        }
        return parsed
    end

    function Service:ApplyImport(parsed, raidId, opts)
        if type(parsed) ~= "table" or type(parsed.reservesData) ~= "table" then
            return false, "INVALID_PARSED"
        end

        clearDisplayRefreshQueue()
        local mode = (parsed.mode == "plus" or parsed.mode == "multi") and parsed.mode or self:GetImportMode()
        reservesData = parsed.reservesData
        setImportMode(mode, true)
        self:Save()

        local nPlayers = tonumber(parsed.nPlayers) or addon.tLength(reservesData)
        addon:debug(Diag.D.LogReservesParseComplete:format(nPlayers))
        if not (opts and opts.silentInfo) then
            addon:info(format(L.SuccessReservesParsed, tostring(nPlayers)))
            local stats = parsed.importStats or {}
            addon:info(L.MsgReservesImportRows:format(tonumber(stats.validRows) or 0, tonumber(stats.skippedRows) or 0))
        end

        local reason = (opts and opts.reason) or "import"
        Bus.TriggerEvent(InternalEvents.ReservesDataChanged, reason, raidId, mode, nPlayers)
        return true, nPlayers
    end

    function Service:ParseCSV(csv, mode)
        local parsed, errCode, errData = self:ParseImport(csv, mode)
        if not parsed then
            return false, 0, errCode, errData
        end

        local ok, nPlayersOrErr, applyErrData = self:ApplyImport(parsed, nil, { reason = "import" })
        if not ok then
            return false, 0, nPlayersOrErr, applyErrData
        end

        return true, nPlayersOrErr
    end

    -- ----- Item Info Querying ----- --
    function Service:QueryItemInfo(itemId)
        if not itemId then
            return
        end
        addon:debug(Diag.D.LogReservesQueryItemInfo:format(itemId))
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
            self:UpdateReserveItemData(itemId, name, link, icon)
        end
        markPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if hasName and hasIcon then
            addon:debug(Diag.D.LogReservesItemInfoReady:format(itemId, name))
            completePendingItem(itemId)
            return true
        end

        addon:debug(Diag.D.LogReservesItemInfoPendingQuery:format(itemId))
        return false
    end

    -- Query all missing items for reserves
    function Service:QueryMissingItems(silent, primeFn)
        local seen = {}
        local count = 0
        local updated = false
        addon:debug(Diag.D.LogReservesQueryMissingItems)
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
        addon:debug(Diag.D.LogReservesMissingItems:format(count))
        addon:debug(Diag.D.LogSRQueryMissingItems:format(tostring(updated), count))
        return updated, count
    end

    -- Update reserve item data
    function Service:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        if not itemId then
            return
        end
        local icon = itemIcon
        if (type(icon) ~= "string" or icon == "") and itemName then
            icon = fallbackIcon
        end
        reservesDirty = true

        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                if type(r) == "table" and r.rawID == itemId then
                    r.itemName = itemName
                    r.itemLink = itemLink
                    r.itemIcon = icon
                end
            end
        else
            -- Fallback: scan all players (should be rare if index is up to date)
            for _, player in pairs(reservesData) do
                if type(player) == "table" and type(player.reserves) == "table" then
                    for i = 1, #player.reserves do
                        local r = player.reserves[i]
                        if type(r) == "table" and r.rawID == itemId then
                            r.itemName = itemName
                            r.itemLink = itemLink
                            r.itemIcon = icon
                        end
                    end
                end
            end
        end

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
        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                local qty = (type(r) == "table" and tonumber(r.quantity)) or 1
                if (qty or 1) > 1 then
                    return true
                end
            end
            return false
        end

        -- Fallback: scan all players (should be rare if index is up to date)
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID == itemId then
                        local qty = tonumber(r.quantity) or 1
                        if qty > 1 then
                            return true
                        end
                    end
                end
            end
        end
        return false
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
    function Service:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        if not itemId then
            return {}
        end
        local list = reservesByItemID[itemId]
        if type(list) ~= "table" then
            return {}
        end

        -- Aggregate per player so we can apply sorting and reuse meta (class/plus).
        local data = { players = {}, playerCounts = {}, playerMeta = {} }
        for i = 1, #list do
            local r = list[i]
            if type(r) == "table" then
                addReservePlayer(data, r)
            end
        end

        local tokens = buildPlayerTokens(itemId, data.players, data.playerCounts, data.playerMeta, useColor, showPlus, showMulti)
        local out = {}
        for i = 1, #tokens do
            out[i] = tokens[i]
        end
        return out
    end

    -- Returns the formatted player list for an item (comma-separated).
    -- useColor, showPlus, and showMulti follow the same rules as GetPlayersForItem.
    function Service:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti)
        addon:debug(Diag.D.LogReservesFormatPlayers:format(itemId))
        local list = self:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        -- Log the list of players found for the item
        addon:debug(Diag.D.LogReservesPlayersList:format(itemId, tconcat(list, ", ")))
        return #list > 0 and tconcat(list, ", ") or ""
    end

    function Service:GetDisplayList()
        if reservesDirty then
            table.sort(reservesDisplayList, function(a, b)
                if a.source ~= b.source then
                    return a.source < b.source
                end
                if a.itemId ~= b.itemId then
                    return a.itemId < b.itemId
                end
                return false
            end)
            reservesDirty = false
        end
        return reservesDisplayList
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
        addon:debug(Diag.D.LogReservesToggleCollapse:format(source, tostring(nextState)))
        return nextState
    end

    function Service:HasPendingItem(itemId)
        if not itemId then
            return false
        end
        return pendingItemInfo[itemId] ~= nil
    end

    function module:Save(contextTag)
        return Service:Save(contextTag)
    end

    function module:Load()
        return Service:Load()
    end

    function module:ResetSaved()
        return Service:ResetSaved()
    end

    function module:HasData()
        return Service:HasData()
    end

    function module:HasItemReserves(itemId)
        return Service:HasItemReserves(itemId)
    end

    function module:GetReserve(playerName)
        return Service:GetReserve(playerName)
    end

    function module:FormatReserveItemIdLabel(itemId)
        return Service:FormatReserveItemIdLabel(itemId)
    end

    function module:FormatReserveDroppedBy(source)
        return Service:FormatReserveDroppedBy(source)
    end

    function module:FormatReserveItemFallback(itemId)
        return Service:FormatReserveItemFallback(itemId)
    end

    function module:GetAllReserves()
        return Service:GetAllReserves()
    end

    function module:GetImportMode()
        return Service:GetImportMode()
    end

    function module:SetImportMode(mode, syncOptions)
        return Service:SetImportMode(mode, syncOptions)
    end

    function module:IsPlusSystem()
        return Service:IsPlusSystem()
    end

    function module:IsMultiReserve()
        return Service:IsMultiReserve()
    end

    function module:GetImportStrategy(mode)
        return Service:GetImportStrategy(mode)
    end

    function module:ParseImport(text, mode, opts)
        return Service:ParseImport(text, mode, opts)
    end

    function module:ApplyImport(parsed, raidId, opts)
        return Service:ApplyImport(parsed, raidId, opts)
    end

    function module:ParseCSV(csv, mode)
        return Service:ParseCSV(csv, mode)
    end

    function module:QueryItemInfo(itemId)
        return Service:QueryItemInfo(itemId)
    end

    function module:QueryMissingItems(silent)
        return Service:QueryMissingItems(silent)
    end

    function module:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        return Service:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
    end

    function module:GetReserveCountForItem(itemId, playerName)
        return Service:GetReserveCountForItem(itemId, playerName)
    end

    function module:GetReserveEntryForItem(itemId, playerName)
        return Service:GetReserveEntryForItem(itemId, playerName)
    end

    function module:GetPlusForItem(itemId, playerName)
        return Service:GetPlusForItem(itemId, playerName)
    end

    function module:HasMultiReserveForItem(itemId)
        return Service:HasMultiReserveForItem(itemId)
    end

    function module:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        return Service:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
    end

    function module:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti)
        return Service:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti)
    end
end
