--[[
    Services/Reserves.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local C = feature.C

local tconcat, twipe = table.concat, table.wipe
local pairs, ipairs, type, next = pairs, ipairs, type, next
local format = string.format

local tostring, tonumber = tostring, tonumber

-- =========== Reserves Module  =========== --
-- Manages item reserves, import, and display.
do
    addon.Reserves = addon.Reserves or {}
    local module = addon.Reserves
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
    local collapsedBossGroups = {}
    local grouped = {}

    -- ----- Private helpers ----- --

    local playerTextTemp = {}

    local function NormalizeImportMode(mode)
        return (mode == "plus") and "plus" or "multi"
    end

    local function ImportModeToOptionValue(mode)
        return (NormalizeImportMode(mode) == "plus") and 1 or 0
    end

    local function SetImportMode(mode, syncOptions)
        local resolved = NormalizeImportMode(mode)
        importMode = resolved

        if syncOptions ~= false then
            local value = ImportModeToOptionValue(resolved)
            Utils.setOption("srImportMode", value)
        end

        return importMode
    end

    local function MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if not itemId then return nil end
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

    local function GetPendingItemInfo(pending)
        if not pending then return nil end
        return pending.name, pending.link, pending.icon
    end

    local function CompletePendingItem(itemId)
        if not itemId or not pendingItemInfo[itemId] then return end
        pendingItemInfo[itemId] = nil
        if pendingItemCount > 0 then
            pendingItemCount = pendingItemCount - 1
        end
        addon:debug(Diag.D.LogReservesItemReady:format(itemId, pendingItemCount))
        if pendingItemCount == 0 then
            addon:debug(Diag.D.LogReservesPendingComplete)
            Utils.triggerEvent("ReservesDataChanged", "iteminfo", itemId)
        end
    end

    -- SoftRes exports class names like "Warrior", "Death Knight", etc.
    -- Normalize them to WoW class tokens (e.g. "WARRIOR", "DEATHKNIGHT") so we can use C.CLASS_COLORS.
    local function NormalizeClassToken(className)
        if not className then return nil end
        local token = tostring(className):upper()
        token = token:gsub("%s+", ""):gsub("%-", "")
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then return token end
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then return token end
        return nil
    end

    local function GetClassColorStr(className)
        local token = NormalizeClassToken(className) or "UNKNOWN"
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then
            return token, C.CLASS_COLORS[token]
        end
        local _, _, _, colorStr = addon.GetClassColor(token)
        return token, colorStr
    end

    local function ColorizeReserveName(itemId, playerName, className)
        if not playerName then return playerName end

        local cls = className
        if (not cls or cls == "") and itemId then
            local r = Service:GetReserveEntryForItem(itemId, playerName)
            cls = r and r.class
        end
        if (not cls or cls == "") and addon.Raid and addon.Raid.GetPlayerClass then
            cls = addon.Raid:GetPlayerClass(playerName)
        end
        if not cls or cls == "" then return playerName end

        local _, colorStr = GetClassColorStr(cls)
        if colorStr and colorStr ~= "ffffffff" then
            return "|c" .. colorStr .. playerName .. "|r"
        end
        return playerName
    end

    local function AddReservePlayer(data, rOrName, countOverride)
        if not data.players then data.players = {} end
        if not data.playerCounts then data.playerCounts = {} end
        if not data.playerMeta then data.playerMeta = {} end

        local name, count, cls, plus
        if type(rOrName) == "table" then
            name = rOrName.player or "?"
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

    local function GetMetaForPlayer(metaByName, itemId, playerName)
        local meta = metaByName and metaByName[playerName]
        if meta and (meta.class or meta.plus) then return meta end

        -- Fallback: resolve from index (keeps compatibility even if meta isn't passed).
        if not meta then meta = { plus = 0, class = nil } end
        if itemId and playerName then
            local r = Service:GetReserveEntryForItem(itemId, playerName)
            if r then
                if r.class and r.class ~= "" and (not meta.class or meta.class == "") then
                    meta.class = r.class
                end
                local p = tonumber(r.plus) or 0
                if p > (meta.plus or 0) then meta.plus = p end
            end
            if (not meta.class or meta.class == "") and addon.Raid and addon.Raid.GetPlayerClass then
                meta.class = addon.Raid:GetPlayerClass(playerName)
            end
        end
        return meta
    end

    -- Formats a single player token for display.
    -- useColor:
    --   true/nil -> UI rendering (class colors enabled)
    --   false    -> chat-safe rendering (no class color codes)
    local function FormatReservePlayerName(itemId, name, count, metaByName, useColor, showPlus, showMulti)
        local meta = GetMetaForPlayer(metaByName, itemId, name)
        local out
        if useColor == false then
            out = name
        else
            out = ColorizeReserveName(itemId, name, meta and meta.class)
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

    local function SortPlayersForDisplay(itemId, players, counts, metaByName)
        if not players then return end

        if Service:IsPlusSystem() and itemId then
            table.sort(players, function(a, b)
                local am = GetMetaForPlayer(metaByName, itemId, a)
                local bm = GetMetaForPlayer(metaByName, itemId, b)
                local ap = (am and tonumber(am.plus)) or 0
                local bp = (bm and tonumber(bm.plus)) or 0
                if ap ~= bp then return ap > bp end
                return tostring(a) < tostring(b)
            end)
        elseif Service:IsMultiReserve() and counts then
            -- Optional: show higher quantities first for readability.
            table.sort(players, function(a, b)
                local aq = counts[a] or 1
                local bq = counts[b] or 1
                if aq ~= bq then return aq > bq end
                return tostring(a) < tostring(b)
            end)
        end
    end

    local function BuildPlayerTokens(itemId, players, counts, metaByName, useColor, showPlus, showMulti)
        if not players then return {} end
        SortPlayersForDisplay(itemId, players, counts, metaByName)
        twipe(playerTextTemp)
        for i = 1, #players do
            local name = players[i]
            playerTextTemp[#playerTextTemp + 1] =
                FormatReservePlayerName(
                    itemId,
                    name,
                    counts and counts[name] or 1,
                    metaByName,
                    useColor,
                    showPlus,
                    showMulti
                )
        end
        return playerTextTemp
    end

    -- How many player tokens we show inline in the Reserve List row before truncating.
    -- Long lists are rendered in a dedicated tooltip on the players line.
    local RESERVE_ROW_MAX_PLAYERS_INLINE = 6

    local function FormatReservePlayerNameBase(itemId, name, metaByName)
        local meta = GetMetaForPlayer(metaByName, itemId, name)
        return ColorizeReserveName(itemId, name, meta and meta.class)
    end

    local function BuildPlayersTooltipLines(itemId, players, counts, metaByName, shownCount, hiddenCount)
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
                local meta = GetMetaForPlayer(metaByName, itemId, name)
                local p = (meta and tonumber(meta.plus)) or 0
                if groups[p] == nil then
                    groups[p] = {}
                    keys[#keys + 1] = p
                end
                groups[p][#groups[p] + 1] = FormatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b) return a > b end)
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
                groups[q][#groups[q] + 1] = FormatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b) return a > b end)
            for i = 1, #keys do
                local q = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipQuantity, q, tconcat(groups[q], ", "))
            end
        else
            -- Fallback: just list names
            local names = {}
            for i = 1, #players do
                names[i] = FormatReservePlayerNameBase(itemId, players[i], metaByName)
            end
            lines[#lines + 1] = tconcat(names, ", ")
        end

        return lines
    end

    local function BuildPlayersText(itemId, players, counts, metaByName)
        if not players then return "", {}, "" end
        BuildPlayerTokens(itemId, players, counts, metaByName)
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
        local tooltipLines = BuildPlayersTooltipLines(itemId, players, counts, metaByName, shown, hidden)
        return shortText, tooltipLines, fullText
    end

    local function GetReserveSource(source)
        if source and source ~= "" then
            return source
        end
        return L.StrUnknown
    end

    local function FormatReserveItemIdLabel(itemId)
        return format(L.StrReservesItemIdLabel, tostring(itemId or "?"))
    end

    -- Kept for potential future tooltip/source variants.
    local function FormatReserveDroppedBy(source)
        if not source or source == "" then return nil end
        return format(L.StrReservesTooltipDroppedBy, source)
    end

    local function FormatReserveItemFallback(itemId)
        return format(L.StrReservesItemFallback, tostring(itemId or "?"))
    end

    local function UpdateDisplayEntryForItem(itemId)
        if not itemId then return end
        reservesDirty = true

        local groupedBySource = {}
        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                if type(r) == "table" then
                    local source = GetReserveSource(r.source)
                    local bySource = groupedBySource[source]
                    if not bySource then
                        bySource = {}
                        groupedBySource[source] = bySource
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
                    AddReservePlayer(data, r)
                end
            end
        end

        local existing = {}
        local remaining = {}
        for i = 1, #reservesDisplayList do
            local data = reservesDisplayList[i]
            if data and data.itemId == itemId then
                existing[#existing + 1] = data
            else
                remaining[#remaining + 1] = data
            end
        end

        local reused = 0
        for source, byQty in pairs(groupedBySource) do
            for _, data in pairs(byQty) do
                reused = reused + 1
                local target = existing[reused]
                if target then
                    target.itemId = itemId
                    target.itemLink = data.itemLink
                    target.itemName = data.itemName
                    target.itemIcon = data.itemIcon
                    target.source = source
                    target.players = target.players or {}
                    target.playerCounts = target.playerCounts or {}
                    target.playerMeta = target.playerMeta or {}
                    twipe(target.players)
                    twipe(target.playerCounts)
                    twipe(target.playerMeta)
                    for i = 1, #data.players do
                        local name = data.players[i]
                        target.players[i] = name
                        target.playerCounts[name] = data.playerCounts[name]
                    end
                    if data.playerMeta then
                        for n, m in pairs(data.playerMeta) do
                            local tm = target.playerMeta[n]
                            if not tm then
                                tm = {}; target.playerMeta[n] = tm
                            end
                            tm.plus = (m and tonumber(m.plus)) or 0
                            tm.class = m and m.class or tm.class
                        end
                    end
                    target.playersText, target.playersTooltipLines, target.playersTextFull =
                        BuildPlayersText(
                            itemId,
                            target.players,
                            target.playerCounts,
                            target.playerMeta
                        )
                    target.players = nil
                    target.playerCounts = nil
                    target.playerMeta = nil
                    remaining[#remaining + 1] = target
                else
                    data.playersText, data.playersTooltipLines, data.playersTextFull =
                        BuildPlayersText(
                            data.itemId,
                            data.players,
                            data.playerCounts,
                            data.playerMeta
                        )
                    data.players = nil
                    data.playerCounts = nil
                    data.playerMeta = nil
                    remaining[#remaining + 1] = data
                end
            end
        end

        twipe(reservesDisplayList)
        for i = 1, #remaining do
            reservesDisplayList[i] = remaining[i]
        end
    end

    local function RebuildIndex()
        twipe(reservesByItemID)
        twipe(reservesByItemPlayer)
        twipe(playerItemsByName)
        reservesDirty = true

        -- Build fast lookup indices
        for playerKey, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                local playerName = player.original or "?"
                local normalizedPlayer = Utils.normalizeLower(playerName, true) or playerKey
                playerItemsByName[normalizedPlayer] = playerItemsByName[normalizedPlayer] or {}

                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID then
                        r.player = r.player or playerName
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
                        local source = GetReserveSource(r.source)

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

                        AddReservePlayer(data, r)
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, data in pairs(byItem) do
                data.playersText, data.playersTooltipLines, data.playersTextFull =
                    BuildPlayersText(
                        data.itemId,
                        data.players,
                        data.playerCounts,
                        data.playerMeta
                    )
                data.players = nil
                data.playerCounts = nil
                data.playerMeta = nil
                reservesDisplayList[#reservesDisplayList + 1] = data
            end
        end
    end

    -- ----- Saved Data Management ----- --

    function Service:Save()
        RebuildIndex()
        addon:debug(Diag.D.LogReservesSaveEntries:format(addon.tLength(reservesData)))
        local saved = {}
        addon.tCopy(saved, reservesData)
        KRT_Reserves = saved
    end

    function Service:Load()
        addon:debug(Diag.D.LogReservesLoadData:format(tostring(KRT_Reserves ~= nil)))
        twipe(reservesData)
        if KRT_Reserves then
            addon.tCopy(reservesData, KRT_Reserves)
        end

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
            if inferred == "multi" then break end
        end
        if not inferred then
            local v = addon.options and addon.options.srImportMode
            inferred = (v == 1) and "plus" or "multi"
        end
        SetImportMode(inferred, true)

        RebuildIndex()
    end

    function Service:ResetSaved()
        addon:debug(Diag.D.LogReservesResetSaved)
        KRT_Reserves = nil
        twipe(reservesData)
        RebuildIndex()
        Utils.triggerEvent("ReservesDataChanged", "clear")
        local clearMessage = L[reserveListClearedKey]
        if clearMessage then
            addon:info(clearMessage)
        end
    end

    function Service:HasData()
        return next(reservesData) ~= nil
    end

    function Service:HasItemReserves(itemId)
        if not itemId then return false end
        local list = reservesByItemID[itemId]
        return type(list) == "table" and #list > 0
    end

    -- ----- Reserve Data Handling ----- --

    function Service:GetReserve(playerName)
        if type(playerName) ~= "string" then return nil end
        local player = Utils.normalizeLower(playerName)
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
            SetImportMode((v == 1) and "plus" or "multi", false)
        end
        return importMode
    end

    function Service:SetImportMode(mode, syncOptions)
        return SetImportMode(mode, syncOptions)
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
        if not field then return nil end
        return Utils.trimText(field:gsub('^"(.-)"$', '%1'), true)
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
            elseif ch == ',' and not inQuotes then
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
                map[Utils.normalizeLower(key)] = i
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

    local function parseCSVRows(csv)
        local rows = {}
        local headerMap = nil
        local firstLine = true

        for line in csv:gmatch("[^\n]+") do
            line = line:gsub("\r$", "")
            if firstLine then
                firstLine = false
                local maybeHeader = splitCSVLine(line)
                local map, isHeader = buildHeaderMap(maybeHeader)
                if isHeader then
                    headerMap = map
                else
                    -- No header detected: treat first line as data
                    local fields     = maybeHeader

                    local itemIdStr  = cleanCSVField(getField(fields, headerMap, "itemid", 2))
                    local source     = cleanCSVField(getField(fields, headerMap, "from", 3))
                    local playerName = cleanCSVField(getField(fields, headerMap, "name", 4))
                    local class      = cleanCSVField(getField(fields, headerMap, "class", 5))
                    local spec       = cleanCSVField(getField(fields, headerMap, "spec", 6))
                    local note       = cleanCSVField(getField(fields, headerMap, "note", 7))
                    local plus       = cleanCSVField(getField(fields, headerMap, "plus", 8))

                    local itemId     = tonumber(itemIdStr)
                    local playerKey  = Utils.normalizeLower(playerName, true)
                    if itemId and playerKey then
                        rows[#rows + 1] = {
                            itemId = itemId,
                            player = playerName,
                            playerKey = playerKey,
                            source = source ~= "" and source or nil,
                            class = class ~= "" and class or nil,
                            spec = spec ~= "" and spec or nil,
                            note = note ~= "" and note or nil,
                            plus = tonumber(plus) or 0,
                        }
                    end
                end
            else
                local fields     = splitCSVLine(line)

                local itemIdStr  = cleanCSVField(getField(fields, headerMap, "itemid", 2))
                local source     = cleanCSVField(getField(fields, headerMap, "from", 3))
                local playerName = cleanCSVField(getField(fields, headerMap, "name", 4))
                local class      = cleanCSVField(getField(fields, headerMap, "class", 5))
                local spec       = cleanCSVField(getField(fields, headerMap, "spec", 6))
                local note       = cleanCSVField(getField(fields, headerMap, "note", 7))
                local plus       = cleanCSVField(getField(fields, headerMap, "plus", 8))

                local itemId     = tonumber(itemIdStr)
                local playerKey  = Utils.normalizeLower(playerName, true)

                if itemId and playerKey then
                    rows[#rows + 1] = {
                        itemId = itemId,
                        player = playerName,
                        playerKey = playerKey,
                        source = source ~= "" and source or nil,
                        class = class ~= "" and class or nil,
                        spec = spec ~= "" and spec or nil,
                        note = note ~= "" and note or nil,
                        plus = tonumber(plus) or 0,
                    }
                else
                    addon:debug(Diag.D.LogSRParseSkippedLine:format(tostring(line)))
                end
            end
        end

        return rows
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
                    return false, "CSV_WRONG_FOR_PLUS", {
                        player = row.player,
                        reason = "multi_item",
                        first = rec.itemId,
                        second = row.itemId,
                        count = rec.count,
                    }
                end
                return false, "CSV_WRONG_FOR_PLUS", {
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
                container = { original = row.player, reserves = {} }
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
                    player = row.player,
                }
                idx[row.itemId] = entry
                container.reserves[#container.reserves + 1] = entry
            end
        end

        return newReservesData
    end

    importStrategies.multi = {
        id = "multi",
        Validate = function(rows) return true end,
        Aggregate = function(rows) return aggregateRows(rows, true) end,
    }

    importStrategies.plus = {
        id = "plus",
        Validate = validatePlusRows,
        Aggregate = function(rows) return aggregateRows(rows, false) end,
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

        local rows = parseCSVRows(text)
        if not rows or #rows == 0 then
            addon:warn(L.WarnNoValidRows)
            return nil, "NO_ROWS"
        end

        local ok, errCode, errData = strategy.Validate(rows)
        if not ok then
            addon:debug(Diag.D.LogReservesImportWrongModePlus
                and Diag.D.LogReservesImportWrongModePlus:format(tostring(errData and errData.player))
                or ("Wrong CSV for Plus System: " .. tostring(errData and errData.player)))
            return nil, errCode or "CSV_INVALID", errData
        end

        local newReservesData = strategy.Aggregate(rows)
        local parsed = {
            mode = resolvedMode,
            reservesData = newReservesData,
            nPlayers = addon.tLength(newReservesData),
            opts = opts,
        }
        return parsed
    end

    function Service:ApplyImport(parsed, raidId, opts)
        if type(parsed) ~= "table" or type(parsed.reservesData) ~= "table" then
            return false, "INVALID_PARSED"
        end

        local mode = (parsed.mode == "plus" or parsed.mode == "multi") and parsed.mode or self:GetImportMode()
        reservesData = parsed.reservesData
        SetImportMode(mode, true)
        self:Save()

        local nPlayers = tonumber(parsed.nPlayers) or addon.tLength(reservesData)
        addon:debug(Diag.D.LogReservesParseComplete:format(nPlayers))
        if not (opts and opts.silentInfo) then
            addon:info(format(L.SuccessReservesParsed, tostring(nPlayers)))
        end

        local reason = (opts and opts.reason) or "import"
        Utils.triggerEvent("ReservesDataChanged", reason, raidId, mode, nPlayers)
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
        if not itemId then return end
        addon:debug(Diag.D.LogReservesQueryItemInfo:format(itemId))
        local pending = pendingItemInfo[itemId]
        local name, link, icon = GetPendingItemInfo(pending)
        local hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
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

        hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        hasIcon = type(icon) == "string" and icon ~= ""
        if hasName then
            self:UpdateReserveItemData(itemId, name, link, icon)
        end
        MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if hasName and hasIcon then
            addon:debug(Diag.D.LogReservesItemInfoReady:format(itemId, name))
            CompletePendingItem(itemId)
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
        if not itemId then return end
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

        UpdateDisplayEntryForItem(itemId)

        return icon
    end

    -- Get reserve count for a specific item for a player
    function Service:GetReserveCountForItem(itemId, playerName)
        local r = self:GetReserveEntryForItem(itemId, playerName)
        if not r then return 0 end
        return tonumber(r.quantity) or 1
    end

    -- Gets the reserve entry table for a specific item for a player (or nil).
    function Service:GetReserveEntryForItem(itemId, playerName)
        if not itemId or not playerName then return nil end
        local playerKey = Utils.normalizeLower(playerName, true)
        if not playerKey then return nil end

        local byP = reservesByItemPlayer[itemId]
        if type(byP) == "table" then
            local r = byP[playerKey]
            if r then return r end
        end

        -- Fallback (should be rare if indices are up to date)
        local entry = reservesData[playerKey]
        if not entry then return nil end
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
        if self:GetImportMode() ~= "plus" then return 0 end
        local r = self:GetReserveEntryForItem(itemId, playerName)
        return (r and tonumber(r.plus)) or 0
    end

    -- Returns true if the item has any multi-reserve entry (quantity > 1).
    -- When true, SR "Plus priority" should be disabled for this item.
    function Service:HasMultiReserveForItem(itemId)
        if self:GetImportMode() ~= "multi" then return false end
        if not itemId then return false end
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
        if not itemId then return {} end
        local list = reservesByItemID[itemId]
        if type(list) ~= "table" then return {} end

        -- Aggregate per player so we can apply sorting and reuse meta (class/plus).
        local data = { players = {}, playerCounts = {}, playerMeta = {} }
        for i = 1, #list do
            local r = list[i]
            if type(r) == "table" then
                AddReservePlayer(data, r)
            end
        end

        local tokens = BuildPlayerTokens(
            itemId,
            data.players,
            data.playerCounts,
            data.playerMeta,
            useColor,
            showPlus,
            showMulti
        )
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
                if a.source ~= b.source then return a.source < b.source end
                if a.itemId ~= b.itemId then return a.itemId < b.itemId end
                return false
            end)
            reservesDirty = false
        end
        return reservesDisplayList
    end

    function Service:IsSourceCollapsed(source)
        if not source then return false end
        return collapsedBossGroups[source] == true
    end

    function Service:ToggleSourceCollapsed(source)
        if not source then return false end
        local nextState = not (collapsedBossGroups[source] == true)
        collapsedBossGroups[source] = nextState
        addon:debug(Diag.D.LogReservesToggleCollapse:format(source, tostring(nextState)))
        return nextState
    end

    function Service:HasPendingItem(itemId)
        if not itemId then return false end
        return pendingItemInfo[itemId] ~= nil
    end

    local function GetReservesUI()
        return addon.ReservesUI or module.UI
    end

    function module:OnLoad(frame)
        local ui = GetReservesUI()
        if ui and ui.OnLoad then
            return ui:OnLoad(frame)
        end
    end

    function module:Refresh()
        local ui = GetReservesUI()
        if ui and ui.Refresh then
            return ui:Refresh()
        end
    end

    function module:CreateReserveHeader(parent, source, yOffset, index)
        local ui = GetReservesUI()
        if ui and ui.CreateReserveHeader then
            return ui:CreateReserveHeader(parent, source, yOffset, index)
        end
    end

    function module:CreateReserveRow(parent, info, yOffset, index, isFirstInGroup)
        local ui = GetReservesUI()
        if ui and ui.CreateReserveRow then
            return ui:CreateReserveRow(parent, info, yOffset, index, isFirstInGroup)
        end
    end

    function module:Save()
        return Service:Save()
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
        local ui = GetReservesUI()
        local updated, count
        if ui and ui.PrimeItemInfoQuery then
            updated, count = Service:QueryMissingItems(silent, function(itemId)
                ui:PrimeItemInfoQuery(itemId)
            end)
        else
            updated, count = Service:QueryMissingItems(silent)
        end

        if updated and module.RequestRefresh then
            module.RequestRefresh(module)
        end

        return updated, count
    end

    function module:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        local icon = Service:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        if module.RequestRefresh then
            module.RequestRefresh(module)
        end
        return icon
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
