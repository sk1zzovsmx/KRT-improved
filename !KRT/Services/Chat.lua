-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local C = feature.C
local Strings = feature.Strings or addon.Strings
local Comms = feature.Comms or addon.Comms

local UnitIsGroupLeader = feature.UnitIsGroupLeader
local UnitIsGroupAssistant = feature.UnitIsGroupAssistant

local find = string.find
local tostring = tostring
local tonumber = tonumber

-- =========== Chat Output Helpers  =========== --
do
    addon.Services = addon.Services or {}
    addon.Services.Chat = addon.Services.Chat or {}
    addon.Chat = addon.Services.Chat -- Legacy alias during namespacing migration.
    local module = addon.Services.Chat

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

    local function ResolveGroupType()
        if type(addon.GetGroupTypeAndCount) == "function" then
            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" or groupType == "party" then
                return groupType
            end
        end

        if type(addon.IsInRaid) == "function" and addon.IsInRaid() then
            return "raid"
        end
        if type(IsInRaid) == "function" and IsInRaid() then
            return "raid"
        end
        if type(UnitInRaid) == "function" and UnitInRaid("player") then
            return "raid"
        end

        local raidCount = (GetRealNumRaidMembers and GetRealNumRaidMembers())
            or (GetNumRaidMembers and GetNumRaidMembers())
            or 0
        if (tonumber(raidCount) or 0) > 0 then
            return "raid"
        end

        local partyCount = (GetRealNumPartyMembers and GetRealNumPartyMembers())
            or (GetNumPartyMembers and GetNumPartyMembers())
            or 0
        if (tonumber(partyCount) or 0) > 0 then
            return "party"
        end

        return nil
    end

    local function ResolveAnnounceChannel(text, preferredChannel)
        if preferredChannel then
            return preferredChannel
        end

        local groupType = ResolveGroupType()
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
        return nil
    end

    -- ----- Public methods ----- --
    function module:Print(text, prefix)
        local msg = Strings.FormatChatMessage(text, prefix or chatPrefixShort, chatOutputFormat, chatPrefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local msg = tostring(text)
        local selectedChannel = ResolveAnnounceChannel(msg, channel)
        if not selectedChannel or selectedChannel == "" then
            return module:Print(msg)
        end
        Comms.Chat(msg, selectedChannel)
    end

    -- ----- Legacy helpers ----- --
    function addon:Announce(text, channel)
        module:Announce(text, channel)
    end
end
