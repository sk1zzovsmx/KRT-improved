-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local select = select
local tostring = tostring
local type = type

addon.Comms = addon.Comms or {}
local Comms = addon.Comms

function Comms.sync(prefix, msg)
    local zone = select(2, IsInInstance())
    if zone == "pvp" or zone == "arena" then
        SendAddonMessage(prefix, msg, "BATTLEGROUND")
    elseif GetRealNumRaidMembers() > 0 then
        SendAddonMessage(prefix, msg, "RAID")
    elseif GetRealNumPartyMembers() > 0 then
        SendAddonMessage(prefix, msg, "PARTY")
    end
end

function Comms.chat(msg, channel, language, target, bypass)
    if not msg then
        return
    end
    SendChatMessage(tostring(msg), channel, language, target)
end

function Comms.whisper(target, msg)
    if type(target) == "string" and msg then
        SendChatMessage(msg, "WHISPER", nil, target)
        return true
    end
end
