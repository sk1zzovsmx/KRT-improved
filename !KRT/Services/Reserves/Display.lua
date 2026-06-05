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

local function copyPlayers(players)
    local out = {}
    for i = 1, #(players or {}) do
        out[i] = players[i]
    end
    return out
end

local function sortPlayerNames(players)
    sort(players, function(a, b)
        return tostring(a or "") < tostring(b or "")
    end)
    return players
end

local function buildTextForPlayers(ctx, itemId, players, counts, metaByName, showPlus, showMulti)
    local tokens = buildPlayerTokens(ctx, itemId, copyPlayers(players), counts, metaByName, false, showPlus, showMulti)
    local out = {}
    for i = 1, #tokens do
        out[i] = tokens[i]
    end
    return tconcat(out, ", ")
end

local function splitPresentAndMissingPlayers(ctx, players, raidNum)
    local presentPlayers, filterApplied = filterPlayersByCurrentRaid(ctx, players, raidNum)
    if not filterApplied then
        return copyPlayers(players), {}, false
    end

    local presentByName = {}
    for i = 1, #presentPlayers do
        presentByName[presentPlayers[i]] = true
    end

    local missingPlayers = {}
    for i = 1, #players do
        local name = players[i]
        if not presentByName[name] then
            missingPlayers[#missingPlayers + 1] = name
        end
    end

    return presentPlayers, missingPlayers, true
end

local function normalizeNameKey(name)
    local key = Strings and Strings.NormalizeLower and Strings.NormalizeLower(name, true) or nil
    if key and key ~= "" then
        return key
    end
    if type(name) == "string" and name ~= "" then
        return string.lower(name)
    end
    return nil
end

local function levenshteinDistance(left, right)
    left = tostring(left or "")
    right = tostring(right or "")

    local leftLen = string.len(left)
    local rightLen = string.len(right)
    if left == right then
        return 0
    end
    if leftLen == 0 then
        return rightLen
    end
    if rightLen == 0 then
        return leftLen
    end

    local previous = {}
    local current = {}
    for j = 0, rightLen do
        previous[j] = j
    end

    for i = 1, leftLen do
        current[0] = i
        local leftByte = string.byte(left, i)
        for j = 1, rightLen do
            local cost = leftByte == string.byte(right, j) and 0 or 1
            local deletion = previous[j] + 1
            local insertion = current[j - 1] + 1
            local substitution = previous[j - 1] + cost
            current[j] = math.min(deletion, insertion, substitution)
        end
        previous, current = current, previous
    end

    return previous[rightLen] or rightLen
end

local function nameSimilarity(left, right, distance)
    local maxLen = math.max(string.len(tostring(left or "")), string.len(tostring(right or "")))
    if maxLen <= 0 then
        return 1
    end
    local score = 1 - ((tonumber(distance) or maxLen) / maxLen)
    if score < 0 then
        return 0
    end
    return score
end

local function classifyNameMatch(distance, similarity)
    if distance <= 1 and similarity >= 0.75 then
        return "strong"
    end
    if distance <= 2 and similarity >= 0.30 then
        return "weak"
    end
    return nil
end

local function buildNameMatch(reserveName, raidName, distance, similarity, strength)
    return {
        reserveName = reserveName,
        raidName = raidName,
        distance = distance,
        similarity = similarity,
        strength = strength,
    }
end

local function compareNameMatch(a, b)
    if a.reserveName ~= b.reserveName then
        return tostring(a.reserveName) < tostring(b.reserveName)
    end
    if a.distance ~= b.distance then
        return (tonumber(a.distance) or 0) < (tonumber(b.distance) or 0)
    end
    if a.similarity ~= b.similarity then
        return (tonumber(a.similarity) or 0) > (tonumber(b.similarity) or 0)
    end
    return tostring(a.raidName) < tostring(b.raidName)
end

local function getReservePlayerNames(ctx)
    local players = {}
    for playerKey, player in pairs(ctx.reservesData or {}) do
        if type(player) == "table" then
            local displayName = ctx.resolvePlayerNameDisplay(playerKey, player, playerKey)
            if displayName and displayName ~= "" then
                players[#players + 1] = displayName
            end
        end
    end
    return sortPlayerNames(players)
end

local function getRaidPlayerNames(ctx, raidNum)
    local raid = ctx.getRaidService()
    local targetRaidNum = raidNum or ctx.getCurrentRaid()
    local players = {}
    if not (raid and raid.GetPlayers and targetRaidNum) then
        return players, false
    end

    local raidPlayers = raid:GetPlayers(targetRaidNum) or {}
    for i = 1, #raidPlayers do
        local player = raidPlayers[i]
        local name = player and player.name
        if type(name) == "string" and name ~= "" then
            players[#players + 1] = name
        end
    end
    return sortPlayerNames(players), true
end

local function splitExactNameMatches(reservePlayers, raidPlayers)
    local reserveByKey = {}
    local raidByKey = {}
    local reserveMissing = {}
    local raidMissing = {}

    for i = 1, #reservePlayers do
        local name = reservePlayers[i]
        local key = normalizeNameKey(name)
        if key then
            reserveByKey[key] = true
        end
    end
    for i = 1, #raidPlayers do
        local name = raidPlayers[i]
        local key = normalizeNameKey(name)
        if key then
            raidByKey[key] = true
        end
    end

    for i = 1, #reservePlayers do
        local name = reservePlayers[i]
        local key = normalizeNameKey(name)
        if key and not raidByKey[key] then
            reserveMissing[#reserveMissing + 1] = name
        end
    end
    for i = 1, #raidPlayers do
        local name = raidPlayers[i]
        local key = normalizeNameKey(name)
        if key and not reserveByKey[key] then
            raidMissing[#raidMissing + 1] = name
        end
    end

    return sortPlayerNames(reserveMissing), sortPlayerNames(raidMissing)
end

local function findBestNameCandidate(reserveName, raidPlayers, usedRaidNames)
    local reserveKey = normalizeNameKey(reserveName)
    local best

    if not reserveKey then
        return nil
    end

    for i = 1, #raidPlayers do
        local raidName = raidPlayers[i]
        local raidKey = normalizeNameKey(raidName)
        if raidKey and not usedRaidNames[raidName] then
            local distance = levenshteinDistance(reserveKey, raidKey)
            local similarity = nameSimilarity(reserveKey, raidKey, distance)
            local strength = classifyNameMatch(distance, similarity)
            if strength then
                local candidate = buildNameMatch(reserveName, raidName, distance, similarity, strength)
                if not best or compareNameMatch(candidate, best) then
                    best = candidate
                end
            end
        end
    end

    return best
end

local function buildReadinessSummaryToken(report)
    local itemContext = report.itemContext or {}
    local rosterReport = report.rosterReport or {}
    local nameMatchReport = report.nameMatchReport or {}

    return tconcat({
        tostring(report.itemId or ""),
        report.hasReserveData and "1" or "0",
        report.hasItemReserves and "1" or "0",
        tostring(itemContext.totalReserveCount or ""),
        tostring(rosterReport.totalReservePlayers or ""),
        tostring(rosterReport.presentReservePlayers or ""),
        tostring(rosterReport.missingReservePlayers or ""),
        tostring(#(nameMatchReport.strongMatches or {})),
        tostring(#(nameMatchReport.weakMatches or {})),
        tostring(nameMatchReport.unmatchedReservePlayersText or ""),
    }, "|")
end

local function buildReadinessHealth(report)
    local itemContext = report.itemContext or {}
    local rosterReport = report.rosterReport or {}
    local nameMatchReport = report.nameMatchReport or {}
    local health = {
        severity = "ok",
        issueCount = 0,
        hasNoData = false,
        hasCurrentItemIssue = false,
        currentItemIssue = nil,
        importedPlayersOutsideRaidCount = tonumber(rosterReport.missingReservePlayers) or 0,
        raidPlayersWithoutReserveCount = #(nameMatchReport.raidPlayersWithoutReserve or {}),
        suggestedNameMatchCount = #(nameMatchReport.strongMatches or {}) + #(nameMatchReport.weakMatches or {}),
        unmatchedReserveCount = #(nameMatchReport.unmatchedReservePlayers or {}),
        unmatchedRaidCount = #(nameMatchReport.unmatchedRaidPlayers or {}),
    }

    local function addIssue()
        health.issueCount = health.issueCount + 1
    end

    if report.hasReserveData ~= true then
        health.severity = "error"
        health.hasNoData = true
        addIssue()
        return health
    end

    if report.itemId then
        if report.hasItemReserves ~= true then
            health.hasCurrentItemIssue = true
            health.currentItemIssue = "no_reserves"
            addIssue()
        elseif report.hasEligibleItemReserve ~= true then
            health.hasCurrentItemIssue = true
            health.currentItemIssue = "no_eligible_reservers"
            addIssue()
        end
    end

    if health.importedPlayersOutsideRaidCount > 0 then
        addIssue()
    end
    if health.suggestedNameMatchCount > 0 then
        addIssue()
    end
    if health.unmatchedReserveCount > 0 then
        addIssue()
    end
    if health.unmatchedRaidCount > 0 then
        addIssue()
    end

    if health.issueCount > 0 then
        health.severity = "warning"
    end
    return health
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

function Display.GetItemReserveContext(ctx, itemId, raidNum)
    local context = {
        itemId = itemId,
        mode = ctx.isPlusSystem() and "plus" or "multi",
        hasReserves = false,
        hasPresentReserve = false,
        totalReserveCount = 0,
        presentReserveCount = 0,
        missingReserveCount = 0,
        presentPlayers = {},
        missingPlayers = {},
        presentPlayersText = "",
        missingPlayersText = "",
        isPlusSystem = ctx.isPlusSystem(),
        isMultiReserve = ctx.isMultiReserve(),
        rosterFilterApplied = false,
    }
    if not itemId then
        return context
    end

    local list = ctx.reservesByItemID[itemId]
    if type(list) ~= "table" or #list == 0 then
        return context
    end

    local data = { players = {}, playerCounts = {}, playerMeta = {} }
    for i = 1, #list do
        local reserveEntry = list[i]
        if type(reserveEntry) == "table" then
            addReservePlayer(data, reserveEntry)
        end
    end

    sortPlayersForDisplay(ctx, itemId, data.players, data.playerCounts, data.playerMeta)
    local presentPlayers, missingPlayers, filterApplied = splitPresentAndMissingPlayers(ctx, data.players, raidNum)
    context.hasReserves = #data.players > 0
    context.hasPresentReserve = #presentPlayers > 0
    context.totalReserveCount = #data.players
    context.presentReserveCount = #presentPlayers
    context.missingReserveCount = #missingPlayers
    context.presentPlayers = presentPlayers
    context.missingPlayers = missingPlayers
    context.presentPlayersText = buildTextForPlayers(ctx, itemId, presentPlayers, data.playerCounts, data.playerMeta, true, true)
    context.missingPlayersText = buildTextForPlayers(ctx, itemId, missingPlayers, data.playerCounts, data.playerMeta, true, true)
    context.rosterFilterApplied = filterApplied == true
    return context
end

function Display.GetRosterReserveMatchReport(ctx, raidNum)
    local report = {
        mode = ctx.isPlusSystem() and "plus" or "multi",
        totalReservePlayers = 0,
        presentReservePlayers = 0,
        missingReservePlayers = 0,
        presentPlayers = {},
        missingPlayers = {},
        presentPlayersText = "",
        missingPlayersText = "",
        rosterFilterApplied = false,
    }
    local players = getReservePlayerNames(ctx)
    local presentPlayers, missingPlayers, filterApplied = splitPresentAndMissingPlayers(ctx, players, raidNum)
    sortPlayerNames(presentPlayers)
    sortPlayerNames(missingPlayers)

    report.totalReservePlayers = #players
    report.presentReservePlayers = #presentPlayers
    report.missingReservePlayers = #missingPlayers
    report.presentPlayers = presentPlayers
    report.missingPlayers = missingPlayers
    report.presentPlayersText = tconcat(presentPlayers, ", ")
    report.missingPlayersText = tconcat(missingPlayers, ", ")
    report.rosterFilterApplied = filterApplied == true
    return report
end

function Display.GetNameMatchReport(ctx, raidNum)
    local reservePlayers = getReservePlayerNames(ctx)
    local raidPlayers, rosterFilterApplied = getRaidPlayerNames(ctx, raidNum)
    local reserveMissing, raidMissing = splitExactNameMatches(reservePlayers, raidPlayers)
    local usedRaidNames = {}
    local usedReserveNames = {}
    local strongMatches = {}
    local weakMatches = {}
    local unmatchedReservePlayers = {}
    local unmatchedRaidPlayers = {}

    for i = 1, #reserveMissing do
        local reserveName = reserveMissing[i]
        local candidate = findBestNameCandidate(reserveName, raidMissing, usedRaidNames)
        if candidate then
            usedReserveNames[reserveName] = true
            usedRaidNames[candidate.raidName] = true
            if candidate.strength == "strong" then
                strongMatches[#strongMatches + 1] = candidate
            else
                weakMatches[#weakMatches + 1] = candidate
            end
        end
    end

    for i = 1, #reserveMissing do
        local reserveName = reserveMissing[i]
        if not usedReserveNames[reserveName] then
            unmatchedReservePlayers[#unmatchedReservePlayers + 1] = reserveName
        end
    end
    for i = 1, #raidMissing do
        local raidName = raidMissing[i]
        if not usedRaidNames[raidName] then
            unmatchedRaidPlayers[#unmatchedRaidPlayers + 1] = raidName
        end
    end

    sort(strongMatches, compareNameMatch)
    sort(weakMatches, compareNameMatch)
    sortPlayerNames(unmatchedReservePlayers)
    sortPlayerNames(unmatchedRaidPlayers)

    return {
        reservePlayersOutsideRaid = reserveMissing,
        raidPlayersWithoutReserve = raidMissing,
        strongMatches = strongMatches,
        weakMatches = weakMatches,
        unmatchedReservePlayers = unmatchedReservePlayers,
        unmatchedRaidPlayers = unmatchedRaidPlayers,
        reservePlayersOutsideRaidText = tconcat(reserveMissing, ", "),
        raidPlayersWithoutReserveText = tconcat(raidMissing, ", "),
        unmatchedReservePlayersText = tconcat(unmatchedReservePlayers, ", "),
        unmatchedRaidPlayersText = tconcat(unmatchedRaidPlayers, ", "),
        rosterFilterApplied = rosterFilterApplied == true,
    }
end

function Display.GetReadinessReport(ctx, itemId, raidNum)
    local itemContext = Display.GetItemReserveContext(ctx, itemId, raidNum)
    local rosterReport = Display.GetRosterReserveMatchReport(ctx, raidNum)
    local nameMatchReport = Display.GetNameMatchReport(ctx, raidNum)
    local report = {
        itemId = itemId,
        mode = ctx.isPlusSystem() and "plus" or "multi",
        hasReserveData = (tonumber(rosterReport.totalReservePlayers) or 0) > 0,
        hasItemReserves = itemContext.hasReserves == true,
        hasEligibleItemReserve = itemContext.hasPresentReserve == true,
        itemContext = itemContext,
        rosterReport = rosterReport,
        nameMatchReport = nameMatchReport,
        rosterFilterApplied = itemContext.rosterFilterApplied == true or rosterReport.rosterFilterApplied == true or nameMatchReport.rosterFilterApplied == true,
    }

    report.summaryToken = buildReadinessSummaryToken(report)
    report.health = buildReadinessHealth(report)
    return report
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
