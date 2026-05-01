-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.Services.Reserves._Chat
-- events: listens to wow.CHAT_MSG_WHISPER and replies with opt-in SoftRes summaries

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Strings = feature.Strings
local Comms = feature.Comms
local Services = feature.Services
local Events = feature.Events
local Bus = feature.Bus

local format = string.format
local len = string.len
local lower = string.lower
local tostring = tostring
local tonumber = tonumber
local type = type

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Reserves")
local module = addon.Services.Reserves
module._Chat = module._Chat or {}

local Chat = module._Chat

local MAX_WHISPER_LEN = 255
local REQUESTS = {
    ["!sr"] = true,
    ["!softres"] = true,
    ["sr"] = true,
    ["softres"] = true,
    ["krt sr"] = true,
    ["krt softres"] = true,
}

-- ----- Private helpers ----- --
local function trimText(value)
    if Strings and Strings.TrimText then
        return Strings.TrimText(value)
    end
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function isRequest(text)
    local normalized = lower(trimText(text or ""))
    return REQUESTS[normalized] == true
end

local function canReplyFromCurrentClient()
    local raid = Services and Services.Raid or nil
    if not (raid and raid.GetPlayerRoleState and raid.CanUseCapability) then
        return false
    end

    local role = raid:GetPlayerRoleState()
    if not (role and role.inRaid) then
        return false
    end

    return role.isMasterLooter == true or raid:CanUseCapability("loot") or raid:CanUseCapability("raid_leadership")
end

local function buildFallbackItemText(entry)
    local itemName = entry.itemName
    if type(itemName) == "string" and itemName ~= "" then
        return itemName
    end

    local itemId = entry.rawID or entry.itemId
    return format(L.StrReservesItemFallback or "[Item %s]", tostring(itemId or "?"))
end

local function buildItemText(entry)
    local itemText = entry.itemLink
    if type(itemText) ~= "string" or itemText == "" then
        itemText = buildFallbackItemText(entry)
    end

    local suffix = ""
    local quantity = tonumber(entry.quantity) or 1
    local plus = tonumber(entry.plus) or 0
    if quantity > 1 then
        suffix = suffix .. " x" .. tostring(quantity)
    end
    if plus > 0 then
        suffix = suffix .. " (P+" .. tostring(plus) .. ")"
    end

    local text = itemText .. suffix
    if len(text) <= MAX_WHISPER_LEN - 16 then
        return text
    end
    return buildFallbackItemText(entry) .. suffix
end

local function sendWhisper(target, text)
    if not (Comms and Comms.Whisper) then
        return false
    end
    return Comms.Whisper(target, text)
end

local function sendReserveMessages(target, entries)
    sendWhisper(target, L.WhisperSoftResHeader)
    for i = 1, #entries do
        local line = format(L.WhisperSoftResEntry, i, buildItemText(entries[i]))
        if len(line) > MAX_WHISPER_LEN then
            line = format(L.WhisperSoftResEntry, i, buildFallbackItemText(entries[i]))
        end
        sendWhisper(target, line)
    end
end

local function registerWhisperHandler()
    local eventName = Events and Events.Wow and Events.Wow.ChatMsgWhisper
    if not (eventName and Bus and Bus.RegisterCallback) then
        return
    end

    Bus.RegisterCallback(eventName, function(_, msg, sender)
        Chat:RequestWhisperReply(msg, sender)
    end)
end

-- ----- Public methods ----- --
function Chat:RequestWhisperReply(msg, sender)
    if not isRequest(msg) then
        return false
    end

    local target = trimText(sender or "")
    if target == "" then
        return true
    end

    if not (addon.options and addon.options.softResWhisperReplies == true) then
        return true
    end

    if not (module.HasData and module:HasData()) then
        return true
    end

    if not canReplyFromCurrentClient() then
        return true
    end

    local entries = module.GetPlayerReserveEntries and module:GetPlayerReserveEntries(target) or {}
    if #entries <= 0 then
        sendWhisper(target, format(L.WhisperSoftResNone, target))
        return true
    end

    sendReserveMessages(target, entries)
    return true
end

registerWhisperHandler()
