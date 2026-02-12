--[[
    Features/Loot.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local C = feature.C

local itemColors = feature.itemColors

local lootState = feature.lootState
local itemInfo = feature.itemInfo

local ItemExists, ItemIsSoulbound, GetItem
local GetItemName, GetItemLink, GetItemTexture

local _G = _G
local tremove, twipe = table.remove, table.wipe
local type = type

local tostring, tonumber = tostring, tonumber

-- =========== Loot Helpers Module  =========== --
-- Manages the loot window items (fetching from loot/inventory).
do
    addon.Loot = addon.Loot or {}
    local module = addon.Loot
    local frameName

    local function GetMasterFrameName()
        if frameName then return frameName end
        local mf = (addon.Master and addon.Master.frame) or _G["KRTMaster"]
        if mf and addon.Master and not addon.Master.frame then addon.Master.frame = mf end
        if not mf then return nil end
        frameName = mf:GetName()
        return frameName
    end

    -- ----- Internal state ----- --
    local lootTable = {}

    -- ----- Private helpers ----- --
    local function BuildPendingAwardKey(itemLink, looter)
        return tostring(itemLink) .. "\001" .. tostring(looter)
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
            if LootSlotIsItem(i) then
                local itemLink = GetLootSlotLink(i)
                if itemLink then
                    local icon, name, _, quality = GetLootSlotInfo(i)
                    if GetItemFamily(itemLink) ~= 64 then
                        local key = Utils.getItemStringFromLink(itemLink) or itemLink
                        local existing = indexByItemKey[key]
                        if existing then
                            lootTable[existing].count = (lootTable[existing].count or 1) + 1
                        else
                            local before = lootState.lootCount
                            -- In loot window we treat each slot as one awardable copy (even if quantity > 1).
                            self:AddItem(itemLink, 1, name, quality, icon)
                            if lootState.lootCount > before then
                                indexByItemKey[key] = lootState.lootCount
                                local it = lootTable[lootState.lootCount]
                                if it then
                                    it.itemKey = key
                                end
                            end
                        end
                    end
                end
            end
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
        if addon.Master and addon.Master.ResetItemCount then
            addon.Master:ResetItemCount()
        end
        addon:trace(Diag.D.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
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
        if i.itemName and i.itemLink and i.itemTexture and i.itemColor then
            frameName = GetMasterFrameName()
            if frameName == nil then return end

            local currentItemLink = _G[frameName .. "Name"]
            currentItemLink:SetText(addon.WrapTextInColorCode(
                i.itemName,
                Utils.normalizeHexColor(i.itemColor)
            ))

            local currentItemBtn = _G[frameName .. "ItemBtn"]
            currentItemBtn:SetNormalTexture(i.itemTexture)

            local options = addon.options or KRT_Options or {}
            if options.showTooltips then
                currentItemBtn.tooltip_item = i.itemLink
                addon:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
            end
            Utils.triggerEvent("SetItem", i.itemLink)
        end
    end

    -- Selects an item from the loot list by its index.
    function module:SelectItem(i)
        if ItemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
            if addon.Master and addon.Master.ResetItemCount then
                addon.Master:ResetItemCount()
            end
        end
    end

    -- Clears all loot from the table and resets the UI display.
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        frameName = GetMasterFrameName()
        if not frameName then return end
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        local itemBtn = _G[frameName .. "ItemBtn"]
        itemBtn.tooltip_item = nil
        GameTooltip:Hide()
        local mf = addon.Master and addon.Master.frame
        if mf and frameName == mf:GetName() then
            Utils.resetEditBox(_G[frameName .. "ItemCount"], true)
        end
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
        local tip = KRT_FakeTooltip or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
        KRT_FakeTooltip = tip
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:SetBagItem(bag, slot)
        tip:Show()

        local num = tip:NumLines()
        local isSoulbound = false
        for i = num, 1, -1 do
            local fs = _G["KRT_FakeTooltipTextLeft" .. i]
            local t = fs and fs:GetText() or nil
            if t and t ~= "" then
                -- Fast check first: exact global string compare.
                if t == ITEM_SOULBOUND then
                    isSoulbound = true
                end
                if addon.Deformat(t, BIND_TRADE_TIME_REMAINING) ~= nil then
                    tip:Hide()
                    return false
                end
            end
        end

        tip:Hide()
        return isSoulbound
    end

    -- Cross-module bridge for split files (Rolls/Master).
    module.GetItem = GetItem
    module.GetItemName = GetItemName
    module.GetItemLink = GetItemLink
    module.GetItemTexture = GetItemTexture
    module.ItemExists = ItemExists
    module.ItemIsSoulbound = ItemIsSoulbound
end
