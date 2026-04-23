-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: passive group-loot parser/state helpers for loot service
-- exports: addon.Services.Loot._PassiveGroupLoot

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag
local C = feature.C
local Core = feature.Core
local Item = feature.Item or addon.Item
local Strings = feature.Strings or addon.Strings
local raidState = feature.raidState
local lootState = feature.lootState
local ITEM_LINK_PATTERN = feature.ITEM_LINK_PATTERN
local rollTypes = feature.rollTypes

addon.Services = addon.Services or {}
addon.Services.Loot = addon.Services.Loot or {}

-- ----- Internal state ----- --
local module = addon.Services.Loot
module._PassiveGroupLoot = module._PassiveGroupLoot or {}

local PassiveGroupLoot = module._PassiveGroupLoot

local tremove = table.remove
local strmatch = string.match
local strlen = string.len
local tonumber, tostring = tonumber, tostring
local type, pairs, select = type, pairs, select

local GROUP_LOOT_PENDING_AWARD_TTL_SECONDS = tonumber(C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS) or 60
local GROUP_LOOT_ROLL_GRACE_SECONDS = tonumber(C.GROUP_LOOT_ROLL_GRACE_SECONDS) or 10

local Services = feature.Services or addon.Services

-- ----- Private helpers ----- --
local function isDebugEnabled()
    return addon.hasDebug ~= nil
end

local function getLootMethodName()
    if type(GetLootMethod) ~= "function" then
        return nil
    end
    local method = select(1, GetLootMethod())
    if type(method) ~= "string" or method == "" then
        return nil
    end
    return method
end

local function getPassiveLootRollState()
    raidState.passiveLootRolls = raidState.passiveLootRolls or {}
    local state = raidState.passiveLootRolls
    state.byItemKey = state.byItemKey or {}
    state.bySessionId = state.bySessionId or {}
    state.byRollId = state.byRollId or {}
    state.nextSessionId = tonumber(state.nextSessionId) or 1
    if state.nextSessionId < 1 then
        state.nextSessionId = 1
    end
    return state
end

local function removePassiveLootRollEntry(state, entry)
    if type(state) ~= "table" or type(entry) ~= "table" then
        return
    end

    if entry.sessionId then
        state.bySessionId[entry.sessionId] = nil
    end
    if entry.rollId then
        state.byRollId[entry.rollId] = nil
    end

    local itemKey = entry.itemKey
    local list = itemKey and state.byItemKey[itemKey] or nil
    if type(list) ~= "table" then
        return
    end

    for i = #list, 1, -1 do
        local candidate = list[i]
        if candidate == entry or (candidate and candidate.sessionId == entry.sessionId) then
            tremove(list, i)
        end
    end

    if #list == 0 then
        state.byItemKey[itemKey] = nil
    end
end

local function purgeExpiredPassiveLootRolls(now)
    local state = getPassiveLootRollState()
    local currentTime = tonumber(now) or GetTime()

    for itemKey, list in pairs(state.byItemKey) do
        if type(list) ~= "table" then
            state.byItemKey[itemKey] = nil
        else
            for i = #list, 1, -1 do
                local entry = list[i]
                local expiresAt = tonumber(entry and entry.expiresAt) or 0
                if not entry or expiresAt <= currentTime then
                    removePassiveLootRollEntry(state, entry)
                end
            end
        end
    end
end

local function getLoggedPassiveLootState()
    raidState.loggedPassiveLoot = raidState.loggedPassiveLoot or {}
    return raidState.loggedPassiveLoot
end

local function buildLoggedPassiveLootKey(itemLink, looter)
    local itemKey = PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink)
    local normalizedLooter = Strings.NormalizeName(looter, true) or looter
    return tostring(itemKey) .. "\001" .. tostring(normalizedLooter)
end

local function purgeExpiredLoggedPassiveLoot(now)
    local state = getLoggedPassiveLootState()
    local currentTime = tonumber(now) or GetTime()

    for key, list in pairs(state) do
        if type(list) ~= "table" then
            state[key] = nil
        else
            for i = #list, 1, -1 do
                local marker = list[i]
                local expiresAt = tonumber(marker and marker.expiresAt) or 0
                if not marker or expiresAt <= currentTime then
                    tremove(list, i)
                end
            end

            if #list == 0 then
                state[key] = nil
            end
        end
    end
end

local function packValues(...)
    return {
        n = select("#", ...),
        ...,
    }
