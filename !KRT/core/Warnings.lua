local addonName, addon = ...
addon.Warnings = {}
local Warnings = addon.Warnings

	local frameName

	local LocalizeUIFrame
	local localized = false

	local UpdateUIFrame
	local updateInterval = 0.1

	local FetchWarnings
	local fetched = false

	local selectedID, tempSelectedID

	local tempName, tempContent
	local SaveWarning
	local isEdit = false

	-- OnLoad frame:
	function Warnings:OnLoad(frame)
		addon:Debug("DEBUG", "Warnings frame loaded.")
		if not frame then return end
		UIWarnings = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Externally update frame:
	function Warnings:Update()
		addon:Debug("DEBUG", "Updating warnings frame.")
		return FetchWarnings()
	end

	-- Toggle frame visibility:
	function Warnings:Toggle()
		addon:Debug("DEBUG", "Toggling Warnings frame visibility.")
		Utils.toggle(UIWarnings)
	end

	-- Hide frame:
	function Warnings:Hide()
		addon:Debug("DEBUG", "Hiding Warnings frame.")
		if UIWarnings and UIWarnings:IsShown() then
			UIWarnings:Hide()
		end
	end

	-- Warning selection:
	function Warnings:Select(btn)
		addon:Debug("DEBUG", "Selecting warning.")
		if btn == nil or isEdit == true then return end
		local bName = btn:GetName()
		local wID = tonumber(_G[bName.."ID"]:GetText())
		addon:Debug("DEBUG", "Selected Warning ID: " .. (wID or "nil"))
		if KRT_Warnings[wID] == nil then return end
		if IsControlKeyDown() then
			selectedID = nil
			tempSelectedID = wID
			return self:Announce(tempSelectedID)
		end
		selectedID = (wID ~= selectedID) and wID or nil
		addon:Debug("DEBUG", "Warning selected, ID: " .. (selectedID or "nil"))
	end

	-- Edit/Save warning:
	function Warnings:Edit()
		addon:Debug("DEBUG", "Editing warning.")
		local wName, wContent
		if selectedID ~= nil then
			local w = KRT_Warnings[selectedID]
			if w == nil then
				selectedID = nil
				return
			end
			if not isEdit and (tempName == "" and tempContent == "") then
				_G[frameName.."Name"]:SetText(w.name)
				_G[frameName.."Name"]:SetFocus()
				_G[frameName.."Content"]:SetText(w.content)
				isEdit = true
				addon:Debug("DEBUG", "Started editing warning: " .. w.name)
				return
			end
		end
		wName    = _G[frameName.."Name"]:GetText()
		wContent = _G[frameName.."Content"]:GetText()
		addon:Debug("DEBUG", "Saving edited warning with name: " .. (wName or "nil"))
		return SaveWarning(wContent, wName, selectedID)
	end

	-- Delete Warning:
	function Warnings:Delete(btn)
		addon:Debug("DEBUG", "Deleting warning.")
		if btn == nil or selectedID == nil then return end
		local oldWarnings = {}
		for i, w in ipairs(KRT_Warnings) do
			_G[frameName.."WarningBtn"..i]:Hide()
			if i ~= selectedID then
				tinsert(oldWarnings, w)
			end
		end
		twipe(KRT_Warnings)
		KRT_Warnings = oldWarnings
		local count = #KRT_Warnings
		if count <= 0 then
			selectedID = nil
		elseif count == 1 then
			selectedID = 1
		elseif selectedID > count then
			selectedID = selectedID - 1
		end
		FetchWarnings()
		addon:Debug("DEBUG", "Deleted warning. Remaining warnings: " .. #KRT_Warnings)
	end

	-- Announce Warning:
	function Warnings:Announce(wID)
		addon:Debug("DEBUG", "Announcing warning with ID: " .. (wID or "nil"))
		if KRT_Warnings == nil then return end
		if wID == nil then
			wID = (selectedID ~= nil) and selectedID or tempSelectedID
		end
		if wID <= 0 or KRT_Warnings[wID] == nil then return end
		tempSelectedID = nil -- Always clear temporary selected id:
		addon:Announce(KRT_Warnings[wID].content)
		addon:Debug("DEBUG", "Announcement sent: " .. KRT_Warnings[wID].content)
	end

	-- Cancel editing/adding:
	function Warnings:Cancel()
		addon:Debug("DEBUG", "Canceling warning editing.")
		_G[frameName.."Name"]:SetText("")
		_G[frameName.."Name"]:ClearFocus()
		_G[frameName.."Content"]:SetText("")
		_G[frameName.."Content"]:ClearFocus()
		selectedID = nil
		tempSelectedID = nil
		isEdit = false
	end

	-- Localizing UI frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."MessageStr"]:SetText(L.StrMessage)
			_G[frameName.."EditBtn"]:SetText(SAVE)
			_G[frameName.."OutputName"]:SetText(L.StrWarningsHelp)
		end
		_G[frameName.."Title"]:SetText(format(titleString, RAID_WARNING))
		_G[frameName.."Name"]:SetScript("OnEscapePressed", Warnings.Cancel)
		_G[frameName.."Content"]:SetScript("OnEscapePressed", Warnings.Cancel)
		_G[frameName.."Name"]:SetScript("OnEnterPressed", Warnings.Edit)
		_G[frameName.."Content"]:SetScript("OnEnterPressed", Warnings.Edit)
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if fetched == false then FetchWarnings() end
			if #KRT_Warnings > 0 then
				for i = 1, #KRT_Warnings do
					if selectedID == i and _G[frameName.."WarningBtn"..i] then
						_G[frameName.."WarningBtn"..i]:LockHighlight()
						_G[frameName.."OutputName"]:SetText(KRT_Warnings[selectedID].name)
						_G[frameName.."OutputContent"]:SetText(KRT_Warnings[selectedID].content)
						_G[frameName.."OutputContent"]:SetTextColor(1, 1, 1)
					else
						_G[frameName.."WarningBtn"..i]:UnlockHighlight()
					end
				end
			end
			if selectedID == nil then
				_G[frameName.."OutputName"]:SetText(L.StrWarningsHelp)
				_G[frameName.."OutputContent"]:SetText(L.StrWarningsHelp)
				_G[frameName.."OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
			end
			tempName    = _G[frameName.."Name"]:GetText()
			tempContent = _G[frameName.."Content"]:GetText()
			Utils.enableDisable(_G[frameName.."EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
			Utils.enableDisable(_G[frameName.."DeleteBtn"], selectedID ~= nil)
			Utils.enableDisable(_G[frameName.."AnnounceBtn"], selectedID ~= nil)
			Utils.setText(_G[frameName.."EditBtn"], SAVE, L.BtnEdit, (tempName ~= "" or tempContent ~= "") or selectedID == nil)
		end
	end

	-- Saving a Warning:
	function SaveWarning(wContent, wName, wID)
		addon:Debug("DEBUG", "Saving warning: " .. (wID or "nil"))
		wID = wID and tonumber(wID) or 0
		wName = tostring(wName):trim()
		wContent = tostring(wContent):trim()
		if wName == "" then
			wName = (isEdit and wID > 0) and wID or (#KRT_Warnings + 1)
		end
		if wContent == "" then
			addon:PrintError(L.StrWarningsError)
			return
		end
		if isEdit and wID > 0 and KRT_Warnings[wID] ~= nil then
			KRT_Warnings[wID].name = wName
			KRT_Warnings[wID].content = wContent
			isEdit = false
		else
			tinsert(KRT_Warnings, {name = wName, content = wContent})
		end
		_G[frameName.."Name"]:SetText("")
		_G[frameName.."Name"]:ClearFocus()
		_G[frameName.."Content"]:SetText("")
		_G[frameName.."Content"]:ClearFocus()
		Warnings:Cancel()
		Warnings:Update()
	end

	-- Fetch Warnings:
	function FetchWarnings()
		addon:Debug("DEBUG", "Fetching warnings.")
		local scrollFrame = _G[frameName.."ScrollFrame"]
		local scrollChild = _G[frameName.."ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for i, w in pairs(KRT_Warnings) do
			local btnName = frameName.."WarningBtn"..i
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTWarningButtonTemplate")
			btn:Show()
			local ID = _G[btnName.."ID"]
			ID:SetText(i)
			local wName = _G[btnName.."Name"]
			wName:SetText(w.name)
			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end

