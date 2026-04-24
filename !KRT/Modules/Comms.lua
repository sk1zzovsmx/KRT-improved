-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addonName = ...
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, tostring = type, tostring
local format = string.format
local select = select
local strmatch = string.match
local tconcat = table.concat
local _G = _G

addon.Comms = addon.Comms or feature.Comms or {}
local Comms = addon.Comms
local L = feature.L
local Core = feature.Core or addon.Core

-- ----- Internal state ----- --

local VERSION_PREFIX = "KRTVersion"
local MSG_VERSION_REQ = "REQ"
local MSG_VERSION_ACK = "ACK"

-- ----- Private helpers ----- --

local function splitVersionPayload(msg)
    local kind, addonVersion, interfaceVersion, schemaVersion, syncProtocol = strmatch(tostring(msg or ""), "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(.*)$")
    return kind, addonVersion, interfaceVersion, schemaVersion, syncProtocol
end

local function getAddonMetadata(key, fallback)
    local getter = _G.GetAddOnMetadata
    if type(getter) == "function" then
        local value = getter(addonName, key)
        if value ~= nil and value ~= "" then
            return tostring(value)
        end
    end
    return tostring(fallback or (L and L.StrUnknown) or "unknown")
end

local function getRaidSchemaVersion()
    local getter = Core and Core.GetRaidSchemaVersion
    if type(getter) == "function" then
        return tostring(getter() or (L and L.StrUnknown) or "unknown")
    end
    return tostring((L and L.StrUnknown) or "unknown")
end

local function getSyncProtocolVersion()
    local syncer = Core and Core.GetSyncer and Core.GetSyncer() or nil
    if syncer and type(syncer.GetProtocolVersion) == "function" then
        return tostring(syncer:GetProtocolVersion() or (L and L.StrUnknown) or "unknown")
    end
    return tostring((L and L.StrUnknown) or "unknown")
end

local function buildVersionPayload(kind)
    return tconcat({
        kind,
        getAddonMetadata("Version", "unknown"),
        getAddonMetadata("Interface", "unknown"),
        getRaidSchemaVersion(),
        getSyncProtocolVersion(),
    }, "|")
end

local function getGroupTransport()
    local zone = select(2, IsInInstance())
    local raidCount = (GetRealNumRaidMembers and GetRealNumRaidMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local partyCount = (GetRealNumPartyMembers and GetRealNumPartyMembers()) or (GetNumPartyMembers and GetNumPartyMembers()) or 0

    if zone == "pvp" or zone == "arena" then
        return "BATTLEGROUND"
    end
    if raidCount > 0 then
        return "RAID"
    end
    if partyCount > 0 then
        return "PARTY"
    end
    return nil
end

local function getPlayerName()
    local name = _G.UnitName and _G.UnitName("player") or nil
    return tostring(name or "")
end

local function sendGroupMessage(prefix, msg)
    local channel = getGroupTransport()
    if channel then
        SendAddonMessage(prefix, msg, channel)
        return true, channel
    end
    return false
end

-- ----- Public methods ----- --

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

function Comms:EnsureVersionPrefix()
    local register = _G.RegisterAddonMessagePrefix
    if type(register) == "function" then
        register(VERSION_PREFIX)
    end
end

function Comms.GetVersionPrefix()
    return VERSION_PREFIX
end

function Comms:RequestVersionCheck()
    self:EnsureVersionPrefix()
    local ok = sendGroupMessage(VERSION_PREFIX, buildVersionPayload(MSG_VERSION_REQ))
    if ok then
        addon:info(L.MsgVersionCheckSent)
        return true
    end
    addon:warn(L.MsgVersionCheckNotInGroup)
    return false
end

function Comms:RequestVersionMessageHandling(prefix, msg, channel, sender)
    if prefix ~= VERSION_PREFIX then
        return false
    end
    if tostring(sender or "") == getPlayerName() then
        return true
    end

    local kind, addonVersion, interfaceVersion, schemaVersion, syncProtocol = splitVersionPayload(msg)
    if kind == MSG_VERSION_REQ then
        SendAddonMessage(VERSION_PREFIX, buildVersionPayload(MSG_VERSION_ACK), "WHISPER", sender)
        return true
    end
    if kind == MSG_VERSION_ACK then
        addon:info(
            L.MsgVersionCheckPeer:format(
                tostring(sender or "?"),
                tostring(addonVersion or "?"),
                tostring(interfaceVersion or "?"),
                tostring(schemaVersion or "?"),
                tostring(syncProtocol or "?")
            )
        )
        return true
    end
    return true
end
