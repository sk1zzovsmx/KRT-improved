-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, tostring = type, tostring
local select = select

addon.Comms = addon.Comms or feature.Comms or {}
local Comms = addon.Comms

function Comms.Sync(prefix, msg)
    local zone = select(2, IsInInstance())
    local raidCount = (GetRealNumRaidMembers and GetRealNumRaidMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local partyCount = (GetRealNumPartyMembers and GetRealNumPartyMembers()) or (GetNumPartyMembers and GetNumPartyMembers()) or 0

    if zone == "pvp" or zone == "arena" then
        SendAddonMessage(prefix, msg, "BATTLEGROUND")
    elseif raidCount > 0 then
        SendAddonMessage(prefix, msg, "RAID")
    elseif partyCount > 0 then
        SendAddonMessage(prefix, msg, "PARTY")
    end
end

function Comms.Chat(msg, channel, language, target, bypass)
    if not msg then
        return
    end
    SendChatMessage(tostring(msg), channel, language, target)
end

function Comms.Whisper(target, msg)
    if type(target) == "string" and msg then
        SendChatMessage(msg, "WHISPER", nil, target)
        return true
    end
end
