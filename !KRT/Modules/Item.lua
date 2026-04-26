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
local tonumber = tonumber
local pcall = pcall

local ITEM_LINK_FORMAT = "|c%s|Hitem:%d:%s|h[%s]|h|r"
local TOOLTIP_NAME = "KRT_ItemTooltip"
local tooltip
local ITEM_CACHE_POLL_SECONDS = 0.30
local ITEM_CACHE_TIMEOUT_SECONDS = 3.00
local BIND_ON_PICKUP = _G.LE_ITEM_BIND_ON_ACQUIRE or 1
local BIND_ON_EQUIP = _G.LE_ITEM_BIND_ON_EQUIP or 2
local BIND_ON_USE = _G.LE_ITEM_BIND_ON_USE or 3
local BIND_QUEST = _G.LE_ITEM_BIND_QUEST or 4

-- ----- Internal state ----- --
local pendingItemRequests = {}
local itemRequestTicker
local itemRequestRepeats = false

-- ----- Private helpers ----- --
local function ensureTooltip()
    if tooltip then
        return tooltip
    end

    tooltip = _G[TOOLTIP_NAME] or CreateFrame("GameTooltip", TOOLTIP_NAME, nil, "GameTooltipTemplate")
    return tooltip
end

local function setTooltipOwner(tip)
    local owner = UIParent or WorldFrame
    if owner and type(tip.SetOwner) == "function" then
        tip:SetOwner(owner, "ANCHOR_NONE")
    end
end

local function getNow()
    local getTime = _G.GetTime
    if type(getTime) == "function" then
        return tonumber(getTime()) or 0
    end
    return 0
end

local function safeCallback(callback, ...)
    if type(callback) == "function" then
        callback(...)
    end
end

local function normalizeTimeoutSeconds(timeoutSeconds)
    local timeout = tonumber(timeoutSeconds) or ITEM_CACHE_TIMEOUT_SECONDS
    if timeout <= 0 then
        timeout = ITEM_CACHE_TIMEOUT_SECONDS
    end
    return timeout
end

