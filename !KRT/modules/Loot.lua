local addonName, addon = ...
addon.Loot = {}
local Loot = addon.Loot

	local frameName

	local lootTable = {}
	local currentItemIndex = 0

	-- Fetches the loot:
	function addon:FetchLoot()
		addon:Debug("DEBUG", "Fetching loot from loot window.")
		local oldItem
		if lootCount >= 1 then
			oldItem = GetItemLink(currentItemIndex)
		end
		lootOpened = true
		fromInventory = false
		self:ClearLoot()

		for i = 1, GetNumLootItems() do
			if LootSlotIsItem(i) then
				local itemLink = GetLootSlotLink(i)
				if GetItemFamily(itemLink) ~= 64 then -- no DE mat!
					self:AddItem(itemLink)
				end
			end
		end

		currentItemIndex = 1
		if oldItem ~= nil then
			for t = 1, lootCount do
				if oldItem == GetItemLink(t) then
					currentItemIndex = t
					break
				end
			end
		end
		addon:Debug("DEBUG", "Loot fetch complete. Current index: %d", currentItemIndex)
		self:PrepareItem()
	end

	-- Add item to loot table:
	function addon:AddItem(itemLink)
		addon:Debug("DEBUG", "Adding item to loot table: %s", tostring(itemLink))
		local itemName, _, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemLink)

		if not itemName or not itemRarity then
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:SetHyperlink(itemLink)
			GameTooltip:Hide()
			addon:Debug("DEBUG", "Item info not available yet, deferring.")
			return
		end

		if fromInventory == false then
			local lootThreshold = GetLootThreshold()
			if itemRarity < lootThreshold then
				addon:Debug("DEBUG", "Item rarity below threshold. Ignoring: %s", itemName)
				return
			end
			lootCount = lootCount + 1
		else
			lootCount = 1
			currentItemIndex = 1
		end

		lootTable[lootCount]             = {}
		lootTable[lootCount].itemName    = itemName
		lootTable[lootCount].itemColor   = itemColors[itemRarity+1]
		lootTable[lootCount].itemLink    = itemLink
		lootTable[lootCount].itemTexture = itemTexture
		TriggerEvent("AddItem", itemLink)
	end

	-- Prepare item display:
	function addon:PrepareItem()
		addon:Debug("DEBUG", "Preparing item for display. Index: %d", currentItemIndex)
		if ItemExists(currentItemIndex) then
			self:SetItem(lootTable[currentItemIndex])
		else
			addon:Debug("DEBUG", "No item exists at index %d", currentItemIndex)
		end
	end

	-- Set item's display:
	function addon:SetItem(i)
		addon:Debug("DEBUG", "Setting item display: %s", i.itemName or "NIL")
		if i.itemName and i.itemLink and i.itemTexture and i.itemColor then
			frameName = frameName or self:GetFrameName()
			if frameName == nil then return end

			local currentItemLink = _G[frameName.."Name"]
			currentItemLink:SetText("|c"..i.itemColor..i.itemName.."|r")

			local currentItemBtn = _G[frameName.."ItemBtn"]
			currentItemBtn:SetNormalTexture(i.itemTexture)

			if self.options.showTooltips then
				currentItemBtn.tooltip_item = i.itemLink
				self:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
			end
			TriggerEvent("SetItem", i.itemLink)
		end

	end

	-- Select an item:
	function addon:SelectItem(i)
		addon:Debug("DEBUG", "Selecting item at index: %d", i)
		if ItemExists(i) then
			currentItemIndex = i
			self:PrepareItem()
		end
	end

	-- Clear all loot:
	function addon:ClearLoot()
		addon:Debug("DEBUG", "Clearing loot.")
		lootTable = twipe(lootTable)
		lootCount = 0
		frameName = frameName or self:GetFrameName()
		_G[frameName.."Name"]:SetText(L.StrNoItemSelected)
		_G[frameName.."ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
		if frameName == UIMaster:GetName() then
			_G[frameName.."ItemCount"]:SetText("")
			_G[frameName.."ItemCount"]:ClearFocus()
			_G[frameName.."ItemCount"]:Hide()
		end
	end

	-- Returns the current item index:
	function GetItemIndex()
		return currentItemIndex
	end

	-- Returns the current item:
	function GetItem(i)
		i = i or currentItemIndex
		return lootTable[i]
	end

	-- Returns the current item's name:
	function GetItemName(i)
		i = i or currentItemIndex
		return lootTable[i] and lootTable[i].itemName or nil
	end

	-- Returns the current item's link:
	function GetItemLink(i)
		i = i or currentItemIndex
		return lootTable[i] and lootTable[i].itemLink or nil
	end

	-- Returns the current item's teture:
	function GetItemTexture(i)
		i = i or currentItemIndex
		return lootTable[i] and lootTable[i].itemTexture or nil
	end

	-- Checks if a loot item exists:
	function ItemExists(i)
		i = i or currentItemIndex
		return (lootTable[i] ~= nil)
	end

	-- Check if an item is soul bound:
	function ItemIsSoulbound(bag, slot)
		addon:Debug("DEBUG", "Checking if item at bag %d, slot %d is soulbound.", bag, slot)
		local tip = KRT_FakeTooltip or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
		KRT_FakeTooltip = tip
		tip:SetOwner(UIParent, "ANCHOR_NONE")
		tip:SetBagItem(bag, slot)
		tip:Show()

		local num = tip:NumLines()
		for i = num, 1, -1 do
			local t = _G["KRT_FakeTooltipTextLeft"..i]:GetText()
			addon:Debug("DEBUG", "Tooltip Line %d: %s", i, t or "nil")
			if deformat(t, BIND_TRADE_TIME_REMAINING) ~= nil then
				addon:Debug("DEBUG", "Item has remaining trade time – not soulbound.")
				tip:Hide()
				return false
			elseif t == ITEM_SOULBOUND then
				addon:Debug("DEBUG", "Item is soulbound.")
				tip:Hide()
				return true
			end
		end

		tip:Hide()
		addon:Debug("DEBUG", "Item is not soulbound.")
		return false
	end


