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

Events.Internal = Events.Internal or {}
Events.Wow = Events.Wow or {}

local Internal = Events.Internal
local Wow = Events.Wow

Internal.AddRoll = "AddRoll"
Internal.LoggerLootLogRequest = "LoggerLootLogRequest"
Internal.LoggerSelectRaid = "LoggerSelectRaid"
Internal.LoggerSelectBoss = "LoggerSelectBoss"
Internal.LoggerSelectPlayer = "LoggerSelectPlayer"
Internal.LoggerSelectBossPlayer = "LoggerSelectBossPlayer"
Internal.LoggerSelectItem = "LoggerSelectItem"
Internal.PlayerCountChanged = "PlayerCountChanged"
Internal.RaidCreate = "RaidCreate"
Internal.RaidLeave = "RaidLeave"
Internal.RaidLootUpdate = "RaidLootUpdate"
Internal.RaidRosterDelta = "RaidRosterDelta"
Internal.ReservesDataChanged = "ReservesDataChanged"
Internal.SetItem = "SetItem"

Internal.ConfigSortAscending = "ConfigsortAscending"
Internal.ConfigShowLootCounterDuringMSRoll = "ConfigshowLootCounterDuringMSRoll"

Wow.LOOT_OPENED = "wow.LOOT_OPENED"
Wow.LOOT_CLOSED = "wow.LOOT_CLOSED"
Wow.LOOT_SLOT_CLEARED = "wow.LOOT_SLOT_CLEARED"
Wow.TRADE_ACCEPT_UPDATE = "wow.TRADE_ACCEPT_UPDATE"
Wow.TRADE_REQUEST_CANCEL = "wow.TRADE_REQUEST_CANCEL"
Wow.TRADE_CLOSED = "wow.TRADE_CLOSED"

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
