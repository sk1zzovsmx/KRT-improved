local addonName, addon = ...
addon.Minimap = {}
local Minimap = addon.Minimap

	local MinimapBtn = addon.Minimap

	-- Menu locals:
	local addonMenu

	-- Button & drag mode:
	local dragMode

	-- Cache frequently used global:
	local abs, sqrt = math.abs, math.sqrt

	-- Initialize minimap menu:
	local function OpenMenu()
		local info = {}
		addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
		addonMenu.displayMode = "MENU"
		addonMenu.initialize = function(self, level)
			if not level then return end
			wipe(info)
			if level == 1 then
				-- Toggle master loot frame:
				info.text = MASTER_LOOTER
				info.notCheckable = 1
				info.func = function() addon.Master:Toggle() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Toggle raid warnings frame:
				info.text = RAID_WARNING
				info.notCheckable = 1
				info.func = function() addon.Warnings:Toggle() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Toggle loot history frame:
				info.text = L.StrLootHistory
				info.notCheckable = 1
				info.func = function() addon.Logger:Toggle() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Separator:
				info.disabled = 1
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Clear raid icons:
				info.text = L.StrClearIcons
				info.notCheckable = 1
				info.func = function() addon:ClearRaidIcons() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Separator:
				info.disabled = 1
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- MS changes header:
				info.isTitle = 1
				info.text = L.StrMSChanges
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				info.notCheckable = 1
				-- Toggle MS Changes frame:
				info.text = L.BtnConfigure
				info.notCheckable = 1
				info.func = function() addon.Changes:Toggle() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Ask for MS changes:
				info.text = L.BtnDemand
				info.notCheckable = 1
				info.func = function() addon.Changes:Demand() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Spam ms changes:
				info.text = CHAT_ANNOUNCE
				info.notCheckable = 1
				info.func = function() addon.Changes:Announce() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				info.disabled = 1
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
				-- Toggle lfm spammer frame:
				info.text = L.StrLFMSpam
				info.notCheckable = 1
				info.func = function() addon.Spammer:Toggle() end
				UIDropDownMenu_AddButton(info, level)
				wipe(info)
			end
		end
		ToggleDropDownMenu(1, nil, addonMenu, KRT_MINIMAP_GUI, 0, 0)
	end

	-- Move button:
	local function moveButton(self)
		local centerX, centerY = Minimap:GetCenter()
		local x, y = GetCursorPosition()
		x, y = x / self:GetEffectiveScale() - centerX, y / self:GetEffectiveScale() - centerY

		if dragMode == "free" then
			self:ClearAllPoints()
			self:SetPoint("CENTER", x, y)
		else
			centerX, centerY = abs(x), abs(y)
			centerX, centerY = (centerX / sqrt(centerX^2 + centerY^2)) * 80, (centerY / sqrt(centerX^2 + centerY^2)) * 80
			centerX = x < 0 and -centerX or centerX
			centerY = y < 0 and -centerY or centerY
			self:ClearAllPoints()
			self:SetPoint("CENTER", centerX, centerY)
		end
	end

	-- OnLoad minimap button:
	function MinimapBtn:OnLoad(btn)
		if not btn then return end
		KRT_MINIMAP_GUI:SetUserPlaced(true)
		KRT_MINIMAP_GUI:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		KRT_MINIMAP_GUI:SetScript("OnMouseDown", function(self, button)
			if IsAltKeyDown() then
				dragMode = "free"
				self:SetScript("OnUpdate", moveButton)
			elseif IsShiftKeyDown() then
				dragMode = nil
				self:SetScript("OnUpdate", moveButton)
			end
		end)
		KRT_MINIMAP_GUI:SetScript("OnMouseUp", function(self)
			self:SetScript("OnUpdate", nil)
		end)
		KRT_MINIMAP_GUI:SetScript("OnClick", function(self, button, down)
			-- Ignore clicks if Shift or Alt keys are held:
			if IsShiftKeyDown() or IsAltKeyDown() then return end
			if button == "RightButton" then
				addon.Config:Toggle()
			elseif button == "LeftButton" then
				OpenMenu()
			end
		end)
		KRT_MINIMAP_GUI:SetScript("OnEnter", function(self)
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			GameTooltip:SetText("|cfff58cbaKader|r |caad4af37Raid Tools|r")
			GameTooltip:AddLine(L.StrMinimapLClick, 1, 1, 1)
			GameTooltip:AddLine(L.StrMinimapRClick, 1, 1, 1)
			GameTooltip:AddLine(L.StrMinimapSClick, 1, 1, 1)
			GameTooltip:AddLine(L.StrMinimapAClick, 1, 1, 1)
			GameTooltip:Show()
		end)
		KRT_MINIMAP_GUI:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)
	end

	-- Toggle button visibility:
	function addon:ToggleMinimapButton()
		self.options.minimapButton = not self.options.minimapButton
		if self.options.minimapButton then
			KRT_MINIMAP_GUI:Show()
		else
			KRT_MINIMAP_GUI:Hide()
		end
	end

	-- Hide minimap button:
	function addon:HideMinimapButton()
		return KRT_MINIMAP_GUI:Hide()
	end


