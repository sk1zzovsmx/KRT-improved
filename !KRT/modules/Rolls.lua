local addonName, addon = ...
addon.Rolls = {}
local Rolls = addon.Rolls
local L = addon.L
local Utils = addon.Utils

local frameName

local record, canRoll, warned = false, true, false
local playerRollTracker, rollsTable, rerolled, itemRollTracker = {}, {}, {}, {}
local selectedPlayer = nil

-- Sorts the rolls in descending or ascending order
local function SortRolls()
	if rollsTable ~= nil then
		table.sort(rollsTable, function(a, b)
			if addon.options.sortAscending then
				return a.roll < b.roll
			end
			return a.roll > b.roll
		end)
		winner = rollsTable[1].name
		addon:Debug("DEBUG", "Sorted rolls; current winner: %s with roll: %d", winner, rollsTable[1].roll)
	end
end

-- Adds a roll to the rollsTable and updates tracking
local function AddRoll(name, roll, itemId)
	roll = tonumber(roll)
	rollsCount = rollsCount + 1
	rollsTable[rollsCount] = { name = name, roll = roll, itemId = itemId }
	addon:Debug("DEBUG", "AddRoll: name=%s, roll=%d, itemId=%s", tostring(name), roll, tostring(itemId))

	if itemId then
		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		itemRollTracker[itemId][name] = (itemRollTracker[itemId][name] or 0) + 1
		addon:Debug("DEBUG", "Updated itemRollTracker: itemId=%d, player=%s, count=%d", itemId, name,
			itemRollTracker[itemId][name])
	end

	TriggerEvent("AddRoll", name, roll)
	SortRolls()
	if not selectedPlayer then
		local resolvedItemId = itemId or addon:GetCurrentRollItemID()
		if currentRollType == rollTypes.reserved then
			local topRoll = -1
			for _, entry in ipairs(rollsTable) do
				if addon:IsReserved(resolvedItemId, entry.name) and entry.roll > topRoll then
					topRoll = entry.roll
					selectedPlayer = entry.name
				end
			end
			addon:Debug("DEBUG", "Reserved roll: selectedPlayer=%s", tostring(selectedPlayer))
		else
			selectedPlayer = winner
			addon:Debug("DEBUG", "Free roll: selectedPlayer=%s", tostring(selectedPlayer))
		end
	end
	addon:FetchRolls()
end

-- Starts a roll for the player
function addon:Roll(btn)
	local itemId = self:GetCurrentRollItemID()
	if not itemId then return end

	playerRollTracker[itemId] = playerRollTracker[itemId] or 0
	local name = UnitName("player")
	local allowed = 1

	if currentRollType == rollTypes.reserved then
		allowed = addon.Reserves:GetReserveCountForItem(itemId, name)
	end

	if playerRollTracker[itemId] >= allowed then
		addon:Debug("DEBUG", "Roll blocked for %s (max %d rolls reached for itemId=%d)", name, allowed, itemId)
		addon:Print(L.ChatOnlyRollOnce)
		return
	end

	addon:Debug("DEBUG", "Rolling for itemId=%d (player=%s)", itemId, name)
	RandomRoll(1, 100)
	playerRollTracker[itemId] = playerRollTracker[itemId] + 1
end

-- Returns current roll session state
function addon:RollStatus()
	addon:Debug("DEBUG", "RollStatus queried: type=%s, record=%s, canRoll=%s, rolled=%s", tostring(currentRollType),
		tostring(record), tostring(canRoll), tostring(rolled))
	return currentRollType, record, canRoll, rolled
end

-- Enables or disables recording rolls
function addon:RecordRolls(bool)
	canRoll, record = bool == true, bool == true
	addon:Debug("DEBUG", "RecordRolls: %s", tostring(bool))
end

