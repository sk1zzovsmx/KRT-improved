local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("KRT")
local Utils = addon.Utils
local AceTimer = LibStub("AceTimer-3.0")
AceTimer:Embed(addon)
local AceEvent = LibStub("AceEvent-3.0")
AceEvent:Embed(addon)
addon.timers = addon.timers or {}

-- Load boss ID library
local BossIDLib = LibStub("LibBossIDs-1.0", true)
addon.BossIDs = BossIDLib and BossIDLib.BossIDs or {}

function addon:Schedule(name, delay, func, ...)
    self:Cancel(name)
    self.timers[name] = self:ScheduleTimer(func, delay, ...)
    return self.timers[name]
end

function addon:Cancel(name)
    local handle = self.timers[name]
    if handle then
        self:CancelTimer(handle, true)
        self.timers[name] = nil
    end
end

local _G = _G
_G["KRT"] = addon


-- SavedVariables:
KRT_Debug			= KRT_Debug or {}
KRT_Options	   		= KRT_Options or {}
KRT_Raids		 	= KRT_Raids or {}
KRT_Players	   		= KRT_Players or {}
KRT_Warnings	  	= KRT_Warnings or {}
KRT_ExportString  	= KRT_ExportString or "$I,$N,$S,$W,$T,$R,$H:$M,$d/$m/$y"
KRT_Spammer	   		= KRT_Spammer or {}
KRT_CurrentRaid   	= KRT_CurrentRaid or nil
KRT_LastBoss	  	= KRT_LastBoss or  nil
KRT_NextReset	 	= KRT_NextReset or  0
KRT_SavedReserves 	= KRT_SavedReserves or {}

-- AddOn main frames:
-- mainFrame no longer needed with AceEvent
local UIMaster, UIConfig, UISpammer, UIChanges, UIWarnings
local UILogger, UILoggerItemBox, UIReserve
-- local UILoggerBossBox, UILoggerPlayerBox
local _

local unitName = UnitName("player")

-- Rolls & Loot related locals:
local trader, winner
local holder, banker, disenchanter
local lootOpened      = false
local rollTypes       = {mainspec = 1, offspec = 2, reserved = 3, free = 4, bank = 5, disenchant = 6, hold = 7, dkp = 8}
local currentRollType = 4
local currentRollItem = 0
local fromInventory   = false
local itemInfo        = {}
local lootCount       = 0
local rollsCount      = 0
local itemCount       = 1
local itemTraded      = 0
local ItemExists, ItemIsSoulbound, GetItem
local GetItemIndex, GetItemName, GetItemLink, GetItemTexture
local lootTypesText = {L.BtnMS, L.BtnOS, L.BtnSR, L.BtnFree, L.BtnBank, L.BtnDisenchant, L.BtnHold}
local lootTypesColored = {
	GREEN_FONT_COLOR_CODE..L.BtnMS..FONT_COLOR_CODE_CLOSE,
	LIGHTYELLOW_FONT_COLOR_CODE..L.BtnOS..FONT_COLOR_CODE_CLOSE,
	"|cffa335ee"..L.BtnSR..FONT_COLOR_CODE_CLOSE,
	NORMAL_FONT_COLOR_CODE..L.BtnFree..FONT_COLOR_CODE_CLOSE,
	ORANGE_FONT_COLOR_CODE..L.BtnBank..FONT_COLOR_CODE_CLOSE,
	RED_FONT_COLOR_CODE..L.BtnDisenchant..FONT_COLOR_CODE_CLOSE,
	HIGHLIGHT_FONT_COLOR_CODE..L.BtnHold..FONT_COLOR_CODE_CLOSE,
	GREEN_FONT_COLOR_CODE.."DKP"..FONT_COLOR_CODE_CLOSE,
}
-- Items color
local itemColors = {
		[1] = "ff9d9d9d",  -- poor
		[2] = "ffffffff",  -- common
		[3] = "ff1eff00",  -- uncommon
		[4] = "ff0070dd",  -- rare
		[5] = "ffa335ee",  -- epic
		[6] = "ffff8000",  -- legendary
		[7] = "ffe6cc80",  -- artifact / heirloom
}
-- Classes color:
local classColors = {
	["UNKNOWN"]     = "ffffffff",
	["DEATHKNIGHT"] = "ffc41f3b",
	["DRUID"]       = "ffff7d0a",
	["HUNTER"]      = "ffabd473",
	["MAGE"]        = "ff40c7eb",
	["PALADIN"]     = "fff58cba",
	["PRIEST"]      = "ffffffff",
	["ROGUE"]       = "fffff569",
	["SHAMAN"]      = "ff0070de",
	["WARLOCK"]     = "ff8787ed",
	["WARRIOR"]     = "ffc79c6e",
}

