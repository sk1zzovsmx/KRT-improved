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

local VALID_MODE_KEYS = {
    normal10 = true,
    normal20 = true,
    normal25 = true,
    normal40 = true,
    heroic10 = true,
    heroic25 = true,
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

local function copyModes(modes)
    if type(modes) ~= "table" then
        return nil
    end

    local copied = {}
    for key, value in pairs(modes) do
        copied[key] = value
    end
    return copied
end

local function copyCandidate(candidate)
    return {
        npcId = tonumber(candidate.npcId),
        npcName = candidate.npcName,
        raid = candidate.raid,
        kind = candidate.kind,
        modes = copyModes(candidate.modes),
    }
end

local function isValidCandidate(candidate)
    if type(candidate) ~= "table" or VALID_SOURCE_KINDS[candidate.kind] ~= true then
        return false
    end

    local npcId = tonumber(candidate.npcId)
    if not npcId or npcId <= 0 then
        return false
    end

    return normalizeText(candidate.npcName) ~= nil and normalizeText(candidate.raid) ~= nil
end

local function getModeKey(context)
    if type(context) ~= "table" then
        return nil
    end

    if type(context.mode) == "string" then
        local mode = normalizeText(context.mode)
        if VALID_MODE_KEYS[mode] == true then
            return mode
        end
    end

    local raidSize = tonumber(context.raidSize)
    local difficulty = tonumber(context.difficulty)
    if raidSize ~= 10 and raidSize ~= 20 and raidSize ~= 25 and raidSize ~= 40 then
        if difficulty == 3 or difficulty == 5 then
            raidSize = 10
        elseif difficulty == 4 or difficulty == 6 then
            raidSize = 25
        end
    end

    if raidSize ~= 10 and raidSize ~= 20 and raidSize ~= 25 and raidSize ~= 40 then
        return nil
    end

    local heroic = difficulty == 5 or difficulty == 6
    if context.isHeroic == true or context.heroic == true then
        heroic = true
    end

    if raidSize == 20 or raidSize == 40 then
        return "normal" .. tostring(raidSize)
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

local function setDataForTests(byItemId)
    addon.LootSourcesData.ByItemId = byItemId or {}
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

function LootSources.FindSource(itemId, context)
    local candidates = filterCandidates(LootSources.GetCandidates(itemId), context)
    if #candidates == 0 then
        return { reason = "missing", candidates = candidates }
    end

    if #candidates == 1 then
        return withConfidence(candidates[1], "exact")
    end

    local sharedTrashCandidate = findSharedTrashCandidate(candidates)
    if sharedTrashCandidate then
        return withConfidence(sharedTrashCandidate, "shared-trash")
    end

    return { reason = "ambiguous", candidates = candidates }
end

LootSources._SetDataForTests = setDataForTests
