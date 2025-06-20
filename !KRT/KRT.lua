local addonName, addon = ...
local L = addon.L
local Utils = addon.Utils

local _G = _G
_G["KRT"] = addon


-- SavedVariables:
KRT_Debug                               = KRT_Debug or {}
KRT_Options                             = KRT_Options or {}
KRT_Raids                               = KRT_Raids or {}
KRT_Players                             = KRT_Players or {}
KRT_Warnings                            = KRT_Warnings or {}
KRT_ExportString                        = KRT_ExportString or "$I,$N,$S,$W,$T,$R,$H:$M,$d/$m/$y"
KRT_Spammer                             = KRT_Spammer or {}
KRT_CurrentRaid                         = KRT_CurrentRaid or nil
KRT_LastBoss                            = KRT_LastBoss or nil
KRT_NextReset                           = KRT_NextReset or 0
KRT_SavedReserves                       = KRT_SavedReserves or {}

-- AddOn main frames:
local mainFrame                         = CreateFrame("Frame")
local UIMaster, UIConfig, UISpammer, UIChanges, UIWarnings
local UILogger, UILoggerItemBox, UIReserve
-- local UILoggerBossBox, UILoggerPlayerBox
local _

local unitName                          = UnitName("player")

-- Rolls & Loot related locals:
local trader, winner
local holder, banker, disenchanter
local lootOpened                        = false
local rollTypes                         = { mainspec = 1, offspec = 2, reserved = 3, free = 4, bank = 5, disenchant = 6, hold = 7, dkp = 8 }
local currentRollType                   = 4
local currentRollItem                   = 0
local fromInventory                     = false
local itemInfo                          = {}
local lootCount                         = 0
local rollsCount                        = 0
local itemCount                         = 1
local itemTraded                        = 0
local ItemExists, ItemIsSoulbound, GetItem
local GetItemIndex, GetItemName, GetItemLink, GetItemTexture
local lootTypesText                     = { L.BtnMS, L.BtnOS, L.BtnSR, L.BtnFree, L.BtnBank, L.BtnDisenchant, L.BtnHold }
local lootTypesColored                  = {
	GREEN_FONT_COLOR_CODE .. L.BtnMS .. FONT_COLOR_CODE_CLOSE,
	LIGHTYELLOW_FONT_COLOR_CODE .. L.BtnOS .. FONT_COLOR_CODE_CLOSE,
	"|cffa335ee" .. L.BtnSR .. FONT_COLOR_CODE_CLOSE,
	NORMAL_FONT_COLOR_CODE .. L.BtnFree .. FONT_COLOR_CODE_CLOSE,
	ORANGE_FONT_COLOR_CODE .. L.BtnBank .. FONT_COLOR_CODE_CLOSE,
	RED_FONT_COLOR_CODE .. L.BtnDisenchant .. FONT_COLOR_CODE_CLOSE,
	HIGHLIGHT_FONT_COLOR_CODE .. L.BtnHold .. FONT_COLOR_CODE_CLOSE,
	GREEN_FONT_COLOR_CODE .. "DKP" .. FONT_COLOR_CODE_CLOSE,
}
-- Items color
local itemColors                        = {
	[1] = "ff9d9d9d", -- poor
	[2] = "ffffffff", -- common
	[3] = "ff1eff00", -- uncommon
	[4] = "ff0070dd", -- rare
	[5] = "ffa335ee", -- epic
	[6] = "ffff8000", -- legendary
	[7] = "ffe6cc80", -- artifact / heirloom
}
-- Classes color:
local classColors                       = {
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
local markers                           = { "{circle}", "{diamond}", "{triangle}", "{moon}", "{square}", "{cross}",
	"{skull}" }

-- Windows Title String:
local titleString                       = "|cfff58cbaK|r|caaf49141RT|r : %s"

-- Some local functions:
local TriggerEvent

-- Cache frequently used globals:
local SendChatMessage                   = SendChatMessage
local tinsert, tremove, tconcat, twipe  = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local pcall                             = pcall
local format, match, find, strlen       = string.format, string.match, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber, ucfirst       = tostring, tonumber, _G.string.ucfirst
local deformat                          = LibStub("LibDeformat-3.0")
local BossIDs                           = LibStub("LibBossIDs-1.0").BossIDs

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
	-- Table of registered callbacks:
	local callbacks = {}

	-- Register a new callback:
	function addon:RegisterCallback(e, func)
		if not e or type(func) ~= "function" then
			error(L.StrCbErrUsage)
		end
		callbacks[e] = callbacks[e] or {}
		tinsert(callbacks[e], func)
		addon:Debug("DEBUG", "Registered callback for event '%s': %s", tostring(e), tostring(func))
		return #callbacks
	end

	-- Trigger a registered event:
	function TriggerEvent(e, ...)
		if not callbacks[e] then
			addon:Debug("DEBUG", "No callbacks registered for event '%s'", tostring(e))
			return
		end
		addon:Debug("DEBUG", "Triggering event '%s' (%d callbacks)", tostring(e), #callbacks[e])
		for i, v in ipairs(callbacks[e]) do
			local ok, err = pcall(v, e, ...)
			if not ok then
				addon:Debug("ERROR", "Error in callback %s for event '%s': %s", tostring(v), tostring(e), tostring(err))
				addon:PrintError(L.StrCbErrExec:format(tostring(v), tostring(e), err))
			end
		end
	end
end

-- ==================== Events System ==================== --

do
	-- Table of registered events:
	local events = {}

	-- Events Handler:
	local function HandleEvent(self, e, ...)
		addon:Debug("DEBUG", "Handling event: '%s'", e)

		if e == "ADDON_LOADED" then
			LoadOptions()
		end
		if not events[e] then
			addon:Debug("DEBUG", "No frames registered for event '%s'", e)
			return
		end
		for i, v in ipairs(events[e]) do
			if type(v[e]) == "function" then
				addon:Debug("DEBUG", "Dispatching event '%s' to frame %d", e, i)
				v[e](v, ...)
			end
		end
	end

	-- Registers new frame event(s):
	function addon:RegisterEvents(...)
		for i = 1, select("#", ...) do
			local e = select(i, ...)
			events[e] = events[e] or {}
			tinsert(events[e], self)
			mainFrame:RegisterEvent(e)
			addon:Debug("INFO", "Registered event '%s' for frame", e)
		end
	end

	-- Unregister all frame events:
	function addon:UnregisterEvents()
		for e, v in pairs(events) do
			for i = #v, 1, -1 do
				if v[i] == self then
					tremove(v, i)
				end
			end
			if #v == 0 then
				events[e] = nil
				mainFrame:UnregisterEvent(e)
				addon:Debug("INFO", "Unregistered event '%s' from frame", e)
			end
		end
	end

	-- Register some events and frame-related functions:
	addon:RegisterEvents("ADDON_LOADED")
	mainFrame:SetScript("OnEvent", HandleEvent)
	mainFrame:SetScript("OnUpdate", Utils.run)
end

-- ==================== Chat Output Helpers ==================== --
do
	-- Output strings:
	local output          = "|cfff58cba%s|r: %s"
	local chatPrefix      = "Kader Raid Tools"
	local chatPrefixShort = "KRT"

	-- Default function that handles final output:
	local function PreparePrint(text, prefix)
		prefix = prefix or chatPrefixShort
		return format(output, prefix, tostring(text))
	end

	-- Default print function:
	function addon:Print(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "Print: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print(msg)
	end

	-- Print Green Success Message:
	function addon:PrintSuccess(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintSuccess: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_green(msg)
	end

	-- Print Red Error Message:
	function addon:PrintError(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintError: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_red(msg)
	end

	-- Print Orange Warning Message:
	function addon:PrintWarning(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintWarning: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_orange(msg)
	end

	-- Print Blue Info Message:
	function addon:PrintInfo(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintInfo: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_blue(msg)
	end

	-- Function used for various announcements:
	function addon:Announce(text, channel)
		local originalChannel = channel
		if not channel then
			-- Switch to raid channel if we're in a raid:
			if self:IsInRaid() then
				-- Check for countdown messages
				local countdownTicPattern = L.ChatCountdownTic:gsub("%%d", "%%d+")
				local isCountdownMessage = text:find(countdownTicPattern) or text:find(L.ChatCountdownEnd)

				if isCountdownMessage then
					-- If it's a countdown message:
					if addon.options.countdownSimpleRaidMsg then
						channel = "RAID" -- Force RAID if countdownSimpleRaidMsg is true
						-- Use RAID_WARNING if leader/officer AND useRaidWarning is true
					elseif addon.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer()) then
						channel = "RAID_WARNING"
					else
						channel = "RAID" -- Fallback to RAID
					end
				else
					if addon.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer()) then
						channel = "RAID_WARNING"
					else
						channel = "RAID" -- Fallback to RAID
					end
				end

				-- Switch to party mode if we're in a party:
			elseif self:IsInParty() then
				channel = "PARTY"

				-- Switch to alone mode
			else
				channel = "SAY"
			end
		end
		-- Let's Go!
		SendChatMessage(tostring(text), channel)
	end
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

-- ==================== Slash Commands ==================== --

do
	-- Valid subcommands for each feature
	local cmdAchiev   = { "ach", "achi", "achiev", "achievement" }
	local cmdLFM      = { "pug", "lfm", "group", "grouper" }
	local cmdConfig   = { "config", "conf", "options", "opt" }
	local cmdChanges  = { "ms", "changes", "mschanges" }
	local cmdWarnings = { "warning", "warnings", "warn", "rw" }
	local cmdLog      = { "log", "logger", "history" }
	local cmdDebug    = { "debug", "dbg", "debugger" }
	local cmdLoot     = { "loot", "ml", "master" }
	local cmdReserves = { "res", "reserves", "reserve" }

	local helpString  = "|caaf49141%s|r: %s"

	local function HandleSlashCmd(cmd)
		if not cmd or cmd == "" then return end

		if cmd == "show" or cmd == "toggle" then
			addon.Master:Toggle()
			return
		end

		local cmd1, cmd2, cmd3 = strsplit(" ", cmd, 3)

		-- ==== Debugger ====
		if Utils.checkEntry(cmdDebug, cmd1) then
			local subCmd = cmd2 and cmd2:lower()

			local actions = {
				clear  = function() addon.Debugger:Clear() end,
				show   = function() addon.Debugger:Show() end,
				hide   = function() addon.Debugger:Hide() end,
				toggle = function()
					if addon.Debugger:IsShown() then
						addon.Debugger:Hide()
						addon.Debugger:Clear()
					else
						addon.Debugger:Show()
					end
				end,
			}

			if not subCmd or subCmd == "" then
				actions.toggle()
			elseif subCmd == "level" or subCmd == "lvl" then
				if not cmd3 then
					addon.Debugger:Add("INFO", "Current log level: %s", addon.Debugger:GetMinLevel())
				else
					addon.Debugger:SetMinLevel(tonumber(cmd3) or cmd3)
				end
			elseif actions[subCmd] then
				actions[subCmd]()
			else
				addon.Debugger:Add("WARN", "Unknown debug command: %s", subCmd)
			end

			-- ==== Achievement Link ====
		elseif Utils.checkEntry(cmdAchiev, cmd1) and find(cmd, "achievement:%d*:") then
			local from, to = string.find(cmd, "achievement:%d*:")
			local id = string.sub(cmd, from + 11, to - 1)
			from, to = string.find(cmd, "|cffffff00|Hachievement:.*%]|h|r")
			local name = string.sub(cmd, from, to)
			print(helpString:format("KRT", name .. " - ID#" .. id))

			-- ==== Config ====
		elseif Utils.checkEntry(cmdConfig, cmd1) then
			if cmd2 == "reset" then
				addon.Config:Default()
			else
				addon.Config:Toggle()
			end

			-- ==== Warnings ====
		elseif Utils.checkEntry(cmdWarnings, cmd1) then
			if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
				addon.Warnings:Toggle()
			elseif cmd2 == "help" then
				addon:Print(format(L.StrCmdCommands, "krt rw"), "KRT")
				print(helpString:format("toggle", L.StrCmdToggle))
				print(helpString:format("[ID]", L.StrCmdWarningAnnounce))
			else
				addon.Warnings:Announce(tonumber(cmd2))
			end

			-- ==== MS Changes ====
		elseif Utils.checkEntry(cmdChanges, cmd1) then
			if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
				addon.Changes:Toggle()
			elseif cmd2 == "demand" or cmd2 == "ask" then
				addon.Changes:Demand()
			elseif cmd2 == "announce" or cmd2 == "spam" then
				addon.Changes:Announce()
			else
				addon:Print(format(L.StrCmdCommands, "krt ms"), "KRT")
				print(helpString:format("toggle", L.StrCmdToggle))
				print(helpString:format("demand", L.StrCmdChangesDemand))
				print(helpString:format("announce", L.StrCmdChangesAnnounce))
			end

			-- ==== Loot Log ====
		elseif Utils.checkEntry(cmdLog, cmd1) then
			if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
				addon.Logger:Toggle()
			end

			-- ==== Master Looter ====
		elseif Utils.checkEntry(cmdLoot, cmd1) then
			if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
				addon.Master:Toggle()
			end

			-- ==== Reserves ====
		elseif Utils.checkEntry(cmdReserves, cmd1) then
			if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
				addon.Reserves:ShowWindow()
			elseif cmd2 == "import" then
				addon.Reserves:ShowImportBox()
			else
				addon:Print(format(L.StrCmdCommands, "krt res"), "KRT")
				print(helpString:format("toggle", L.StrCmdToggle))
				print(helpString:format("import", L.StrCmdReservesImport))
			end

			-- ==== LFM (Spammer) ====
		elseif Utils.checkEntry(cmdLFM, cmd1) then
			if not cmd2 or cmd2 == "" or cmd2 == "toggle" or cmd2 == "show" then
				addon.Spammer:Toggle()
			elseif cmd2 == "start" then
				addon.Spammer:Start()
			elseif cmd2 == "stop" then
				addon.Spammer:Stop()
			else
				addon:Print(format(L.StrCmdCommands, "krt pug"), "KRT")
				print(helpString:format("toggle", L.StrCmdToggle))
				print(helpString:format("start", L.StrCmdLFMStart))
				print(helpString:format("stop", L.StrCmdLFMStop))
			end

			-- ==== Help fallback ====
		else
			addon:Print(format(L.StrCmdCommands, "krt"), "KRT")
			print(helpString:format("config", L.StrCmdConfig))
			print(helpString:format("lfm", L.StrCmdGrouper))
			print(helpString:format("ach", L.StrCmdAchiev))
			print(helpString:format("changes", L.StrCmdChanges))
			print(helpString:format("warnings", L.StrCmdWarnings))
			print(helpString:format("log", L.StrCmdLog))
			print(helpString:format("reserves", L.StrCmdReserves))
		end
	end

	-- Register slash commands
	SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
	SlashCmdList["KRT"] = HandleSlashCmd
end

-- ==================== What else to do? ==================== --
--[===[ And here we go... ]===] --

-- On ADDON_LOADED:
function addon:ADDON_LOADED(name)
	if name ~= addonName then return end
	mainFrame:UnregisterEvent("ADDON_LOADED")
	LoadOptions()
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
		Utils.schedule(3, function()
			addon.Raid:Check(instanceName, instanceDiff)
		end)
	else
		if KRT then
			addon:Debug("INFO", "Raid '%s' is not supported for monitoring.", instanceName)
		end
	end
end

function addon:PLAYER_ENTERING_WORLD()
	mainFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if KRT then
		addon:Debug("INFO", "Player entered the world. Initial raid check scheduled.")
	end
	Utils.schedule(3, self.Raid.FirstCheck)
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
		if BossIDs[npcID] then
			if KRT then
				addon:Debug("INFO", "Boss killed: %s", destName)
			end
			self.Raid:AddBoss(destName)
		end
	end
end

-- ==================== Debugger ==================== --

addon.Debugger = {}
local Debugger = addon.Debugger

local frameName, frame, scrollFrame
local isDebuggerOpen = false
local buffer = {}

local logLevelPriority = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local logLevelNames    = { [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }
local minLevel         = "DEBUG"
local MAX_DEBUG_LOGS   = 500

function Debugger:OnLoad(self)
    frame = self
    frameName = frame:GetName()
    scrollFrame = _G[frameName .. "ScrollFrame"]
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    if KRT_Debug and KRT_Debug.Pos and KRT_Debug.Pos.point then
        local p = KRT_Debug.Pos
        frame:ClearAllPoints()
        frame:SetPoint(p.point, p.relativeTo or UIParent, p.relativePoint, p.xOfs, p.yOfs)
    end
end

function Debugger:Show()
    if not frame then return end
    frame:Show()

    if not isDebuggerOpen then
        isDebuggerOpen = true
        self:Add("DEBUG", "Debugger window opened.")
        self:AddBufferedMessages()
    end
end

function Debugger:Hide()
    if frame then
        frame:Hide()
        isDebuggerOpen = false
    end
end

function Debugger:Clear()
    if scrollFrame then
        scrollFrame:Clear()
    end
    buffer = {}
end

function Debugger:SetMinLevel(level)
    if type(level) == "number" and logLevelNames[level] then
        minLevel = logLevelNames[level]
        self:Add("INFO", "Log level set to [%s]", minLevel)
    elseif type(level) == "string" then
        level = string.upper(level)
        if logLevelPriority[level] then
            minLevel = level
            self:Add("INFO", "Log level set to [%s]", minLevel)
        else
            self:Add("ERROR", "Invalid log level: %s", level)
        end
    else
        self:Add("ERROR", "Invalid log level type.")
    end
end

function Debugger:GetMinLevel()
    return minLevel
end

function Debugger:Add(level, msg, ...)
    if not msg then
        msg = level
        level = "DEBUG"
    end

    if logLevelPriority[level] < logLevelPriority[minLevel] then return end

    if select("#", ...) > 0 then
        local safeArgs = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            table.insert(safeArgs, type(v) == "string" and v or tostring(v))
        end
        msg = string.format(msg, unpack(safeArgs))
    end
    local line = string.format("[%s][%s] %s", date("%H:%M:%S"), level, msg)

    if not scrollFrame then
        tinsert(buffer, line)
        while #buffer > MAX_DEBUG_LOGS do
            table.remove(buffer, 1)
        end
        return
    end

    local r, g, b = 1, 1, 1
    if level == "ERROR" then
        r, g, b = 1, 0.2, 0.2
    elseif level == "WARN" then
        r, g, b = 1, 0.8, 0
    elseif level == "INFO" then
        r, g, b = 0.6, 0.8, 1
    elseif level == "DEBUG" then
        r, g, b = 0.8, 0.8, 0.8
    end

    scrollFrame:AddMessage(line, r, g, b)

    if KRT_Debug and KRT_Debug.Debugs then
        table.insert(KRT_Debug.Debugs, line)
        while #KRT_Debug.Debugs > MAX_DEBUG_LOGS do
            table.remove(KRT_Debug.Debugs, 1)
        end
    end
end

function Debugger:AddBufferedMessages()
    for _, msg in ipairs(buffer) do
        scrollFrame:AddMessage(msg)
    end
    buffer = {}
end

function Debugger:IsShown()
    return frame and frame:IsShown()
end

-- ==================== Minimap ==================== --

addon.Minimap = {}
local MinimapBtn = addon.Minimap

local addonMenu
local dragMode

local abs, sqrt = math.abs, math.sqrt

local function OpenMenu()
    local info = {}
    addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
    addonMenu.displayMode = "MENU"
    addonMenu.initialize = function(self, level)
        if not level then return end
        wipe(info)
        if level == 1 then
            info.text = MASTER_LOOTER
            info.notCheckable = 1
            info.func = function() addon.Master:Toggle() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.text = RAID_WARNING
            info.notCheckable = 1
            info.func = function() addon.Warnings:Toggle() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.text = L.StrLootHistory
            info.notCheckable = 1
            info.func = function() addon.Logger:Toggle() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.disabled = 1
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.text = L.StrClearIcons
            info.notCheckable = 1
            info.func = function() addon:ClearRaidIcons() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.disabled = 1
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.isTitle = 1
            info.text = L.StrMSChanges
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.notCheckable = 1
            info.text = L.BtnConfigure
            info.notCheckable = 1
            info.func = function() addon.Changes:Toggle() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.text = L.BtnDemand
            info.notCheckable = 1
            info.func = function() addon.Changes:Demand() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.text = CHAT_ANNOUNCE
            info.notCheckable = 1
            info.func = function() addon.Changes:Announce() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.disabled = 1
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
            info.text = L.StrLFMSpam
            info.notCheckable = 1
            info.func = function() addon.Spammer:Toggle() end
            UIDropDownMenu_AddButton(info, level)
            wipe(info)
        end
    end
    ToggleDropDownMenu(1, nil, addonMenu, KRT_MINIMAP_GUI, 0, 0)
end

local function moveButton(self)
    local centerX, centerY = Minimap:GetCenter()
    local x, y = GetCursorPosition()
    x, y = x / self:GetEffectiveScale() - centerX, y / self:GetEffectiveScale() - centerY

    if dragMode == "free" then
        self:ClearAllPoints()
        self:SetPoint("CENTER", x, y)
    else
        centerX, centerY = abs(x), abs(y)
        centerX, centerY = (centerX / sqrt(centerX ^ 2 + centerY ^ 2)) * 80,
                (centerY / sqrt(centerX ^ 2 + centerY ^ 2)) * 80
        centerX = x < 0 and -centerX or centerX
        centerY = y < 0 and -centerY or centerY
        self:ClearAllPoints()
        self:SetPoint("CENTER", centerX, centerY)
    end
end

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
    KRT_MINIMAP_GUI:SetScript("OnClick", function(self, button)
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
    KRT_MINIMAP_GUI:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function addon:ToggleMinimapButton()
    self.options.minimapButton = not self.options.minimapButton
    if self.options.minimapButton then
        KRT_MINIMAP_GUI:Show()
    else
        KRT_MINIMAP_GUI:Hide()
    end
end

function addon:HideMinimapButton()
    return KRT_MINIMAP_GUI:Hide()
end

-- ==================== Config ==================== --

addon.Config = {}
local Config = addon.Config

local frameName
local LocalizeUIFrame
local localized = false
local UpdateUIFrame
local updateInterval = 0.1

local defaultOptions = {
    sortAscending          = false,
    useRaidWarning         = true,
    announceOnWin          = true,
    announceOnHold         = true,
    announceOnBank         = false,
    announceOnDisenchant   = false,
    lootWhispers           = false,
    screenReminder         = true,
    ignoreStacks           = false,
    showTooltips           = true,
    minimapButton          = true,
    countdownSimpleRaidMsg = false,
    countdownDuration      = 5,
    countdownRollsBlock    = true,
}

local function LoadDefaultOptions()
    addon:Debug("DEBUG", "Loading default options")
    for k, v in pairs(defaultOptions) do
        KRT_Options[k] = v
    end
    addon:Debug("DEBUG", "Default options loaded")
end

function LoadOptions()
    addon:Debug("DEBUG", "Loading addon options")
    addon.options = KRT_Options
    Utils.fillTable(addon.options, defaultOptions)

    if not addon.options.useRaidWarning then
        addon.options.countdownSimpleRaidMsg = false
    end
    addon:Debug("DEBUG", "Addon options loaded: %s", tostring(addon.options))
end

function Config:Default()
    addon:Debug("DEBUG", "Resetting to default options")
    return LoadDefaultOptions()
end

function Config:OnLoad(frame)
    if not frame then return end
    addon:Debug("DEBUG", "Config frame loaded: %s", frame:GetName())
    UIConfig = frame
    frameName = frame:GetName()
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnUpdate", UpdateUIFrame)
end

function Config:Toggle()
    addon:Debug("DEBUG", "Toggling config frame visibility")
    Utils.toggle(UIConfig)
end

function Config:Hide()
    if UIConfig and UIConfig:IsShown() then
        addon:Debug("DEBUG", "Hiding config frame")
        UIConfig:Hide()
    end
end

function Config:OnClick(btn)
    if not btn then return end
    frameName = frameName or btn:GetParent():GetName()
    local value, name = nil, btn:GetName()
    addon:Debug("DEBUG", "Button clicked: %s", name)
    if name ~= frameName .. "countdownDuration" then
        value = (btn:GetChecked() == 1) or false
        if name == frameName .. "minimapButton" then
            addon:Debug("DEBUG", "Toggling minimap button")
            addon:ToggleMinimapButton()
        end
    else
        value = btn:GetValue()
        _G[frameName .. "countdownDurationText"]:SetText(value)
        addon:Debug("DEBUG", "Setting countdown duration to: %d", value)
    end
    name = strsub(name, strlen(frameName) + 1)
    TriggerEvent("Config" .. name, value)
    KRT_Options[name] = value
    addon:Debug("DEBUG", "Option %s set to: %s", name, tostring(value))
end

function LocalizeUIFrame()
    if localized then return end
    if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
        _G[frameName .. "sortAscendingStr"]:SetText(L.StrConfigSortAscending)
        _G[frameName .. "useRaidWarningStr"]:SetText(L.StrConfigUseRaidWarning)
        _G[frameName .. "announceOnWinStr"]:SetText(L.StrConfigAnnounceOnWin)
        _G[frameName .. "announceOnHoldStr"]:SetText(L.StrConfigAnnounceOnHold)
        _G[frameName .. "announceOnBankStr"]:SetText(L.StrConfigAnnounceOnBank)
        _G[frameName .. "announceOnDisenchantStr"]:SetText(L.StrConfigAnnounceOnDisenchant)
        _G[frameName .. "lootWhispersStr"]:SetText(L.StrConfigLootWhisper)
        _G[frameName .. "countdownRollsBlockStr"]:SetText(L.StrConfigCountdownRollsBlock)
        _G[frameName .. "screenReminderStr"]:SetText(L.StrConfigScreenReminder)
        _G[frameName .. "ignoreStacksStr"]:SetText(L.StrConfigIgnoreStacks)
        _G[frameName .. "showTooltipsStr"]:SetText(L.StrConfigShowTooltips)
        _G[frameName .. "minimapButtonStr"]:SetText(L.StrConfigMinimapButton)
        _G[frameName .. "countdownDurationStr"]:SetText(L.StrConfigCountdownDuration)
        _G[frameName .. "countdownSimpleRaidMsgStr"]:SetText(L.StrConfigCountdownSimpleRaidMsg)
    end
    _G[frameName .. "Title"]:SetText(format(titleString, SETTINGS))
    _G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
    _G[frameName .. "DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)
    localized = true
end

function UpdateUIFrame(self, elapsed)
    LocalizeUIFrame()
    if Utils.periodic(self, frameName, updateInterval, elapsed) then
        _G[frameName .. "sortAscending"]:SetChecked(addon.options.sortAscending == true)
        _G[frameName .. "useRaidWarning"]:SetChecked(addon.options.useRaidWarning == true)
        _G[frameName .. "announceOnWin"]:SetChecked(addon.options.announceOnWin == true)
        _G[frameName .. "announceOnHold"]:SetChecked(addon.options.announceOnHold == true)
        _G[frameName .. "announceOnBank"]:SetChecked(addon.options.announceOnBank == true)
        _G[frameName .. "announceOnDisenchant"]:SetChecked(addon.options.announceOnDisenchant == true)
        _G[frameName .. "lootWhispers"]:SetChecked(addon.options.lootWhispers == true)
        _G[frameName .. "countdownRollsBlock"]:SetChecked(addon.options.countdownRollsBlock == true)
        _G[frameName .. "screenReminder"]:SetChecked(addon.options.screenReminder == true)
        _G[frameName .. "ignoreStacks"]:SetChecked(addon.options.ignoreStacks == true)
        _G[frameName .. "showTooltips"]:SetChecked(addon.options.showTooltips == true)
        _G[frameName .. "minimapButton"]:SetChecked(addon.options.minimapButton == true)
        _G[frameName .. "countdownDuration"]:SetValue(addon.options.countdownDuration)
        _G[frameName .. "countdownDurationText"]:SetText(addon.options.countdownDuration)

        local useRaidWarningBtn = _G[frameName .. "useRaidWarning"]
        local countdownSimpleRaidMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
        local countdownSimpleRaidMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]

        if useRaidWarningBtn and countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
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

