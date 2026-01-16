--[[
    KRT.lua
    - Main addon file for Kader Raid Tools (KRT).
    - Handles core logic, event registration, and module initialization.
]]

local addonName, addon = ...
addon                  = addon or {}
addon.name             = addon.name or addonName
local L                = addon.L
local Utils            = addon.Utils
local C                = addon.C

local _G               = _G
_G["KRT"]              = addon


---============================================================================
-- Costants
---============================================================================

local ITEM_LINK_PATTERN   = C.ITEM_LINK_PATTERN
local rollTypes           = C.rollTypes
local lootTypesText       = C.lootTypesText
local lootTypesColored    = C.lootTypesColored
local itemColors          = C.itemColors
local RAID_TARGET_MARKERS = C.RAID_TARGET_MARKERS
local K_COLOR             = C.K_COLOR
local RT_COLOR            = C.RT_COLOR

---============================================================================
-- Saved Variables
-- These variables are persisted across sessions for the addon.
---============================================================================

KRT_Options               = KRT_Options or {}
KRT_Raids                 = KRT_Raids or {}
KRT_Players               = KRT_Players or {}
KRT_Warnings              = KRT_Warnings or {}
KRT_ExportString          = KRT_ExportString or "$I,$N,$S,$W,$T,$R,$H:$M,$d/$m/$y"
KRT_Spammer               = KRT_Spammer or {}
KRT_CurrentRaid           = KRT_CurrentRaid or nil
KRT_LastBoss              = KRT_LastBoss or nil
KRT_NextReset             = KRT_NextReset or 0
KRT_SavedReserves         = KRT_SavedReserves or {}
KRT_PlayerCounts          = KRT_PlayerCounts or {}
addon.options             = KRT_Options

---============================================================================
-- External Libraries / Bootstrap
---============================================================================
local Compat              = LibStub("LibCompat-1.0")
addon.Compat              = Compat
addon.BossIDs             = LibStub("LibBossIDs-1.0")
addon.Debugger            = LibStub("LibLogger-1.0")
addon.Deformat            = LibStub("LibDeformat-3.0")
addon.CallbackHandler     = LibStub("CallbackHandler-1.0")

Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
addon.Debugger:Embed(addon)

-- Alias locali (safe e veloci)
local UnitIsGroupLeader    = addon.UnitIsGroupLeader
local UnitIsGroupAssistant = addon.UnitIsGroupAssistant
local tContains            = _G.tContains

do
    local lv = addon.Debugger.logLevels.INFO
    if KRT_Options and KRT_Options.debug then
        lv = addon.Debugger.logLevels.DEBUG
    end
    addon:SetLogLevel(lv)
    addon:SetPerformanceMode(true)
end

---============================================================================
-- Core Addon Frames & Locals
---============================================================================

-- Centralised addon state
addon.State                = addon.State or {}
local coreState            = addon.State

coreState.frames           = coreState.frames or {}
local Frames               = coreState.frames
Frames.main                = Frames.main or CreateFrame("Frame")

-- Addon UI Frames
local mainFrame            = Frames.main
local UIMaster, UIConfig, UISpammer, UIChanges, UIWarnings, UILogger, UILoggerItemBox

-- Player info helper
coreState.player           = coreState.player or {}
-- Rolls & Loot
coreState.loot             = coreState.loot or {}
local lootState            = coreState.loot
lootState.itemInfo         = lootState.itemInfo or {}
lootState.currentRollType  = lootState.currentRollType or 4
lootState.currentRollItem  = lootState.currentRollItem or 0
lootState.currentItemIndex = lootState.currentItemIndex or 0
lootState.itemCount        = lootState.itemCount or 1
lootState.lootCount        = lootState.lootCount or 0
lootState.rollsCount       = lootState.rollsCount or 0
lootState.itemTraded       = lootState.itemTraded or 0
lootState.rollStarted      = lootState.rollStarted or false
if lootState.opened == nil then lootState.opened = false end
if lootState.fromInventory == nil then lootState.fromInventory = false end

local itemInfo = lootState.itemInfo

---============================================================================
-- Cached Functions & Libraries
---============================================================================

