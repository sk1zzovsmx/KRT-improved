-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: centralized event-name registry helpers

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, tostring = type, tostring

addon.Events = addon.Events or feature.Events or {}
local Events = addon.Events
local Core = feature.Core

-- ----- Internal state ----- --
Events.Internal = Events.Internal or {}
Events.Wow = Events.Wow or {}

local Internal = Events.Internal
local Wow = Events.Wow

Core.EnsureBootstrapEvents()

Internal.AddRoll = "AddRoll"
Internal.LoggerLootLogRequest = "LoggerLootLogRequest"
Internal.LoggerSelectRaid = "LoggerSelectRaid"
Internal.LoggerSelectBoss = "LoggerSelectBoss"
Internal.LoggerSelectPlayer = "LoggerSelectPlayer"
Internal.LoggerSelectBossPlayer = "LoggerSelectBossPlayer"
Internal.LoggerSelectItem = "LoggerSelectItem"
Internal.PlayerCountChanged = "PlayerCountChanged"
Internal.RaidCreate = "RaidCreate"
Internal.RaidChangesUpdated = "RaidChangesUpdated"
Internal.RaidLeave = "RaidLeave"
Internal.RaidLootUpdate = "RaidLootUpdate"
Internal.ReservesDataChanged = "ReservesDataChanged"
Internal.SetItem = "SetItem"

Internal.ConfigSortAscending = "ConfigsortAscending"
Internal.ConfigShowLootCounterDuringMSRoll = "ConfigshowLootCounterDuringMSRoll"

-- ----- Private helpers ----- --

-- ----- Public methods ----- --
function Events.ConfigOptionChanged(optionName)
    if type(optionName) ~= "string" or optionName == "" then
        return nil
    end
    return "Config" .. optionName
end

function Events.WowForwarded(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        return nil
    end
    return Wow[eventName] or ("wow." .. tostring(eventName))
end
