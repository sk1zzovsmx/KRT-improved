local addonName, addon = ...
addon.Logger = {}
local Logger = addon.Logger

	local frameName

	local LocalizeUIFrame
	local localized = false

	local UpdateUIFrame
	local updateInterval = 0.1

	Logger.selectedRaid       = nil
	Logger.selectedBoss       = nil
	Logger.selectedPlayer     = nil
	Logger.selectedBossPlayer = nil
	Logger.selectedItem       = nil

	-- OnLoad frame:
	function Logger:OnLoad(frame)
		if not frame then return end
		UILogger = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
		frame:SetScript("OnHide", function()
			Logger.selectedRaid = KRT_CurrentRaid
			Logger.selectedBoss = nil
			Logger.selectedPlayer = nil
			Logger.selectedItem = nil
		end)
	end

	-- Toggle frame visibility:
	function Logger:Toggle()
		Utils.toggle(UILogger)
	end

	-- Hide Frame:
	function Logger:Hide()
		if UILogger and UILogger:IsShown() then
			Logger.selectedRaid = KRT_CurrentRaid
			Logger.selectedBoss = nil
			Logger.selectedPlayer = nil
			Logger.selectedItem = nil
			UILogger:Hide()
		end
	end

	-- Localizing frame:
	function LocalizeUIFrame()
		if localized then return end
		_G[frameName.."Title"]:SetText(format(titleString, L.StrLootHistory))
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if Logger.selectedRaid == nil then
				Logger.selectedRaid = KRT_CurrentRaid
			end
		end
	end

	-- Select a raid:
	function Logger:SelectRaid(btn)
		if not btn then return end
		local rID = btn:GetID()
		if rID ~= addon.Logger.selectedRaid then
			addon.Logger.selectedRaid = rID
		else
			addon.Logger.selectedRaid = nil
		end
		TriggerEvent("LoggerSelectRaid", rID)
	end

	-- Select a boss:
	function Logger:SelectBoss(btn)
		if not btn then return end
		local bID = btn:GetID()
		if bID ~= addon.Logger.selectedBoss then
			addon.Logger.selectedBoss = bID
		else
			addon.Logger.selectedBoss = nil
		end
		TriggerEvent("LoggerSelectBoss", bID)
	end

	-- Select a boss attendee:
	function Logger:SelectBossPlayer(btn)
		if not btn then return end
		local pID = btn:GetID()
		if pID ~= addon.Logger.selectedBossPlayer then
			addon.Logger.selectedBossPlayer = pID
		else
			addon.Logger.selectedBossPlayer = nil
		end
		TriggerEvent("LoggerSelectBossPlayer", pID)
	end

	-- Select a player:
	function Logger:SelectPlayer(btn)
		if not btn then return end
		local pID = btn:GetID()
		if pID ~= addon.Logger.selectedPlayer then
			addon.Logger.selectedPlayer = pID
		else
			addon.Logger.selectedPlayer = nil
		end
		TriggerEvent("LoggerSelectPlayer", pID)
	end

	do
		local itemMenu
		local function OpenItemMenu(btn)
			if not addon.Logger.selectedItem then return end
			itemMenu = itemMenu or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")
			local menuList = {
				{
					text = L.StrEditItemLooter,
					func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER") end
				},
				{
					text = L.StrEditItemRollType,
					func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_ROLL") end
				},
				{
					text = L.StrEditItemRollValue,
					func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE") end
				}
			}
			EasyMenu(menuList, itemMenu, "cursor", 0 , 0, "MENU")
		end

		-- Select an item:
		function Logger:SelectItem(btn, button)
			if not btn then
				return
			elseif button == "LeftButton" then
				if not btn then return end
				local iID = btn:GetID()
				if iID ~= addon.Logger.selectedItem then
					addon.Logger.selectedItem = iID
				else
					addon.Logger.selectedItem = nil
				end
				TriggerEvent("LoggerSelectItem", iID)
			elseif button == "RightButton" then
				addon.Logger.selectedItem = btn:GetID()
				OpenItemMenu(btn)
			end
		end

		StaticPopupDialogs["KRTLOGGER_ITEM_EDIT_WINNER"] = {
			text         = L.StrEditItemLooterHelp,
			button1      = SAVE,
			button2      = CANCEL,
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
			hasEditBox = 1,
			cancels = "KRTLOGGER_ITEM_EDIT_WINNER",
			OnShow = function(self)
				self.raidId = addon.Logger.selectedRaid
				self.itemId = addon.Logger.selectedItem
			end,
			OnHide = function(self)
				self.raidId = nil
				self.itemId = nil
			end,
			OnAccept = function(self)
				local name = self.editBox:GetText():trim()

				if name ~= "" and self.raidId and KRT_Raids[self.raidId] then
					for i, player in ipairs(KRT_Raids[self.raidId].players) do
						if name:lower() == player.name:lower() then
							addon:Log(self.itemId, player.name)
							addon.Logger.Loot:Fetch()
							break
						end
					end
				end

				-- default
				self.editBox:SetText("")
				self.editBox:ClearFocus()
				self:Hide()
			end,
		}

		StaticPopupDialogs["KRTLOGGER_ITEM_EDIT_ROLL"] = {
			text         = L.StrEditItemRollTypeHelp,
			button1      = SAVE,
			button2      = CANCEL,
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
			hasEditBox = 1,
			cancels = "KRTLOGGER_ITEM_EDIT_ROLL",
			OnShow = function(self) self.itemId = addon.Logger.selectedItem end,
			OnHide = function(self) self.itemId = nil end,
			OnAccept = function(self)
				local rollType = self.editBox:GetNumber()
				if rollType > 0 and rollType <= 7 then
					addon:Log(self.itemId, nil, rollType)
					addon.Logger.Loot:Fetch()
				end
			end,
		}

		StaticPopupDialogs["KRTLOGGER_ITEM_EDIT_VALUE"] = {
			text         = L.StrEditItemRollValueHelp,
			button1      = SAVE,
			button2      = CANCEL,
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
			hasEditBox = 1,
			cancels = "KRTLOGGER_ITEM_EDIT_VALUE",
			OnShow = function(self) self.itemId = addon.Logger.selectedItem end,
			OnHide = function(self) self.itemId = nil end,
			OnAccept = function(self)
				local rollValue = self.editBox:GetNumber()
				if rollValue ~= nil then
					addon:Log(self.itemId, nil, nil, rollValue)
					addon.Logger.Loot:Fetch()
				end
			end,
		}
	end

	addon:RegisterCallback("LoggerSelectRaid", function()
		addon.Logger.selectedBoss   = nil
		addon.Logger.selectedPlayer = nil
		addon.Logger.selectedItem   = nil
	end)
