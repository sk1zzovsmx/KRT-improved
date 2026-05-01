-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: reserves display/grouping helpers
-- exports: addon.Services.Reserves._Display

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local C = feature.C
local Strings = feature.Strings

local format = string.format
local sort = table.sort
local tconcat, twipe = table.concat, table.wipe
local pairs, tostring, tonumber, type = pairs, tostring, tonumber, type

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Reserves")
local module = addon.Services.Reserves
module._Display = module._Display or {}

local Display = module._Display

local RESERVE_ROW_MAX_PLAYERS_INLINE = 6
local playerTextTemp = {}

-- ----- Private helpers ----- --
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

local function colorizeReserveName(ctx, itemId, playerName, className)
    if not playerName then
        return playerName
    end

    local classToken = className
    if (not classToken or classToken == "") and itemId then
        local reserveEntry = ctx.getReserveEntryForItem(itemId, playerName)
        classToken = reserveEntry and reserveEntry.class
    end

    local raidService = ctx.getRaidService()
    if (not classToken or classToken == "") and raidService and raidService.GetPlayerClass then
        classToken = raidService:GetPlayerClass(playerName)
    end

    if not classToken or classToken == "" then
        return playerName
    end

    local _, colorStr = getClassColorStr(classToken)
    if colorStr and colorStr ~= "ffffffff" then
        return "|c" .. colorStr .. playerName .. "|r"
    end
    return playerName
end

local function addReservePlayer(data, reserveEntry, countOverride, fallbackName)
    if not data.players then
        data.players = {}
    end
    if not data.playerCounts then
        data.playerCounts = {}
    end
    if not data.playerMeta then
        data.playerMeta = {}
    end

    local name
    local count
    local className
    local plus

    if type(reserveEntry) == "table" then
        name = reserveEntry.playerNameDisplay or fallbackName or "?"
        count = tonumber(reserveEntry.quantity) or 1
        className = reserveEntry.class
        plus = tonumber(reserveEntry.plus) or 0
    else
        name = reserveEntry or "?"
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
    if className and className ~= "" and (not meta.class or meta.class == "") then
        meta.class = className
    end
    if plus and plus > (meta.plus or 0) then
        meta.plus = plus
    end
end

local function getMetaForPlayer(ctx, metaByName, itemId, playerName)
    local meta = metaByName and metaByName[playerName]
    if meta and (meta.class or meta.plus) then
        return meta
    end

    if not meta then
        meta = { plus = 0, class = nil }
    end
    if itemId and playerName then
        local reserveEntry = ctx.getReserveEntryForItem(itemId, playerName)
        if reserveEntry then
            if reserveEntry.class and reserveEntry.class ~= "" and (not meta.class or meta.class == "") then
                meta.class = reserveEntry.class
            end
            local plus = tonumber(reserveEntry.plus) or 0
            if plus > (meta.plus or 0) then
                meta.plus = plus
            end
        end

        local raidService = ctx.getRaidService()
        if (not meta.class or meta.class == "") and raidService and raidService.GetPlayerClass then
            meta.class = raidService:GetPlayerClass(playerName)
        end
    end
    return meta
end

local function formatReservePlayerName(ctx, itemId, name, count, metaByName, useColor, showPlus, showMulti)
    local meta = getMetaForPlayer(ctx, metaByName, itemId, name)
    local out

    if useColor == false then
        out = name
    else
        out = colorizeReserveName(ctx, itemId, name, meta and meta.class)
    end

    if showMulti ~= false and ctx.isMultiReserve() and count and count > 1 then
        out = out .. format(L.StrReserveCountSuffix, count)
    end

    if showPlus ~= false and ctx.isPlusSystem() and itemId then
        local plus = (meta and tonumber(meta.plus)) or ctx.getPlusForItem(itemId, name) or 0
        if plus and plus > 0 then
            out = out .. format(" (P+%d)", plus)
        end
    end

    return out
end

local function sortPlayersForDisplay(ctx, itemId, players, counts, metaByName)
    if not players then
        return
    end

    if ctx.isPlusSystem() and itemId then
        sort(players, function(a, b)
            local aMeta = getMetaForPlayer(ctx, metaByName, itemId, a)
            local bMeta = getMetaForPlayer(ctx, metaByName, itemId, b)
            local aPlus = (aMeta and tonumber(aMeta.plus)) or 0
            local bPlus = (bMeta and tonumber(bMeta.plus)) or 0
            if aPlus ~= bPlus then
                return aPlus > bPlus
            end
            return tostring(a) < tostring(b)
        end)
    elseif ctx.isMultiReserve() and counts then
        sort(players, function(a, b)
            local aQuantity = counts[a] or 1
            local bQuantity = counts[b] or 1
            if aQuantity ~= bQuantity then
                return aQuantity > bQuantity
            end
            return tostring(a) < tostring(b)
        end)
    end
end

