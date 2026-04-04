-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- notes: consolidated item helpers + tooltip-based item metadata probing

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

addon.Item = addon.Item or feature.Item or {}
local Item = addon.Item

local _G = _G
local type, tostring = type, tostring
local pcall = pcall

local ITEM_LINK_FORMAT = "|c%s|Hitem:%d:%s|h[%s]|h|r"
local TOOLTIP_NAME = "KRT_ItemTooltip"
local tooltip

local function ensureTooltip()
    if tooltip then
        return tooltip
    end

    tooltip = _G[TOOLTIP_NAME] or CreateFrame("GameTooltip", TOOLTIP_NAME, nil, "GameTooltipTemplate")
    return tooltip
end

local function setTooltipOwner(tip)
    local owner = UIParent or WorldFrame
    if owner then
        tip:SetOwner(owner, "ANCHOR_NONE")
    end
end

local function scanSoulboundFlag(tip)
    local numLines = tip:NumLines() or 0
    for i = numLines, 1, -1 do
        local line = _G[TOOLTIP_NAME .. "TextLeft" .. i]
        local text = line and line:GetText() or nil
        if text and text ~= "" then
            if text == ITEM_SOULBOUND then
                return true
            end

            if addon.Deformat and addon.Deformat(text, BIND_TRADE_TIME_REMAINING) ~= nil then
                return false
            end
        end
    end

    return false
end

function Item.GetItemIdFromLink(itemLink)
    if type(itemLink) == "number" then
        return itemLink
    end
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end
    local _, itemId = addon.Deformat(itemLink, ITEM_LINK_FORMAT)
    return itemId
end

function Item.GetItemStringFromLink(itemLink)
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

function Item.WarmItemCache(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return false
    end
    if not itemLink:find("item:", 1, true) then
        return false
    end

    local tip = ensureTooltip()
    setTooltipOwner(tip)
    tip:ClearLines()
    local ok = pcall(tip.SetHyperlink, tip, itemLink)
    tip:Hide()
    return ok == true
end

function Item.IsBagItemSoulbound(bag, slot)
    if bag == nil or slot == nil then
        return false
    end

    local tip = ensureTooltip()
    setTooltipOwner(tip)
    tip:ClearLines()
    local ok = pcall(tip.SetBagItem, tip, bag, slot)
    if not ok then
        tip:Hide()
        return false
    end

    local isSoulbound = scanSoulboundFlag(tip)
    tip:Hide()
    return isSoulbound
end
