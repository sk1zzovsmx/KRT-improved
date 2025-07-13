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

-- Items to ignore when adding raids loot
addon.ignoredItems = {
    -- Emblems (Wrath of the Lich King)
    [40752] = true,  -- Emblem of Heroism
    [40753] = true,  -- Emblem of Valor
    [45624] = true,  -- Emblem of Conquest
    [47241] = true,  -- Emblem of Triumph
    [49426] = true,  -- Emblem of Frost
    -- Emblems and Tokens (The Burning Crusade)
    [29434] = true,  -- Badge of Justice
    [29736] = true,  -- Arcane Tome
    [29737] = true,  -- Firewing Signet
    [29738] = true,  -- Fel Armament
    [29739] = true,  -- Sunfury Signet
    [29740] = true,  -- Mark of Sargeras
    [29741] = true,  -- Fel Armament
    -- High-end Gems
    [36931] = true,  -- Ametrine
    [36919] = true,  -- Cardinal Ruby
    [36928] = true,  -- Dreadstone
    [36934] = true,  -- Eye of Zul
    [36922] = true,  -- King's Amber
    [36925] = true,  -- Majestic Zircon
    -- Enchanting Materials - Classic
    [10940] = true,  -- Strange Dust
    [10938] = true,  -- Lesser Magic Essence
    [10939] = true,  -- Greater Magic Essence
    [10978] = true,  -- Small Glimmering Shard
    [10998] = true,  -- Lesser Astral Essence
    [11082] = true,  -- Greater Astral Essence
    [11083] = true,  -- Soul Dust
    [11084] = true,  -- Large Glimmering Shard
    [11134] = true,  -- Lesser Mystic Essence
    [11135] = true,  -- Greater Mystic Essence
    [11137] = true,  -- Vision Dust
    [11138] = true,  -- Small Glowing Shard
    [11139] = true,  -- Large Glowing Shard
    [11174] = true,  -- Lesser Nether Essence
    [11175] = true,  -- Greater Nether Essence
    [11176] = true,  -- Dream Dust
    [11177] = true,  -- Small Radiant Shard
    [11178] = true,  -- Large Radiant Shard
    [14343] = true,  -- Small Brilliant Shard
    [14344] = true,  -- Large Brilliant Shard
    [16202] = true,  -- Lesser Eternal Essence
    [16203] = true,  -- Greater Eternal Essence
    [16204] = true,  -- Illusion Dust
    [20725] = true,  -- Nexus Crystal
    -- Enchanting Materials - The Burning Crusade
    [22445] = true,  -- Arcane Dust
    [22446] = true,  -- Greater Planar Essence
    [22447] = true,  -- Lesser Planar Essence
    [22448] = true,  -- Small Prismatic Shard
    [22449] = true,  -- Large Prismatic Shard
    [22450] = true,  -- Void Crystal
    -- Enchanting Materials - Wrath of the Lich King
    [34052] = true,  -- Dream Shard
    [34053] = true,  -- Small Dream Shard
    [34054] = true,  -- Infinite Dust
    [34055] = true,  -- Greater Cosmic Essence
    [34056] = true,  -- Lesser Cosmic Essence
    [34057] = true,  -- Abyss Crystal
}

-- List of bosses IDs to track
addon.bossListIDs = {
    -- Karazhan (10 giocatori)
    [16152] = "Attumen the Huntsman",
    [16457] = "Maiden of Virtue",
    [15687] = "Moroes",
    [15691] = "The Curator",
    [15688] = "Terestian Illhoof",
    [16524] = "Shade of Aran",
    [15689] = "Netherspite",
    [15690] = "Prince Malchezaar",
    [17225] = "Nightbane",
    -- Gruul's Lair (25 giocatori)
    [18831] = "High King Maulgar",
    [19044] = "Gruul the Dragonkiller",
    -- Magtheridon's Lair (25 giocatori)
    [17257] = "Magtheridon",
    -- Serpentshrine Cavern (25 giocatori)
    [21216] = "Hydross the Unstable",
    [21217] = "The Lurker Below",
    [21215] = "Leotheras the Blind",
    [21214] = "Fathom-Lord Karathress",
    [21213] = "Morogrim Tidewalker",
    [21212] = "Lady Vashj",
    -- The Eye (Tempest Keep) (25 giocatori)
    [19514] = "Al'ar",
    [19516] = "Void Reaver",
    [18805] = "High Astromancer Solarian",
    [19622] = "Kael'thas Sunstrider",
    -- Battle for Mount Hyjal (25 giocatori)
    [17767] = "Rage Winterchill",
    [17808] = "Anetheron",
    [17888] = "Kaz'rogal",
    [17842] = "Azgalor",
    [17968] = "Archimonde",
    -- Black Temple (25 giocatori)
    [22887] = "High Warlord Naj'entus",
    [22898] = "Supremus",
    [22841] = "Shade of Akama",
    [22871] = "Teron'khan",
    [22948] = "Gurtogg Bloodboil",
    [23420] = "Reliquary of Souls",
    [22947] = "Mother Shahraz",
    [22949] = "Illidari Council",
    [22917] = "Illidan Stormrage",
    -- Sunwell Plateau (25 giocatori)
    [24850] = "Kalecgos",
    [24882] = "Brutallus",
    [25038] = "Felmyst",
    [25165] = "Eredar Twins",
    [25741] = "M'uru",
    [25315] = "Kil'jaeden",
    -- Zul'Aman (10 giocatori)
    [23574] = "Nalorakk",
    [23576] = "Jan'alai",
    [23578] = "Akil'zon",
    [23577] = "Halazzi",
    [24239] = "Hex Lord Malacrass",
    [23863] = "Zul'jin",
    -- World Bosses
    [18728] = "Doom Lord Kazzak",
    [17711] = "Doomwalker",
    -- Naxxramas:
    [15956] = "Anub'Rekhan",
    [15953] = "Grand Widow Faerlina",
    [15952] = "Maexxna",
    [15954] = "Noth the Plaguebringer",
    [15936] = "Heigan the Unclean",
    [16011] = "Loatheb",
    [16061] = "Instructor Razuvious",
    [16060] = "Gothik the Harvester",
    [16028] = "Patchwerk",
    [15931] = "Grobbulus",
    [15932] = "Gluth",
    [15928] = "Thaddius",
    [15989] = "Sapphiron",
    [15990] = "Kel'Thuzad",
    -- The Obsidian Sanctum:
    [28860] = "Sartharion",
    -- Eye of Eternity:
    [28859] = "Malygos",
    -- Archavon's Chamber:
    [31125] = "Archavon the Stone Watcher",
    [33993] = "Emalon the Storm Watcher",
    [35013] = "Koralon the Flame Watcher",
    [38433] = "Toravon the Ice Watcher",
    -- Ulduar
    [33113] = "Flame Leviathan",
    [33118] = "Ignis the Furnace Master",
    [33186] = "Razorscale",
    [33293] = "XT-002 Deconstructor",
    [32930] = "Kologarn",
    [33515] = "Auriaya",
    [33271] = "General Vezax",
    [33288] = "Yogg-Saron",
    -- Onyxia's Lair:
    [10184] = "Onyxia",
    -- Trial of the Crusader:
    [34797] = "Icehowl",
    [34780] = "Lord Jaraxxus",
    [34564] = "Anub'arak",
    -- Icecrown Citadel:
    [36612] = "Lord Marrowgar",
    [36855] = "Lady Deathwhisper",
    [37813] = "Deathbringer Saurfang",
    [36626] = "Festergut",
    [36627] = "Rotface",
    [36678] = "Professor Putricide",
    [37955] = "Blood-Queen Lana'thel",
    [36853] = "Sindragosa",
    [36597] = "The Lich King"
}

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
local LoadOptions

-- Cache frequently used globals:
local SendChatMessage                   = SendChatMessage
local tinsert, tremove, tconcat, twipe  = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local pcall                             = pcall
local format, match, find, strlen       = string.format, string.match, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber, ucfirst       = tostring, tonumber, _G.string.ucfirst
local deformat                          = LibStub("LibDeformat-3.0")

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

-- ==================== Debugger ==================== --