-- Handles system message for detecting rolls
function addon:CHAT_MSG_SYSTEM(msg)
	if not msg or not record then return end
	local player, roll, min, max = deformat(msg, RANDOM_ROLL_RESULT)
	if player and roll and min == 1 and max == 100 then
		addon:Debug("DEBUG", "Detected roll message: %s rolled %d (range %d-%d)", player, roll, min, max)
		if not canRoll then
			if not warned then
				self:Announce(L.ChatCountdownBlock)
				warned = true
				addon:Debug("DEBUG", "Roll blocked: countdown active")
			end
			return
		end

		local itemId = self:GetCurrentRollItemID()
		if not itemId or lootCount == 0 then
			addon:PrintError("Item ID missing or loot table not ready – roll will be ignored.")
			addon:Debug("DEBUG", "Roll ignored: missing itemId or lootCount = 0")
			return
		end

		local allowed = 1
		if currentRollType == rollTypes.reserved then
			local playerReserves = addon.Reserves:GetReserveCountForItem(itemId, player)
			allowed = playerReserves > 0 and playerReserves or 1
		end

		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		local used = itemRollTracker[itemId][player] or 0

		if used >= allowed then
			if not Utils.checkEntry(rerolled, player) then
				Utils.whisper(player, L.ChatOnlyRollOnce)
				tinsert(rerolled, player)
				addon:Debug("DEBUG", "Roll denied: %s exceeded allowed rolls for item %d", player, itemId)
			end
			return
		end

		addon:Debug("DEBUG", "Roll accepted: %s (%d/%d) for item %d", player, used + 1, allowed, itemId)
		AddRoll(player, roll, itemId)
	end
end

