-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag

local Events = feature.Events or addon.Events or {}
local C = feature.C
local Bus = feature.Bus or addon.Bus
local Item = feature.Item or addon.Item

local itemColors = feature.itemColors

local InternalEvents = Events.Internal

local lootState = feature.lootState
local itemInfo = feature.itemInfo

local itemExists, itemIsSoulbound, getItem
local getItemName, getItemLink, getItemTexture

local tremove, twipe = table.remove, table.wipe
local type, pairs = type, pairs

local tostring, tonumber = tostring, tonumber
local PENDING_AWARD_TTL_SECONDS = C.PENDING_AWARD_TTL_SECONDS

-- =========== Loot Helpers Module  =========== --
-- Manages the loot window items (fetching from loot/inventory).
do
    addon.Services = addon.Services or {}
    addon.Services.Loot = addon.Services.Loot or {}
    local module = addon.Services.Loot

    -- ----- Internal state ----- --
    local lootTable = {}

    -- ----- Private helpers ----- --
    local function normalizePendingAwardItemKey(itemLink)
        local itemKey = Item.GetItemStringFromLink(itemLink)
        if itemKey and itemKey ~= "" then
            return itemKey
        end
        return itemLink
    end

    local function buildPendingAwardKey(itemLink, looter, useRawItemLink)
        local itemKey = useRawItemLink and itemLink or normalizePendingAwardItemKey(itemLink)
        return tostring(itemKey) .. "\001" .. tostring(looter)
    end

    local function warmItemCache(itemLink)
        local probe = Item or addon.Item
        if probe and probe.WarmItemCache then
            probe.WarmItemCache(itemLink)
        end
    end

    local function isBagItemSoulbound(bag, slot)
        local probe = Item or addon.Item
        if probe and probe.IsBagItemSoulbound then
            return probe.IsBagItemSoulbound(bag, slot)
        end
        return false
    end

    local function addLootWindowSlot(indexByItemKey, slot)
        if not LootSlotIsItem(slot) then
            return
        end

        local itemLink = GetLootSlotLink(slot)
        if not itemLink or GetItemFamily(itemLink) == 64 then
            return
        end

        local key = Item.GetItemStringFromLink(itemLink) or itemLink
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
    function module:QueuePendingAward(itemLink, looter, rollType, rollValue, rollSessionId)
        if not itemLink or not looter then
            return
        end
        local key = buildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if not list then
            local rawLinkKey = buildPendingAwardKey(itemLink, looter, true)
            if rawLinkKey ~= key and lootState.pendingAwards[rawLinkKey] then
                list = lootState.pendingAwards[rawLinkKey]
                lootState.pendingAwards[key] = list
                lootState.pendingAwards[rawLinkKey] = nil
            end
        end
        if not list then
            list = {}
            lootState.pendingAwards[key] = list
        end
        list[#list + 1] = {
            itemLink = itemLink,
            looter = looter,
            rollType = rollType,
            rollValue = rollValue,
            rollSessionId = rollSessionId and tostring(rollSessionId) or nil,
            ts = GetTime(),
        }
    end

    function module:ConsumePendingAward(itemLink, looter, maxAge)
        local ttl = tonumber(maxAge) or PENDING_AWARD_TTL_SECONDS
        if ttl < 0 then
            ttl = 0
        end
        local key = buildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if not list then
            local rawLinkKey = buildPendingAwardKey(itemLink, looter, true)
            if rawLinkKey ~= key then
                key = rawLinkKey
                list = lootState.pendingAwards[key]
            end
        end
        if not list then
            return nil
        end
        local now = GetTime()
        for i = 1, #list do
            local p = list[i]
            if p and (now - (p.ts or 0)) <= ttl then
                tremove(list, i)
                local remaining = #list
                if #list == 0 then
                    lootState.pendingAwards[key] = nil
                end
                addon:debug(Diag.D.LogLootPendingAwardConsumed:format(tostring(itemLink), tostring(looter), remaining, ttl))
                return p
            end
        end
        for i = #list, 1, -1 do
            local p = list[i]
            if not p or (now - (p.ts or 0)) > ttl then
                tremove(list, i)
            end
        end
        if #list == 0 then
            lootState.pendingAwards[key] = nil
        end
        return nil
    end

    function module:PurgePendingAwards(maxAge)
        local ttl = tonumber(maxAge) or PENDING_AWARD_TTL_SECONDS
        if ttl < 0 then
            ttl = 0
        end
        local now = GetTime()
        for key, list in pairs(lootState.pendingAwards) do
            if type(list) ~= "table" then
                lootState.pendingAwards[key] = nil
            else
                for i = #list, 1, -1 do
                    local p = list[i]
                    if not p or (now - (p.ts or 0)) > ttl then
                        tremove(list, i)
                    end
                end
                if #list == 0 then
                    lootState.pendingAwards[key] = nil
                end
            end
        end
    end

    -- Fetches items from the currently open loot window.
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = getItemLink(lootState.currentItemIndex)
        end
        addon:trace(Diag.D.LogLootFetchStart:format(GetNumLootItems() or 0, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        local indexByItemKey = {}
        for i = 1, GetNumLootItems() do
            -- In loot window we treat each slot as one awardable copy (even if quantity > 1).
            addLootWindowSlot(indexByItemKey, i)
        end

        lootState.currentItemIndex = 1
        if oldItem ~= nil then
            for t = 1, lootState.lootCount do
                if oldItem == getItemLink(t) then
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
            if rarity < lootThreshold then
                return
            end
            lootState.lootCount = lootState.lootCount + 1
        else
            lootState.lootCount = 1
            lootState.currentItemIndex = 1
        end
        lootTable[lootState.lootCount] = {}
        lootTable[lootState.lootCount].itemName = itemName
        lootTable[lootState.lootCount].itemColor = itemColor
        lootTable[lootState.lootCount].itemLink = itemLink
        lootTable[lootState.lootCount].itemTexture = itemTexture
        lootTable[lootState.lootCount].count = itemCount or 1
    end

    -- Prepares the currently selected item for display.
    function module:PrepareItem()
        if itemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    -- Sets the main item display in the UI.
    function module:SetItem(i)
        if not i then
            Bus.TriggerEvent(InternalEvents.SetItem, nil, nil)
            return
        end
        if not (i.itemName and i.itemLink and i.itemTexture and i.itemColor) then
            return
        end
        Bus.TriggerEvent(InternalEvents.SetItem, i.itemLink, i)
    end

    -- Selects an item from the loot list by its index.
    function module:SelectItem(i)
        if itemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
        end
    end

    -- Clears all loot from the table and resets the UI display.
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        Bus.TriggerEvent(InternalEvents.SetItem, nil, nil)
    end

    -- Returns the table for the currently selected item.
    function getItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    -- Returns the name of the currently selected item.
    function getItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    -- Returns the link of the currently selected item.
    function getItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    -- Returns the texture of the currently selected item.
    function getItemTexture(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    function module:GetCurrentItemCount()
        if lootState.fromInventory then
            return itemInfo.count or lootState.selectedItemCount or 1
        end
        local item = getItem()
        local count = item and item.count
        if count and count > 0 then
            return count
        end
        return 1
    end

    -- Checks if a loot item exists at the given index.
    function itemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    -- Checks if an item in the player's bags is soulbound.
    function itemIsSoulbound(bag, slot)
        return isBagItemSoulbound(bag, slot)
    end

    -- Cross-module bridge for split files (Rolls/Master).
    module.WarmItemCache = warmItemCache
    module.IsBagItemSoulbound = isBagItemSoulbound
    module.GetItem = getItem
    module.GetItemName = getItemName
    module.GetItemLink = getItemLink
    module.GetItemTexture = getItemTexture
    module.ItemExists = itemExists
    module.ItemIsSoulbound = itemIsSoulbound
end
