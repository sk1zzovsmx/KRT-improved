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

-- ----- Internal state ----- --
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
Internal.RaidChangesUpdated = "RaidChangesUpdated"
Internal.RaidLeave = "RaidLeave"
Internal.RaidLootUpdate = "RaidLootUpdate"
Internal.RaidRosterDelta = "RaidRosterDelta"
Internal.ReservesDataChanged = "ReservesDataChanged"
Internal.SetItem = "SetItem"

Internal.ConfigSortAscending = "ConfigsortAscending"
Internal.ConfigShowLootCounterDuringMSRoll = "ConfigshowLootCounterDuringMSRoll"

-- Canonical forwarded WoW-event names.
Wow.LootOpened = Wow.LootOpened or "wow.LOOT_OPENED"
Wow.LootClosed = Wow.LootClosed or "wow.LOOT_CLOSED"
Wow.LootSlotCleared = Wow.LootSlotCleared or "wow.LOOT_SLOT_CLEARED"
Wow.ChatMsgWhisper = Wow.ChatMsgWhisper or "wow.CHAT_MSG_WHISPER"
Wow.TradeAcceptUpdate = Wow.TradeAcceptUpdate or "wow.TRADE_ACCEPT_UPDATE"
Wow.TradeRequestCancel = Wow.TradeRequestCancel or "wow.TRADE_REQUEST_CANCEL"
Wow.TradeClosed = Wow.TradeClosed or "wow.TRADE_CLOSED"

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
