--[[
	KRT.lua
	Core logic file for the Kader Raid Tools addon.
]]

-- ============================================================================
-- Addon Namespace & Initialization
-- ============================================================================

local addonName, addon = ...
local L = addon.L
local Utils = addon.Utils

local _G = _G
_G["KRT"] = addon

-- ============================================================================
-- Saved Variables
-- ============================================================================

KRT_Debug = KRT_Debug or {}
KRT_Options = KRT_Options or {}
KRT_Raids = KRT_Raids or {}
KRT_Players = KRT_Players or {}
KRT_Warnings = KRT_Warnings or {}
KRT_ExportString = KRT_ExportString or "$I,$N,$S,$W,$T,$R,$H:$M,$d/$m/$y"
KRT_Spammer = KRT_Spammer or {}
KRT_CurrentRaid = KRT_CurrentRaid or nil
KRT_LastBoss = KRT_LastBoss or nil
KRT_NextReset = KRT_NextReset or 0
KRT_SavedReserves = KRT_SavedReserves or {}
KRT_PlayerCounts = KRT_PlayerCounts or {}

-- ============================================================================
-- Local Variables & Cached Functions
-- ============================================================================

-- Addon main frames
local mainFrame = CreateFrame("Frame")
local masterFrame, configFrame, spammerFrame, changesFrame, warningsFrame, loggerFrame

-- Player Info
local unitName = UnitName("player")

-- Rolls & Loot
local winner
local holder, banker, disenchanter
local lootOpened = false
local rollTypes = { mainspec = 1, offspec = 2, reserved = 3, free = 4, bank = 5, disenchant = 6, hold = 7, dkp = 8 }
local currentRollType = 4
local currentRollItem = 0
fromInventory = false -- Note: Used globally across modules, cannot be fully localized without logic change.
local itemInfo = {}
local lootCount = 0
local rollsCount = 0
local itemCount = 1
local lootTypesText = { L.BtnMS, L.BtnOS, L.BtnSR, L.BtnFree, L.BtnBank, L.BtnDisenchant, L.BtnHold }
local lootTypesColored = {
	GREEN_FONT_COLOR_CODE .. L.BtnMS .. FONT_COLOR_CODE_CLOSE,
	LIGHTYELLOW_FONT_COLOR_CODE .. L.BtnOS .. FONT_COLOR_CODE_CLOSE,
	"|cffa335ee" .. L.BtnSR .. FONT_COLOR_CODE_CLOSE,
	NORMAL_FONT_COLOR_CODE .. L.BtnFree .. FONT_COLOR_CODE_CLOSE,
	ORANGE_FONT_COLOR_CODE .. L.BtnBank .. FONT_COLOR_CODE_CLOSE,
	RED_FONT_COLOR_CODE .. L.BtnDisenchant .. FONT_COLOR_CODE_CLOSE,
	HIGHLIGHT_FONT_COLOR_CODE .. L.BtnHold .. FONT_COLOR_CODE_CLOSE,
	GREEN_FONT_COLOR_CODE .. "DKP" .. FONT_COLOR_CODE_CLOSE,
}
-- Item rarity colors
local itemColors = {
	[1] = "ff9d9d9d", -- Poor
	[2] = "ffffffff", -- Common
	[3] = "ff1eff00", -- Uncommon
	[4] = "ff0070dd", -- Rare
	[5] = "ffa335ee", -- Epic
	[6] = "ffff8000", -- Legendary
	[7] = "ffe6cc80", -- Artifact / Heirloom
}
-- Class colors
local classColors = {
	["UNKNOWN"] = "ffffffff",
	["DEATHKNIGHT"] = "ffc41f3b",
	["DRUID"] = "ffff7d0a",
	["HUNTER"] = "ffabd473",
	["MAGE"] = "ff40c7eb",
	["PALADIN"] = "fff58cba",
	["PRIEST"] = "ffffffff",
	["ROGUE"] = "fffff569",
	["SHAMAN"] = "ff0070de",
	["WARLOCK"] = "ff8787ed",
	["WARRIOR"] = "ffc79c6e",
}

-- Raid Target Icons
local markers = { "{circle}", "{diamond}", "{triangle}", "{moon}", "{square}", "{cross}", "{skull}" }

-- Windows Title String
local titleString = "|cfff58cbaK|r|caaf49141RT|r : %s"

-- Forward declarations
local TriggerEvent
local LoadOptions

-- Cached Globals
local SendChatMessage = SendChatMessage
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local format, match, find, strlen = string.format, string.match, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber, ucfirst = tostring, tonumber, _G.string.ucfirst
local deformat = LibStub("LibDeformat-3.0")
local BossIDs = LibStub("LibBossIDs-1.0")

-- ============================================================================
-- Core Functions
-- ============================================================================

-- Returns the Master Looter frame's name if it's loaded.
function addon:GetFrameName()
	if masterFrame then
		return masterFrame:GetName()
	end
	return nil
end

-- Logs a message to the internal debugger.
function addon:Debug(level, msg, ...)
	if self.Debugger then
		self.Debugger:Add(level, msg, ...)
	end
end