local function buildItemFallbackLink(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return nil
    end
    return "item:" .. tostring(itemId) .. ":0:0:0:0:0:0:0"
end

local function getItemSnapshot(itemRef)
    local getItemInfo = _G.GetItemInfo
    if type(getItemInfo) ~= "function" then
        return nil
    end

    local name, link, rarity, _, _, _, _, _, _, texture = getItemInfo(itemRef)
    if not name and type(itemRef) == "number" then
        name, link, rarity, _, _, _, _, _, _, texture = getItemInfo(buildItemFallbackLink(itemRef))
    end
    if not name and not link then
        return nil
    end

    local itemId = Item.GetItemIdFromLink(link) or Item.GetItemIdFromLink(itemRef)
    return {
        itemId = itemId,
        itemName = name,
        itemLink = link,
        itemRarity = rarity,
        itemTexture = texture,
        itemRef = itemRef,
    }
end

local function warmItemRef(itemRef)
    if type(itemRef) == "string" then
        return Item.WarmItemCache(itemRef)
    end

    local fallbackLink = buildItemFallbackLink(itemRef)
    if fallbackLink then
        return Item.WarmItemCache(fallbackLink)
    end
    return false
end

local function cancelItemRequestTicker()
    if itemRequestTicker then
        addon.CancelTimer(itemRequestTicker, true)
        itemRequestTicker = nil
        itemRequestRepeats = false
    end
end

local processItemRequests

local function ensureItemRequestTicker()
    if itemRequestTicker then
        return
    end
    if type(addon.NewTicker) == "function" then
        itemRequestTicker = addon.NewTicker(ITEM_CACHE_POLL_SECONDS, processItemRequests)
        itemRequestRepeats = true
    elseif type(addon.NewTimer) == "function" then
        itemRequestTicker = addon.NewTimer(ITEM_CACHE_POLL_SECONDS, processItemRequests)
        itemRequestRepeats = false
    end
end

processItemRequests = function()
    if not itemRequestRepeats then
        itemRequestTicker = nil
    end

    local now = getNow()
    local nextRequests = {}

    for i = 1, #pendingItemRequests do
        local request = pendingItemRequests[i]
        if request.cancelled then
            -- Dropped below.
        else
            local snapshot = getItemSnapshot(request.itemRef)
            if snapshot then
                request.cancelled = true
                safeCallback(request.callback, snapshot, true)
            elseif now >= request.expiresAt then
                request.cancelled = true
                safeCallback(request.callback, nil, false, "timeout")
            else
                warmItemRef(request.itemRef)
                nextRequests[#nextRequests + 1] = request
            end
        end
    end

    pendingItemRequests = nextRequests
    if #pendingItemRequests == 0 then
        cancelItemRequestTicker()
    elseif type(addon.NewTimer) == "function" and not itemRequestTicker then
        ensureItemRequestTicker()
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

local function scanBindType(tip)
    local numLines = tip:NumLines() or 0
    local bindOnPickup = _G.ITEM_BIND_ON_PICKUP or "Binds when picked up"
    local bindOnEquip = _G.ITEM_BIND_ON_EQUIP or "Binds when equipped"
    local bindOnUse = _G.ITEM_BIND_ON_USE or "Binds when used"
    local bindQuest = _G.ITEM_BIND_QUEST or "Quest Item"

    for i = 1, numLines do
        local line = _G[TOOLTIP_NAME .. "TextLeft" .. i]
        local text = line and line:GetText() or nil
        if text and text ~= "" then
            if text == bindOnPickup or text == ITEM_SOULBOUND then
                return BIND_ON_PICKUP
            end
            if text == bindOnEquip then
                return BIND_ON_EQUIP
            end
            if text == bindOnUse then
                return BIND_ON_USE
            end
            if text == bindQuest then
                return BIND_QUEST
            end
        end
    end

    return nil
end

-- ----- Public methods ----- --
function Item.GetItemIdFromLink(itemLink)
    if type(itemLink) == "number" then
        return itemLink
    end
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end
    local directId = itemLink:match("item:(%d+)")
    if directId then
        return tonumber(directId)
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
    if type(tip.ClearLines) == "function" then
        tip:ClearLines()
    end
    local ok = pcall(tip.SetHyperlink, tip, itemLink)
    if type(tip.Hide) == "function" then
        tip:Hide()
    end
    return ok == true
end

function Item.RequestItemInfo(itemRef, callback, timeoutSeconds)
    if type(callback) ~= "function" then
        return nil, "callback_required"
    end
    if type(itemRef) ~= "string" and type(itemRef) ~= "number" then
        return nil, "invalid_item"
    end

    local snapshot = getItemSnapshot(itemRef)
    if snapshot then
        safeCallback(callback, snapshot, true)
        return {
            Cancel = function()
                return false
            end,
            IsCancelled = function()
                return true
            end,
        }
    end

    warmItemRef(itemRef)

    local request = {
        itemRef = itemRef,
        callback = callback,
        expiresAt = getNow() + normalizeTimeoutSeconds(timeoutSeconds),
        cancelled = false,
    }
    pendingItemRequests[#pendingItemRequests + 1] = request
    ensureItemRequestTicker()

    local handle = {}
    function handle:Cancel()
        if request.cancelled then
            return false
        end
        request.cancelled = true
        return true
    end
    function handle:IsCancelled()
        return request.cancelled == true
    end
    return handle
end

function Item.GetItemBindFromTooltip(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end

    local tip = ensureTooltip()
    setTooltipOwner(tip)
    if type(tip.ClearLines) == "function" then
        tip:ClearLines()
    end
    local ok = pcall(tip.SetHyperlink, tip, itemLink)
    if not ok then
        if type(tip.Hide) == "function" then
            tip:Hide()
        end
        return nil
    end

    local bindType = scanBindType(tip)
    if type(tip.Hide) == "function" then
        tip:Hide()
    end
    return bindType
end

function Item.IsBagItemSoulbound(bag, slot)
    if bag == nil or slot == nil then
        return false
    end

    local tip = ensureTooltip()
    setTooltipOwner(tip)
    if type(tip.ClearLines) == "function" then
        tip:ClearLines()
    end
    local ok = pcall(tip.SetBagItem, tip, bag, slot)
    if not ok then
        if type(tip.Hide) == "function" then
            tip:Hide()
        end
        return false
    end

    local isSoulbound = scanSoulboundFlag(tip)
    if type(tip.Hide) == "function" then
        tip:Hide()
    end
    return isSoulbound
end