-- Raid Target Icons:
local markers = {"{circle}", "{diamond}", "{triangle}", "{moon}", "{square}", "{cross}", "{skull}"}

-- Make these tables accessible to other modules
addon.rollTypes = rollTypes
addon.itemColors = itemColors
addon.markers = markers

-- Windows Title String:
local titleString = "|cfff58cbaK|r|caaf49141RT|r : %s"

-- Some local functions:
local TriggerEvent
local LoadOptions

-- Cache frequently used globals:
local SendChatMessage = SendChatMessage
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local pcall = pcall
local format, match, find, strlen = string.format, string.match, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber, ucfirst = tostring, tonumber, _G.string.ucfirst
local deformat = LibStub("LibDeformat-3.0")

-- Returns the used frame's name:
function addon:GetFrameName()
	local name
	if UIMaster ~= nil then
		name = UIMaster:GetName()
	end
	return name
end

--Returns debug function
function addon:Debug(level, msg, ...)
    if self.Debugger then
        self.Debugger:Add(level, msg, ...)
    end
end

-- ==================== Callbacks Helpers ==================== --

do
        function addon:RegisterCallback(event, func)
                if not event or type(func) ~= "function" then
                        error(L.StrCbErrUsage)
                end
                addon:RegisterMessage(event, func)
        end

        local function TriggerEvent(event, ...)
                addon:SendMessage(event, ...)
        end
end

-- ==================== Events System ==================== --

do
        function addon:RegisterEvents(...)
                for i = 1, select("#", ...) do
                        addon:RegisterEvent(select(i, ...))
                end
        end

        function addon:UnregisterEvents(...)
                if select("#", ...) == 0 then
                        addon:UnregisterAllEvents()
                else
                        for i = 1, select("#", ...) do
                                addon:UnregisterEvent(select(i, ...))
                        end
                end
        end

        addon:RegisterEvents("ADDON_LOADED")
end

-- ==================== Tooltips ==================== --
do
	local colors = HIGHLIGHT_FONT_COLOR

	-- Show the tooltip:
	local function ShowTooltip(frame)
		addon:Debug("DEBUG", "Showing tooltip for frame: " .. (frame:GetName() or "Unnamed"))
		-- Is the anchor manually set?
		if not frame.tooltip_anchor then
			addon:Debug("DEBUG", "Setting default anchor for tooltip.")
			GameTooltip_SetDefaultAnchor(GameTooltip, frame)
		else
			addon:Debug("DEBUG", "Setting custom anchor for tooltip: " .. frame.tooltip_anchor)
			GameTooltip:SetOwner(frame, frame.tooltip_anchor)
		end

		-- Do we have a title?
		if frame.tooltip_title then
			addon:Debug("DEBUG", "Tooltip title: " .. frame.tooltip_title)
			GameTooltip:SetText(frame.tooltip_title)
		end

		-- Do We have a text?
		if frame.tooltip_text then
			addon:Debug("DEBUG", "Tooltip text: " .. tostring(frame.tooltip_text))
			if type(frame.tooltip_text) == "string" then
				GameTooltip:AddLine(frame.tooltip_text, colors.r, colors.g, colors.b, true)
			elseif type(frame.tooltip_text) == "table" then
				for _, l in ipairs(frame.tooltip_text) do
					addon:Debug("DEBUG", "Adding line to tooltip: " .. tostring(l))
					GameTooltip:AddLine(l, colors.r, colors.g, colors.b, true)
				end
			end
		end

		-- Do we have an item tooltip?
		if frame.tooltip_item then
			addon:Debug("DEBUG", "Setting item tooltip: " .. frame.tooltip_item)
			GameTooltip:SetHyperlink(frame.tooltip_item)
		end

		-- Show the tooltip
		GameTooltip:Show()
		addon:Debug("DEBUG", "Tooltip shown for frame: " .. (frame:GetName() or "Unnamed"))
	end

	-- Hides the tooltip:
	local function HideTooltip()
		addon:Debug("DEBUG", "Hiding tooltip.")
		GameTooltip:Hide()
	end

	-- Sets addon tooltips scripts:
	function addon:SetTooltip(frame, text, anchor, title)
		addon:Debug("DEBUG", "Setting tooltip for frame: " .. (frame:GetName() or "Unnamed"))
		-- No frame no blame...
		if not frame then return end
		-- Prepare the text
		frame.tooltip_text = text and text or frame.tooltip_text
		frame.tooltip_anchor = anchor and anchor or frame.tooltip_anchor
		frame.tooltip_title = title and title or frame.tooltip_title
		-- No title or text? nothing to do...
		if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then
			addon:Debug("DEBUG", "No tooltip content to set.")
			return
		end
		addon:Debug("DEBUG", "Setting tooltip content for frame: " .. (frame:GetName() or "Unnamed"))
		frame:SetScript("OnEnter", ShowTooltip)
		frame:SetScript("OnLeave", HideTooltip)
	end
