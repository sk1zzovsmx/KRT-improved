-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type = type
local GetRealmName = GetRealmName
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitIsGroupLeader = _G.UnitIsGroupLeader

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.RaidState = Utils.RaidState or {}
local RaidState = Utils.RaidState

function RaidState.getPlayerName()
    local state = addon.State
    state.player = state.player or {}
    local name = state.player.name
        or addon.UnitFullName("player")
    state.player.name = name
    return name
end

-- Resolve a raid table and raid number.
--
-- Returns:
--   raidTableOrNil, resolvedRaidNumOrNil
--
-- Notes:
-- - Uses current raid via addon.Core.getCurrentRaid() when raidNum is nil.
-- - Safe when KRT_Raids is nil.
function RaidState.getRaid(raidNum)
    if raidNum == nil then
        local core = addon.Core
        if core and core.getCurrentRaid then
            raidNum = core.getCurrentRaid()
        else
            local state = addon.State
            raidNum = state and state.currentRaid or nil
        end
    end
    if not raidNum then
        return nil, nil
    end
    local raids = KRT_Raids
    local raid = raids and raids[raidNum] or nil
    return raid, raidNum
end

RaidState.GetRaid = RaidState.getRaid

function RaidState.getRealmName()
    local realm = GetRealmName()
    if type(realm) ~= "string" then
        return ""
    end
    return realm
end

function RaidState.getUnitRank(unit, fallback)
    local groupLeader = (addon and addon.UnitIsGroupLeader) or UnitIsGroupLeader
    local groupAssistant = (addon and addon.UnitIsGroupAssistant) or UnitIsGroupAssistant

    if groupLeader and groupLeader(unit) then
        return 2
    end
    if groupAssistant and groupAssistant(unit) then
        return 1
    end
    return fallback or 0
end
