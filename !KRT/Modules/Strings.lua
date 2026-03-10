-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type, tostring = type, tostring
local find = string.find
local format, gsub = string.format, string.gsub
local strsub = string.sub
local lower, upper = string.lower, string.upper

local GetAchievementLink = GetAchievementLink

local ITEM_LINK_FORMAT = "|c%s|Hitem:%d:%s|h[%s]|h|r"

addon.Strings = addon.Strings or {}
local Strings = addon.Strings

local function trimRaw(value)
    if value == nil then
        return ""
    end
    return gsub(tostring(value), "^%s*(.-)%s*$", "%1")
end

function Strings.ucfirst(value)
    if type(value) ~= "string" then
        value = tostring(value or "")
    end
    value = lower(value)
    return gsub(value, "%a", upper, 1)
end

function Strings.trimText(value, allowNil)
    if value == nil then
        return allowNil and nil or ""
    end
    return trimRaw(value)
end

function Strings.normalizeName(value, allowNil)
    local text = Strings.trimText(value, allowNil)
    if text == nil then
        return nil
    end
    return Strings.ucfirst(text)
end

function Strings.normalizeLower(value, allowNil)
    local text = Strings.trimText(value, allowNil)
    if text == nil then
        return nil
    end
    return lower(text)
end

function Strings.findAchievement(inp)
    local out = trimRaw(inp)
    if out ~= "" and find(out, "%{%d*%}") then
        local b, e = find(out, "%{%d*%}")
        local id = strsub(out, b + 1, e - 1)
        local link = (id and id ~= "" and GetAchievementLink(id)) or ("[" .. id .. "]")
        out = strsub(out, 1, b - 1) .. link .. strsub(out, e + 1)
    end
    return out
end

function Strings.formatChatMessage(text, prefix, outputFormat, prefixHex)
    local msgPrefix = prefix or ""
    if prefixHex then
        local Colors = addon.Colors
        local normalized = Colors and Colors.normalizeHexColor and Colors.normalizeHexColor(prefixHex) or "ffffffff"
        msgPrefix = addon.WrapTextInColorCode(msgPrefix, normalized)
    end
    return format(outputFormat or "%s%s", msgPrefix, tostring(text))
end

function Strings.splitArgs(msg)
    msg = Strings.trimText(msg)
    if msg == "" then
        return "", ""
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    return Strings.normalizeLower(cmd), Strings.trimText(rest)
end

function Strings.getItemIdFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local _, itemId = addon.Deformat(itemLink, ITEM_LINK_FORMAT)
    return itemId
end

function Strings.getItemStringFromLink(itemLink)
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
