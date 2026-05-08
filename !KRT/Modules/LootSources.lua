-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.LootSources

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Strings = feature.Strings

local type, tonumber, tostring = type, tonumber, tostring
local pairs = pairs
local strlower = string.lower
local gsub = string.gsub

addon.LootSourcesData = addon.LootSourcesData or {}
addon.LootSourcesData.ByItemId = addon.LootSourcesData.ByItemId or {}
addon.LootSources = addon.LootSources or {}
local LootSources = addon.LootSources

-- ----- Internal state ----- --
local VALID_SOURCE_KINDS = {
    boss = true,
    trash = true,
}

-- ----- Private helpers ----- --
local function trimText(value)
    if Strings and Strings.TrimText then
        return Strings.TrimText(value)
    end
    return gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function normalizeText(value)
    local text = trimText(value)
    if text == "" then
        return nil
    end
    if Strings and Strings.NormalizeLower then
        return Strings.NormalizeLower(text, true)
    end
    return strlower(text)
end

local function copyCandidate(candidate)
    return {
        npcId = tonumber(candidate.npcId),
        npcName = candidate.npcName,
        raid = candidate.raid,
        kind = candidate.kind,
        modes = candidate.modes,
    }
end

local function isValidCandidate(candidate)
    return type(candidate) == "table" and VALID_SOURCE_KINDS[candidate.kind] == true
end

local function getModeKey(context)
    if type(context) ~= "table" then
        return nil
    end

    if type(context.mode) == "string" then
        local mode = normalizeText(context.mode)
        if mode == "normal10" or mode == "normal25" or mode == "heroic10" or mode == "heroic25" then
            return mode
        end
    end

    local raidSize = tonumber(context.raidSize)
    local difficulty = tonumber(context.difficulty)
    if raidSize ~= 10 and raidSize ~= 25 then
        if difficulty == 3 or difficulty == 5 then
            raidSize = 10
        elseif difficulty == 4 or difficulty == 6 then
            raidSize = 25
        end
    end

    if raidSize ~= 10 and raidSize ~= 25 then
        return nil
    end

    local heroic = difficulty == 5 or difficulty == 6
    if context.isHeroic == true or context.heroic == true then
        heroic = true
    end

    return (heroic and "heroic" or "normal") .. tostring(raidSize)
end

local function matchesRaidContext(candidate, context)
    if type(context) ~= "table" then
        return true
    end

    local candidateRaid = normalizeText(candidate.raid)
    if not candidateRaid then
        return true
    end

    local raid = normalizeText(context.raid)
    local zoneName = normalizeText(context.zoneName)
    local instanceName = normalizeText(context.instanceName)

    if not raid and not zoneName and not instanceName then
        return true
    end

    return candidateRaid == raid or candidateRaid == zoneName or candidateRaid == instanceName
end

local function matchesModeContext(candidate, modeKey)
    if not modeKey then
        return true
    end

    if type(candidate.modes) ~= "table" then
        return true
    end

    return candidate.modes[modeKey] == true
end

local function filterCandidates(candidates, context)
    local filtered = {}
    local modeKey = getModeKey(context)
    for i = 1, #candidates do
        local candidate = candidates[i]
        if matchesRaidContext(candidate, context) and matchesModeContext(candidate, modeKey) then
            filtered[#filtered + 1] = candidate
        end
    end
    return filtered
end

local function withConfidence(candidate, confidence)
    local resolved = copyCandidate(candidate)
    resolved.confidence = confidence
    return resolved
end

local function findUniqueRecentCandidate(candidates, context)
    if type(context) ~= "table" then
        return nil
    end

    local recentNpcId = tonumber(context.recentSourceNpcId)
    local recentName = normalizeText(context.recentSourceName)
    if not recentNpcId and not recentName then
        return nil
    end

    local matched
    local matchedCount = 0
    for i = 1, #candidates do
        local candidate = candidates[i]
        local isMatch = false
        if recentNpcId and tonumber(candidate.npcId) == recentNpcId then
            isMatch = true
        elseif recentName and normalizeText(candidate.npcName) == recentName then
            isMatch = true
        end

        if isMatch then
            matched = candidate
            matchedCount = matchedCount + 1
        end
    end

    if matchedCount == 1 then
        return matched
    end
    return nil
end

local function findSharedTrashCandidate(candidates)
    local sharedNpcId
    local sharedCandidate
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.kind ~= "trash" then
            return nil
        end

        local npcId = tonumber(candidate.npcId)
        if not npcId then
            return nil
        end

        if sharedNpcId and sharedNpcId ~= npcId then
            return nil
        end

        sharedNpcId = npcId
        sharedCandidate = sharedCandidate or candidate
    end

    return sharedCandidate
end

-- ----- Public methods ----- --
function LootSources.GetCandidates(itemId)
    local numericItemId = tonumber(itemId)
    if not numericItemId then
        return {}
    end

    local sources = addon.LootSourcesData.ByItemId[numericItemId]
    if type(sources) ~= "table" then
        return {}
    end

    local candidates = {}
    for i = 1, #sources do
        local candidate = sources[i]
        if isValidCandidate(candidate) then
            candidates[#candidates + 1] = copyCandidate(candidate)
        end
    end
    return candidates
end

function LootSources.Resolve(itemId, context)
    local candidates = filterCandidates(LootSources.GetCandidates(itemId), context)
    if #candidates == 0 then
        return { reason = "missing", candidates = candidates }
    end

    if #candidates == 1 then
        return withConfidence(candidates[1], "exact")
    end

    local recentCandidate = findUniqueRecentCandidate(candidates, context)
    if recentCandidate then
        return withConfidence(recentCandidate, "context")
    end

    local sharedTrashCandidate = findSharedTrashCandidate(candidates)
    if sharedTrashCandidate then
        return withConfidence(sharedTrashCandidate, "shared-trash")
    end

    return { reason = "ambiguous", candidates = candidates }
end

function LootSources._SetDataForTests(byItemId)
    addon.LootSourcesData.ByItemId = byItemId or {}
end
