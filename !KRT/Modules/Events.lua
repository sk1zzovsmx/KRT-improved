-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type = type
local tostring = tostring

addon.Events = addon.Events or {}
local Events = addon.Events

Events.Internal = Events.Internal or {}
Events.Wow = Events.Wow or {}

local Internal = Events.Internal
local Wow = Events.Wow

-- Internal bus events.
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

-- WoW forwarded bus events (wow.<EVENT_NAME>).
Wow.LOOT_OPENED = "wow.LOOT_OPENED"
Wow.LOOT_CLOSED = "wow.LOOT_CLOSED"
Wow.LOOT_SLOT_CLEARED = "wow.LOOT_SLOT_CLEARED"
Wow.TRADE_ACCEPT_UPDATE = "wow.TRADE_ACCEPT_UPDATE"
Wow.TRADE_REQUEST_CANCEL = "wow.TRADE_REQUEST_CANCEL"
Wow.TRADE_CLOSED = "wow.TRADE_CLOSED"

-- Helpers for dynamic event-name building.
function Events.configOptionChanged(optionName)
    if type(optionName) ~= "string" or optionName == "" then
        return nil
    end
    return "Config" .. optionName
end

function Events.wowForwarded(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        return nil
    end
    return Wow[eventName] or ("wow." .. tostring(eventName))
end