do
	addon.Debugger         = {}
	local Debugger         = addon.Debugger

	-- Local references
	local frameName, frame, scrollFrame
	local isDebuggerOpen   = false
	local buffer           = {} -- Holds messages if the frame isn't ready

	local logLevelPriority = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
	local logLevelNames    = { [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }
	local minLevel         = "DEBUG" -- Default log level
	local MAX_DEBUG_LOGS   = 500  -- <--- Limite massimo log, modifica qui

	-- Called when the XML frame is loaded
	function Debugger:OnLoad(self)
		frame = self
		frameName = frame:GetName()
		scrollFrame = _G[frameName .. "ScrollFrame"]
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

		if scrollFrame then
			print("[Debugger] scrollFrame found:", scrollFrame:GetName())
		else
			print("[Debugger] ERROR: scrollFrame is nil!")
		end

		-- Restore saved position if available
		if KRT_Debug and KRT_Debug.Pos and KRT_Debug.Pos.point then
			local p = KRT_Debug.Pos
			frame:ClearAllPoints()
			frame:SetPoint(p.point, p.relativeTo or UIParent, p.relativePoint, p.xOfs, p.yOfs)
		end
	end

	-- Show the debugger window
	function Debugger:Show()
		if not frame then return end
		frame:Show()

		if not isDebuggerOpen then
			isDebuggerOpen = true
			self:Add("DEBUG", "Debugger window opened.")
			self:AddBufferedMessages()
		end
	end

	-- Hide the debugger window
	function Debugger:Hide()
		if frame then
			frame:Hide()
			isDebuggerOpen = false
		end
	end

	-- Clear the debug output
	function Debugger:Clear()
		if scrollFrame then
			scrollFrame:Clear()
		end
		buffer = {}
	end

	-- Set the minimum log level
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

	-- Get the current minimum log level
	function Debugger:GetMinLevel()
		return minLevel
	end

	-- Add a message to the log (with optional level)
	function Debugger:Add(level, msg, ...)
		-- Allow call like Add("message") without level
		if not msg then
			msg = level
			level = "DEBUG"
		end

		if logLevelPriority[level] < logLevelPriority[minLevel] then return end

		if select('#', ...) > 0 then
			local safeArgs = {}
			for i = 1, select('#', ...) do
				local v = select(i, ...)
				table.insert(safeArgs, type(v) == "string" and v or tostring(v))
			end
			msg = string.format(msg, unpack(safeArgs))
		end
		local line = string.format("[%s][%s] %s", date("%H:%M:%S"), level, msg)

		-- Se la finestra non è pronta
		if not scrollFrame then
			tinsert(buffer, line)
			-- Limita la lunghezza del buffer!
			while #buffer > MAX_DEBUG_LOGS do
				table.remove(buffer, 1)
			end
			return
		end

		-- Scegli colore
		local r, g, b = 1, 1, 1 -- default white
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

		-- [OPZIONALE] Se hai una tabella di log persistente, tronca anche quella
		if KRT_Debug and KRT_Debug.Debugs then
			table.insert(KRT_Debug.Debugs, line)
			while #KRT_Debug.Debugs > MAX_DEBUG_LOGS do
				table.remove(KRT_Debug.Debugs, 1)
			end
		end
	end

	-- Replay any buffered messages
	function Debugger:AddBufferedMessages()
		for _, msg in ipairs(buffer) do
			scrollFrame:AddMessage(msg)
		end
		buffer = {}
	end

	-- Returns true if debugger is visible
	function Debugger:IsShown()
		return frame and frame:IsShown()
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
		return #callbacks
	end

	-- Trigger a registered event:
	function TriggerEvent(e, ...)
		if not callbacks[e] then
			return
		end
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

		if e == "ADDON_LOADED" then
			LoadOptions()
		end
		if not events[e] then
			return
		end
		for i, v in ipairs(events[e]) do
			if type(v[e]) == "function" then
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

-- ==================== Raid Helpers ==================== --
do
	addon.Raid               = {}
	local Raid               = addon.Raid
	local inRaid             = false
	local numRaid            = 0
	local GetLootMethod      = GetLootMethod
	local GetNumPartyMembers = GetNumPartyMembers
	local GetNumRaidMembers  = GetNumRaidMembers
	local GetRaidRosterInfo  = GetRaidRosterInfo

	----------------------
	-- Logger Functions --
	----------------------

	-- Update raid roster:
	function addon:UpdateRaidRoster()
		if not KRT_CurrentRaid then return end
		numRaid = GetNumRaidMembers()
		if numRaid == 0 then
			addon:Debug("INFO", "Raid disbanded. Ending current raid.")
			Raid:End()
			return
		end
		local realm = GetRealmName() or UNKNOWN
		KRT_Players[realm] = KRT_Players[realm] or {}
		local players = {}
		for i = 1, numRaid do
			local name, rank, subgroup, level, classL, class, _, online = GetRaidRosterInfo(i)
			if name then
				tinsert(players, name)
				inRaid = false
				for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
					if v.name == name and v.leave == nil then
						inRaid = true
					end
				end
				local unitID = "raid" .. tostring(i)
				local raceL, race = UnitRace(unitID)
				if not inRaid then
					addon:Debug("INFO", "New player joined raid: %s", name)
					local toRaid = {
						name = name,
						rank = rank,
						subgroup = subgroup,
						class = class or "UNKNOWN",
						join = Utils.GetCurrentTime(),
						leave = nil
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
		for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
			local found = nil
			for _, p in ipairs(players) do
				if v.name == p then
					found = true
					break
				end
			end
			if not found and v.leave == nil then
				addon:Debug("INFO", "Player left raid: %s", v.name)
				v.leave = Utils.GetCurrentTime()
			end
		end
		Utils.unschedule(addon.UpdateRaidRoster)
	end

	-- Creates a new raid log entry:
	function Raid:Create(zoneName, raidSize)
		if KRT_CurrentRaid then
			addon:Debug("INFO", "Ending previous raid before creating new one.")
			self:End()
		end
		numRaid = GetNumRaidMembers()
		if numRaid == 0 then return end
		local realm = GetRealmName() or UNKNOWN
		KRT_Players[realm] = KRT_Players[realm] or {}
		local currentTime = Utils.GetCurrentTime()
		addon:Debug("INFO", "Creating new raid: %s (%d-man)", zoneName, raidSize)
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
					name     = name,
					rank     = rank,
					subgroup = subgroup,
					class    = class or "UNKNOWN",
					join     = Utils.GetCurrentTime(),
					leave    = nil,
				})
				KRT_Players[realm][name] = {
					name   = name,
					level  = level,
					race   = race,
					raceL  = raceL,
					class  = class or "UNKNOWN",
					classL = classL,
					sex    = UnitSex(unitID),
				}
			end
		end
		tinsert(KRT_Raids, raidInfo)
		KRT_CurrentRaid = #KRT_Raids
		addon:Debug("INFO", "Raid created with ID: %d", KRT_CurrentRaid)
		TriggerEvent("RaidCreate", KRT_CurrentRaid)
		Utils.schedule(3, addon.UpdateRaidRoster)
	end

	-- Ends the current raid entry:
	function Raid:End()
		if not KRT_CurrentRaid then return end
		addon:Debug("INFO", "Ending raid ID: %d", KRT_CurrentRaid)
		Utils.unschedule(addon.Raid.UpdateRaidRoster)
		local currentTime = Utils.GetCurrentTime()
		for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
			if not v.leave then v.leave = currentTime end
		end
		KRT_Raids[KRT_CurrentRaid].endTime = currentTime
		KRT_CurrentRaid = nil
		KRT_LastBoss = nil
	end

	-- Checks raid status:
	function Raid:Check(instanceName, instanceDiff)
		if not KRT_CurrentRaid then
			addon:Debug("INFO", "No active raid. Creating new one for instance: %s", instanceName)
			Raid:Create(instanceName, (instanceDiff % 2 == 0 and 25 or 10))
			return
		end

		local current = KRT_Raids[KRT_CurrentRaid]

		if current then
			if current.zone == instanceName then
				local desiredSize = (instanceDiff % 2 == 0) and 25 or 10
				if current.size ~= desiredSize then
					addon:Debug("INFO", "Raid size changed from %d to %d. Creating new raid session.", current.size,
						desiredSize)
					addon:Print(L.StrNewRaidSessionChange)
					Raid:Create(instanceName, desiredSize)
				end
			end
		end
	end

	-- Checks the raid status upon player's login:
	function Raid:FirstCheck()
		Utils.unschedule(addon.Raid.FirstCheck)
		if GetNumRaidMembers() == 0 then return end

		-- We are in a raid? We update roster
		if KRT_CurrentRaid and Raid:CheckPlayer(unitName, KRT_CurrentRaid) then
			Utils.schedule(2, addon.UpdateRaidRoster)
			return
		end

		local instanceName, instanceType, instanceDiff = GetInstanceInfo()
		if instanceType == "raid" then
			Raid:Check(instanceName, instanceDiff)
		end
	end

	-- Add a player to the raid:
	function Raid:AddPlayer(t, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		-- We must check if the players existed or not
		if not raidNum or not t or not t.name then
			addon:Debug("ERROR", "Raid:AddPlayer called with invalid parameters (raidNum=%s, player=%s)",
				tostring(raidNum), tostring(t and t.name))
			return
		end
		local players = Raid:GetPlayers(raidNum)
		local found = false
		for i, p in ipairs(players) do
			-- If found, we simply updated the table:
			if t.name == p.name then
				KRT_Raids[raidNum].players[i] = t
				found = true
				break
			end
		end
		-- If the players wasn't in the raid, we add him/her:
		if not found then
			tinsert(KRT_Raids[raidNum].players, t)
			addon:Debug("INFO", "Added new player %s to raid %d", t.name, raidNum)
		end
	end

	-- Add a boss kill to the active raid:
	function Raid:AddBoss(bossName, manDiff, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		if not raidNum or not bossName then
			addon:Debug("ERROR", "Raid:AddBoss called with invalid parameters (raidNum=%s, bossName=%s)",
				tostring(raidNum), tostring(bossName))
			return
		end
		local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
		if manDiff then
			instanceDiff = (KRT_Raids[raidNum].size == 10) and 1 or 2
			if lower(manDiff) == "h" then
				instanceDiff = instanceDiff + 2
			end
		elseif isDyn then
			instanceDiff = instanceDiff + (2 * dynDiff)
		end
		local players = {}
		for i = 1, GetNumRaidMembers() do
			local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
			if online == 1 then -- track only online players:
				tinsert(players, name)
			end
		end
		local currentTime = Utils.GetCurrentTime()
		local killInfo = {
			name = bossName,
			difficulty = instanceDiff,
			players = players,
			date = currentTime,
			hash = Utils.encode(raidNum .. "|" .. bossName .. "|" .. (KRT_LastBoss or "0"))
		}
		tinsert(KRT_Raids[raidNum].bossKills, killInfo)
		KRT_LastBoss = #KRT_Raids[raidNum].bossKills
		addon:Debug("INFO", "Boss kill recorded: '%s' [Difficulty %d] in Raid #%d with %d players. Time: %s", bossName,
			instanceDiff, raidNum, #players, currentTime)
	end

	-- Adds a loot to the active raid:
	function Raid:AddLoot(msg, rollType, rollValue)
		if not KRT_CurrentRaid then
			addon:Debug("ERROR", "Raid:AddLoot called with no active raid.")
			return
		end
		-- Master Loot Part:
		local player, itemLink, itemCount = deformat(msg, LOOT_ITEM_MULTIPLE)
		if not player then
			itemCount = 1
			player, itemLink = deformat(msg, LOOT_ITEM)
		end
		if not player then
			player = unitName
			itemLink, itemCount = deformat(msg, msg, LOOT_ITEM_SELF_MULTIPLE)
		end
		if not itemLink then
			itemCount = 1
			itemLink = deformat(msg, LOOT_ITEM_SELF)
		end
		-- Master Loot Part:
		if not player or not itemLink then
			itemCount = 1
			player, itemLink = deformat(msg, LOOT_ROLL_YOU_WON)
			if not itemLink then
				player = unitName
				itemLink = deformat(msg, LOOT_ROLL_YOU_WON)
			end
		end

		if not itemLink then
			return
		end
		-- Extract item information
		local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
		local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
		local _, _, _, _, itemId = string.find(itemLink,
			"|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
		itemId = tonumber(itemId)
		-- We don't proceed if lower then threshold or ignored:
		local lootThreshold = GetLootThreshold()
		if itemRarity and itemRarity < lootThreshold then
			return
		end
		if itemId and addon.ignoredItems[itemId] then
			return
		end
		if not KRT_LastBoss then
			self:AddBoss("_TrashMob_")
		end
		rollType = rollType or currentRollType
		rollValue = rollValue or addon:HighestRoll()

		local lootInfo = {
			itemId      = itemId,
			itemName    = itemName,
			itemString  = itemString,
			itemLink    = itemLink,
			itemRarity  = itemRarity,
			itemTexture = itemTexture,
			itemCount   = itemCount,
			looter      = player,
			rollType    = rollType,
			rollValue   = rollValue,
			bossNum     = KRT_LastBoss,
			time        = Utils.GetCurrentTime(),
		}
		tinsert(KRT_Raids[KRT_CurrentRaid].loot, lootInfo)
		addon:Debug("INFO", "Loot added: %s x%d to %s [Raid #%d, Boss #%d, Rarity: %d, Roll: %s %s]",
			itemName or "unknown", itemCount, player, KRT_CurrentRaid, KRT_LastBoss or 0, itemRarity or -1,
			tostring(rollType), tostring(rollValue))
	end

	--------------------
	-- Raid Functions --
	--------------------

	-- Returns members count:
	function addon:GetNumRaid()
		return numRaid
	end

	-- Returns raid size: 10 or 25
	function addon:GetRaidSize()
		local size = 0
		if self:IsInRaid() then
			local diff = GetRaidDifficulty()
			size = (diff == 1 or diff == 3) and 10 or 25
		else
		end
		return size
	end

	-- Return class color by name:
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

	-- Checks if a raid is expired
	function Raid:Expired(rID)
		rID = rID or KRT_CurrentRaid
		if not rID or not KRT_Raids[rID] then
			return true
		end
		local currentTime = Utils.GetCurrentTime()
		local startTime = KRT_Raids[rID].startTime
		local validDuration = (currentTime + KRT_NextReset) - startTime

		local isExpired = validDuration >= 604800 -- 7 days in seconds
		return isExpired
	end

	-- Retrieves the raid loot:
	function Raid:GetLoot(raidNum, bossNum)
		local items = {}
		raidNum = raidNum or KRT_CurrentRaid
		bossNum = bossNum or 0
		if not raidNum or not KRT_Raids[raidNum] then
			return items
		end
		local loot = KRT_Raids[raidNum].loot
		local total = 0
		if tonumber(bossNum) <= 0 then
			for k, v in ipairs(loot) do
				local info = v
				info.id = k
				tinsert(items, info)
				total = total + 1
			end
		elseif KRT_Raids[raidNum].bossKills[bossNum] then
			for k, v in ipairs(loot) do
				if v.bossNum == bossNum then
					local info = v
					info.id = k
					tinsert(items, info)
					total = total + 1
				end
			end
		else
		end
		return items
	end

	-- Retrieves a loot item position within the raid loot:
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

	-- Retrieves raid bosses:
	function Raid:GetBosses(raidNum)
		local bosses = {}
		raidNum = raidNum or KRT_CurrentRaid
		if not raidNum or not KRT_Raids[raidNum] then
			return bosses
		end
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
		return bosses
	end

	----------------------
	-- Player Functions --
	----------------------

	-- Returns current raid players:
	function Raid:GetPlayers(raidNum, bossNum)
		raidNum = raidNum or KRT_CurrentRaid
		local players = {}
		if not raidNum or not KRT_Raids[raidNum] then
			return players
		end
		for k, v in ipairs(KRT_Raids[raidNum].players) do
			local info = v
			v.id = k
			tinsert(players, info)
		end
		-- players = KRT_Raids[raidNum].players
		if bossNum and KRT_Raids[raidNum].bossKills[bossNum] then
			local _players = {}
			for i, p in ipairs(players) do
				if Utils.checkEntry(KRT_Raids[raidNum]["bossKills"][bossNum]["players"], p.name) then
					tinsert(_players, p)
				end
			end
			return _players
		end
		return players
	end

	-- Checks if the given players in the raid:
	function Raid:CheckPlayer(name, raidNum)
		local found = false
		local players = Raid:GetPlayers(raidNum)
		local originalName = name
		if players ~= nil then
			name = ucfirst(name:trim())
			for i, p in ipairs(players) do
				if name == p.name then
					found = true
					break
				elseif strlen(name) >= 5 and p.name:startsWith(name) then
					name = p.name
					found = true
					break
				end
			end
		end
		return found, name
	end

	-- Returns the players ID:
	function Raid:GetPlayerID(name, raidNum)
		local id = 0
		raidNum = raidNum or KRT_CurrentRaid
		name = name or unitName
		if raidNum and KRT_Raids[raidNum] then
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

	-- Get Player name:
	function Raid:GetPlayerName(id, raidNum)
		local name
		raidNum = raidNum or addon.Logger.selectedRaid or KRT_CurrentRaid
		if raidNum and KRT_Raids[raidNum] then
			for k, p in ipairs(KRT_Raids[raidNum].players) do
				if k == id then
					name = p.name
					break
				end
			end
		end
		return name
	end

	-- Returns a table of items looted by the selected player:
	function Raid:GetPlayerLoot(name, raidNum, bossNum)
		local items = {}
		local loot = Raid:GetLoot(raidNum, bossNum)
		local originalName = name
		name = (type(name) == "number") and Raid:GetPlayerName(name) or name
		for k, v in ipairs(loot) do
			if v.looter == name then
				local info = v
				info.id = k
				tinsert(items, info)
			end
		end
		return items
	end

	-- Get player rank:
	function addon:GetPlayerRank(name, raidNum)
		local players = Raid:GetPlayers(raidNum)
		local rank = 0
		local originalName = name
		name = name or unitName or UnitName("player")
		if next(players) == nil then
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
			for i, p in ipairs(players) do
				if p.name == name then
					rank = p.rank or 0
					break
				end
			end
		end
		return rank
	end

	-- Get player class:
	function addon:GetPlayerClass(name)
		local class = "UNKNOWN"
		local realm = GetRealmName() or UNKNOWN
		local resolvedName = name or unitName
		if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
			class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
		end

		return class
	end

	-- Get player UnitID
	function addon:GetUnitID(name)
		local players = Raid:GetPlayers()
		local id = "none"
		local resolvedName = name
		if players then
			for i, p in ipairs(players) do
				if p.name == name then
					id = "raid" .. tostring(i)
					break
				end
			end
		end
		return id
	end

	-----------------------
	-- Raid & Loot Check --
	-----------------------

	-- Whether the player is a party group:
	function addon:IsInParty()
		local inParty = (GetNumPartyMembers() > 0) and (GetNumRaidMembers() == 0)
		return inParty
	end

	-- Whether the player is a raid group:
	function addon:IsInRaid()
		local raidStatus = (inRaid == true or GetNumRaidMembers() > 0)
		return raidStatus
	end

	-- Check if the raid is using mater loot system:
	function addon:IsMasterLoot()
		local method = select(1, GetLootMethod())
		return (method == "master")
	end

	-- Check if the player is the master looter:
	function addon:IsMasterLooter()
		local method, partyID = GetLootMethod()
		local isML = (partyID and partyID == 0)
		return isML
	end

	-- Utility : Clear all raid icons:
	function addon:ClearRaidIcons()
		local players = Raid:GetPlayers()
		for i, p in ipairs(players) do
			SetRaidTarget("raid" .. tostring(i), 0)
		end
	end
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
		return Utils.print(msg)
	end

	-- Print Green Success Message:
	function addon:PrintSuccess(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_green(msg)
	end

	-- Print Red Error Message:
	function addon:PrintError(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_red(msg)
	end

	-- Print Orange Warning Message:
	function addon:PrintWarning(text, prefix)
		local msg = PreparePrint(text, prefix)
		return Utils.print_orange(msg)
	end

	-- Print Blue Info Message:
	function addon:PrintInfo(text, prefix)
		local msg = PreparePrint(text, prefix)
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

-- ==================== MiniMap Button ==================== --

do
	addon.Minimap = {}
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
			centerX, centerY = (centerX / sqrt(centerX ^ 2 + centerY ^ 2)) * 80,
				(centerY / sqrt(centerX ^ 2 + centerY ^ 2)) * 80
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
end

-- ==================== Rolls Helpers ==================== --

do
	addon.Rolls = {}
	local Rolls = addon.Rolls
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
		end
	end

	-- Adds a roll to the rollsTable and updates tracking
	local function AddRoll(name, roll, itemId)
		roll = tonumber(roll)
		rollsCount = rollsCount + 1
		rollsTable[rollsCount] = { name = name, roll = roll, itemId = itemId }

		if itemId then
			itemRollTracker[itemId] = itemRollTracker[itemId] or {}
			itemRollTracker[itemId][name] = (itemRollTracker[itemId][name] or 0) + 1
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
			else
				selectedPlayer = winner
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
			addon:Print(L.ChatOnlyRollOnce)
			return
		end

		RandomRoll(1, 100)
		playerRollTracker[itemId] = playerRollTracker[itemId] + 1
	end

	-- Returns current roll session state
	function addon:RollStatus()
		return currentRollType, record, canRoll, rolled
	end

	-- Enables or disables recording rolls
	function addon:RecordRolls(bool)
		canRoll, record = bool == true, bool == true
	end

	-- Handles system message for detecting rolls
	function addon:CHAT_MSG_SYSTEM(msg)
		if not msg or not record then return end
		local player, roll, min, max = deformat(msg, RANDOM_ROLL_RESULT)
		if player and roll and min == 1 and max == 100 then
			if not canRoll then
				if not warned then
					self:Announce(L.ChatCountdownBlock)
					warned = true
				end
				return
			end

			local itemId = self:GetCurrentRollItemID()
			if not itemId or lootCount == 0 then
				addon:PrintError("Item ID missing or loot table not ready – roll will be ignored.")
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
				end
				return
			end

			AddRoll(player, roll, itemId)
		end
	end

	-- Returns the current rolls table
	function addon:GetRolls()
		return rollsTable
	end

	-- Sets the rolled flag to true
	function addon:SetRolled()
		rolled = true
	end

	-- Checks if a player has rolled
	function addon:DidRoll(itemId, name)
		if not itemId then
			for i = 1, rollsCount do
				if rollsTable[i].name == name then
					return true
				end
			end
			return false
		end
		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		local used = itemRollTracker[itemId][name] or 0
		local allowed = (currentRollType == rollTypes.reserved and addon.Reserves:GetReserveCountForItem(itemId, name) > 0)
			and addon.Reserves:GetReserveCountForItem(itemId, name) or 1
		local result = used >= allowed
		return result
	end

	-- Returns the highest roll value of the current winner
	function addon:HighestRoll()
		for i = 1, rollsCount do
			if rollsTable[i].name == winner then
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
			return nil
		end
		local itemId = tonumber(string.match(itemLink, "item:(%d+)"))
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
		return result
	end

	-- Checks if the player has reserved the item
	function addon:IsReserved(itemId, name)
		local reserved = addon.Reserves:GetReserveCountForItem(itemId, name) > 0
		return reserved
	end

	-- Gets how many reserves the player has used
	function addon:GetUsedReserveCount(itemId, name)
		itemRollTracker[itemId] = itemRollTracker[itemId] or {}
		local count = itemRollTracker[itemId][name] or 0
		return count
	end

	-- Gets the allowed number of reserves for a player
	function addon:GetAllowedReserves(itemId, name)
		local count = addon.Reserves:GetReserveCountForItem(itemId, name)
		return count
	end

	-- Rebuilds the roll UI and marks the top roll or selected winner
	function addon:FetchRolls()
		local frameName = addon:GetFrameName()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())

		local itemId = self:GetCurrentRollItemID()
		local isSR = currentRollType == rollTypes.reserved

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
			else
				starTarget = winner
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
	end
end

-- ==================== Loot Helpers ==================== --

do
	addon.Loot = {}
	local Loot = addon.Loot
	local frameName

	local lootTable = {}
	local currentItemIndex = 0

	-- Fetches the loot:
	function addon:FetchLoot()
		local oldItem
		if lootCount >= 1 then
			oldItem = GetItemLink(currentItemIndex)
		end
		lootOpened = true
		fromInventory = false
		self:ClearLoot()

		for i = 1, GetNumLootItems() do
			if LootSlotIsItem(i) then
				local itemLink = GetLootSlotLink(i)
				if GetItemFamily(itemLink) ~= 64 then -- no DE mat!
					self:AddItem(itemLink)
				end
			end
		end

		currentItemIndex = 1
		if oldItem ~= nil then
			for t = 1, lootCount do
				if oldItem == GetItemLink(t) then
					currentItemIndex = t
					break
				end
			end
		end
		self:PrepareItem()
	end

	-- Add item to loot table:
	function addon:AddItem(itemLink)
		local itemName, _, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture =
			GetItemInfo(itemLink)

		if not itemName or not itemRarity then
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:SetHyperlink(itemLink)
			GameTooltip:Hide()
			return
		end

		if fromInventory == false then
			local lootThreshold = GetLootThreshold()
			if itemRarity < lootThreshold then
				return
			end
			lootCount = lootCount + 1
		else
			lootCount = 1
			currentItemIndex = 1
		end

		lootTable[lootCount]             = {}
		lootTable[lootCount].itemName    = itemName
		lootTable[lootCount].itemColor   = itemColors[itemRarity + 1]
		lootTable[lootCount].itemLink    = itemLink
		lootTable[lootCount].itemTexture = itemTexture
		TriggerEvent("AddItem", itemLink)
	end

	-- Prepare item display:
	function addon:PrepareItem()
		if ItemExists(currentItemIndex) then
			self:SetItem(lootTable[currentItemIndex])
		else
		end
	end

	-- Set item's display:
	function addon:SetItem(i)
		if i.itemName and i.itemLink and i.itemTexture and i.itemColor then
			frameName = frameName or self:GetFrameName()
			if frameName == nil then return end

			local currentItemLink = _G[frameName .. "Name"]
			currentItemLink:SetText("|c" .. i.itemColor .. i.itemName .. "|r")

			local currentItemBtn = _G[frameName .. "ItemBtn"]
			currentItemBtn:SetNormalTexture(i.itemTexture)

			if self.options.showTooltips then
				currentItemBtn.tooltip_item = i.itemLink
				self:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
			end
			TriggerEvent("SetItem", i.itemLink)
		end
	end

	-- Select an item:
	function addon:SelectItem(i)
		if ItemExists(i) then
			currentItemIndex = i
			self:PrepareItem()
		end
	end

	-- Clear all loot:
	function addon:ClearLoot()
		lootTable = twipe(lootTable)
		lootCount = 0
		frameName = frameName or self:GetFrameName()
		_G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
		_G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
		if frameName == UIMaster:GetName() then
			_G[frameName .. "ItemCount"]:SetText("")
			_G[frameName .. "ItemCount"]:ClearFocus()
			_G[frameName .. "ItemCount"]:Hide()
		end
	end

	-- Returns the current item index:
	function GetItemIndex()
		return currentItemIndex
	end

	-- Returns the current item:
	function GetItem(i)
		i = i or currentItemIndex
		return lootTable[i]
	end

	-- Returns the current item's name:
	function GetItemName(i)
		i = i or currentItemIndex
		return lootTable[i] and lootTable[i].itemName or nil
	end

	-- Returns the current item's link:
	function GetItemLink(i)
		i = i or currentItemIndex
		return lootTable[i] and lootTable[i].itemLink or nil
	end

	-- Returns the current item's teture:
	function GetItemTexture(i)
		i = i or currentItemIndex
		return lootTable[i] and lootTable[i].itemTexture or nil
	end

	-- Checks if a loot item exists:
	function ItemExists(i)
		i = i or currentItemIndex
		return (lootTable[i] ~= nil)
	end

	-- Check if an item is soul bound:
	function ItemIsSoulbound(bag, slot)
		local tip = KRT_FakeTooltip or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
		KRT_FakeTooltip = tip
		tip:SetOwner(UIParent, "ANCHOR_NONE")
		tip:SetBagItem(bag, slot)
		tip:Show()

		local num = tip:NumLines()
		for i = num, 1, -1 do
			local t = _G["KRT_FakeTooltipTextLeft" .. i]:GetText()
			if deformat(t, BIND_TRADE_TIME_REMAINING) ~= nil then
				tip:Hide()
				return false
			elseif t == ITEM_SOULBOUND then
				tip:Hide()
				return true
			end
		end

		tip:Hide()
		return false
	end
end

-- ==================== Master Loot Frame ==================== --

do
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
		Utils.toggle(UIMaster)
	end

	-- Hide frame:
	function Master:Hide()
		if UIMaster and UIMaster:IsShown() then
			UIMaster:Hide()
		end
	end

	-- Button: Select/Remove Item
	function Master:BtnSelectItem(btn)
		if btn == nil or lootCount <= 0 then return end
		if fromInventory == true then
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
		if btn == nil or lootCount <= 0 then return end
		if fromInventory == true then
			addon:Announce(L.ChatReadyCheck)
			DoReadyCheck()
		else
			addon:Announce(L.ChatSpamLoot, "RAID")
			for i = 1, lootCount do
				local itemLink = GetItemLink(i)
				if itemLink then
					addon:Announce(i .. ". " .. itemLink, "RAID")
				end
			end
		end
	end

	-- Button: Open List
	function Master:BtnOpenReserves(btn)
		addon.Reserves:ShowWindow()
	end

	-- Button: Import Reserve
	function Master:BtnImportReserves(btn)
		addon.Reserves:ShowImportBox()
	end

	-- Generic roll button:
	local function AnnounceRoll(rollType, chatMsg)
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
					and L[chatMsg .. "Multiple" .. suff]:format(srList, itemLink, itemCount)
					or L[chatMsg]:format(srList, itemLink)
			else
				local suff = addon.options.sortAscending and "Low" or "High"
				message = itemCount > 1
					and L[chatMsg .. "Multiple" .. suff]:format(itemLink, itemCount)
					or L[chatMsg]:format(itemLink)
			end

			addon:Announce(message)
			_G[frameName .. "ItemCount"]:ClearFocus()
			currentRollItem = addon.Raid:GetLootID(itemID)
		end
	end

	function Master:BtnMS(btn)
		return AnnounceRoll(1, "ChatRollMS")
	end

	function Master:BtnOS(btn)
		return AnnounceRoll(2, "ChatRollOS")
	end

	function Master:BtnSR(btn)
		return AnnounceRoll(3, "ChatRollSR")
	end

	function Master:BtnFree(btn)
		return AnnounceRoll(4, "ChatRollFree")
	end

	function Master:BtnCountdown(btn)
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
		announced = false
		return addon:ClearRolls()
	end

	-- Button: Award/Trade
	function Master:BtnAward(btn)
		if lootCount <= 0 or rollsCount <= 0 then
			return
		end
		countdownRun = false
		local itemLink = GetItemLink()
		_G[frameName .. "ItemCount"]:ClearFocus()
		if fromInventory == true then
			return TradeItem(itemLink, winner, currentRollType, addon:HighestRoll())
		end
		return AssignItem(itemLink, winner, currentRollType, addon:HighestRoll())
	end

	-- Button: Hold item
	function Master:BtnHold(btn)
		if lootCount <= 0 or holder == nil then return end
		countdownRun = false
		local itemLink = GetItemLink()
		if itemLink == nil then return end
		currentRollType = rollTypes.hold
		if fromInventory == true then
			return TradeItem(itemLink, holder, rollTypes.hold, 0)
		end
		return AssignItem(itemLink, holder, rollTypes.hold, 0)
	end

	-- Button: Bank item
	function Master:BtnBank(btn)
		if lootCount <= 0 or banker == nil then return end
		countdownRun = false
		local itemLink = GetItemLink()
		if itemLink == nil then return end
		currentRollType = rollTypes.bank
		if fromInventory == true then
			return TradeItem(itemLink, banker, rollTypes.bank, 0)
		end
		return AssignItem(itemLink, banker, rollTypes.bank, 0)
	end

	-- Button: Disenchant item
	function Master:BtnDisenchant(btn)
		if lootCount <= 0 or disenchanter == nil then return end
		countdownRun = false
		local itemLink = GetItemLink()
		if itemLink == nil then return end
		currentRollType = rollTypes.disenchant
		if fromInventory == true then
			return TradeItem(itemLink, disenchanter, rollTypes.disenchant, 0)
		end
		return AssignItem(itemLink, disenchanter, rollTypes.disenchant, 0)
	end

	-- Select winner:
	function Master:SelectWinner(btn)
		if not btn then return end
		local btnName = btn:GetName()
		local player = _G[btnName .. "Name"]:GetText()
		if player ~= nil then
			if IsControlKeyDown() then
				local roll = _G[btnName .. "Roll"]:GetText()
				addon:Announce(format(L.ChatPlayerRolled, player, roll))
				return
			end
			winner = player:trim()
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
			announced = false
			selectionFrame:Hide()
			addon:SelectItem(index)
		end
	end

	-- Localizing ui frame:
	function LocalizeUIFrame()
		if localized then return end
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
		_G[frameName .. "ItemCount"]:SetScript("OnTextChanged", function(self)
			announced = false
		end)
		if next(dropDownData) == nil then
			for i = 1, 8 do dropDownData[i] = {} end
		end
		dropDownFrameHolder       = _G[frameName .. "HoldDropDown"]
		dropDownFrameBanker       = _G[frameName .. "BankDropDown"]
		dropDownFrameDisenchanter = _G[frameName .. "DisenchantDropDown"]
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

			Utils.setText(_G[frameName .. "CountdownBtn"], L.BtnStop, L.BtnCountdown, countdownRun == true)
			Utils.setText(_G[frameName .. "AwardBtn"], TRADE, L.BtnAward, fromInventory == true)

			if countdownRun == true then
				local tick = ceil(addon.options.countdownDuration - GetTime() + countdownStart)
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
					countdownRun = false
					countdownPos = 0
					addon:Announce(L.ChatCountdownEnd)
					if addon.options.countdownRollsBlock then
						addon:RecordRolls(false)
					end
				end
			end

			Utils.enableDisable(_G[frameName .. "SelectItemBtn"], lootCount > 1 or (fromInventory and lootCount >= 1))
			Utils.enableDisable(_G[frameName .. "SpamLootBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "MSBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "OSBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "SRBtn"], lootCount >= 1 and addon.Reserves:HasData())
			Utils.enableDisable(_G[frameName .. "FreeBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "CountdownBtn"], lootCount >= 1 and ItemExists())
			Utils.enableDisable(_G[frameName .. "HoldBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "BankBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "DisenchantBtn"], lootCount >= 1)
			Utils.enableDisable(_G[frameName .. "AwardBtn"], (lootCount >= 1 and rollsCount >= 1))
			Utils.enableDisable(_G[frameName .. "OpenReservesBtn"], addon.Reserves:HasData())
			Utils.enableDisable(_G[frameName .. "ImportReservesBtn"], not addon.Reserves:HasData())

			local rollType, record, canRoll, rolled = addon:RollStatus()
			Utils.enableDisable(_G[frameName .. "RollBtn"], record and canRoll and rolled == false)
			Utils.enableDisable(_G[frameName .. "ClearBtn"], rollsCount >= 1)

			Utils.setText(_G[frameName .. "SelectItemBtn"], L.BtnRemoveItem, L.BtnSelectItem, fromInventory)
			Utils.setText(_G[frameName .. "SpamLootBtn"], READY_CHECK, L.BtnSpamLoot, fromInventory)
		end
	end

	-- Initialize DropDowns:
	function InitializeDropDowns()
		if UIDROPDOWNMENU_MENU_LEVEL == 2 then
			local g = UIDROPDOWNMENU_MENU_VALUE
			local m = dropDownData[g]
			for key, value in pairs(m) do
				local info        = UIDropDownMenu_CreateInfo()
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
					local info        = UIDropDownMenu_CreateInfo()
					info.hasArrow     = 1
					info.notCheckable = 1
					info.text         = GROUP .. " " .. key
					info.value        = key
					info.owner        = UIDROPDOWNMENU_OPEN_MENU
					UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
				end
			end
		end
	end

	-- Prepare DropDowns:
	function PrepareDropDowns()
		for i = 1, 8 do
			dropDownData[i] = twipe(dropDownData[i])
		end
		dropDownGroupData = twipe(dropDownGroupData)

		for p = 1, GetRealNumRaidMembers() do
			local name, _, subgroup = GetRaidRosterInfo(p)
			if name then
				dropDownData[subgroup][name] = name
				dropDownGroupData[subgroup] = true
			end
		end
	end

	-- OnClick DropDowns:
	function Master:OnClickDropDown(owner, value)
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
		if name == dropDownFrameHolder:GetName() then
			holder = KRT_Raids[KRT_CurrentRaid].holder
			if holder and addon:GetUnitID(holder) == "none" then
				KRT_Raids[KRT_CurrentRaid].holder = nil
				holder = nil
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
			selectionFrame = CreateFrame("Frame", nil, UIMaster, "KRTSimpleFrameTemplate")
			selectionFrame:Hide()
		end
		local index = 1
		local btnName = frameName .. "ItemSelectionBtn" .. index
		local btn = _G[btnName]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btnName = frameName .. "ItemSelectionBtn" .. index
			btn = _G[btnName]
		end
	end

	-- Update the selection frame:
	function UpdateSelectionFrame()
		CreateSelectionFrame()
		local height = 5
		for i = 1, lootCount do
			local btnName = frameName .. "ItemSelectionBtn" .. i
			local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
			btn:SetID(i)
			btn:Show()
			local itemName = GetItemName(i)
			local itemNameBtn = _G[btnName .. "Name"]
			itemNameBtn:SetText(itemName)
			local itemTexture = GetItemTexture(i)
			local itemTextureBtn = _G[btnName .. "Icon"]
			itemTextureBtn:SetTexture(itemTexture)
			btn:SetPoint("TOPLEFT", selectionFrame, "TOPLEFT", 0, -height)
			height = height + 37
		end
		selectionFrame:SetHeight(height)
		if lootCount <= 0 then
			selectionFrame:Hide()
		end
	end

	-- ITEM_LOCKED:
	function addon:ITEM_LOCKED(inBag, inSlot)
		if not inBag or not inSlot then return end
		local itemTexture, itemCount, locked, quality, _, _, itemLink = GetContainerItemInfo(inBag, inSlot)
		if not itemLink or not itemTexture then return end
		_G[frameName .. "ItemBtn"]:SetScript("OnClick", function(self)
			if not ItemIsSoulbound(inBag, inSlot) then
				_G[frameName .. "ItemCount"]:SetText("")
				_G[frameName .. "ItemCount"]:ClearFocus()
				_G[frameName .. "ItemCount"]:Hide()

				fromInventory = true
				addon:AddItem(itemLink)
				addon:PrepareItem()
				announced        = false
				itemInfo.bagID   = inBag
				itemInfo.slotID  = inSlot
				itemInfo.count   = GetItemCount(itemLink)
				itemInfo.isStack = (itemCount > 1)
				if itemInfo.count >= 1 then
					itemCount = itemInfo.count
					_G[frameName .. "ItemCount"]:SetText(itemInfo.count)
					_G[frameName .. "ItemCount"]:Show()
					_G[frameName .. "ItemCount"]:SetFocus()
				end
			end
			ClearCursor()
		end)
	end

	-- LOOT_OPENED:
	function addon:LOOT_OPENED()
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
		if itemCount == 1 and trader and winner and trader ~= winner then
			if tAccepted == 1 and pAccepted == 1 then
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
			return false
		end

		for p = 1, 40 do
			if GetMasterLootCandidate(p) == playerName then
				GiveMasterLoot(itemIndex, p)
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
		return false
	end

	-- Trade item to player:
	function TradeItem(itemLink, playerName, rollType, rollValue)
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
						tinsert(winners, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
					else
						SetRaidTarget(rolls[i].name, i + 1)
						tinsert(winners, markers[i] .. " " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
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
			announced = false
		end
	end)
end

-- ==================== Raid Helper Reserves ==================== --
do
	addon.Reserves = {}
	local Reserves = addon.Reserves

	local frameName
	local LocalizeUIFrame
	local localized = false
	local UpdateUIFrame
	local updateInterval = 0.5

	local reservesData = {}
	local reservesByItemID = {}
	local reserveListFrame, scrollFrame, scrollChild
	local reserveItemRows, rowsByItemID = {}, {}
	local pendingItemInfo = {}
	local collapsedBossGroups = {}

	----------------------------------------------------------------
	-- Saved Data
	----------------------------------------------------------------
	function Reserves:Save()
		KRT_SavedReserves = table.deepCopy(reservesData)
		KRT_SavedReserves.reservesByItemID = table.deepCopy(reservesByItemID)
	end

	function Reserves:Load()
		if KRT_SavedReserves then
			reservesData = table.deepCopy(KRT_SavedReserves)
			reservesByItemID = table.deepCopy(KRT_SavedReserves.reservesByItemID or {})
		else
			reservesData = {}
			reservesByItemID = {}
		end
	end

	function Reserves:ResetSaved()
		KRT_SavedReserves = nil
		wipe(reservesData)
		wipe(reservesByItemID)
		self:RefreshWindow()
		self:CloseWindow()
		addon:Print(L.StrReserveListCleared)
	end

	function Reserves:HasData()
		return next(reservesData) ~= nil
	end

	----------------------------------------------------------------
	-- UI Windows
	----------------------------------------------------------------
	function Reserves:ShowWindow()
		if not reserveListFrame then
			addon:PrintError("Reserve List frame not available.")
			return
		end
		reserveListFrame:Show()
	end

	function Reserves:CloseWindow()
		if reserveListFrame then reserveListFrame:Hide() end
	end

	function Reserves:ShowImportBox()
		local frame = _G["KRTImportWindow"]
		if not frame then
			addon:PrintError("KRTImportWindow not found.")
			return
		end
		frame:Show()
		if _G["KRTImportEditBox"] then
			_G["KRTImportEditBox"]:SetText("")
		end
		_G[frame:GetName() .. "Title"]:SetText(format(titleString, L.StrImportReservesTitle))
	end

	function Reserves:OnLoad(frame)
		reserveListFrame = frame
		frameName = frame:GetName()

		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
		frame:SetScript("OnUpdate", UpdateUIFrame)

		scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"]
		scrollChild = scrollFrame and scrollFrame.ScrollChild or _G["KRTReserveListFrameScrollChild"]

		local buttons = {
			CloseButton = "CloseWindow",
			ClearButton = "ResetSaved",
			QueryButton = "QueryMissingItems",
		}
		for suff, method in pairs(buttons) do
			local btn = _G["KRTReserveListFrame" .. suff]
			if btn and self[method] then
				btn:SetScript("OnClick", function() self[method](self) end)
			end
		end

		LocalizeUIFrame()

		local refreshFrame = CreateFrame("Frame")
		refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		refreshFrame:SetScript("OnEvent", function(_, _, itemId)
			if pendingItemInfo[itemId] then
				local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
				if name then
					self:UpdateReserveItemData(itemId, name, link, tex)
					pendingItemInfo[itemId] = nil
				else
				end
			end
		end)
	end

	----------------------------------------------------------------
	-- Localization and UI Update Functions
	----------------------------------------------------------------
	-- Localize UI Frame:
	function LocalizeUIFrame()
		if localized then
			return
		end
		if frameName then
			_G[frameName .. "Title"]:SetText(format(titleString, L.StrRaidReserves))
		end
		localized = true
	end

	-- Update UI Frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			local clearButton = _G[frameName .. "ClearButton"]
			if clearButton then
				local hasData = Reserves:HasData()
				Utils.enableDisable(clearButton, hasData)
			end

			local queryButton = _G[frameName .. "QueryButton"]
			if queryButton then
				local hasData = Reserves:HasData()
				Utils.enableDisable(queryButton, hasData)
			end
		end
	end

	----------------------------------------------------------------
	-- Reserve Data
	----------------------------------------------------------------
	-- Get specific reserve for a player:
	function Reserves:GetReserve(playerName)
		local player = playerName:lower():trim()
		local reserve = reservesData[player]

		-- Log when the function is called and show the reserve for the player
		if reserve then
		else
		end

		return reserve
	end

	-- Get all reserves:
	function Reserves:GetAllReserves()
		return reservesData
	end

	-- Parse imported text
	function Reserves:ParseCSV(csv)
		wipe(reservesData)
		wipe(reservesByItemID)

		local function cleanCSVField(field)
			if not field then return nil end
			return field:gsub('^"(.-)"$', '%1'):trim()
		end

		local firstLine = true
		for line in csv:gmatch("[^\r\n]+") do
			if firstLine then
				firstLine = false
			else
				local _, itemIdStr, source, playerName, class, spec, note, plus = line:match(
					'^"?(.-)"?,(.-),(.-),(.-),(.-),(.-),(.-),(.-)')

				-- Clean CSV field
				itemIdStr                                                       = cleanCSVField(itemIdStr)
				source                                                          = cleanCSVField(source)
				playerName                                                      = cleanCSVField(playerName)
				class                                                           = cleanCSVField(class)
				spec                                                            = cleanCSVField(spec)
				note                                                            = cleanCSVField(note)
				plus                                                            = cleanCSVField(plus)

				local itemId                                                    = tonumber(itemIdStr)
				local normalized                                                = playerName and
					playerName:lower():trim()

				if normalized and itemId then
					-- Log the player being processed
					reservesData[normalized] = reservesData[normalized] or {
						original = playerName,
						reserves = {}
					}

					local found = false
					for _, entry in ipairs(reservesData[normalized].reserves) do
						if entry.rawID == itemId then
							entry.quantity = (entry.quantity or 1) + 1
							found = true
							break
						end
					end

					if not found then
						local entry = {
							rawID    = itemId,
							itemLink = nil,
							itemName = nil,
							itemIcon = nil,
							quantity = 1,
							class    = class ~= "" and class or nil,
							note     = note ~= "" and note or nil,
							plus     = tonumber(plus) or 0,
							source   = source ~= "" and source or nil
						}
						tinsert(reservesData[normalized].reserves, entry)
						reservesByItemID[itemId] = reservesByItemID[itemId] or {}
						tinsert(reservesByItemID[itemId], entry)
						-- Log new reserve entry added
					end
				end
			end
		end
		-- Log when the CSV parsing is completed

		self:RefreshWindow()
		self:Save()
	end

	----------------------------------------------------------------
	-- Query / Tooltip
	----------------------------------------------------------------
	-- Query for item info
	function Reserves:QueryItemInfo(itemId)
		if not itemId then return end
		local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
		if name and link and tex then
			self:UpdateReserveItemData(itemId, name, link, tex)
			return true
		else
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:SetHyperlink("item:" .. itemId)
			GameTooltip:Hide()
			return false
		end
	end

	-- Query all missing items for reserves
	function Reserves:QueryMissingItems()
		local count = 0
		for _, player in pairs(reservesData) do
			if type(player) == "table" and type(player.reserves) == "table" then
				for _, r in ipairs(player.reserves) do
					if not r.itemLink or not r.itemIcon then
						if not self:QueryItemInfo(r.rawID) then
							count = count + 1
						end
					end
				end
			end
		end
		addon:Print(count > 0 and ("Requested info for " .. count .. " missing items.") or
			"All item infos are available.")
	end

	-- Update reserve item data
	function Reserves:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
		for _, player in pairs(reservesData) do
			if type(player) == "table" and type(player.reserves) == "table" then
				for _, r in ipairs(player.reserves or {}) do
					if r.rawID == itemId then
						r.itemName = itemName
						r.itemLink = itemLink
						r.itemIcon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
					end
				end
			end
		end

		local rows = rowsByItemID[itemId]
		if not rows then return end

		for _, row in ipairs(rows) do
			local icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
			row.icon:SetTexture(icon)

			if row.quantityText then
				if row.quantityText:GetText() and row.quantityText:GetText():match("^%d+x$") then
					row.quantityText:SetText(row.quantityText:GetText()) -- Preserve format
				end
			end

			local tooltipText = itemLink or itemName or ("Item ID: " .. itemId)
			row.nameText:SetText(tooltipText)

			row.iconBtn:SetScript("OnEnter", function()
				GameTooltip:SetOwner(row.iconBtn, "ANCHOR_RIGHT")
				if itemLink then
					GameTooltip:SetHyperlink(itemLink)
				else
					GameTooltip:SetText("Item ID: " .. itemId, 1, 1, 1)
				end
				GameTooltip:Show()
			end)

			row.iconBtn:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end
	end

	-- Get reserve count for a specific item for a player
	function Reserves:GetReserveCountForItem(itemId, playerName)
		local normalized = playerName and playerName:lower()
		local entry = reservesData[normalized]
		if not entry then return 0 end
		for _, r in ipairs(entry.reserves or {}) do
			if r.rawID == itemId then
				return r.quantity or 1
			end
		end
		return 0
	end

	----------------------------------------------------------------
	-- Display / Table Rendering
	----------------------------------------------------------------
	function Reserves:RefreshWindow()
		if not reserveListFrame or not scrollChild then return end

		-- Hide and clear old rows
		for _, row in ipairs(reserveItemRows) do row:Hide() end
		wipe(reserveItemRows)
		wipe(rowsByItemID)

		-- Group reserves by item source, ID, and quantity
		local grouped = {}
		for _, player in pairs(reservesData) do
			for _, r in ipairs(player.reserves or {}) do
				local key = (r.source or "Unknown") .. "||" .. r.rawID .. "||" .. (r.quantity or 1)
				grouped[key] = grouped[key] or {
					itemId = r.rawID,
					quantity = r.quantity or 1,
					itemLink = r.itemLink,
					itemName = r.itemName,
					itemIcon = r.itemIcon,
					source = r.source or "Unknown",
					players = {}
				}
				tinsert(grouped[key].players, player.original)
			end
		end

		-- Sort the grouped reserves
		local displayList = {}
		for _, data in pairs(grouped) do
			tinsert(displayList, data)
		end
		table.sort(displayList, function(a, b)
			if a.source ~= b.source then return a.source < b.source end
			if a.itemId ~= b.itemId then return a.itemId < b.itemId end
			return a.quantity < b.quantity
		end)

		local rowHeight, yOffset = 34, 0
		local seenSources = {}

		-- Create headers and reserve rows
		for index, entry in ipairs(displayList) do
			local source = entry.source

			-- Log for new source groups
			if not seenSources[source] then
				seenSources[source] = true
				if collapsedBossGroups[source] == nil then
					collapsedBossGroups[source] = false
				end

				local headerBtn = CreateFrame("Button", nil, scrollChild)
				headerBtn:SetSize(320, 28)
				headerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

				local fullLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				fullLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
				fullLabel:SetTextColor(1, 0.82, 0)
				local prefix = collapsedBossGroups[source] and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or
					"|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
				fullLabel:SetText(prefix .. source)
				fullLabel:SetPoint("CENTER", headerBtn, "CENTER", 0, 0)

				local leftLine = headerBtn:CreateTexture(nil, "ARTWORK")
				leftLine:SetTexture("Interface\\Buttons\\WHITE8x8")
				leftLine:SetVertexColor(1, 1, 1, 0.3)
				leftLine:SetHeight(1)
				leftLine:SetPoint("RIGHT", fullLabel, "LEFT", -6, 0)
				leftLine:SetPoint("LEFT", headerBtn, "LEFT", 4, 0)

				local rightLine = headerBtn:CreateTexture(nil, "ARTWORK")
				rightLine:SetTexture("Interface\\Buttons\\WHITE8x8")
				rightLine:SetVertexColor(1, 1, 1, 0.3)
				rightLine:SetHeight(1)
				rightLine:SetPoint("LEFT", fullLabel, "RIGHT", 6, 0)
				rightLine:SetPoint("RIGHT", headerBtn, "RIGHT", -4, 0)

				-- Click toggle
				headerBtn:SetScript("OnClick", function()
					collapsedBossGroups[source] = not collapsedBossGroups[source]
					Reserves:RefreshWindow()
				end)

				tinsert(reserveItemRows, headerBtn)
				yOffset = yOffset + 24
			end

			-- Log for rows that are added
			if not collapsedBossGroups[source] then
				local row = Reserves:CreateReserveRow(scrollChild, entry, yOffset, index)
				tinsert(reserveItemRows, row)
				yOffset = yOffset + rowHeight
			end
		end

		-- Update the scrollable area
		scrollChild:SetHeight(yOffset)
		scrollFrame:SetVerticalScroll(0)
	end

	-- Create a new row for displaying a reserve
	function Reserves:CreateReserveRow(parent, info, yOffset, index)
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(320, 34)
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
		row._rawID = info.itemId

		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(row)
		bg:SetTexture("Interface\\Buttons\\WHITE8x8")
		bg:SetVertexColor(index % 2 == 0 and 0.1 or 0, 0.1, 0.1, 0.3)

		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(32, 32)
		icon:SetPoint("LEFT", row, "LEFT", 0, 0)

		local iconBtn = CreateFrame("Button", nil, row)
		iconBtn:SetAllPoints(icon)

		local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
		nameText:SetText(info.itemLink or info.itemName or ("[Item " .. info.itemId .. "]"))

		local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		playerText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
		playerText:SetText(table.concat(info.players or {}, ", "))

		local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		quantityText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
		quantityText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		quantityText:SetTextColor(1, 1, 1)

		if info.quantity and info.quantity > 1 then
			quantityText:SetText(info.quantity .. "x")
			quantityText:Show()
		else
			quantityText:Hide()
		end

		icon:SetTexture(info.itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

		iconBtn:SetScript("OnEnter", function()
			GameTooltip:SetOwner(iconBtn, "ANCHOR_RIGHT")
			if info.itemLink then
				GameTooltip:SetHyperlink(info.itemLink)
			else
				GameTooltip:SetText("Item ID: " .. info.itemId, 1, 1, 1)
			end
			if info.source then
				GameTooltip:AddLine("Dropped by: " .. info.source, 0.8, 0.8, 0.8)
			end
			GameTooltip:Show()
		end)

		iconBtn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		row.icon = icon
		row.iconBtn = iconBtn
		row.nameText = nameText
		row.quantityText = quantityText

		row:Show()
		rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
		tinsert(rowsByItemID[info.itemId], row)

		return row
	end

	----------------------------------------------------------------
	-- SR Announcement
	----------------------------------------------------------------
	function Reserves:GetPlayersForItem(itemId)
		local players = {}
		-- Loop through each player and their reserves
		for _, player in pairs(reservesData or {}) do
			for _, r in ipairs(player.reserves or {}) do
				if r.rawID == itemId then
					local qty = r.quantity or 1
					local display = qty > 1 and ("(" .. qty .. "x)" .. player.original) or player.original
					tinsert(players, display)
					-- Log when a player is added for an item
					break
				end
			end
		end
		return players
	end

	function Reserves:FormatReservedPlayersLine(itemId)
		local list = self:GetPlayersForItem(itemId)
		-- Log the list of players found for the item
		return #list > 0 and table.concat(list, ", ") or ""
	end
end

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
		-- Countdown:
		countdownDuration      = 5,
		countdownRollsBlock    = true,
	}

	-- Load default options:
	local function LoadDefaultOptions()
		for k, v in pairs(defaultOptions) do
			KRT_Options[k] = v
		end
	end

	-- Load addon options:
	function LoadOptions()
		addon.options = KRT_Options
		Utils.fillTable(addon.options, defaultOptions)

		if not addon.options.useRaidWarning then
			addon.options.countdownSimpleRaidMsg = false
		end
	end

	-- External reset of default options:
	function Config:Default()
		return LoadDefaultOptions()
	end

	-- OnLoad frame:
	function Config:OnLoad(frame)
		if not frame then return end
		UIConfig = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Toggle frame visibility:
	function Config:Toggle()
		Utils.toggle(UIConfig)
	end

	-- Hide frame:
	function Config:Hide()
		if UIConfig and UIConfig:IsShown() then
			UIConfig:Hide()
		end
	end

	-- OnClick options:
	function Config:OnClick(btn)
		if not btn then return end
		frameName = frameName or btn:GetParent():GetName()
		local value, name = nil, btn:GetName()
		if name ~= frameName .. "countdownDuration" then
			value = (btn:GetChecked() == 1) or false
			if name == frameName .. "minimapButton" then
				addon:ToggleMinimapButton()
			end
		else
			value = btn:GetValue()
			_G[frameName .. "countdownDurationText"]:SetText(value)
		end
		name = strsub(name, strlen(frameName) + 1)
		TriggerEvent("Config" .. name, value)
		KRT_Options[name] = value
	end

	-- Localizing ui frame:
	function LocalizeUIFrame()
		if localized then
			return
		end
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

	-- OnUpdate frame:
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
					countdownSimpleRaidMsgStr:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
						HIGHLIGHT_FONT_COLOR.b)
					countdownSimpleRaidMsgBtn:SetChecked(addon.options.countdownSimpleRaidMsg)
				end
			end
		end
	end
end

-- ==================== Warnings Frame ==================== --

do
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
		if not frame then return end
		UIWarnings = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Externally update frame:
	function Warnings:Update()
		return FetchWarnings()
	end

	-- Toggle frame visibility:
	function Warnings:Toggle()
		Utils.toggle(UIWarnings)
	end

	-- Hide frame:
	function Warnings:Hide()
		if UIWarnings and UIWarnings:IsShown() then
			UIWarnings:Hide()
		end
	end

	-- Warning selection:
	function Warnings:Select(btn)
		if btn == nil or isEdit == true then return end
		local bName = btn:GetName()
		local wID = tonumber(_G[bName .. "ID"]:GetText())
		if KRT_Warnings[wID] == nil then return end
		if IsControlKeyDown() then
			selectedID = nil
			tempSelectedID = wID
			return self:Announce(tempSelectedID)
		end
		selectedID = (wID ~= selectedID) and wID or nil
	end

	-- Edit/Save warning:
	function Warnings:Edit()
		local wName, wContent
		if selectedID ~= nil then
			local w = KRT_Warnings[selectedID]
			if w == nil then
				selectedID = nil
				return
			end
			if not isEdit and (tempName == "" and tempContent == "") then
				_G[frameName .. "Name"]:SetText(w.name)
				_G[frameName .. "Name"]:SetFocus()
				_G[frameName .. "Content"]:SetText(w.content)
				isEdit = true
				return
			end
		end
		wName    = _G[frameName .. "Name"]:GetText()
		wContent = _G[frameName .. "Content"]:GetText()
		return SaveWarning(wContent, wName, selectedID)
	end

	-- Delete Warning:
	function Warnings:Delete(btn)
		if btn == nil or selectedID == nil then return end
		local oldWarnings = {}
		for i, w in ipairs(KRT_Warnings) do
			_G[frameName .. "WarningBtn" .. i]:Hide()
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
	end

	-- Announce Warning:
	function Warnings:Announce(wID)
		if KRT_Warnings == nil then return end
		if wID == nil then
			wID = (selectedID ~= nil) and selectedID or tempSelectedID
		end
		if wID <= 0 or KRT_Warnings[wID] == nil then return end
		tempSelectedID = nil -- Always clear temporary selected id:
		addon:Announce(KRT_Warnings[wID].content)
	end

	-- Cancel editing/adding:
	function Warnings:Cancel()
		_G[frameName .. "Name"]:SetText("")
		_G[frameName .. "Name"]:ClearFocus()
		_G[frameName .. "Content"]:SetText("")
		_G[frameName .. "Content"]:ClearFocus()
		selectedID = nil
		tempSelectedID = nil
		isEdit = false
	end

	-- Localizing UI frame:
	function LocalizeUIFrame()
		if localized then return end
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

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if fetched == false then FetchWarnings() end
			if #KRT_Warnings > 0 then
				for i = 1, #KRT_Warnings do
					if selectedID == i and _G[frameName .. "WarningBtn" .. i] then
						_G[frameName .. "WarningBtn" .. i]:LockHighlight()
						_G[frameName .. "OutputName"]:SetText(KRT_Warnings[selectedID].name)
						_G[frameName .. "OutputContent"]:SetText(KRT_Warnings[selectedID].content)
						_G[frameName .. "OutputContent"]:SetTextColor(1, 1, 1)
					else
						_G[frameName .. "WarningBtn" .. i]:UnlockHighlight()
					end
				end
			end
			if selectedID == nil then
				_G[frameName .. "OutputName"]:SetText(L.StrWarningsHelp)
				_G[frameName .. "OutputContent"]:SetText(L.StrWarningsHelp)
				_G[frameName .. "OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
			end
			tempName    = _G[frameName .. "Name"]:GetText()
			tempContent = _G[frameName .. "Content"]:GetText()
			Utils.enableDisable(_G[frameName .. "EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID ~= nil)
			Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID ~= nil)
			Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit,
				(tempName ~= "" or tempContent ~= "") or selectedID == nil)
		end
	end

	-- Saving a Warning:
	function SaveWarning(wContent, wName, wID)
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
			tinsert(KRT_Warnings, { name = wName, content = wContent })
		end
		_G[frameName .. "Name"]:SetText("")
		_G[frameName .. "Name"]:ClearFocus()
		_G[frameName .. "Content"]:SetText("")
		_G[frameName .. "Content"]:ClearFocus()
		Warnings:Cancel()
		Warnings:Update()
	end

	-- Fetch Warnings:
	function FetchWarnings()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for i, w in pairs(KRT_Warnings) do
			local btnName = frameName .. "WarningBtn" .. i
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTWarningButtonTemplate")
			btn:Show()
			local ID = _G[btnName .. "ID"]
			ID:SetText(i)
			local wName = _G[btnName .. "Name"]
			wName:SetText(w.name)
			btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
			btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
			totalHeight = totalHeight + btn:GetHeight()
		end
		fetched = true
	end
end

-- ==================== MS Changes Frame ==================== --

do
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
		if not frame then return end
		UIChanges = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Toggle frame visibility:
	function Changes:Toggle()
		CancelChanges()
		Utils.toggle(UIChanges)
	end

	-- Hide frame:
	function Changes:Hide()
		if UIChanges and UIChanges:IsShown() then
			CancelChanges()
			UIChanges:Hide()
		end
	end

	-- Clear Changes:
	function Changes:Clear()
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
		if not KRT_CurrentRaid then return end
		addon:Announce(L.StrChangesDemand)
	end

	-- Spam Changes:
	function Changes:Announce()
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
		changesTable = KRT_CurrentRaid and KRT_Raids[KRT_CurrentRaid].changes or {}
	end

	-- Fetch All Changes:
	function FetchChanges()
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
		isAdd = false
		isEdit = false
		selectedID = nil
		tempSelectedID = nil
		_G[frameName .. "Name"]:SetText("")
		_G[frameName .. "Name"]:ClearFocus()
		_G[frameName .. "Spec"]:SetText("")
		_G[frameName .. "Spec"]:ClearFocus()
	end
end

-- ==================== LFM Spam Frame ==================== --

do
	addon.Spammer = {}
	local Spammer = addon.Spammer

	local spamFrame = CreateFrame("Frame")
	local frameName

	local LocalizeUIFrame
	local localized = false

	local UpdateUIFrame
	local updateInterval = 0.05

	local FindAchievement

	local loaded = false

	local name, tankClass, healerClass, meleeClass, rangedClass
	local duration = 60
	local tank = 0
	local healer = 0
	local melee = 0
	local ranged = 0
	local message, output = nil, "LFM"
	local finalOutput = ""
	local length = 0
	local channels = {}

	local ticking = false
	local paused = false
	local tickStart, tickPos = 0, 0

	local ceil = math.ceil

	-- OnLoad frame:
	function Spammer:OnLoad(frame)
		if not frame then return end
		UISpammer = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Toggle frame visibility:
	function Spammer:Toggle()
		Utils.toggle(UISpammer)
	end

	-- Hide frame:
	function Spammer:Hide()
		if UISpammer and UISpammer:IsShown() then
			UISpammer:Hide()
		end
	end

	-- Save edit box:-
	function Spammer:Save(box)
		if not box then return end
		local boxName = box:GetName()
		local target = gsub(boxName, frameName, "")
		if find(target, "Chat") then
			KRT_Spammer.Channels = KRT_Spammer.Channels or {}
			local channel = gsub(target, "Chat", "")
			local checked = (box:GetChecked() == 1)
			local existed = Utils.checkEntry(KRT_Spammer.Channels, channel)
			if checked and not existed then
				tinsert(KRT_Spammer.Channels, channel)
			elseif not checked and existed then
				Utils.removeEntry(KRT_Spammer.Channels, channel)
			end
		else
			local value = box:GetText():trim()
			value = (value == "") and nil or value
			KRT_Spammer[target] = value
			box:ClearFocus()
			if ticking and paused then paused = false end
		end
		loaded = false
	end

	-- Start spamming:
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
				-- Spammer:Spam()
			end
		end
	end

	-- Stop spamming:
	function Spammer:Stop()
		_G[frameName .. "Tick"]:SetText(duration or 0)
		ticking = false
		paused = false
	end

	-- Pausing spammer
	function Spammer:Pause()
		paused = true
	end

	-- Send spam message:
	function Spammer:Spam()
		if strlen(finalOutput) > 255 then
			addon:PrintError(L.StrSpammerErrLength)
			ticking = false
			return
		end
		if #channels <= 0 then
			SendChatMessage(tostring(finalOutput), "YELL")
			return
		end
		for i, c in ipairs(channels) do
			if c == "Guild" or c == "Yell" then
				SendChatMessage(tostring(finalOutput), upper(c))
			else
				SendChatMessage(tostring(finalOutput), "CHANNEL", nil, c)
			end
		end
	end

	-- Tab move between edit boxes:
	function Spammer:Tab(a, b)
		local target
		if IsShiftKeyDown() and _G[frameName .. b] ~= nil then
			target = _G[frameName .. b]
		elseif _G[frameName .. a] ~= nil then
			target = _G[frameName .. a]
		end
		if target then target:SetFocus() end
	end

	-- Clears Data
	function Spammer:Clear()
		for k, _ in pairs(KRT_Spammer) do
			if k ~= "Channels" and k ~= "Duration" then
				KRT_Spammer[k] = nil
			end
		end
		message, output, finalOutput = nil, "LFM", ""
		Spammer:Stop()
		_G[frameName .. "Name"]:SetText("")
		_G[frameName .. "Tank"]:SetText("")
		_G[frameName .. "TankClass"]:SetText("")
		_G[frameName .. "Healer"]:SetText("")
		_G[frameName .. "HealerClass"]:SetText("")
		_G[frameName .. "Melee"]:SetText("")
		_G[frameName .. "MeleeClass"]:SetText("")
		_G[frameName .. "Ranged"]:SetText("")
		_G[frameName .. "RangedClass"]:SetText("")
		_G[frameName .. "Message"]:SetText("")
	end

	-- Localizing ui frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName .. "CompStr"]:SetText(L.StrSpammerCompStr)
			_G[frameName .. "NeedStr"]:SetText(L.StrSpammerNeedStr)
			_G[frameName .. "MessageStr"]:SetText(L.StrSpammerMessageStr)
			_G[frameName .. "PreviewStr"]:SetText(L.StrSpammerPreviewStr)
		end
		_G[frameName .. "Title"]:SetText(format(titleString, L.StrSpammer))
		_G[frameName .. "StartBtn"]:SetScript("OnClick", Spammer.Start)

		local durationBox = _G[frameName .. "Duration"]
		durationBox.tooltip_title = AUCTION_DURATION
		addon:SetTooltip(durationBox, L.StrSpammerDurationHelp)

		local messageBox = _G[frameName .. "Message"]
		messageBox.tooltip_title = L.StrMessage
		addon:SetTooltip(messageBox, {
			L.StrSpammerMessageHelp1,
			L.StrSpammerMessageHelp2,
			L.StrSpammerMessageHelp3,
		})

		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not loaded then
				for k, v in pairs(KRT_Spammer) do
					if k == "Channels" then
						for i, c in ipairs(v) do
							_G[frameName .. "Chat" .. c]:SetChecked()
						end
					elseif _G[frameName .. k] then
						_G[frameName .. k]:SetText(v)
					end
				end
				loaded = true
			end

			-- We build the message only if the frame is shown
			if UISpammer:IsShown() then
				channels    = KRT_Spammer.Channels or {}
				name        = _G[frameName .. "Name"]:GetText():trim()
				tank        = tonumber(_G[frameName .. "Tank"]:GetText()) or 0
				tankClass   = _G[frameName .. "TankClass"]:GetText():trim()
				healer      = tonumber(_G[frameName .. "Healer"]:GetText()) or 0
				healerClass = _G[frameName .. "HealerClass"]:GetText():trim()
				melee       = tonumber(_G[frameName .. "Melee"]:GetText()) or 0
				meleeClass  = _G[frameName .. "MeleeClass"]:GetText():trim()
				ranged      = tonumber(_G[frameName .. "Ranged"]:GetText()) or 0
				rangedClass = _G[frameName .. "RangedClass"]:GetText():trim()
				message     = _G[frameName .. "Message"]:GetText():trim()

				local temp  = output
				if string.trim(name) ~= "" then temp = temp .. " " .. name end
				if tank > 0 or healer > 0 or melee > 0 or ranged > 0 then
					temp = temp .. " - Need"
					if tank > 0 then
						temp = temp .. ", " .. tank .. " Tank"
						if tankClass ~= "" then temp = temp .. " (" .. tankClass .. ")" end
					end
					if healer > 0 then
						temp = temp .. ", " .. healer .. " Healer"
						if healerClass ~= "" then temp = temp .. " (" .. healerClass .. ")" end
					end
					if melee > 0 then
						temp = temp .. ", " .. melee .. " Melee"
						if meleeClass ~= "" then temp = temp .. " (" .. meleeClass .. ")" end
					end
					if ranged > 0 then
						temp = temp .. ", " .. ranged .. " Ranged"
						if rangedClass ~= "" then temp = temp .. " (" .. rangedClass .. ")" end
					end
				end
				if message ~= "" then
					temp = temp .. " - " .. FindAchievement(message)
				end

				if temp ~= "LFM" then
					local total = tank + healer + melee + ranged
					local max = name:find("25") and 25 or 10
					temp = temp .. " (" .. max - (total or 0) .. "/" .. max .. ")"

					_G[frameName .. "Output"]:SetText(temp)
					length = strlen(temp)
					_G[frameName .. "Length"]:SetText(length .. "/255")

					if length <= 0 then
						_G[frameName .. "Length"]:SetTextColor(0.5, 0.5, 0.5)
					elseif length <= 255 then
						_G[frameName .. "Length"]:SetTextColor(0.0, 1.0, 0.0)
						_G[frameName .. "Message"]:SetMaxLetters(255)
					else
						_G[frameName .. "Message"]:SetMaxLetters(strlen(message) - 1)
						_G[frameName .. "Length"]:SetTextColor(1.0, 0.0, 0.0)
					end
				else
					_G[frameName .. "Output"]:SetText(temp)
				end

				-- Set set duration:
				duration = _G[frameName .. "Duration"]:GetText()
				if duration == "" then
					duration = 60
					_G[frameName .. "Duration"]:SetText(duration)
				end
				finalOutput = temp
				Utils.setText(_G[frameName .. "StartBtn"], (paused and L.BtnResume or L.BtnStop), START, ticking == true)
				Utils.enableDisable(_G[frameName .. "StartBtn"], (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255))
			end

			if ticking then
				if not paused then
					local count = ceil(duration - GetTime() + tickStart)
					local i = tickPos - 1
					while i >= count do
						_G[frameName .. "Tick"]:SetText(i)
						i = i - 1
					end
					tickPos = count
					if tickPos < 0 then tickPos = 0 end
					if tickPos == 0 then
						_G[frameName .. "Tick"]:SetText("")
						Spammer:Spam()
						ticking = false
						Spammer:Start()
					end
				end
			end
		end
	end

	function FindAchievement(inp)
		local out = inp:trim()
		if out and out ~= "" and find(out, "%{%d*%}") then
			local b, e = find(out, "%{%d*%}")
			local id = strsub(out, b + 1, e - 1)
			if not id or id == "" or not GetAchievementLink(id) then
				link = "[" .. id .. "]"
			else
				link = GetAchievementLink(id)
			end
			out = strsub(out, 0, b - 1) .. link .. strsub(out, e + 1)
		end
		return out
	end

	-- To spam even if the frame is closed:
	spamFrame:SetScript("OnUpdate", function(self, elapsed)
		if UISpammer then UpdateUIFrame(UISpammer, elapsed) end
	end)
end

-- ==================== Tooltips ==================== --
do
	local colors = HIGHLIGHT_FONT_COLOR

	-- Show the tooltip:
	local function ShowTooltip(frame)
		-- Is the anchor manually set?
		if not frame.tooltip_anchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, frame)
		else
			GameTooltip:SetOwner(frame, frame.tooltip_anchor)
		end

		-- Do we have a title?
		if frame.tooltip_title then
			GameTooltip:SetText(frame.tooltip_title)
		end

		-- Do We have a text?
		if frame.tooltip_text then
			if type(frame.tooltip_text) == "string" then
				GameTooltip:AddLine(frame.tooltip_text, colors.r, colors.g, colors.b, true)
			elseif type(frame.tooltip_text) == "table" then
				for _, l in ipairs(frame.tooltip_text) do
					GameTooltip:AddLine(l, colors.r, colors.g, colors.b, true)
				end
			end
		end

		-- Do we have an item tooltip?
		if frame.tooltip_item then
			GameTooltip:SetHyperlink(frame.tooltip_item)
		end

		-- Show the tooltip
		GameTooltip:Show()
	end

	-- Hides the tooltip:
	local function HideTooltip()
		GameTooltip:Hide()
	end

	-- Sets addon tooltips scripts:
	function addon:SetTooltip(frame, text, anchor, title)
		-- No frame no blame...
		if not frame then return end
		-- Prepare the text
		frame.tooltip_text = text and text or frame.tooltip_text
		frame.tooltip_anchor = anchor and anchor or frame.tooltip_anchor
		frame.tooltip_title = title and title or frame.tooltip_title
		-- No title or text? nothing to do...
		if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then
			return
		end
		frame:SetScript("OnEnter", ShowTooltip)
		frame:SetScript("OnLeave", HideTooltip)
	end
end

-- ==================== Loot History Frame ==================== --

-- Main frame:
do
	addon.Logger              = {}
	local Logger              = addon.Logger
	local frameName

	local LocalizeUIFrame
	local localized           = false

	local UpdateUIFrame
	local updateInterval      = 0.1

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
		_G[frameName .. "Title"]:SetText(format(titleString, L.StrLootHistory))
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
			EasyMenu(menuList, itemMenu, "cursor", 0, 0, "MENU")
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
			hasEditBox   = 1,
			cancels      = "KRTLOGGER_ITEM_EDIT_WINNER",
			OnShow       = function(self)
				self.raidId = addon.Logger.selectedRaid
				self.itemId = addon.Logger.selectedItem
			end,
			OnHide       = function(self)
				self.raidId = nil
				self.itemId = nil
			end,
			OnAccept     = function(self)
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
			hasEditBox   = 1,
			cancels      = "KRTLOGGER_ITEM_EDIT_ROLL",
			OnShow       = function(self) self.itemId = addon.Logger.selectedItem end,
			OnHide       = function(self) self.itemId = nil end,
			OnAccept     = function(self)
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
			hasEditBox   = 1,
			cancels      = "KRTLOGGER_ITEM_EDIT_VALUE",
			OnShow       = function(self) self.itemId = addon.Logger.selectedItem end,
			OnHide       = function(self) self.itemId = nil end,
			OnAccept     = function(self)
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
			_G[frameName .. "Title"]:SetText(L.StrRaidsList)
			_G[frameName .. "HeaderDate"]:SetText(L.StrDate)
			_G[frameName .. "HeaderSize"]:SetText(L.StrSize)
			_G[frameName .. "CurrentBtn"]:SetText(L.StrSetCurrent)
			_G[frameName .. "ExportBtn"]:SetText(L.BtnExport)
		end
		_G[frameName .. "ExportBtn"]:Disable() -- FIXME
		addon:SetTooltip(
			_G[frameName .. "CurrentBtn"],
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
					_G[frameName .. "RaidBtn" .. v.id]:LockHighlight()
				else
					_G[frameName .. "RaidBtn" .. v.id]:UnlockHighlight()
				end
			end

			Utils.enableDisable(_G[frameName .. "CurrentBtn"], (
				selectedRaid and
				selectedRaid ~= KRT_CurrentRaid and
				not addon.Raid:Expired(selectedRaid) and
				addon:GetRaidSize() == KRT_Raids[selectedRaid].size
			))
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], (selectedRaid ~= KRT_CurrentRaid))
		end
	end

	-- Initialize raids list:
	function InitRaidsList()
		raidsTable = {}
		for i, r in ipairs(KRT_Raids) do
			local info = { id = i, zone = r.zone, size = r.size, date = r.startTime }
			tinsert(raidsTable, info)
		end
	end

	-- Utility function to visually hide list:
	local function ResetList()
		local index = 1
		local btn = _G[frameName .. "RaidBtn" .. index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName .. "RaidBtn" .. index]
		end
	end

	-- Fetch raids list:
	function Raids:Fetch()
		ResetList()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())

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
				if _G[frameName .. "RaidBtn" .. selectedRaid] then
					_G[frameName .. "RaidBtn" .. selectedRaid]:Hide()
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
			_G[frameName .. "Title"]:SetText(L.StrBosses)
			_G[frameName .. "HeaderTime"]:SetText(L.StrTime)
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
					_G[frameName .. "BossBtn" .. v.id]:LockHighlight()
				else
					_G[frameName .. "BossBtn" .. v.id]:UnlockHighlight()
				end
			end
			Utils.enableDisable(_G[frameName .. "AddBtn"], selectedRaid)
			Utils.enableDisable(_G[frameName .. "EditBtn"], selectedBoss)
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedBoss)
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
		local btn = _G[frameName .. "BossBtn" .. index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName .. "BossBtn" .. index]
		end
	end

	-- Fetch bosses list:
	function Boss:Fetch()
		ResetList()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())

		for i, boss in ipairs(bossTable) do
			local btnName = frameName .. "BossBtn" .. boss.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerBossButton")
			btn:SetID(boss.id)
			btn:Show()
			_G[btnName .. "ID"]:SetText(boss.id)
			_G[btnName .. "Name"]:SetText(boss.name)
			_G[btnName .. "Time"]:SetText(date("%H:%M", boss.time))
			_G[btnName .. "Mode"]:SetText(boss.mode)
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
			_G[frameName .. "Title"]:SetText(L.StrBossAttendees)
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
				if selectedBossPlayer and p.id == selectedBossPlayer and _G[frameName .. "PlayerBtn" .. p.id] then
					_G[frameName .. "PlayerBtn" .. p.id]:LockHighlight()
				elseif _G[frameName .. "PlayerBtn" .. p.id] then
					_G[frameName .. "PlayerBtn" .. p.id]:UnlockHighlight()
				end
			end
			-- Add/Ban button:
			Utils.enableDisable(_G[frameName .. "AddBtn"], selectedBoss and not selectedBossPlayer)
			Utils.enableDisable(_G[frameName .. "RemoveBtn"], selectedBoss and selectedBossPlayer)
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
		local btn = _G[frameName .. "PlayerBtn" .. index]
		while btn do
			btn:Hide()
			index = index + 1
			btn = _G[frameName .. "PlayerBtn" .. index]
		end
	end

	-- Fetch boss attendees list:
	function BossAttendees:Fetch()
		ResetList()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for i, p in ipairs(playersTable) do
			local btnName = frameName .. "PlayerBtn" .. p.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerBossAttendeeButton")
			btn:SetID(p.id)
			btn:Show()
			local name = _G[btnName .. "Name"]
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
			if btn and selectedBossPlayer ~= nil then
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
			_G[frameName .. "Title"]:SetText(L.StrRaidAttendees)
			_G[frameName .. "HeaderJoin"]:SetText(L.StrJoin)
			_G[frameName .. "HeaderLeave"]:SetText(L.StrLeave)
		end
		-- FIXME: disable buttons for now
		_G[frameName .. "AddBtn"]:Disable()
		_G[frameName .. "DeleteBtn"]:Disable()

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
				if selectedPlayer and p.id == selectedPlayer and _G[frameName .. "PlayerBtn" .. i] then
					_G[frameName .. "PlayerBtn" .. i]:LockHighlight()
				elseif _G[frameName .. "PlayerBtn" .. i] then
					_G[frameName .. "PlayerBtn" .. i]:UnlockHighlight()
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
		local btn = _G[frameName .. "PlayerBtn" .. index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName .. "PlayerBtn" .. index]
		end
	end

	-- Fetch bosses list:
	function RaidAttendees:Fetch()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for i, p in ipairs(playersTable) do
			local btnName = frameName .. "PlayerBtn" .. p.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerRaidAttendeeButton")
			btn:SetID(p.id)
			btn:Show()
			local name = _G[btnName .. "Name"]
			name:SetText(p.name)
			local r, g, b = addon:GetClassColor(p.class)
			name:SetVertexColor(r, g, b)
			_G[btnName .. "Join"]:SetText(date("%H:%M", p.join))
			if p.leave then
				_G[btnName .. "Leave"]:SetText(date("%H:%M", p.leave))
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
		end

		-- FIXME: disable buttons for now
		_G[frameName .. "ExportBtn"]:Disable()
		_G[frameName .. "ClearBtn"]:Disable()
		_G[frameName .. "AddBtn"]:Disable()
		_G[frameName .. "EditBtn"]:Disable()

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
				if selectedItem and selectedItem == v.id and _G[frameName .. "ItemBtn" .. i] then
					_G[frameName .. "ItemBtn" .. i]:LockHighlight()
				elseif _G[frameName .. "ItemBtn" .. i] then
					_G[frameName .. "ItemBtn" .. i]:UnlockHighlight()
				end
			end
			Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedItem)
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
		local btn = _G[frameName .. "ItemBtn" .. index]
		while btn ~= nil do
			btn:Hide()
			index = index + 1
			btn = _G[frameName .. "ItemBtn" .. index]
		end
	end

	-- Fetch bosses list:
	function Loot:Fetch()
		ResetList()
		local scrollFrame = _G[frameName .. "ScrollFrame"]
		local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
		local totalHeight = 0
		scrollChild:SetHeight(scrollFrame:GetHeight())
		scrollChild:SetWidth(scrollFrame:GetWidth())
		for k, v in ipairs(lootTable) do
			local btnName = frameName .. "ItemBtn" .. v.id
			local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTLoggerLootButton")
			btn:SetID(v.id)
			btn:Show()

			_G[btnName .. "Name"]:SetText("|c" .. itemColors[v.itemRarity + 1] .. v.itemName .. "|r")
			_G[btnName .. "Source"]:SetText(addon.Logger.Boss:GetName(v.bossNum, selectedRaid))
			local player = v.looter
			local class = addon:GetPlayerClass(player)
			local r, g, b = addon:GetClassColor(class)
			_G[btnName .. "Winner"]:SetText(player)
			_G[btnName .. "Winner"]:SetVertexColor(r, g, b)
			_G[btnName .. "Type"]:SetText(lootTypesColored[v.rollType] or lootTypesColored[6])
			_G[btnName .. "Roll"]:SetText(v.rollValue or 0)
			_G[btnName .. "Time"]:SetText(date("%H:%M", v.time))
			_G[btnName .. "ItemIconTexture"]:SetTexture(v.itemTexture)

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
				if _G[frameName .. "ItemBtn" .. selectedItem] then
					_G[frameName .. "ItemBtn" .. selectedItem]:Hide()
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
			lootList[iID].rollType = tonumber(rollType)
			fetched                = false
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
		_G[frameName .. "Name"]:SetText(bossData.name)

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
		_G[frameName .. "Time"]:SetText(string.format("%02d:%02d", tempDate.hour, tempDate.min))
		_G[frameName .. "Difficulty"]:SetText((bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n")
		isEdit = true
		self:Toggle()
	end

	function BossBox:Save()
		selectedRaid = addon.Logger.selectedRaid
		if not selectedRaid then return end
		local name = _G[frameName .. "Name"]:GetText():trim()
		local diff = _G[frameName .. "Difficulty"]:GetText():trim():lower()
		local bTime = _G[frameName .. "Time"]:GetText():trim()

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
				date = time({ day = day, month = month, year = year, hour = hour, min = minute }),
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
		_G[frameName .. "Name"]:SetText("")
		_G[frameName .. "Difficulty"]:SetText("")
		_G[frameName .. "Time"]:SetText("")
		isEdit = false
		-- isAdd = false
	end

	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName .. "Title"]:SetText(L.StrAddBoss)
		end
		-- Help tooltips:
		addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
		addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
		addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
		localized = true
	end

	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, (selectedBoss and isEdit))
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
		_G[frameName .. "Name"]:SetText("")
		_G[frameName .. "Name"]:ClearFocus()
		UIFrame:Hide()
	end

	local function LocalizeUIFrame()
		if not localized then
			if GetLocale() ~= "enUS" and GetLocale() then
				_G[frameName .. "Title"]:SetText(L.StrAddPlayer)
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
			_G[frameName .. "Name"]:SetText("")
			_G[frameName .. "Name"]:SetFocus()
		end)
		frame:SetScript("OnHide", function(self)
			_G[frameName .. "Name"]:SetText("")
			_G[frameName .. "Name"]:ClearFocus()
		end)
	end

	function AttendeesBox:Toggle()
		Utils.toggle(UIFrame)
	end

	function AttendeesBox:Save()
		local name = _G[frameName .. "Name"]:GetText()
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

	-- Register out slash command:
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
		if addon.bossListIDs[npcID] then
			if KRT then
				addon:Debug("INFO", "Boss killed: %s", destName)
			end
			self.Raid:AddBoss(destName)
		end
	end
end