end

local localizedDeformatCache = {}
local localizedFormatCaptures = {
    c = { pattern = "(.)", numeric = false },
    d = { pattern = "(-?%d+)", numeric = true },
    f = { pattern = "(-?%d+%.?%d*)", numeric = true },
    g = { pattern = "(-?%d+%.?%d*)", numeric = true },
    i = { pattern = "(-?%d+)", numeric = true },
    s = { pattern = "(.-)", numeric = false },
}

local function escapeLuaPatternText(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function compileLocalizedDeformatPattern(pattern)
    local cached = localizedDeformatCache[pattern]
    if cached then
        return cached
    end

    local luaPattern = { "^" }
    local captures = {}
    local nextIndex = 1
    local maxIndex = 0
    local cursor = 1

    while cursor <= strlen(pattern) do
        local percentIndex = string.find(pattern, "%", cursor, true)
        if not percentIndex then
            luaPattern[#luaPattern + 1] = escapeLuaPatternText(string.sub(pattern, cursor))
            break
        end

        if percentIndex > cursor then
            luaPattern[#luaPattern + 1] = escapeLuaPatternText(string.sub(pattern, cursor, percentIndex - 1))
        end

        local marker = string.sub(pattern, percentIndex + 1, percentIndex + 1)
        if marker == "%" then
            luaPattern[#luaPattern + 1] = "%%"
            cursor = percentIndex + 2
        else
            local placeholder = string.sub(pattern, percentIndex + 1)
            local explicitIndex, explicitFlags, explicitType = strmatch(placeholder, "^(%d+)%$([%-%d%.]*)([cdfgis])")
            local flags = nil
            local formatType = explicitType
            local targetIndex = nil

            if formatType then
                targetIndex = tonumber(explicitIndex)
                cursor = percentIndex + #explicitIndex + #explicitFlags + 3
            else
                flags, formatType = strmatch(placeholder, "^([%-%d%.]*)([cdfgis])")
                if not formatType then
                    luaPattern[#luaPattern + 1] = "%%"
                    cursor = percentIndex + 1
                else
                    targetIndex = nextIndex
                    nextIndex = nextIndex + 1
                    cursor = percentIndex + #flags + 2
                end
            end

            if formatType then
                local capture = localizedFormatCaptures[formatType]
                luaPattern[#luaPattern + 1] = capture.pattern
                captures[#captures + 1] = {
                    targetIndex = targetIndex,
                    numeric = capture.numeric,
                }
                if targetIndex > maxIndex then
                    maxIndex = targetIndex
                end
            end
        end
    end

    luaPattern[#luaPattern + 1] = "$"
    cached = {
        captures = captures,
        maxIndex = maxIndex,
        matchPattern = table.concat(luaPattern),
    }
    localizedDeformatCache[pattern] = cached
    return cached
end

local function tryLocalizedDeformatValues(pattern, msg)
    local compiled = compileLocalizedDeformatPattern(pattern)
    if not compiled or compiled.maxIndex < 1 then
        return nil
    end

    local matches = packValues(strmatch(msg, compiled.matchPattern))
    if matches.n == 0 or matches[1] == nil then
        return nil
    end

    local values = { n = compiled.maxIndex }
    for i = 1, #compiled.captures do
        local capture = compiled.captures[i]
        local value = matches[i]
        if capture.numeric then
            value = tonumber(value) or value
        end
        values[capture.targetIndex] = value
    end
    return values
end

local function tryDeformatValues(pattern, msg)
    if type(pattern) ~= "string" or pattern == "" or type(msg) ~= "string" or msg == "" then
        return nil
    end

    if type(addon.Deformat) == "function" then
        local values = packValues(addon.Deformat(msg, pattern))
        if values.n > 0 and values[1] ~= nil then
            return values
        end
    end

    return tryLocalizedDeformatValues(pattern, msg)
end

local function normalizeLootPlayerName(name)
    return Strings.NormalizeName(name, true) or name
end

local GROUP_LOOT_RULES = {
    {
        rollType = rollTypes.NEED,
        label = "NE",
        selectionGroupPattern = LOOT_ROLL_NEED,
        selectionSelfPattern = LOOT_ROLL_NEED_SELF,
        rollPattern = LOOT_ROLL_ROLLED_NEED,
        rollSelfPattern = _G["LOOT_ROLL_ROLLED_NEED_SELF"],
        winnerPatterns = {
            { group = LOOT_ROLL_WON_NO_SPAM_NEED, self = LOOT_ROLL_YOU_WON_NO_SPAM_NEED },
        },
    },
    {
        rollType = rollTypes.GREED,
        label = "GR",
        selectionGroupPattern = LOOT_ROLL_GREED,
        selectionSelfPattern = LOOT_ROLL_GREED_SELF,
        rollPattern = LOOT_ROLL_ROLLED_GREED,
        rollSelfPattern = _G["LOOT_ROLL_ROLLED_GREED_SELF"],
        winnerPatterns = {
            { group = LOOT_ROLL_WON_NO_SPAM_GREED, self = LOOT_ROLL_YOU_WON_NO_SPAM_GREED },
        },
    },
    {
        rollType = rollTypes.DISENCHANT,
        label = "DE",
        selectionGroupPattern = LOOT_ROLL_DISENCHANT,
        selectionSelfPattern = LOOT_ROLL_DISENCHANT_SELF,
        rollPattern = LOOT_ROLL_ROLLED_DE,
        rollSelfPattern = _G["LOOT_ROLL_ROLLED_DE_SELF"] or _G["LOOT_ROLL_ROLLED_DISENCHANT_SELF"],
        winnerPatterns = {
            { group = LOOT_ROLL_WON_NO_SPAM_DE, self = LOOT_ROLL_YOU_WON_NO_SPAM_DE },
            { group = LOOT_ROLL_WON_NO_SPAM_DISENCHANT, self = LOOT_ROLL_YOU_WON_NO_SPAM_DISENCHANT },
        },
    },
}

local function getGroupLootRule(rollType)
    local resolvedRollType = tonumber(rollType)
    for i = 1, #GROUP_LOOT_RULES do
        local rule = GROUP_LOOT_RULES[i]
        if rule.rollType == resolvedRollType then
            return rule
        end
    end
    return nil
end

local function isGroupLootItemLink(value)
    if type(value) ~= "string" or value == "" then
        return false
    end

    if strmatch(value, ITEM_LINK_PATTERN) then
        return true
    end

    if Item and Item.GetItemStringFromLink then
        local itemKey = Item.GetItemStringFromLink(value)
        if itemKey and itemKey ~= "" then
            return true
        end
    end

    return false
end

-- Reusable buffer for numeric values extracted from loot messages (GC reduction).
local numbersBuffer = {}

local function extractGroupLootPatternValues(values)
    local playerName
    local itemLink
    local nCount = 0

    -- Reuse static buffer; wipe previous contents.
    for k in pairs(numbersBuffer) do
        numbersBuffer[k] = nil
    end

    if not values then
        return nil, nil, numbersBuffer
    end

    for i = 1, values.n do
        local value = values[i]
        local numberValue = tonumber(value)
        if numberValue ~= nil then
            nCount = nCount + 1
            numbersBuffer[nCount] = numberValue
        elseif not itemLink and isGroupLootItemLink(value) then
            itemLink = value
        elseif not playerName and type(value) == "string" and value ~= "" then
            playerName = normalizeLootPlayerName(value)
        end
    end

    return playerName, itemLink, numbersBuffer
end

local function resolveGroupLootNumericFields(numbers, singleNumberMode)
    local count = #numbers
    if count >= 2 then
        return numbers[1], numbers[count] or 0
    end
    if count == 1 then
        if singleNumberMode == "roll_id" then
            return numbers[1], 0
        end
        return nil, numbers[1] or 0
    end
    return nil, 0
end

local function parseGroupLootSelection(msg, rule)
    local values = tryDeformatValues(rule.selectionSelfPattern, msg)
    if values then
        local _, itemLink, numbers = extractGroupLootPatternValues(values)
        if itemLink then
            return Core.GetPlayerName(), itemLink, numbers[1] or nil
        end
    end

    values = tryDeformatValues(rule.selectionGroupPattern, msg)
    if values then
        local playerName, itemLink, numbers = extractGroupLootPatternValues(values)
        if playerName and itemLink then
            return playerName, itemLink, numbers[1] or nil
        end
    end

    return nil
end

local function parseGroupLootRollPattern(msg, pattern, rollType, isSelf)
    local values = tryDeformatValues(pattern, msg)
    if not values then
        return nil
    end

    local playerName, itemLink, numbers = extractGroupLootPatternValues(values)
    local rollId, rollValue = resolveGroupLootNumericFields(numbers, "roll_value")
    if not itemLink then
        return nil
    end
    if isSelf then
        playerName = Core.GetPlayerName()
    end
    if not playerName then
        return nil
    end

    return playerName, itemLink, rollType, rollValue, rollId
end

local function parseGroupLootRoll(msg)
    for i = 1, #GROUP_LOOT_RULES do
        local rule = GROUP_LOOT_RULES[i]
        local playerName, itemLink, rollType, rollValue, rollId = parseGroupLootRollPattern(msg, rule.rollPattern, rule.rollType, false)
        if itemLink then
            return playerName, itemLink, rollType, rollValue, rollId
        end

        playerName, itemLink, rollType, rollValue, rollId = parseGroupLootRollPattern(msg, rule.rollSelfPattern, rule.rollType, true)
        if itemLink then
            return playerName, itemLink, rollType, rollValue, rollId
        end
    end

    return nil
end

local function parseGroupLootWinnerPattern(msg, groupPattern, selfPattern, rollType)
    local values = tryDeformatValues(selfPattern, msg)
    if values then
        local _, itemLink, numbers = extractGroupLootPatternValues(values)
        local rollId, rollValue = resolveGroupLootNumericFields(numbers, "roll_value")
        if itemLink then
            return Core.GetPlayerName(), itemLink, rollType, rollValue, rollId
        end
    end

    values = tryDeformatValues(groupPattern, msg)
    if values then
        local playerName, itemLink, numbers = extractGroupLootPatternValues(values)
        local rollId, rollValue = resolveGroupLootNumericFields(numbers, "roll_value")
        if playerName and itemLink then
            return playerName, itemLink, rollType, rollValue, rollId
        end
    end

    return nil
end

local function parseGroupLootWinner(msg)
    for i = 1, #GROUP_LOOT_RULES do
        local rule = GROUP_LOOT_RULES[i]
        for j = 1, #rule.winnerPatterns do
            local patterns = rule.winnerPatterns[j]
            local playerName, itemLink, resolvedRollType, resolvedRollValue, resolvedRollId = parseGroupLootWinnerPattern(msg, patterns.group, patterns.self, rule.rollType)
            if itemLink then
                return playerName, itemLink, resolvedRollType, resolvedRollValue, resolvedRollId
            end
        end
    end

    local values = tryDeformatValues(LOOT_ROLL_YOU_WON, msg)
    if values and values.n >= 2 then
        return Core.GetPlayerName(), values[2], nil, nil, tonumber(values[1]) or nil
    end
    if values and values.n >= 1 then
        return Core.GetPlayerName(), values[1], nil, nil, nil
    end

    values = tryDeformatValues(LOOT_ROLL_WON, msg)
    if values and values.n >= 3 then
        return normalizeLootPlayerName(values[2]), values[3], nil, nil, tonumber(values[1]) or nil
    end
    if values and values.n >= 2 then
        return normalizeLootPlayerName(values[1]), values[2], nil, nil, nil
    end

    return nil
end

local function queuePendingPassiveAward(owner, itemLink, looter, rollType, rollValue, rollId, refreshLogged)
    local rollSessionId, expiresAt = PassiveGroupLoot.ResolvePassivePendingAwardContext(itemLink, rollId)
    local upgraded = owner:UpgradeLoggedPassiveLootRoll(itemLink, looter, rollType, rollValue, rollSessionId)
    if not upgraded then
        owner:AddPendingAward(itemLink, looter, rollType, rollValue, rollSessionId, expiresAt)
    elseif refreshLogged and type(owner.RefreshPendingAward) == "function" then
        owner:RefreshPendingAward(itemLink, looter, GROUP_LOOT_PENDING_AWARD_TTL_SECONDS, rollSessionId, expiresAt)
    end
    return upgraded
end

local function capturePassiveRollBossContext(raidService, raidNum, sessionId, ttlSeconds, now)
    if not (raidService and raidService.FindAndRememberBossContextForLootSession) then
        return 0
    end

    return tonumber(raidService:FindAndRememberBossContextForLootSession(raidNum, sessionId, {
        ttlSeconds = ttlSeconds,
        now = now,
        allowContextRecovery = true,
    })) or 0
end

-- ----- Public methods ----- --
function PassiveGroupLoot.IsPassiveGroupLootMethod(method)
    local resolvedMethod = method or getLootMethodName()
    return resolvedMethod == "group" or resolvedMethod == "needbeforegreed"
end

function PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink)
    local itemKey = Item.GetItemStringFromLink(itemLink)
    if itemKey and itemKey ~= "" then
        return itemKey
    end
    return itemLink
end

function PassiveGroupLoot.GetPassiveLootRollEntry(itemLink)
    local itemKey = PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink)
    purgeExpiredPassiveLootRolls()

    local state = getPassiveLootRollState()
    local list = state.byItemKey[itemKey]
    if type(list) ~= "table" then
        return nil
    end

    local entry = nil
    for i = 1, #list do
        local candidate = list[i]
        if candidate then
            if entry then
                return nil
            end
            entry = candidate
        end
    end

    return entry
end

function PassiveGroupLoot.GetPassiveLootRollEntryByRollId(rollId)
    local resolvedRollId = tonumber(rollId)
    if not resolvedRollId then
        return nil
    end

    purgeExpiredPassiveLootRolls()
    local state = getPassiveLootRollState()
    return state.byRollId[resolvedRollId]
end

function PassiveGroupLoot.ConsumePassiveLootRollEntry(sessionId)
    if type(sessionId) ~= "string" or sessionId == "" then
        return nil
    end

    purgeExpiredPassiveLootRolls()
    local state = getPassiveLootRollState()
    local entry = state.bySessionId[sessionId]
    if not entry then
        return nil
    end

    removePassiveLootRollEntry(state, entry)
    return entry
end

function PassiveGroupLoot.RememberLoggedPassiveLoot(itemLink, looter, rollSessionId)
    if not itemLink or not looter then
        return
    end

    local now = GetTime()
    purgeExpiredLoggedPassiveLoot(now)

    local state = getLoggedPassiveLootState()
    local key = buildLoggedPassiveLootKey(itemLink, looter)
    local list = state[key]
    if type(list) ~= "table" then
        list = {}
        state[key] = list
    end

    local resolvedSessionId = rollSessionId and tostring(rollSessionId) or nil
    local expiresAt = now + GROUP_LOOT_PENDING_AWARD_TTL_SECONDS
    for i = 1, #list do
        local marker = list[i]
        if marker and tostring(marker.rollSessionId or "") == tostring(resolvedSessionId or "") then
            marker.rollSessionId = resolvedSessionId
            marker.expiresAt = expiresAt
            return
        end
    end

    list[#list + 1] = {
        rollSessionId = resolvedSessionId,
        expiresAt = expiresAt,
    }
end

function PassiveGroupLoot.HasLoggedPassiveLoot(itemLink, looter, rollSessionId)
    if not itemLink or not looter then
        return false
    end

    purgeExpiredLoggedPassiveLoot()

    local state = getLoggedPassiveLootState()
    local list = state[buildLoggedPassiveLootKey(itemLink, looter)]
    if type(list) ~= "table" or #list == 0 then
        return false
    end

    local resolvedSessionId = rollSessionId and tostring(rollSessionId) or nil
    if resolvedSessionId and resolvedSessionId ~= "" then
        for i = 1, #list do
            local marker = list[i]
            if marker and tostring(marker.rollSessionId or "") == resolvedSessionId then
                return true
            end
        end
        return false
    end

    return #list == 1
end

function PassiveGroupLoot.ParseGroupLootWinner(msg)
    return parseGroupLootWinner(msg)
end

function PassiveGroupLoot.IsPassiveLootWinnerMessage(msg)
    local _, itemLink = parseGroupLootWinner(msg)
    return itemLink ~= nil
end

function PassiveGroupLoot.ResolvePassivePendingAwardContext(itemLink, rollId)
    local entry = PassiveGroupLoot.GetPassiveLootRollEntryByRollId(rollId) or PassiveGroupLoot.GetPassiveLootRollEntry(itemLink)
    if entry then
        return entry.sessionId, tonumber(entry.expiresAt) or nil
    end
    return nil, GetTime() + GROUP_LOOT_PENDING_AWARD_TTL_SECONDS
end

function PassiveGroupLoot.AddPassiveLootRoll(owner, rollId, rollTime)
    local currentRaidId = Core.GetCurrentRaid()
    if not currentRaidId or not PassiveGroupLoot.IsPassiveGroupLootMethod() then
        return nil
    end

    local resolvedRollId = tonumber(rollId)
    if not resolvedRollId then
        return nil
    end

    local getLootRollItemLink = _G.GetLootRollItemLink
    if type(getLootRollItemLink) ~= "function" then
        return nil
    end

    local itemLink = getLootRollItemLink(resolvedRollId)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    purgeExpiredPassiveLootRolls()
    local state = getPassiveLootRollState()
    local existing = state.byRollId[resolvedRollId]
    local durationSeconds = (tonumber(rollTime) or 0) / 1000
    if durationSeconds < 0 then
        durationSeconds = 0
    end
    local expiresAt = GetTime() + durationSeconds + GROUP_LOOT_ROLL_GRACE_SECONDS
    local currentTime = feature.Time.GetCurrentTime()
    local raidService = Services.Raid
    local contextTtl = durationSeconds + GROUP_LOOT_ROLL_GRACE_SECONDS

    if existing then
        existing.itemLink = itemLink
        existing.itemKey = PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink)
        existing.expiresAt = expiresAt
        local capturedBossNid = capturePassiveRollBossContext(raidService, currentRaidId, existing.sessionId, contextTtl, currentTime)
        if capturedBossNid > 0 then
            existing.bossNid = capturedBossNid
        end
        return existing
    end

    local itemKey = PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink)
    local list = state.byItemKey[itemKey]
    if type(list) ~= "table" then
        list = {}
        state.byItemKey[itemKey] = list
    end

    local entry = {
        rollId = resolvedRollId,
        itemLink = itemLink,
        itemKey = itemKey,
        sessionId = "GL:" .. tostring(state.nextSessionId),
        expiresAt = expiresAt,
        bossNid = nil,
    }
    state.nextSessionId = state.nextSessionId + 1
    list[#list + 1] = entry
    state.bySessionId[entry.sessionId] = entry
    state.byRollId[resolvedRollId] = entry
    local capturedBossNid = capturePassiveRollBossContext(raidService, currentRaidId, entry.sessionId, contextTtl, currentTime)
    if capturedBossNid > 0 then
        entry.bossNid = capturedBossNid
    end
    return entry
end

function PassiveGroupLoot.AddGroupLootMessage(owner, msg)
    if type(msg) ~= "string" or msg == "" or not PassiveGroupLoot.IsPassiveGroupLootMethod() then
        return nil
    end

    local canQueuePendingAward = owner and type(owner.AddPendingAward) == "function"
    if canQueuePendingAward then
        for i = 1, #GROUP_LOOT_RULES do
            local rule = GROUP_LOOT_RULES[i]
            local playerName, itemLink, rollId = parseGroupLootSelection(msg, rule)
            if playerName and itemLink then
                local rollSessionId, expiresAt = PassiveGroupLoot.ResolvePassivePendingAwardContext(itemLink, rollId)
                owner:AddPendingAward(itemLink, playerName, rule.rollType, 0, rollSessionId, expiresAt)
                if isDebugEnabled() then
                    addon:debug(Diag.D.LogLootGroupSelectionQueued:format(rule.label, tostring(playerName), tostring(itemLink)))
                end
                return "selection"
            end
        end

        local rollPlayer, rollItemLink, rollType, rollValue, rollId = parseGroupLootRoll(msg)
        if rollPlayer and rollItemLink and rollType then
            local rule = getGroupLootRule(rollType)
            queuePendingPassiveAward(owner, rollItemLink, rollPlayer, rollType, rollValue, rollId, false)
            if isDebugEnabled() then
                addon:debug(Diag.D.LogLootGroupSelectionQueued:format((rule and rule.label) or "?", tostring(rollPlayer), tostring(rollItemLink)))
            end
            return "selection"
        end
    end

    local playerName, itemLink, winnerRollType, winnerRollValue, winnerRollId = parseGroupLootWinner(msg)
    if playerName and itemLink then
        local rule = getGroupLootRule(winnerRollType)
        local winnerTypeLabel = (rule and rule.label) or "msg-generic"
        local winnerRollLabel = (winnerRollValue ~= nil) and tostring(winnerRollValue) or "msg-none"
        if canQueuePendingAward and (winnerRollType ~= nil or winnerRollValue ~= nil) then
            queuePendingPassiveAward(owner, itemLink, playerName, winnerRollType, winnerRollValue, winnerRollId, true)
        end
        if isDebugEnabled() then
            addon:debug(Diag.D.LogLootGroupWinnerDetected:format(tostring(playerName), winnerTypeLabel, winnerRollLabel, tostring(itemLink)))
        end
        return "winner"
    end

    return nil
end
