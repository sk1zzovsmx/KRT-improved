--[[
    Features/Chat.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Utils = feature.Utils
local C = feature.C

local UnitIsGroupLeader = feature.UnitIsGroupLeader
local UnitIsGroupAssistant = feature.UnitIsGroupAssistant

local find = string.find
local tostring = tostring

-- =========== Chat Output Helpers  =========== --
do
    addon.Chat            = addon.Chat or {}
    local module          = addon.Chat
    -- ----- Internal state ----- --
    local output          = C.CHAT_OUTPUT_FORMAT
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local prefixHex       = C.CHAT_PREFIX_HEX

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --
    function module:Print(text, prefix)
        local msg = Utils.formatChatMessage(text, prefix or chatPrefixShort, output, prefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local ch = channel

        if not ch then
            local seconds = addon.Deformat(text, L.ChatCountdownTic)
            local isCountdown = (seconds ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)

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
