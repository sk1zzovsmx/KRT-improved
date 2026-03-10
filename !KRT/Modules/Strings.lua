-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, tostring = type, tostring
local find, gsub = string.find, string.gsub
local strsub = string.sub
local format = string.format
local lower, upper = string.lower, string.upper

local GetAchievementLink = GetAchievementLink

local Colors = feature.Colors or addon.Colors or {}

addon.Strings = addon.Strings or feature.Strings or {}
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
