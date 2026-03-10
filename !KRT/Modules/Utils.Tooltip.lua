-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local _G = _G
local type, ipairs, pcall = type, ipairs, pcall

local function CreateFrame(...)
    return _G.CreateFrame(...)
end

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.Tooltip = Utils.Tooltip or {}
local Tooltip = Utils.Tooltip

local colors = HIGHLIGHT_FONT_COLOR
local fakeBagTooltip
local warmItemTooltip

local function showTooltip(frame)
    if not frame.tooltip_anchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, frame.tooltip_anchor)
    end

    if frame.tooltip_title then
        GameTooltip:SetText(frame.tooltip_title)
    end

    if frame.tooltip_text then
        if type(frame.tooltip_text) == "string" then
            GameTooltip:AddLine(frame.tooltip_text, colors.r, colors.g, colors.b, true)
        elseif type(frame.tooltip_text) == "table" then
            for _, line in ipairs(frame.tooltip_text) do
                GameTooltip:AddLine(line, colors.r, colors.g, colors.b, true)
            end
        end
    end

    if frame.tooltip_item then
        GameTooltip:SetHyperlink(frame.tooltip_item)
    end

    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

function Tooltip.setTooltip(frame, text, anchor, title)
    if not frame then
        return
    end
    frame.tooltip_text = text and text or frame.tooltip_text
    frame.tooltip_anchor = anchor and anchor or frame.tooltip_anchor
    frame.tooltip_title = title and title or frame.tooltip_title
    if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then
        return
    end
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", hideTooltip)
end

-- Warm item cache using a hidden tooltip (nil-safe, no return value).
function Tooltip.warmItemCache(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return
    end
    if not itemLink:find("item:", 1, true) then
        return
    end

    warmItemTooltip = warmItemTooltip or CreateFrame("GameTooltip", nil, UIParent, "GameTooltipTemplate")
    warmItemTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = pcall(warmItemTooltip.SetHyperlink, warmItemTooltip, itemLink)
    if ok then
        warmItemTooltip:Hide()
    end
end

-- Tooltip-based soulbound check for bag items (3.3.5a-safe).
function Tooltip.isBagItemSoulbound(bag, slot)
    if bag == nil or slot == nil then
        return false
    end

    fakeBagTooltip = fakeBagTooltip or KRT_FakeTooltip
        or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
    KRT_FakeTooltip = fakeBagTooltip
    fakeBagTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    fakeBagTooltip:SetBagItem(bag, slot)
    fakeBagTooltip:Show()

    local isSoulbound = false
    local numLines = fakeBagTooltip:NumLines() or 0
    for i = numLines, 1, -1 do
        local fs = _G["KRT_FakeTooltipTextLeft" .. i]
        local text = fs and fs:GetText() or nil
        if text and text ~= "" then
            if text == ITEM_SOULBOUND then
                isSoulbound = true
            end
            if addon.Deformat(text, BIND_TRADE_TIME_REMAINING) ~= nil then
                fakeBagTooltip:Hide()
                return false
            end
        end
    end

    fakeBagTooltip:Hide()
    return isSoulbound
end
