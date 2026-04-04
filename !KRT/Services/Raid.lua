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
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Time = feature.Time or addon.Time
local Base64 = feature.Base64 or addon.Base64
local Item = feature.Item or addon.Item
local IgnoredItems = feature.IgnoredItems or addon.IgnoredItems or {}
local IgnoredMobs = feature.IgnoredMobs or addon.IgnoredMobs or {}

local InternalEvents = Events.Internal

local ITEM_LINK_PATTERN = feature.ITEM_LINK_PATTERN
local rollTypes = feature.rollTypes

local lootState = feature.lootState
local raidState = feature.raidState

local tinsert, tremove, twipe = table.insert, table.remove, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select
local strlen = string.len
local strmatch = string.match

local tostring, tonumber = tostring, tonumber
local UnitRace, UnitSex = UnitRace, UnitSex

-- Raid helper module.
-- Manages raid state, roster, boss kills, and loot logging.
do
    addon.Services = addon.Services or {}
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid
    -- ----- Internal state ----- --
    local numRaid = 0
    local rosterVersion = 0
    local getLootMethod = GetLootMethod
    local getRaidRosterInfo = GetRaidRosterInfo
    local unitIsUnit = UnitIsUnit
    local liveUnitsByName = {}
    local liveNamesByUnit = {}
    local pendingUnits = {}
    local raidInstanceCheckHandles = {}
    local masterLootCandidateCache = {
        itemLink = nil,
        rosterVersion = nil,
        indexByName = {},
    }

    local UNKNOWN_OBJECT = _G.UNKNOWNOBJECT
    local UNKNOWN_BEING = _G.UNKNOWNBEING or _G.UKNOWNBEING
    local RETRY_DELAY_SECONDS = 1
    local RETRY_MAX_ATTEMPTS = 5
    local RAID_INSTANCE_CHECK_DELAYS = { 0.3, 0.8, 1.5, 2.5, 3.5 }
    local ROSTER_REFRESH_DELAY_SECONDS = 2

    local function getLootService()
        local services = addon.Services
        return services and services.Loot or nil
    end

    local function getRollsService()
        local services = addon.Services
        return services and services.Rolls or nil
    end
    local BOSS_KILL_DEDUPE_WINDOW_SECONDS = tonumber(C.BOSS_KILL_DEDUPE_WINDOW_SECONDS) or 30
    local BOSS_EVENT_CONTEXT_TTL_SECONDS = tonumber(C.BOSS_EVENT_CONTEXT_TTL_SECONDS) or BOSS_KILL_DEDUPE_WINDOW_SECONDS
    local PENDING_AWARD_TTL_SECONDS = tonumber(C.PENDING_AWARD_TTL_SECONDS) or 8
    local GROUP_LOOT_PENDING_AWARD_TTL_SECONDS = tonumber(C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS) or 60
    local GROUP_LOOT_ROLL_GRACE_SECONDS = tonumber(C.GROUP_LOOT_ROLL_GRACE_SECONDS) or 10

    -- ----- Private helpers ----- --
    local function getLootMethodName()
        if type(getLootMethod) ~= "function" then
            return nil
        end
        local method = select(1, getLootMethod())
        if type(method) ~= "string" or method == "" then
            return nil
        end
        return method
    end

    local function invalidateMasterLootCandidateCache()
        masterLootCandidateCache.itemLink = nil
        masterLootCandidateCache.rosterVersion = nil
        twipe(masterLootCandidateCache.indexByName)
    end

    local function buildMasterLootCandidateCache(itemLink)
        masterLootCandidateCache.itemLink = itemLink
        masterLootCandidateCache.rosterVersion = rosterVersion
        twipe(masterLootCandidateCache.indexByName)

        for p = 1, addon.GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                masterLootCandidateCache.indexByName[candidate] = p
            end
        end

        addon:debug(Diag.D.LogMLCandidateCacheBuilt:format(tostring(itemLink), addon.tLength(masterLootCandidateCache.indexByName)))
        return masterLootCandidateCache
    end

    local function ensureMasterLootCandidateCache(itemLink)
        if masterLootCandidateCache.itemLink ~= itemLink or masterLootCandidateCache.rosterVersion ~= rosterVersion then
            return buildMasterLootCandidateCache(itemLink)
        end
        return masterLootCandidateCache
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

    local function resolvePassivePendingAwardContext(itemLink, rollId)
        local entry = getPassiveLootRollEntryByRollId(rollId) or getPassiveLootRollEntry(itemLink)
        if entry then
            return entry.sessionId, tonumber(entry.expiresAt) or nil
        end
        return nil, GetTime() + GROUP_LOOT_PENDING_AWARD_TTL_SECONDS
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

    local function isUnknownName(name)
        return (not name) or name == "" or name == UNKNOWN_OBJECT or name == UNKNOWN_BEING
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

    local function invalidateRaidRuntime(raid)
        if Core and Core.StripRuntimeRaidCaches then
            Core.StripRuntimeRaidCaches(raid)
            return
        end
        if type(raid) == "table" then
            raid._runtime = nil
        end
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

    local function resetLiveUnitCaches()
        twipe(liveUnitsByName)
        twipe(liveNamesByUnit)
    end

    local function cancelPendingUnitRetryTimer()
        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = nil
    end

    local function cancelScheduledRosterRefresh()
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
    end

    local function scheduleRosterRefresh()
        cancelScheduledRosterRefresh()
        module.updateRosterHandle = addon.NewTimer(ROSTER_REFRESH_DELAY_SECONDS, function()
            module.updateRosterHandle = nil
            module:UpdateRaidRoster()
        end)
    end

    local function resetPendingUnitRetry()
        cancelPendingUnitRetryTimer()
        twipe(pendingUnits)
    end

    local function markPendingUnit(unitID)
        local tries = tonumber(pendingUnits[unitID]) or 0
        if tries < RETRY_MAX_ATTEMPTS then
            pendingUnits[unitID] = tries + 1
        end
    end

    local function trimPendingUnits(maxRaidSize)
        for unitID in pairs(pendingUnits) do
            local idx = tonumber(strmatch(unitID, "^raid(%d+)$")) or 0
            if idx <= 0 or idx > maxRaidSize then
                pendingUnits[unitID] = nil
            end
        end
    end

    local function hasRetryablePendingUnits()
        for _, tries in pairs(pendingUnits) do
            if (tonumber(tries) or 0) < RETRY_MAX_ATTEMPTS then
                return true
            end
        end
        return false
    end

    local function schedulePendingUnitRetry()
        if not hasRetryablePendingUnits() then
            return
        end

        cancelPendingUnitRetryTimer()
        module.pendingUnitRetryHandle = addon.NewTimer(RETRY_DELAY_SECONDS, function()
            module.pendingUnitRetryHandle = nil
            if not addon.IsInRaid() then
                return
            end
            addon:RAID_ROSTER_UPDATE(true)
        end)
    end

    local function finalizeRosterDelta(delta)
        if #delta.joined == 0 then
            delta.joined = nil
        end
        if #delta.updated == 0 then
            delta.updated = nil
        end
        if #delta.left == 0 then
            delta.left = nil
        end
        if #delta.unresolved == 0 then
            delta.unresolved = nil
        end
        if delta.joined or delta.updated or delta.left or delta.unresolved then
            return delta
        end
        return nil
    end

    local function ensureRealmPlayerMeta(realm)
        KRT_Players[realm] = KRT_Players[realm] or {}
        return KRT_Players[realm]
    end

    local function getSyntheticRosterState(raidNum)
        local debugState = addon.State and addon.State.debug or nil
        local syntheticByRaid = debugState and debugState.syntheticByRaid or nil
        if type(syntheticByRaid) ~= "table" then
            return nil
        end
        return syntheticByRaid[tonumber(raidNum) or -1]
    end

    local function isSyntheticRosterPlayer(name, raidNum)
        local syntheticState = getSyntheticRosterState(raidNum)
        if type(syntheticState) ~= "table" or not name then
            return false
        end
        return syntheticState[name] == true
    end

    local function upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
        if not (realmPlayers and name and unitID) then
            return
        end

        local known = realmPlayers[name]
        if not known then
            known = {}
            realmPlayers[name] = known
        end

        known.name = name
        known.level = level or 0
        known.race = race
        known.raceL = raceL
        known.class = class or "UNKNOWN"
        known.classL = classL
        known.sex = UnitSex(unitID) or 0
    end

    local function findRaidPlayerByNid(raid, playerNid)
        local nid = tonumber(playerNid)
        if not nid or nid <= 0 then
            return nil
        end

        local players = raid and raid.players or {}
        for i = #players, 1, -1 do
            local player = players[i]
            if player and tonumber(player.playerNid) == nid then
                return player, i
            end
        end
        return nil
    end

    local function resolveLootLooterName(raid, loot)
        if type(loot) ~= "table" then
            return nil
        end
        local looterNid = tonumber(loot.looterNid)
        if looterNid and looterNid > 0 then
            local player = findRaidPlayerByNid(raid, looterNid)
            if player and player.name then
                return player.name
            end
        end
        return nil
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

    local function findUpgradeablePassiveLootEntry(raid, itemLink, looter, rollSessionId)
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
                local lootLooter = resolveLootLooterName(raid, loot)
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

    local function upgradeLoggedPassiveLootRoll(itemLink, looter, rollType, rollValue, rollSessionId)
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

        local loot = findUpgradeablePassiveLootEntry(raid, itemLink, looter, rollSessionId)
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

    local function buildDefaultRaidPlayer(name)
        return {
            name = name,
            rank = 0,
            subgroup = 1,
            class = "UNKNOWN",
            join = Time.GetCurrentTime(),
            leave = nil,
            count = 0,
        }
    end

    local function ensureRaidPlayerNid(name, raidNum)
        local resolvedName = Strings.NormalizeName(name, true) or name
        if not resolvedName or resolvedName == "" then
            return 0, resolvedName
        end

        local playerNid = module:GetPlayerID(resolvedName, raidNum)
        if playerNid > 0 then
            return playerNid, resolvedName
        end

        module:AddPlayer(buildDefaultRaidPlayer(resolvedName), raidNum)
        playerNid = module:GetPlayerID(resolvedName, raidNum)
        return playerNid, resolvedName
    end

    local function resolveRaidDifficulty(instanceDiff)
        local diff = tonumber(instanceDiff)
        local _, instanceType, liveDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if instanceType ~= "raid" then
            return diff
        end

        liveDiff = tonumber(liveDiff)
        if isDyn then
            local baseDiff = liveDiff or diff
            if baseDiff then
                return baseDiff + (2 * (tonumber(dynDiff) or 0))
            end
            return nil
        end

        -- Prefer live difficulty from GetInstanceInfo(): event payload can be stale during
        -- automatic fallback (for example 25H requested, 25N applied by the instance).
        return liveDiff or diff
    end

    local function getRaidSizeFromDifficulty(instanceDiff)
        local diff = tonumber(instanceDiff)
        if not diff then
            return nil
        end
        return (diff % 2 == 0) and 25 or 10
    end

    local function cancelRaidInstanceChecks()
        for idx, handle in pairs(raidInstanceCheckHandles) do
            addon.CancelTimer(handle, true)
            raidInstanceCheckHandles[idx] = nil
        end
    end

    local function runLiveRaidInstanceCheck()
        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        if instanceType ~= "raid" then
            return
        end
        if L.RaidZones[instanceName] == nil then
            return
        end
        module:Check(instanceName, instanceDiff)
    end

    local function createRaidSessionWithReason(instanceName, newSize, instanceDiff, isCreate)
        local created = module:Create(instanceName, newSize, instanceDiff)
        if not created then
            return false
        end
        addon:info(L.StrNewRaidSessionChange)
        local template = isCreate and Diag.D.LogRaidSessionCreate or Diag.D.LogRaidSessionChange
        addon:debug(template:format(tostring(instanceName), newSize, tonumber(instanceDiff) or -1))
        return true
    end

    local function shouldIgnoreBossKillNpcId(npcId)
        if type(IgnoredMobs.Contains) ~= "function" then
            return false
        end
        return IgnoredMobs.Contains(npcId)
    end

    local function findRecentBossKillByName(raid, bossName, now)
        if not raid or not bossName then
            return nil, nil
        end

        local bossKills = raid.bossKills or {}
        for i = #bossKills, 1, -1 do
            local bossKill = bossKills[i]
            local killTime = tonumber(bossKill and bossKill.time) or 0
            local delta = now - killTime
            if delta > BOSS_KILL_DEDUPE_WINDOW_SECONDS then
                return nil, nil
            end
            if delta >= 0 and bossKill and bossKill.name == bossName then
                return bossKill, delta
            end
        end
        return nil, nil
    end

    local function findRecentBossContext(raid, now)
        if not raid then
            return nil, nil
        end

        local bossKills = raid.bossKills or {}
        for i = #bossKills, 1, -1 do
            local bossKill = bossKills[i]
            local killTime = tonumber(bossKill and bossKill.time) or 0
            local delta = now - killTime
            if delta > BOSS_KILL_DEDUPE_WINDOW_SECONDS then
                return nil, nil
            end

            local bossName = bossKill and (bossKill.name or bossKill.boss) or nil
            local bossNid = tonumber(bossKill and bossKill.bossNid) or 0
            if delta >= 0 and bossNid > 0 and bossName and bossName ~= "_TrashMob_" then
                return bossKill, delta
            end
        end

        return nil, nil
    end

    local function clearBossEventContext()
        raidState.bossEventContext = nil
    end

    local function setBossEventContext(raidNum, bossNid, bossName, source, seenAt)
        raidNum = tonumber(raidNum) or 0
        bossNid = tonumber(bossNid) or 0
        if raidNum <= 0 or bossNid <= 0 or not bossName then
            clearBossEventContext()
            return nil
        end

        raidState.bossEventContext = {
            raidNum = raidNum,
            bossNid = bossNid,
            name = bossName,
            source = source or "event",
            seenAt = tonumber(seenAt) or Time.GetCurrentTime(),
        }

        addon:debug(Diag.D.LogBossEventContextSet:format(tostring(bossName), bossNid, raidNum, tostring(source or "event")))

        return raidState.bossEventContext
    end

    local function recoverBossEventContext(raidNum, now)
        local bossEventContext = raidState.bossEventContext
        if type(bossEventContext) ~= "table" then
            return 0
        end

        local contextRaidNum = tonumber(bossEventContext.raidNum) or 0
        local contextBossNid = tonumber(bossEventContext.bossNid) or 0
        local delta = (tonumber(now) or 0) - (tonumber(bossEventContext.seenAt) or 0)

        if contextRaidNum ~= (tonumber(raidNum) or 0) or contextBossNid <= 0 then
            clearBossEventContext()
            return 0
        end

        if delta < 0 or delta > BOSS_EVENT_CONTEXT_TTL_SECONDS then
            clearBossEventContext()
            return 0
        end

        Core.SetLastBoss(contextBossNid)
        addon:debug(
            Diag.D.LogBossEventContextRecovered:format(tostring(bossEventContext.name), contextBossNid, tonumber(delta) or -1, tostring(bossEventContext.source or "event"))
        )

        return contextBossNid
    end

    local function recoverRecentBossContext(raid, now)
        local bossKill, delta = findRecentBossContext(raid, now)
        local bossNid = tonumber(bossKill and bossKill.bossNid) or 0
        if bossNid <= 0 then
            return 0
        end

        Core.SetLastBoss(bossNid)
        addon:debug(Diag.D.LogBossRecentContextRecovered:format(tostring(bossKill.name or bossKill.boss), bossNid, tonumber(delta) or -1))
        return bossNid
    end

    local function recoverBossContextFromCurrentTarget()
        if not Core.GetCurrentRaid() or Core.GetLastBoss() then
            return 0
        end

        local targetGuid = UnitGUID and UnitGUID("target") or nil
        local npcId = targetGuid and addon.GetCreatureId and addon.GetCreatureId(targetGuid) or nil
        local bossLib = addon.BossIDs
        local bossIds = bossLib and bossLib.BossIDs
        if not (npcId and bossIds and bossIds[npcId]) then
            return 0
        end
        if shouldIgnoreBossKillNpcId(npcId) then
            return 0
        end

        local targetName = UnitName and UnitName("target") or nil
        local bossName = targetName
        if isUnknownName(bossName) then
            bossName = nil
        end
        if not bossName and bossLib and bossLib.GetBossName then
            bossName = bossLib:GetBossName(npcId)
        end
        if not bossName then
            return 0
        end

        addon:debug(Diag.D.LogBossLootTargetMatched:format(tonumber(npcId) or -1, tostring(bossName)))
        return module:AddBoss(bossName, nil, nil, npcId)
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
        local lootService = getLootService()
        local pendingAwardTtl = passiveGroupLoot and GROUP_LOOT_PENDING_AWARD_TTL_SECONDS or PENDING_AWARD_TTL_SECONDS
        -- In ML mode, block stale GL:* pending awards only when the current item
        -- maps to an active roll session. Without a preferred session, keep GL
        -- pending lookup enabled to preserve passive Group Loot logging in mixed
        -- transition windows (Group Loot -> ML).
        local allowGroupLootPendingAwards = passiveGroupLoot or not preferredRollSessionId
        local pendingAward = lootService
            and lootService:RemovePendingAward(itemLink, player, pendingAwardTtl, preferredRollSessionId, passiveGroupLoot, allowGroupLootPendingAwards)
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
                local passiveRoll = getPassiveLootRollEntry(itemLink)
                rollSessionId = passiveRoll and passiveRoll.sessionId or nil
                outcome.matchedPassiveRoll = passiveRoll ~= nil
            else
                rollSessionId = preferredRollSessionId
            end
        end

        -- Resolve award source: pending award/group-loot choice -> manual ML tag -> current roll type.
        if not rollType then
            if module:IsMasterLooter() and not lootState.fromInventory then
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
            local rollsService = getRollsService()
            rollValue = rollsService and rollsService:HighestRoll() or 0
        end

        return rollType, rollValue, rollSessionId, outcome
    end

    local function buildLootRecord(raid, itemId, itemName, itemString, itemLink, itemRarity, itemTexture, itemCount, looterNid, rollType, rollValue, rollSessionId)
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
            bossNid = tonumber(Core.GetLastBoss()) or 0,
            time = Time.GetCurrentTime(),
        }

        return lootInfo, lootNid
    end

    -- ----- Public methods ----- --

    function module:GetRosterVersion()
        return rosterVersion
    end

    function module:InvalidateMasterLootCandidateCache()
        invalidateMasterLootCandidateCache()
    end

    function module:ResolveMasterLootCandidateIndex(itemLink, playerName)
        local cache = ensureMasterLootCandidateCache(itemLink)
        local candidateIndex = cache.indexByName[playerName]
        if not candidateIndex then
            addon:debug(Diag.D.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            cache = buildMasterLootCandidateCache(itemLink)
            candidateIndex = cache.indexByName[playerName]
        end
        return candidateIndex
    end

    function module:HasMasterLootCandidates(itemLink)
        local cache = ensureMasterLootCandidateCache(itemLink)
        return next(cache.indexByName) ~= nil
    end

    function module:PublishRosterDelta(delta, raidNum)
        local payload

        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return nil, nil
        end

        if type(delta) ~= "table" then
            delta = {}
        end

        payload = {
            joined = type(delta.joined) == "table" and delta.joined or {},
            updated = type(delta.updated) == "table" and delta.updated or {},
            left = type(delta.left) == "table" and delta.left or {},
            unresolved = type(delta.unresolved) == "table" and delta.unresolved or {},
        }

        rosterVersion = rosterVersion + 1
        payload = finalizeRosterDelta(payload) or payload
        Bus.TriggerEvent(InternalEvents.RaidRosterDelta, payload, rosterVersion, raidNum)
        return rosterVersion, payload
    end

    function module:GetRaid(raidNum)
        if raidNum == nil then
            raidNum = Core.GetCurrentRaid and Core.GetCurrentRaid() or nil
        end
        if not raidNum then
            return nil, nil
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.GetRaid", { "GetRaidByIndex" })
        if raidStore then
            return raidStore:GetRaidByIndex(raidNum)
        end
        return nil, raidNum
    end

    function module:ResolveRaid(raidNum)
        return module:GetRaid(raidNum)
    end

    function module:InvalidateRaidRuntime(raidNum)
        local raid = Core.EnsureRaidById(raidNum)
        if raid then
            invalidateRaidRuntime(raid)
        end
    end

    function module:IsSyntheticPlayerActive(name, raidNum)
        local currentRaidId = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(currentRaidId)
        local resolvedName

        if not raid or not name then
            return false
        end

        resolvedName = Strings.NormalizeName(name, true)
        if not resolvedName or resolvedName == "" then
            return false
        end

        if not isSyntheticRosterPlayer(resolvedName, currentRaidId) then
            return false
        end

        return module:GetPlayerID(resolvedName, currentRaidId) > 0
    end

    function module:CancelInstanceChecks()
        cancelRaidInstanceChecks()
    end

    function module:ScheduleInstanceChecks()
        cancelRaidInstanceChecks()

        -- Immediate live check, then short retries to catch delayed server fallback updates.
        runLiveRaidInstanceCheck()

        for i = 1, #RAID_INSTANCE_CHECK_DELAYS do
            local idx = i
            local delaySeconds = RAID_INSTANCE_CHECK_DELAYS[idx]
            raidInstanceCheckHandles[idx] = addon.NewTimer(delaySeconds, function()
                raidInstanceCheckHandles[idx] = nil
                runLiveRaidInstanceCheck()
            end)
        end
    end

    function module:IsIgnoredItem(itemId)
        if type(IgnoredItems.Contains) ~= "function" then
            return false
        end
        return IgnoredItems.Contains(itemId)
    end

    -- Updates the current raid roster, adding new players and marking those who left.
    -- Returns rosterChanged, delta where delta contains joined/updated/left/unresolved lists.
    function module:UpdateRaidRoster()
        if addon.IsInRaid() then
            local instanceName, instanceType, instanceDiff = GetInstanceInfo()
            if instanceType == "raid" and L.RaidZones[instanceName] ~= nil then
                module:Check(instanceName, instanceDiff)
            end
        end

        if not Core.GetCurrentRaid() then
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            return false
        end
        -- Cancel any pending roster update timer.
        cancelScheduledRosterRefresh()

        local rosterChanged = false
        local delta = {
            joined = {},
            updated = {},
            left = {},
            unresolved = {},
        }

        if not addon.IsInRaid() then
            rosterChanged = true
            numRaid = 0
            addon:debug(Diag.D.LogRaidLeftGroupEndSession)
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            module:End()
            if rosterChanged then
                rosterVersion = rosterVersion + 1
            end
            return rosterChanged
        end

        local currentRaidId = Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(currentRaidId)
        if not raid then
            return false
        end

        local realm = Core.GetRealmName()
        local realmPlayers = ensureRealmPlayerMeta(realm)
        local raidStore = Core.GetRaidStoreOrNil("Raid.UpdateRaidRoster", { "EnsureRaidRuntime" })
        local runtime = raidStore and raidStore:EnsureRaidRuntime(raid) or nil
        local playersByName = runtime and runtime.playersByName or {}

        local prevNumRaid = numRaid
        local n = GetNumRaidMembers()

        -- Keep local raid-size cache in sync.
        numRaid = n
        if n ~= prevNumRaid then
            rosterChanged = true
        end

        if n == 0 then
            rosterChanged = true
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            module:End()
            rosterVersion = rosterVersion + 1
            return rosterChanged
        end

        local prevUnitsByName = liveUnitsByName
        local prevNamesByUnit = liveNamesByUnit
        local nextUnitsByName = {}
        local nextNamesByUnit = {}
        local seen = {}
        local now = Time.GetCurrentTime()
        local hasUnknownUnits = false

        for i = 1, n do
            local unitID = "raid" .. tostring(i)
            local name, rank, subgroup, level, classL, class = getRaidRosterInfo(i)
            if isUnknownName(name) then
                hasUnknownUnits = true
                markPendingUnit(unitID)
                local prevName = prevNamesByUnit[unitID]
                if prevName and not nextUnitsByName[prevName] then
                    seen[prevName] = true
                    nextUnitsByName[prevName] = unitID
                    nextNamesByUnit[unitID] = prevName
                end
                tinsert(delta.unresolved, { unitID = unitID, name = prevName })
            else
                pendingUnits[unitID] = nil
                nextUnitsByName[name] = unitID
                nextNamesByUnit[unitID] = name

                local raceL, race = UnitRace(unitID)
                local oldUnitID = prevUnitsByName[name]
                local prevPlayer = playersByName[name]
                local active = prevPlayer and prevPlayer.leave == nil
                local player = prevPlayer

                if not active then
                    rosterChanged = true
                    local newRank = rank or (prevPlayer and prevPlayer.rank) or 0
                    local newSubgroup = subgroup or (prevPlayer and prevPlayer.subgroup) or 1
                    local newClass = class or (prevPlayer and prevPlayer.class) or "UNKNOWN"
                    player = {
                        playerNid = prevPlayer and prevPlayer.playerNid or nil,
                        name = name,
                        rank = newRank,
                        subgroup = newSubgroup,
                        class = newClass,
                        join = now,
                        leave = nil,
                        count = (prevPlayer and prevPlayer.count) or 0,
                    }
                    tinsert(delta.joined, {
                        name = name,
                        unitID = unitID,
                        rank = newRank,
                        subgroup = newSubgroup,
                        class = newClass,
                    })
                else
                    local oldRank = player.rank or 0
                    local oldSubgroup = player.subgroup or 1
                    local oldClass = player.class or "UNKNOWN"
                    local newRank = rank or oldRank
                    local newSubgroup = subgroup or oldSubgroup
                    local newClass = class or oldClass
                    local fieldChanged = (oldRank ~= newRank) or (oldSubgroup ~= newSubgroup) or (oldClass ~= newClass)
                    local unitChanged = oldUnitID and (oldUnitID ~= unitID)

                    if fieldChanged or unitChanged then
                        rosterChanged = true
                        tinsert(delta.updated, {
                            name = name,
                            oldUnitID = oldUnitID,
                            unitID = unitID,
                            oldRank = oldRank,
                            rank = newRank,
                            oldSubgroup = oldSubgroup,
                            subgroup = newSubgroup,
                            oldClass = oldClass,
                            class = newClass,
                        })
                    end

                    player.rank = newRank
                    player.subgroup = newSubgroup
                    player.class = newClass
                end

                -- Keep raid.players consistent even if rows were manually edited.
                module:AddPlayer(player)

                seen[name] = true

                upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
            end
        end

        trimPendingUnits(n)
        liveUnitsByName = nextUnitsByName
        liveNamesByUnit = nextNamesByUnit

        -- Mark leavers
        for pname, p in pairs(playersByName) do
            if p.leave == nil and not seen[pname] then
                if isSyntheticRosterPlayer(pname, currentRaidId) then
                    seen[pname] = true
                else
                    p.leave = now
                    rosterChanged = true
                    tinsert(delta.left, {
                        name = pname,
                        unitID = prevUnitsByName[pname],
                        rank = p.rank or 0,
                        subgroup = p.subgroup or 1,
                        class = p.class or "UNKNOWN",
                    })
                end
            end
        end

        if hasUnknownUnits then
            schedulePendingUnitRetry()
        else
            resetPendingUnitRetry()
        end

        delta = finalizeRosterDelta(delta)

        if rosterChanged then
            rosterVersion = rosterVersion + 1
            addon:debug(Diag.D.LogRaidRosterUpdate:format(rosterVersion, n))
        end
        return rosterChanged, delta
    end

    -- Creates a new raid log entry.
    function module:Create(zoneName, raidSize, raidDiff)
        if not addon.IsInRaid() then
            return false
        end

        local num = GetNumRaidMembers()
        if num == 0 then
            return false
        end

        if Core.GetCurrentRaid() then
            self:End()
        end

        numRaid = num

        local realm = Core.GetRealmName()
        local realmPlayers = ensureRealmPlayerMeta(realm)
        local currentTime = Time.GetCurrentTime()

        local instanceDiff = tonumber(raidDiff)
        if not instanceDiff then
            instanceDiff = resolveRaidDifficulty()
        end

        local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("Raid.Create", { "CreateRaidRecord", "InsertRaid" }) or nil
        if not raidStore then
            return false
        end

        local raidInfo = raidStore:CreateRaidRecord({
            realm = realm,
            zone = zoneName,
            size = raidSize,
            difficulty = tonumber(instanceDiff) or nil,
            startTime = currentTime,
        })

        for i = 1, num do
            local name, rank, subgroup, level, classL, class = getRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)

                local p = {
                    playerNid = raidInfo.nextPlayerNid,
                    name = name,
                    rank = rank or 0,
                    subgroup = subgroup or 1,
                    class = class or "UNKNOWN",
                    join = Time.GetCurrentTime(),
                    leave = nil,
                    count = 0,
                }
                raidInfo.nextPlayerNid = (tonumber(raidInfo.nextPlayerNid) or 1) + 1

                tinsert(raidInfo.players, p)

                upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
            end
        end

        local _, raidId = raidStore:InsertRaid(raidInfo)
        if not raidId then
            return false
        end
        Core.SetCurrentRaid(raidId)
        clearBossEventContext()
        -- New session context: force version-gated roster consumers (e.g. Master dropdowns) to rebuild.
        rosterVersion = rosterVersion + 1
        resetPendingUnitRetry()
        resetLiveUnitCaches()

        addon:info(Diag.I.LogRaidCreated:format(Core.GetCurrentRaid() or -1, tostring(zoneName), tonumber(raidSize) or -1, #raidInfo.players))

        Bus.TriggerEvent(InternalEvents.RaidCreate, Core.GetCurrentRaid())

        -- Schedule one delayed roster refresh.
        scheduleRosterRefresh()
        return true
    end

    -- Stable-ID helpers (bossNid / lootNid).
    -- Fresh SavedVariables only. Schema is normalized by Core.EnsureRaidSchema().

    function module:EnsureStableIds(raidNum)
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)
    end

    function module:GetBossByNid(bossNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or bossNid == nil then
            return nil
        end
        Core.EnsureRaidSchema(raid)

        bossNid = tonumber(bossNid) or 0
        if bossNid <= 0 then
            return nil
        end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local b = bosses[i]
            if b and tonumber(b.bossNid) == bossNid then
                return b, i
            end
        end
        return nil
    end

    function module:GetLootByNid(lootNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or lootNid == nil then
            return nil
        end
        Core.EnsureRaidSchema(raid)

        lootNid = tonumber(lootNid) or 0
        if lootNid <= 0 then
            return nil
        end

        local loot = raid.loot
        for i = 1, #loot do
            local l = loot[i]
            if l and tonumber(l.lootNid) == lootNid then
                return l, i
            end
        end
        return nil
    end

    -- Ends the current raid log entry, marking end time.
    function module:End()
        cancelRaidInstanceChecks()
        resetPendingUnitRetry()
        resetLiveUnitCaches()
        if not Core.GetCurrentRaid() then
            return
        end
        -- Stop any pending roster update when ending the raid
        cancelScheduledRosterRefresh()
        local currentTime = Time.GetCurrentTime()
        local raid = Core.EnsureRaidById(Core.GetCurrentRaid())
        if raid then
            local duration = currentTime - (raid.startTime or currentTime)
            addon:info(
                Diag.I.LogRaidEnded:format(
                    Core.GetCurrentRaid() or -1,
                    tostring(raid.zone),
                    tonumber(raid.size) or -1,
                    raid.bossKills and #raid.bossKills or 0,
                    raid.loot and #raid.loot or 0,
                    duration
                )
            )

            for _, v in pairs(raid.players) do
                if not v.leave then
                    v.leave = currentTime
                end
            end
            raid.endTime = currentTime
        end
        Core.SetCurrentRaid(nil)
        Core.SetLastBoss(nil)
        clearBossEventContext()
    end

    -- Checks the current raid status and creates a new session if needed.
    function module:Check(instanceName, instanceDiff)
        instanceDiff = resolveRaidDifficulty(instanceDiff)
        local newSize = getRaidSizeFromDifficulty(instanceDiff)
        addon:debug(Diag.D.LogRaidCheck:format(tostring(instanceName), tostring(instanceDiff), tostring(Core.GetCurrentRaid())))
        if not newSize then
            return
        end

        if not Core.GetCurrentRaid() then
            module:Create(instanceName, newSize, instanceDiff)
            return
        end

        local current = Core.EnsureRaidById(Core.GetCurrentRaid())
        if not current then
            createRaidSessionWithReason(instanceName, newSize, instanceDiff, true)
            return
        end

        local shouldCreate = current.zone ~= instanceName or tonumber(current.size) ~= newSize or tonumber(current.difficulty) ~= instanceDiff

        if shouldCreate then
            createRaidSessionWithReason(instanceName, newSize, instanceDiff, false)
        end
    end

    -- Performs an initial raid check on player login.
    function module:FirstCheck()
        -- Cancel any pending first-check timer before starting a new one
        addon.CancelTimer(module.firstCheckHandle, true)
        module.firstCheckHandle = nil
        if not addon.IsInGroup() then
            return
        end

        if Core.GetCurrentRaid() and module:CheckPlayer(Core.GetPlayerName(), Core.GetCurrentRaid()) then
            -- Restart the roster update timer: cancel the old one and schedule a new one
            scheduleRosterRefresh()
            return
        end

        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        addon:debug(
            Diag.D.LogRaidFirstCheck:format(
                tostring(addon.IsInGroup()),
                tostring(Core.GetCurrentRaid() ~= nil),
                tostring(instanceName),
                tostring(instanceType),
                tostring(instanceDiff)
            )
        )
        if instanceType == "raid" then
            module:Check(instanceName, instanceDiff)
            return
        end
    end

    -- Adds a player to the raid log.
    function module:AddPlayer(t, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not t or not t.name then
            return
        end
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local players = module:GetPlayers(raidNum)
        local found = false
        local nextPlayerNid = tonumber(raid.nextPlayerNid) or 1

        for i, p in ipairs(players) do
            if t.name == p.name then
                -- Preserve count if present
                t.count = t.count or p.count or 0
                t.playerNid = tonumber(t.playerNid) or tonumber(p.playerNid) or nextPlayerNid
                if tonumber(t.playerNid) >= nextPlayerNid then
                    raid.nextPlayerNid = tonumber(t.playerNid) + 1
                end
                raid.players[i] = t
                found = true
                break
            end
        end

        if not found then
            t.count = t.count or 0
            t.playerNid = tonumber(t.playerNid) or nextPlayerNid
            raid.nextPlayerNid = tonumber(t.playerNid) + 1
            tinsert(raid.players, t)
            addon:trace(Diag.D.LogRaidPlayerJoin:format(tostring(t.name), tonumber(raidNum) or -1))
        else
            addon:trace(Diag.D.LogRaidPlayerRefresh:format(tostring(t.name), tonumber(raidNum) or -1))
        end
        invalidateRaidRuntime(raid)
    end

    -- Adds a boss kill to the active raid log.
    function module:AddBoss(bossName, manDiff, raidNum, sourceNpcId)
        sourceNpcId = tonumber(sourceNpcId)
        if sourceNpcId and shouldIgnoreBossKillNpcId(sourceNpcId) then
            addon:trace(Diag.D.LogBossUnitDiedIgnored:format(sourceNpcId, tostring(bossName)))
            return 0
        end

        if isUnknownName(bossName) then
            bossName = nil
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not bossName then
            addon:debug(Diag.D.LogBossAddSkipped:format(tostring(raidNum), tostring(bossName)))
            return 0
        end

        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end
        Core.EnsureRaidSchema(raid)

        local instanceDiff = resolveRaidDifficulty()
        if manDiff then
            instanceDiff = (raid.size == 10) and 1 or 2
            if Strings.NormalizeLower(manDiff, true) == "h" then
                instanceDiff = instanceDiff + 2
            end
        end

        local currentTime = Time.GetCurrentTime()
        local bossSource = sourceNpcId and "UNIT_DIED" or "YELL"
        local existingBoss, delta = findRecentBossKillByName(raid, bossName, currentTime)
        if existingBoss then
            local existingBossNid = tonumber(existingBoss.bossNid) or 0
            if existingBossNid > 0 then
                Core.SetLastBoss(existingBossNid)
                setBossEventContext(raidNum, existingBossNid, bossName, bossSource, currentTime)
            end
            addon:trace(Diag.D.LogBossDuplicateSuppressed:format(tostring(bossName), sourceNpcId or -1, existingBossNid, tonumber(delta) or -1))
            return existingBossNid
        end

        local players = {}
        local seenPlayers = {}
        for unit in addon.UnitIterator(true) do
            if UnitIsConnected(unit) then
                local name = UnitName(unit)
                if name then
                    local resolvedName = Strings.NormalizeName(name, true) or name
                    local playerNid = ensureRaidPlayerNid(resolvedName, raidNum)
                    if playerNid > 0 and not seenPlayers[playerNid] then
                        seenPlayers[playerNid] = true
                        tinsert(players, playerNid)
                    end
                end
            end
        end

        local bossNid = tonumber(raid.nextBossNid) or 1
        raid.nextBossNid = bossNid + 1

        local killInfo = {
            bossNid = bossNid,
            name = bossName,
            difficulty = instanceDiff,
            mode = (instanceDiff == 3 or instanceDiff == 4) and "h" or "n",
            players = players,
            time = currentTime,
            hash = Base64.Encode(raidNum .. "|" .. bossName .. "|" .. bossNid),
        }

        tinsert(raid.bossKills, killInfo)
        invalidateRaidRuntime(raid)
        Core.SetLastBoss(bossNid)
        setBossEventContext(raidNum, bossNid, bossName, bossSource, currentTime)
        addon:info(Diag.I.LogBossLogged:format(tostring(bossName), tonumber(instanceDiff) or -1, tonumber(raidNum) or -1, #players))
        addon:debug(Diag.D.LogBossLastBossHash:format(tonumber(Core.GetLastBoss()) or -1, tostring(killInfo.hash)))
        return bossNid
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

        if not Core.GetLastBoss() then
            local currentTime = Time.GetCurrentTime()
            local recoveredBossNid = recoverBossEventContext(currentRaidId, currentTime)
            if recoveredBossNid <= 0 then
                recoveredBossNid = recoverRecentBossContext(raid, currentTime)
            end
            if recoveredBossNid <= 0 then
                recoveredBossNid = recoverBossContextFromCurrentTarget()
            end
            if recoveredBossNid <= 0 then
                addon:debug(Diag.D.LogBossNoContextTrash)
                self:AddBoss("_TrashMob_")
            end
        end

        local passiveGroupLoot = isPassiveGroupLootMethod()
        local isPassiveWinnerMessage = passiveGroupLoot and isPassiveLootWinnerMessage(msg)
        local rollSessionId
        local rollOutcome
        rollType, rollValue, rollSessionId, rollOutcome = resolveLootRollOutcome(itemLink, itemString, itemId, player, rollType, rollValue)

        if passiveGroupLoot and not (rollOutcome and rollOutcome.consumedPendingAward) and hasLoggedPassiveLoot(itemLink, player, rollSessionId) then
            return
        end

        local looterNid
        looterNid, player = ensureRaidPlayerNid(player, currentRaidId)

        local lootInfo, lootNid = buildLootRecord(raid, itemId, itemName, itemString, itemLink, itemRarity, itemTexture, itemCount, looterNid, rollType, rollValue, rollSessionId)

        -- LootCounter (MS only): increment the winner's count when the loot is actually awarded.
        -- This runs off the authoritative LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event.
        if tonumber(rollType) == rollTypes.MAINSPEC then
            module:AddPlayerCount(player, itemCount, currentRaidId)
        end

        if passiveGroupLoot and isPassiveWinnerMessage then
            rememberLoggedPassiveLoot(itemLink, player, rollSessionId)
        end

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        consumePassiveLootRollEntry(rollSessionId)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, currentRaidId, lootInfo)
        addon:debug(Diag.D.LogLootLogged:format(tonumber(currentRaidId) or -1, tostring(itemId), tostring(lootInfo.bossNid), tostring(player)))
    end

    function module:AddPassiveLootRoll(rollId, rollTime)
        if not Core.GetCurrentRaid() or not isPassiveGroupLootMethod() then
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

        if existing then
            existing.itemLink = itemLink
            existing.itemKey = getPassiveLootRollItemKey(itemLink)
            existing.expiresAt = expiresAt
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
        }
        state.nextSessionId = state.nextSessionId + 1
        list[#list + 1] = entry
        state.bySessionId[entry.sessionId] = entry
        state.byRollId[resolvedRollId] = entry
        return entry
    end

    function module:AddGroupLootMessage(msg)
        if type(msg) ~= "string" or msg == "" or not isPassiveGroupLootMethod() then
            return nil
        end

        local lootService = getLootService()
        local canQueuePendingAward = lootService and lootService.AddPendingAward
        if canQueuePendingAward then
            for i = 1, #GROUP_LOOT_RULES do
                local rule = GROUP_LOOT_RULES[i]
                local playerName, itemLink, rollId = parseGroupLootSelection(msg, rule)
                if playerName and itemLink then
                    local rollSessionId, expiresAt = resolvePassivePendingAwardContext(itemLink, rollId)
                    lootService:AddPendingAward(itemLink, playerName, rule.rollType, 0, rollSessionId, expiresAt)
                    addon:debug(Diag.D.LogLootGroupSelectionQueued:format(rule.label, tostring(playerName), tostring(itemLink)))
                    return "selection"
                end
            end

            local rollPlayer, rollItemLink, rollType, rollValue, rollId = parseGroupLootRoll(msg)
            if rollPlayer and rollItemLink and rollType then
                local rule = getGroupLootRule(rollType)
                local rollSessionId, expiresAt = resolvePassivePendingAwardContext(rollItemLink, rollId)
                if not upgradeLoggedPassiveLootRoll(rollItemLink, rollPlayer, rollType, rollValue, rollSessionId) then
                    lootService:AddPendingAward(rollItemLink, rollPlayer, rollType, rollValue, rollSessionId, expiresAt)
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
                if not upgradeLoggedPassiveLootRoll(itemLink, playerName, winnerRollType, winnerRollValue, rollSessionId) and (winnerRollType ~= nil or winnerRollValue ~= nil) then
                    lootService:AddPendingAward(itemLink, playerName, winnerRollType, winnerRollValue, rollSessionId, expiresAt)
                elseif lootService.RefreshPendingAward then
                    lootService:RefreshPendingAward(itemLink, playerName, GROUP_LOOT_PENDING_AWARD_TTL_SECONDS, rollSessionId, expiresAt)
                end
            end
            addon:debug(Diag.D.LogLootGroupWinnerDetected:format(tostring(playerName), winnerTypeLabel, winnerRollLabel, tostring(itemLink)))
            return "winner"
        end

        return nil
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

        local looterNid
        looterNid, looter = ensureRaidPlayerNid(looter, raidNum)

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
            bossNid = tonumber(bossNid) or tonumber(Core.GetLastBoss()) or 0,
            time = Time.GetCurrentTime(),
            source = source or "TRADE_ONLY",
        }

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, raidNum, lootInfo)
        addon:debug(Diag.D.LogLootTradeOnlyLogged:format(tonumber(raidNum) or -1, tostring(itemId), tostring(lootNid), tostring(looter), count, tostring(lootInfo.source)))
        return lootNid
    end

    -- Player count API.

    function module:GetPlayerCountByNid(playerNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end
        Core.EnsureRaidSchema(raid)

        local player = findRaidPlayerByNid(raid, playerNid)
        if not player then
            return 0
        end
        return tonumber(player.count) or 0
    end

    function module:SetPlayerCountByNid(playerNid, value, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local player = findRaidPlayerByNid(raid, playerNid)
        if not player then
            return
        end

        value = tonumber(value) or 0
        -- Hard clamp: counts are always non-negative.
        if value < 0 then
            value = 0
        end

        local old = tonumber(player.count) or 0
        player.count = value

        if old ~= value then
            Bus.TriggerEvent(InternalEvents.PlayerCountChanged, player.name, value, old, raidNum)
        end
    end

    function module:AddPlayerCountByNid(playerNid, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        local current = module:GetPlayerCountByNid(playerNid, raidNum) or 0
        local nextVal = current + delta
        if nextVal < 0 then
            nextVal = 0
        end

        module:SetPlayerCountByNid(playerNid, nextVal, raidNum)
    end

    -- Adds (or subtracts) from the per-raid player count.
    -- Used by LootCounter UI and MS auto-counting.
    -- Clamps to 0 (never negative).
    function module:AddPlayerCount(name, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not name then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        -- Normalize/resolve name if possible.
        local ok, fixed = module:CheckPlayer(name, raidNum)
        if ok and fixed then
            name = fixed
        end

        -- Ensure the player exists in the raid log.
        local playerNid
        playerNid, name = ensureRaidPlayerNid(name, raidNum)

        if playerNid == 0 then
            return
        end

        module:AddPlayerCountByNid(playerNid, delta, raidNum)
    end

    function module:GetPlayerCount(name, raidNum)
        if not name then
            return 0
        end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            return 0
        end
        return module:GetPlayerCountByNid(playerNid, raidNum)
    end

    function module:SetPlayerCount(name, value, raidNum)
        if not name then
            return
        end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            return
        end
        module:SetPlayerCountByNid(playerNid, value, raidNum)
    end

    function module:IncrementPlayerCount(name, raidNum)
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            addon:error(L.ErrCannotFindPlayer:format(name))
            return
        end

        local c = module:GetPlayerCountByNid(playerNid, raidNum)
        module:SetPlayerCountByNid(playerNid, c + 1, raidNum)
    end

    function module:DecrementPlayerCount(name, raidNum)
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            addon:error(L.ErrCannotFindPlayer:format(name))
            return
        end

        local c = module:GetPlayerCountByNid(playerNid, raidNum)
        if c <= 0 then
            -- Already at floor; keep it at 0 without spamming errors.
            module:SetPlayerCountByNid(playerNid, 0, raidNum)
            return
        end
        module:SetPlayerCountByNid(playerNid, c - 1, raidNum)
    end

    -- Raid functions.

    function module:IsPlayerInRaid()
        if addon.IsInRaid() then
            return true
        end
        local groupType = addon.GetGroupTypeAndCount()
        if groupType == "raid" then
            return true
        end
        if UnitInRaid("player") then
            return true
        end
        return (GetNumRaidMembers() or 0) > 0
    end

    -- Returns the number of members in the raid.
    function module:GetNumRaid()
        return numRaid
    end

    -- Returns raid size: 10 or 25.
    function module:GetRaidSize()
        local _, _, members = addon.GetGroupTypeAndCount()
        if members == 0 then
            return 0
        end

        local diff = Time.GetDifficulty()
        if diff then
            return (diff == 1 or diff == 3) and 10 or 25
        end

        return members > 20 and 25 or 10
    end

    -- Checks if a raid log is expired (older than the weekly reset).
    function module:Expired(rID)
        local raid = Core.EnsureRaidById(rID)
        if not raid then
            return true
        end

        local startTime = raid.startTime
        local currentTime = Time.GetCurrentTime()
        local week = 604800 -- 7 days in seconds

        if Core.GetNextReset() and Core.GetNextReset() > currentTime then
            return startTime < (Core.GetNextReset() - week)
        end

        return currentTime >= startTime + week
    end

    -- Retrieves all loot for a given raid and optional boss number.
    function module:GetLoot(raidNum, bossNid)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        bossNid = tonumber(bossNid) or 0
        if not raid then
            return {}
        end
        Core.EnsureRaidSchema(raid)

        local loot = raid.loot or {}
        if bossNid <= 0 then
            return loot
        end

        local items = {}
        for _, v in ipairs(loot) do
            if tonumber(v.bossNid) == bossNid then
                tinsert(items, v)
            end
        end
        return items
    end

    -- Retrieves the position of a specific loot item within the raid's loot table.
    function module:GetLootID(itemID, raidNum, holderName)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        itemID = tonumber(itemID)
        if not itemID then
            return 0
        end

        local bossNid = tonumber(Core.GetLastBoss()) or 0
        local loot = raid.loot or {}

        for i = #loot, 1, -1 do
            local v = loot[i]
            if v and tonumber(v.itemId) == itemID then
                local winnerName = resolveLootLooterName(raid, v)
                if not holderName or holderName == "" or winnerName == holderName then
                    if bossNid <= 0 or tonumber(v.bossNid) == bossNid then
                        return tonumber(v.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    function module:GetHeldLootNid(itemLink, raidNum, holderName, bossNid)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or not itemLink then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        local queryBossNid = tonumber(bossNid) or 0
        local _, _, queryItemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local _, _, _, _, queryItemId = string.find(itemLink, ITEM_LINK_PATTERN)
        queryItemId = tonumber(queryItemId)

        local loot = raid.loot or {}
        for i = #loot, 1, -1 do
            local entry = loot[i]
            if entry and tonumber(entry.rollType) == rollTypes.HOLD then
                local winnerName = resolveLootLooterName(raid, entry)
                if (not holderName or holderName == "" or winnerName == holderName) and (queryBossNid <= 0 or tonumber(entry.bossNid) == queryBossNid) then
                    local sameItem = false
                    if queryItemString and entry.itemString and entry.itemString == queryItemString then
                        sameItem = true
                    elseif queryItemId and tonumber(entry.itemId) == queryItemId then
                        sameItem = true
                    elseif entry.itemLink and entry.itemLink == itemLink then
                        sameItem = true
                    end
                    if sameItem then
                        return tonumber(entry.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    function module:GetLootNidByRollSessionId(rollSessionId, raidNum, holderName, bossNid)
        local sessionId = rollSessionId and tostring(rollSessionId) or nil
        if not sessionId or sessionId == "" then
            return 0
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        local queryBossNid = tonumber(bossNid) or 0
        local loot = raid.loot or {}
        for i = #loot, 1, -1 do
            local entry = loot[i]
            if entry and tostring(entry.rollSessionId or "") == sessionId then
                local winnerName = resolveLootLooterName(raid, entry)
                if (not holderName or holderName == "" or winnerName == holderName) and (queryBossNid <= 0 or tonumber(entry.bossNid) == queryBossNid) then
                    return tonumber(entry.lootNid) or 0
                end
            end
        end
        return 0
    end

    -- Retrieves all boss kills for a given raid.
    function module:GetBosses(raidNum, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or not raid.bossKills then
            return {}
        end

        Core.EnsureRaidSchema(raid)

        local bosses = out or {}
        if out then
            twipe(bosses)
        end

        for i = 1, #raid.bossKills do
            local boss = raid.bossKills[i]
            bosses[#bosses + 1] = {
                id = tonumber(boss.bossNid), -- stable selection id
                seq = i, -- display order
                name = boss.name,
                time = boss.time,
                mode = boss.mode or ((boss.difficulty == 3 or boss.difficulty == 4) and "h" or "n"),
            }
        end

        return bosses
    end

    -- Player functions.

    -- Returns players from the raid log. Can be filtered by boss kill.
    function module:GetPlayers(raidNum, bossNid, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return {}
        end

        Core.EnsureRaidSchema(raid)

        local raidPlayers = raid.players or {}

        bossNid = tonumber(bossNid) or 0
        if bossNid > 0 then
            local bossKill = module:GetBossByNid(bossNid, raidNum)
            if bossKill and bossKill.players then
                local players = out or {}
                if out then
                    twipe(players)
                end
                local bossPlayers = {}
                for i = 1, #bossKill.players do
                    local playerNid = tonumber(bossKill.players[i])
                    if playerNid and playerNid > 0 then
                        bossPlayers[playerNid] = true
                    end
                end
                for _, p in ipairs(raidPlayers) do
                    local playerNid = tonumber(p and p.playerNid)
                    if playerNid and bossPlayers[playerNid] then
                        tinsert(players, p)
                    end
                end
                -- Caller releases when using a pooled table.
                return players
            end
        end

        return raidPlayers
    end

    -- Returns LootCounter rows from canonical raid data (unique by player name).
    function module:GetLootCounterRows(raidNum, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        local rows = out or {}
        if out then
            twipe(rows)
        end
        if not raid or not raid.players then
            return rows
        end

        Core.EnsureRaidSchema(raid)

        local seenByName = {}
        for i = #raid.players, 1, -1 do
            local p = raid.players[i]
            if p and p.name and not seenByName[p.name] then
                seenByName[p.name] = true
                rows[#rows + 1] = {
                    playerNid = tonumber(p.playerNid),
                    name = p.name,
                    class = p.class,
                    count = tonumber(p.count) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        return rows
    end

    -- Checks if a player is in the raid log.
    function module:CheckPlayer(name, raidNum)
        local found = false
        local players = module:GetPlayers(raidNum)
        if players ~= nil then
            name = Strings.NormalizeName(name)
            for _, p in ipairs(players) do
                if name == p.name then
                    found = true
                    break
                elseif strlen(name) >= 5 and p.name:startsWith(name) then
                    name = p.name
                    found = true
                    break
                end
            end
        end
        return found, name
    end

    -- Returns the player's stable ID (playerNid) from the raid log.
    function module:GetPlayerID(name, raidNum)
        local playerNid = 0
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        if raid then
            name = Strings.NormalizeName(name or Core.GetPlayerName(), true)
            local players = raid.players or {}
            for i = #players, 1, -1 do
                local p = players[i]
                if p and p.name == name then
                    playerNid = tonumber(p.playerNid) or 0
                    break
                end
            end
        end
        return playerNid
    end

    -- Gets a player's name by stable ID (playerNid).
    function module:GetPlayerName(id, raidNum)
        local name
        raidNum = raidNum or (addon.State and addon.State.selectedRaid) or Core.GetCurrentRaid()
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        if raid then
            local qid = tonumber(id) or id
            local players = raid.players or {}
            for i = 1, #players do
                local p = players[i]
                local pid = p and (tonumber(p.playerNid) or p.playerNid)
                if pid == qid then
                    name = p.name
                    break
                end
            end
        end
        return name
    end

    -- Returns a table of items looted by the selected player.
    function module:GetPlayerLoot(name, raidNum, bossNid)
        local items = {}
        local loot = module:GetLoot(raidNum, bossNid)
        local playerNid
        if type(name) == "number" then
            playerNid = tonumber(name)
        else
            local resolvedName = Strings.NormalizeName(name, true)
            playerNid = module:GetPlayerID(resolvedName, raidNum)
        end
        if not playerNid or playerNid <= 0 then
            return items
        end
        for _, v in ipairs(loot) do
            if tonumber(v.looterNid) == playerNid then
                tinsert(items, v)
            end
        end
        return items
    end

    -- Gets a player's rank.
    function module:GetPlayerRank(name, raidNum)
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        local players = raid and raid.players or {}
        local rank = 0
        name = name or Core.GetPlayerName() or UnitName("player")
        if #players == 0 then
            if addon.IsInGroup() then
                local unit = module:GetUnitID(name)
                if unit and unit ~= "none" then
                    rank = Core.GetUnitRank(unit) or 0
                end
            end
        else
            for _, p in ipairs(players) do
                if p.name == name then
                    rank = p.rank or 0
                    break
                end
            end
        end
        return rank
    end

    -- Gets a player's class from the saved players database.
    function module:GetPlayerClass(name)
        local class = "UNKNOWN"
        local realm = Core.GetRealmName()
        local resolvedName = name or Core.GetPlayerName()
        if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
            class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
        end
        return class
    end

    -- Gets a player's unit ID (e.g., "raid1").
    function module:GetUnitID(name)
        if not addon.IsInGroup() or not name then
            return "none"
        end

        name = Strings.NormalizeName(name)
        local cachedUnit = liveUnitsByName[name]
        if cachedUnit then
            if UnitExists(cachedUnit) and UnitName(cachedUnit) == name then
                return cachedUnit
            end
            liveUnitsByName[name] = nil
            if liveNamesByUnit[cachedUnit] == name then
                liveNamesByUnit[cachedUnit] = nil
            end
        end

        for unit in addon.UnitIterator(true) do
            local unitName = UnitName(unit)
            if unitName then
                unitName = Strings.NormalizeName(unitName)
                liveUnitsByName[unitName] = unit
                liveNamesByUnit[unit] = unitName
                if unitName == name then
                    return unit
                end
            end
        end
        return "none"
    end

    -- Raid and loot status checks.

    -- Checks if the group is using the Master Looter system.
    function module:IsMasterLoot()
        local method = select(1, getLootMethod())
        return (method == "master")
    end

    -- Checks if the player is the Master Looter.
    function module:IsMasterLooter()
        local method, partyMaster, raidMaster = getLootMethod()
        if method ~= "master" then
            return false
        end
        if partyMaster then
            if partyMaster == 0 or unitIsUnit("party" .. tostring(partyMaster), "player") then
                return true
            end
        end
        if raidMaster then
            if raidMaster == 0 or unitIsUnit("raid" .. tostring(raidMaster), "player") then
                return true
            end
        end
        return false
    end

    function module:GetPlayerRoleState()
        local inRaid = type(module.IsPlayerInRaid) == "function" and module:IsPlayerInRaid() or false
        local rank = Core.GetUnitRank and (tonumber(Core.GetUnitRank("player", 0)) or 0) or 0
        local isLeader = rank >= 2
        local isAssistant = rank == 1
        return {
            inRaid = inRaid,
            rank = rank,
            isLeader = isLeader,
            isAssistant = isAssistant,
            hasRaidLeadership = inRaid and rank > 0,
            hasGroupLeadership = rank > 0,
            isMasterLooter = module:IsMasterLooter(),
        }
    end

    function module:GetCapabilityState(capability)
        local role = module:GetPlayerRoleState()
        local state = {
            capability = capability,
            allowed = false,
            reason = "unknown_capability",
            role = role,
        }

        if capability == "loot" then
            if not role.inRaid or role.isMasterLooter then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_master_looter"
            end
            return state
        end

        if capability == "raid_leadership" or capability == "changes_broadcast" or capability == "raid_warning" or capability == "raid_icons" then
            if not role.inRaid then
                state.reason = "not_in_raid"
            elseif role.hasRaidLeadership then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_leadership"
            end
            return state
        end

        if capability == "group_leadership" or capability == "ready_check" then
            if role.hasGroupLeadership then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_group_leadership"
            end
            return state
        end

        return state
    end

    function module:CanUseCapability(capability)
        local state = module:GetCapabilityState(capability)
        return state and state.allowed == true
    end

    -- Master-only actions are allowed out of raid, but in raid require current ML ownership.
    function module:CanUseMasterOnlyFeatures()
        return module:CanUseCapability("loot")
    end

    function module:IsMasterOnlyBlocked()
        return not module:CanUseMasterOnlyFeatures()
    end

    function module:CanObservePassiveLoot()
        local method = getLootMethodName()
        if method == "master" then
            return module:CanUseMasterOnlyFeatures()
        end
        return isPassiveGroupLootMethod(method)
    end

    -- Processes COMBAT_LOG_EVENT_UNFILTERED for boss-kill detection.
    function module:COMBAT_LOG_EVENT_UNFILTERED(...)
        if not Core.GetCurrentRaid() then
            return
        end

        -- Hot-path fast check: inspect the event type before unpacking extra args.
        local subEvent = select(2, ...)
        if subEvent ~= "UNIT_DIED" then
            return
        end

        -- 3.3.5a base params (8):
        -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags
        local destGUID, destName, destFlags = select(6, ...)
        if bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then
            return
        end

        -- LibCompat embeds GetCreatureId with the 3.3.5a GUID parsing rules.
        local npcId = destGUID and addon.GetCreatureId(destGUID)
        local bossLib = addon.BossIDs
        local bossIds = bossLib and bossLib.BossIDs
        if not (npcId and bossIds and bossIds[npcId]) then
            return
        end

        local boss = destName
        if not boss and bossLib and bossLib.GetBossName then
            boss = bossLib:GetBossName(npcId)
        end
        if boss then
            addon:trace(Diag.D.LogBossUnitDiedMatched:format(tonumber(npcId) or -1, tostring(boss)))
            module:AddBoss(boss, nil, nil, npcId)
        end
    end

    -- Clears all raid target icons.
    function module:ClearRaidIcons()
        local players = module:GetPlayers()
        for i = 1, #players do
            SetRaidTarget("raid" .. tostring(i), 0)
        end
    end
end
