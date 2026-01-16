local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local itemColors = C.itemColors
addon.State = addon.State or {}
local coreState = addon.State
coreState.loot = coreState.loot or {}
local lootState = coreState.loot
lootState.itemInfo = lootState.itemInfo or {}
local itemInfo = lootState.itemInfo

---============================================================================
-- Loot Helpers Module
-- Manages the loot window items (fetching from loot/inventory).
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Loot = addon.Loot or {}
    local module = addon.Loot
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local lootTable = {}

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    --
    -- Fetches items from the currently open loot window.
    --
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = module:GetItemLink(lootState.currentItemIndex)
        end
        addon:trace(L.LogLootFetchStart:format(GetNumLootItems() or 0, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        for i = 1, GetNumLootItems() do
            if LootSlotIsItem(i) then
                local itemLink = GetLootSlotLink(i)
                if itemLink then
                    local icon, name, quantity, quality = GetLootSlotInfo(i)
                    if GetItemFamily(itemLink) ~= 64 then
                        self:AddItem(itemLink, quantity, name, quality, icon)
                    end
                end
            end
        end

        lootState.currentItemIndex = 1
        if oldItem ~= nil then
            for t = 1, lootState.lootCount do
                if oldItem == module:GetItemLink(t) then
                    lootState.currentItemIndex = t
                    break
                end
            end
        end
        self:PrepareItem()
        if addon.Master and addon.Master.ResetItemCount then
            addon.Master:ResetItemCount()
        end
        addon:trace(L.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    --
    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
    --
    function module:AddItem(itemLink, itemCount, nameHint, rarityHint, textureHint, colorHint)
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

        -- Try to warm the item cache (doesn't guarantee immediate GetItemInfo).
        if (not itemName or not itemRarity or not itemTexture) and type(itemLink) == "string" then
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:SetHyperlink(itemLink)
            GameTooltip:Hide()
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
            addon:warn(L.LogLootItemInfoMissing:format(tostring(itemLink)))
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

    --
    -- Prepares the currently selected item for display.
    --
    function module:PrepareItem()
        if module:ItemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    --
    -- Sets the main item display in the UI.
    --
    function module:SetItem(i)
        if i.itemName and i.itemLink and i.itemTexture and i.itemColor then
            frameName = frameName or Utils.getFrameName()
            if frameName == nil then return end

            local currentItemLink = _G[frameName .. "Name"]
            currentItemLink:SetText(addon.WrapTextInColorCode(
                i.itemName,
                Utils.normalizeHexColor(i.itemColor)
            ))

            local currentItemBtn = _G[frameName .. "ItemBtn"]
            currentItemBtn:SetNormalTexture(i.itemTexture)

            local options = addon.options
            if options.showTooltips then
                currentItemBtn.tooltip_item = i.itemLink
                addon:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
            end
            Utils.triggerEvent("SetItem", i.itemLink)
        end
    end

    --
    -- Selects an item from the loot list by its index.
    --
    function module:SelectItem(i)
        if module:ItemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
            if addon.Master and addon.Master.ResetItemCount then
                addon.Master:ResetItemCount()
            end
        end
    end

    --
    -- Clears all loot from the table and resets the UI display.
    --
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        frameName = frameName or Utils.getFrameName()
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        local masterFrame = addon.UIMaster
        if masterFrame and frameName == masterFrame:GetName() then
            Utils.resetEditBox(_G[frameName .. "ItemCount"], true)
        end
    end

    -- Returns the table for the currently selected item.
    --
    function module:GetItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    function module:GetItemIndex()
        return lootState.currentItemIndex
    end

    --
    -- Returns the name of the currently selected item.
    --
    function module:GetItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    --
    -- Returns the link of the currently selected item.
    --
    function module:GetItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    --
    -- Returns the texture of the currently selected item.
    --
    function module:GetItemTexture(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    function module:GetCurrentItemCount()
        if lootState.fromInventory then
            return itemInfo.count or lootState.itemCount or 1
        end
        local item = module:GetItem()
        local count = item and item.count
        if count and count > 0 then
            return count
        end
        return 1
    end

    --
    -- Checks if a loot item exists at the given index.
    --
    function module:ItemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    --
    -- Checks if an item in the player's bags is soulbound.
    --
    function module:ItemIsSoulbound(bag, slot)
        local tip = KRT_FakeTooltip or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
        KRT_FakeTooltip = tip
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:SetBagItem(bag, slot)
        tip:Show()

        local num = tip:NumLines()
        for i = num, 1, -1 do
            local t = _G["KRT_FakeTooltipTextLeft" .. i]:GetText()
            if addon.Deformat(t, BIND_TRADE_TIME_REMAINING) ~= nil then
                return false
            elseif t == ITEM_SOULBOUND then
                return true
            end
        end

        tip:Hide()
        return false
    end
end