local function buildPlayerTokens(ctx, itemId, players, counts, metaByName, useColor, showPlus, showMulti)
    if not players then
        return {}
    end

    sortPlayersForDisplay(ctx, itemId, players, counts, metaByName)
    twipe(playerTextTemp)
    for i = 1, #players do
        local name = players[i]
        playerTextTemp[#playerTextTemp + 1] = formatReservePlayerName(ctx, itemId, name, counts and counts[name] or 1, metaByName, useColor, showPlus, showMulti)
    end
    return playerTextTemp
end

local function formatReservePlayerNameBase(ctx, itemId, name, metaByName)
    local meta = getMetaForPlayer(ctx, metaByName, itemId, name)
    return colorizeReserveName(ctx, itemId, name, meta and meta.class)
end

local function buildPlayersTooltipLines(ctx, itemId, players, counts, metaByName, shownCount, hiddenCount)
    local lines = {}
    local total = players and #players or 0

    lines[#lines + 1] = format(L.StrReservesTooltipTotal, total)
    if hiddenCount and hiddenCount > 0 and shownCount and shownCount > 0 then
        lines[#lines + 1] = format(L.StrReservesTooltipShownHidden, shownCount, hiddenCount)
    end

    if not players or total == 0 then
        return lines
    end

    if ctx.isPlusSystem() and itemId then
        local groups = {}
        local keys = {}
        for i = 1, #players do
            local name = players[i]
            local meta = getMetaForPlayer(ctx, metaByName, itemId, name)
            local plus = (meta and tonumber(meta.plus)) or 0
            if groups[plus] == nil then
                groups[plus] = {}
                keys[#keys + 1] = plus
            end
            groups[plus][#groups[plus] + 1] = formatReservePlayerNameBase(ctx, itemId, name, metaByName)
        end
        sort(keys, function(a, b)
            return a > b
        end)
        for i = 1, #keys do
            local plus = keys[i]
            lines[#lines + 1] = format(L.StrReservesTooltipPlus, plus, tconcat(groups[plus], ", "))
        end
    elseif ctx.isMultiReserve() and counts then
        local groups = {}
        local keys = {}
        for i = 1, #players do
            local name = players[i]
            local quantity = counts[name] or 1
            if groups[quantity] == nil then
                groups[quantity] = {}
                keys[#keys + 1] = quantity
            end
            groups[quantity][#groups[quantity] + 1] = formatReservePlayerNameBase(ctx, itemId, name, metaByName)
        end
        sort(keys, function(a, b)
            return a > b
        end)
        for i = 1, #keys do
            local quantity = keys[i]
            lines[#lines + 1] = format(L.StrReservesTooltipQuantity, quantity, tconcat(groups[quantity], ", "))
        end
    else
        local names = {}
        for i = 1, #players do
            names[i] = formatReservePlayerNameBase(ctx, itemId, players[i], metaByName)
        end
        lines[#lines + 1] = tconcat(names, ", ")
    end

    return lines
end

local function buildPlayersText(ctx, itemId, players, counts, metaByName)
    if not players then
        return "", {}, ""
    end

    buildPlayerTokens(ctx, itemId, players, counts, metaByName)
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
    local tooltipLines = buildPlayersTooltipLines(ctx, itemId, players, counts, metaByName, shown, hidden)
    return shortText, tooltipLines, fullText
end

local function getReserveSource(source)
    if source and source ~= "" then
        return source
    end
    return L.StrUnknown
end

local function filterPlayersByCurrentRaid(ctx, players, raidNum)
    local raidService = ctx.getRaidService()
    if not (raidService and raidService.GetPlayerID) then
        return players, false
    end

    local targetRaidNum = raidNum
    if not targetRaidNum then
        targetRaidNum = ctx.getCurrentRaid()
    end
    if not targetRaidNum then
        return players, false
    end

    local filteredPlayers = {}
    for i = 1, #players do
        local name = players[i]
        if type(name) == "string" and name ~= "" then
            local playerNid = raidService:GetPlayerID(name, targetRaidNum)
            if tonumber(playerNid) and playerNid > 0 then
                filteredPlayers[#filteredPlayers + 1] = name
            end
        end
    end

    return filteredPlayers, true
end

local function hasCurrentRaidPlayer(ctx, list, raidNum)
    local raidService = ctx.getRaidService()
    if not (raidService and raidService.GetPlayerID) then
        return true, false
    end

    local targetRaidNum = raidNum
    if not targetRaidNum then
        targetRaidNum = ctx.getCurrentRaid()
    end
    if not targetRaidNum then
        return true, false
    end

    for i = 1, #list do
        local reserveEntry = list[i]
        local name = reserveEntry and reserveEntry.playerNameDisplay
        if type(name) == "string" and name ~= "" then
            local playerNid = raidService:GetPlayerID(name, targetRaidNum)
            if tonumber(playerNid) and playerNid > 0 then
                return true, true
            end
        end
    end

    return false, true
end

-- ----- Public methods ----- --
function Display.FormatReserveItemIdLabel(itemId)
    return format(L.StrReservesItemIdLabel, tostring(itemId or "?"))
end

function Display.FormatReserveDroppedBy(source)
    if not source or source == "" then
        return nil
    end
    return format(L.StrReservesTooltipDroppedBy, source)
end

function Display.FormatReserveItemFallback(itemId)
    return format(L.StrReservesItemFallback, tostring(itemId or "?"))
end

function Display.RebuildIndex(ctx)
    twipe(ctx.reservesByItemID)
    twipe(ctx.reservesByItemPlayer)
    twipe(ctx.playerItemsByName)
    ctx.setDirty(true)

    for playerKey, player in pairs(ctx.reservesData) do
        if type(player) == "table" and type(player.reserves) == "table" then
            local playerName = ctx.resolvePlayerNameDisplay(playerKey, player)
            player.playerNameDisplay = playerName
            player.original = nil

            local normalizedPlayer = Strings.NormalizeLower(playerName, true) or playerKey
            if type(normalizedPlayer) ~= "string" then
                normalizedPlayer = tostring(playerKey or "")
            end
            if normalizedPlayer == "" then
                normalizedPlayer = "?"
            end

            ctx.playerItemsByName[normalizedPlayer] = ctx.playerItemsByName[normalizedPlayer] or {}

            for i = 1, #player.reserves do
                local reserveEntry = player.reserves[i]
                if type(reserveEntry) == "table" and reserveEntry.rawID then
                    reserveEntry.player = nil
                    reserveEntry.playerNameDisplay = playerName

                    local itemId = reserveEntry.rawID
                    local list = ctx.reservesByItemID[itemId]
                    if not list then
                        list = {}
                        ctx.reservesByItemID[itemId] = list
                    end
                    list[#list + 1] = reserveEntry

                    local byPlayer = ctx.reservesByItemPlayer[itemId]
                    if not byPlayer then
                        byPlayer = {}
                        ctx.reservesByItemPlayer[itemId] = byPlayer
                    end
                    byPlayer[normalizedPlayer] = reserveEntry
                    ctx.playerItemsByName[normalizedPlayer][itemId] = true
                end
            end
        end
    end

    twipe(ctx.reservesDisplayList)
    twipe(ctx.grouped)
    for itemId, list in pairs(ctx.reservesByItemID) do
        if type(list) == "table" then
            for i = 1, #list do
                local reserveEntry = list[i]
                if type(reserveEntry) == "table" then
                    local source = getReserveSource(reserveEntry.source)
                    local bySource = ctx.grouped[source]

                    if not bySource then
                        bySource = {}
                        ctx.grouped[source] = bySource
                        if ctx.collapsedBossGroups[source] == nil then
                            ctx.collapsedBossGroups[source] = false
                        end
                    end

                    local data = bySource[itemId]
                    if not data then
                        data = {
                            itemId = itemId,
                            itemLink = reserveEntry.itemLink,
                            itemName = reserveEntry.itemName,
                            itemIcon = reserveEntry.itemIcon,
                            source = source,
                            players = {},
                            playerCounts = {},
                            playerMeta = {},
                        }
                        bySource[itemId] = data
                    end

                    addReservePlayer(data, reserveEntry)
                end
            end
        end
    end

    for _, byItem in pairs(ctx.grouped) do
        for _, data in pairs(byItem) do
            data.playersText, data.playersTooltipLines, data.playersTextFull = buildPlayersText(ctx, data.itemId, data.players, data.playerCounts, data.playerMeta)
            data.players = nil
            data.playerCounts = nil
            data.playerMeta = nil
            ctx.reservesDisplayList[#ctx.reservesDisplayList + 1] = data
        end
    end
end

function Display.HasCurrentRaidPlayersForItem(ctx, itemId, raidNum)
    if not itemId then
        return false
    end

    local list = ctx.reservesByItemID[itemId]
    if type(list) ~= "table" or #list == 0 then
        return false
    end

    local hasMatch, filterApplied = hasCurrentRaidPlayer(ctx, list, raidNum)
    if not filterApplied then
        return true
    end

    return hasMatch
end

function Display.GetPlayersForItem(ctx, itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
    if not itemId then
        return {}
    end

    local list = ctx.reservesByItemID[itemId]
    if type(list) ~= "table" then
        return {}
    end

    local data = { players = {}, playerCounts = {}, playerMeta = {} }
    for i = 1, #list do
        local reserveEntry = list[i]
        if type(reserveEntry) == "table" then
            addReservePlayer(data, reserveEntry)
        end
    end

    if onlyCurrentRaidPlayers == true then
        local filteredPlayers, filterApplied = filterPlayersByCurrentRaid(ctx, data.players, raidNum)
        if filterApplied then
            data.players = filteredPlayers
        end
    end

    local tokens = buildPlayerTokens(ctx, itemId, data.players, data.playerCounts, data.playerMeta, useColor, showPlus, showMulti)
    local out = {}
    for i = 1, #tokens do
        out[i] = tokens[i]
    end
    return out
end

function Display.GetDisplayList(ctx)
    if ctx.isDirty() then
        sort(ctx.reservesDisplayList, function(a, b)
            if a.source ~= b.source then
                return a.source < b.source
            end
            if a.itemId ~= b.itemId then
                return a.itemId < b.itemId
            end
            return false
        end)
        ctx.setDirty(false)
    end
    return ctx.reservesDisplayList
end
