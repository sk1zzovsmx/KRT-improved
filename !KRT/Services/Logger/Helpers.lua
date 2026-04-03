-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Core = feature.Core

local tostring, tonumber = tostring, tonumber

-- ----- Internal state ----- --
addon.Services = addon.Services or {}
addon.Services.Logger = addon.Services.Logger or {}
addon.Services.Logger.Helpers = addon.Services.Logger.Helpers or {}

local Helpers = addon.Services.Logger.Helpers

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

function Helpers:BuildCountTitle(baseText, count)
    return ("%s (%d)"):format(tostring(baseText or ""), tonumber(count) or 0)
end

function Helpers:BuildContextTitle(baseText, contextText, emptyHint)
    local suffix = contextText
    if not suffix or suffix == "" then
        suffix = emptyHint
    end
    if suffix and suffix ~= "" then
        return ("%s - %s"):format(baseText, suffix)
    end
    return baseText
end

function Helpers:BuildCountContextTitle(baseText, count, contextText, emptyHint)
    return self:BuildContextTitle(self:BuildCountTitle(baseText, count), contextText, emptyHint)
end

function Helpers:BuildBossEmptyStateText(count, hasRaid)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not hasRaid then
        return L.StrLoggerEmptyBossesSelectRaid
    end
    return L.StrLoggerEmptyBosses
end

function Helpers:BuildBossAttendeesEmptyStateText(count, hasRaid, hasBoss)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not hasRaid then
        return L.StrLoggerEmptyBossAttendeesSelectRaid
    end
    if not hasBoss then
        return L.StrLoggerEmptyBossAttendeesSelectBoss
    end
    return L.StrLoggerEmptyBossAttendees
end

function Helpers:BuildRaidAttendeesEmptyStateText(count, hasRaid)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not hasRaid then
        return L.StrLoggerEmptyRaidAttendeesSelectRaid
    end
    return L.StrLoggerEmptyRaidAttendees
end

function Helpers:BuildLootEmptyStateText(count, hasRaid, hasFilter)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not hasRaid then
        return L.StrLoggerEmptyLootSelectRaid
    end
    if hasFilter then
        return L.StrLoggerEmptyLootFiltered
    end
    return L.StrLoggerEmptyLoot
end

function Helpers:BuildCsvEmptyStateText(csvValue, hasRaid)
    if not hasRaid then
        return L.StrLoggerEmptyCsvSelectRaid
    end
    if not csvValue or csvValue == "" then
        return L.StrLoggerEmptyCsv
    end
    return nil
end

function Helpers:GetRaidNidByIndex(raidIndex)
    return raidIndex and Core.GetRaidNidById(raidIndex) or nil
end

function Helpers:GetRaidIndexByNid(raidNid)
    return raidNid and Core.GetRaidIdByNid(raidNid) or nil
end
