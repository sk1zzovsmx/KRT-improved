local addonName, addon = ...
addon.Changes = {}
local Changes = addon.Changes

local frameName

local LocalizeUIFrame
local localized = false

local UpdateUIFrame
local updateInterval = 0.1

local changesTable = {}
local FetchChanges, SaveChanges, CancelChanges
local fetched = false
local selectedID, tempSelectedID
local isAdd = false
local isEdit = false

-- OnLoad frame:
function Changes:OnLoad(frame)
	addon:Debug("DEBUG", "MS Changes frame loaded.")
	if not frame then return end
	UIChanges = frame
	frameName = frame:GetName()
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnUpdate", UpdateUIFrame)
end

-- Toggle frame visibility:
function Changes:Toggle()
	addon:Debug("DEBUG", "Toggling MS Changes frame visibility.")
	CancelChanges()
	Utils.toggle(UIChanges)
end

-- Hide frame:
function Changes:Hide()
	addon:Debug("DEBUG", "Hiding MS Changes frame.")
	if UIChanges and UIChanges:IsShown() then
		CancelChanges()
		UIChanges:Hide()
	end
end

-- Clear Changes:
function Changes:Clear()
	addon:Debug("DEBUG", "Clearing changes.")
	if not KRT_CurrentRaid or changesTable == nil then return end
	for n, p in pairs(changesTable) do
		changesTable[n] = nil
		if _G[frameName .. "PlayerBtn" .. n] then
			_G[frameName .. "PlayerBtn" .. n]:Hide()
		end
	end
	CancelChanges()
	fetched = false
end

-- Selecting Player:
function Changes:Select(btn)
	-- No selection.
	addon:Debug("DEBUG", "Selecting player for changes.")
	if not btn then return end
	local btnName = btn:GetName()
	local name = _G[btnName .. "Name"]:GetText()
	-- No ID set.
	if not name then return end
	-- Make sure the player exists in the raid:
	local found = true
	if not addon.Raid:CheckPlayer(name) then found = false end
	if not changesTable[name] then found = false end
	if not found then
		if _G[frameName .. "PlayerBtn" .. name] then
			_G[frameName .. "PlayerBtn" .. name]:Hide()
		end
		fetched = false
		return
	end
	-- Quick announce?
	if IsControlKeyDown() then
		tempSelectedID = (name ~= selectedID) and name or nil
		self:Announce()
		return
	end
	-- Selection:
	selectedID = (name ~= selectedID) and name or nil
	isAdd = false
	isEdit = false
end

-- Add / Delete:
function Changes:Add(btn)
	addon:Debug("DEBUG", "Adding or deleting change for player.")
	if not KRT_CurrentRaid or not btn then return end
	if not selectedID then
		btn:Hide()
		_G[frameName .. "Name"]:Show()
		_G[frameName .. "Name"]:SetFocus()
		isAdd = true
	elseif changesTable[selectedID] then
		changesTable[selectedID] = nil
		if _G[frameName .. "PlayerBtn" .. selectedID] then
			_G[frameName .. "PlayerBtn" .. selectedID]:Hide()
		end
		CancelChanges()
		fetched = false
	end
end

-- Edit / Save
function Changes:Edit()
	addon:Debug("DEBUG", "Editing or saving change for player.")
	if not KRT_CurrentRaid then return end
	if not selectedID or isEdit then
		local name = _G[frameName .. "Name"]:GetText()
		local spec = _G[frameName .. "Spec"]:GetText()
		SaveChanges(name, spec)
	elseif changesTable[selectedID] then
		_G[frameName .. "Name"]:SetText(selectedID)
		_G[frameName .. "Spec"]:SetText(changesTable[selectedID])
		_G[frameName .. "Spec"]:Show()
		_G[frameName .. "Spec"]:SetFocus()
		isAdd = false
		isEdit = true
	end
end

-- Remove player's change:
function Changes:Delete(name)
	addon:Debug("DEBUG", "Deleting change for player: " .. (name or "nil"))
	if not KRT_CurrentRaid or not name then return end
	KRT_Raids[KRT_CurrentRaid].changes[name] = nil
	if _G[frameName .. "PlayerBtn" .. name] then
		_G[frameName .. "PlayerBtn" .. name]:Hide()
	end
end

addon:RegisterCallback("RaidLeave", function(e, name)
	Changes:Delete(name)
	CancelChanges()
end)

-- Ask For Changes:
function Changes:Demand()
	addon:Debug("DEBUG", "Requesting changes from players.")
	if not KRT_CurrentRaid then return end
	addon:Announce(L.StrChangesDemand)
end

-- Spam Changes:
function Changes:Announce()
	addon:Debug("DEBUG", "Announcing changes.")
	if not KRT_CurrentRaid then return end
	-- In case of a reload/relog and the frame wasn't loaded
	if not fetched or #changesTable == 0 then
		InitChangesTable()
		FetchChanges()
	end
	local count = Utils.tableLen(changesTable)
	local msg
	if count == 0 then
		if tempSelectedID then
			tempSelectedID = nil
			return
		end
		msg = L.StrChangesAnnounceNone
	elseif selectedID or tempSelectedID then
		local name = tempSelectedID and tempSelectedID or selectedID
		if tempSelectedID ~= nil then tempSelectedID = nil end
		if not changesTable[name] then return end
		msg = format(L.StrChangesAnnounceOne, name, changesTable[name])
	else
		msg = L.StrChangesAnnounce
		local i = count
		for n, c in pairs(changesTable) do
			msg = msg .. " " .. n .. "=" .. c
			i = i - 1
			if i > 0 then msg = msg .. " /" end
		end
	end
	addon:Announce(msg)
