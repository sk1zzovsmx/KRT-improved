-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag

local Events = feature.Events or addon.Events
local C = feature.C
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Item = feature.Item or addon.Item
local Strings = feature.Strings or addon.Strings
local Time = feature.Time or addon.Time
local IgnoredItems = feature.IgnoredItems or addon.IgnoredItems or {}

local itemColors = feature.itemColors

local InternalEvents = Events.Internal

local lootState = feature.lootState
local itemInfo = feature.itemInfo
local raidState = feature.raidState
local ITEM_LINK_PATTERN = feature.ITEM_LINK_PATTERN
local rollTypes = feature.rollTypes

local itemExists, itemIsSoulbound, getItem
local getItemName, getItemLink, getItemTexture

local tinsert, tremove, twipe = table.insert, table.remove, table.wipe
local type, pairs, select = type, pairs, select
local strsub = string.sub
local strmatch = string.match
local strlen = string.len

local tostring, tonumber = tostring, tonumber
local PENDING_AWARD_TTL_SECONDS = tonumber(C.PENDING_AWARD_TTL_SECONDS) or 8
local GROUP_LOOT_PENDING_AWARD_TTL_SECONDS = tonumber(C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS) or 60
local GROUP_LOOT_ROLL_GRACE_SECONDS = tonumber(C.GROUP_LOOT_ROLL_GRACE_SECONDS) or 10
local BOSS_EVENT_CONTEXT_TTL_SECONDS = tonumber(C.BOSS_EVENT_CONTEXT_TTL_SECONDS) or 30
local GROUP_LOOT_SESSION_PREFIX = "GL:"

