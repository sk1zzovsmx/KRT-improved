local addonName, addon = ...
addon.Master = {}
local Master = addon.Master

	local frameName

	local LocalizeUIFrame
	local localized = false

	local UpdateUIFrame
	local updateInterval = 0.05

	local InitializeDropDowns, PrepareDropDowns, UpdateDropDowns
	local dropDownData, dropDownGroupData = {}, {}
	local dropDownFrameHolder, dropDownFrameBanker, dropDownFrameDisenchanter
	local dropDownsInitialized

	local selectionFrame, UpdateSelectionFrame

	local countdownRun = false
	local countdownStart, countdownPos = 0, 0

	local AssignItem, TradeItem
	local screenshotWarn = false

	local announced = false

	-- OnLoad frame:
	function Master:OnLoad(frame)
		if not frame then return end
		addon:Debug("DEBUG", "Master Loot Frame OnLoad invoked.")
		UIMaster = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
		frame:SetScript("OnHide", function()
			if selectionFrame then selectionFrame:Hide() end
		end)
	end

	-- Toggle frame visibility:
	function Master:Toggle()
		addon:Debug("DEBUG", "Toggling Master Loot Frame.")
		Utils.toggle(UIMaster)
	end

	-- Hide frame:
	function Master:Hide()
		if UIMaster and UIMaster:IsShown() then
			addon:Debug("DEBUG", "Hiding Master Loot Frame.")
			UIMaster:Hide()
		end
	end

	-- Button: Select/Remove Item
	function Master:BtnSelectItem(btn)
		addon:Debug("DEBUG", "BtnSelectItem pressed.")
		if btn == nil or lootCount <= 0 then return end
		if fromInventory == true then
			addon:Debug("DEBUG", "Clearing inventory loot.")
			addon:ClearLoot()
			addon:ClearRolls()
			addon:RecordRolls(false)
			announced = false
			fromInventory = false
			if lootOpened == true then addon:FetchLoot() end
		elseif selectionFrame then
			selectionFrame:SetShown(not selectionFrame:IsVisible())
		end
	end

	function Master:BtnSpamLoot(btn)
		addon:Debug("DEBUG", "BtnSpamLoot pressed.")
		if btn == nil or lootCount <= 0 then return end
		if fromInventory == true then
			addon:Debug("DEBUG", "Sending ready check.")
			addon:Announce(L.ChatReadyCheck)
			DoReadyCheck()
		else
			addon:Debug("DEBUG", "Spamming loot list in RAID.")
			addon:Announce(L.ChatSpamLoot, "RAID")
			for i = 1, lootCount do
				local itemLink = GetItemLink(i)
				if itemLink then
					addon:Announce(i..". "..itemLink, "RAID")
				end
			end
		end
	end

	-- Button: Open List
	function Master:BtnOpenReserves(btn)
		addon:Debug("DEBUG", "Opening reserves list.")
		addon.Reserves:ShowWindow()
	end

	-- Button: Import Reserve
	function Master:BtnImportReserves(btn)
		addon:Debug("DEBUG", "Importing reserves.")
		addon.Reserves:ShowImportBox()
	end

	-- Generic roll button:
	local function AnnounceRoll(rollType, chatMsg)
		addon:Debug("DEBUG", "Announcing roll type %d with message key '%s'.", rollType, chatMsg)
		if lootCount >= 1 then
			announced = false
			currentRollType = rollType
			addon:ClearRolls()
			addon:RecordRolls(true)

			local itemLink = GetItemLink()
			local itemID = tonumber(string.match(itemLink or "", "item:(%d+)"))
			local message = ""

			if rollType == rollTypes.reserved and addon.Reserves and addon.Reserves.FormatReservedPlayersLine then
				local srList = addon.Reserves:FormatReservedPlayersLine(itemID)
				local suff = addon.options.sortAscending and "Low" or "High"
				message = itemCount > 1
					and L[chatMsg.."Multiple"..suff]:format(srList, itemLink, itemCount)
					or L[chatMsg]:format(srList, itemLink)
			else
				local suff = addon.options.sortAscending and "Low" or "High"
				message = itemCount > 1
					and L[chatMsg.."Multiple"..suff]:format(itemLink, itemCount)
					or L[chatMsg]:format(itemLink)
			end

			addon:Announce(message)
			_G[frameName.."ItemCount"]:ClearFocus()
			currentRollItem = addon.Raid:GetLootID(itemID)
		end
	end

	function Master:BtnMS(btn) addon:Debug("DEBUG", "MS roll button pressed.") return AnnounceRoll(1, "ChatRollMS")
	end
	function Master:BtnOS(btn) addon:Debug("DEBUG", "OS roll button pressed.") return AnnounceRoll(2, "ChatRollOS")
	end
	function Master:BtnSR(btn) addon:Debug("DEBUG", "SR roll button pressed.") return AnnounceRoll(3, "ChatRollSR")
	end
	function Master:BtnFree(btn) addon:Debug("DEBUG", "Free roll button pressed.") return AnnounceRoll(4, "ChatRollFree")
	end

	function Master:BtnCountdown(btn)
		addon:Debug("DEBUG", "Countdown button pressed.")
		if countdownRun then
			addon:RecordRolls(false)
			countdownRun = false
		else
			addon:RecordRolls(true)
			announced = false
			countdownRun = true
			countdownStart = GetTime()
			countdownPos = addon.options.countdownDuration + 1
		end
	end

	-- Button: Clear Rolls
	function Master:BtnClear(btn)
		addon:Debug("DEBUG", "Clear rolls button pressed.")
		announced = false
		return addon:ClearRolls()
	end

	-- Button: Award/Trade
	function Master:BtnAward(btn)
		addon:Debug("DEBUG", "Award button pressed.")
		if lootCount <= 0 or rollsCount <= 0 then
			addon:Debug("DEBUG", "Cannot award, lootCount=%d, rollsCount=%d", lootCount or 0, rollsCount or 0)
			return
		end
		countdownRun = false
		local itemLink = GetItemLink()
		_G[frameName.."ItemCount"]:ClearFocus()
		if fromInventory == true then
			addon:Debug("DEBUG", "Trading item %s to %s", itemLink, winner)
			return TradeItem(itemLink, winner, currentRollType, addon:HighestRoll())
		end
		addon:Debug("DEBUG", "Assigning item %s to %s", itemLink, winner)
		return AssignItem(itemLink, winner, currentRollType, addon:HighestRoll())
	end

	-- Button: Hold item
	function Master:BtnHold(btn)
		addon:Debug("DEBUG", "BtnHold pressed.")
		if lootCount <= 0 or holder == nil then return end
		countdownRun = false
		local itemLink = GetItemLink()
		if itemLink == nil then return end
		currentRollType = rollTypes.hold
		addon:Debug("DEBUG", "Holding item %s for %s", itemLink, holder)
		if fromInventory == true then
			return TradeItem(itemLink, holder, rollTypes.hold, 0)
		end
		return AssignItem(itemLink, holder, rollTypes.hold, 0)
	end

	-- Button: Bank item
	function Master:BtnBank(btn)
		addon:Debug("DEBUG", "BtnBank pressed.")
		if lootCount <= 0 or banker == nil then return end
		countdownRun = false
		local itemLink = GetItemLink()
		if itemLink == nil then return end
		currentRollType = rollTypes.bank
		addon:Debug("DEBUG", "Banking item %s to %s", itemLink, banker)
		if fromInventory == true then
			return TradeItem(itemLink, banker, rollTypes.bank, 0)
		end
		return AssignItem(itemLink, banker, rollTypes.bank, 0)
	end

	-- Button: Disenchant item
	function Master:BtnDisenchant(btn)
		addon:Debug("DEBUG", "BtnDisenchant pressed.")
		if lootCount <= 0 or disenchanter == nil then return end
		countdownRun = false
		local itemLink = GetItemLink()
		if itemLink == nil then return end
		currentRollType = rollTypes.disenchant
		addon:Debug("DEBUG", "Disenchanting item %s by %s", itemLink, disenchanter)
		if fromInventory == true then
			return TradeItem(itemLink, disenchanter, rollTypes.disenchant, 0)
		end
		return AssignItem(itemLink, disenchanter, rollTypes.disenchant, 0)
	end

	-- Select winner:
	function Master:SelectWinner(btn)
		if not btn then return end
		local btnName = btn:GetName()
		local player = _G[btnName.."Name"]:GetText()
		if player ~= nil then
			if IsControlKeyDown() then
				local roll = _G[btnName.."Roll"]:GetText()
				addon:Debug("DEBUG", "Control-click on %s, announcing roll: %s", player, roll)
				addon:Announce(format(L.ChatPlayerRolled, player, roll))
				return
			end
			winner = player:trim()
			addon:Debug("DEBUG", "Selected winner: %s", winner)
			addon:FetchRolls()
			Utils.sync("KRT-RollWinner", player)
		end
		if itemCount == 1 then announced = false end
	end

	-- Select item roll for:
	function Master:BtnSelectedItem(btn)
		if not btn then return end
		local index = btn:GetID()
		if index ~= nil then
			addon:Debug("DEBUG", "Selected item index: %d", index)
			announced = false
			selectionFrame:Hide()
			addon:SelectItem(index)
		end
	end

	-- Localizing ui frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."ConfigBtn"]:SetText(L.BtnConfigure)
			_G[frameName.."SelectItemBtn"]:SetText(L.BtnSelectItem)
			_G[frameName.."SpamLootBtn"]:SetText(L.BtnSpamLoot)
			_G[frameName.."MSBtn"]:SetText(L.BtnMS)
			_G[frameName.."OSBtn"]:SetText(L.BtnOS)
			_G[frameName.."SRBtn"]:SetText(L.BtnSR)
			_G[frameName.."FreeBtn"]:SetText(L.BtnFree)
			_G[frameName.."CountdownBtn"]:SetText(L.BtnCountdown)
			_G[frameName.."AwardBtn"]:SetText(L.BtnAward)
			_G[frameName.."RollBtn"]:SetText(L.BtnRoll)
			_G[frameName.."ClearBtn"]:SetText(L.BtnClear)
			_G[frameName.."HoldBtn"]:SetText(L.BtnHold)
			_G[frameName.."BankBtn"]:SetText(L.BtnBank)
			_G[frameName.."DisenchantBtn"]:SetText(L.BtnDisenchant)
			_G[frameName.."Name"]:SetText(L.StrNoItemSelected)
			_G[frameName.."RollsHeaderRoll"]:SetText(L.StrRoll)
			_G[frameName.."OpenReservesBtn"]:SetText(L.BtnOpenReserves)
			_G[frameName.."ImportReservesBtn"]:SetText(L.BtnImportReserves)
		end
		_G[frameName.."Title"]:SetText(format(titleString, MASTER_LOOTER))
		_G[frameName.."ItemCount"]:SetScript("OnTextChanged", function(self)
			announced = false
		end)
		if next(dropDownData) == nil then
			for i = 1, 8 do dropDownData[i] = {} end
		end
		dropDownFrameHolder       = _G[frameName.."HoldDropDown"]
		dropDownFrameBanker       = _G[frameName.."BankDropDown"]
		dropDownFrameDisenchanter = _G[frameName.."DisenchantDropDown"]
		PrepareDropDowns()
		UIDropDownMenu_Initialize(dropDownFrameHolder, InitializeDropDowns)
		UIDropDownMenu_Initialize(dropDownFrameBanker, InitializeDropDowns)
		UIDropDownMenu_Initialize(dropDownFrameDisenchanter, InitializeDropDowns)
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			itemCount = _G[frameName.."ItemCount"]:GetNumber()
			addon:Debug("DEBUG", "Item count read from UI: %d", itemCount)
			if itemInfo.count and itemInfo.count ~= itemCount then
				if itemInfo.count < itemCount then
					itemCount = itemInfo.count
					_G[frameName.."ItemCount"]:SetNumber(itemInfo.count)
					addon:Debug("DEBUG", "Item count adjusted to match available: %d", itemInfo.count)
				end
			end

			UpdateDropDowns(dropDownFrameHolder)
			UpdateDropDowns(dropDownFrameBanker)
			UpdateDropDowns(dropDownFrameDisenchanter)

			Utils.setText(_G[frameName.."CountdownBtn"], L.BtnStop, L.BtnCountdown, countdownRun == true)
			Utils.setText(_G[frameName.."AwardBtn"], TRADE, L.BtnAward, fromInventory == true)

			if countdownRun == true then
				local tick = ceil(addon.options.countdownDuration - GetTime() + countdownStart)
				addon:Debug("DEBUG", "Countdown ticking. Tick: %d", tick)
				local i = countdownPos - 1
				while i >= tick do
					if i >= addon.options.countdownDuration then
						addon:Announce(L.ChatCountdownTic:format(i))
					elseif i >= 10 then
						if i % 10 == 0 then
							addon:Announce(L.ChatCountdownTic:format(i))
						end
					elseif ((i > 0 and i < 10 and i % 7 == 0) or (i > 0 and i >= 5 and i % 5 == 0) or (i > 0 and i <= 3)) then
						addon:Announce(L.ChatCountdownTic:format(i))
					end
					i = i - 1
				end
				countdownPos = tick
				if countdownPos == 0 then
					addon:Debug("DEBUG", "Countdown ended.")
					countdownRun = false
					countdownPos = 0
					addon:Announce(L.ChatCountdownEnd)
					if addon.options.countdownRollsBlock then
						addon:RecordRolls(false)
					end
				end
			end

			Utils.enableDisable(_G[frameName.."SelectItemBtn"], lootCount > 1 or (fromInventory and lootCount >= 1))
			Utils.enableDisable(_G[frameName.."SpamLootBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."MSBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."OSBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."SRBtn"], lootCount >= 1 and addon.Reserves:HasData())
			Utils.enableDisable(_G[frameName.."FreeBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."CountdownBtn"], lootCount >= 1 and ItemExists())
			Utils.enableDisable(_G[frameName.."HoldBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."BankBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."DisenchantBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName.."AwardBtn"], (lootCount >= 1 and rollsCount >= 1))
			Utils.enableDisable(_G[frameName.."OpenReservesBtn"], addon.Reserves:HasData())
			Utils.enableDisable(_G[frameName.."ImportReservesBtn"], not addon.Reserves:HasData())

			local rollType, record, canRoll, rolled = addon:RollStatus()
			Utils.enableDisable(_G[frameName.."RollBtn"], record and canRoll and rolled == false)
			Utils.enableDisable(_G[frameName.."ClearBtn"], rollsCount >= 1)

			Utils.setText(_G[frameName.."SelectItemBtn"], L.BtnRemoveItem, L.BtnSelectItem, fromInventory)
			Utils.setText(_G[frameName.."SpamLootBtn"], READY_CHECK, L.BtnSpamLoot, fromInventory)
		end
	end

	-- Initialize DropDowns:
	function InitializeDropDowns()
		addon:Debug("DEBUG", "Initializing dropdowns at level %d", UIDROPDOWNMENU_MENU_LEVEL)
		if UIDROPDOWNMENU_MENU_LEVEL == 2 then
			local g = UIDROPDOWNMENU_MENU_VALUE
			local m = dropDownData[g]
			for key, value in pairs(m) do
				addon:Debug("DEBUG", "Adding dropdown entry to group %s: %s", g, key)
				local info = UIDropDownMenu_CreateInfo()
				info.hasArrow     = false
				info.notCheckable = 1
				info.text         = key
				info.func         = Master.OnClickDropDown
				info.arg1         = UIDROPDOWNMENU_OPEN_MENU
				info.arg2         = key
				UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
			end
		end
		if UIDROPDOWNMENU_MENU_LEVEL == 1 then
			for key, value in pairs(dropDownData) do
				if dropDownGroupData[key] == true then
					addon:Debug("DEBUG", "Adding dropdown group: %s", key)
					local info = UIDropDownMenu_CreateInfo()
					info.hasArrow     = 1
					info.notCheckable = 1
					info.text         = GROUP.." "..key
					info.value        = key
					info.owner        = UIDROPDOWNMENU_OPEN_MENU
					UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL )
				end
			end
		end
	end

	-- Prepare DropDowns:
	function PrepareDropDowns()
		addon:Debug("DEBUG", "Preparing dropdown data for raid members.")
		for i = 1, 8 do
			dropDownData[i] = twipe(dropDownData[i])
		end
		dropDownGroupData = twipe(dropDownGroupData)

		for p = 1, GetRealNumRaidMembers() do
			local name, _, subgroup = GetRaidRosterInfo(p)
			if name then
				dropDownData[subgroup][name] = name
				dropDownGroupData[subgroup] = true
				addon:Debug("DEBUG", "Added %s to group %d", name, subgroup)
			end
		end
	end

	-- OnClick DropDowns:
	function Master:OnClickDropDown(owner, value)
		addon:Debug("DEBUG", "Dropdown clicked: %s selected for %s", value, owner:GetName())
		if not KRT_CurrentRaid then return end

		UIDropDownMenu_SetText(owner, value)
		UIDropDownMenu_SetSelectedValue(owner, value)

		local name = owner:GetName()
		if name == dropDownFrameHolder:GetName() then
			KRT_Raids[KRT_CurrentRaid].holder = value
		elseif name == dropDownFrameBanker:GetName() then
			KRT_Raids[KRT_CurrentRaid].banker = value
		elseif name == dropDownFrameDisenchanter:GetName() then
			KRT_Raids[KRT_CurrentRaid].disenchanter = value
		end

		CloseDropDownMenus()
	end

	-- OnUpdate DropDowns:
	function UpdateDropDowns(frame)
		if not frame or not KRT_CurrentRaid then return end
		local name = frame:GetName()
		addon:Debug("DEBUG", "Updating dropdown frame: %s", name)
		if name == dropDownFrameHolder:GetName() then
			holder = KRT_Raids[KRT_CurrentRaid].holder
			if holder and addon:GetUnitID(holder) == "none" then
				KRT_Raids[KRT_CurrentRaid].holder = nil
				holder = nil
				addon:Debug("DEBUG", "Holder not in raid, reset.")
			end
			if holder then
				UIDropDownMenu_SetText(dropDownFrameHolder, holder)
				UIDropDownMenu_SetSelectedValue(dropDownFrameHolder, holder)
			end
		-- Update loot banker:
		elseif name == dropDownFrameBanker:GetName() then
			banker = KRT_Raids[KRT_CurrentRaid].banker
			if banker and addon:GetUnitID(banker) == "none" then
				KRT_Raids[KRT_CurrentRaid].banker = nil
				banker = nil
				addon:Debug("DEBUG", "Banker not in raid, reset.")
			end
			if banker then
				UIDropDownMenu_SetText(dropDownFrameBanker, banker)
				UIDropDownMenu_SetSelectedValue(dropDownFrameBanker, banker)
			end
		-- Update loot disenchanter:
		elseif name == dropDownFrameDisenchanter:GetName() then
			disenchanter = KRT_Raids[KRT_CurrentRaid].disenchanter
			if disenchanter and addon:GetUnitID(disenchanter) == "none" then
				KRT_Raids[KRT_CurrentRaid].disenchanter = nil
				disenchanter = nil
				addon:Debug("DEBUG", "Disenchanter not in raid, reset.")
			end
			if disenchanter then
				UIDropDownMenu_SetText(dropDownFrameDisenchanter, disenchanter)
				UIDropDownMenu_SetSelectedValue(dropDownFrameDisenchanter, disenchanter)
			end
		end
	end

	-- Generate the selection frame:
	local function CreateSelectionFrame()
		if selectionFrame == nil then
			addon:Debug("DEBUG", "Creating selection frame.")
			selectionFrame = CreateFrame("Frame", nil, UIMaster, "KRTSimpleFrameTemplate")
			selectionFrame:Hide()
		end
		local index = 1
		local btnName = frameName.."ItemSelectionBtn"..index
		local btn = _G[btnName]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btnName = frameName.."ItemSelectionBtn"..index
			btn = _G[btnName]
		end
	end

	-- Update the selection frame:
	function UpdateSelectionFrame()
		addon:Debug("DEBUG", "Updating selection frame with %d items.", lootCount)
		CreateSelectionFrame()
		local height = 5
		for i = 1, lootCount do
			local btnName = frameName.."ItemSelectionBtn"..i
			local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
			btn:SetID(i)
			btn:Show()
			local itemName = GetItemName(i)
			addon:Debug("DEBUG", "Item %d: %s", i, itemName)
			local itemNameBtn = _G[btnName.."Name"]
			itemNameBtn:SetText(itemName)
			local itemTexture = GetItemTexture(i)
			local itemTextureBtn = _G[btnName.."Icon"]
			itemTextureBtn:SetTexture(itemTexture)
			btn:SetPoint("TOPLEFT", selectionFrame, "TOPLEFT", 0, -height)
			height = height + 37
		end
		selectionFrame:SetHeight(height)
		if lootCount <= 0 then
			addon:Debug("DEBUG", "No loot to show; hiding selection frame.")
			selectionFrame:Hide()
		end
	end

	-- ITEM_LOCKED:
	function addon:ITEM_LOCKED(inBag, inSlot)
		addon:Debug("DEBUG", "ITEM_LOCKED received: bag=%s, slot=%s", tostring(inBag), tostring(inSlot))
		if not inBag or not inSlot then return end
		local itemTexture, itemCount, locked, quality, _, _, itemLink = GetContainerItemInfo(inBag, inSlot)
		if not itemLink or not itemTexture then return end
		_G[frameName.."ItemBtn"]:SetScript("OnClick", function(self)
			if not ItemIsSoulbound(inBag, inSlot) then
				addon:Debug("DEBUG", "Item from inventory: %s", itemLink)
				_G[frameName.."ItemCount"]:SetText("")
				_G[frameName.."ItemCount"]:ClearFocus()
				_G[frameName.."ItemCount"]:Hide()

				fromInventory = true
				addon:AddItem(itemLink)
				addon:PrepareItem()
				announced = false
				itemInfo.bagID   = inBag
				itemInfo.slotID  = inSlot
				itemInfo.count   = GetItemCount(itemLink)
				itemInfo.isStack = (itemCount > 1)
				if itemInfo.count >= 1 then
					itemCount = itemInfo.count
					_G[frameName.."ItemCount"]:SetText(itemInfo.count)
					_G[frameName.."ItemCount"]:Show()
					_G[frameName.."ItemCount"]:SetFocus()
				end
			end
			ClearCursor()
		end)
	end

	-- LOOT_OPENED:
	function addon:LOOT_OPENED()
		addon:Debug("DEBUG", "LOOT_OPENED triggered.")
		if self:IsMasterLooter() then
			lootOpened = true
			announced = false
			self:FetchLoot()
			UpdateSelectionFrame()
			if lootCount >= 1 then UIMaster:Show() end
			if not self.Logger.container then
				self.Logger.source = UnitName("target")
			end
		end
	end

	-- LOOT_CLOSED:
	function addon:LOOT_CLOSED()
		addon:Debug("DEBUG", "LOOT_CLOSED triggered.")
		if self:IsMasterLooter() then
			lootOpened = false
			UIMaster:Hide()
			self:ClearLoot()
			self:ClearRolls()
			self:RecordRolls(false)
		end
	end

	-- LOOT_SLOT_CLEARED:
	function addon:LOOT_SLOT_CLEARED()
		addon:Debug("DEBUG", "LOOT_SLOT_CLEARED triggered.")
		if self:IsMasterLooter() then
			self:FetchLoot()
			UpdateSelectionFrame()
			if lootCount >= 1 then
				UIMaster:Show()
			else
				UIMaster:Hide()
			end
		end
	end

	-- on TRADE_ACCEPT_UPDATE:
	function addon:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
		addon:Debug("DEBUG", "TRADE_ACCEPT_UPDATE: tAccepted=%s, pAccepted=%s", tostring(tAccepted), tostring(pAccepted))
		if itemCount == 1 and trader and winner and trader ~= winner then
			if tAccepted == 1 and pAccepted == 1 then
				addon:Debug("DEBUG", "Trade confirmed. Logging item trade: %s to %s", tostring(currentRollItem), tostring(winner))
				self:Log(currentRollItem, winner, currentRollType, self:HighestRoll())
				trader = nil
				winner = nil
				self:ClearLoot()
				self:ClearRolls()
				self:RecordRolls(false)
				screenshotWarn = false
			end
		end
	end

	-- Directly assign item to player:
	function AssignItem(itemLink, playerName, rollType, rollValue)
		addon:Debug("DEBUG", "Attempting to assign item %s to %s with rollType %s and rollValue %s", itemLink, playerName, tostring(rollType), tostring(rollValue))
		local itemIndex, tempItemLink
		for i = 1, GetNumLootItems() do
			tempItemLink = GetLootSlotLink(i)
			if tempItemLink == itemLink then
				itemIndex = i
				break
			end
		end
		if itemIndex == nil then
			addon:PrintError(L.ErrCannotFindItem:format(itemLink))
			addon:Debug("DEBUG", "Item %s not found in loot window.", itemLink)
			return false
		end

		for p = 1, 40 do
			if GetMasterLootCandidate(p) == playerName then
				GiveMasterLoot(itemIndex, p)
				addon:Debug("DEBUG", "Gave master loot index %d to player %s", itemIndex, playerName)
				local output, whisper
				if rollType <= 4 and addon.options.announceOnWin then
					output = L.ChatAward:format(playerName, itemLink)
				elseif rollType == rollTypes.hold and addon.options.announceOnHold then
					output = L.ChatHold:format(playerName, itemLink)
					if addon.options.lootWhispers then
						whisper = L.WhisperHoldAssign:format(itemLink)
					end
				elseif rollType == rollTypes.bank and addon.options.announceOnBank then
					output = L.ChatBank:format(playerName, itemLink)
					if addon.options.lootWhispers then
						whisper = L.WhisperBankAssign:format(itemLink)
					end
				elseif rollType == rollTypes.disenchant and addon.options.announceOnDisenchant then
					output = L.ChatDisenchant:format(itemLink, playerName)
					if addon.options.lootWhispers then
						whisper = L.WhisperDisenchantAssign:format(itemLink)
					end
				end
				if output and not announced then
					addon:Announce(output)
					announced = true
				end
				if whisper then
					Utils.whisper(playerName, whisper)
				end
				addon:Log(currentRollItem, playerName, rollType, rollValue)
				return true
			end
		end
		addon:PrintError(L.ErrCannotFindPlayer:format(playerName))
		addon:Debug("DEBUG", "Player %s not found among master loot candidates.", playerName)
		return false
	end

	-- Trade item to player:
	function TradeItem(itemLink, playerName, rollType, rollValue)
		addon:Debug("DEBUG", "Trading item %s to %s, rollType=%s, rollValue=%s", itemLink, playerName, tostring(rollType), tostring(rollValue))
		if itemLink ~= GetItemLink() then return end
		trader = unitName

		-- Prepare initial output and whisper:
		local output, whisper
		local keep = true
		if rollType <= 4 and addon.options.announceOnWin then
			output = L.ChatAward:format(playerName, itemLink)
			keep = false
		elseif rollType == rollTypes.hold and addon.options.announceOnHold then
			output = L.ChatNoneRolledHold:format(itemLink, playerName)
		elseif rollType == rollTypes.bank and addon.options.announceOnBank then
			output = L.ChatNoneRolledBank:format(itemLink, playerName)
		elseif rollType == rollTypes.disenchant and addon.options.announceOnDisenchant then
			output = L.ChatNoneRolledDisenchant:format(itemLink, playerName)
		end

		-- Keeping the item:
		if keep then
			if rollType == rollTypes.hold then
				whisper = L.WhisperHoldTrade:format(itemLink)
			elseif rollType == rollTypes.bank then
				whisper = L.WhisperBankTrade:format(itemLink)
			elseif rollType == rollTypes.disenchant then
				whisper = L.WhisperDisenchantTrade:format(itemLink)
			end
		-- Multiple winners:
		elseif itemCount > 1 then
			addon:ClearRaidIcons()
			SetRaidTarget(trader, 1)
			local rolls = addon:GetRolls()
			local winners = {}
			for i = 1, itemCount do
				if rolls[i] then
					if rolls[i].name == trader then
						tinsert(winners, "{star} "..rolls[i].name.."("..rolls[i].roll..")")
					else
						SetRaidTarget(rolls[i].name, i + 1)
						tinsert(winners, markers[i].." "..rolls[i].name.."("..rolls[i].roll..")")
					end
				end
			end
			output = L.ChatTradeMutiple:format(tconcat(winners, ", "), trader)
		-- Trader is the winner:
		elseif trader == winner then
			addon:ClearLoot()
			addon:ClearRolls(false)
			addon:ClearRaidIcons()
		-- Can trade the player?
		elseif CheckInteractDistance(playerName, 2) == 1 then
			if itemInfo.isStack and not addon.options.ignoreStacks then
				addon:PrintWarning(L.ErrItemStack:format(itemLink))
				return false
			end
			ClearCursor()
			PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
			if CursorHasItem() then
				addon:Debug("DEBUG", "Initiating trade of item %s to %s", itemLink, playerName)
				InitiateTrade(playerName)
				if addon.options.screenReminder and not screenshotWarn then
					addon:PrintWarning(L.ErrScreenReminder)
					screenshotWarn = true
				end
			end
		-- Cannot trade the player?
		elseif addon:GetUnitID(playerName) ~= "none" then
			addon:ClearRaidIcons()
			SetRaidTarget(trader, 1)
			SetRaidTarget(winner, 4)
			output = L.ChatTrade:format(playerName, itemLink)
		end

		if not announced then
			if output then addon:Announce(output) end
			if whisper then
				if playerName == trader then
					addon:ClearLoot()
					addon:ClearRolls()
					addon:RecordRolls(false)
				else
					Utils.whisper(playerName, whisper)
				end
			end
			if rollType <= rollTypes.free and playerName == trader then
				addon:Log(currentRollItem, trader, rollType, rollValue)
			end
			announced = true
		end
		return true
	end

	-- Register some callbacks:
	addon:RegisterCallback("SetItem", function(f, itemLink)
		local oldItem = GetItemLink()
		if oldItem ~= itemLink then
			addon:Debug("DEBUG", "Item changed from %s to %s", tostring(oldItem), tostring(itemLink))
			announced = false
		end
	end)


