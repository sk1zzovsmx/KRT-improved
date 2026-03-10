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
    addon.Chat = addon.Chat or {}
    local module = addon.Chat

    -- ----- Internal state ----- --
    local chatOutputFormat = C.CHAT_OUTPUT_FORMAT
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local chatPrefixHex = C.CHAT_PREFIX_HEX

    -- ----- Private helpers ----- --
    local function IsCountdownMessage(text)
        local seconds = addon.Deformat(text, L.ChatCountdownTic)
        return (seconds ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)
    end

    local function CanUseRaidWarning()
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end

    local function ResolveAnnounceChannel(text, preferredChannel)
        if preferredChannel then
            return preferredChannel
        end

        local groupType = addon.GetGroupTypeAndCount()
        if groupType == "raid" then
            local options = addon.options or {}
            if IsCountdownMessage(text) and options.countdownSimpleRaidMsg then
                return "RAID"
            end
            if options.useRaidWarning and CanUseRaidWarning() then
                return "RAID_WARNING"
            end
            return "RAID"
        end
        if groupType == "party" then
            return "PARTY"
        end
        return "SAY"
    end

    -- ----- Public methods ----- --
    function module:Print(text, prefix)
        local msg = Utils.formatChatMessage(text, prefix or chatPrefixShort, chatOutputFormat, chatPrefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local msg = tostring(text)
        local selectedChannel = ResolveAnnounceChannel(msg, channel)
        Utils.chat(msg, selectedChannel)
    end

    -- ----- Legacy helpers ----- --
    function addon:Announce(text, channel)
        module:Announce(text, channel)
    end
end
