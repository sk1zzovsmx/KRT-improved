-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local Diag = feature.Diag
local Utils = feature.Utils
local Events = feature.Events or addon.Events or {}
local C = feature.C
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings

local itemColors = feature.itemColors

local InternalEvents = Events.Internal

local lootState = feature.lootState
local itemInfo = feature.itemInfo

local ItemExists, ItemIsSoulbound, GetItem
local GetItemName, GetItemLink, GetItemTexture

local tremove, twipe = table.remove, table.wipe
local type = type
local pcall = pcall

local tostring, tonumber = tostring, tonumber

-- =========== Loot Helpers Module  =========== --
-- Manages the loot window items (fetching from loot/inventory).
do
    addon.Services = addon.Services or {}
    addon.Services.Loot = addon.Services.Loot or addon.Loot or {}
    addon.Loot = addon.Services.Loot -- Legacy alias during namespacing migration.
    local module = addon.Services.Loot

    -- ----- Internal state ----- --
    local lootTable = {}
    local fakeBagTooltip
    local warmItemTooltip

    -- ----- Private helpers ----- --
    local function BuildPendingAwardKey(itemLink, looter)
        return tostring(itemLink) .. "\001" .. tostring(looter)
    end

    local function warmItemCache(itemLink)
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

    local function isBagItemSoulbound(bag, slot)
        if bag == nil or slot == nil then
            return false
        end

        fakeBagTooltip = fakeBagTooltip or KRT_FakeTooltip
            or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
        KRT_FakeTooltip = fakeBagTooltip
        fakeBagTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        fakeBagTooltip:SetBagItem(bag, slot)
        fakeBagTooltip:Show()

        local linePrefix = "KRT_FakeTooltipTextLeft"
        local isSoulbound = false
        local numLines = fakeBagTooltip:NumLines() or 0
        for i = numLines, 1, -1 do
            local fs = _G[linePrefix .. i]
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

    local function AddLootWindowSlot(indexByItemKey, slot)
        if not LootSlotIsItem(slot) then
            return
        end

        local itemLink = GetLootSlotLink(slot)
        if not itemLink or GetItemFamily(itemLink) == 64 then
            return
        end

        local key = Strings.getItemStringFromLink(itemLink) or itemLink
        local existing = indexByItemKey[key]
        if existing then
            lootTable[existing].count = (lootTable[existing].count or 1) + 1
            return
        end

        local icon, name, _, quality = GetLootSlotInfo(slot)
        local before = lootState.lootCount
        module:AddItem(itemLink, 1, name, quality, icon)
        if lootState.lootCount > before then
            indexByItemKey[key] = lootState.lootCount
            local item = lootTable[lootState.lootCount]
            if item then
                item.itemKey = key
            end
        end
    end

    -- ----- Public methods ----- --
    -- Pending award helpers (shared with Master/Raid flows).
    function module:QueuePendingAward(itemLink, looter, rollType, rollValue)
        if not itemLink or not looter then
            return
        end
        local key = BuildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if not list then
            list = {}
            lootState.pendingAwards[key] = list
        end
        list[#list + 1] = {
            itemLink  = itemLink,
            looter    = looter,
            rollType  = rollType,
            rollValue = rollValue,
            ts        = GetTime(),
        }
    end

    function module:ConsumePendingAward(itemLink, looter, maxAge)
        local key = BuildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if not list then
            return nil
        end
        local now = GetTime()
        for i = 1, #list do
            local p = list[i]
            if p and (now - (p.ts or 0)) <= maxAge then
                tremove(list, i)
                if #list == 0 then
                    lootState.pendingAwards[key] = nil
                end
                return p
            end
        end
        for i = #list, 1, -1 do
            local p = list[i]
            if not p or (now - (p.ts or 0)) > maxAge then
                tremove(list, i)
            end
        end
        if #list == 0 then
            lootState.pendingAwards[key] = nil
        end
        return nil
    end

    -- Fetches items from the currently open loot window.
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = GetItemLink(lootState.currentItemIndex)
        end
        addon:trace(Diag.D.LogLootFetchStart:format(GetNumLootItems() or 0, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        local indexByItemKey = {}
        for i = 1, GetNumLootItems() do
            -- In loot window we treat each slot as one awardable copy (even if quantity > 1).
            AddLootWindowSlot(indexByItemKey, i)
        end

        lootState.currentItemIndex = 1
        if oldItem ~= nil then
            for t = 1, lootState.lootCount do
                if oldItem == GetItemLink(t) then
                    lootState.currentItemIndex = t
                    break
                end
            end
        end
        self:PrepareItem()
        addon:trace(Diag.D.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
    function module:AddItem(itemLink, itemCount, nameHint, rarityHint, textureHint, colorHint)
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

        -- Try to warm the item cache (doesn't guarantee immediate GetItemInfo).
        if (not itemName or not itemRarity or not itemTexture) and type(itemLink) == "string" then
            warmItemCache(itemLink)
        end

        if not itemName then
            itemName = nameHint
            if not itemName and type(itemLink) == "string" then
                itemName = itemLink:match("%[(.-)%]")
            end
        end

        if not itemRarity then
            itemRarity = rarityHint
        end

        if not itemTexture then
            itemTexture = textureHint
        end

        -- Prefer: explicit hint > link color > rarity color table.
        local itemColor = colorHint
        if not itemColor and type(itemLink) == "string" then
            itemColor = itemLink:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
        end
        if not itemColor then
            local r = tonumber(itemRarity) or 1
            itemColor = itemColors[r + 1] or itemColors[2]
        end

        if not itemName then
            addon:debug(Diag.D.LogLootItemInfoMissing:format(tostring(itemLink)))
            itemName = tostring(itemLink)
        end

        itemTexture = itemTexture or C.RESERVES_ITEM_FALLBACK_ICON

        if lootState.fromInventory == false then
            local lootThreshold = GetLootThreshold() or 2
            local rarity = tonumber(itemRarity) or 1
            if rarity < lootThreshold then return end
            lootState.lootCount = lootState.lootCount + 1
        else
            lootState.lootCount = 1
            lootState.currentItemIndex = 1
        end
        lootTable[lootState.lootCount]             = {}
        lootTable[lootState.lootCount].itemName    = itemName
        lootTable[lootState.lootCount].itemColor   = itemColor
        lootTable[lootState.lootCount].itemLink    = itemLink
        lootTable[lootState.lootCount].itemTexture = itemTexture
        lootTable[lootState.lootCount].count       = itemCount or 1
    end

    -- Prepares the currently selected item for display.
    function module:PrepareItem()
        if ItemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    -- Sets the main item display in the UI.
    function module:SetItem(i)
        if not i then
            Bus.triggerEvent(InternalEvents.SetItem, nil, nil)
            return
        end
        if not (i.itemName and i.itemLink and i.itemTexture and i.itemColor) then return end
        Bus.triggerEvent(InternalEvents.SetItem, i.itemLink, i)
    end

    -- Selects an item from the loot list by its index.
    function module:SelectItem(i)
        if ItemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
        end
    end

    -- Clears all loot from the table and resets the UI display.
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        Bus.triggerEvent(InternalEvents.SetItem, nil, nil)
    end

    -- Returns the table for the currently selected item.
    function GetItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    -- Returns the name of the currently selected item.
    function GetItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    -- Returns the link of the currently selected item.
    function GetItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    -- Returns the texture of the currently selected item.
    function GetItemTexture(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    function module:GetCurrentItemCount()
        if lootState.fromInventory then
            return itemInfo.count or lootState.itemCount or 1
        end
        local item = GetItem()
        local count = item and item.count
        if count and count > 0 then
            return count
        end
        return 1
    end

    -- Checks if a loot item exists at the given index.
    function ItemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    -- Checks if an item in the player's bags is soulbound.
    function ItemIsSoulbound(bag, slot)
        return isBagItemSoulbound(bag, slot)
    end

    -- Cross-module bridge for split files (Rolls/Master).
    module.warmItemCache = warmItemCache
    module.isBagItemSoulbound = isBagItemSoulbound
    module.GetItem = GetItem
    module.GetItemName = GetItemName
    module.GetItemLink = GetItemLink
    module.GetItemTexture = GetItemTexture
    module.ItemExists = ItemExists
    module.ItemIsSoulbound = ItemIsSoulbound
end