-- =========== Loot Helpers Module  =========== --
-- Manages the loot window items (fetching from loot/inventory).
do
    addon.Services.Loot = addon.Services.Loot or {}
    local module = addon.Services.Loot

    -- ----- Internal state ----- --
    local lootTable = {}

    -- ----- Private helpers ----- --
    local function normalizePendingAwardItemKey(itemLink)
        local itemKey = Item.GetItemStringFromLink(itemLink)
        if itemKey and itemKey ~= "" then
            return itemKey
        end
        return itemLink
    end

    local function buildPendingAwardKey(itemLink, looter, useRawItemLink)
        local itemKey = useRawItemLink and itemLink or normalizePendingAwardItemKey(itemLink)
        return tostring(itemKey) .. "\001" .. tostring(looter)
    end

    local function getPendingAwardList(itemLink, looter)
        local key = buildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if list then
            return key, list
        end

        local rawLinkKey = buildPendingAwardKey(itemLink, looter, true)
        if rawLinkKey == key then
            return key, nil
        end

        list = lootState.pendingAwards[rawLinkKey]
        if list then
            lootState.pendingAwards[key] = list
            lootState.pendingAwards[rawLinkKey] = nil
        end

        return key, list
    end

    local function ensurePendingAwardList(itemLink, looter)
        local key, list = getPendingAwardList(itemLink, looter)
        if not list then
            list = {}
            lootState.pendingAwards[key] = list
        end
        return key, list
    end

    local function normalizePendingAwardTtl(maxAge)
        local ttl = tonumber(maxAge) or PENDING_AWARD_TTL_SECONDS
        if ttl < 0 then
            ttl = 0
        end
        return ttl
    end

    local function isPendingAwardValid(pending, now, ttl)
        local expiresAt = tonumber(pending and pending.expiresAt) or nil
        return pending and ((expiresAt and now <= expiresAt) or (not expiresAt and (now - (pending.ts or 0)) <= ttl))
    end

    local function isPendingAwardExpired(pending, now, ttl)
        local expiresAt = tonumber(pending and pending.expiresAt) or nil
        return not pending or ((expiresAt and now > expiresAt) or (not expiresAt and (now - (pending.ts or 0)) > ttl))
    end

    local function hasResolvedPendingAwardValue(pending)
        return (tonumber(pending and pending.rollValue) or 0) > 0
    end

    local function isGroupLootSessionId(sessionId)
        return type(sessionId) == "string" and strsub(sessionId, 1, #GROUP_LOOT_SESSION_PREFIX) == GROUP_LOOT_SESSION_PREFIX
    end

    local function shouldConsiderPendingForMode(pending, allowGroupLootPendingAwards)
        if allowGroupLootPendingAwards ~= false then
            return true
        end
        local sessionId = pending and pending.rollSessionId and tostring(pending.rollSessionId) or nil
        return not isGroupLootSessionId(sessionId)
    end

    local function consumePendingAwardAt(list, key, index, itemLink, looter, ttl)
        local pending = list[index]
        tremove(list, index)
        local remaining = #list
        if #list == 0 then
            lootState.pendingAwards[key] = nil
        end
        addon:debug(Diag.D.LogLootPendingAwardConsumed:format(tostring(itemLink), tostring(looter), remaining, ttl))
        return pending
    end

    local function pruneExpiredPendingAwards(list, now, ttl)
        if type(list) ~= "table" then
            return
        end
        for i = #list, 1, -1 do
            local pending = list[i]
            if isPendingAwardExpired(pending, now, ttl) then
                tremove(list, i)
            end
        end
    end

    local function findPendingAwardIndex(list, now, ttl, matcher)
        for i = 1, #list do
            local pending = list[i]
            if isPendingAwardValid(pending, now, ttl) and (not matcher or matcher(pending)) then
                return i
            end
        end
        return nil
    end

    local function findUniqueValidPendingAwardIndex(list, now, ttl)
        local uniqueIndex = nil
        for i = 1, #list do
            local pending = list[i]
            if isPendingAwardValid(pending, now, ttl) then
                if uniqueIndex then
                    return nil
                end
                uniqueIndex = i
            end
        end
        return uniqueIndex
    end

    local function tryUpgradePendingAward(list, rollType, rollValue, rollSessionId, expiresAt, now)
        if not (rollValue and rollValue > 0) then
            return false
        end

        for pass = 1, 2 do
            for i = 1, #list do
                local pending = list[i]
                local pendingType = tonumber(pending and pending.rollType)
                local pendingValue = tonumber(pending and pending.rollValue) or 0
                local pendingSessionId = pending and pending.rollSessionId and tostring(pending.rollSessionId) or nil
                local sameType = pending and pendingType == rollType and pendingValue <= 0
                local sessionMatches = (pass == 1 and rollSessionId and pendingSessionId == rollSessionId)
                    or (pass == 2 and ((not rollSessionId) or pendingSessionId == nil or pendingSessionId == ""))

                if sameType and sessionMatches then
                    pending.rollValue = rollValue
                    pending.ts = now
                    if rollSessionId and not pendingSessionId then
                        pending.rollSessionId = rollSessionId
                    end
                    if expiresAt and ((tonumber(pending.expiresAt) or 0) < expiresAt) then
                        pending.expiresAt = expiresAt
                    end
                    return true
                end
            end
        end

        return false
    end

    local function touchPendingAward(pending, now, rollSessionId, expiresAt)
        if not pending then
            return nil
        end

        pending.ts = now
        if rollSessionId and (not pending.rollSessionId or pending.rollSessionId == "") then
            pending.rollSessionId = rollSessionId
        end
        if expiresAt and ((tonumber(pending.expiresAt) or 0) < expiresAt) then
            pending.expiresAt = expiresAt
        end
        return pending
    end

    local function warmItemCache(itemLink)
        local probe = Item or addon.Item
        if probe and probe.WarmItemCache then
            probe.WarmItemCache(itemLink)
        end
    end

    local function isBagItemSoulbound(bag, slot)
        local probe = Item or addon.Item
        if probe and probe.IsBagItemSoulbound then
            return probe.IsBagItemSoulbound(bag, slot)
        end
        return false
    end

    local function getRaidService()
        local services = addon.Services
        if type(services) ~= "table" then
            return nil
        end
        return services.Raid
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

    local function isPassiveGroupLootMethod(method)
        local resolvedMethod = method or getLootMethodName()
        return resolvedMethod == "group" or resolvedMethod == "needbeforegreed"
    end

    local function getPassiveLootRollItemKey(itemLink)
        local probe = Item or addon.Item
        if probe and probe.GetItemStringFromLink then
            local itemKey = probe.GetItemStringFromLink(itemLink)
            if type(itemKey) == "string" and itemKey ~= "" then
                return itemKey
            end
        end
        return itemLink
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

    local function getPassiveLootRollEntry(itemLink)
        local itemKey = getPassiveLootRollItemKey(itemLink)
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

    local function getPassiveLootRollEntryByRollId(rollId)
        local resolvedRollId = tonumber(rollId)
        if not resolvedRollId then
            return nil
        end

        purgeExpiredPassiveLootRolls()
        local state = getPassiveLootRollState()
        return state.byRollId[resolvedRollId]
    end

    local function consumePassiveLootRollEntry(sessionId)
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

    local function getLoggedPassiveLootState()
        raidState.loggedPassiveLoot = raidState.loggedPassiveLoot or {}
        return raidState.loggedPassiveLoot
    end

    local function buildLoggedPassiveLootKey(itemLink, looter)
        local itemKey = getPassiveLootRollItemKey(itemLink)
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

    local function rememberLoggedPassiveLoot(itemLink, looter, rollSessionId)
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

    local function hasLoggedPassiveLoot(itemLink, looter, rollSessionId)
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

    local function resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        local session = lootState.rollSession
        if type(session) ~= "table" then
            return nil
        end
        local sessionId = session.id
        if not sessionId or sessionId == "" then
            return nil
        end

        local sessionItemId = tonumber(session.itemId)
        local parsedItemId = tonumber(itemId)
        if sessionItemId and parsedItemId and sessionItemId == parsedItemId then
            return tostring(sessionId)
        end

        local sessionKey = session.itemKey
        if sessionKey and itemString and sessionKey == itemString then
            return tostring(sessionId)
        end
        if sessionKey and itemLink and sessionKey == itemLink then
            return tostring(sessionId)
        end
        return nil
    end

    local function bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        local resolvedLootNid = tonumber(lootNid)
        local session = lootState.rollSession
        if not resolvedLootNid or resolvedLootNid <= 0 or type(session) ~= "table" then
            return
        end

        local sessionId = session.id and tostring(session.id) or nil
        local matchedSessionId = rollSessionId and tostring(rollSessionId) or nil
        if not matchedSessionId then
            matchedSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end
        if not sessionId or matchedSessionId ~= sessionId then
            return
        end

        session.lootNid = resolvedLootNid
        lootState.currentRollItem = resolvedLootNid
    end

    local function tryDeformat(pattern, msg)
        if type(addon.Deformat) ~= "function" then
            return nil
        end
        if type(pattern) ~= "string" or pattern == "" or type(msg) ~= "string" or msg == "" then
            return nil
        end
        return addon.Deformat(msg, pattern)
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

    local function extractGroupLootPatternValues(values)
        local playerName
        local itemLink
        local numbers = {}

        if not values then
            return nil, nil, numbers
        end

        for i = 1, values.n do
            local value = values[i]
            local numberValue = tonumber(value)
            if numberValue ~= nil then
                numbers[#numbers + 1] = numberValue
            elseif not itemLink and isGroupLootItemLink(value) then
                itemLink = value
            elseif not playerName and type(value) == "string" and value ~= "" then
                playerName = normalizeLootPlayerName(value)
            end
        end

        return playerName, itemLink, numbers
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

    local function isPassiveLootWinnerMessage(msg)
        local _, itemLink = parseGroupLootWinner(msg)
        return itemLink ~= nil
    end

    local function resolvePassivePendingAwardContext(itemLink, rollId)
        local entry = getPassiveLootRollEntryByRollId(rollId) or getPassiveLootRollEntry(itemLink)
        if entry then
            return entry.sessionId, tonumber(entry.expiresAt) or nil
        end
        return nil, GetTime() + GROUP_LOOT_PENDING_AWARD_TTL_SECONDS
    end

    local function invalidateRaidRuntime(raid)
        if Core and Core.StripRuntimeRaidCaches then
            Core.StripRuntimeRaidCaches(raid)
            return
        end
        if type(raid) == "table" then
            raid._runtime = nil
        end
    end

    local function getLootItemKey(loot)
        if type(loot) ~= "table" then
            return nil
        end
        if type(loot.itemString) == "string" and loot.itemString ~= "" then
            return loot.itemString
        end
        return getPassiveLootRollItemKey(loot.itemLink)
    end

    local function resolveLootLooterName(raidNum, loot)
        if type(loot) ~= "table" then
            return nil
        end

        local looterNid = tonumber(loot.looterNid)
        if not looterNid or looterNid <= 0 then
            return nil
        end

        local raidService = getRaidService()
        if raidService then
            return raidService:GetPlayerName(looterNid, raidNum)
        end

        local raid = Core.EnsureRaidById(raidNum)
        local players = raid and raid.players or {}
        for i = #players, 1, -1 do
            local player = players[i]
            if player and tonumber(player.playerNid) == looterNid then
                return player.name
            end
        end
        return nil
    end

    local function findUpgradeablePassiveLootEntry(raid, raidNum, itemLink, looter, rollSessionId)
        if type(raid) ~= "table" or not itemLink or not looter then
            return nil
        end

        local targetItemKey = getPassiveLootRollItemKey(itemLink)
        local targetLooter = Strings.NormalizeName(looter, true) or looter
        local targetSessionId = rollSessionId and tostring(rollSessionId) or nil
        local currentTime = tonumber(Time.GetCurrentTime()) or 0
        local uniqueMatch = nil
        local sessionlessMatch = nil
        local lootList = raid.loot or {}

        for i = #lootList, 1, -1 do
            local loot = lootList[i]
            local lootTime = tonumber(loot and loot.time) or 0
            if currentTime > 0 and lootTime > 0 and (currentTime - lootTime) > GROUP_LOOT_PENDING_AWARD_TTL_SECONDS then
                break
            end

            if loot and getLootItemKey(loot) == targetItemKey then
                local lootLooter = resolveLootLooterName(raidNum, loot)
                if lootLooter == targetLooter and (tonumber(loot.rollValue) or 0) <= 0 then
                    local lootSessionId = loot.rollSessionId and tostring(loot.rollSessionId) or nil
                    if targetSessionId and targetSessionId ~= "" then
                        if lootSessionId == targetSessionId then
                            return loot
                        end
                        if not lootSessionId or lootSessionId == "" then
                            if sessionlessMatch then
                                sessionlessMatch = false
                            else
                                sessionlessMatch = loot
                            end
                        end
                    else
                        if uniqueMatch then
                            return nil
                        end
                        uniqueMatch = loot
                    end
                end
            end
        end

        if targetSessionId and type(sessionlessMatch) == "table" then
            return sessionlessMatch
        end

        return uniqueMatch
    end

    local function addLootWindowSlot(indexByItemKey, slot)
        if not LootSlotIsItem(slot) then
            return
        end

        local itemLink = GetLootSlotLink(slot)
        if not itemLink or GetItemFamily(itemLink) == 64 then
            return
        end

        local key = Item.GetItemStringFromLink(itemLink) or itemLink
        local existing = indexByItemKey[key]
        if existing then
            lootTable[existing].count = (lootTable[existing].count or 1) + 1
            return
        end

        local icon, name, _, quality = GetLootSlotInfo(slot)
        local before = lootState.lootCount
        module:AddItem(itemLink, 1, name, quality, icon)
        if lootState.lootCount > before then
            indexByItemKey[key] = lootState.lootCount
            local item = lootTable[lootState.lootCount]
            if item then
                item.itemKey = key
            end
        end
    end

    local function findLootSlotIndex(itemLink)
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        local wantedId = Item.GetItemIdFromLink(itemLink)
        for i = 1, GetNumLootItems() do
            local tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                return i
            end
            if wantedKey and tempItemLink then
                local tempKey = Item.GetItemStringFromLink(tempItemLink) or tempItemLink
                if tempKey == wantedKey then
                    return i
                end
            end
            if wantedId and tempItemLink then
                local tempItemId = Item.GetItemIdFromLink(tempItemLink)
                if tempItemId and tempItemId == wantedId then
                    return i
                end
            end
        end
        return nil
    end

    local function scanTradeableInventory(itemLink, itemId)
        if not itemLink and not itemId then
            return nil
        end

        local wantedKey = itemLink and (Item.GetItemStringFromLink(itemLink) or itemLink) or nil
        local wantedId = tonumber(itemId) or (itemLink and Item.GetItemIdFromLink(itemLink)) or nil
        local totalCount = 0
        local firstBag, firstSlot, firstSlotCount
        local hasMatch = false

        for bag = 0, 4 do
            local n = GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local key = Item.GetItemStringFromLink(link) or link
                    local linkId = Item.GetItemIdFromLink(link)
                    local matches = (wantedKey and key == wantedKey) or (wantedId and linkId == wantedId)
                    if matches then
                        hasMatch = true
                        if not itemIsSoulbound(bag, slot) then
                            local _, count = GetContainerItemInfo(bag, slot)
                            local slotCount = tonumber(count) or 1
                            totalCount = totalCount + slotCount
                            if not firstBag then
                                firstBag = bag
                                firstSlot = slot
                                firstSlotCount = slotCount
                            end
                        end
                    end
                end
            end
        end

        return totalCount, firstBag, firstSlot, firstSlotCount, hasMatch
    end

    local function resolveTradeableInventoryItem(itemLink, cachedBag, cachedSlot, selectedItemCount)
        local totalCount, bag, slot, slotCount
        local usedFastPath = false
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        local wantedId = Item.GetItemIdFromLink(itemLink)

        cachedBag = tonumber(cachedBag)
        cachedSlot = tonumber(cachedSlot)

        if cachedBag and cachedSlot then
            local cachedLink = GetContainerItemLink(cachedBag, cachedSlot)
            if cachedLink then
                local cachedKey = Item.GetItemStringFromLink(cachedLink) or cachedLink
                local cachedId = Item.GetItemIdFromLink(cachedLink)
                local sameItem = (wantedKey and cachedKey == wantedKey) or (wantedId and cachedId == wantedId)
                if sameItem and not itemIsSoulbound(cachedBag, cachedSlot) then
                    local _, count = GetContainerItemInfo(cachedBag, cachedSlot)
                    bag = cachedBag
                    slot = cachedSlot
                    slotCount = tonumber(count) or 1
                    usedFastPath = true
                end
            end
        end

        if not (bag and slot) then
            totalCount, bag, slot, slotCount = scanTradeableInventory(itemLink, wantedId)
        elseif usedFastPath then
            if (tonumber(selectedItemCount) or 1) > 1 then
                totalCount = scanTradeableInventory(itemLink, wantedId)
            else
                totalCount = tonumber(slotCount) or 1
            end
        end

        if not (bag and slot) then
            return nil
        end

        return {
            bag = bag,
            slot = slot,
            slotCount = tonumber(slotCount) or 1,
            totalCount = tonumber(totalCount) or tonumber(slotCount) or 1,
        }
    end

    local function parseLootChatMessage(msg, rollType, rollValue)
        -- Parse loot chat variants ("receives loot" and "receives item").
        local player, itemLink, count = addon.Deformat(msg, LOOT_ITEM_MULTIPLE)
        local itemCount = count or 1

        if not player then
            player, itemLink = addon.Deformat(msg, LOOT_ITEM)
            itemCount = 1
        end

        -- Self loot path (no player name in the string).
        if not itemLink then
            local link
            link, count = addon.Deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
            if link then
                itemLink = link
                itemCount = count or 1
                player = Core.GetPlayerName()
            end
        end

        if not itemLink then
            local link = addon.Deformat(msg, LOOT_ITEM_SELF)
            if link then
                itemLink = link
                itemCount = 1
                player = Core.GetPlayerName()
            end
        end

        -- Fallback for alternate loot-roll chat formats.
        if not player or not itemLink then
            local resolvedRollType, resolvedRollValue
            player, itemLink, resolvedRollType, resolvedRollValue = parseGroupLootWinner(msg)
            if itemLink then
                itemCount = 1
                rollType = rollType or resolvedRollType
                if rollValue == nil then
                    rollValue = resolvedRollValue
                end
            end
        end

        if not itemLink then
            return nil, nil, nil, rollType, rollValue
        end

        return Strings.NormalizeName(player, true) or player, tonumber(itemCount) or 1, itemLink, rollType, rollValue
    end

    local function getLootItemDetails(itemLink)
        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        return itemString, itemName, itemRarity, itemTexture, tonumber(itemId)
    end

    local function shouldSkipLootEntry(itemRarity, itemId, itemLink)
        -- Ignore low-rarity and explicitly ignored items.
        local lootThreshold = GetLootThreshold()
        if itemRarity and itemRarity < lootThreshold then
            addon:debug(Diag.D.LogLootIgnoredBelowThreshold:format(tostring(itemRarity), tonumber(lootThreshold) or -1, tostring(itemLink)))
            return true
        end
        if itemId and module:IsIgnoredItem(itemId) then
            addon:debug(Diag.D.LogLootIgnoredItemId:format(tostring(itemId), tostring(itemLink)))
            return true
        end
        return false
    end

    local function resolveLootRollOutcome(itemLink, itemString, itemId, player, rollType, rollValue)
        local passiveGroupLoot = isPassiveGroupLootMethod()
        local preferredRollSessionId = nil
        if not passiveGroupLoot then
            preferredRollSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end

        local rollSessionId
        local outcome = {
            consumedPendingAward = false,
            matchedPassiveRoll = false,
        }
        local pendingAwardTtl = passiveGroupLoot and GROUP_LOOT_PENDING_AWARD_TTL_SECONDS or PENDING_AWARD_TTL_SECONDS
        -- In ML mode, block stale GL:* pending awards only when the current item
        -- maps to an active roll session. Without a preferred session, keep GL
        -- pending lookup enabled to preserve passive Group Loot logging in mixed
        -- transition windows (Group Loot -> ML).
        local allowGroupLootPendingAwards = passiveGroupLoot or not preferredRollSessionId
        local pendingAward = module:RemovePendingAward(itemLink, player, pendingAwardTtl, preferredRollSessionId, passiveGroupLoot, allowGroupLootPendingAwards)
        if pendingAward then
            if not rollType then
                rollType = pendingAward.rollType
            end
            if rollValue == nil then
                rollValue = pendingAward.rollValue
            elseif passiveGroupLoot then
                local currentRollValue = tonumber(rollValue) or 0
                local pendingRollValue = tonumber(pendingAward.rollValue) or 0
                if currentRollValue <= 0 and pendingRollValue > 0 then
                    rollValue = pendingAward.rollValue
                end
            end
            if rollValue == nil then
                rollValue = pendingAward.rollValue
            end
            rollSessionId = pendingAward.rollSessionId and tostring(pendingAward.rollSessionId) or nil
            outcome.consumedPendingAward = true
        end

        if not rollSessionId then
            if passiveGroupLoot then
                local passiveRoll = module:GetPassiveLootRollEntry(itemLink)
                rollSessionId = passiveRoll and passiveRoll.sessionId or nil
                outcome.matchedPassiveRoll = passiveRoll ~= nil
            else
                rollSessionId = preferredRollSessionId
            end
        end

        -- Resolve award source: pending award/group-loot choice -> manual ML tag -> current roll type.
        if not rollType then
            local raidService = getRaidService()
            local isMasterLooter = raidService and raidService:IsMasterLooter()
            if isMasterLooter and not lootState.fromInventory then
                rollType = rollTypes.MANUAL
                rollValue = 0

                -- Debug marker for manual-tagged loot.
                addon:debug(Diag.D.LogLootTaggedManual, tostring(itemLink), tostring(player), tostring(lootState.currentRollType))
            else
                rollType = lootState.currentRollType
            end
        end

        if not rollSessionId then
            rollSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end

        if not rollValue then
            local services = addon.Services
            local rollsService = services and services.Rolls or nil
            rollValue = rollsService and rollsService:HighestRoll() or 0
        end

        return rollType, rollValue, rollSessionId, outcome
    end

    local function resolveBossNidForLoot(raid, raidNum, rollSessionId, passiveGroupLoot, now)
        local raidService = getRaidService()
        if not raidService then
            return 0
        end
        local ttlSeconds = passiveGroupLoot and GROUP_LOOT_PENDING_AWARD_TTL_SECONDS or BOSS_EVENT_CONTEXT_TTL_SECONDS
        return tonumber(raidService:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, {
            now = tonumber(now) or Time.GetCurrentTime(),
            allowContextRecovery = not passiveGroupLoot,
            allowTrashFallback = true,
            ttlSeconds = ttlSeconds,
        })) or 0
    end

    local function buildLootRecord(raid, itemId, itemName, itemString, itemLink, itemRarity, itemTexture, itemCount, looterNid, rollType, rollValue, rollSessionId, bossNid)
        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local lootInfo = {
            itemId = itemId,
            itemName = itemName,
            itemString = itemString,
            itemLink = itemLink,
            itemRarity = itemRarity,
            itemTexture = itemTexture,
            itemCount = itemCount,
            looterNid = (looterNid > 0) and looterNid or nil,
            rollType = rollType,
            rollValue = rollValue,
            rollSessionId = rollSessionId,
            lootNid = lootNid,
            bossNid = tonumber(bossNid) or 0,
            time = Time.GetCurrentTime(),
        }

        return lootInfo, lootNid
    end

    -- ----- Public methods ----- --
    function module:IsPassiveGroupLootMethod(method)
        return isPassiveGroupLootMethod(method)
    end

    function module:GetPassiveLootRollEntry(itemLink)
        return getPassiveLootRollEntry(itemLink)
    end

    function module:GetPassiveLootRollEntryByRollId(rollId)
        return getPassiveLootRollEntryByRollId(rollId)
    end

    function module:ConsumePassiveLootRollEntry(sessionId)
        return consumePassiveLootRollEntry(sessionId)
    end

    function module:ResolvePassivePendingAwardContext(itemLink, rollId)
        return resolvePassivePendingAwardContext(itemLink, rollId)
    end

    function module:RememberLoggedPassiveLoot(itemLink, looter, rollSessionId)
        rememberLoggedPassiveLoot(itemLink, looter, rollSessionId)
    end

    function module:HasLoggedPassiveLoot(itemLink, looter, rollSessionId)
        return hasLoggedPassiveLoot(itemLink, looter, rollSessionId)
    end

    function module:ParseGroupLootWinner(msg)
        return parseGroupLootWinner(msg)
    end

    function module:IsPassiveLootWinnerMessage(msg)
        return isPassiveLootWinnerMessage(msg)
    end

    function module:UpgradeLoggedPassiveLootRoll(itemLink, looter, rollType, rollValue, rollSessionId)
        local resolvedRollValue = tonumber(rollValue) or 0
        local currentRaidId = Core.GetCurrentRaid()
        if resolvedRollValue <= 0 or not currentRaidId then
            return false
        end

        local raid = Core.EnsureRaidById(currentRaidId)
        if not raid then
            return false
        end
        Core.EnsureRaidSchema(raid)

        local loot = findUpgradeablePassiveLootEntry(raid, currentRaidId, itemLink, looter, rollSessionId)
        if not loot then
            return false
        end

        loot.rollType = rollType or loot.rollType
        loot.rollValue = resolvedRollValue
        if rollSessionId and (not loot.rollSessionId or loot.rollSessionId == "") then
            loot.rollSessionId = tostring(rollSessionId)
        end

        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(loot.lootNid, loot.rollSessionId, loot.itemId, loot.itemString, loot.itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, currentRaidId, loot)
        return true
    end

    function module:IsIgnoredItem(itemId)
        if type(IgnoredItems.Contains) ~= "function" then
            return false
        end
        return IgnoredItems.Contains(itemId)
    end

    -- Adds a loot item to the active raid log.
    function module:AddLoot(msg, rollType, rollValue)
        local player
        local itemCount
        local itemLink
        player, itemCount, itemLink, rollType, rollValue = parseLootChatMessage(msg, rollType, rollValue)
        if not itemLink then
            addon:debug(Diag.D.LogLootParseFailed:format(tostring(msg)))
            return
        end

        local itemString, itemName, itemRarity, itemTexture, itemId = getLootItemDetails(itemLink)
        addon:trace(Diag.D.LogLootParsed:format(tostring(player), tostring(itemLink), itemCount))

        if shouldSkipLootEntry(itemRarity, itemId, itemLink) then
            return
        end
        raidState.lastLootCount = itemCount

        local currentRaidId = Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(currentRaidId)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local passiveGroupLoot = isPassiveGroupLootMethod()
        local isPassiveWinnerMessage = isPassiveLootWinnerMessage(msg)
        local rollSessionId
        local rollOutcome
        rollType, rollValue, rollSessionId, rollOutcome = resolveLootRollOutcome(itemLink, itemString, itemId, player, rollType, rollValue)

        if passiveGroupLoot and not (rollOutcome and rollOutcome.consumedPendingAward) then
            local alreadyLogged = module:HasLoggedPassiveLoot(itemLink, player, rollSessionId)
            if alreadyLogged then
                return
            end
        end

        local currentTime = Time.GetCurrentTime()
        local raidService = getRaidService()
        local bossNid = resolveBossNidForLoot(raid, currentRaidId, rollSessionId, passiveGroupLoot, currentTime)
        if bossNid <= 0 then
            addon:debug(Diag.D.LogBossNoContextTrash)
        end

        local looterNid = 0
        if raidService then
            looterNid, player = raidService:EnsureRaidPlayerNid(player, currentRaidId)
        end

        local lootInfo, lootNid =
            buildLootRecord(raid, itemId, itemName, itemString, itemLink, itemRarity, itemTexture, itemCount, looterNid, rollType, rollValue, rollSessionId, bossNid)

        -- LootCounter (MS only): increment the winner's count when the loot is actually awarded.
        -- This runs off the authoritative LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event.
        if tonumber(rollType) == rollTypes.MAINSPEC and raidService then
            raidService:AddPlayerCount(player, itemCount, currentRaidId)
        end

        if passiveGroupLoot and isPassiveWinnerMessage then
            module:RememberLoggedPassiveLoot(itemLink, player, rollSessionId)
        end

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        module:ConsumePassiveLootRollEntry(rollSessionId)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, currentRaidId, lootInfo)
        addon:debug(Diag.D.LogLootLogged:format(tonumber(currentRaidId) or -1, tostring(itemId), tostring(lootInfo.bossNid), tostring(player)))
    end

    -- Creates a local raid loot entry for inventory-trade awards when no reliable loot context exists.
    function module:LogTradeOnlyLoot(itemLink, looter, rollType, rollValue, itemCount, source, raidNum, bossNid, rollSessionId)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not itemLink or not looter or looter == "" then
            return 0
        end
        looter = Strings.NormalizeName(looter, true) or looter

        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end
        Core.EnsureRaidSchema(raid)

        local raidService = getRaidService()
        local looterNid = 0
        if raidService then
            looterNid, looter = raidService:EnsureRaidPlayerNid(looter, raidNum)
        end

        local count = tonumber(itemCount) or 1
        if count < 1 then
            count = 1
        end

        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        itemId = tonumber(itemId)
        if not itemName then
            itemName = strmatch(itemLink, "%[(.-)%]") or tostring(itemLink)
        end

        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local currentTime = Time.GetCurrentTime()
        local resolvedBossNid = tonumber(bossNid) or 0
        if resolvedBossNid <= 0 and raidService then
            resolvedBossNid = raidService:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, {
                now = currentTime,
                allowContextRecovery = false,
                allowTrashFallback = true,
                ttlSeconds = GROUP_LOOT_PENDING_AWARD_TTL_SECONDS,
            })
        end

        local lootInfo = {
            itemId = itemId,
            itemName = itemName,
            itemString = itemString,
            itemLink = itemLink,
            itemRarity = itemRarity,
            itemTexture = itemTexture,
            itemCount = count,
            looterNid = (looterNid > 0) and looterNid or nil,
            rollType = tonumber(rollType),
            rollValue = tonumber(rollValue) or 0,
            rollSessionId = rollSessionId and tostring(rollSessionId) or nil,
            lootNid = lootNid,
            bossNid = resolvedBossNid,
            time = currentTime,
            source = source or "TRADE_ONLY",
        }

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, raidNum, lootInfo)
        addon:debug(Diag.D.LogLootTradeOnlyLogged:format(tonumber(raidNum) or -1, tostring(itemId), tostring(lootNid), tostring(looter), count, tostring(lootInfo.source)))
        return lootNid
    end

    function module:AddPassiveLootRoll(rollId, rollTime)
        if not Core.GetCurrentRaid() or not isPassiveGroupLootMethod() then
            return nil
        end

        local currentRaidId = Core.GetCurrentRaid()
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
        local currentTime = Time.GetCurrentTime()
        local raidService = getRaidService()
        local contextTtl = durationSeconds + GROUP_LOOT_ROLL_GRACE_SECONDS

        if existing then
            existing.itemLink = itemLink
            existing.itemKey = getPassiveLootRollItemKey(itemLink)
            existing.expiresAt = expiresAt
            if raidService then
                local capturedBossNid = raidService:FindAndRememberBossEventContextForLootSession(currentRaidId, existing.sessionId, contextTtl, currentTime)
                if tonumber(capturedBossNid) > 0 then
                    existing.bossNid = capturedBossNid
                end
            end
            return existing
        end

        local itemKey = getPassiveLootRollItemKey(itemLink)
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
        if raidService then
            local capturedBossNid = raidService:FindAndRememberBossEventContextForLootSession(currentRaidId, entry.sessionId, contextTtl, currentTime)
            if tonumber(capturedBossNid) > 0 then
                entry.bossNid = capturedBossNid
            end
        end
        return entry
    end

    function module:AddGroupLootMessage(msg)
        if type(msg) ~= "string" or msg == "" or not isPassiveGroupLootMethod() then
            return nil
        end

        local canQueuePendingAward = type(self.AddPendingAward) == "function"
        if canQueuePendingAward then
            for i = 1, #GROUP_LOOT_RULES do
                local rule = GROUP_LOOT_RULES[i]
                local playerName, itemLink, rollId = parseGroupLootSelection(msg, rule)
                if playerName and itemLink then
                    local rollSessionId, expiresAt = resolvePassivePendingAwardContext(itemLink, rollId)
                    self:AddPendingAward(itemLink, playerName, rule.rollType, 0, rollSessionId, expiresAt)
                    addon:debug(Diag.D.LogLootGroupSelectionQueued:format(rule.label, tostring(playerName), tostring(itemLink)))
                    return "selection"
                end
            end

            local rollPlayer, rollItemLink, rollType, rollValue, rollId = parseGroupLootRoll(msg)
            if rollPlayer and rollItemLink and rollType then
                local rule = getGroupLootRule(rollType)
                local rollSessionId, expiresAt = resolvePassivePendingAwardContext(rollItemLink, rollId)
                if not self:UpgradeLoggedPassiveLootRoll(rollItemLink, rollPlayer, rollType, rollValue, rollSessionId) then
                    self:AddPendingAward(rollItemLink, rollPlayer, rollType, rollValue, rollSessionId, expiresAt)
                end
                addon:debug(Diag.D.LogLootGroupSelectionQueued:format((rule and rule.label) or "?", tostring(rollPlayer), tostring(rollItemLink)))
                return "selection"
            end
        end

        local playerName, itemLink, winnerRollType, winnerRollValue, winnerRollId = parseGroupLootWinner(msg)
        if playerName and itemLink then
            local rule = getGroupLootRule(winnerRollType)
            local winnerTypeLabel = (rule and rule.label) or "msg-generic"
            local winnerRollLabel = (winnerRollValue ~= nil) and tostring(winnerRollValue) or "msg-none"
            if canQueuePendingAward then
                local rollSessionId, expiresAt = resolvePassivePendingAwardContext(itemLink, winnerRollId)
                if
                    not self:UpgradeLoggedPassiveLootRoll(itemLink, playerName, winnerRollType, winnerRollValue, rollSessionId)
                    and (winnerRollType ~= nil or winnerRollValue ~= nil)
                then
                    self:AddPendingAward(itemLink, playerName, winnerRollType, winnerRollValue, rollSessionId, expiresAt)
                elseif type(self.RefreshPendingAward) == "function" then
                    self:RefreshPendingAward(itemLink, playerName, GROUP_LOOT_PENDING_AWARD_TTL_SECONDS, rollSessionId, expiresAt)
                end
            end
            addon:debug(Diag.D.LogLootGroupWinnerDetected:format(tostring(playerName), winnerTypeLabel, winnerRollLabel, tostring(itemLink)))
            return "winner"
        end

        return nil
    end

    -- Pending award helpers (shared with Master/Raid flows).
    function module:AddPendingAward(itemLink, looter, rollType, rollValue, rollSessionId, expiresAt)
        if not itemLink or not looter then
            return
        end
        local _, list = ensurePendingAwardList(itemLink, looter)
        local now = GetTime()
        local resolvedRollType = tonumber(rollType)
        local resolvedRollValue = tonumber(rollValue)
        local resolvedSessionId = rollSessionId and tostring(rollSessionId) or nil
        local resolvedExpiresAt = tonumber(expiresAt) or nil

        -- Group Loot commonly emits a "selected need/greed" message first, then
        -- a later "Need Roll - 96 ..." line for the same item/player. Upgrade the
        -- oldest zero-value pending entry so FIFO consumption keeps the numeric
        -- rollValue attached to the same upcoming loot receipt.
        if tryUpgradePendingAward(list, resolvedRollType, resolvedRollValue, resolvedSessionId, resolvedExpiresAt, now) then
            return
        end

        list[#list + 1] = {
            itemLink = itemLink,
            looter = looter,
            rollType = resolvedRollType or rollType,
            rollValue = resolvedRollValue or rollValue,
            rollSessionId = resolvedSessionId,
            expiresAt = resolvedExpiresAt,
            ts = now,
        }
    end

    function module:RemovePendingAward(itemLink, looter, maxAge, rollSessionId, preferResolvedValue, allowGroupLootPendingAwards)
        local ttl = normalizePendingAwardTtl(maxAge)
        local key, list = getPendingAwardList(itemLink, looter)
        if not list then
            return nil
        end

        local now = GetTime()
        local preferredSessionId = rollSessionId and tostring(rollSessionId) or nil
        if preferredSessionId and preferredSessionId ~= "" then
            local sessionIndex = findPendingAwardIndex(list, now, ttl, function(pending)
                return shouldConsiderPendingForMode(pending, allowGroupLootPendingAwards) and tostring(pending.rollSessionId or "") == preferredSessionId
            end)
            if sessionIndex then
                return consumePendingAwardAt(list, key, sessionIndex, itemLink, looter, ttl)
            end
        end

        if preferResolvedValue then
            local resolvedIndex = findPendingAwardIndex(list, now, ttl, function(pending)
                return shouldConsiderPendingForMode(pending, allowGroupLootPendingAwards) and hasResolvedPendingAwardValue(pending)
            end)
            if resolvedIndex then
                return consumePendingAwardAt(list, key, resolvedIndex, itemLink, looter, ttl)
            end
        end

        local firstValidIndex = findPendingAwardIndex(list, now, ttl, function(pending)
            return shouldConsiderPendingForMode(pending, allowGroupLootPendingAwards)
        end)
        if firstValidIndex then
            return consumePendingAwardAt(list, key, firstValidIndex, itemLink, looter, ttl)
        end

        pruneExpiredPendingAwards(list, now, ttl)
        if #list == 0 then
            lootState.pendingAwards[key] = nil
        end
        return nil
    end

    function module:RefreshPendingAward(itemLink, looter, maxAge, rollSessionId, expiresAt)
        local ttl = normalizePendingAwardTtl(maxAge)
        local key, list = getPendingAwardList(itemLink, looter)
        if not list then
            return nil
        end

        local now = GetTime()
        local resolvedSessionId = rollSessionId and tostring(rollSessionId) or nil
        local resolvedExpiresAt = tonumber(expiresAt) or nil
        local touched

        if resolvedSessionId and resolvedSessionId ~= "" then
            local sessionIndex = findPendingAwardIndex(list, now, ttl, function(pending)
                return tostring(pending.rollSessionId or "") == resolvedSessionId
            end)
            if sessionIndex then
                touched = list[sessionIndex]
            end
        end

        if not touched then
            local uniqueIndex = findUniqueValidPendingAwardIndex(list, now, ttl)
            if uniqueIndex then
                touched = list[uniqueIndex]
            end
        end

        pruneExpiredPendingAwards(list, now, ttl)
        if #list == 0 then
            lootState.pendingAwards[key] = nil
        end

        if not touched then
            return nil
        end

        return touchPendingAward(touched, now, resolvedSessionId, resolvedExpiresAt)
    end

    function module:PurgePendingAwards(maxAge)
        local ttl = normalizePendingAwardTtl(maxAge)
        local now = GetTime()
        for key, list in pairs(lootState.pendingAwards) do
            if type(list) ~= "table" then
                lootState.pendingAwards[key] = nil
            else
                pruneExpiredPendingAwards(list, now, ttl)
                if #list == 0 then
                    lootState.pendingAwards[key] = nil
                end
            end
        end
    end

    -- Fetches items from the currently open loot window.
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = getItemLink(lootState.currentItemIndex)
        end
        addon:trace(Diag.D.LogLootFetchStart:format(GetNumLootItems() or 0, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        local indexByItemKey = {}
        for i = 1, GetNumLootItems() do
            -- In loot window we treat each slot as one awardable copy (even if quantity > 1).
            addLootWindowSlot(indexByItemKey, i)
        end

        lootState.currentItemIndex = 1
        if oldItem ~= nil then
            for t = 1, lootState.lootCount do
                if oldItem == getItemLink(t) then
                    lootState.currentItemIndex = t
                    break
                end
            end
        end
        self:PrepareItem()
        addon:trace(Diag.D.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
    function module:AddItem(itemLink, itemCount, nameHint, rarityHint, textureHint, colorHint)
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

        -- Try to warm the item cache (doesn't guarantee immediate GetItemInfo).
        if (not itemName or not itemRarity or not itemTexture) and type(itemLink) == "string" then
            warmItemCache(itemLink)
        end

        if not itemName then
            itemName = nameHint
            if not itemName and type(itemLink) == "string" then
                itemName = itemLink:match("%[(.-)%]")
            end
        end

        if not itemRarity then
            itemRarity = rarityHint
        end

        if not itemTexture then
            itemTexture = textureHint
        end

        -- Prefer: explicit hint > link color > rarity color table.
        local itemColor = colorHint
        if not itemColor and type(itemLink) == "string" then
            itemColor = itemLink:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
        end
        if not itemColor then
            local r = tonumber(itemRarity) or 1
            itemColor = itemColors[r + 1] or itemColors[2]
        end

        if not itemName then
            addon:debug(Diag.D.LogLootItemInfoMissing:format(tostring(itemLink)))
            itemName = tostring(itemLink)
        end

        itemTexture = itemTexture or C.RESERVES_ITEM_FALLBACK_ICON

        if lootState.fromInventory == false then
            local lootThreshold = GetLootThreshold() or 2
            local rarity = tonumber(itemRarity) or 1
            if rarity < lootThreshold then
                return
            end
            lootState.lootCount = lootState.lootCount + 1
        else
            lootState.lootCount = 1
            lootState.currentItemIndex = 1
        end
        lootTable[lootState.lootCount] = {}
        lootTable[lootState.lootCount].itemName = itemName
        lootTable[lootState.lootCount].itemColor = itemColor
        lootTable[lootState.lootCount].itemLink = itemLink
        lootTable[lootState.lootCount].itemTexture = itemTexture
        lootTable[lootState.lootCount].count = itemCount or 1
    end

    -- Prepares the currently selected item for display.
    function module:PrepareItem()
        if itemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    -- Sets the main item display in the UI.
    function module:SetItem(i)
        if not i then
            Bus.TriggerEvent(InternalEvents.SetItem, nil, nil)
            return
        end
        if not (i.itemName and i.itemLink and i.itemTexture and i.itemColor) then
            return
        end
        Bus.TriggerEvent(InternalEvents.SetItem, i.itemLink, i)
    end

    -- Selects an item from the loot list by its index.
    function module:SelectItem(i)
        if itemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
        end
    end

    -- Clears all loot from the table and resets the UI display.
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        Bus.TriggerEvent(InternalEvents.SetItem, nil, nil)
    end

    -- Returns the table for the currently selected item.
    function getItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    -- Returns the name of the currently selected item.
    function getItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    -- Returns the link of the currently selected item.
    function getItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    -- Returns the texture of the currently selected item.
    function getItemTexture(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    function module:GetCurrentItemCount()
        if lootState.fromInventory then
            return itemInfo.count or lootState.selectedItemCount or 1
        end
        local item = getItem()
        local count = item and item.count
        if count and count > 0 then
            return count
        end
        return 1
    end

    -- Checks if a loot item exists at the given index.
    function itemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    -- Checks if an item in the player's bags is soulbound.
    function itemIsSoulbound(bag, slot)
        return isBagItemSoulbound(bag, slot)
    end

    -- Cross-module bridge for split files (Rolls/Master).
    module.WarmItemCache = warmItemCache
    module.IsBagItemSoulbound = isBagItemSoulbound
    module.GetItem = getItem
    module.GetItemName = getItemName
    module.GetItemLink = getItemLink
    module.GetItemTexture = getItemTexture
    module.ItemExists = itemExists
    module.ItemIsSoulbound = itemIsSoulbound
    function module.FindLootSlotIndex(selfOrItemLink, maybeItemLink)
        local itemLink = maybeItemLink ~= nil and maybeItemLink or selfOrItemLink
        return findLootSlotIndex(itemLink)
    end

    function module.FindTradeableInventoryMatch(selfOrItemLink, arg2, arg3)
        local itemLink, itemId
        if type(selfOrItemLink) == "table" then
            itemLink = arg2
            itemId = arg3
        else
            itemLink = selfOrItemLink
            itemId = arg2
        end
        return scanTradeableInventory(itemLink, itemId)
    end

    function module.FindTradeableInventoryItem(selfOrItemLink, arg2, arg3, arg4, arg5)
        local itemLink, cachedBag, cachedSlot, selectedItemCount
        if type(selfOrItemLink) == "table" then
            itemLink = arg2
            cachedBag = arg3
            cachedSlot = arg4
            selectedItemCount = arg5
        else
            itemLink = selfOrItemLink
            cachedBag = arg2
            cachedSlot = arg3
            selectedItemCount = arg4
        end
        return resolveTradeableInventoryItem(itemLink, cachedBag, cachedSlot, selectedItemCount)
    end
end