end

-- Logger Raids List:
do
	addon.Logger.Raids = {}
	local Raids = addon.Logger.Raids
	local frameName

	local LocalizeUIFrame
	local localized = false
	local UpdateUIFrame
	local updateInterval = 0.075

	local InitRaidsList
	local fetched = false
	local raidsTable = {}
	local selectedRaid

	-- OnLoad Frame:
	function Raids:OnLoad(frame)
		if not frame then return end
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Localizing frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."Title"]:SetText(L.StrRaidsList)
			_G[frameName.."HeaderDate"]:SetText(L.StrDate)
			_G[frameName.."HeaderSize"]:SetText(L.StrSize)
			_G[frameName.."CurrentBtn"]:SetText(L.StrSetCurrent)
			_G[frameName.."ExportBtn"]:SetText(L.BtnExport)
		end
		_G[frameName.."ExportBtn"]:Disable() -- FIXME
		addon:SetTooltip(
			_G[frameName.."CurrentBtn"],
			L.StrRaidsCurrentHelp,
			nil,
			L.StrRaidCurrentTitle
		)
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			selectedRaid = addon.Logger.selectedRaid
			if fetched == false then
				InitRaidsList()
				Raids:Fetch()
			end
			-- Highlight selected raid:
			for _, v in ipairs(raidsTable) do
				if selectedRaid and selectedRaid == v.id then
					_G[frameName.."RaidBtn"..v.id]:LockHighlight()
				else
					_G[frameName.."RaidBtn"..v.id]:UnlockHighlight()
				end
			end

			Utils.enableDisable(_G[frameName.."CurrentBtn"], (
				selectedRaid and
				selectedRaid ~= KRT_CurrentRaid and
				not addon.Raid:Expired(selectedRaid) and
				addon:GetRaidSize() == KRT_Raids[selectedRaid].size
			))
			Utils.enableDisable(_G[frameName.."DeleteBtn"], (selectedRaid ~= KRT_CurrentRaid))
		end
	end

	-- Initialize raids list:
	function InitRaidsList()
		raidsTable = {}
		for i, r in ipairs(KRT_Raids) do
			local info = {id = i, zone = r.zone, size = r.size, date = r.startTime}
			tinsert(raidsTable, info)
		end
	end

	-- Utility function to visually hide list:
	local function ResetList()
		local index = 1
		local btn = _G[frameName.."RaidBtn"..index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName.."RaidBtn"..index]
		end
	end

	-- Fetch raids list:
	function Raids:Fetch()
		ResetList()
		local scrollFrame = _G[frameName.."ScrollFrame"]
		local scrollChild = _G[frameName.."ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())

		for i = #raidsTable, 1, -1 do
			local raid = raidsTable[i]
			local btnName = frameName.."RaidBtn"..raid.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerRaidButton")
			btn:SetID(raid.id)
			btn:Show()
			_G[btnName.."ID"]:SetText(raid.id)
			_G[btnName.."Date"]:SetText(date("%d/%m/%Y %H:%M", raid.date))
			_G[btnName.."Zone"]:SetText(raid.zone)
			_G[btnName.."Size"]:SetText(raid.size)
			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end

	-- Set selected raid as current:
	function Raids:SetCurrent(btn)
		if not btn or not selectedRaid or not KRT_Raids[selectedRaid] then return end
		if KRT_Raids[selectedRaid].size ~= addon:GetRaidSize() then
			addon:PrintError(L.ErrCannotSetCurrentRaidSize)
			return
		end
		-- Never set expired raids as current:
		if addon.Raid:Expired(selectedRaid) then
			addon:PrintError(L.ErrCannotSetCurrentRaidReset)
			return
		end
		-- Change current raid:
		KRT_CurrentRaid = selectedRaid
	end

	-- Delete a raid:
	do
		local function DeleteRaid()
			if selectedRaid and KRT_Raids[selectedRaid] then
				-- Make sure to NEVER delete the current raid:
				if KRT_CurrentRaid and KRT_CurrentRaid == selectedRaid then
					addon:PrintError(L.ErrCannotDeleteRaid)
					return
				end
				tremove(KRT_Raids, selectedRaid)
				if KRT_CurrentRaid and KRT_CurrentRaid > selectedRaid then
					KRT_CurrentRaid = KRT_CurrentRaid - 1
				end
				if _G[frameName.."RaidBtn"..selectedRaid] then
					_G[frameName.."RaidBtn"..selectedRaid]:Hide()
				end
				addon.Logger.selectedRaid = nil
				fetched = false
			end
		end

		-- Handles the click on the delete button:
		function Raids:Delete(btn)
			if btn and selectedRaid ~= nil then
				StaticPopup_Show("KRTLOGGER_DELETE_RAID")
			end
		end
		StaticPopupDialogs["KRTLOGGER_DELETE_RAID"] = {
			text         = L.StrConfirmDeleteRaid,
			button1      = L.BtnOK,
			button2      = CANCEL,
			OnAccept     = function() DeleteRaid() end,
			cancels      = "KRTLOGGER_DELETE_RAID",
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
		}
	end

	-- Sorting raids list:
	do
		local ascending = false
		local sortTypes = {
			id = function(a, b)
				if ascending then
					return (a.id < b.id)
				end
				return (a.id > b.id)
			end,
			date = function(a, b)
				if ascending then
					return (a.date < b.date)
				end
				return (a.date > b.date)
			end,
			zone = function(a, b)
				if ascending then
					return (a.zone < b.zone)
				end
				return (a.zone > b.zone)
			end,
			size = function(a, b)
				if ascending then
					return (a.size < b.size)
				end
				return (a.size > b.size)
			end,
		}

		function Raids:Sort(t)
			if t == nil or sortTypes[t] == nil then return end
			ascending = not ascending
			table.sort(raidsTable, sortTypes[t])
			self:Fetch()
		end
	end

	-- Add raid creation callback:
	addon:RegisterCallback("RaidCreate", function(f, num)
		addon.Logger.selectedRaid = tonumber(num)
		fetched = false
	end)
end

-- Logger bosses list:
do
	addon.Logger.Boss = {}
	local Boss = addon.Logger.Boss
	local frameName

	local LocalizeUIFrame
	local localized = false
	local UpdateUIFrame
	local updateInterval = 0.075

	local InitBossList
	local fetched = false
	local bossTable = {}
	local selectedRaid
	local selectedBoss

	function Boss:OnLoad(frame)
		if not frame then return end
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Localizing frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."Title"]:SetText(L.StrBosses)
			_G[frameName.."HeaderTime"]:SetText(L.StrTime)
		end
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		selectedRaid = addon.Logger.selectedRaid
		selectedBoss = addon.Logger.selectedBoss
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if fetched == false then
				InitBossList()
				Boss:Fetch()
			end
			-- Highlight selected raid:
			for _, v in ipairs(bossTable) do
				if selectedBoss ~= nil and selectedBoss == v.id then
					_G[frameName.."BossBtn"..v.id]:LockHighlight()
				else
					_G[frameName.."BossBtn"..v.id]:UnlockHighlight()
				end
			end
			Utils.enableDisable(_G[frameName.."AddBtn"], selectedRaid)
			Utils.enableDisable(_G[frameName.."EditBtn"], selectedBoss)
			Utils.enableDisable(_G[frameName.."DeleteBtn"], selectedBoss)
		end
	end

	-- Initialize bosses list:
	function InitBossList()
		bossTable = addon.Raid:GetBosses(selectedRaid)
		table.sort(bossTable, function(a, b)
			return a.id > b.id
		end)
	end

	-- Utility function to visually hide list:
	local function ResetList()
		local index = 1
		local btn = _G[frameName.."BossBtn"..index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName.."BossBtn"..index]
		end
	end

	-- Fetch bosses list:
	function Boss:Fetch()
		ResetList()
		local scrollFrame = _G[frameName.."ScrollFrame"]
		local scrollChild = _G[frameName.."ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())

		for i, boss in ipairs(bossTable) do
			local btnName = frameName.."BossBtn"..boss.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerBossButton")
			btn:SetID(boss.id)
			btn:Show()
			_G[btnName.."ID"]:SetText(boss.id)
			_G[btnName.."Name"]:SetText(boss.name)
			_G[btnName.."Time"]:SetText(date("%H:%M", boss.time))
			_G[btnName.."Mode"]:SetText(boss.mode)
			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end

	-- Add a boss to raid:
	function Boss:Add(btn)
		if not btn then return end
		addon.Logger.BossBox:Toggle()
	end

	-- Edit a raid boss:
	function Boss:Edit(btn)
		if not btn or not selectedBoss then return end
		addon.Logger.BossBox:Fill()
	end

	-- Delete a boss:
	do
		local function DeleteBoss()
			if not selectedBoss then return end
			local raid = KRT_Raids[selectedRaid]
			if not raid or not raid.bossKills[selectedBoss] then return end
			-- We remove the raid boss first:
			tremove(raid.bossKills, selectedBoss)
			-- We delete all the loot from the boss:
			for i = #raid.loot, 1, -1 do
				if raid.loot[i].bossNum == selectedBoss then
					table.remove(raid.loot, i)
				end
			end
			fetched = false
		end

		-- Handles the click on the delete button:
		function Boss:Delete(btn)
			if btn and selectedBoss ~= nil then
				StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
			end
		end
		StaticPopupDialogs["KRTLOGGER_DELETE_BOSS"] = {
			text         = L.StrConfirmDeleteBoss,
			button1      = L.BtnOK,
			button2      = CANCEL,
			OnAccept     = function() DeleteBoss() end,
			cancels      = "KRTLOGGER_DELETE_BOSS",
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
		}
	end

	-- Sorting bosses list:
	do
		local ascending = false
		local sortTypes = {
			id = function(a, b)
				if ascending then
					return (a.id < b.id)
				end
				return (a.id > b.id)
			end,
			name = function(a, b)
				if ascending then
					return (a.name < b.name)
				end
				return (a.name > b.name)
			end,
			time = function(a, b)
				if ascending then
					return (a.time < b.time)
				end
				return (a.time > b.time)
			end,
			mode = function(a, b)
				if ascending then
					return (a.mode < b.mode)
				end
				return (a.mode > b.mode)
			end,
		}

		-- Sort bosses:
		function Boss:Sort(t)
			if t == nil or sortTypes[t] == nil then return end
			ascending = not ascending
			table.sort(bossTable, sortTypes[t])
			self:Fetch()
		end
	end

	-- Returns the selected boss name:
	function Boss:GetName(bossNum, raidNum)
		local name = L.StrUnknown
		raidNum = raidNum or KRT_CurrentRaid
		local bosses = KRT_Raids[raidNum].bossKills
		if bosses and bosses[bossNum] then
			name = bosses[bossNum].name
			if name == "_TrashMob_" then name = L.StrTrashMob end
		end
		return name
	end

	addon:RegisterCallback("LoggerSelectRaid", function()
		fetched = false
	end)
end

-- Logger boss attendees list:
do
	addon.Logger.BossAttendees = {}
	local BossAttendees = addon.Logger.BossAttendees
	local frameName

	local LocalizeUIFrame
	local localized = false
	local UpdateUIFrame
	local updateInterval = 0.075

	local InitBossAttendeesList
	local fetched = false
	local playersTable = {}
	local selectedRaid
	local selectedBoss
	local selectedBossPlayer

	function BossAttendees:OnLoad(frame)
		if not frame then return end
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Localizing frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."Title"]:SetText(L.StrBossAttendees)
		end
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		selectedRaid = addon.Logger.selectedRaid
		selectedBoss = addon.Logger.selectedBoss
		selectedPlayer = addon.Logger.selectedPlayer
		selectedBossPlayer = addon.Logger.selectedBossPlayer
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if fetched == false then
				InitBossAttendeesList()
				BossAttendees:Fetch()
			end
			for i, p in ipairs(playersTable) do
				if selectedBossPlayer and p.id == selectedBossPlayer and _G[frameName.."PlayerBtn"..p.id] then
					_G[frameName.."PlayerBtn"..p.id]:LockHighlight()
				elseif _G[frameName.."PlayerBtn"..p.id] then
					_G[frameName.."PlayerBtn"..p.id]:UnlockHighlight()
				end
			end
			-- Add/Ban button:
			Utils.enableDisable(_G[frameName.."AddBtn"], selectedBoss and not selectedBossPlayer)
			Utils.enableDisable(_G[frameName.."RemoveBtn"], selectedBoss and selectedBossPlayer)
		end
	end

	-- Initialize boss attendees list:
	function InitBossAttendeesList()
		if not selectedBoss then
			playersTable = {}
			return
		end
		playersTable = addon.Raid:GetPlayers(selectedRaid, selectedBoss)
	end

	-- Utility function to visually hide list:
	local function ResetList()
		local index = 1
		local btn = _G[frameName.."PlayerBtn"..index]
		while btn do
			btn:Hide()
			index = index + 1
			btn = _G[frameName.."PlayerBtn"..index]
		end
	end

	-- Fetch boss attendees list:
	function BossAttendees:Fetch()
		ResetList()
		local scrollFrame = _G[frameName.."ScrollFrame"]
		local scrollChild = _G[frameName.."ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for i, p in ipairs(playersTable) do
			local btnName = frameName.."PlayerBtn"..p.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerBossAttendeeButton")
			btn:SetID(p.id)
			btn:Show()
			local name = _G[btnName.."Name"]
			name:SetText(p.name)
			local r, g, b = addon:GetClassColor(p.class)
			name:SetVertexColor(r, g, b)
			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end

	-- Add a player to raid:
	function BossAttendees:Add(btn)
		if not btn then return end
		addon.Logger.AttendeesBox:Toggle()
	end

	-- Delete a boss attendee:
	do
		local function DeleteAttendee()
			if not selectedBoss or not selectedBossPlayer then return end
			local raid = KRT_Raids[selectedRaid]
			if not raid or not raid.bossKills[selectedBoss] then return end
			-- We remove the raid boss first:
			table.remove(raid.bossKills[selectedBoss].players, selectedBossPlayer)
			-- We delete all the loot from the boss:
			for i = #raid.loot, 1, -1 do
				if raid.loot[i].bossNum == selectedPlayer then
					table.remove(raid.loot, i)
				end
			end
			fetched = false
		end

		-- Handles the click on the delete button:
		function BossAttendees:Delete(btn)
			if btn and selectedBossPlayer  ~= nil then
				StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
			end
		end
		StaticPopupDialogs["KRTLOGGER_DELETE_ATTENDEE"] = {
			text         = L.StrConfirmDeleteAttendee,
			button1      = L.BtnOK,
			button2      = CANCEL,
			OnAccept     = function() DeleteAttendee() end,
			cancels      = "KRTLOGGER_DELETE_ATTENDEE",
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
		}
	end

	-- Sorting boss attendees list:
	do
		local ascending = false
		local sortTypes = {
			name = function(a, b)
				if ascending then
					return (a.name < b.name)
				end
				return (a.name > b.name)
			end,
		}

		-- Sort bosses:
		function BossAttendees:Sort(t)
			if t == nil or sortTypes[t] == nil then return end
			ascending = not ascending
			table.sort(playersTable, sortTypes[t])
			self:Fetch()
		end
	end

	local function ResetFetch()
		fetched = false
	end

	addon:RegisterCallback("LoggerSelectRaid", ResetFetch)
	addon:RegisterCallback("LoggerSelectBoss", ResetFetch)
end

-- Logger raid attendees list:
do
	addon.Logger.RaidAttendees = {}
	local RaidAttendees = addon.Logger.RaidAttendees
	local frameName

	local LocalizeUIFrame
	local localized = false
	local UpdateUIFrame
	local updateInterval = 0.075

	local InitRaidAttendeesList
	local fetched = false
	local playersTable = {}
	local selectedRaid
	local selectedPlayer

	function RaidAttendees:OnLoad(frame)
		if not frame then return end
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Localizing frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."Title"]:SetText(L.StrRaidAttendees)
			_G[frameName.."HeaderJoin"]:SetText(L.StrJoin)
			_G[frameName.."HeaderLeave"]:SetText(L.StrLeave)
		end
		-- FIXME: disable buttons for now
		_G[frameName.."AddBtn"]:Disable()
		_G[frameName.."DeleteBtn"]:Disable()

		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		selectedRaid = addon.Logger.selectedRaid
		selectedPlayer = addon.Logger.selectedPlayer
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if fetched == false then
				InitRaidAttendeesList()
				RaidAttendees:Fetch()
			end
			-- Highlight selected raid:
			for i, p in ipairs(playersTable) do
				if selectedPlayer and p.id == selectedPlayer and _G[frameName.."PlayerBtn"..i] then
					_G[frameName.."PlayerBtn"..i]:LockHighlight()
				elseif _G[frameName.."PlayerBtn"..i] then
					_G[frameName.."PlayerBtn"..i]:UnlockHighlight()
				end
			end
		end
	end

	-- Initialize bosses list:
	function InitRaidAttendeesList()
		playersTable = addon.Raid:GetPlayers(selectedRaid)
	end

	-- Utility function to visually hide list:
	local function ResetList()
		local index = 1
		local btn = _G[frameName.."PlayerBtn"..index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName.."PlayerBtn"..index]
		end
	end

	-- Fetch bosses list:
	function RaidAttendees:Fetch()
		local scrollFrame = _G[frameName.."ScrollFrame"]
		local scrollChild = _G[frameName.."ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for i, p in ipairs(playersTable) do
			local btnName = frameName.."PlayerBtn"..p.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerRaidAttendeeButton")
			btn:SetID(p.id)
			btn:Show()
			local name = _G[btnName.."Name"]
			name:SetText(p.name)
			local r, g, b = addon:GetClassColor(p.class)
			name:SetVertexColor(r, g, b)
			_G[btnName.."Join"]:SetText(date("%H:%M", p.join))
			if p.leave then
				_G[btnName.."Leave"]:SetText(date("%H:%M", p.leave))
			end
			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end

	-- Add a player to raid:
	function RaidAttendees:Add(btn)
		if not btn then return end
		addon:PrintInfo("Coming soon...")
	end

	-- Delete a boss:
	do
		local function DeleteAttendee()
			if not selectedPlayer then return end
			local raid = KRT_Raids[selectedRaid]
			if not raid or not raid.bossKills[selectedPlayer] then return end
			local name = raid.players[selectedPlayer].name
			-- We remove the raid boss first:
			table.remove(raid.players, selectedPlayer)
			-- We delete player from the bosses:
			for _, boss in ipairs(raid.bossKills) do
				for i, playerName in ipairs(boss.players) do
					if playerName == name then
						table.remove(boss.players, i)
					end
				end
			end
			-- We delete all the loot from that player:
                        for i = #raid.loot, 1, -1 do
                                if raid.loot[i].bossNum == selectedPlayer then
                                        tremove(raid.loot, i)
                                end
                        end
			fetched = false
		end

		-- Handles the click on the delete button:
		function RaidAttendees:Delete(btn)
			if btn and selectedPlayer ~= nil then
				StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
			end
		end
		StaticPopupDialogs["KRTLOGGER_DELETE_RAIDATTENDEE"] = {
			text         = L.StrConfirmDeleteAttendee,
			button1      = L.BtnOK,
			button2      = CANCEL,
			OnAccept     = function() DeleteAttendee() end,
			cancels      = "KRTLOGGER_DELETE_RAIDATTENDEE",
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
		}
	end

	-- Sorting bosses list:
	do
		local ascending = false
		local sortTypes = {
			name = function(a, b)
				if ascending then
					return (a.name < b.name)
				end
				return (a.name > b.name)
			end,
			join = function(a, b)
				if ascending then
					return (a.join < b.join)
				end
				return (a.join > b.join)
			end,
			leave = function(a, b)
				if ascending then
					return (a.leave < b.leave)
				end
				return (a.leave > b.leave)
			end,
		}

		-- Sort bosses:
		function RaidAttendees:Sort(t)
			if t == nil or sortTypes[t] == nil then return end
			ascending = not ascending
			table.sort(playersTable, sortTypes[t])
			self:Fetch()
		end
	end

	addon:RegisterCallback("LoggerSelectRaid", function()
		fetched = false
	end)
end

-- Logger loot list:
do
	addon.Logger.Loot = {}
	local Loot = addon.Logger.Loot
	local frameName

	local LocalizeUIFrame
	local localized = false

	local UpdateUIFrame
	local updateInterval = 0.075

	local InitLootList
	local fetched = false
	local raidLoot = {}
	local lootTable = {}
	local selectedRaid
	local selectedBoss
	local selectedPlayer
	local selectedItem

	function Loot:OnLoad(frame)
		if not frame then return end
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Localizing frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."Title"]:SetText(L.StrRaidLoot)
			_G[frameName.."ExportBtn"]:SetText(L.BtnExport)
			_G[frameName.."ClearBtn"]:SetText(L.BtnClear)
			_G[frameName.."EditBtn"]:SetText(L.BtnEdit)
			_G[frameName.."HeaderItem"]:SetText(L.StrItem)
			_G[frameName.."HeaderSource"]:SetText(L.StrSource)
			_G[frameName.."HeaderWinner"]:SetText(L.StrWinner)
			_G[frameName.."HeaderType"]:SetText(L.StrType)
			_G[frameName.."HeaderRoll"]:SetText(L.StrRoll)
			_G[frameName.."HeaderTime"]:SetText(L.StrTime)
		end

		-- FIXME: disable buttons for now
		_G[frameName.."ExportBtn"]:Disable()
		_G[frameName.."ClearBtn"]:Disable()
		_G[frameName.."AddBtn"]:Disable()
		_G[frameName.."EditBtn"]:Disable()

		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		selectedRaid = addon.Logger.selectedRaid
		selectedBoss = addon.Logger.selectedBoss
		selectedPlayer = addon.Logger.selectedPlayer
		selectedItem = addon.Logger.selectedItem
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if fetched == false then
				raidLoot = addon.Raid:GetLoot(selectedRaid)
				InitLootList()
				Loot:Fetch()
			end
			-- Highlight selected raid:
			for i, v in ipairs(raidLoot) do
				if selectedItem and selectedItem == v.id and _G[frameName.."ItemBtn"..i] then
					_G[frameName.."ItemBtn"..i]:LockHighlight()
				elseif _G[frameName.."ItemBtn"..i] then
					_G[frameName.."ItemBtn"..i]:UnlockHighlight()
				end
			end
			Utils.enableDisable(_G[frameName.."DeleteBtn"], selectedItem)
		end
	end

	-- Initialize bosses list:
	function InitLootList()
		lootTable = {}
		if not selectedPlayer then
			lootTable = addon.Raid:GetLoot(selectedRaid, selectedBoss)
		else
			lootTable = addon.Raid:GetPlayerLoot(selectedPlayer, selectedRaid, selectedBoss)
		end
	end

	-- Utility function to visually hide list:
	local function ResetList()
		local index = 1
		local btn = _G[frameName.."ItemBtn"..index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName.."ItemBtn"..index]
		end
	end

	-- Fetch bosses list:
	function Loot:Fetch()
		ResetList()
		local scrollFrame = _G[frameName.."ScrollFrame"]
		local scrollChild = _G[frameName.."ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for k, v in ipairs(lootTable) do
			local btnName = frameName.."ItemBtn"..v.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerLootButton")
			btn:SetID(v.id)
			btn:Show()

			_G[btnName.."Name"]:SetText("|c"..itemColors[v.itemRarity+1]..v.itemName.."|r")
			_G[btnName.."Source"]:SetText(addon.Logger.Boss:GetName(v.bossNum, selectedRaid))
			local player = v.looter
			local class = addon:GetPlayerClass(player)
			local r, g, b = addon:GetClassColor(class)
			_G[btnName.."Winner"]:SetText(player)
			_G[btnName.."Winner"]:SetVertexColor(r, g, b)
			_G[btnName.."Type"]:SetText(lootTypesColored[v.rollType] or lootTypesColored[6])
			_G[btnName.."Roll"]:SetText(v.rollValue or 0)
			_G[btnName.."Time"]:SetText(date("%H:%M", v.time))
			_G[btnName.."ItemIconTexture"]:SetTexture(v.itemTexture)

			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end

	-- Sorting bosses list:
	do
		local ascending = false
		local sortTypes = {
			id = function(a, b)
				if ascending then
					return (a.itemId < b.itemId)
				end
				return (a.itemId > b.itemId)
			end,
			source = function(a, b)
				if ascending then
					return (a.bossNum < b.bossNum)
				end
				return (a.bossNum > b.bossNum)
			end,
			winner = function(a, b)
				if ascending then
					return (a.looter < b.looter)
				end
				return (a.looter > b.looter)
			end,
			type = function(a, b)
				if not a.rollType or not b.rollType then return end
				if ascending then
					return (lootTypesColored[a.rollType] < lootTypesColored[b.rollType])
				end
				return (lootTypesColored[a.rollType] > lootTypesColored[b.rollType])
			end,
			roll = function(a, b)
				if not a.rollValue and not b.rollValue then return end
				if ascending then
					return (a.rollValue < b.rollValue)
				end
				return (a.rollValue > b.rollValue)
			end,
			time = function(a, b)
				if ascending then
					return (a.time < b.time)
				end
				return (a.time > b.time)
			end,
		}

		-- Sort bosses:
		function Loot:Sort(t)
			if t == nil or sortTypes[t] == nil then return end
			ascending = not ascending
			table.sort(lootTable, sortTypes[t])
			self:Fetch()
		end
	end

	function Loot:OnEnter(btn)
		if not btn then return end
		local iID = btn:GetParent():GetID()
		if not raidLoot[iID] then return end
		GameTooltip:SetOwner(btn, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(raidLoot[iID].itemString)
	end

	-- Delete an item:
	do
		local function DeleteItem()
			if selectedRaid and KRT_Raids[selectedRaid] then
				tremove(KRT_Raids[selectedRaid].loot, selectedItem)
				if _G[frameName.."ItemBtn"..selectedItem] then
					_G[frameName.."ItemBtn"..selectedItem]:Hide()
				end
				addon.Logger.selectedItem = nil
				fetched = false
			end
		end

		-- Handles the click on the delete button:
		function Loot:Delete(btn)
			if btn and selectedItem ~= nil then
				StaticPopup_Show("KRTLOGGER_DELETE_ITEM")
			end
		end
		StaticPopupDialogs["KRTLOGGER_DELETE_ITEM"] = {
			text         = L.StrConfirmDeleteItem,
			button1      = L.BtnOK,
			button2      = CANCEL,
			OnAccept     = function() DeleteItem() end,
			cancels      = "KRTLOGGER_DELETE_ITEM",
			timeout      = 0,
			whileDead    = 1,
			hideOnEscape = 1,
		}
	end

	-- Reset fetch status callback:
	local function ResetFetch()
		fetched = false
	end

	addon:RegisterCallback("LoggerSelectRaid", ResetFetch)
	addon:RegisterCallback("LoggerSelectBoss", ResetFetch)
	addon:RegisterCallback("LoggerSelectPlayer", ResetFetch)

	-- =================== --

	function addon:Log(iID, looter, rollType, rollValue)
		local raidID = addon.Logger and addon.Logger.selectedRaid
		if not raidID or not KRT_Raids or not KRT_Raids[raidID] then
			return
		end

		local lootList = KRT_Raids[raidID].loot
		if not lootList or not lootList[iID] then
			return
		end

		if looter and looter ~= "" then
			lootList[iID].looter = looter
			fetched = false
		end
		if tonumber(rollType) ~= nil then
			lootList[iID].rollType  = tonumber(rollType)
			fetched = false
		end
		if tonumber(rollValue) ~= nil then
			lootList[iID].rollValue = tonumber(rollValue)
			fetched = false
		end
	end
end

-- Add Boss Box
do
	addon.Logger.BossBox = {}
	local BossBox = addon.Logger.BossBox
	local UIFrame, frameName
	local LocalizeUIFrame, UpdateUIFrame
	local localized = false
	local updateInterval = 0.1
	local CancelAddEdit
	local selectedRaid, selectedBoss
	-- local isAdd = false
	local isEdit = false

	local raidData = {}
	local bossData = {}
	local tempDate = {}
	local datePattern = "(%d+)/(%d+)/(%d+) (%d+):(%d+)"

	function BossBox:OnLoad(frame)
		if not frame then return end
		UIFrame = frame
		-- UILoggerBossBox = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
		frame:SetScript("OnHide", CancelAddEdit)
	end

	function BossBox:Toggle()
		Utils.toggle(UIFrame)
	end

	function BossBox:Hide()
		if UIFrame and UIFrame:IsShown() then
			CancelAddEdit()
			UIFrame:Hide()
		end
	end

	function BossBox:Fill()
		selectedRaid = addon.Logger.selectedRaid
		selectedBoss = addon.Logger.selectedBoss

		if not selectedRaid or not selectedBoss then return end
		raidData = KRT_Raids[selectedRaid]
		if not raidData then return end
		bossData = raidData.bossKills[selectedBoss]
		if not bossData then return end

		-- Fill our boss name:
		_G[frameName.."Name"]:SetText(bossData.name)

		-- Prepare boss kill time then fill box:
		local t = date("%d/%m/%Y %H:%M", bossData.date)
		local day, month, year, hour, minute = match(t, datePattern)
		tempDate = {
			day = tonumber(day),
			month = tonumber(month),
			year = tonumber(year),
			hour = tonumber(hour),
			min = tonumber(minute)
		}
		_G[frameName.."Time"]:SetText(string.format("%02d:%02d", tempDate.hour, tempDate.min))
		_G[frameName.."Difficulty"]:SetText((bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n")
		isEdit = true
		self:Toggle()
	end

	function BossBox:Save()
		selectedRaid = addon.Logger.selectedRaid
		if not selectedRaid then return end
		local name = _G[frameName.."Name"]:GetText():trim()
		local diff = _G[frameName.."Difficulty"]:GetText():trim():lower()
		local bTime = _G[frameName.."Time"]:GetText():trim()

		-- Check the name:
		name = (name == "") and "_TrashMob_" or name

		-- Check the difficulty:
		if name ~= "_TrashMob_" and (diff ~= "h" and diff ~= "n") then
			addon:PrintError(L.ErrBossDifficulty)
			return
		end

		local hour, minute

		if isEdit and bossData ~= nil then
			-- Use provided time or fallback to previous values:
			if bTime == "" then
				hour, minute = tempDate.hour, tempDate.min
			else
				hour, minute = match(bTime, "(%d+):(%d+)")
				hour, minute = tonumber(hour), tonumber(minute)
			end
		else
			hour, minute = GetGameTime()
		end

		-- Validate time values:
		if not hour or not minute then
			addon:PrintError(L.ErrBossTime)
			return
		end

		local difficulty = (raidData.size == 10) and 1 or 2
		if diff == "h" then difficulty = difficulty + 2 end

		local _, month, day, year = CalendarGetDate()

		if isEdit and bossData ~= nil then
			-- Update existing bossData:
			bossData.name = name
			tempDate.hour = hour
			tempDate.min = minute
			bossData.date = time(tempDate)
			bossData.difficulty = difficulty
			KRT_Raids[selectedRaid].bossKills[selectedBoss] = bossData
			isEdit = false
		else
			-- Create new bossData:
			local boss = {
				name = name,
				date = time({day=day, month=month, year=year, hour=hour, min=minute}),
				difficulty = difficulty,
				players = {},
			}
			tinsert(KRT_Raids[selectedRaid].bossKills, boss)
		end

		CancelAddEdit()
		self:Hide()
		TriggerEvent("LoggerSelectRaid")
	end

	function CancelAddEdit()
		selectedRaid = nil
		selectedBoss = nil
		_G[frameName.."Name"]:SetText("")
		_G[frameName.."Difficulty"]:SetText("")
		_G[frameName.."Time"]:SetText("")
		isEdit = false
		-- isAdd = false
	end

	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."Title"]:SetText(L.StrAddBoss)
		end
		-- Help tooltips:
		addon:SetTooltip(_G[frameName.."Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
		addon:SetTooltip(_G[frameName.."Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
		addon:SetTooltip(_G[frameName.."Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
		localized = true
	end
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			Utils.setText(_G[frameName.."Title"], L.StrEditBoss, L.StrAddBoss, (selectedBoss and isEdit))
		end
	end
end

-- Add Boss Attendee Box
do
	addon.Logger.AttendeesBox = {}
	local AttendeesBox = addon.Logger.AttendeesBox
	local UIFrame, frameName
	local localized = false
	local updateInterval = 0.5
	local selectedRaid, selectedBoss

	local function CancelAdd()
		_G[frameName.."Name"]:SetText("")
		_G[frameName.."Name"]:ClearFocus()
		UIFrame:Hide()
	end

	local function LocalizeUIFrame()
		if not localized then
			if GetLocale() ~= "enUS" and GetLocale() then
				_G[frameName.."Title"]:SetText(L.StrAddPlayer)
			end
			localized = true
		end
	end

	local function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		selectedRaid = addon.Logger.selectedRaid
		selectedBoss = addon.Logger.selectedBoss
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
		end
	end

	function AttendeesBox:OnLoad(frame)
		if not frame then return end
		UIFrame = frame
		-- UILoggerPlayerBox = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
		frame:SetScript("OnShow", function(self)
			_G[frameName.."Name"]:SetText("")
			_G[frameName.."Name"]:SetFocus()
		end)
		frame:SetScript("OnHide", function(self)
			_G[frameName.."Name"]:SetText("")
			_G[frameName.."Name"]:ClearFocus()
		end)
	end

	function AttendeesBox:Toggle()
		Utils.toggle(UIFrame)
	end

	function AttendeesBox:Save()
		local name = _G[frameName.."Name"]:GetText()
		-- invalid name provided.
		if name:trim() == "" then
			addon:PrintError(L.ErrAttendeesInvalidName)
			return
		end

		-- check if the player was in the raid.
		if not selectedRaid or not KRT_Raids[selectedRaid] or not selectedBoss then
			addon:PrintError(L.ErrAttendeesInvalidRaidBoss)
			return
		end

		-- the player is already there
		for _, n in ipairs(KRT_Raids[selectedRaid].bossKills[selectedBoss].players) do
			if n:lower() == name:lower() then
				addon:PrintError(L.ErrAttendeesPlayerExists)
				return
			end
		end

		local players = KRT_Raids[selectedRaid].players
		for _, player in ipairs(players) do
			if name:lower() == player.name:lower() then
				addon:PrintSuccess(L.StrAttendeesAddSuccess)
				tinsert(KRT_Raids[selectedRaid].bossKills[selectedBoss].players, player.name)
				CancelAdd()
				return
			end
		end
		addon:PrintError(L.ErrAttendeesNotFound or "Player not in raid")
		addon.Logger.BossAttendees:Fetch()
	end

