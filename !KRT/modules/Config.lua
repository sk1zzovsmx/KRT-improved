local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("KRT")
if not addon then return end

-- ==================== Configuration Frame ==================== --

do
	addon.Config = {}
	local Config = addon.Config
	local frameName

	-- Frame localization:
	local LocalizeUIFrame
	local localized = false

	-- Frame update:
	local UpdateUIFrame
	local updateInterval = 0.1

	-- Addon default options:
	local defaultOptions = {
		sortAscending        = false,
		useRaidWarning       = true,
		announceOnWin        = true,
		announceOnHold       = true,
		announceOnBank       = false,
		announceOnDisenchant = false,
		lootWhispers         = false,
		screenReminder       = true,
		ignoreStacks         = false,
		showTooltips         = true,
		minimapButton        = true,
		countdownSimpleRaidMsg = false,
		-- Countdown:
		countdownDuration    = 5,
		countdownRollsBlock  = true,
	}

	-- Load default options:
	local function LoadDefaultOptions()
		addon:Debug("DEBUG", "Loading default options")
		for k, v in pairs(defaultOptions) do
			KRT_Options[k] = v
		end
		addon:Debug("DEBUG", "Default options loaded")
	end

	-- Load addon options:
	function LoadOptions()
		addon:Debug("DEBUG", "Loading addon options")
		addon.options = KRT_Options
		Utils.fillTable(addon.options, defaultOptions)

		if not addon.options.useRaidWarning then
			addon.options.countdownSimpleRaidMsg = false
		end
		addon:Debug("DEBUG", "Addon options loaded: %s", tostring(addon.options))
	end

	-- External reset of default options:
	function Config:Default()
		addon:Debug("DEBUG", "Resetting to default options")
		return LoadDefaultOptions()
	end

	-- OnLoad frame:
	function Config:OnLoad(frame)
		if not frame then return end
		addon:Debug("DEBUG", "Config frame loaded: %s", frame:GetName())
		UIConfig = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Toggle frame visibility:
	function Config:Toggle()
		addon:Debug("DEBUG", "Toggling config frame visibility")
		Utils.toggle(UIConfig)
	end

	-- Hide frame:
	function Config:Hide()
		if UIConfig and UIConfig:IsShown() then
			addon:Debug("DEBUG", "Hiding config frame")
			UIConfig:Hide()
		end
	end

	-- OnClick options:
	function Config:OnClick(btn)
		if not btn then return end
		frameName = frameName or btn:GetParent():GetName()
		local value, name = nil, btn:GetName()
		addon:Debug("DEBUG", "Button clicked: %s", name)		
		if name ~= frameName.."countdownDuration" then
			value = (btn:GetChecked() == 1) or false
			if name == frameName.."minimapButton" then
				addon:Debug("DEBUG", "Toggling minimap button")
				addon:ToggleMinimapButton()
			end
		else
			value = btn:GetValue()
			_G[frameName.."countdownDurationText"]:SetText(value)
			addon:Debug("DEBUG", "Setting countdown duration to: %d", value)
		end
		name = strsub(name, strlen(frameName) + 1)
		TriggerEvent("Config"..name, value)
		KRT_Options[name] = value
		addon:Debug("DEBUG", "Option %s set to: %s", name, tostring(value))
	end

	-- Localizing ui frame:
	function LocalizeUIFrame()
		if localized then 
			addon:Debug("DEBUG", "UI is already localized. Skipping.")
			return 
		end		
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			addon:Debug("DEBUG", "Setting localized UI strings.")
			_G[frameName.."sortAscendingStr"]:SetText(L.StrConfigSortAscending)
			_G[frameName.."useRaidWarningStr"]:SetText(L.StrConfigUseRaidWarning)
			_G[frameName.."announceOnWinStr"]:SetText(L.StrConfigAnnounceOnWin)
			_G[frameName.."announceOnHoldStr"]:SetText(L.StrConfigAnnounceOnHold)
			_G[frameName.."announceOnBankStr"]:SetText(L.StrConfigAnnounceOnBank)
			_G[frameName.."announceOnDisenchantStr"]:SetText(L.StrConfigAnnounceOnDisenchant)
			_G[frameName.."lootWhispersStr"]:SetText(L.StrConfigLootWhisper)
			_G[frameName.."countdownRollsBlockStr"]:SetText(L.StrConfigCountdownRollsBlock)
			_G[frameName.."screenReminderStr"]:SetText(L.StrConfigScreenReminder)
			_G[frameName.."ignoreStacksStr"]:SetText(L.StrConfigIgnoreStacks)
			_G[frameName.."showTooltipsStr"]:SetText(L.StrConfigShowTooltips)
			_G[frameName.."minimapButtonStr"]:SetText(L.StrConfigMinimapButton)
			_G[frameName.."countdownDurationStr"]:SetText(L.StrConfigCountdownDuration)
			_G[frameName.."countdownSimpleRaidMsgStr"]:SetText(L.StrConfigCountdownSimpleRaidMsg)
		end
		_G[frameName.."Title"]:SetText(format(titleString, SETTINGS))
		_G[frameName.."AboutStr"]:SetText(L.StrConfigAbout)
		_G[frameName.."DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)		
		addon:Debug("DEBUG", "UI frame localized.")
		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			_G[frameName.."sortAscending"]:SetChecked(addon.options.sortAscending == true)
			_G[frameName.."useRaidWarning"]:SetChecked(addon.options.useRaidWarning == true)
			_G[frameName.."announceOnWin"]:SetChecked(addon.options.announceOnWin == true)
			_G[frameName.."announceOnHold"]:SetChecked(addon.options.announceOnHold == true)
			_G[frameName.."announceOnBank"]:SetChecked(addon.options.announceOnBank == true)
			_G[frameName.."announceOnDisenchant"]:SetChecked(addon.options.announceOnDisenchant == true)
			_G[frameName.."lootWhispers"]:SetChecked(addon.options.lootWhispers == true)
			_G[frameName.."countdownRollsBlock"]:SetChecked(addon.options.countdownRollsBlock == true)
			_G[frameName.."screenReminder"]:SetChecked(addon.options.screenReminder == true)
			_G[frameName.."ignoreStacks"]:SetChecked(addon.options.ignoreStacks == true)
			_G[frameName.."showTooltips"]:SetChecked(addon.options.showTooltips == true)
			_G[frameName.."minimapButton"]:SetChecked(addon.options.minimapButton == true)
			_G[frameName.."countdownDuration"]:SetValue(addon.options.countdownDuration)
			_G[frameName.."countdownDurationText"]:SetText(addon.options.countdownDuration)
			addon:Debug("DEBUG", "Options updated in UI frame.")

			local useRaidWarningBtn = _G[frameName.."useRaidWarning"]
			local countdownSimpleRaidMsgBtn = _G[frameName.."countdownSimpleRaidMsg"]
			local countdownSimpleRaidMsgStr = _G[frameName.."countdownSimpleRaidMsgStr"]

			if useRaidWarningBtn and countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
				addon:Debug("DEBUG", "Updating Countdown Simple Raid Msg based on Use Raid Warning.")
				if not useRaidWarningBtn:GetChecked() then
					countdownSimpleRaidMsgBtn:SetChecked(addon.options.countdownSimpleRaidMsg)
					countdownSimpleRaidMsgBtn:Disable()
					countdownSimpleRaidMsgStr:SetTextColor(0.5, 0.5, 0.5)
				else
					countdownSimpleRaidMsgBtn:Enable()
					countdownSimpleRaidMsgStr:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
					countdownSimpleRaidMsgBtn:SetChecked(addon.options.countdownSimpleRaidMsg)
				end
			end
		end
	end
end