-- Returns the current rolls table
function addon:GetRolls()
	addon:Debug("DEBUG", "GetRolls called; count: %d", #rollsTable)
	return rollsTable
end

-- Sets the rolled flag to true
function addon:SetRolled()
	rolled = true
	addon:Debug("DEBUG", "SetRolled: rolled flag set to true")
end

-- Checks if a player has rolled
function addon:DidRoll(itemId, name)
	if not itemId then
		for i = 1, rollsCount do
			if rollsTable[i].name == name then
				addon:Debug("DEBUG", "DidRoll: %s has rolled (no itemId)", name)
				return true
			end
		end
		addon:Debug("DEBUG", "DidRoll: %s has NOT rolled (no itemId)", name)
		return false
	end
	itemRollTracker[itemId] = itemRollTracker[itemId] or {}
	local used = itemRollTracker[itemId][name] or 0
	local allowed = (currentRollType == rollTypes.reserved and addon.Reserves:GetReserveCountForItem(itemId, name) > 0)
		and addon.Reserves:GetReserveCountForItem(itemId, name) or 1
	local result = used >= allowed
	addon:Debug("DEBUG", "DidRoll: name=%s, itemId=%d, used=%d, allowed=%d, result=%s", name, itemId, used, allowed,
		tostring(result))
	return result
end

-- Returns the highest roll value of the current winner
function addon:HighestRoll()
	for i = 1, rollsCount do
		if rollsTable[i].name == winner then
			addon:Debug("DEBUG", "HighestRoll: %s rolled %d", winner, rollsTable[i].roll)
			return rollsTable[i].roll
		end
	end
	return 0
end

-- Clears all roll-related state and UI
function addon:ClearRolls(rec)
	frameName = frameName or self:GetFrameName()
	if not frameName then return end
	rollsTable, rerolled, itemRollTracker = {}, {}, {}
	playerRollTracker, rolled, warned, rollsCount = {}, false, false, 0
	selectedPlayer = nil
	if rec == false then record = false end

	local i = 1
	local btn = _G[frameName .. "PlayerBtn" .. i]
	while btn do
		btn:Hide()
		i = i + 1
		btn = _G[frameName .. "PlayerBtn" .. i]
	end

	self:ClearRaidIcons()
end

-- Gets the current item ID being rolled for
function addon:GetCurrentRollItemID()
	local index = GetItemIndex and GetItemIndex() or 1
	local item = GetItem and GetItem(index)
	local itemLink = item and item.itemLink
	if not itemLink then
		addon:Debug("DEBUG", "GetCurrentRollItemID: No itemLink found at index %d", index)
		return nil
	end
	local itemId = tonumber(string.match(itemLink, "item:(%d+)"))
	addon:Debug("DEBUG", "GetCurrentRollItemID: Found itemId %d", itemId)
	return itemId
end

-- Validates if a player can still roll
function addon:IsValidRoll(itemId, name)
	itemRollTracker[itemId] = itemRollTracker[itemId] or {}
	local used = itemRollTracker[itemId][name] or 0
	local allowed = (currentRollType == rollTypes.reserved)
		and addon.Reserves:GetReserveCountForItem(itemId, name)
		or 1
	local result = used < allowed
	addon:Debug("DEBUG", "IsValidRoll: %s on item %d: used=%d, allowed=%d, valid=%s", name, itemId, used, allowed,
		tostring(result))
	return result
end

-- Checks if the player has reserved the item
function addon:IsReserved(itemId, name)
	local reserved = addon.Reserves:GetReserveCountForItem(itemId, name) > 0
	addon:Debug("DEBUG", "IsReserved: %s for item %d => %s", name, itemId, tostring(reserved))
	return reserved
end

-- Gets how many reserves the player has used
function addon:GetUsedReserveCount(itemId, name)
	itemRollTracker[itemId] = itemRollTracker[itemId] or {}
	local count = itemRollTracker[itemId][name] or 0
	addon:Debug("DEBUG", "GetUsedReserveCount: %s on item %d => %d", name, itemId, count)
	return count
end

-- Gets the allowed number of reserves for a player
function addon:GetAllowedReserves(itemId, name)
	local count = addon.Reserves:GetReserveCountForItem(itemId, name)
	addon:Debug("DEBUG", "GetAllowedReserves: %s for item %d => %d", name, itemId, count)
	return count
end

-- Rebuilds the roll UI and marks the top roll or selected winner
function addon:FetchRolls()
	local frameName = addon:GetFrameName()
	addon:Debug("DEBUG", "FetchRolls called; frameName: %s", frameName)
	local scrollFrame = _G[frameName .. "ScrollFrame"]
	local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
	scrollChild:SetHeight(scrollFrame:GetHeight())
	scrollChild:SetWidth(scrollFrame:GetWidth())

	local itemId = self:GetCurrentRollItemID()
	local isSR = currentRollType == rollTypes.reserved
	addon:Debug("DEBUG", "Current itemId: %s, SR mode: %s", tostring(itemId), tostring(isSR))

	local starTarget = selectedPlayer
	if not starTarget then
		if isSR then
			local topRoll = -1
			for _, entry in ipairs(rollsTable) do
				local name, roll = entry.name, entry.roll
				if addon:IsReserved(itemId, name) and roll > topRoll then
					topRoll = roll
					starTarget = name
				end
			end
			addon:Debug("DEBUG", "Top SR roll by: %s", tostring(starTarget))
		else
			starTarget = winner
			addon:Debug("DEBUG", "Top roll winner: %s", tostring(starTarget))
		end
	end

	local starShown = false
	local totalHeight = 0
	for i = 1, rollsCount do
		local entry = rollsTable[i]
		local name, roll = entry.name, entry.roll
		local btnName = frameName .. "PlayerBtn" .. i
		local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")
		btn:SetID(i)
		btn:Show()
		if not btn.selectedBackground then
			btn.selectedBackground = btn:CreateTexture("KRTSelectedHighlight", "ARTWORK")
			btn.selectedBackground:SetAllPoints()
			btn.selectedBackground:SetTexture(1, 0.8, 0, 0.1)
			btn.selectedBackground:Hide()
		end

		local nameStr, rollStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"], _G[btnName .. "Star"]

		if nameStr and nameStr.SetVertexColor then
			local _, class = UnitClass(name)
			class = class and class:upper() or "UNKNOWN"
			if isSR and self:IsReserved(itemId, name) then
				nameStr:SetVertexColor(0.4, 0.6, 1.0)
			else
				local r, g, b = self:GetClassColor(class)
				nameStr:SetVertexColor(r, g, b)
			end
		end

		if selectedPlayer == name then
			nameStr:SetText("> " .. name .. " <")
			btn.selectedBackground:Show()
		else
			nameStr:SetText(name)
			btn.selectedBackground:Hide()
		end

		if isSR and self:IsReserved(itemId, name) then
			local count = self:GetAllowedReserves(itemId, name)
			local used = self:GetUsedReserveCount(itemId, name)
			rollStr:SetText(count > 1 and format("%d (%d/%d)", roll, used, count) or tostring(roll))
		else
			rollStr:SetText(roll)
		end

		local showStar = not starShown and name == starTarget
		Utils.showHide(star, showStar)
		if showStar then
			addon:Debug("DEBUG", "Star assigned to: %s", name)
			starShown = true
		end

		btn:SetScript("OnClick", function()
			selectedPlayer = name
			addon:FetchRolls()
		end)

		btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
		btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
		totalHeight = totalHeight + btn:GetHeight()
	end
	addon:Debug("DEBUG", "FetchRolls completed. Total entries: %d", rollsCount)
end