local tinsert, tremove, tconcat, twipe  = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local format, find, strlen              = string.format, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber                = tostring, tonumber
local UnitRace, UnitSex, GetRealmName   = UnitRace, UnitSex, GetRealmName

---============================================================================
-- Event System (WoW API events)
-- Clean frame-based dispatcher (NO CallbackHandler here)
---============================================================================
do
    -- listeners[event] = { obj1, obj2, ... }
    local listeners = {}

    local function HandleEvent(_, e, ...)
        local list = listeners[e]
        if not list then return end

        for i = 1, #list do
            local obj = list[i]
            local fn = obj and obj[e]
            if type(fn) == "function" then
                local ok, err = pcall(fn, obj, ...)
                if not ok then
                    addon:error("Event handler failed event=%s err=%s", tostring(e), tostring(err))
                end
            end
        end
    end

    local function AddListener(obj, e)
        if type(e) ~= "string" or e == "" then
            error("Usage: RegisterEvent(\"EVENT_NAME\")", 3)
        end

        local list = listeners[e]
        if not list then
            list = {}
            listeners[e] = list
            mainFrame:RegisterEvent(e)
        else
            for i = 1, #list do
                if list[i] == obj then return end -- already registered
            end
        end

        list[#list + 1] = obj
    end

    local function RemoveListener(obj, e)
        local list = listeners[e]
        if not list then return end

        for i = #list, 1, -1 do
            if list[i] == obj then
                tremove(list, i)
            end
        end

        if #list == 0 then
            listeners[e] = nil
            mainFrame:UnregisterEvent(e)
        end
    end

    function addon:RegisterEvent(e)
        AddListener(self, e)
    end

    function addon:RegisterEvents(...)
        for i = 1, select("#", ...) do
            AddListener(self, select(i, ...))
        end
    end

    function addon:UnregisterEvent(e)
        RemoveListener(self, e)
    end

    function addon:UnregisterEvents()
        local keys = {}
        for e in pairs(listeners) do
            keys[#keys + 1] = e
        end
        for i = 1, #keys do
            RemoveListener(self, keys[i])
        end
    end

    function addon:UnregisterAllEvents()
        self:UnregisterEvents()
    end

    mainFrame:SetScript("OnEvent", HandleEvent)

    -- bootstrap
    addon:RegisterEvent("ADDON_LOADED")
end

---============================================================================
-- Main Event Handlers
---============================================================================

local addonEvents = {
    CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM",
    CHAT_MSG_LOOT = "CHAT_MSG_LOOT",
    CHAT_MSG_MONSTER_YELL = "CHAT_MSG_MONSTER_YELL",
    RAID_ROSTER_UPDATE = "RAID_ROSTER_UPDATE",
    PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
    COMBAT_LOG_EVENT_UNFILTERED = "COMBAT_LOG_EVENT_UNFILTERED",
    RAID_INSTANCE_WELCOME = "RAID_INSTANCE_WELCOME",
    ITEM_LOCKED = "ITEM_LOCKED",
    LOOT_CLOSED = "LOOT_CLOSED",
    LOOT_OPENED = "LOOT_OPENED",
    LOOT_SLOT_CLEARED = "LOOT_SLOT_CLEARED",
    TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
    TRADE_REQUEST_CANCEL = "TRADE_REQUEST_CANCEL",
    TRADE_CLOSED = "TRADE_CLOSED",
}

-- Master looter events
do
    local forward = {
        ITEM_LOCKED = "ITEM_LOCKED",
        LOOT_OPENED = "LOOT_OPENED",
        LOOT_CLOSED = "LOOT_CLOSED",
        LOOT_SLOT_CLEARED = "LOOT_SLOT_CLEARED",
        TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
        TRADE_REQUEST_CANCEL = "TRADE_REQUEST_CANCEL",
        TRADE_CLOSED = "TRADE_CLOSED",
    }
    for e, m in pairs(forward) do
        local method = m
        addon[e] = function(_, ...)
            addon.Master[method](addon.Master, ...)
        end
    end
end

--
-- ADDON_LOADED: Initializes the addon after loading.
--
function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    addon.BUILD = addon.BUILD or "fixed4-2026-01-06"
    local lvl = addon.GetLogLevel and addon:GetLogLevel()
    addon:info(L.LogCoreLoaded:format(tostring(GetAddOnMetadata(addonName, "Version")),
        tostring(lvl), tostring(true)))
    addon:info(L.LogCoreBuild:format(tostring(addon.BUILD)))
    addon.LoadOptions()
    addon.Reserves:Load()
    for event in pairs(addonEvents) do
        self:RegisterEvent(event)
    end
    addon:debug(L.LogCoreEventsRegistered:format(addon.tLength(addonEvents)))
    self:RAID_ROSTER_UPDATE()
end

--
-- RAID_ROSTER_UPDATE: Updates the raid roster when it changes.
--
function addon:RAID_ROSTER_UPDATE()
    addon.Raid:UpdateRaidRoster()
end

--
-- RAID_INSTANCE_WELCOME: Triggered when entering a raid instance.
--
function addon:RAID_INSTANCE_WELCOME(...)
    local instanceName, instanceType, instanceDiff = GetInstanceInfo()
    _, KRT_NextReset = ...
    addon:trace(L.LogRaidInstanceWelcome:format(tostring(instanceName), tostring(instanceType),
        tostring(instanceDiff), tostring(KRT_NextReset)))
    if instanceType == "raid" and not L.RaidZones[instanceName] then
        addon:warn(L.LogRaidUnmappedZone:format(tostring(instanceName), tostring(instanceDiff)))
    end
    if L.RaidZones[instanceName] ~= nil then
        addon:info(L.LogRaidInstanceRecognized:format(tostring(instanceName), tostring(instanceDiff)))
        addon.After(3, function()
            addon.Raid:Check(instanceName, instanceDiff)
        end)
    end
end

--
-- PLAYER_ENTERING_WORLD: Performs initial checks when the player logs in.
--
function addon:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local module = self.Raid
    addon:trace(L.LogCorePlayerEnteringWorld)
    addon.CancelTimer(module.firstCheckHandle, true)
    module.firstCheckHandle = addon.After(3, function() module:FirstCheck() end)
end

--
-- CHAT_MSG_LOOT: Adds looted items to the raid log.
--
function addon:CHAT_MSG_LOOT(msg)
    addon:trace(L.LogLootChatMsgLootRaw:format(tostring(msg)))
    if KRT_CurrentRaid then
        self.Raid:AddLoot(msg)
    end
end

--
-- CHAT_MSG_SYSTEM: Forwards roll messages to the Rolls module.
--
function addon:CHAT_MSG_SYSTEM(msg)
    addon.Rolls:CHAT_MSG_SYSTEM(msg)
end

--
-- CHAT_MSG_MONSTER_YELL: Logs a boss kill based on specific boss yells.
--
function addon:CHAT_MSG_MONSTER_YELL(...)
    local text, boss = ...
    if L.BossYells[text] and KRT_CurrentRaid then
        addon:trace(L.LogBossYellMatched:format(tostring(text), tostring(L.BossYells[text])))
        self.Raid:AddBoss(L.BossYells[text])
    end
end

--
-- COMBAT_LOG_EVENT_UNFILTERED: Logs a boss kill when a boss unit dies.
--
function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
    if not KRT_CurrentRaid then return end

    -- 3.3.5a base params (8):
    -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags
    local _, subEvent, _, _, _, destGUID, destName, destFlags = ...
    if subEvent ~= "UNIT_DIED" then return end
    if bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then return end

    -- LibCompat embeds GetCreatureId with the 3.3.5a GUID parsing rules.
    local npcId = destGUID and addon.GetCreatureId(destGUID)
    local bossLib = addon.BossIDs
    local bossIds = bossLib and bossLib.BossIDs
    if not (npcId and bossIds and bossIds[npcId]) then return end

    local boss = destName or bossLib:GetBossName(npcId)
    if boss then
        addon:trace(L.LogBossUnitDiedMatched:format(tonumber(npcId) or -1, tostring(boss)))
        self.Raid:AddBoss(boss)
    end
end