-- ============================================================================
-- Debugger Module
-- ============================================================================
do
	addon.Debugger = {}
	local Debugger = addon.Debugger

	local frame, scrollFrame
	local isDebuggerOpen = false
	local buffer = {} -- Holds messages if the frame isn't ready

	local logLevelPriority = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
	local logLevelNames = { [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }
	local minLevel = "DEBUG" -- Default log level
	local MAX_DEBUG_LOGS = 500

	-- Called when the debugger frame is loaded.
	function Debugger:OnLoad(self)
		frame = self
		scrollFrame = _G[self:GetName() .. "ScrollFrame"]
		self:SetMovable(true)
		self:EnableMouse(true)
		self:RegisterForDrag("LeftButton")
		self:SetScript("OnDragStart", self.StartMoving)
		self:SetScript("OnDragStop", self.StopMovingOrSizing)

		-- Restore saved position if available
		if KRT_Debug and KRT_Debug.Pos and KRT_Debug.Pos.point then
			local p = KRT_Debug.Pos
			self:ClearAllPoints()
			self:SetPoint(p.point, p.relativeTo or UIParent, p.relativePoint, p.xOfs, p.yOfs)
		end
	end

	-- Shows the debugger window.
	function Debugger:Show()
		if not frame then return end
		frame:Show()

		if not isDebuggerOpen then
			isDebuggerOpen = true
			self:Add("DEBUG", "Debugger window opened.")
			self:AddBufferedMessages()
		end
	end

	-- Hides the debugger window.
	function Debugger:Hide()
		if frame then
			frame:Hide()
			isDebuggerOpen = false
		end
	end

	-- Clears the debug output.
	function Debugger:Clear()
		if scrollFrame then
			scrollFrame:Clear()
		end
		twipe(buffer)
	end

	-- Sets the minimum log level to display.
	function Debugger:SetMinLevel(level)
		if type(level) == "number" and logLevelNames[level] then
			minLevel = logLevelNames[level]
			self:Add("INFO", "Log level set to [%s]", minLevel)
		elseif type(level) == "string" then
			level = upper(level)
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

	-- Gets the current minimum log level.
	function Debugger:GetMinLevel()
		return minLevel
	end

	-- Adds a message to the log.
	function Debugger:Add(level, msg, ...)
		-- Allow calls like Add("message") without a level
		if not msg then
			msg = level
			level = "DEBUG"
		end

		if logLevelPriority[level] < logLevelPriority[minLevel] then return end

		if select('#', ...) > 0 then
			local safeArgs = {}
			for i = 1, select('#', ...) do
				local v = select(i, ...)
				tinsert(safeArgs, type(v) == "string" and v or tostring(v))
			end
			msg = format(msg, unpack(safeArgs))
		end
		local line = format("[%s][%s] %s", date("%H:%M:%S"), level, msg)

		-- If the window isn't ready, buffer the message
		if not scrollFrame then
			tinsert(buffer, line)
			-- Limit the buffer size
			while #buffer > MAX_DEBUG_LOGS do
				tremove(buffer, 1)
			end
			return
		end

		-- Set color based on level
		local r, g, b = 1, 1, 1 -- Default white
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

		-- Truncate persistent log table
		if KRT_Debug and KRT_Debug.Debugs then
			tinsert(KRT_Debug.Debugs, line)
			while #KRT_Debug.Debugs > MAX_DEBUG_LOGS do
				tremove(KRT_Debug.Debugs, 1)
			end
		end
	end

	-- Displays any buffered messages once the frame is ready.
	function Debugger:AddBufferedMessages()
		for _, msg in ipairs(buffer) do
			scrollFrame:AddMessage(msg)
		end
		twipe(buffer)
	end

	-- Returns true if the debugger window is visible.
	function Debugger:IsShown()
		return frame and frame:IsShown()
	end
end

-- ============================================================================
-- Callback System
-- ============================================================================
do
	local callbacks = {}

	-- Registers a new callback function for a given event.
	function addon:RegisterCallback(event, func)
		if not event or type(func) ~= "function" then
			error(L.StrCbErrUsage)
		end
		callbacks[event] = callbacks[event] or {}
		tinsert(callbacks[event], func)
		return #callbacks
	end

	-- Triggers a registered event, calling all associated callbacks.
	function TriggerEvent(event, ...)
		if not callbacks[event] then return end
		for i, v in ipairs(callbacks[event]) do
			local ok, err = pcall(v, event, ...)
			if not ok then
				addon:PrintError(L.StrCbErrExec:format(tostring(v), tostring(event), err))
			end
		end
	end
end

-- ============================================================================
-- Event Handling System
-- ============================================================================
do
	local events = {}

	-- Main event handler for the addon.
	local function HandleEvent(self, event, ...)
		if event == "ADDON_LOADED" then
			LoadOptions()
		end

		if not events[event] then return end

		for i, v in ipairs(events[event]) do
			if type(v[event]) == "function" then
				v[event](v, ...)
			end
		end
	end

	-- Registers a frame to listen for one or more WoW API events.
	function addon:RegisterEvents(...)
		for i = 1, select("#", ...) do
			local event = select(i, ...)
			events[event] = events[event] or {}
			tinsert(events[event], self)
			mainFrame:RegisterEvent(event)
		end
	end

	-- Unregisters all events for the calling frame.
	function addon:UnregisterEvents()
		for event, registeredFrames in pairs(events) do
			for i = #registeredFrames, 1, -1 do
				if registeredFrames[i] == self then
					tremove(registeredFrames, i)
				end
			end
			if #registeredFrames == 0 then
				events[event] = nil
				mainFrame:UnregisterEvent(event)
			end
		end
	end

	-- Initial event registration and frame setup
	addon:RegisterEvents("ADDON_LOADED")
	mainFrame:SetScript("OnEvent", HandleEvent)
	mainFrame:SetScript("OnUpdate", Utils.run)
end

-- ============================================================================
-- Raid Helpers & Logger
-- ============================================================================
do
	addon.Raid = {}
	local Raid = addon.Raid
	local inRaid = false
	local numRaid = 0

	-- Cached Globals
	local GetLootMethod = GetLootMethod
	local GetNumPartyMembers = GetNumPartyMembers
	local GetNumRaidMembers = GetNumRaidMembers
	local GetRaidRosterInfo = GetRaidRosterInfo

	-- Updates the raid roster, marking players who have left.
	function addon:UpdateRaidRoster()
		if not KRT_CurrentRaid then return end

		numRaid = GetNumRaidMembers()
		if numRaid == 0 then
			Raid:End()
			return
		end

		local realm = GetRealmName() or UNKNOWN
		KRT_Players[realm] = KRT_Players[realm] or {}
		local currentPlayers = {}

		for i = 1, numRaid do
			local name, rank, subgroup, level, classL, class, _, online = GetRaidRosterInfo(i)
			if name then
				tinsert(currentPlayers, name)
				inRaid = false
				for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
					if v.name == name and v.leave == nil then
						inRaid = true
						break
					end
				end

				local unitID = "raid" .. tostring(i)
				local raceL, race = UnitRace(unitID)
				if not inRaid then
					local toRaid = {
						name = name,
						rank = rank,
						subgroup = subgroup,
						class = class or "UNKNOWN",
						join = Utils.GetCurrentTime(),
						leave = nil,
						count = 0,
					}
					Raid:AddPlayer(toRaid)
				end
				if not KRT_Players[realm][name] then
					KRT_Players[realm][name] = {
						name = name,
						level = level,
						race = race,
						raceL = raceL,
						class = class or "UNKNOWN",
						classL = classL,
						sex = UnitSex(unitID)
					}
				end
			end
		end
		-- Mark players who have left
		for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
			local found = false
			for _, p in ipairs(currentPlayers) do
				if v.name == p then
					found = true
					break
				end
			end
			if not found and v.leave == nil then
				v.leave = Utils.GetCurrentTime()
			end
		end
		Utils.unschedule(addon.UpdateRaidRoster)
	end

	-- Creates a new raid log entry.
	function Raid:Create(zoneName, raidSize)
		if KRT_CurrentRaid then
			self:End()
		end

		numRaid = GetNumRaidMembers()
		if numRaid == 0 then return end

		local realm = GetRealmName() or UNKNOWN
		KRT_Players[realm] = KRT_Players[realm] or {}
		local currentTime = Utils.GetCurrentTime()
		local raidInfo = {
			realm = realm,
			zone = zoneName,
			size = raidSize,
			players = {},
			bossKills = {},
			loot = {},
			startTime = currentTime,
			changes = {},
		}

		for i = 1, numRaid do
			local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
			if name then
				local unitID = "raid" .. tostring(i)
				local raceL, race = UnitRace(unitID)
				tinsert(raidInfo.players, {
					name = name,
					rank = rank,
					subgroup = subgroup,
					class = class or "UNKNOWN",
					join = Utils.GetCurrentTime(),
					leave = nil,
					count = 0,
				})
				KRT_Players[realm][name] = {
					name = name,
					level = level,
					race = race,
					raceL = raceL,
					class = class or "UNKNOWN",
					classL = classL,
					sex = UnitSex(unitID),
				}
			end
		end

		tinsert(KRT_Raids, raidInfo)
		KRT_CurrentRaid = #KRT_Raids
		TriggerEvent("RaidCreate", KRT_CurrentRaid)
		Utils.schedule(3, addon.UpdateRaidRoster)
	end

	-- Ends the current raid entry, setting end times.
	function Raid:End()
		if not KRT_CurrentRaid then return end
		Utils.unschedule(addon.Raid.UpdateRaidRoster)

		local currentTime = Utils.GetCurrentTime()
		for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
			if not v.leave then v.leave = currentTime end
		end
		KRT_Raids[KRT_CurrentRaid].endTime = currentTime
		KRT_CurrentRaid = nil
		KRT_LastBoss = nil
	end

	-- Checks raid status and creates a new session if necessary.
	function Raid:Check(instanceName, instanceDiff)
		if not KRT_CurrentRaid then
			Raid:Create(instanceName, (instanceDiff % 2 == 0 and 25 or 10))
			return
		end

		local current = KRT_Raids[KRT_CurrentRaid]
		if current then
			if current.zone == instanceName then
				if current.size == 10 and (instanceDiff % 2 == 0) then
					addon:Print(L.StrNewRaidSessionChange)
					Raid:Create(instanceName, 25)
				elseif current.size == 25 and (instanceDiff % 2 ~= 0) then
					addon:Print(L.StrNewRaidSessionChange)
					Raid:Create(instanceName, 10)
				end
			end
		elseif (instanceDiff % 2 == 0) then
			addon:Print(L.StrNewRaidSessionChange)
			Raid:Create(instanceName, 25)
		elseif (instanceDiff % 2 ~= 0) then
			addon:Print(L.StrNewRaidSessionChange)
			Raid:Create(instanceName, 10)
		end
	end

	-- Checks the raid status upon player's login or reload.
	function Raid:FirstCheck()
		Utils.unschedule(addon.Raid.FirstCheck)
		if GetNumRaidMembers() == 0 then return end

		if KRT_CurrentRaid and Raid:CheckPlayer(unitName, KRT_CurrentRaid) then
			Utils.schedule(2, addon.UpdateRaidRoster)
			return
		end

		local instanceName, instanceType, instanceDiff = GetInstanceInfo()
		if instanceType == "raid" then
			Raid:Check(instanceName, instanceDiff)
		end
	end

	-- Adds or updates a player in the raid log.
	function Raid:AddPlayer(t, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		if not raidNum or not t or not t.name then return end
		local players = Raid:GetPlayers(raidNum)
		local found = false
		for i, p in ipairs(players) do
			if t.name == p.name then
				t.count = t.count or p.count or 0 -- Preserve count if present
				KRT_Raids[raidNum].players[i] = t
				found = true
				break
			end
		end
		if not found then
			t.count = t.count or 0
			tinsert(KRT_Raids[raidNum].players, t)
		end
	end

	-- Adds a boss kill to the active raid log.
	function Raid:AddBoss(bossName, manDiff, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		if not raidNum or not bossName then return end

		local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
		if manDiff then
			instanceDiff = (KRT_Raids[raidNum].size == 10) and 1 or 2
			if lower(manDiff) == "h" then instanceDiff = instanceDiff + 2 end
		elseif isDyn then
			instanceDiff = instanceDiff + (2 * dynDiff)
		end

		local onlinePlayers = {}
		for i = 1, GetNumRaidMembers() do
			local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
			if online == 1 then
				tinsert(onlinePlayers, name)
			end
		end

		local currentTime = Utils.GetCurrentTime()
		local killInfo = {
			name = bossName,
			difficulty = instanceDiff,
			players = onlinePlayers,
			date = currentTime,
			hash = Utils.encode(raidNum .. "|" .. bossName .. "|" .. (KRT_LastBoss or "0"))
		}
		tinsert(KRT_Raids[raidNum].bossKills, killInfo)
		KRT_LastBoss = #KRT_Raids[raidNum].bossKills
	end

	-- Adds a looted item to the active raid log.
	function Raid:AddLoot(msg, rollType, rollValue)
		-- Handle Master Loot messages
		local player, itemLink, itemCount = deformat(msg, LOOT_ITEM_MULTIPLE)
		if not player then
			itemCount = 1
			player, itemLink = deformat(msg, LOOT_ITEM)
		end
		if not player then
			player = unitName
			itemLink, itemCount = deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
		end
		if not itemLink then
			itemCount = 1
			itemLink = deformat(msg, LOOT_ITEM_SELF)
		end
		-- Handle Roll Won messages
		if not player or not itemLink then
			itemCount = 1
			player, itemLink = deformat(msg, LOOT_ROLL_YOU_WON)
			if not itemLink then
				player = unitName
				itemLink = deformat(msg, LOOT_ROLL_YOU_WON)
			end
		end

		if not itemLink then return end
		local _, _, itemString = find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
		local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
		local _, _, _, _, itemId = find(itemLink, "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
		itemId = tonumber(itemId)

		-- We don't proceed if lower than threshold or ignored
		local lootThreshold = GetLootThreshold()
		if itemRarity and itemRarity < lootThreshold then return end
		if itemId and addon.ignoredItems[itemId] then return end

		if not KRT_LastBoss then self:AddBoss("_TrashMob_") end

		if not rollType then rollType = currentRollType end
		if not rollValue then rollValue = addon:HighestRoll() end

		local lootInfo = {
			itemId = itemId,
			itemName = itemName,
			itemString = itemString,
			itemLink = itemLink,
			itemRarity = itemRarity,
			itemTexture = itemTexture,
			itemCount = itemCount,
			looter = player,
			rollType = rollType,
			rollValue = rollValue,
			bossNum = KRT_LastBoss,
			time = Utils.GetCurrentTime(),
		}
		tinsert(KRT_Raids[KRT_CurrentRaid].loot, lootInfo)
	end

	-- Player Loot Count API
	function Raid:GetPlayerCount(name, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		local players = Raid:GetPlayers(raidNum)
		for _, p in ipairs(players) do
			if p.name == name then
				return p.count or 0
			end
		end
		return 0
	end

	function Raid:SetPlayerCount(name, value, raidNum)
		raidNum = raidNum or KRT_CurrentRaid

		if value < 0 then
			addon:PrintError(L.ErrPlayerCountBelowZero:format(name))
			return
		end

		local players = KRT_Raids[raidNum] and KRT_Raids[raidNum].players
		if not players then return end
		for i, p in ipairs(players) do
			if p.name == name then
				p.count = value
				return
			end
		end
	end

	function Raid:IncrementPlayerCount(name, raidNum)
		if Raid:GetPlayerID(name, raidNum) == 0 then
			addon:PrintError(L.ErrCannotFindPlayer:format(name))
			return
		end
		local c = Raid:GetPlayerCount(name, raidNum)
		Raid:SetPlayerCount(name, c + 1, raidNum)
	end

	function Raid:DecrementPlayerCount(name, raidNum)
		if Raid:GetPlayerID(name, raidNum) == 0 then
			addon:PrintError(L.ErrCannotFindPlayer:format(name))
			return
		end
		local c = Raid:GetPlayerCount(name, raidNum)
		if c <= 0 then
			addon:PrintError(L.ErrPlayerCountBelowZero:format(name))
			return
		end
		Raid:SetPlayerCount(name, c - 1, raidNum)
	end

	-- Public Raid Functions
	function addon:GetNumRaid()
		return numRaid
	end

	function addon:GetRaidSize()
		if self:IsInRaid() then
			local diff = GetRaidDifficulty()
			return (diff == 1 or diff == 3) and 10 or 25
		end
		return 0
	end

	do
		local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
		function addon:GetClassColor(name)
			name = (name == "DEATH KNIGHT") and "DEATHKNIGHT" or name
			if not colors[name] then
				return 1, 1, 1
			end
			local c = colors[name]
			return c.r, c.g, c.b
		end
	end

	function Raid:Expired(rID)
		rID = rID or KRT_CurrentRaid
		if not rID or not KRT_Raids[rID] then
			return true
		end
		local currentTime = Utils.GetCurrentTime()
		local startTime = KRT_Raids[rID].startTime
		local validDuration = (currentTime + KRT_NextReset) - startTime
		return validDuration >= 604800 -- 7 days in seconds
	end

	function Raid:GetLoot(raidNum, bossNum)
		local items = {}
		raidNum = raidNum or KRT_CurrentRaid
		bossNum = bossNum or 0
		if not raidNum or not KRT_Raids[raidNum] then return items end

		local loot = KRT_Raids[raidNum].loot
		if tonumber(bossNum) <= 0 then
			for k, v in ipairs(loot) do
				local info = v
				info.id = k
				tinsert(items, info)
			end
		elseif KRT_Raids[raidNum].bossKills[bossNum] then
			for k, v in ipairs(loot) do
				if v.bossNum == bossNum then
					local info = v
					info.id = k
					tinsert(items, info)
				end
			end
		end
		return items
	end

	function Raid:GetLootID(itemID, raidNum, holderName)
		local pos = 0
		local loot = self:GetLoot(raidNum)
		holderName = holderName or unitName
		itemID = tonumber(itemID)
		for k, v in ipairs(loot) do
			if v.itemId == itemID and v.looter == holderName then
				pos = k
				break
			end
		end
		return pos
	end

	function Raid:GetBosses(raidNum)
		local bosses = {}
		raidNum = raidNum or KRT_CurrentRaid
		if raidNum and KRT_Raids[raidNum] then
			local kills = KRT_Raids[raidNum].bossKills
			for i, b in ipairs(kills) do
				local info = {
					id = i,
					difficulty = b.difficulty,
					time = b.date,
					hash = b.hash or "0",
				}
				if b.name == "_TrashMob_" then
					info.name = L.StrTrashMob
					info.mode = ""
				else
					info.name = b.name
					info.mode = (b.difficulty == 3 or b.difficulty == 4) and PLAYER_DIFFICULTY2 or PLAYER_DIFFICULTY1
				end
				tinsert(bosses, info)
			end
		end
		return bosses
	end

	-- Public Player Functions
	function Raid:GetPlayers(raidNum, bossNum)
		raidNum = raidNum or KRT_CurrentRaid
		local players = {}
		if raidNum and KRT_Raids[raidNum] then
			for k, v in ipairs(KRT_Raids[raidNum].players) do
				local info = v
				v.id = k
				tinsert(players, info)
			end
			if bossNum and KRT_Raids[raidNum].bossKills[bossNum] then
				local bossPlayers = {}
				for _, p in ipairs(players) do
					if Utils.checkEntry(KRT_Raids[raidNum].bossKills[bossNum].players, p.name) then
						tinsert(bossPlayers, p)
					end
				end
				return bossPlayers
			end
		end
		return players
	end

	function Raid:CheckPlayer(name, raidNum)
		local players = Raid:GetPlayers(raidNum)
		if not players then return false, name end

		local cleanName = ucfirst(name:trim())
		for _, p in ipairs(players) do
			if cleanName == p.name then
				return true, p.name
			elseif strlen(cleanName) >= 5 and p.name:startsWith(cleanName) then
				return true, p.name
			end
		end
		return false, name
	end

	function Raid:GetPlayerID(name, raidNum)
		local id = 0
		raidNum = raidNum or KRT_CurrentRaid
		if raidNum and KRT_Raids[raidNum] then
			name = name or unitName
			local players = KRT_Raids[raidNum].players
			for i, p in ipairs(players) do
				if p.name == name then
					id = i
					break
				end
			end
		end
		return id
	end

	function Raid:GetPlayerName(id, raidNum)
		raidNum = raidNum or addon.Logger.selectedRaid or KRT_CurrentRaid
		if raidNum and KRT_Raids[raidNum] then
			for k, p in ipairs(KRT_Raids[raidNum].players) do
				if k == id then
					return p.name
				end
			end
		end
		return nil
	end

	function Raid:GetPlayerLoot(name, raidNum, bossNum)
		local items = {}
		local loot = Raid:GetLoot(raidNum, bossNum)
		local resolvedName = (type(name) == "number") and Raid:GetPlayerName(name) or name
		for k, v in ipairs(loot) do
			if v.looter == resolvedName then
				local info = v
				info.id = k
				tinsert(items, info)
			end
		end
		return items
	end

	function addon:GetPlayerRank(name, raidNum)
		local players = Raid:GetPlayers(raidNum)
		local rank = 0
		name = name or unitName or UnitName("player")
		if not next(players) then
			if GetNumRaidMembers() > 0 then
				numRaid = GetNumRaidMembers()
				for i = 1, numRaid do
					local pname, prank = GetRaidRosterInfo(i)
					if pname == name then
						rank = prank
						break
					end
				end
			end
		else
			for _, p in ipairs(players) do
				if p.name == name then
					rank = p.rank or 0
					break
				end
			end
		end
		return rank
	end

	function addon:GetPlayerClass(name)
		local realm = GetRealmName() or UNKNOWN
		local resolvedName = name or unitName
		if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
			return KRT_Players[realm][resolvedName].class or "UNKNOWN"
		end
		return "UNKNOWN"
	end

	function addon:GetUnitID(name)
		local players = Raid:GetPlayers()
		if players then
			for i, p in ipairs(players) do
				if p.name == name then
					return "raid" .. tostring(i)
				end
			end
		end
		return "none"
	end

	-- Status Checks
	function addon:IsInParty()
		return (GetNumPartyMembers() > 0) and (GetNumRaidMembers() == 0)
	end

	function addon:IsInRaid()
		return (inRaid == true or GetNumRaidMembers() > 0)
	end

	function addon:IsMasterLoot()
		local method = select(1, GetLootMethod())
		return (method == "master")
	end

	function addon:IsMasterLooter()
		local _, partyID = GetLootMethod()
		return (partyID and partyID == 0)
	end

	function addon:ClearRaidIcons()
		local players = Raid:GetPlayers()
		for i, _ in ipairs(players) do
			SetRaidTarget("raid" .. tostring(i), 0)
		end
	end
end

-- ============================================================================
-- Chat Output Helpers
-- ============================================================================
do
	local outputFormat = "|cfff58cba%s|r: %s"
	local chatPrefix = "Kader Raid Tools"
	local chatPrefixShort = "KRT"

	-- Prepares a formatted string for printing.
	local function PreparePrint(text, prefix)
		prefix = prefix or chatPrefixShort
		return format(outputFormat, prefix, tostring(text))
	end

	function addon:Print(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print(msg)
	end

	function addon:PrintSuccess(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_green(msg)
	end

	function addon:PrintError(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_red(msg)
	end

	function addon:PrintWarning(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_orange(msg)
	end

	function addon:PrintInfo(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_blue(msg)
	end

	-- Announces a message to the appropriate channel.
	function addon:Announce(text, channel)
		if not channel then
			if self:IsInRaid() then
				local isCountdown = text:find(L.ChatCountdownTic:gsub("%%d", "%%d+")) or text:find(L.ChatCountdownEnd)
				local useRaidWarning = self.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer())

				if isCountdown then
					if self.options.countdownSimpleRaidMsg or not useRaidWarning then
						channel = "RAID"
					else
						channel = "RAID_WARNING"
					end
				else
					if useRaidWarning then
						channel = "RAID_WARNING"
					else
						channel = "RAID"
					end
				end
			elseif self:IsInParty() then
				channel = "PARTY"
			else
				channel = "SAY"
			end
		end
		SendChatMessage(tostring(text), channel)
	end
end

-- ============================================================================
-- Minimap Button
-- ============================================================================
do
	addon.Minimap = {}
	local MinimapBtn = addon.Minimap
	local addonMenu, dragMode
	local abs, sqrt = math.abs, math.sqrt

	-- Initializes and displays the minimap button's right-click menu.
	local function OpenMenu()
		addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
		addonMenu.displayMode = "MENU"
		addonMenu.initialize = function(self, level)
			if level ~= 1 then return end
			local info = {}

			-- Menu items
			info = { text = MASTER_LOOTER, notCheckable = 1, func = function() addon.Master:Toggle() end }
			UIDropDownMenu_AddButton(info)
			info = { text = RAID_WARNING, notCheckable = 1, func = function() addon.Warnings:Toggle() end }
			UIDropDownMenu_AddButton(info)
			info = { text = L.StrLootHistory, notCheckable = 1, func = function() addon.Logger:Toggle() end }
			UIDropDownMenu_AddButton(info)

			-- Separator
			info = { disabled = 1, notCheckable = 1 }
			UIDropDownMenu_AddButton(info)

			info = { text = L.StrClearIcons, notCheckable = 1, func = function() addon:ClearRaidIcons() end }
			UIDropDownMenu_AddButton(info)

			-- Separator
			info = { disabled = 1, notCheckable = 1 }
			UIDropDownMenu_AddButton(info)

			-- MS Changes Sub-Menu
			info = { isTitle = 1, text = L.StrMSChanges, notCheckable = 1 }
			UIDropDownMenu_AddButton(info)
			info = { text = L.BtnConfigure, notCheckable = 1, func = function() addon.Changes:Toggle() end }
			UIDropDownMenu_AddButton(info)
			info = { text = L.BtnDemand, notCheckable = 1, func = function() addon.Changes:Demand() end }
			UIDropDownMenu_AddButton(info)
			info = { text = CHAT_ANNOUNCE, notCheckable = 1, func = function() addon.Changes:Announce() end }
			UIDropDownMenu_AddButton(info)

			-- Separator
			info = { disabled = 1, notCheckable = 1 }
			UIDropDownMenu_AddButton(info)

			info = { text = L.StrLFMSpam, notCheckable = 1, func = function() addon.Spammer:Toggle() end }
			UIDropDownMenu_AddButton(info)
		end
		ToggleDropDownMenu(1, nil, addonMenu, KRT_MINIMAP_GUI, 0, 0)
	end

	-- Handles moving the minimap button.
	local function moveButton(self)
		local centerX, centerY = Minimap:GetCenter()
		local x, y = GetCursorPosition()
		x, y = x / self:GetEffectiveScale() - centerX, y / self:GetEffectiveScale() - centerY

		if dragMode == "free" then
			self:ClearAllPoints()
			self:SetPoint("CENTER", x, y)
		else -- Snap to minimap edge
			centerX, centerY = abs(x), abs(y)
			centerX, centerY = (centerX / sqrt(centerX ^ 2 + centerY ^ 2)) * 80, (centerY / sqrt(centerX ^ 2 + centerY ^ 2)) * 80
			centerX = x < 0 and -centerX or centerX
			centerY = y < 0 and -centerY or centerY
			self:ClearAllPoints()
			self:SetPoint("CENTER", centerX, centerY)
		end
	end

	-- OnLoad handler for the minimap button.
	function MinimapBtn:OnLoad(btn)
		if not btn then return end
		btn:SetUserPlaced(true)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnMouseDown", function(self, button)
			if IsAltKeyDown() then
				dragMode = "free"
				self:SetScript("OnUpdate", moveButton)
			elseif IsShiftKeyDown() then
				dragMode = nil
				self:SetScript("OnUpdate", moveButton)
			end
		end)
		btn:SetScript("OnMouseUp", function(self)
			self:SetScript("OnUpdate", nil)
		end)
		btn:SetScript("OnClick", function(self, button, down)
			if IsShiftKeyDown() or IsAltKeyDown() then return end
			if button == "RightButton" then
				addon.Config:Toggle()
			elseif button == "LeftButton" then
				OpenMenu()
			end
		end)
		btn:SetScript("OnEnter", function(self)
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			GameTooltip:SetText("|cfff58cbaKader|r |caad4af37Raid Tools|r")
			GameTooltip:AddLine(L.StrMinimapLClick, 1, 1, 1)
			GameTooltip:AddLine(L.StrMinimapRClick, 1, 1, 1)
			GameTooltip:AddLine(L.StrMinimapSClick, 1, 1, 1)
			GameTooltip:AddLine(L.StrMinimapAClick, 1, 1, 1)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
		end)
	end

	-- Toggles the minimap button's visibility based on options.
	function addon:ToggleMinimapButton()
		self.options.minimapButton = not self.options.minimapButton
		if self.options.minimapButton then
			KRT_MINIMAP_GUI:Show()
		else
			KRT_MINIMAP_GUI:Hide()
		end
	end
end

-- ============================================================================
-- Rolling System
-- ============================================================================
do
	addon.Rolls = {}
	local Rolls = addon.Rolls

	local record, canRoll, warned, rolled = false, true, false, false
	local playerRollTracker, rollsTable, rerolled, itemRollTracker = {}, {}, {}, {}
	local selectedPlayer = nil

	-- Sorts the rolls table based on the configuration.
	local function SortRolls()
		if rollsTable and #rollsTable > 0 then
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

	-- Adds a roll to the tracking tables.
	local function AddRoll(name, roll, itemId)
		roll = tonumber(roll)
		rollsCount = rollsCount + 1
		rollsTable[rollsCount] = { name = name, roll = roll, itemId = itemId }
		addon:Debug("DEBUG", "AddRoll: name=%s, roll=%d, itemId=%s", tostring(name), roll, tostring(itemId))

		if itemId then
			itemRollTracker[itemId] = itemRollTracker[itemId] or {}
			itemRollTracker[itemId][name] = (itemRollTracker[itemId][name] or 0) + 1
			addon:Debug("DEBUG", "Updated itemRollTracker: itemId=%d, player=%s, count=%d", itemId, name, itemRollTracker[itemId][name])
		end

		TriggerEvent("AddRoll", name, roll)
		SortRolls()

		-- Auto-select winner if not manually selected
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

	-- Initiates a /roll 1-100 for the player.
	function addon:Roll(btn)
		local itemId = self:GetCurrentRollItemID()
		if not itemId then return end

		playerRollTracker[itemId] = playerRollTracker[itemId] or 0
		local name = UnitName("player")
		local allowedRolls = 1

		if currentRollType == rollTypes.reserved then
			allowedRolls = addon.Reserves:GetReserveCountForItem(itemId, name)
		end

		if playerRollTracker[itemId] >= allowedRolls then
			addon:Debug("DEBUG", "Roll blocked for %s (max %d rolls reached for itemId=%d)", name, allowedRolls, itemId)
			addon:Print(L.ChatOnlyRollOnce)
			return
		end

		addon:Debug("DEBUG", "Rolling for itemId=%d (player=%s)", itemId, name)
		RandomRoll(1, 100)
		playerRollTracker[itemId] = playerRollTracker[itemId] + 1
	end

	-- Returns the current state of the rolling session.
	function addon:RollStatus()
		addon:Debug("DEBUG", "RollStatus queried: type=%s, record=%s, canRoll=%s, rolled=%s", tostring(currentRollType), tostring(record), tostring(canRoll), tostring(rolled))
		return currentRollType, record, canRoll, rolled
	end

	-- Enables or disables the recording of rolls.
	function addon:RecordRolls(bool)
		canRoll, record = bool == true, bool == true
		addon:Debug("DEBUG", "RecordRolls: %s", tostring(bool))
	end

	-- Event handler for CHAT_MSG_SYSTEM to detect rolls.
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

			local allowedRolls = 1
			if currentRollType == rollTypes.reserved then
				local playerReserves = addon.Reserves:GetReserveCountForItem(itemId, player)
				allowedRolls = playerReserves > 0 and playerReserves or 1
			end

			itemRollTracker[itemId] = itemRollTracker[itemId] or {}
			local usedRolls = itemRollTracker[itemId][player] or 0

			if usedRolls >= allowedRolls then
				if not Utils.checkEntry(rerolled, player) then
					Utils.whisper(player, L.ChatOnlyRollOnce)
					tinsert(rerolled, player)
					addon:Debug("DEBUG", "Roll denied: %s exceeded allowed rolls for item %d", player, itemId)
				end
				return
			end

			addon:Debug("DEBUG", "Roll accepted: %s (%d/%d) for item %d", player, usedRolls + 1, allowedRolls, itemId)
			AddRoll(player, roll, itemId)
		end
	end

	-- Returns the table of current rolls.
	function addon:GetRolls()
		addon:Debug("DEBUG", "GetRolls called; count: %d", #rollsTable)
		return rollsTable
	end

	-- Flags that the player has rolled.
	function addon:SetRolled()
		rolled = true
		addon:Debug("DEBUG", "SetRolled: rolled flag set to true")
	end

	-- Checks if a player has already used all their rolls for an item.
	function addon:DidRoll(itemId, name)
		if not itemId then -- Check for any roll if no item is specified
			for _, entry in ipairs(rollsTable) do
				if entry.name == name then
					addon:Debug("DEBUG", "DidRoll: %s has rolled (no itemId)", name)
					return true
				end
			end
			addon:Debug("DEBUG", "DidRoll: %s has NOT rolled (no itemId)", name)
			return false
		end
		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		local usedRolls = itemRollTracker[itemId][name] or 0
		local allowedRolls = (currentRollType == rollTypes.reserved and addon.Reserves:GetReserveCountForItem(itemId, name) > 0) and addon.Reserves:GetReserveCountForItem(itemId, name) or 1
		local result = usedRolls >= allowedRolls
		addon:Debug("DEBUG", "DidRoll: name=%s, itemId=%d, used=%d, allowed=%d, result=%s", name, itemId, usedRolls, allowedRolls, tostring(result))
		return result
	end

	-- Returns the roll value of the current highest roller.
	function addon:HighestRoll()
		if winner then
			for _, entry in ipairs(rollsTable) do
				if entry.name == winner then
					addon:Debug("DEBUG", "HighestRoll: %s rolled %d", winner, entry.roll)
					return entry.roll
				end
			end
		end
		return 0
	end

	-- Clears all roll-related state and UI elements.
	function addon:ClearRolls(rec)
		twipe(rollsTable)
		twipe(rerolled)
		twipe(itemRollTracker)
		twipe(playerRollTracker)
		rolled, warned, rollsCount = false, false, 0
		selectedPlayer, winner = nil, nil
		if rec == false then record = false end

		local frame = addon:GetFrameName() and _G[addon:GetFrameName()]
		if not frame then return end
		local i = 1
		local btn = _G[frame:GetName() .. "PlayerBtn" .. i]
		while btn do
			btn:Hide()
			i = i + 1
			btn = _G[frame:GetName() .. "PlayerBtn" .. i]
		end

		self:ClearRaidIcons()
	end

	-- Gets the current item ID being rolled for from the loot window.
	function addon:GetCurrentRollItemID()
		if not lootOpened and not fromInventory then return nil end
		local lootModule = addon.Loot
		local index = lootModule and lootModule.GetItemIndex and lootModule:GetItemIndex() or 1
		local itemLink = lootModule and lootModule.GetItemLink and lootModule:GetItemLink(index)
		if not itemLink then
			addon:Debug("DEBUG", "GetCurrentRollItemID: No itemLink found at index %d", index)
			return nil
		end
		local itemId = tonumber(match(itemLink, "item:(%d+)"))
		addon:Debug("DEBUG", "GetCurrentRollItemID: Found itemId %d", itemId)
		return itemId
	end

	-- Validates if a player can still roll for an item.
	function addon:IsValidRoll(itemId, name)
		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		local used = itemRollTracker[itemId][name] or 0
		local allowed = (currentRollType == rollTypes.reserved) and addon.Reserves:GetReserveCountForItem(itemId, name) or 1
		local result = used < allowed
		addon:Debug("DEBUG", "IsValidRoll: %s on item %d: used=%d, allowed=%d, valid=%s", name, itemId, used, allowed, tostring(result))
		return result
	end

	-- Checks if a player has reserved the item.
	function addon:IsReserved(itemId, name)
		local reserved = addon.Reserves:GetReserveCountForItem(itemId, name) > 0
		addon:Debug("DEBUG", "IsReserved: %s for item %d => %s", name, itemId, tostring(reserved))
		return reserved
	end

	-- Gets how many reserves the player has used.
	function addon:GetUsedReserveCount(itemId, name)
		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		local count = itemRollTracker[itemId][name] or 0
		addon:Debug("DEBUG", "GetUsedReserveCount: %s on item %d => %d", name, itemId, count)
		return count
	end

	-- Gets the allowed number of reserves for a player.
	function addon:GetAllowedReserves(itemId, name)
		local count = addon.Reserves:GetReserveCountForItem(itemId, name)
		addon:Debug("DEBUG", "GetAllowedReserves: %s for item %d => %d", name, itemId, count)
		return count
	end

	-- Updates the UI to display the current list of rolls.
	function addon:FetchRolls()
		local frame = addon:GetFrameName() and _G[addon:GetFrameName()]
		if not frame then return end
		addon:Debug("DEBUG", "FetchRolls called; frameName: %s", frame:GetName())

		local scrollFrame = _G[frame:GetName() .. "ScrollFrame"]
		local scrollChild = _G[frame:GetName() .. "ScrollFrameScrollChild"]
		scrollChild:SetHeight(scrollFrame:GetHeight())

		local itemId = self:GetCurrentRollItemID()
		local isSR = currentRollType == rollTypes.reserved
		addon:Debug("DEBUG", "Current itemId: %s, SR mode: %s", tostring(itemId), tostring(isSR))

		local starTarget = selectedPlayer
		if not starTarget then
			if isSR then
				local topRoll = -1
				for _, entry in ipairs(rollsTable) do
					if addon:IsReserved(itemId, entry.name) and entry.roll > topRoll then
						topRoll = entry.roll
						starTarget = entry.name
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
		for i = 1, #rollsTable do
			local entry = rollsTable[i]
			local name, roll = entry.name, entry.roll
			local btnName = frame:GetName() .. "PlayerBtn" .. i
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")
			btn:SetID(i)
			btn:Show()

			-- Ensure background exists for selection highlight
			if not btn.selectedBackground then
				btn.selectedBackground = btn:CreateTexture(nil, "ARTWORK")
				btn.selectedBackground:SetAllPoints()
				btn.selectedBackground:SetTexture(1, 0.8, 0, 0.1)
			end

			local nameStr, rollStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"], _G[btnName .. "Star"]

			if nameStr and nameStr.SetVertexColor then
				if isSR and self:IsReserved(itemId, name) then
					nameStr:SetVertexColor(0.4, 0.6, 1.0) -- Blue for reserved
				else
					local _, class = UnitClass(name)
					class = class and upper(class) or "UNKNOWN"
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
				winner = name
				addon:FetchRolls()
			end)

			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end

		-- Hide unused buttons
		for i = #rollsTable + 1, rollsCount do
			local btn = _G[frame:GetName() .. "PlayerBtn" .. i]
			if btn then btn:Hide() end
		end
		rollsCount = #rollsTable

		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		addon:Debug("DEBUG", "FetchRolls completed. Total entries: %d", rollsCount)
	end
end

-- ============================================================================
-- Loot Management System
-- ============================================================================
do
	addon.Loot = {}
	local Loot = addon.Loot

	local lootTable = {}
	local currentItemIndex = 0

	-- Forward declarations for functions defined in this scope
	local GetItem, GetItemIndex, GetItemLink, GetItemName, GetItemTexture, ItemExists, ItemIsSoulbound

	-- Fetches items from the loot window and populates the internal loot table.
	function addon:FetchLoot()
		local oldItemLink
		if lootCount >= 1 then
			oldItemLink = GetItemLink(currentItemIndex)
		end

		lootOpened = true
		fromInventory = false
		self:ClearLoot()

		for i = 1, GetNumLootItems() do
			if LootSlotIsItem(i) then
				local itemLink = GetLootSlotLink(i)
				-- Ignore enchanting materials
				if GetItemFamily(itemLink) ~= 64 then
					self:AddItem(itemLink)
				end
			end
		end

		currentItemIndex = 1
		if oldItemLink then
			for i = 1, lootCount do
				if oldItemLink == GetItemLink(i) then
					currentItemIndex = i
					break
				end
			end
		end
		self:PrepareItem()
	end

	-- Adds a single item to the internal loot table.
	function addon:AddItem(itemLink)
		local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

		if not itemName or not itemRarity then
			-- Item info not available yet, deferring (will be picked up by another event)
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:SetHyperlink(itemLink)
			GameTooltip:Hide()
			addon:Debug("DEBUG", "Item info not available yet, deferring.")
			return
		end

		if not fromInventory then
			local lootThreshold = GetLootThreshold()
			if itemRarity < lootThreshold then return end
			lootCount = lootCount + 1
		else
			lootCount = 1
			currentItemIndex = 1
		end

		lootTable[lootCount] = {
			itemName = itemName,
			itemColor = itemColors[itemRarity + 1],
			itemLink = itemLink,
			itemTexture = itemTexture
		}
		TriggerEvent("AddItem", itemLink)
	end

	-- Sets up the display for the currently selected item.
	function addon:PrepareItem()
		if ItemExists(currentItemIndex) then
			self:SetItem(lootTable[currentItemIndex])
		end
	end

	-- Updates the UI frames to show the specified item's details.
	function addon:SetItem(itemData)
		if not (itemData.itemName and itemData.itemLink and itemData.itemTexture and itemData.itemColor) then return end
		local frame = masterFrame or (addon:GetFrameName() and _G[addon:GetFrameName()])
		if not frame then return end
		local frameName = frame:GetName()

		_G[frameName .. "Name"]:SetText("|c" .. itemData.itemColor .. itemData.itemName .. "|r")
		local currentItemBtn = _G[frameName .. "ItemBtn"]
		currentItemBtn:SetNormalTexture(itemData.itemTexture)

		if self.options.showTooltips then
			currentItemBtn.tooltip_item = itemData.itemLink
			self:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
		end
		TriggerEvent("SetItem", itemData.itemLink)
	end

	-- Selects a new item from the loot table by its index.
	function addon:SelectItem(index)
		if ItemExists(index) then
			currentItemIndex = index
			self:PrepareItem()
		end
	end

	-- Clears all loot from the internal table and resets the UI.
	function addon:ClearLoot()
		twipe(lootTable)
		lootCount = 0
		local frame = masterFrame or (addon:GetFrameName() and _G[addon:GetFrameName()])
		if not frame then return end
		local frameName = frame:GetName()

		_G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
		_G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
		if frame == masterFrame then
			local itemCountFrame = _G[frameName .. "ItemCount"]
			itemCountFrame:SetText("")
			itemCountFrame:ClearFocus()
			itemCountFrame:Hide()
		end
	end

	-- Getter functions for loot item properties
	GetItemIndex = function() return currentItemIndex end
	GetItem = function(i) return lootTable[i or currentItemIndex] end
	GetItemName = function(i) return lootTable[i or currentItemIndex] and lootTable[i or currentItemIndex].itemName or nil end
	GetItemLink = function(i) return lootTable[i or currentItemIndex] and lootTable[i or currentItemIndex].itemLink or nil end
	GetItemTexture = function(i) return lootTable[i or currentItemIndex] and lootTable[i or currentItemIndex].itemTexture or nil end
	ItemExists = function(i) return lootTable[i or currentItemIndex] ~= nil end
	Loot.GetItemIndex = GetItemIndex
	Loot.GetItemLink = GetItemLink

	-- Checks if an item in a container is soulbound by scanning its tooltip.
	-- This is a common workaround for the limited API.
	ItemIsSoulbound = function(bag, slot)
		local tip = KRT_FakeTooltip or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
		KRT_FakeTooltip = tip
		tip:SetOwner(UIParent, "ANCHOR_NONE")
		tip:SetBagItem(bag, slot)
		tip:Show()

		for i = tip:NumLines(), 1, -1 do
			local textLine = _G["KRT_FakeTooltipTextLeft" .. i]
			if textLine then
				local text = textLine:GetText()
				if deformat(text, BIND_TRADE_TIME_REMAINING) then
					tip:Hide()
					return false
				elseif text == ITEM_SOULBOUND then
					tip:Hide()
					return true
				end
			end
		end

		tip:Hide()
		return false
	end
end

-- ============================================================================
-- Master Looter Frame
-- ============================================================================
do
	addon.Master = {}
	local Master = addon.Master

	local localized, dropDownsInitialized, countdownRun, announced, screenshotWarn = false, false, false, false, false
	local countdownStart, countdownPos = 0, 0
	local trader
	local updateInterval = 0.05
	local dropDownData, dropDownGroupData = {}, {}
	local dropDownFrameHolder, dropDownFrameBanker, dropDownFrameDisenchanter
	local selectionFrame

	-- Local forward declarations
	local LocalizeUIFrame, UpdateUIFrame, InitializeDropDowns, PrepareDropDowns, UpdateDropDowns
	local UpdateSelectionFrame, CreateSelectionFrame, AssignItem, TradeItem

	function Master:OnLoad(frame)
		if not frame then return end
		masterFrame = frame
		local frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
		frame:SetScript("OnHide", function()
			if selectionFrame then selectionFrame:Hide() end
		end)
	end

	function Master:Toggle() Utils.toggle(masterFrame) end
	function Master:Hide() if masterFrame and masterFrame:IsShown() then masterFrame:Hide() end end

	-- Button Handlers
	function Master:BtnSelectItem(btn)
		if not btn or lootCount <= 0 then return end
		if fromInventory then
			addon:ClearLoot()
			addon:ClearRolls()
			addon:RecordRolls(false)
			announced = false
			fromInventory = false
			if lootOpened then addon:FetchLoot() end
		elseif selectionFrame then
			selectionFrame:SetShown(not selectionFrame:IsVisible())
		end
	end

	function Master:BtnSpamLoot(btn)
		if not btn or lootCount <= 0 then return end
		if fromInventory then
			addon:Announce(L.ChatReadyCheck)
			DoReadyCheck()
		else
			addon:Announce(L.ChatSpamLoot, "RAID")
			for i = 1, lootCount do
				local itemLink = addon.Loot.GetItemLink(i)
				if itemLink then
					addon:Announce(i .. ". " .. itemLink, "RAID")
				end
			end
		end
	end

	function Master:BtnOpenReserves() addon.Reserves:ShowWindow() end
	function Master:BtnImportReserves() addon.Reserves:ShowImportBox() end

	local function AnnounceRoll(type, chatMsg)
		if lootCount < 1 then return end
		announced = false
		currentRollType = type
		addon:ClearRolls()
		addon:RecordRolls(true)

		local itemLink = addon.Loot.GetItemLink()
		local itemID = tonumber(match(itemLink or "", "item:(%d+)"))
		local message = ""
		local suffix = addon.options.sortAscending and "Low" or "High"

		if type == rollTypes.reserved and addon.Reserves and addon.Reserves.FormatReservedPlayersLine then
			local srList = addon.Reserves:FormatReservedPlayersLine(itemID)
			message = itemCount > 1 and L[chatMsg .. "Multiple" .. suffix]:format(srList, itemLink, itemCount) or L[chatMsg]:format(srList, itemLink)
		else
			message = itemCount > 1 and L[chatMsg .. "Multiple" .. suffix]:format(itemLink, itemCount) or L[chatMsg]:format(itemLink)
		end

		addon:Announce(message)
		if masterFrame then _G[masterFrame:GetName() .. "ItemCount"]:ClearFocus() end
		currentRollItem = addon.Raid:GetLootID(itemID)
	end

	function Master:BtnMS() AnnounceRoll(rollTypes.mainspec, "ChatRollMS") end
	function Master:BtnOS() AnnounceRoll(rollTypes.offspec, "ChatRollOS") end
	function Master:BtnSR() AnnounceRoll(rollTypes.reserved, "ChatRollSR") end
	function Master:BtnFree() AnnounceRoll(rollTypes.free, "ChatRollFree") end

	function Master:BtnCountdown()
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

	function Master:BtnClear()
		announced = false
		addon:ClearRolls()
	end

	function Master:BtnAward()
		if lootCount <= 0 or rollsCount <= 0 then
			addon:Debug("DEBUG", "Cannot award, lootCount=%d, rollsCount=%d", lootCount or 0, rollsCount or 0)
			return
		end
		countdownRun = false
		local itemLink = addon.Loot.GetItemLink()
		if masterFrame then _G[masterFrame:GetName() .. "ItemCount"]:ClearFocus() end
		if fromInventory then
			TradeItem(itemLink, winner, currentRollType, addon:HighestRoll())
		else
			AssignItem(itemLink, winner, currentRollType, addon:HighestRoll())
		end
	end

	function Master:BtnHold()
		if lootCount <= 0 or not holder then return end
		countdownRun = false
		local itemLink = addon.Loot.GetItemLink()
		if not itemLink then return end
		currentRollType = rollTypes.hold
		if fromInventory then
			TradeItem(itemLink, holder, rollTypes.hold, 0)
		else
			AssignItem(itemLink, holder, rollTypes.hold, 0)
		end
	end

	function Master:BtnBank()
		if lootCount <= 0 or not banker then return end
		countdownRun = false
		local itemLink = addon.Loot.GetItemLink()
		if not itemLink then return end
		currentRollType = rollTypes.bank
		if fromInventory then
			TradeItem(itemLink, banker, rollTypes.bank, 0)
		else
			AssignItem(itemLink, banker, rollTypes.bank, 0)
		end
	end

	function Master:BtnDisenchant()
		if lootCount <= 0 or not disenchanter then return end
		countdownRun = false
		local itemLink = addon.Loot.GetItemLink()
		if not itemLink then return end
		currentRollType = rollTypes.disenchant
		if fromInventory then
			TradeItem(itemLink, disenchanter, rollTypes.disenchant, 0)
		else
			AssignItem(itemLink, disenchanter, rollTypes.disenchant, 0)
		end
	end

	-- UI Interaction
	function Master:SelectWinner(btn)
		if not btn then return end
		local playerName = _G[btn:GetName() .. "Name"]:GetText()
		if not playerName then return end

		if IsControlKeyDown() then
			local roll = _G[btn:GetName() .. "Roll"]:GetText()
			addon:Announce(format(L.ChatPlayerRolled, playerName, roll))
			return
		end
		winner = playerName:trim()
		addon:FetchRolls()
		Utils.sync("KRT-RollWinner", playerName)
		if itemCount == 1 then announced = false end
	end

	function Master:BtnSelectedItem(btn)
		if not btn then return end
		local index = btn:GetID()
		if index then
			announced = false
			selectionFrame:Hide()
			addon:SelectItem(index)
		end
	end

	-- Frame Logic
	LocalizeUIFrame = function()
		if localized or not masterFrame then return end
		local frameName = masterFrame:GetName()
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName .. "ConfigBtn"]:SetText(L.BtnConfigure)
			_G[frameName .. "SelectItemBtn"]:SetText(L.BtnSelectItem)
			_G[frameName .. "SpamLootBtn"]:SetText(L.BtnSpamLoot)
			_G[frameName .. "MSBtn"]:SetText(L.BtnMS)
			_G[frameName .. "OSBtn"]:SetText(L.BtnOS)
			_G[frameName .. "SRBtn"]:SetText(L.BtnSR)
			_G[frameName .. "FreeBtn"]:SetText(L.BtnFree)
			_G[frameName .. "CountdownBtn"]:SetText(L.BtnCountdown)
			_G[frameName .. "AwardBtn"]:SetText(L.BtnAward)
			_G[frameName .. "RollBtn"]:SetText(L.BtnRoll)
			_G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
			_G[frameName .. "HoldBtn"]:SetText(L.BtnHold)
			_G[frameName .. "BankBtn"]:SetText(L.BtnBank)
			_G[frameName .. "DisenchantBtn"]:SetText(L.BtnDisenchant)
			_G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
			_G[frameName .. "RollsHeaderRoll"]:SetText(L.StrRoll)
			_G[frameName .. "OpenReservesBtn"]:SetText(L.BtnOpenReserves)
			_G[frameName .. "ImportReservesBtn"]:SetText(L.BtnImportReserves)
		end
		_G[frameName .. "Title"]:SetText(format(titleString, MASTER_LOOTER))
		_G[frameName .. "ItemCount"]:SetScript("OnTextChanged", function() announced = false end)
		if not next(dropDownData) then
			for i = 1, 8 do dropDownData[i] = {} end
		end
		dropDownFrameHolder = _G[frameName .. "HoldDropDown"]
		dropDownFrameBanker = _G[frameName .. "BankDropDown"]
		dropDownFrameDisenchanter = _G[frameName .. "DisenchantDropDown"]
		PrepareDropDowns()
		UIDropDownMenu_Initialize(dropDownFrameHolder, InitializeDropDowns)
		UIDropDownMenu_Initialize(dropDownFrameBanker, InitializeDropDowns)
		UIDropDownMenu_Initialize(dropDownFrameDisenchanter, InitializeDropDowns)
		localized = true
	end

	UpdateUIFrame = function(self, elapsed)
		if not masterFrame then return end
		LocalizeUIFrame()
		if Utils.periodic(self, masterFrame:GetName(), updateInterval, elapsed) then
			local frameName = masterFrame:GetName()
			itemCount = _G[frameName .. "ItemCount"]:GetNumber()
			if itemInfo.count and itemInfo.count ~= itemCount then
				if itemInfo.count < itemCount then
					itemCount = itemInfo.count
					_G[frameName .. "ItemCount"]:SetNumber(itemInfo.count)
				end
			end

			UpdateDropDowns(dropDownFrameHolder)
			UpdateDropDowns(dropDownFrameBanker)
			UpdateDropDowns(dropDownFrameDisenchanter)

			Utils.setText(_G[frameName .. "CountdownBtn"], L.BtnStop, L.BtnCountdown, countdownRun)
			Utils.setText(_G[frameName .. "AwardBtn"], TRADE, L.BtnAward, fromInventory)

			if countdownRun then
				local tick = ceil(addon.options.countdownDuration - GetTime() + countdownStart)
				for i = countdownPos - 1, tick, -1 do
					if i >= addon.options.countdownDuration or (i >= 10 and i % 10 == 0) or (i > 0 and i < 10 and (i % 7 == 0 or i % 5 == 0 or i <= 3)) then
						addon:Announce(L.ChatCountdownTic:format(i))
					end
				end
				countdownPos = tick
				if countdownPos <= 0 then
					countdownRun = false
					addon:Announce(L.ChatCountdownEnd)
					if addon.options.countdownRollsBlock then
						addon:RecordRolls(false)
					end
				end
			end

			local hasLoot = lootCount >= 1
			Utils.enableDisable(_G[frameName .. "SelectItemBtn"], lootCount > 1 or (fromInventory and hasLoot))
			Utils.enableDisable(_G[frameName .. "SpamLootBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "MSBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "OSBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "SRBtn"], hasLoot and addon.Reserves:HasData())
			Utils.enableDisable(_G[frameName .. "FreeBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "CountdownBtn"], hasLoot and addon.Loot.GetItemLink() ~= nil)
			Utils.enableDisable(_G[frameName .. "HoldBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "BankBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "DisenchantBtn"], hasLoot)
			Utils.enableDisable(_G[frameName .. "AwardBtn"], hasLoot and rollsCount >= 1)
			Utils.enableDisable(_G[frameName .. "OpenReservesBtn"], addon.Reserves:HasData())
			Utils.enableDisable(_G[frameName .. "ImportReservesBtn"], not addon.Reserves:HasData())

			local _, record, canRoll, isRolled = addon:RollStatus()
			Utils.enableDisable(_G[frameName .. "RollBtn"], record and canRoll and not isRolled)
			Utils.enableDisable(_G[frameName .. "ClearBtn"], rollsCount >= 1)

			Utils.setText(_G[frameName .. "SelectItemBtn"], L.BtnRemoveItem, L.BtnSelectItem, fromInventory)
			Utils.setText(_G[frameName .. "SpamLootBtn"], READY_CHECK, L.BtnSpamLoot, fromInventory)
		end
	end

	-- DropDown Logic
	InitializeDropDowns = function()
		if UIDROPDOWNMENU_MENU_LEVEL == 1 then
			for key, value in pairs(dropDownData) do
				if dropDownGroupData[key] then
					local info = UIDropDownMenu_CreateInfo()
					info.hasArrow, info.notCheckable = 1, 1
					info.text, info.value, info.owner = GROUP .. " " .. key, key, UIDROPDOWNMENU_OPEN_MENU
					UIDropDownMenu_AddButton(info)
				end
			end
		elseif UIDROPDOWNMENU_MENU_LEVEL == 2 then
			local group = UIDROPDOWNMENU_MENU_VALUE
			local members = dropDownData[group]
			for key, value in pairs(members) do
				local info = UIDropDownMenu_CreateInfo()
				info.notCheckable, info.text = 1, key
				info.func, info.arg1, info.arg2 = Master.OnClickDropDown, UIDROPDOWNMENU_OPEN_MENU, key
				UIDropDownMenu_AddButton(info)
			end
		end
	end

	PrepareDropDowns = function()
		for i = 1, 8 do twipe(dropDownData[i]) end
		twipe(dropDownGroupData)
		for p = 1, GetRealNumRaidMembers() do
			local name, _, subgroup = GetRaidRosterInfo(p)
			if name then
				dropDownData[subgroup][name] = name
				dropDownGroupData[subgroup] = true
			end
		end
	end

	function Master:OnClickDropDown(owner, value)
		if not KRT_CurrentRaid then return end
		UIDropDownMenu_SetText(owner, value)
		UIDropDownMenu_SetSelectedValue(owner, value)
		local frameName = owner:GetName()
		if frameName == dropDownFrameHolder:GetName() then
			KRT_Raids[KRT_CurrentRaid].holder = value
		elseif frameName == dropDownFrameBanker:GetName() then
			KRT_Raids[KRT_CurrentRaid].banker = value
		elseif frameName == dropDownFrameDisenchanter:GetName() then
			KRT_Raids[KRT_CurrentRaid].disenchanter = value
		end
		CloseDropDownMenus()
	end

	UpdateDropDowns = function(frame)
		if not frame or not KRT_CurrentRaid then return end
		local frameName = frame:GetName()
		local raidData = KRT_Raids[KRT_CurrentRaid]
		if not raidData then return end

		if frameName == dropDownFrameHolder:GetName() then
			holder = raidData.holder
			if holder and addon:GetUnitID(holder) == "none" then
				raidData.holder = nil; holder = nil
			end
			if holder then UIDropDownMenu_SetText(frame, holder); UIDropDownMenu_SetSelectedValue(frame, holder) end
		elseif frameName == dropDownFrameBanker:GetName() then
			banker = raidData.banker
			if banker and addon:GetUnitID(banker) == "none" then
				raidData.banker = nil; banker = nil
			end
			if banker then UIDropDownMenu_SetText(frame, banker); UIDropDownMenu_SetSelectedValue(frame, banker) end
		elseif frameName == dropDownFrameDisenchanter:GetName() then
			disenchanter = raidData.disenchanter
			if disenchanter and addon:GetUnitID(disenchanter) == "none" then
				raidData.disenchanter = nil; disenchanter = nil
			end
			if disenchanter then UIDropDownMenu_SetText(frame, disenchanter); UIDropDownMenu_SetSelectedValue(frame, disenchanter) end
		end
	end

	-- Item Selection Frame Logic
	CreateSelectionFrame = function()
		if not selectionFrame and masterFrame then
			selectionFrame = CreateFrame("Frame", nil, masterFrame, "KRTSimpleFrameTemplate")
			selectionFrame:Hide()
		end
		if not selectionFrame then return end
		local i = 1
		while _G[masterFrame:GetName() .. "ItemSelectionBtn" .. i] do
			_G[masterFrame:GetName() .. "ItemSelectionBtn" .. i]:Hide()
			i = i + 1
		end
	end

	UpdateSelectionFrame = function()
		if not masterFrame then return end
		CreateSelectionFrame()
		if not selectionFrame then return end
		local frameName = masterFrame:GetName()
		local height = 5
		for i = 1, lootCount do
			local btnName = frameName .. "ItemSelectionBtn" .. i
			local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
			btn:SetID(i)
			btn:Show()
			_G[btnName .. "Name"]:SetText(addon.Loot.GetItemName(i))
			_G[btnName .. "Icon"]:SetTexture(addon.Loot.GetItemTexture(i))
			btn:SetPoint("TOPLEFT", 5, -height)
			height = height + 37
		end
		selectionFrame:SetHeight(height)
		selectionFrame:SetWidth(200)
		if lootCount <= 0 then selectionFrame:Hide() end
	end

	-- Item Assignment/Trade Logic
	AssignItem = function(itemLink, playerName, rollType, rollValue)
		local itemIndex
		for i = 1, GetNumLootItems() do
			if GetLootSlotLink(i) == itemLink then
				itemIndex = i
				break
			end
		end
		if not itemIndex then
			addon:PrintError(L.ErrCannotFindItem:format(itemLink))
			return false
		end

		for p = 1, GetMasterLootNumItems() do
			if GetMasterLootCandidate(p) == playerName then
				GiveMasterLoot(itemIndex, p)
				local output, whisper
				if rollType <= rollTypes.free and addon.options.announceOnWin then
					output = L.ChatAward:format(playerName, itemLink)
				elseif rollType == rollTypes.hold and addon.options.announceOnHold then
					output = L.ChatHold:format(playerName, itemLink)
					if addon.options.lootWhispers then whisper = L.WhisperHoldAssign:format(itemLink) end
				elseif rollType == rollTypes.bank and addon.options.announceOnBank then
					output = L.ChatBank:format(playerName, itemLink)
					if addon.options.lootWhispers then whisper = L.WhisperBankAssign:format(itemLink) end
				elseif rollType == rollTypes.disenchant and addon.options.announceOnDisenchant then
					output = L.ChatDisenchant:format(itemLink, playerName)
					if addon.options.lootWhispers then whisper = L.WhisperDisenchantAssign:format(itemLink) end
				end
				if output and not announced then addon:Announce(output); announced = true end
				if whisper then Utils.whisper(playerName, whisper) end
				addon:Log(currentRollItem, playerName, rollType, rollValue)
				return true
			end
		end
		addon:PrintError(L.ErrCannotFindPlayer:format(playerName))
		return false
	end

	TradeItem = function(itemLink, playerName, rollType, rollValue)
		if itemLink ~= addon.Loot.GetItemLink() then return end
		trader = unitName

		local output, whisper, keep = nil, nil, true
		if rollType <= rollTypes.free and addon.options.announceOnWin then
			output, keep = L.ChatAward:format(playerName, itemLink), false
		elseif rollType == rollTypes.hold and addon.options.announceOnHold then
			output = L.ChatNoneRolledHold:format(itemLink, playerName)
		elseif rollType == rollTypes.bank and addon.options.announceOnBank then
			output = L.ChatNoneRolledBank:format(itemLink, playerName)
		elseif rollType == rollTypes.disenchant and addon.options.announceOnDisenchant then
			output = L.ChatNoneRolledDisenchant:format(itemLink, playerName)
		end

		if keep then
			if rollType == rollTypes.hold then whisper = L.WhisperHoldTrade:format(itemLink)
			elseif rollType == rollTypes.bank then whisper = L.WhisperBankTrade:format(itemLink)
			elseif rollType == rollTypes.disenchant then whisper = L.WhisperDisenchantTrade:format(itemLink) end
		elseif itemCount > 1 then
			addon:ClearRaidIcons()
			SetRaidTarget(trader, 1)
			local rolls = addon:GetRolls()
			local winnersText = {}
			for i = 1, itemCount do
				if rolls[i] then
					if rolls[i].name == trader then
						tinsert(winnersText, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
					else
						SetRaidTarget(rolls[i].name, i + 1)
						tinsert(winnersText, markers[i] .. " " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
					end
				end
			end
			output = L.ChatTradeMutiple:format(tconcat(winnersText, ", "), trader)
		elseif trader == winner then
			addon:ClearLoot(); addon:ClearRolls(false); addon:ClearRaidIcons()
		elseif CheckInteractDistance(playerName, 2) == 1 then
			if itemInfo.isStack and not addon.options.ignoreStacks then
				addon:PrintWarning(L.ErrItemStack:format(itemLink))
				return false
			end
			ClearCursor(); PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
			if CursorHasItem() then
				InitiateTrade(playerName)
				if addon.options.screenReminder and not screenshotWarn then
					addon:PrintWarning(L.ErrScreenReminder); screenshotWarn = true
				end
			end
		elseif addon:GetUnitID(playerName) ~= "none" then
			addon:ClearRaidIcons(); SetRaidTarget(trader, 1); SetRaidTarget(winner, 4)
			output = L.ChatTrade:format(playerName, itemLink)
		end

		if not announced then
			if output then addon:Announce(output) end
			if whisper then
				if playerName == trader then
					addon:ClearLoot(); addon:ClearRolls(); addon:RecordRolls(false)
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

	-- Event Handlers
	function addon:ITEM_LOCKED(_, inBag, inSlot)
		if not inBag or not inSlot or not masterFrame then return end
		local _, _, _, _, _, _, itemLink = GetContainerItemInfo(inBag, inSlot)
		if not itemLink then return end
		_G[masterFrame:GetName() .. "ItemBtn"]:SetScript("OnClick", function()
			if not ItemIsSoulbound(inBag, inSlot) then
				_G[masterFrame:GetName() .. "ItemCount"]:Hide()
				fromInventory = true
				addon:AddItem(itemLink)
				addon:PrepareItem()
				announced = false
				itemInfo.bagID, itemInfo.slotID = inBag, inSlot
				itemInfo.count, itemInfo.isStack = GetItemCount(itemLink), GetItemCount(itemLink) > 1
				if itemInfo.count >= 1 then
					itemCount = itemInfo.count
					_G[masterFrame:GetName() .. "ItemCount"]:SetText(itemInfo.count)
					_G[masterFrame:GetName() .. "ItemCount"]:Show()
					_G[masterFrame:GetName() .. "ItemCount"]:SetFocus()
				end
			end
			ClearCursor()
		end)
	end

	function addon:LOOT_OPENED()
		if self:IsMasterLooter() then
			lootOpened, announced = true, false
			self:FetchLoot()
			UpdateSelectionFrame()
			if lootCount >= 1 and masterFrame then masterFrame:Show() end
			if not self.Logger.container then self.Logger.source = UnitName("target") end
		end
	end

	function addon:LOOT_CLOSED()
		if self:IsMasterLooter() then
			lootOpened = false
			if masterFrame then masterFrame:Hide() end
			self:ClearLoot(); self:ClearRolls(); self:RecordRolls(false)
		end
	end

	function addon:LOOT_SLOT_CLEARED()
		if self:IsMasterLooter() then
			self:FetchLoot()
			UpdateSelectionFrame()
			if lootCount >= 1 and masterFrame then masterFrame:Show() else if masterFrame then masterFrame:Hide() end end
		end
	end

	function addon:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
		if itemCount == 1 and trader and winner and trader ~= winner then
			if tAccepted == 1 and pAccepted == 1 then
				self:Log(currentRollItem, winner, currentRollType, self:HighestRoll())
				trader, winner = nil, nil
				self:ClearLoot(); self:ClearRolls(); self:RecordRolls(false)
				screenshotWarn = false
			end
		end
	end

	addon:RegisterCallback("SetItem", function(_, itemLink)
		if addon.Loot.GetItemLink() ~= itemLink then
			announced = false
		end
	end)
end

-- ============================================================================
-- Loot Counter Frame
-- ============================================================================
do
	local rows = {}
	local lootCounterFrame, scrollChild

	local function EnsureFrames()
		lootCounterFrame = lootCounterFrame or _G["KRTLootCounterFrame"]
		scrollChild = scrollChild or _G["KRTLootCounterFrameScrollFrameScrollChild"]
	end

	local function GetCurrentRaidPlayers()
		local players = {}
		for i = 1, GetNumRaidMembers() do
			local name = GetRaidRosterInfo(i)
			if name and name ~= "" then
				tinsert(players, name)
				if KRT_PlayerCounts[name] == nil then
					KRT_PlayerCounts[name] = 0
				end
			end
		end
		table.sort(players)
		return players
	end

	function addon:ToggleCountsFrame()
		EnsureFrames()
		if lootCounterFrame then
			Utils.toggle(lootCounterFrame)
			if lootCounterFrame:IsShown() then
				addon:UpdateCountsFrame() -- Always refresh before showing
			end
		end
	end

	function addon:UpdateCountsFrame()
		EnsureFrames()
		if not lootCounterFrame or not scrollChild then return end

		local players = GetCurrentRaidPlayers()
		local numPlayers = #players
		local rowHeight = 25

		scrollChild:SetHeight(numPlayers * rowHeight)

		for i = 1, numPlayers do
			local name = players[i]
			local row = rows[i]
			if not row then
				row = CreateFrame("Frame", nil, scrollChild)
				row:SetSize(160, 24)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)

				row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.name:SetPoint("LEFT", 0, 0)
				row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.count:SetPoint("LEFT", row.name, "RIGHT", 10, 0)

				row.plus = CreateFrame("Button", nil, row, "KRTButtonTemplate")
				row.plus:SetSize(22, 22); row.plus:SetText("+")
				row.plus:SetPoint("LEFT", row.count, "RIGHT", 5, 0)
				row.plus:SetScript("OnClick", function()
					local pName = row._playerName
					if pName then KRT_PlayerCounts[pName] = (KRT_PlayerCounts[pName] or 0) + 1; addon:UpdateCountsFrame() end
				end)

				row.minus = CreateFrame("Button", nil, row, "KRTButtonTemplate")
				row.minus:SetSize(22, 22); row.minus:SetText("-")
				row.minus:SetPoint("LEFT", row.plus, "RIGHT", 2, 0)
				row.minus:SetScript("OnClick", function()
					local pName = row._playerName
					if pName then local c = (KRT_PlayerCounts[pName] or 1) - 1; KRT_PlayerCounts[pName] = c; addon:UpdateCountsFrame() end
				end)

				rows[i] = row
			else
				row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
			end

			row._playerName = name
			row.name:SetText(name)
			row.count:SetText(tostring(KRT_PlayerCounts[name] or 0))
			row:Show()
		end

		for i = numPlayers + 1, #rows do
			if rows[i] then rows[i]:Hide() end
		end
	end
end

-- ============================================================================
-- Raid Reserves System
-- ============================================================================
do
	addon.Reserves = {}
	local Reserves = addon.Reserves

	local frameName
	local localized = false
	local updateInterval = 0.5

	local reservesData, reservesByItemID = {}, {}
	local reserveListFrame, scrollFrame, scrollChild
	local reserveItemRows, rowsByItemID = {}, {}
	local pendingItemInfo, collapsedBossGroups = {}, {}

	-- Data Management
	function Reserves:Save()
		addon:Debug("DEBUG", "Saving reserves data. Entries: %d", Utils.tableLen(reservesData))
		KRT_SavedReserves = table.deepCopy(reservesData)
		KRT_SavedReserves.reservesByItemID = table.deepCopy(reservesByItemID)
	end

	function Reserves:Load()
		addon:Debug("DEBUG", "Loading reserves. Data exists: %s", tostring(KRT_SavedReserves ~= nil))
		if KRT_SavedReserves then
			reservesData = table.deepCopy(KRT_SavedReserves)
			reservesByItemID = table.deepCopy(KRT_SavedReserves.reservesByItemID or {})
		else
			reservesData = {}; reservesByItemID = {}
		end
	end

	function Reserves:ResetSaved()
		addon:Debug("DEBUG", "Resetting saved reserves data.")
		KRT_SavedReserves = nil
		twipe(reservesData); twipe(reservesByItemID)
		self:RefreshWindow()
		self:CloseWindow()
		addon:Print(L.StrReserveListCleared)
	end

	function Reserves:HasData() return next(reservesData) ~= nil end

	-- UI Windows
	function Reserves:ShowWindow()
		if not reserveListFrame then addon:PrintError("Reserve List frame not available."); return end
		addon:Debug("DEBUG", "Showing reserve list window.")
		reserveListFrame:Show()
	end

	function Reserves:CloseWindow()
		addon:Debug("DEBUG", "Closing reserve list window.")
		if reserveListFrame then reserveListFrame:Hide() end
	end

	function Reserves:ShowImportBox()
		addon:Debug("DEBUG", "Opening import reserves box.")
		local frame = _G["KRTImportWindow"]
		if not frame then addon:PrintError("KRTImportWindow not found."); return end
		frame:Show()
		if _G["KRTImportEditBox"] then _G["KRTImportEditBox"]:SetText("") end
		_G[frame:GetName() .. "Title"]:SetText(format(titleString, L.StrImportReservesTitle))
	end

	function Reserves:OnLoad(frame)
		addon:Debug("DEBUG", "Reserves frame loaded.")
		reserveListFrame = frame
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", function(...) UpdateUIFrame(...) end)

		scrollFrame = _G[frameName .. "ScrollFrame"]
		scrollChild = _G[frameName .. "ScrollFrameScrollChild"]

		_G[frameName .. "CloseButton"]:SetScript("OnClick", function() self:CloseWindow() end)
		_G[frameName .. "ClearButton"]:SetScript("OnClick", function() self:ResetSaved() end)
		_G[frameName .. "QueryButton"]:SetScript("OnClick", function() self:QueryMissingItems() end)

		local refreshFrame = CreateFrame("Frame")
		refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		refreshFrame:SetScript("OnEvent", function(_, _, itemId)
			addon:Debug("DEBUG", "GET_ITEM_INFO_RECEIVED for itemId %d", itemId)
			if pendingItemInfo[itemId] then
				local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
				if name then
					addon:Debug("DEBUG", "Updating reserve data for item: %s", link)
					self:UpdateReserveItemData(itemId, name, link, tex)
					pendingItemInfo[itemId] = nil
				end
			end
		end)
	end

	-- UI Update
	function UpdateUIFrame(self, elapsed)
		if not localized then
			if frameName then _G[frameName .. "Title"]:SetText(format(titleString, L.StrRaidReserves)) end
			localized = true
		end
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			local hasData = Reserves:HasData()
			Utils.enableDisable(_G[frameName .. "ClearButton"], hasData)
			Utils.enableDisable(_G[frameName .. "QueryButton"], hasData)
		end
	end

	-- Data Access
	function Reserves:GetReserve(playerName)
		local player = playerName:lower():trim()
		return reservesData[player]
	end

	function Reserves:ParseCSV(csv)
		addon:Debug("DEBUG", "Starting to parse CSV data.")
		twipe(reservesData); twipe(reservesByItemID)

		local function cleanCSVField(field)
			return field and field:gsub('^"(.-)"$', '%1'):trim() or nil
		end

		local isFirstLine = true
		for line in csv:gmatch("[^\r\n]+") do
			if isFirstLine then
				isFirstLine = false
			else
				local _, itemIdStr, source, playerName, class, spec, note, plus = line:match('^"?(.-)"?,(.-),(.-),(.-),(.-),(.-),(.-),(.-)')
				local itemId = tonumber(cleanCSVField(itemIdStr))
				playerName = cleanCSVField(playerName)
				local normalized = playerName and playerName:lower():trim()

				if normalized and itemId then
					addon:Debug("DEBUG", "Processing player: %s, Item ID: %d", playerName, itemId)
					reservesData[normalized] = reservesData[normalized] or { original = playerName, reserves = {} }

					local found = false
					for _, entry in ipairs(reservesData[normalized].reserves) do
						if entry.rawID == itemId then
							entry.quantity = (entry.quantity or 1) + 1
							found = true
							addon:Debug("DEBUG", "Updated quantity for player %s, item ID %d. New quantity: %d", playerName, itemId, entry.quantity)
							break
						end
					end

					if not found then
						local entry = {
							rawID = itemId, itemLink = nil, itemName = nil, itemIcon = nil,
							quantity = 1,
							class = cleanCSVField(class) or nil,
							note = cleanCSVField(note) or nil,
							plus = tonumber(cleanCSVField(plus)) or 0,
							source = cleanCSVField(source) or nil
						}
						tinsert(reservesData[normalized].reserves, entry)
						reservesByItemID[itemId] = reservesByItemID[itemId] or {}
						tinsert(reservesByItemID[itemId], entry)
						addon:Debug("DEBUG", "Added new reserve entry for player %s, item ID %d", playerName, itemId)
					end
				end
			end
		end
		addon:Debug("DEBUG", "Finished parsing CSV data. Total reserves processed: %d", Utils.tableLen(reservesData))
		self:RefreshWindow(); self:Save()
	end

	-- Item Info Query
	function Reserves:QueryItemInfo(itemId)
		if not itemId then return end
		addon:Debug("DEBUG", "Querying info for itemId: %d", itemId)
		local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
		if name and link and tex then
			self:UpdateReserveItemData(itemId, name, link, tex)
			return true
		else
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:SetHyperlink("item:" .. itemId); GameTooltip:Hide()
			return false
		end
	end

	function Reserves:QueryMissingItems()
		local count = 0
		addon:Debug("DEBUG", "Querying missing items in reserves.")
		for _, player in pairs(reservesData) do
			if type(player) == "table" and type(player.reserves) == "table" then
				for _, r in ipairs(player.reserves) do
					if not r.itemLink or not r.itemIcon then
						if not self:QueryItemInfo(r.rawID) then count = count + 1 end
					end
				end
			end
		end
		addon:Print(count > 0 and ("Requested info for " .. count .. " missing items.") or "All item infos are available.")
	end

	function Reserves:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
		addon:Debug("DEBUG", "Updating reserve item data for itemId: %d", itemId)
		for _, player in pairs(reservesData) do
			if type(player) == "table" then
				for _, r in ipairs(player.reserves or {}) do
					if r.rawID == itemId then
						r.itemName, r.itemLink, r.itemIcon = itemName, itemLink, itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
					end
				end
			end
		end
		local rows = rowsByItemID[itemId]
		if not rows then return end

		for _, row in ipairs(rows) do
			row.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.nameText:SetText(itemLink or itemName or ("[Item ID: " .. itemId .. "]"))
			row.iconBtn:SetScript("OnEnter", function()
				GameTooltip:SetOwner(row.iconBtn, "ANCHOR_RIGHT")
				if itemLink then GameTooltip:SetHyperlink(itemLink) else GameTooltip:SetText("Item ID: " .. itemId, 1, 1, 1) end
				GameTooltip:Show()
			end)
		end
	end

	function Reserves:GetReserveCountForItem(itemId, playerName)
		local normalized = playerName and playerName:lower()
		local entry = reservesData[normalized]
		if not entry then return 0 end
		for _, r in ipairs(entry.reserves or {}) do
			if r.rawID == itemId then return r.quantity or 1 end
		end
		return 0
	end

	-- UI Rendering
	function Reserves:RefreshWindow()
		if not reserveListFrame or not scrollChild then return end

		for _, row in ipairs(reserveItemRows) do row:Hide() end
		twipe(reserveItemRows); twipe(rowsByItemID)

		local grouped = {}
		for _, player in pairs(reservesData) do
			for _, r in ipairs(player.reserves or {}) do
				local key = (r.source or "Unknown") .. "||" .. r.rawID .. "||" .. (r.quantity or 1)
				grouped[key] = grouped[key] or { itemId = r.rawID, quantity = r.quantity or 1, itemLink = r.itemLink, itemName = r.itemName, itemIcon = r.itemIcon, source = r.source or "Unknown", players = {} }
				tinsert(grouped[key].players, player.original)
			end
		end

		local displayList = {}
		for _, data in pairs(grouped) do tinsert(displayList, data) end
		table.sort(displayList, function(a, b)
			if a.source ~= b.source then return a.source < b.source end
			if a.itemId ~= b.itemId then return a.itemId < b.itemId end
			return a.quantity < b.quantity
		end)

		local yOffset = 0
		local seenSources = {}
		for _, entry in ipairs(displayList) do
			local source = entry.source
			if not seenSources[source] then
				seenSources[source] = true
				collapsedBossGroups[source] = collapsedBossGroups[source] == nil and false or collapsedBossGroups[source]
				yOffset = yOffset + self:CreateHeaderRow(scrollChild, source, yOffset)
			end
			if not collapsedBossGroups[source] then
				yOffset = yOffset + self:CreateReserveRow(scrollChild, entry, yOffset)
			end
		end

		scrollChild:SetHeight(yOffset); scrollFrame:SetVerticalScroll(0)
	end

	function Reserves:CreateHeaderRow(parent, source, yOffset)
		local headerBtn = CreateFrame("Button", nil, parent)
		headerBtn:SetSize(320, 24); headerBtn:SetPoint("TOPLEFT", 0, -yOffset)
		local prefix = collapsedBossGroups[source] and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
		local fullLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fullLabel:SetPoint("CENTER")
		fullLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE"); fullLabel:SetTextColor(1, 0.82, 0); fullLabel:SetText(prefix .. source)
		headerBtn:SetScript("OnClick", function() collapsedBossGroups[source] = not collapsedBossGroups[source]; self:RefreshWindow() end)
		tinsert(reserveItemRows, headerBtn)
		return 24
	end

	function Reserves:CreateReserveRow(parent, info, yOffset)
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(320, 34); row:SetPoint("TOPLEFT", 0, -yOffset); row._rawID = info.itemId

		local icon = row:CreateTexture(nil, "ARTWORK"); icon:SetSize(32, 32); icon:SetPoint("LEFT", 0, 0)
		icon:SetTexture(info.itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
		local iconBtn = CreateFrame("Button", nil, row); iconBtn:SetAllPoints(icon)
		iconBtn:SetScript("OnEnter", function()
			GameTooltip:SetOwner(iconBtn, "ANCHOR_RIGHT")
			if info.itemLink then GameTooltip:SetHyperlink(info.itemLink) else GameTooltip:SetText("Item ID: " .. info.itemId, 1, 1, 1) end
			if info.source then GameTooltip:AddLine("Dropped by: " .. info.source, 0.8, 0.8, 0.8) end
			GameTooltip:Show()
		end)
		iconBtn:SetScript("OnLeave", GameTooltip.Hide)

		local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
		nameText:SetText(info.itemLink or info.itemName or ("[Item " .. info.itemId .. "]"))
		local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		playerText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
		playerText:SetText(table.concat(info.players or {}, ", "))

		row.icon, row.iconBtn, row.nameText = icon, iconBtn, nameText
		rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
		tinsert(rowsByItemID[info.itemId], row)
		return 34
	end

	-- SR Announcement
	function Reserves:GetPlayersForItem(itemId)
		addon:Debug("DEBUG", "Getting players for itemId: %d", itemId)
		local players = {}
		for _, player in pairs(reservesData or {}) do
			for _, r in ipairs(player.reserves or {}) do
				if r.rawID == itemId then
					local qty = r.quantity or 1
					local display = qty > 1 and (player.original .. " (" .. qty .. "x)") or player.original
					tinsert(players, display)
					break
				end
			end
		end
		return players
	end

	function Reserves:FormatReservedPlayersLine(itemId)
		local list = self:GetPlayersForItem(itemId)
		addon:Debug("DEBUG", "Players for itemId %d: %s", itemId, table.concat(list, ", "))
		return #list > 0 and table.concat(list, ", ") or ""
	end
end

-- ============================================================================
-- Configuration Frame
-- ============================================================================
do
	addon.Config = {}
	local Config = addon.Config

	local localized = false
	local updateInterval = 0.1
	local defaultOptions = {
		sortAscending = false,
		useRaidWarning = true,
		announceOnWin = true,
		announceOnHold = true,
		announceOnBank = false,
		announceOnDisenchant = false,
		lootWhispers = false,
		screenReminder = true,
		ignoreStacks = false,
		showTooltips = true,
		minimapButton = true,
		countdownSimpleRaidMsg = false,
		countdownDuration = 5,
		countdownRollsBlock = true,
	}

	function LoadOptions()
		addon.options = KRT_Options
		Utils.fillTable(addon.options, defaultOptions)
		if not addon.options.useRaidWarning then addon.options.countdownSimpleRaidMsg = false end
	end

	function Config:Default()
		for k, v in pairs(defaultOptions) do KRT_Options[k] = v end
	end

	function Config:OnLoad(frame)
		configFrame = frame
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
	end

	function Config:Toggle() Utils.toggle(configFrame) end
	function Config:Hide() if configFrame and configFrame:IsShown() then configFrame:Hide() end end

	function Config:OnClick(btn)
		if not btn then return end
		local frameName = btn:GetParent():GetName()
		local optionName = gsub(btn:GetName(), frameName, "")
		local value
		if optionName == "countdownDuration" then
			value = btn:GetValue()
			_G[btn:GetName() .. "Text"]:SetText(value)
		else
			value = btn:GetChecked()
			if optionName == "minimapButton" then addon:ToggleMinimapButton() end
		end
		KRT_Options[optionName] = value
		TriggerEvent("Config" .. optionName, value)
	end

	function Config:UpdateUIFrame(self, elapsed)
		if not configFrame then return end
		local frameName = configFrame:GetName()
		if not localized then
			_G[frameName .. "Title"]:SetText(format(titleString, SETTINGS))
			_G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
			_G[frameName .. "DefaultsBtn"]:SetScript("OnClick", self.Default)
			localized = true
		end
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			for option, value in pairs(addon.options) do
				local widget = _G[frameName .. option]
				if widget then
					if widget:GetObjectType() == "CheckButton" then
						widget:SetChecked(value)
					elseif widget:GetObjectType() == "Slider" then
						widget:SetValue(value)
						_G[widget:GetName() .. "Text"]:SetText(value)
					end
				end
			end
			local useRaidWarningBtn = _G[frameName .. "useRaidWarning"]
			local simpleMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
			local simpleMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]
			if useRaidWarningBtn and simpleMsgBtn then
				Utils.enableDisable(simpleMsgBtn, useRaidWarningBtn:GetChecked())
				simpleMsgStr:SetTextColor(useRaidWarningBtn:GetChecked() and HIGHLIGHT_FONT_COLOR.r or 0.5, useRaidWarningBtn:GetChecked() and HIGHLIGHT_FONT_COLOR.g or 0.5, useRaidWarningBtn:GetChecked() and HIGHLIGHT_FONT_COLOR.b or 0.5)
			end
		end
	end
end

-- ============================================================================
-- Warnings Frame
-- ============================================================================
do
	addon.Warnings = {}
	local Warnings = addon.Warnings

	local localized, fetched, isEdit = false, false, false
	local updateInterval = 0.1
	local selectedID, tempSelectedID
	local tempName, tempContent

	-- Forward declarations
	local LocalizeUIFrame, UpdateUIFrame, FetchWarnings, SaveWarning

	function Warnings:OnLoad(frame)
		if not frame then return end
		warningsFrame = frame
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", function(...) UpdateUIFrame(...) end)
	end

	function Warnings:Update() return FetchWarnings() end
	function Warnings:Toggle() Utils.toggle(warningsFrame) end
	function Warnings:Hide() if warningsFrame and warningsFrame:IsShown() then warningsFrame:Hide() end end

	function Warnings:Select(btn)
		if not btn or isEdit then return end
		local btnName = btn:GetName()
		local warningID = tonumber(_G[btnName .. "ID"]:GetText())
		if not KRT_Warnings[warningID] then return end

		if IsControlKeyDown() then
			selectedID = nil
			tempSelectedID = warningID
			return self:Announce(tempSelectedID)
		end
		selectedID = (warningID ~= selectedID) and warningID or nil
	end

	function Warnings:Edit()
		local frameName = warningsFrame:GetName()
		if selectedID then
			local warning = KRT_Warnings[selectedID]
			if not warning then selectedID = nil; return end

			if not isEdit and (tempName == "" and tempContent == "") then
				_G[frameName .. "Name"]:SetText(warning.name)
				_G[frameName .. "Name"]:SetFocus()
				_G[frameName .. "Content"]:SetText(warning.content)
				isEdit = true
				return
			end
		end
		local wName = _G[frameName .. "Name"]:GetText()
		local wContent = _G[frameName .. "Content"]:GetText()
		return SaveWarning(wContent, wName, selectedID)
	end

	function Warnings:Delete()
		if not selectedID then return end
		local frameName = warningsFrame:GetName()
		local oldWarnings = {}
		for i, w in ipairs(KRT_Warnings) do
			if _G[frameName .. "WarningBtn" .. i] then _G[frameName .. "WarningBtn" .. i]:Hide() end
			if i ~= selectedID then tinsert(oldWarnings, w) end
		end
		twipe(KRT_Warnings)
		KRT_Warnings = oldWarnings

		local count = #KRT_Warnings
		if count == 0 then selectedID = nil
		elseif selectedID > count then selectedID = selectedID - 1 end
		FetchWarnings()
	end

	function Warnings:Announce(warningID)
		if not KRT_Warnings then return end
		warningID = warningID or selectedID or tempSelectedID
		if not warningID or warningID <= 0 or not KRT_Warnings[warningID] then return end

		tempSelectedID = nil -- Always clear temporary selected id
		return addon:Announce(KRT_Warnings[warningID].content)
	end

	function Warnings:Cancel()
		local frameName = warningsFrame:GetName()
		_G[frameName .. "Name"]:SetText(""); _G[frameName .. "Name"]:ClearFocus()
		_G[frameName .. "Content"]:SetText(""); _G[frameName .. "Content"]:ClearFocus()
		selectedID, tempSelectedID, isEdit = nil, nil, false
	end

	LocalizeUIFrame = function()
		local frameName = warningsFrame:GetName()
		if localized or not frameName then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName .. "MessageStr"]:SetText(L.StrMessage)
			_G[frameName .. "EditBtn"]:SetText(SAVE)
			_G[frameName .. "OutputName"]:SetText(L.StrWarningsHelp)
		end
		_G[frameName .. "Title"]:SetText(format(titleString, RAID_WARNING))
		_G[frameName .. "Name"]:SetScript("OnEscapePressed", Warnings.Cancel)
		_G[frameName .. "Content"]:SetScript("OnEscapePressed", Warnings.Cancel)
		_G[frameName .. "Name"]:SetScript("OnEnterPressed", Warnings.Edit)
		_G[frameName .. "Content"]:SetScript("OnEnterPressed", Warnings.Edit)
		localized = true
	end

	UpdateUIFrame = function(self, elapsed)
		if not warningsFrame then return end
		local frameName = warningsFrame:GetName()
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not fetched then FetchWarnings() end
			if #KRT_Warnings > 0 then
				for i = 1, #KRT_Warnings do
					local btn = _G[frameName .. "WarningBtn" .. i]
					if btn then
						if selectedID == i then
							btn:LockHighlight()
							_G[frameName .. "OutputName"]:SetText(KRT_Warnings[selectedID].name)
							_G[frameName .. "OutputContent"]:SetText(KRT_Warnings[selectedID].content)
							_G[frameName .. "OutputContent"]:SetTextColor(1, 1, 1)
						else
							btn:UnlockHighlight()
						end
					end
				end
			end
			if not selectedID then
				_G[frameName .. "OutputName"]:SetText(L.StrWarningsHelp)
				_G[frameName .. "OutputContent"]:SetText(L.StrWarningsHelp)
				_G[frameName .. "OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
			end
			tempName = _G[frameName .. "Name"]:GetText()
			tempContent = _G[frameName .. "Content"]:GetText()
			local hasInput = (tempName ~= "" or tempContent ~= "")
			Utils.enableDisable(_G[frameName .. "EditBtn"], hasInput or selectedID)
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID)
			Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID)
			Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, hasInput or not selectedID)
		end
	end

	SaveWarning = function(wContent, wName, wID)
		wID = tonumber(wID) or 0
		wName = tostring(wName):trim()
		wContent = tostring(wContent):trim()
		if wName == "" then wName = (isEdit and wID > 0) and wID or (#KRT_Warnings + 1) end
		if wContent == "" then addon:PrintError(L.StrWarningsError); return end

		if isEdit and wID > 0 and KRT_Warnings[wID] then
			KRT_Warnings[wID].name = wName
			KRT_Warnings[wID].content = wContent
			isEdit = false
		else
			tinsert(KRT_Warnings, { name = wName, content = wContent })
		end
		Warnings:Cancel()
		Warnings:Update()
	end

	FetchWarnings = function()
		if not warningsFrame then return end
		local frameName = warningsFrame:GetName()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		for i, w in ipairs(KRT_Warnings) do
			local btnName = frameName .. "WarningBtn" .. i
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTWarningButtonTemplate")
			btn:Show()
			_G[btnName .. "ID"]:SetText(i)
			_G[btnName .. "Name"]:SetText(w.name)
			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end
end

-- ============================================================================
-- MS Changes Frame
-- ============================================================================
do
	addon.Changes = {}
	local Changes = addon.Changes

	local localized, fetched, isAdd, isEdit = false, false, false, false
	local updateInterval = 0.1
	local changesTable = {}
	local selectedPlayerName, tempSelectedPlayerName

	-- Forward declarations
	local LocalizeUIFrame, UpdateUIFrame, FetchChanges, SaveChanges, CancelChanges, InitChangesTable

	function Changes:OnLoad(frame)
		if not frame then return end
		changesFrame = frame
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", function(...) UpdateUIFrame(...) end)
	end

	function Changes:Toggle()
		CancelChanges()
		Utils.toggle(changesFrame)
	end

	function Changes:Hide()
		if changesFrame and changesFrame:IsShown() then
			CancelChanges()
			changesFrame:Hide()
		end
	end

	function Changes:Clear()
		if not KRT_CurrentRaid or not changesTable then return end
		local frameName = changesFrame:GetName()
		for name, _ in pairs(changesTable) do
			changesTable[name] = nil
			if _G[frameName .. "PlayerBtn" .. name] then
				_G[frameName .. "PlayerBtn" .. name]:Hide()
			end
		end
		CancelChanges()
		fetched = false
	end

	function Changes:Select(btn)
		if not btn then return end
		local frameName = changesFrame:GetName()
		local playerName = _G[btn:GetName() .. "Name"]:GetText()
		if not playerName then return end

		-- Ensure player is valid and has a change entry
		local found, resolvedName = addon.Raid:CheckPlayer(playerName)
		if not found or not changesTable[resolvedName] then
			if _G[frameName .. "PlayerBtn" .. playerName] then
				_G[frameName .. "PlayerBtn" .. playerName]:Hide()
			end
			fetched = false
			return
		end

		if IsControlKeyDown() then
			tempSelectedPlayerName = (resolvedName ~= selectedPlayerName) and resolvedName or nil
			self:Announce()
			return
		end

		selectedPlayerName = (resolvedName ~= selectedPlayerName) and resolvedName or nil
		isAdd = false
		isEdit = false
	end

	function Changes:Add(btn)
		if not KRT_CurrentRaid or not btn then return end
		local frameName = changesFrame:GetName()
		if not selectedPlayerName then
			btn:Hide()
			_G[frameName .. "Name"]:Show()
			_G[frameName .. "Name"]:SetFocus()
			isAdd = true
		elseif changesTable[selectedPlayerName] then
			changesTable[selectedPlayerName] = nil
			if _G[frameName .. "PlayerBtn" .. selectedPlayerName] then
				_G[frameName .. "PlayerBtn" .. selectedPlayerName]:Hide()
			end
			CancelChanges()
			fetched = false
		end
	end

	function Changes:Edit()
		if not KRT_CurrentRaid then return end
		local frameName = changesFrame:GetName()
		if not selectedPlayerName or isEdit then
			local name = _G[frameName .. "Name"]:GetText()
			local spec = _G[frameName .. "Spec"]:GetText()
			SaveChanges(name, spec)
		elseif changesTable[selectedPlayerName] then
			_G[frameName .. "Name"]:SetText(selectedPlayerName)
			_G[frameName .. "Spec"]:SetText(changesTable[selectedPlayerName])
			_G[frameName .. "Spec"]:Show()
			_G[frameName .. "Spec"]:SetFocus()
			isAdd = false
			isEdit = true
		end
	end

	function Changes:Delete(name)
		if not KRT_CurrentRaid or not name then return end
		local raidChanges = KRT_Raids[KRT_CurrentRaid] and KRT_Raids[KRT_CurrentRaid].changes
		if raidChanges then raidChanges[name] = nil end
		if changesFrame and _G[changesFrame:GetName() .. "PlayerBtn" .. name] then
			_G[changesFrame:GetName() .. "PlayerBtn" .. name]:Hide()
		end
	end

	addon:RegisterCallback("RaidLeave", function(_, name)
		Changes:Delete(name)
		CancelChanges()
	end)

	function Changes:Demand()
		if not KRT_CurrentRaid then return end
		addon:Announce(L.StrChangesDemand)
	end

	function Changes:Announce()
		if not KRT_CurrentRaid then return end
		if not fetched or not next(changesTable) then
			InitChangesTable()
			FetchChanges()
		end

		local count = Utils.tableLen(changesTable)
		local msg
		if count == 0 then
			if tempSelectedPlayerName then tempSelectedPlayerName = nil; return end
			msg = L.StrChangesAnnounceNone
		elseif selectedPlayerName or tempSelectedPlayerName then
			local name = tempSelectedPlayerName or selectedPlayerName
			if tempSelectedPlayerName then tempSelectedPlayerName = nil end
			if not changesTable[name] then return end
			msg = format(L.StrChangesAnnounceOne, name, changesTable[name])
		else
			local announcements = {}
			for name, spec in pairs(changesTable) do
				tinsert(announcements, name .. "=" .. spec)
			end
			msg = L.StrChangesAnnounce .. table.concat(announcements, " / ")
		end
		addon:Announce(msg)
	end

	LocalizeUIFrame = function()
		if localized or not changesFrame then return end
		local frameName = changesFrame:GetName()
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

	UpdateUIFrame = function(self, elapsed)
		if not changesFrame then return end
		LocalizeUIFrame()
		local frameName = changesFrame:GetName()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not fetched then
				InitChangesTable()
				FetchChanges()
			end
			local count = Utils.tableLen(changesTable)
			if count > 0 then
				for name, _ in pairs(changesTable) do
					local btn = _G[frameName .. "PlayerBtn" .. name]
					if btn then
						Utils.toggleHighlight(btn, selectedPlayerName == name)
					end
				end
			else
				tempSelectedPlayerName, selectedPlayerName = nil, nil
			end

			local showInputs = isEdit or isAdd
			Utils.showHide(_G[frameName .. "Name"], showInputs)
			Utils.showHide(_G[frameName .. "Spec"], showInputs)
			Utils.enableDisable(_G[frameName .. "EditBtn"], selectedPlayerName or showInputs)
			Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, isAdd or (selectedPlayerName and isEdit))
			Utils.setText(_G[frameName .. "AddBtn"], ADD, DELETE, not (selectedPlayerName or isEdit or isAdd))
			Utils.showHide(_G[frameName .. "AddBtn"], not showInputs)
			Utils.enableDisable(_G[frameName .. "ClearBtn"], count > 0)
			Utils.enableDisable(_G[frameName .. "AnnounceBtn"], count > 0)
			Utils.enableDisable(_G[frameName .. "AddBtn"], KRT_CurrentRaid)
			Utils.enableDisable(_G[frameName .. "DemandBtn"], KRT_CurrentRaid)
		end
	end

	InitChangesTable = function()
		addon:Debug("DEBUG", "Initializing changes table.")
		changesTable = KRT_CurrentRaid and KRT_Raids[KRT_CurrentRaid].changes or {}
	end

	FetchChanges = function()
		if not KRT_CurrentRaid or not changesFrame then return end
		addon:Debug("DEBUG", "Fetching all changes.")
		local frameName = changesFrame:GetName()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())

		for name, spec in pairs(changesTable) do
			local btnName = frameName .. "PlayerBtn" .. name
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTChangesButtonTemplate")
			btn:Show()
			local nameText = _G[btnName .. "Name"]
			nameText:SetText(name)
			local r, g, b = addon:GetClassColor(addon:GetPlayerClass(name))
			nameText:SetVertexColor(r, g, b)
			_G[btnName .. "Spec"]:SetText(spec)
			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end

	SaveChanges = function(name, spec)
		if not KRT_CurrentRaid or not name then return end
		name = ucfirst(name:trim())
		spec = ucfirst(spec:trim())
		local found, resolvedName = addon.Raid:CheckPlayer(name)
		if not found then
			addon:PrintError(format((name == "" and L.ErrChangesNoPlayer or L.ErrCannotFindPlayer), name))
			return
		end
		changesTable[resolvedName] = (spec == "") and nil or spec
		CancelChanges()
		fetched = false
	end

	CancelChanges = function()
		isAdd, isEdit = false, false
		selectedPlayerName, tempSelectedPlayerName = nil, nil
		if changesFrame then
			local frameName = changesFrame:GetName()
			_G[frameName .. "Name"]:SetText(""); _G[frameName .. "Name"]:ClearFocus()
			_G[frameName .. "Spec"]:SetText(""); _G[frameName .. "Spec"]:ClearFocus()
		end
	end
end

-- ============================================================================
-- LFM Spammer Frame
-- ============================================================================
do
	addon.Spammer = {}
	local Spammer = addon.Spammer

	local spamFrame = CreateFrame("Frame")
	local localized, loaded, ticking, paused = false, false, false, false
	local updateInterval = 0.05
	local tickStart, tickPos = 0, 0
	local duration = 60
	local finalOutput = ""
	local channels = {}

	local FindAchievement, LocalizeUIFrame, UpdateUIFrame

	function Spammer:OnLoad(frame)
		if not frame then return end
		spammerFrame = frame
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", function(...) UpdateUIFrame(...) end)
	end

	function Spammer:Toggle() Utils.toggle(spammerFrame) end
	function Spammer:Hide() if spammerFrame and spammerFrame:IsShown() then spammerFrame:Hide() end end

	function Spammer:Save(box)
		if not box then return end
		local frameName = spammerFrame:GetName()
		local target = gsub(box:GetName(), frameName, "")
		if find(target, "Chat") then
			KRT_Spammer.Channels = KRT_Spammer.Channels or {}
			local channel = gsub(target, "Chat", "")
			if box:GetChecked() then
				if not Utils.checkEntry(KRT_Spammer.Channels, channel) then tinsert(KRT_Spammer.Channels, channel) end
			else
				Utils.removeEntry(KRT_Spammer.Channels, channel)
			end
		else
			local value = box:GetText():trim()
			KRT_Spammer[target] = (value == "") and nil or value
			box:ClearFocus()
			if ticking and paused then paused = false end
		end
		loaded = false
	end

	function Spammer:Start()
		if strlen(finalOutput) > 3 and strlen(finalOutput) <= 255 then
			if paused then
				paused = false
			elseif ticking then
				ticking = false
			else
				tickStart = GetTime()
				duration = tonumber(duration)
				tickPos = (duration >= 1 and duration or 60) + 1
				ticking = true
			end
		end
	end

	function Spammer:Stop()
		if spammerFrame then _G[spammerFrame:GetName() .. "Tick"]:SetText(duration or 0) end
		ticking, paused = false, false
	end

	function Spammer:Pause() paused = true end

	function Spammer:Spam()
		if strlen(finalOutput) > 255 then
			addon:PrintError(L.StrSpammerErrLength); ticking = false; return
		end
		if #channels == 0 then
			SendChatMessage(finalOutput, "YELL")
			return
		end
		for _, channel in ipairs(channels) do
			if channel == "Guild" or channel == "Yell" then
				SendChatMessage(finalOutput, upper(channel))
			else
				SendChatMessage(finalOutput, "CHANNEL", nil, channel)
			end
		end
	end

	function Spammer:Tab(nextBox, prevBox)
		local frameName = spammerFrame:GetName()
		local target
		if IsShiftKeyDown() and _G[frameName .. prevBox] then
			target = _G[frameName .. prevBox]
		elseif _G[frameName .. nextBox] then
			target = _G[frameName .. nextBox]
		end
		if target then target:SetFocus() end
	end

	function Spammer:Clear()
		for k, _ in pairs(KRT_Spammer) do
			if k ~= "Channels" and k ~= "Duration" then KRT_Spammer[k] = nil end
		end
		finalOutput = ""; self:Stop()
		local frameName = spammerFrame:GetName()
		local fields = { "Name", "Tank", "TankClass", "Healer", "HealerClass", "Melee", "MeleeClass", "Ranged", "RangedClass", "Message" }
		for _, field in ipairs(fields) do
			if _G[frameName .. field] then _G[frameName .. field]:SetText("") end
		end
	end

	FindAchievement = function(input)
		local text = input:trim()
		if text and text ~= "" and find(text, "%{%d+%}") then
			local achievementID = strmatch(text, "{ (%d+)}")
			local link = GetAchievementLink(achievementID) or "[" .. achievementID .. "]"
			text = gsub(text, "{%d+}", link)
		end
		return text
	end

	LocalizeUIFrame = function()
		local frameName = spammerFrame:GetName()
		if localized or not frameName then return end
		_G[frameName .. "Title"]:SetText(format(titleString, L.StrSpammer))
		_G[frameName .. "StartBtn"]:SetScript("OnClick", Spammer.Start)
		local durationBox = _G[frameName .. "Duration"]
		durationBox.tooltip_title = AUCTION_DURATION
		addon:SetTooltip(durationBox, L.StrSpammerDurationHelp)
		local messageBox = _G[frameName .. "Message"]
		messageBox.tooltip_title = L.StrMessage
		addon:SetTooltip(messageBox, { L.StrSpammerMessageHelp1, L.StrSpammerMessageHelp2, L.StrSpammerMessageHelp3 })
		localized = true
	end

	UpdateUIFrame = function(self, elapsed)
		if not spammerFrame then return end
		local frameName = spammerFrame:GetName()
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not loaded then
				for k, v in pairs(KRT_Spammer) do
					if k == "Channels" then
						for _, c in ipairs(v) do _G[frameName .. "Chat" .. c]:SetChecked(true) end
					elseif _G[frameName .. k] then
						_G[frameName .. k]:SetText(v)
					end
				end
				loaded = true
			end

			if spammerFrame:IsShown() then
				channels = KRT_Spammer.Channels or {}
				local name = _G[frameName .. "Name"]:GetText():trim()
				local tank = tonumber(_G[frameName .. "Tank"]:GetText()) or 0
				local tankClass = _G[frameName .. "TankClass"]:GetText():trim()
				local healer = tonumber(_G[frameName .. "Healer"]:GetText()) or 0
				local healerClass = _G[frameName .. "HealerClass"]:GetText():trim()
				local melee = tonumber(_G[frameName .. "Melee"]:GetText()) or 0
				local meleeClass = _G[frameName .. "MeleeClass"]:GetText():trim()
				local ranged = tonumber(_G[frameName .. "Ranged"]:GetText()) or 0
				local rangedClass = _G[frameName .. "RangedClass"]:GetText():trim()
				local message = _G[frameName .. "Message"]:GetText():trim()

				local parts = { "LFM" }
				if name ~= "" then tinsert(parts, name) end
				local needs = {}
				if tank > 0 then tinsert(needs, tank .. " Tank" .. (tankClass ~= "" and " (" .. tankClass .. ")" or "")) end
				if healer > 0 then tinsert(needs, healer .. " Healer" .. (healerClass ~= "" and " (" .. healerClass .. ")" or "")) end
				if melee > 0 then tinsert(needs, melee .. " Melee" .. (meleeClass ~= "" and " (" .. meleeClass .. ")" or "")) end
				if ranged > 0 then tinsert(needs, ranged .. " Ranged" .. (rangedClass ~= "" and " (" .. rangedClass .. ")" or "")) end

				if #needs > 0 then tinsert(parts, "- Need " .. table.concat(needs, ", ")) end
				if message ~= "" then tinsert(parts, "- " .. FindAchievement(message)) end

				local temp = table.concat(parts, " ")
				if temp ~= "LFM" then
					local total = tank + healer + melee + ranged
					local max = name:find("25") and 25 or 10
					temp = temp .. " (" .. max - total .. "/" .. max .. ")"
					finalOutput = temp
				else
					finalOutput = ""
				end

				_G[frameName .. "Output"]:SetText(finalOutput)
				local len = strlen(finalOutput)
				_G[frameName .. "Length"]:SetText(len .. "/255")
				_G[frameName .. "Length"]:SetTextColor(len > 255 and 1 or 0, len > 255 and 0 or 1, 0)

				duration = _G[frameName .. "Duration"]:GetText()
				if duration == "" then duration = 60; _G[frameName .. "Duration"]:SetText(duration) end
				Utils.setText(_G[frameName .. "StartBtn"], paused and L.BtnResume or L.BtnStop, START, ticking)
				Utils.enableDisable(_G[frameName .. "StartBtn"], len > 3 and len <= 255)
			end

			if ticking and not paused then
				local tick = ceil(duration - GetTime() + tickStart)
				_G[frameName .. "Tick"]:SetText(tick > 0 and tick or "")
				if tickPos > tick then tickPos = tick end -- Resync on lag
				if tickPos <= 0 then
					self:Spam()
					ticking = false
					self:Start()
				end
			end
		end
	end

	spamFrame:SetScript("OnUpdate", function(self, elapsed)
		if spammerFrame then UpdateUIFrame(spammerFrame, elapsed) end
	end)
end

-- ============================================================================
-- Tooltip System
-- ============================================================================
do
	local colors = HIGHLIGHT_FONT_COLOR

	local function ShowTooltip(frame)
		if not frame.tooltip_anchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, frame)
		else
			GameTooltip:SetOwner(frame, frame.tooltip_anchor)
		end

		if frame.tooltip_title then GameTooltip:SetText(frame.tooltip_title) end

		if frame.tooltip_text then
			if type(frame.tooltip_text) == "string" then
				GameTooltip:AddLine(frame.tooltip_text, colors.r, colors.g, colors.b, true)
			elseif type(frame.tooltip_text) == "table" then
				for _, line in ipairs(frame.tooltip_text) do
					GameTooltip:AddLine(line, colors.r, colors.g, colors.b, true)
				end
			end
		end

		if frame.tooltip_item then GameTooltip:SetHyperlink(frame.tooltip_item) end
		GameTooltip:Show()
	end

	function addon:SetTooltip(frame, text, anchor, title)
		if not frame then return end
		frame.tooltip_text = text or frame.tooltip_text
		frame.tooltip_anchor = anchor or frame.tooltip_anchor
		frame.tooltip_title = title or frame.tooltip_title
		if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then return end
		frame:SetScript("OnEnter", ShowTooltip)
		frame:SetScript("OnLeave", GameTooltip.Hide)
	end
end

-- ============================================================================
-- Loot History Frame (Logger)
-- ============================================================================
do
	addon.Logger = {}
	local Logger = addon.Logger

	local localized = false
	local updateInterval = 0.05

	Logger.selectedRaid, Logger.selectedBoss, Logger.selectedPlayer, Logger.selectedBossPlayer, Logger.selectedItem = nil, nil, nil, nil, nil

	function Logger:OnLoad(frame)
		if not frame then return end
		loggerFrame = frame
		local frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
		frame:SetScript("OnHide", function()
			self.selectedRaid = KRT_CurrentRaid
			self.selectedBoss, self.selectedPlayer, self.selectedItem = nil, nil, nil
		end)
	end

	function Logger:Toggle() Utils.toggle(loggerFrame) end
	function Logger:Hide() if loggerFrame and loggerFrame:IsShown() then self:Toggle() end end

	function Logger:UpdateUIFrame(self, elapsed)
		local frameName = loggerFrame:GetName()
		if not localized then
			_G[frameName .. "Title"]:SetText(format(titleString, L.StrLootHistory))
			localized = true
		end
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not self.selectedRaid then
				self.selectedRaid = KRT_CurrentRaid
			end
		end
	end

	function Logger:SelectRaid(btn)
		if not btn then return end
		local raidID = btn:GetID()
		self.selectedRaid = (raidID ~= self.selectedRaid) and raidID or nil
		TriggerEvent("LoggerSelectRaid", raidID)
	end

	function Logger:SelectBoss(btn)
		if not btn then return end
		local bossID = btn:GetID()
		self.selectedBoss = (bossID ~= self.selectedBoss) and bossID or nil
		TriggerEvent("LoggerSelectBoss", bossID)
	end

	function Logger:SelectBossPlayer(btn)
		if not btn then return end
		local playerID = btn:GetID()
		self.selectedBossPlayer = (playerID ~= self.selectedBossPlayer) and playerID or nil
		TriggerEvent("LoggerSelectBossPlayer", playerID)
	end

	function Logger:SelectPlayer(btn)
		if not btn then return end
		local playerID = btn:GetID()
		self.selectedPlayer = (playerID ~= self.selectedPlayer) and playerID or nil
		TriggerEvent("LoggerSelectPlayer", playerID)
	end

	do -- Item Selection & Context Menu
		local itemMenu
		local function OpenItemMenu()
			if not Logger.selectedItem then return end
			itemMenu = itemMenu or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")
			local menuList = {
				{ text = L.StrEditItemLooter, func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER") end },
				{ text = L.StrEditItemRollType, func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_ROLL") end },
				{ text = L.StrEditItemRollValue, func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE") end },
			}
			EasyMenu(menuList, itemMenu, "cursor", 0, 0, "MENU")
		end

		function Logger:SelectItem(btn, button)
			if not btn then return end
			local itemID = btn:GetID()
			if button == "LeftButton" then
				self.selectedItem = (itemID ~= self.selectedItem) and itemID or nil
				TriggerEvent("LoggerSelectItem", itemID)
			elseif button == "RightButton" then
				self.selectedItem = itemID
				OpenItemMenu()
			end
		end

		StaticPopupDialogs["KRTLOGGER_ITEM_EDIT_WINNER"] = {
			text = L.StrEditItemLooterHelp, button1 = SAVE, button2 = CANCEL, hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
			OnShow = function(self) self.raidId, self.itemId = Logger.selectedRaid, Logger.selectedItem end,
			OnAccept = function(self)
				local name = self.editBox:GetText():trim()
				if name ~= "" and self.raidId and KRT_Raids[self.raidId] then
					for _, player in ipairs(KRT_Raids[self.raidId].players) do
						if name:lower() == player.name:lower() then
							addon:Log(self.itemId, player.name); addon.Logger.Loot:Fetch(); break
						end
					end
				end
			end,
		}
		StaticPopupDialogs["KRTLOGGER_ITEM_EDIT_ROLL"] = {
			text = L.StrEditItemRollTypeHelp, button1 = SAVE, button2 = CANCEL, hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
			OnShow = function(self) self.itemId = Logger.selectedItem end,
			OnAccept = function(self)
				local rollType = self.editBox:GetNumber()
				if rollType > 0 and rollType <= 7 then addon:Log(self.itemId, nil, rollType); addon.Logger.Loot:Fetch() end
			end,
		}
		StaticPopupDialogs["KRTLOGGER_ITEM_EDIT_VALUE"] = {
			text = L.StrEditItemRollValueHelp, button1 = SAVE, button2 = CANCEL, hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
			OnShow = function(self) self.itemId = Logger.selectedItem end,
			OnAccept = function(self)
				local rollValue = self.editBox:GetNumber()
				if rollValue then addon:Log(self.itemId, nil, nil, rollValue); addon.Logger.Loot:Fetch() end
			end,
		}
	end

	addon:RegisterCallback("LoggerSelectRaid", function()
		Logger.selectedBoss, Logger.selectedPlayer, Logger.selectedItem = nil, nil, nil
	end)
end

-- ============================================================================
-- Logger: Raids List
-- ============================================================================
do
	addon.Logger.Raids = {}
	local Raids = addon.Logger.Raids

	local raidsFrame, frameName
	local localized, fetched = false, false
	local updateInterval = 0.075
	local raidsTable = {}

	function Raids:OnLoad(frame)
		if not frame then return end
		raidsFrame = frame
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
	end

	function Raids:UpdateUIFrame(self, elapsed)
		if not raidsFrame then return end
		if not localized then
			_G[frameName .. "Title"]:SetText(L.StrRaidsList)
			_G[frameName .. "HeaderDate"]:SetText(L.StrDate)
			_G[frameName .. "HeaderSize"]:SetText(L.StrSize)
			_G[frameName .. "CurrentBtn"]:SetText(L.StrSetCurrent)
			_G[frameName .. "ExportBtn"]:SetText(L.BtnExport)
			_G[frameName .. "ExportBtn"]:Disable() -- FIXME: Re-enable when export is implemented
			addon:SetTooltip(_G[frameName .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)
			localized = true
		end

		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			local selectedRaidID = addon.Logger.selectedRaid
			if not fetched then
				self:InitRaidsList()
				self:Fetch()
			end

			for _, raidInfo in ipairs(raidsTable) do
				local btn = _G[frameName .. "RaidBtn" .. raidInfo.id]
				if btn then
					Utils.toggleHighlight(btn, selectedRaidID and selectedRaidID == raidInfo.id)
				end
			end

			local canSetCurrent = selectedRaidID and
				selectedRaidID ~= KRT_CurrentRaid and
				not addon.Raid:Expired(selectedRaidID) and
				KRT_Raids[selectedRaidID] and
				addon:GetRaidSize() == KRT_Raids[selectedRaidID].size
			Utils.enableDisable(_G[frameName .. "CurrentBtn"], canSetCurrent)
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedRaidID and selectedRaidID ~= KRT_CurrentRaid)
		end
	end

	function Raids:InitRaidsList()
		twipe(raidsTable)
		for i, r in ipairs(KRT_Raids) do
			tinsert(raidsTable, { id = i, zone = r.zone, size = r.size, date = r.startTime })
		end
	end

	function Raids:Fetch()
		if not frameName then return end
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())

		-- Hide all existing buttons before redrawing
		for i = 1, #KRT_Raids do
			if _G[frameName .. "RaidBtn" .. i] then _G[frameName .. "RaidBtn" .. i]:Hide() end
		end

		for i = #raidsTable, 1, -1 do
			local raid = raidsTable[i]
			local btnName = frameName .. "RaidBtn" .. raid.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerRaidButton")
			btn:SetID(raid.id)
			btn:Show()
			_G[btnName .. "ID"]:SetText(raid.id)
			_G[btnName .. "Date"]:SetText(date("%d/%m/%Y %H:%M", raid.date))
			_G[btnName .. "Zone"]:SetText(raid.zone)
			_G[btnName .. "Size"]:SetText(raid.size)
			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end

	function Raids:SetCurrent()
		local selectedRaidID = addon.Logger.selectedRaid
		if not selectedRaidID or not KRT_Raids[selectedRaidID] then return end
		if KRT_Raids[selectedRaidID].size ~= addon:GetRaidSize() then
			addon:PrintError(L.ErrCannotSetCurrentRaidSize)
			return
		end
		if addon.Raid:Expired(selectedRaidID) then
			addon:PrintError(L.ErrCannotSetCurrentRaidReset)
			return
		end
		KRT_CurrentRaid = selectedRaidID
	end

	do -- Delete Raid Logic
		local function DeleteRaid()
			local selectedRaidID = addon.Logger.selectedRaid
			if selectedRaidID and KRT_Raids[selectedRaidID] then
				if KRT_CurrentRaid and KRT_CurrentRaid == selectedRaidID then
					addon:PrintError(L.ErrCannotDeleteRaid)
					return
				end
				tremove(KRT_Raids, selectedRaidID)
				if KRT_CurrentRaid and KRT_CurrentRaid > selectedRaidID then
					KRT_CurrentRaid = KRT_CurrentRaid - 1
				end
				addon.Logger.selectedRaid = nil
				fetched = false
			end
		end

		function Raids:Delete()
			if addon.Logger.selectedRaid then
				StaticPopup_Show("KRTLOGGER_DELETE_RAID")
			end
		end

		StaticPopupDialogs["KRTLOGGER_DELETE_RAID"] = {
			text = L.StrConfirmDeleteRaid, button1 = L.BtnOK, button2 = CANCEL,
			OnAccept = DeleteRaid, timeout = 0, whileDead = 1, hideOnEscape = 1,
		}
	end

	do -- Sorting Logic
		local ascending = false
		local sortTypes = {
			id = function(a, b) return ascending and (a.id < b.id) or (a.id > b.id) end,
			date = function(a, b) return ascending and (a.date < b.date) or (a.date > b.date) end,
			zone = function(a, b) return ascending and (a.zone < b.zone) or (a.zone > b.zone) end,
			size = function(a, b) return ascending and (a.size < b.size) or (a.size > b.size) end,
		}

		function Raids:Sort(sortType)
			if not sortTypes[sortType] then return end
			ascending = not ascending
			table.sort(raidsTable, sortTypes[sortType])
			self:Fetch()
		end
	end

	addon:RegisterCallback("RaidCreate", function(_, raidNum)
		addon.Logger.selectedRaid = tonumber(raidNum)
		fetched = false
	end)
end

-- ============================================================================
-- Logger: Boss List
-- ============================================================================
do
	addon.Logger.Boss = {}
	local Boss = addon.Logger.Boss

	local bossesFrame, frameName
	local localized, fetched = false, false
	local updateInterval = 0.075
	local bossTable = {}

	function Boss:OnLoad(frame)
		if not frame then return end
		bossesFrame = frame
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
	end

	function Boss:UpdateUIFrame(self, elapsed)
		if not bossesFrame then return end
		if not localized then
			_G[frameName .. "Title"]:SetText(L.StrBosses)
			_G[frameName .. "HeaderTime"]:SetText(L.StrTime)
			localized = true
		end

		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			local selectedRaidID = addon.Logger.selectedRaid
			local selectedBossID = addon.Logger.selectedBoss
			if not fetched then
				self:InitBossList()
				self:Fetch()
			end

			for _, bossInfo in ipairs(bossTable) do
				local btn = _G[frameName .. "BossBtn" .. bossInfo.id]
				if btn then
					Utils.toggleHighlight(btn, selectedBossID and selectedBossID == bossInfo.id)
				end
			end
			Utils.enableDisable(_G[frameName .. "AddBtn"], selectedRaidID)
			Utils.enableDisable(_G[frameName .. "EditBtn"], selectedBossID)
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedBossID)
		end
	end

	function Boss:InitBossList()
		bossTable = addon.Raid:GetBosses(addon.Logger.selectedRaid)
		table.sort(bossTable, function(a, b) return a.id > b.id end)
	end

	function Boss:Fetch()
		if not frameName then return end
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())

		-- Hide all existing buttons before redrawing
		for i = 1, 50 do if _G[frameName .. "BossBtn" .. i] then _G[frameName .. "BossBtn" .. i]:Hide() end end

		for _, boss in ipairs(bossTable) do
			local btnName = frameName .. "BossBtn" .. boss.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerBossButton")
			btn:SetID(boss.id)
			btn:Show()
			_G[btnName .. "ID"]:SetText(boss.id)
			_G[btnName .. "Name"]:SetText(boss.name)
			_G[btnName .. "Time"]:SetText(date("%H:%M", boss.time))
			_G[btnName .. "Mode"]:SetText(boss.mode)
			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end

	function Boss:Add() addon.Logger.BossBox:Toggle() end
	function Boss:Edit() if addon.Logger.selectedBoss then addon.Logger.BossBox:Fill() end end

	do -- Delete Boss Logic
		local function DeleteBoss()
			local selectedRaidID = addon.Logger.selectedRaid
			local selectedBossID = addon.Logger.selectedBoss
			if not selectedRaidID or not selectedBossID then return end

			local raid = KRT_Raids[selectedRaidID]
			if not raid or not raid.bossKills[selectedBossID] then return end

			tremove(raid.bossKills, selectedBossID)
			-- Remove associated loot
			for i = #raid.loot, 1, -1 do
				if raid.loot[i].bossNum == selectedBossID then
					tremove(raid.loot, i)
				end
			end
			fetched = false
		end

		function Boss:Delete()
			if addon.Logger.selectedBoss then
				StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
			end
		end

		StaticPopupDialogs["KRTLOGGER_DELETE_BOSS"] = {
			text = L.StrConfirmDeleteBoss, button1 = L.BtnOK, button2 = CANCEL,
			OnAccept = DeleteBoss, timeout = 0, whileDead = 1, hideOnEscape = 1,
		}
	end

	do -- Sorting Logic
		local ascending = false
		local sortTypes = {
			id = function(a, b) return ascending and (a.id < b.id) or (a.id > b.id) end,
			name = function(a, b) return ascending and (a.name < b.name) or (a.name > b.name) end,
			time = function(a, b) return ascending and (a.time < b.time) or (a.time > b.time) end,
			mode = function(a, b) return ascending and (a.mode < b.mode) or (a.mode > b.mode) end,
		}

		function Boss:Sort(sortType)
			if not sortTypes[sortType] then return end
			ascending = not ascending
			table.sort(bossTable, sortTypes[sortType])
			self:Fetch()
		end
	end

	function Boss:GetName(bossNum, raidNum)
		local name = L.StrUnknown
		raidNum = raidNum or KRT_CurrentRaid
		local raid = KRT_Raids[raidNum]
		if raid and raid.bossKills and raid.bossKills[bossNum] then
			name = raid.bossKills[bossNum].name
			if name == "_TrashMob_" then name = L.StrTrashMob end
		end
		return name
	end

	addon:RegisterCallback("LoggerSelectRaid", function() fetched = false end)
end

-- ============================================================================
-- Logger: Boss Attendees List
-- ============================================================================
do
	addon.Logger.BossAttendees = {}
	local BossAttendees = addon.Logger.BossAttendees

	local attendeesFrame, frameName
	local localized, fetched = false, false
	local updateInterval = 0.075
	local playersTable = {}

	function BossAttendees:OnLoad(frame)
		if not frame then return end
		attendeesFrame = frame
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
	end

	function BossAttendees:UpdateUIFrame(self, elapsed)
		if not attendeesFrame then return end
		if not localized then
			_G[frameName .. "Title"]:SetText(L.StrBossAttendees)
			localized = true
		end

		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			local selectedBossID = addon.Logger.selectedBoss
			local selectedPlayerID = addon.Logger.selectedBossPlayer
			if not fetched then
				self:InitList()
				self:Fetch()
			end

			for _, playerInfo in ipairs(playersTable) do
				local btn = _G[frameName .. "PlayerBtn" .. playerInfo.id]
				if btn then
					Utils.toggleHighlight(btn, selectedPlayerID and selectedPlayerID == playerInfo.id)
				end
			end
			Utils.enableDisable(_G[frameName .. "AddBtn"], selectedBossID and not selectedPlayerID)
			Utils.enableDisable(_G[frameName .. "RemoveBtn"], selectedBossID and selectedPlayerID)
		end
	end

	function BossAttendees:InitList()
		if not addon.Logger.selectedBoss then
			twipe(playersTable)
			return
		end
		playersTable = addon.Raid:GetPlayers(addon.Logger.selectedRaid, addon.Logger.selectedBoss)
	end

	function BossAttendees:Fetch()
		if not frameName then return end
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())

		for i = 1, 40 do if _G[frameName .. "PlayerBtn" .. i] then _G[frameName .. "PlayerBtn" .. i]:Hide() end end

		for _, p in ipairs(playersTable) do
			local btnName = frameName .. "PlayerBtn" .. p.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerBossAttendeeButton")
			btn:SetID(p.id)
			btn:Show()
			local nameText = _G[btnName .. "Name"]
			nameText:SetText(p.name)
			local r, g, b = addon:GetClassColor(p.class)
			nameText:SetVertexColor(r, g, b)
			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end

	function BossAttendees:Add() addon.Logger.AttendeesBox:Toggle() end

	do -- Delete Attendee Logic
		local function DeleteAttendee()
			local selectedRaidID = addon.Logger.selectedRaid
			local selectedBossID = addon.Logger.selectedBoss
			local selectedPlayerID = addon.Logger.selectedBossPlayer
			if not selectedRaidID or not selectedBossID or not selectedPlayerID then return end

			local raid = KRT_Raids[selectedRaidID]
			if not raid or not raid.bossKills[selectedBossID] then return end

			-- Remove player from the boss kill record
			local playerNameToRemove = addon.Raid:GetPlayerName(selectedPlayerID, selectedRaidID)
			Utils.removeEntry(raid.bossKills[selectedBossID].players, playerNameToRemove)
			fetched = false
		end

		function BossAttendees:Delete()
			if addon.Logger.selectedBossPlayer then
				StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
			end
		end

		StaticPopupDialogs["KRTLOGGER_DELETE_ATTENDEE"] = {
			text = L.StrConfirmDeleteAttendee, button1 = L.BtnOK, button2 = CANCEL,
			OnAccept = DeleteAttendee, timeout = 0, whileDead = 1, hideOnEscape = 1,
		}
	end

	do -- Sorting Logic
		local ascending = false
		function BossAttendees:Sort(sortType)
			if sortType == "name" then
				ascending = not ascending
				table.sort(playersTable, function(a, b) return ascending and (a.name < b.name) or (a.name > b.name) end)
				self:Fetch()
			end
		end
	end

	local function ResetFetch() fetched = false end
	addon:RegisterCallback("LoggerSelectRaid", ResetFetch)
	addon:RegisterCallback("LoggerSelectBoss", ResetFetch)
end

-- ============================================================================
-- Logger: Raid Attendees List
-- ============================================================================
do
	addon.Logger.RaidAttendees = {}
	local RaidAttendees = addon.Logger.RaidAttendees

	local attendeesFrame, frameName
	local localized, fetched = false, false
	local updateInterval = 0.075
	local playersTable = {}

	function RaidAttendees:OnLoad(frame)
		if not frame then return end
		attendeesFrame = frame
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
	end

	function RaidAttendees:UpdateUIFrame(self, elapsed)
		if not attendeesFrame then return end
		if not localized then
			_G[frameName .. "Title"]:SetText(L.StrRaidAttendees)
			_G[frameName .. "HeaderJoin"]:SetText(L.StrJoin)
			_G[frameName .. "HeaderLeave"]:SetText(L.StrLeave)
			-- FIXME: Re-enable buttons when functionality is implemented.
			_G[frameName .. "AddBtn"]:Disable()
			_G[frameName .. "DeleteBtn"]:Disable()
			localized = true
		end

		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not fetched then
				self:InitList()
				self:Fetch()
			end

			local selectedPlayerID = addon.Logger.selectedPlayer
			for _, playerInfo in ipairs(playersTable) do
				local btn = _G[frameName .. "PlayerBtn" .. playerInfo.id]
				if btn then
					Utils.toggleHighlight(btn, selectedPlayerID and selectedPlayerID == playerInfo.id)
				end
			end
		end
	end

	function RaidAttendees:InitList()
		playersTable = addon.Raid:GetPlayers(addon.Logger.selectedRaid)
	end

	function RaidAttendees:Fetch()
		if not frameName then return end
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())

		-- Hide all existing buttons before redrawing
		for i = 1, 40 do if _G[frameName .. "PlayerBtn" .. i] then _G[frameName .. "PlayerBtn" .. i]:Hide() end end

		for _, p in ipairs(playersTable) do
			local btnName = frameName .. "PlayerBtn" .. p.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerRaidAttendeeButton")
			btn:SetID(p.id)
			btn:Show()

			local nameText = _G[btnName .. "Name"]
			nameText:SetText(p.name)
			local r, g, b = addon:GetClassColor(p.class)
			nameText:SetVertexColor(r, g, b)

			_G[btnName .. "Join"]:SetText(date("%H:%M", p.join))
			_G[btnName .. "Leave"]:SetText(p.leave and date("%H:%M", p.leave) or "")

			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end

	do -- Delete Attendee Logic
		local function DeleteAttendee()
			local selectedRaidID = addon.Logger.selectedRaid
			local selectedPlayerID = addon.Logger.selectedPlayer
			if not selectedRaidID or not selectedPlayerID then return end

			local raid = KRT_Raids[selectedRaidID]
			if not raid or not raid.players[selectedPlayerID] then return end

			local name = raid.players[selectedPlayerID].name
			tremove(raid.players, selectedPlayerID)

			-- Remove player from all boss kills in this raid
			for _, boss in ipairs(raid.bossKills) do
				Utils.removeEntry(boss.players, name)
			end

			-- Remove all loot associated with this player in this raid
			for i = #raid.loot, 1, -1 do
				if raid.loot[i].looter == name then
					tremove(raid.loot, i)
				end
			end
			fetched = false
		end

		function RaidAttendees:Delete()
			if addon.Logger.selectedPlayer then
				StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
			end
		end

		StaticPopupDialogs["KRTLOGGER_DELETE_RAIDATTENDEE"] = {
			text = L.StrConfirmDeleteAttendee, button1 = L.BtnOK, button2 = CANCEL,
			OnAccept = DeleteAttendee, timeout = 0, whileDead = 1, hideOnEscape = 1,
		}
	end

	do -- Sorting Logic
		local ascending = false
		local sortTypes = {
			name  = function(a, b) return ascending and (a.name < b.name) or (a.name > b.name) end,
			join  = function(a, b) return ascending and (a.join < b.join) or (a.join > b.join) end,
			leave = function(a, b)
				-- Handle nil leave times
				local aLeave, bLeave = a.leave or (ascending and math.huge or -math.huge), b.leave or (ascending and math.huge or -math.huge)
				return ascending and (aLeave < bLeave) or (aLeave > bLeave)
			end,
		}

		function RaidAttendees:Sort(sortType)
			if not sortTypes[sortType] then return end
			ascending = not ascending
			table.sort(playersTable, sortTypes[sortType])
			self:Fetch()
		end
	end

	addon:RegisterCallback("LoggerSelectRaid", function() fetched = false end)
end

-- ============================================================================
-- Logger: Loot List
-- ============================================================================
do
	addon.Logger.Loot = {}
	local Loot = addon.Logger.Loot

	local lootFrame, frameName
	local localized, fetched = false, false
	local updateInterval = 0.075
	local raidLoot, lootTable = {}, {}

	function Loot:OnLoad(frame)
		if not frame then return end
		lootFrame = frame
		frameName = frame:GetName()
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
	end

	function Loot:UpdateUIFrame(self, elapsed)
		if not lootFrame then return end
		if not localized then
			_G[frameName .. "Title"]:SetText(L.StrRaidLoot)
			_G[frameName .. "ExportBtn"]:SetText(L.BtnExport)
			_G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
			_G[frameName .. "EditBtn"]:SetText(L.BtnEdit)
			_G[frameName .. "HeaderItem"]:SetText(L.StrItem)
			_G[frameName .. "HeaderSource"]:SetText(L.StrSource)
			_G[frameName .. "HeaderWinner"]:SetText(L.StrWinner)
			_G[frameName .. "HeaderType"]:SetText(L.StrType)
			_G[frameName .. "HeaderRoll"]:SetText(L.StrRoll)
			_G[frameName .. "HeaderTime"]:SetText(L.StrTime)
			-- FIXME: Re-enable buttons when functionality is implemented
			_G[frameName .. "ExportBtn"]:Disable()
			_G[frameName .. "ClearBtn"]:Disable()
			_G[frameName .. "AddBtn"]:Disable()
			_G[frameName .. "EditBtn"]:Disable()
			localized = true
		end

		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not fetched then
				raidLoot = addon.Raid:GetLoot(addon.Logger.selectedRaid)
				self:InitList()
				self:Fetch()
			end

			local selectedItemID = addon.Logger.selectedItem
			for _, lootInfo in ipairs(raidLoot) do
				local btn = _G[frameName .. "ItemBtn" .. lootInfo.id]
				if btn then
					Utils.toggleHighlight(btn, selectedItemID and selectedItemID == lootInfo.id)
				end
			end
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedItemID)
		end
	end

	function Loot:InitList()
		twipe(lootTable)
		local selectedPlayerID = addon.Logger.selectedPlayer
		if not selectedPlayerID then
			lootTable = addon.Raid:GetLoot(addon.Logger.selectedRaid, addon.Logger.selectedBoss)
		else
			lootTable = addon.Raid:GetPlayerLoot(selectedPlayerID, addon.Logger.selectedRaid, addon.Logger.selectedBoss)
		end
	end

	function Loot:Fetch()
		if not frameName then return end
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())

		for i = 1, 100 do if _G[frameName .. "ItemBtn" .. i] then _G[frameName .. "ItemBtn" .. i]:Hide() end end

		for _, v in ipairs(lootTable) do
			local btnName = frameName .. "ItemBtn" .. v.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerLootButton")
			btn:SetID(v.id)
			btn:Show()

			_G[btnName .. "Name"]:SetText("|c" .. itemColors[v.itemRarity + 1] .. v.itemName .. "|r")
			_G[btnName .. "Source"]:SetText(addon.Logger.Boss:GetName(v.bossNum, addon.Logger.selectedRaid))

			local winnerText = _G[btnName .. "Winner"]
			local r, g, b = addon:GetClassColor(addon:GetPlayerClass(v.looter))
			winnerText:SetText(v.looter)
			winnerText:SetVertexColor(r, g, b)

			_G[btnName .. "Type"]:SetText(lootTypesColored[v.rollType] or lootTypesColored[4]) -- Default to Free
			_G[btnName .. "Roll"]:SetText(v.rollValue or 0)
			_G[btnName .. "Time"]:SetText(date("%H:%M", v.time))
			_G[btnName .. "ItemIconTexture"]:SetTexture(v.itemTexture)

			btn:SetPoint("TOPLEFT", 0, -totalHeight)
			btn:SetWidth(scrollFrame:GetWidth() - 20)
			totalHeight = totalHeight + btn:GetHeight()
		end
		scrollChild:SetHeight(math.max(totalHeight, scrollFrame:GetHeight()))
		fetched = true
	end

	function Loot:OnEnter(btn)
		if not btn then return end
		local itemID = btn:GetParent():GetID()
		if not raidLoot[itemID] then return end
		GameTooltip:SetOwner(btn, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(raidLoot[itemID].itemLink)
	end

	do -- Delete Item Logic
		local function DeleteItem()
			local selectedRaidID = addon.Logger.selectedRaid
			local selectedItemID = addon.Logger.selectedItem
			if selectedRaidID and KRT_Raids[selectedRaidID] and selectedItemID then
				tremove(KRT_Raids[selectedRaidID].loot, selectedItemID)
				addon.Logger.selectedItem = nil
				fetched = false
			end
		end

		function Loot:Delete()
			if addon.Logger.selectedItem then
				StaticPopup_Show("KRTLOGGER_DELETE_ITEM")
			end
		end

		StaticPopupDialogs["KRTLOGGER_DELETE_ITEM"] = {
			text = L.StrConfirmDeleteItem, button1 = L.BtnOK, button2 = CANCEL,
			OnAccept = DeleteItem, timeout = 0, whileDead = 1, hideOnEscape = 1,
		}
	end

	do -- Sorting Logic
		local ascending = false
		local sortTypes = {
			id     = function(a, b) return ascending and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
			source = function(a, b) return ascending and (a.bossNum < b.bossNum) or (a.bossNum > b.bossNum) end,
			winner = function(a, b) return ascending and (a.looter < b.looter) or (a.looter > b.looter) end,
			type   = function(a, b) return ascending and (a.rollType < b.rollType) or (a.rollType > b.rollType) end,
			roll   = function(a, b) return ascending and ((a.rollValue or 0) < (b.rollValue or 0)) or ((a.rollValue or 0) > (b.rollValue or 0)) end,
			time   = function(a, b) return ascending and (a.time < b.time) or (a.time > b.time) end,
		}

		function Loot:Sort(sortType)
			if not sortTypes[sortType] then return end
			ascending = not ascending
			table.sort(lootTable, sortTypes[sortType])
			self:Fetch()
		end
	end

	function addon:Log(itemID, looter, rollType, rollValue)
		local raidID = addon.Logger and addon.Logger.selectedRaid or KRT_CurrentRaid
		if not raidID or not KRT_Raids[raidID] then return end

		local lootItem = KRT_Raids[raidID].loot[itemID]
		if not lootItem then return end

		if looter and looter ~= "" then lootItem.looter = looter end
		if tonumber(rollType) then lootItem.rollType = tonumber(rollType) end
		if tonumber(rollValue) then lootItem.rollValue = tonumber(rollValue) end
		fetched = false -- Mark loot list as needing a refresh
	end

	local function ResetFetch() fetched = false end
	addon:RegisterCallback("LoggerSelectRaid", ResetFetch)
	addon:RegisterCallback("LoggerSelectBoss", ResetFetch)
	addon:RegisterCallback("LoggerSelectPlayer", ResetFetch)
end

-- ============================================================================
-- Logger: Add/Edit Boss Popup
-- ============================================================================
do
	addon.Logger.BossBox = {}
	local BossBox = addon.Logger.BossBox

	local bossBoxFrame, frameName
	local localized, isEdit = false, false
	local updateInterval = 0.1
	local raidData, bossData, tempDate = {}, {}, {}

	function BossBox:OnLoad(frame)
		if not frame then return end
		bossBoxFrame = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", function(...) self:UpdateUIFrame(...) end)
		frame:SetScript("OnHide", function() self:CancelAddEdit() end)
	end

	function BossBox:Toggle() Utils.toggle(bossBoxFrame) end
	function BossBox:Hide() if bossBoxFrame and bossBoxFrame:IsShown() then bossBoxFrame:Hide() end end

	function BossBox:Fill()
		local selectedRaidID = addon.Logger.selectedRaid
		local selectedBossID = addon.Logger.selectedBoss
		if not selectedRaidID or not selectedBossID then return end

		raidData = KRT_Raids[selectedRaidID]
		if not raidData then return end
		bossData = raidData.bossKills[selectedBossID]
		if not bossData then return end

		_G[frameName .. "Name"]:SetText(bossData.name)
		local d = date("*t", bossData.date)
		tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
		_G[frameName .. "Time"]:SetText(format("%02d:%02d", tempDate.hour, tempDate.min))
		_G[frameName .. "Difficulty"]:SetText((bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n")
		isEdit = true
		self:Toggle()
	end

	function BossBox:Save()
		local selectedRaidID = addon.Logger.selectedRaid
		if not selectedRaidID then return end
		local name = _G[frameName .. "Name"]:GetText():trim()
		local diff = lower(_G[frameName .. "Difficulty"]:GetText():trim())
		local bTime = _G[frameName .. "Time"]:GetText():trim()

		name = (name == "") and "_TrashMob_" or name
		if name ~= "_TrashMob_" and (diff ~= "h" and diff ~= "n") then
			addon:PrintError(L.ErrBossDifficulty); return
		end

		local hour, minute = match(bTime, "(%d+):(%d+)")
		hour, minute = tonumber(hour), tonumber(minute)
		if not hour or not minute then
			addon:PrintError(L.ErrBossTime); return
		end

		local difficulty = (KRT_Raids[selectedRaidID].size == 10) and 1 or 2
		if diff == "h" then difficulty = difficulty + 2 end

		local _, month, day, year = CalendarGetDate()
		local killDate = { day = day, month = month, year = year, hour = hour, min = minute }

		if isEdit and bossData then
			bossData.name = name
			bossData.date = time(killDate)
			bossData.difficulty = difficulty
		else
			tinsert(KRT_Raids[selectedRaidID].bossKills, {
				name = name,
				date = time(killDate),
				difficulty = difficulty,
				players = {},
			})
		end
		self:Hide()
		TriggerEvent("LoggerSelectRaid") -- Force a full refresh of the logger
	end

	function BossBox:CancelAddEdit()
		if not frameName then return end
		_G[frameName .. "Name"]:SetText(""); _G[frameName .. "Difficulty"]:SetText(""); _G[frameName .. "Time"]:SetText("")
		isEdit, raidData, bossData = false, {}, {}
		twipe(tempDate)
	end

	function BossBox:UpdateUIFrame(self, elapsed)
		if not localized then
			addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
			addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
			addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
			localized = true
		end
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
		end
	end
end

-- ============================================================================
-- Logger: Add Attendee Popup
-- ============================================================================
do
	addon.Logger.AttendeesBox = {}
	local AttendeesBox = addon.Logger.AttendeesBox

	local attendeesBoxFrame, frameName
	local localized = false

	function AttendeesBox:OnLoad(frame)
		if not frame then return end
		attendeesBoxFrame = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnShow", function() _G[frameName .. "Name"]:SetText(""); _G[frameName .. "Name"]:SetFocus() end)
		frame:SetScript("OnHide", function() _G[frameName .. "Name"]:SetText(""); _G[frameName .. "Name"]:ClearFocus() end)
	end

	function AttendeesBox:Toggle() Utils.toggle(attendeesBoxFrame) end

	function AttendeesBox:Save()
		local name = _G[frameName .. "Name"]:GetText():trim()
		if name == "" then addon:PrintError(L.ErrAttendeesInvalidName); return end

		local selectedRaidID = addon.Logger.selectedRaid
		local selectedBossID = addon.Logger.selectedBoss
		if not selectedRaidID or not selectedBossID or not KRT_Raids[selectedRaidID] then
			addon:PrintError(L.ErrAttendeesInvalidRaidBoss); return
		end

		local bossKill = KRT_Raids[selectedRaidID].bossKills[selectedBossID]
		for _, existingName in ipairs(bossKill.players) do
			if existingName:lower() == name:lower() then
				addon:PrintError(L.ErrAttendeesPlayerExists); return
			end
		end

		local raidPlayers = KRT_Raids[selectedRaidID].players
		for _, player in ipairs(raidPlayers) do
			if name:lower() == player.name:lower() then
				addon:PrintSuccess(L.StrAttendeesAddSuccess)
				tinsert(bossKill.players, player.name)
				self:Toggle() -- Hide frame on success
				addon.Logger.BossAttendees:InitList() -- Refresh list
				addon.Logger.BossAttendees:Fetch()
				return
			end
		end
		-- If we get here, the player wasn't found in the main raid roster
		addon:PrintError(L.ErrAttendeesInvalidName)
	end
end

-- ============================================================================
-- Slash Commands
-- ============================================================================
do
	local cmdAchiev = { "ach", "achi", "achiev", "achievement" }
	local cmdLFM = { "pug", "lfm", "group", "grouper" }
	local cmdConfig = { "config", "conf", "options", "opt" }
	local cmdChanges = { "ms", "changes", "mschanges" }
	local cmdWarnings = { "warning", "warnings", "warn", "rw" }
	local cmdLog = { "log", "logger", "history" }
	local cmdDebug = { "debug", "dbg", "debugger" }
	local cmdLoot = { "loot", "ml", "master" }
	local cmdReserves = { "res", "reserves", "reserve" }
	local helpString = "|caaf49141%s|r: %s"

	local function HandleSlashCmd(cmd)
		if not cmd or cmd == "" then
			addon.Master:Toggle()
			return
		end

		local cmd1, cmd2, cmd3 = strsplit(" ", cmd, 3)
		cmd1 = cmd1 and lower(cmd1) or ""
		cmd2 = cmd2 and lower(cmd2) or ""

		if cmd1 == "show" or cmd1 == "toggle" then
			addon.Master:Toggle()
		elseif Utils.checkEntry(cmdDebug, cmd1) then
			if cmd2 == "" then addon.Debugger:IsShown() and addon.Debugger:Hide() or addon.Debugger:Show()
			elseif cmd2 == "clear" then addon.Debugger:Clear()
			elseif cmd2 == "level" or cmd2 == "lvl" then
				if not cmd3 then addon.Debugger:Add("INFO", "Current log level: %s", addon.Debugger:GetMinLevel())
				else addon.Debugger:SetMinLevel(tonumber(cmd3) or cmd3) end
			else addon.Debugger:Add("WARN", "Unknown debug command: %s", cmd2) end
		elseif Utils.checkEntry(cmdConfig, cmd1) then
			if cmd2 == "reset" then addon.Config:Default() else addon.Config:Toggle() end
		elseif Utils.checkEntry(cmdWarnings, cmd1) then
			if cmd2 == "" or cmd2 == "toggle" then addon.Warnings:Toggle()
			elseif cmd2 == "help" then print(helpString:format("toggle", L.StrCmdToggle)); print(helpString:format("[ID]", L.StrCmdWarningAnnounce))
			else addon.Warnings:Announce(tonumber(cmd2)) end
		elseif Utils.checkEntry(cmdChanges, cmd1) then
			if cmd2 == "" or cmd2 == "toggle" then addon.Changes:Toggle()
			elseif cmd2 == "demand" or cmd2 == "ask" then addon.Changes:Demand()
			elseif cmd2 == "announce" or cmd2 == "spam" then addon.Changes:Announce() end
		elseif Utils.checkEntry(cmdLog, cmd1) then
			addon.Logger:Toggle()
		elseif Utils.checkEntry(cmdLoot, cmd1) then
			addon.Master:Toggle()
		elseif Utils.checkEntry(cmdReserves, cmd1) then
			if cmd2 == "" or cmd2 == "toggle" then addon.Reserves:ShowWindow() elseif cmd2 == "import" then addon.Reserves:ShowImportBox() end
		elseif Utils.checkEntry(cmdLFM, cmd1) then
			if cmd2 == "" or cmd2 == "toggle" then addon.Spammer:Toggle()
			elseif cmd2 == "start" then addon.Spammer:Start()
			elseif cmd2 == "stop" then addon.Spammer:Stop() end
		else
			addon:Print(format(L.StrCmdCommands, "krt"), "KRT")
			print(helpString:format("config", L.StrCmdConfig)); print(helpString:format("lfm", L.StrCmdGrouper));
			print(helpString:format("changes", L.StrCmdChanges)); print(helpString:format("warnings", L.StrCmdWarnings));
			print(helpString:format("log", L.StrCmdLog)); print(helpString:format("reserves", L.StrCmdReserves));
		end
	end

	SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
	SlashCmdList["KRT"] = HandleSlashCmd

	SLASH_KRTCOUNTS1 = "/krtcounts"
	SlashCmdList["KRTCOUNTS"] = function() addon:ToggleCountsFrame() end
end

-- ============================================================================
-- Main Event Handlers
-- ============================================================================

function addon:ADDON_LOADED(name)
	if name ~= addonName then return end
	mainFrame:UnregisterEvent("ADDON_LOADED")
	self:RegisterEvents(
		"CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONSTER_YELL",
		"RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "COMBAT_LOG_EVENT_UNFILTERED", "RAID_INSTANCE_WELCOME",
		"ITEM_LOCKED", "LOOT_CLOSED", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "TRADE_ACCEPT_UPDATE"
	)
	self:RAID_ROSTER_UPDATE()
end

function addon:RAID_ROSTER_UPDATE()
	self:UpdateRaidRoster()
end

function addon:RAID_INSTANCE_WELCOME(_, nextReset)
	local instanceName, _, instanceDiff = GetInstanceInfo()
	KRT_NextReset = nextReset
	if L.RaidZones[instanceName] then
		Utils.schedule(3, function() addon.Raid:Check(instanceName, instanceDiff) end)
	end
end

function addon:PLAYER_ENTERING_WORLD()
	mainFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	Utils.schedule(3, self.Raid.FirstCheck)
end

function addon:CHAT_MSG_LOOT(msg)
	if KRT_CurrentRaid then
		self.Raid:AddLoot(msg)
	end
end

function addon:CHAT_MSG_MONSTER_YELL(text, boss)
	if L.BossYells[text] and KRT_CurrentRaid then
		self.Raid:AddBoss(L.BossYells[text])
	end
end

function addon:COMBAT_LOG_EVENT_UNFILTERED(_, event, _, _, _, destGUID, destName)
	if not KRT_CurrentRaid or event ~= "UNIT_DIED" then return end
	local npcID = Utils.GetNPCID(destGUID)
	if BossIDs.BossIDs[npcID] then
		self.Raid:AddBoss(destName)
	end
end