-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- exports: publish module APIs on addon.*
-- notes: infra adapter for tooltip-based item metadata probing

local addon = select(2, ...)

addon.ItemProbe = addon.ItemProbe or {}
local ItemProbe = addon.ItemProbe

local _G = _G
local type = type
local pcall = pcall

local TOOLTIP_NAME = "KRT_ItemProbeTooltip"
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

function ItemProbe.WarmItemCache(itemLink)
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

function ItemProbe.IsBagItemSoulbound(bag, slot)
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