end

-- Localize UI Frame:
function LocalizeUIFrame()
	if localized then return end
	if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
		_G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
		_G[frameName .. "AddBtn"]:SetText(ADD)
		_G[frameName .. "EditBtn"]:SetText(L.BtnEdit)
		_G[frameName .. "DemandBtn"]:SetText(L.BtnDemand)
		_G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
	end
	_G[frameName .. "Title"]:SetText(format(titleString, L.StrChanges))
	_G[frameName .. "Name"]:SetScript("OnEnterPressed", Changes.Edit)
	_G[frameName .. "Spec"]:SetScript("OnEnterPressed", Changes.Edit)
	_G[frameName .. "Name"]:SetScript("OnEscapePressed", CancelChanges)
	_G[frameName .. "Spec"]:SetScript("OnEscapePressed", CancelChanges)
	localized = true
end

-- OnUpdate frame:
function UpdateUIFrame(self, elapsed)
	LocalizeUIFrame()
	if Utils.periodic(self, frameName, updateInterval, elapsed) then
		if not fetched then
			InitChangesTable()
			FetchChanges()
		end
		local count = Utils.tableLen(changesTable)
		if count > 0 then
			for n, s in pairs(changesTable) do
				if selectedID == n and _G[frameName .. "PlayerBtn" .. n] then
					_G[frameName .. "PlayerBtn" .. n]:LockHighlight()
				elseif _G[frameName .. "PlayerBtn" .. n] ~= nil then
					_G[frameName .. "PlayerBtn" .. n]:UnlockHighlight()
				end
			end
		else
			tempSelectedID = nil
			selectedID = nil
		end
		Utils.showHide(_G[frameName .. "Name"], (isEdit or isAdd))
		Utils.showHide(_G[frameName .. "Spec"], (isEdit or isAdd))
		Utils.enableDisable(_G[frameName .. "EditBtn"], (selectedID or isEdit or isAdd))
		Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, isAdd or (selectedID and isEdit))
		Utils.setText(_G[frameName .. "AddBtn"], ADD, DELETE, (not selectedID and not isEdit and not isAdd))
		Utils.showHide(_G[frameName .. "AddBtn"], (not isEdit and not isAdd))
		Utils.enableDisable(_G[frameName .. "ClearBtn"], count > 0)
		Utils.enableDisable(_G[frameName .. "AnnounceBtn"], count > 0)
		Utils.enableDisable(_G[frameName .. "AddBtn"], KRT_CurrentRaid)
		Utils.enableDisable(_G[frameName .. "DemandBtn"], KRT_CurrentRaid)
	end
end

-- Initialize changes table:
function InitChangesTable()
	addon:Debug("DEBUG", "Initializing changes table.")
	changesTable = KRT_CurrentRaid and KRT_Raids[KRT_CurrentRaid].changes or {}
end

-- Fetch All Changes:
function FetchChanges()
	addon:Debug("DEBUG", "Fetching all changes.")
	if not KRT_CurrentRaid then return end
	local scrollFrame = _G[frameName .. "ScrollFrame"]
	local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
	local totalHeight = 0
	scrollChild:SetHeight(scrollFrame:GetHeight())
	scrollChild:SetWidth(scrollFrame:GetWidth())
	for n, c in pairs(changesTable) do
		local btnName = frameName .. "PlayerBtn" .. n
		local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTChangesButtonTemplate")
		btn:Show()
		local name = _G[btnName .. "Name"]
		name:SetText(n)
		local class = addon:GetPlayerClass(n)
		local r, g, b = addon:GetClassColor(class)
		name:SetVertexColor(r, g, b)
		_G[btnName .. "Spec"]:SetText(c)
		btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
		btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
		totalHeight = totalHeight + btn:GetHeight()
	end
	fetched = true
end

-- Save Changes:
function SaveChanges(name, spec)
	addon:Debug("DEBUG", "Saving changes for player: " .. (name or "nil"))
	if not KRT_CurrentRaid or not name then return end
	name = ucfirst(name:trim())
	spec = ucfirst(spec:trim())
	-- Is the player in the raid?
	local found
	found, name = addon.Raid:CheckPlayer(name)
	if not found then
		addon:PrintError(format((name == "" and L.ErrChangesNoPlayer or L.ErrCannotFindPlayer), name))
		return
	end
	changesTable[name] = (spec == "") and nil or spec
	CancelChanges()
	fetched = false
end

-- Cancel all actions:
function CancelChanges()
	addon:Debug("DEBUG", "Cancelling all changes.")
	isAdd = false
	isEdit = false
	selectedID = nil
	tempSelectedID = nil
	_G[frameName .. "Name"]:SetText("")
	_G[frameName .. "Name"]:ClearFocus()
	_G[frameName .. "Spec"]:SetText("")
	_G[frameName .. "Spec"]:ClearFocus()
end
