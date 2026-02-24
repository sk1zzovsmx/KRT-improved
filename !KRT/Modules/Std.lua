-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, tostring, tonumber = type, tostring, tonumber
local select = select

local floor = math.floor

local find, gsub = string.find, string.gsub
local strsub = string.sub
local format = string.format
local lower, upper = string.lower, string.upper
local char, byte = string.char, string.byte

local GetAchievementLink = GetAchievementLink

local ITEM_LINK_FORMAT = "|c%s|Hitem:%d:%s|h[%s]|h|r"
local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

addon.Colors = addon.Colors or {}
local Colors = addon.Colors

function Colors.NormalizeHexColor(color)
    if type(color) == "string" then
        local hex = color:gsub("^|c", ""):gsub("|r$", ""):gsub("^#", "")
        if #hex == 6 then
            hex = "ff" .. hex
        end
        return hex
    end

    if type(color) == "table" and color.GenerateHexColor then
        local hex = color:GenerateHexColor():gsub("^#", "")
        if #hex == 6 then
            hex = "ff" .. hex
        end
        return hex
    end

    return "ffffffff"
end

function Colors.GetClassColor(className)
    local r, g, b = addon.GetClassColor(className)
    return (r or 1), (g or 1), (b or 1)
end

addon.Strings = addon.Strings or {}
local Strings = addon.Strings

local function trimRaw(value)
    if value == nil then
        return ""
    end
    return gsub(tostring(value), "^%s*(.-)%s*$", "%1")
end

function Strings.UpperFirst(value)
    if type(value) ~= "string" then
        value = tostring(value or "")
    end
    value = lower(value)
    return gsub(value, "%a", upper, 1)
end

function Strings.TrimText(value, allowNil)
    if value == nil then
        return allowNil and nil or ""
    end
    return trimRaw(value)
end

function Strings.NormalizeName(value, allowNil)
    local text = Strings.TrimText(value, allowNil)
    if text == nil then
        return nil
    end
    return Strings.UpperFirst(text)
end

function Strings.NormalizeLower(value, allowNil)
    local text = Strings.TrimText(value, allowNil)
    if text == nil then
        return nil
    end
    return lower(text)
end

function Strings.FindAchievement(inp)
    local out = trimRaw(inp)
    if out ~= "" and find(out, "%{%d*%}") then
        local b, e = find(out, "%{%d*%}")
        local id = strsub(out, b + 1, e - 1)
        local link = (id and id ~= "" and GetAchievementLink(id)) or ("[" .. id .. "]")
        out = strsub(out, 1, b - 1) .. link .. strsub(out, e + 1)
    end
    return out
end

function Strings.FormatChatMessage(text, prefix, outputFormat, prefixHex)
    local msgPrefix = prefix or ""
    if prefixHex then
        local normalized = Colors.NormalizeHexColor and Colors.NormalizeHexColor(prefixHex) or "ffffffff"
        msgPrefix = addon.WrapTextInColorCode(msgPrefix, normalized)
    end
    return format(outputFormat or "%s%s", msgPrefix, tostring(text))
end

function Strings.SplitArgs(msg)
    msg = Strings.TrimText(msg)
    if msg == "" then
        return "", ""
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    return Strings.NormalizeLower(cmd), Strings.TrimText(rest)
end

function Strings.GetItemIdFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local _, itemId = addon.Deformat(itemLink, ITEM_LINK_FORMAT)
    return itemId
end

function Strings.GetItemStringFromLink(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local itemString = itemLink:match("|H(item:[%-%d:]+)|h")
    if itemString then
        return itemString
    end

    local _, itemId, rest = addon.Deformat(itemLink, ITEM_LINK_FORMAT)
    if itemId then
        if rest and rest ~= "" then
            return "item:" .. tostring(itemId) .. ":" .. tostring(rest)
        end
        return "item:" .. tostring(itemId)
    end

    return nil
end

addon.Time = addon.Time or {}
local Time = addon.Time

function Time.SecondsToClock(seconds)
    local sec = tonumber(seconds)
    if sec <= 0 then
        return "00:00:00"
    end
    local total = floor(sec)
    local hours = floor(total / 3600)
    local minutes = floor((total % 3600) / 60)
    local secondsPart = floor(total % 60)
    return format("%02d:%02d:%02d", hours, minutes, secondsPart)
end

function Time.IsRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return ((inInstance) and (instanceType == "raid"))
end

function Time.GetDifficulty()
    local difficulty = nil
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "raid" then
        difficulty = GetRaidDifficulty()
    end
    return difficulty
end

function Time.GetCurrentTime(server)
    if server == nil then
        server = true
    end
    local ts = time()
    if server == true then
        local _, month, day, year = CalendarGetDate()
        local hour, minute = GetGameTime()
        ts = time({ year = year, month = month, day = day, hour = hour, min = minute })
    end
    return ts
end

function Time.GetServerOffset()
    local sH, sM = GetGameTime()
    local lH, lM = tonumber(date("%H")), tonumber(date("%M"))
    local sT = sH + sM / 60
    local lT = lH + lM / 60
    local offset = addon.Round((sT - lT) / 0.5) * 0.5
    if offset >= 12 then
        offset = offset - 24
    elseif offset < -12 then
        offset = offset + 24
    end
    return offset
end

addon.Base64 = addon.Base64 or {}
local Base64 = addon.Base64

function Base64.Encode(data)
    return ((gsub(data, ".", function(x)
        local out, bits = "", byte(x)
        for i = 8, 1, -1 do
            out = out .. (bits % 2 ^ i - bits % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return out
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then
            return ""
        end
        local c = 0
        for i = 1, 6 do
            c = c + (strsub(x, i, i) == "1" and 2 ^ (6 - i) or 0)
        end
        return strsub(BASE64_ALPHABET, c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

function Base64.Decode(data)
    data = gsub(data, "[^" .. BASE64_ALPHABET .. "=]", "")
    return (gsub(data, ".", function(x)
        if x == "=" then
            return ""
        end
        local out, f = "", (find(BASE64_ALPHABET, x) - 1)
        for i = 6, 1, -1 do
            out = out .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return out
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then
            return ""
        end
        local c = 0
        for i = 1, 8 do
            c = c + (strsub(x, i, i) == "1" and 2 ^ (8 - i) or 0)
        end
        return char(c)
    end))
end

addon.Comms = addon.Comms or {}
local Comms = addon.Comms

function Comms.Sync(prefix, msg)
    local zone = select(2, IsInInstance())
    if zone == "pvp" or zone == "arena" then
        SendAddonMessage(prefix, msg, "BATTLEGROUND")
    elseif GetRealNumRaidMembers() > 0 then
        SendAddonMessage(prefix, msg, "RAID")
    elseif GetRealNumPartyMembers() > 0 then
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