end

-- ==================== What else to do? ==================== --
--[===[ And here we go... ]===]--

-- On ADDON_LOADED:
function addon:ADDON_LOADED(name)
        if name ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        if addon.Config and addon.Config.LoadOptions then
                addon.Config:LoadOptions()
        end
	self:RegisterEvents(
		"CHAT_MSG_ADDON",
		"CHAT_MSG_SYSTEM",
		"CHAT_MSG_LOOT",
		"CHAT_MSG_MONSTER_YELL",
		"RAID_ROSTER_UPDATE",
		"PLAYER_ENTERING_WORLD",
		"COMBAT_LOG_EVENT_UNFILTERED",
		"RAID_INSTANCE_WELCOME",
		-- Master frame events:
		"ITEM_LOCKED",
		"LOOT_CLOSED",
		"LOOT_OPENED",
		"LOOT_SLOT_CLEARED",
		"TRADE_ACCEPT_UPDATE"
	)
	self:RAID_ROSTER_UPDATE()
end

function addon:RAID_ROSTER_UPDATE()
	if KRT then
		addon:Debug("INFO", "Updating raid member list.")
	end
	self:UpdateRaidRoster()
end

function addon:RAID_INSTANCE_WELCOME(...)
	local instanceName, instanceType, instanceDiff = GetInstanceInfo()
	_, KRT_NextReset = ...
	
	if L.RaidZones[instanceName] ~= nil then
		if KRT then
			addon:Debug("INFO", "Raid '%s' started. Type: %s, Difficulty: %d", instanceName, instanceType, instanceDiff)
		end
                addon:Schedule("raidCheck", 3, function()
                        addon.Raid:Check(instanceName, instanceDiff)
                end)
	else
		if KRT then
			addon:Debug("INFO", "Raid '%s' is not supported for monitoring.", instanceName)
		end
	end
end

function addon:PLAYER_ENTERING_WORLD()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if KRT then
		addon:Debug("INFO", "Player entered the world. Initial raid check scheduled.")
	end
        addon:Schedule("firstCheck", 3, self.Raid.FirstCheck)
end

function addon:CHAT_MSG_LOOT(msg)
	if KRT_CurrentRaid then
		if KRT then
			addon:Debug("INFO", "Loot received: %s", msg)
		end
		self.Raid:AddLoot(msg)
	end
end

function addon:CHAT_MSG_MONSTER_YELL(...)
	local text, boss = ...
	if L.BossYells[text] and KRT_CurrentRaid then
		if KRT then
			addon:Debug("INFO", "Boss yell '%s' detected: %s", boss, text)
		end
		self.Raid:AddBoss(L.BossYells[text])
	end
end

function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
	local _, event, _, _, _, destGUID, destName = ...
	if not KRT_CurrentRaid then return end
	if event == "UNIT_DIED" then
                local npcID = Utils.GetNPCID(destGUID)
                if addon.BossIDs[npcID] then
			if KRT then
				addon:Debug("INFO", "Boss killed: %s", destName)
			end
			self.Raid:AddBoss(destName)
		end
	end
end
