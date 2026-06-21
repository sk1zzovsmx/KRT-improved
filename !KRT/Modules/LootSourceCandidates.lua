-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.LootSourceCandidates
-- events: none

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Strings = feature.Strings

local type, tostring, tonumber = type, tostring, tonumber
local strsub = string.sub
local strlen = string.len
local gmatch = string.gmatch

-- ----- Internal state ----- --
local LootSourceCandidates = feature.LootSourceCandidates or {}
feature.LootSourceCandidates = LootSourceCandidates
addon.LootSourceCandidates = LootSourceCandidates

local SHARED_SOURCE_LABEL = "Shared"
local SHARED_SOURCE_PREFIX = "Shared:"

-- ----- Private helpers ----- --
local function normalizeText(value)
    if Strings and Strings.NormalizeText then
        return Strings.NormalizeText(value, true)
    end
    if value == nil then
        return nil
    end
    local text = tostring(value)
    if text == "" then
        return nil
    end
    return text
end

local function candidateKey(name)
    if Strings and Strings.NormalizeLower then
        return Strings.NormalizeLower(name, true) or name
    end
    return name
end

-- ----- Public methods ----- --
function LootSourceCandidates.GetSharedLabel()
    return SHARED_SOURCE_LABEL
end

function LootSourceCandidates.IsLegacySharedText(value)
    local text = normalizeText(value)
    return type(text) == "string" and strsub(text, 1, strlen(SHARED_SOURCE_PREFIX)) == SHARED_SOURCE_PREFIX
end

function LootSourceCandidates.IsSharedSourceName(value)
    local text = normalizeText(value)
    return text == SHARED_SOURCE_LABEL or LootSourceCandidates.IsLegacySharedText(text)
end

function LootSourceCandidates.Append(out, seen, rawName, rawNpcId, rawKind, rawSourceKey)
    if type(out) ~= "table" or type(seen) ~= "table" then
        return false
    end

    local name = normalizeText(rawName)
    if not name then
        return false
    end

    local key = candidateKey(name)
    if seen[key] then
        return false
    end
    seen[key] = true

    local candidate = {
        name = name,
        kind = normalizeText(rawKind) or "boss",
    }

    local sourceKey = normalizeText(rawSourceKey)
    if sourceKey then
        candidate.sourceKey = sourceKey
    end

    local npcId = tonumber(rawNpcId) or 0
    if npcId > 0 then
        candidate.npcId = npcId
    end

    out[#out + 1] = candidate
    return true
end

function LootSourceCandidates.ParseSharedText(value)
    local text = normalizeText(value)
    if not text then
        return nil
    end

    if LootSourceCandidates.IsLegacySharedText(text) then
        text = normalizeText(strsub(text, strlen(SHARED_SOURCE_PREFIX) + 1))
    end
    if not text or text == SHARED_SOURCE_LABEL then
        return nil
    end

    local out = {}
    local seen = {}
    for name in gmatch(text, "[^/]+") do
        LootSourceCandidates.Append(out, seen, name, nil, "boss")
    end
    return (#out > 0) and out or nil
end

function LootSourceCandidates.ParseLegacySharedText(value)
    if not LootSourceCandidates.IsLegacySharedText(value) then
        return nil
    end
    return LootSourceCandidates.ParseSharedText(value)
end

function LootSourceCandidates.Copy(candidates, fallbackText)
    local copied = {}
    local seen = {}

    if type(candidates) == "table" then
        for i = 1, #candidates do
            local candidate = candidates[i]
            if type(candidate) == "table" then
                LootSourceCandidates.Append(copied, seen, candidate.name or candidate.npcName, candidate.npcId or candidate.sourceNpcId, candidate.kind, candidate.sourceKey)
            end
        end
    end

    if #copied == 0 then
        local parsed = LootSourceCandidates.ParseSharedText(fallbackText)
        if type(parsed) == "table" then
            for i = 1, #parsed do
                local candidate = parsed[i]
                LootSourceCandidates.Append(copied, seen, candidate.name, candidate.npcId, candidate.kind, candidate.sourceKey)
            end
        end
    end

    return (#copied > 0) and copied or nil
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Modules/LootSourceCandidates", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
        },
    })
    registry.SetLoaded("Modules/LootSourceCandidates")
end
