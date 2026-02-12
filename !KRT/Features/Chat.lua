--[[
    Features/Chat.lua
]]

local addon = select(2, ...)
addon = addon or {}

local feature = (addon.Core and addon.Core.getFeatureShared and addon.Core.getFeatureShared()) or {}

local L = feature.L or addon.L or {}
local Utils = feature.Utils or addon.Utils
local C = feature.C or addon.C or {}

local UnitIsGroupLeader = feature.UnitIsGroupLeader or addon.UnitIsGroupLeader
local UnitIsGroupAssistant = feature.UnitIsGroupAssistant or addon.UnitIsGroupAssistant

local find = string.find
local tostring = tostring

-- =========== Chat Output Helpers  =========== --
do
    addon.Chat            = addon.Chat or {}
    local module          = addon.Chat
    -- ----- Internal state (non-exposed local variables) ----- --
    local output          = C.CHAT_OUTPUT_FORMAT
    local chatPrefix      = C.CHAT_PREFIX
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local prefixHex       = C.CHAT_PREFIX_HEX

    -- ----- Public module functions ----- --
    function module:Print(text, prefix)
        local msg = Utils.formatChatMessage(text, prefix or chatPrefixShort, output, prefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local ch = channel

        if not ch then
            local isCountdown = false
            do
                local seconds = addon.Deformat(text, L.ChatCountdownTic)
                isCountdown = (seconds ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)
            end

            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" then
                if isCountdown and addon.options.countdownSimpleRaidMsg then
                    ch = "RAID"
                elseif addon.options.useRaidWarning
                    and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
                    ch = "RAID_WARNING"
                else
                    ch = "RAID"
                end
            elseif groupType == "party" then
                ch = "PARTY"
            else
                ch = "SAY"
            end
        end
        Utils.chat(tostring(text), ch)
    end

    -- ----- Legacy helpers ----- --
    function addon:Announce(text, channel)
        module:Announce(text, channel)
    end
end
