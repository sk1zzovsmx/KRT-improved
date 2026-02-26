-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local addonName = addon.name

local L = feature.L
local Diag = feature.Diag

local Bus = feature.Bus or addon.Bus
local Frames = feature.Frames or addon.Frames
local Time = feature.Time or addon.Time
local Events = feature.Events or addon.Events or {}
local C = feature.C

local InternalEvents = Events.Internal
local WowEvents = Events.Wow

local _G = _G
local tremove = table.remove
local pairs, select, type = pairs, select, type
local error, pcall = error, pcall
local tostring, tonumber = tostring, tonumber

_G["KRT"] = addon

-- =========== Saved Variables  =========== --
-- These variables are persisted across sessions for the addon.

KRT_Raids = KRT_Raids or {}
KRT_Players = KRT_Players or {}
KRT_Reserves = (type(KRT_Reserves) == "table") and KRT_Reserves or {}
KRT_Warnings = KRT_Warnings or {}
KRT_Spammer = KRT_Spammer or {}
KRT_Options = KRT_Options or {}

-- =========== External Libraries / Bootstrap  =========== --
local Compat = LibStub("LibCompat-1.0")
addon.Compat = Compat
addon.BossIDs = LibStub("LibBossIDs-1.0")
addon.Debugger = LibStub("LibLogger-1.0")
addon.Deformat = LibStub("LibDeformat-3.0")

Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
addon.Debugger:Embed(addon)

-- =========== Timer Debug (optional)  =========== --
-- Helps diagnose sporadic FPS drops caused by runaway timers/tickers (LibCompat WaitFrame).
-- Usage:
--   /krt debug timers        (sorted by age)
--   /krt debug timers dur    (sorted by duration)
--   /krt debug timers iters  (sorted by iterations)
--   /krt debug timers reset
-- Tip: enable /krt debug on to include creation call sites.
do
    local TD = addon.TimerDebug or {}
    addon.TimerDebug = TD

    TD.stats = TD.stats or { created = 0, cancelled = 0, after = 0, active = 0, maxActive = 0 }
    -- Weak keys so we don't keep tickers alive.
    TD.active = TD.active or setmetatable({}, { __mode = "k" })

    local _After = addon.After
    local _NewTimer = addon.NewTimer
    local _NewTicker = addon.NewTicker
    local _CancelTimer = addon.CancelTimer

    local function now()
        return (GetTime and GetTime()) or 0
    end

    local function captureStack()
        -- Only capture when debug is enabled (avoid overhead in normal use).
        if addon.State and addon.State.debugEnabled and debugstack then
            return debugstack(3, 1, 0)
        end
        return nil
    end

    local function track(ticker, kind, duration, iterations)
        if not ticker then return end
        TD.active[ticker] = {
            kind = kind,
            createdAt = now(),
            duration = tonumber(duration) or 0,
            iterations = (iterations == nil) and -1 or iterations,
            by = captureStack(),
        }
        TD.stats.created = (TD.stats.created or 0) + 1
        TD.stats.active = (TD.stats.active or 0) + 1
        if TD.stats.active > (TD.stats.maxActive or 0) then
            TD.stats.maxActive = TD.stats.active
        end
    end

    local function untrack(ticker, reason)
        if not ticker then return end
        if TD.active[ticker] then
            TD.active[ticker] = nil
            if (TD.stats.active or 0) > 0 then
                TD.stats.active = TD.stats.active - 1
            end
            if reason == "cancel" then
                TD.stats.cancelled = (TD.stats.cancelled or 0) + 1
            end
        end
    end

    if type(_After) == "function" then
        addon.After = function(duration, callback)
            TD.stats.after = (TD.stats.after or 0) + 1
            return _After(duration, callback)
        end
    end

    if type(_NewTimer) == "function" then
        addon.NewTimer = function(duration, callback)
            local ticker
            local wrapped = function(selfTicker, ...)
                local t = selfTicker or ticker
                if callback then
                    callback(selfTicker, ...)
                end
                untrack(t, "done")
            end
            ticker = _NewTimer(duration, wrapped)
            track(ticker, "timer", duration, 1)
            return ticker
        end
    end

    if type(_NewTicker) == "function" then
        addon.NewTicker = function(duration, callback, iterations)
            local ticker
            local wrapped = function(selfTicker, ...)
                local t = selfTicker or ticker
                if callback then
                    callback(selfTicker, ...)
                end
                -- LibCompat calls callback before decrementing _iterations, so 1 means "last tick".
                if t and t._iterations == 1 then
                    untrack(t, "done")
                end
            end
            ticker = _NewTicker(duration, wrapped, iterations)
            track(ticker, "ticker", duration, iterations)
            return ticker
        end
    end

    if type(_CancelTimer) == "function" then
        addon.CancelTimer = function(ticker, silent)
            untrack(ticker, "cancel")
            return _CancelTimer(ticker, silent)
        end
    end

    function addon:ResetTimerDebug()
        if not self.TimerDebug then return end
        for k in pairs(self.TimerDebug.active or {}) do
            self.TimerDebug.active[k] = nil
        end
        self.TimerDebug.stats = { created = 0, cancelled = 0, after = 0, active = 0, maxActive = 0 }
    end

    -- sortBy: age|dur|iters
    function addon:DumpTimerDebug(sortBy)
        local tdbg = self.TimerDebug
        if not tdbg then
            if self.warn then self:warn("Timer debug not available.") end
            return
        end

        local rows = {}
        local nowT = now()
        for _, info in pairs(tdbg.active) do
            local age = nowT - (info.createdAt or nowT)
            rows[#rows + 1] = {
                kind = info.kind or "?",
                age = age,
                duration = info.duration or 0,
                iterations = info.iterations,
                by = info.by,
            }
        end

        local key = "age"
        local k = tostring(sortBy or ""):lower()
        if k == "duration" or k == "dur" then
            key = "duration"
        elseif k == "iters" or k == "iter" then
            key = "iterations"
        else
            key = "age"
        end

        table.sort(rows, function(a, b)
            local av = a[key] or 0
            local bv = b[key] or 0
            if av == bv then
                return (a.age or 0) > (b.age or 0)
            end
            return av > bv
        end)

        local s = tdbg.stats or {}
        if self.info then
            self:info("Timers: active=%d (max=%d) created=%d cancelled=%d after=%d",
                s.active or 0, s.maxActive or 0, s.created or 0, s.cancelled or 0, s.after or 0)
        end

        local limit = 15
        if #rows < limit then limit = #rows end
        for i = 1, limit do
            local r = rows[i]
            if self.info then
                self:info("%2d) %s | age:%.1fs dur:%.2fs iters:%s", i, r.kind, r.age, r.duration,
                    (r.iterations == nil and "?" or tostring(r.iterations)))
            end
            if r.by and (addon.State and addon.State.debugEnabled) and self.debug then
                self:debug("    created at: %s", tostring(r.by))
            end
        end

        if self.info then
            self:info("Tip: /krt debug timers reset  |  /krt debug on (to include call sites)")
        end
    end
end

-- =========== LibCompat  =========== --

-- Keep LibCompat chat output behavior, but without prepending tostring(addon) ("table: ...").
function addon:Print(...)
    return Compat.Print(Compat, ...)
end

do
    local lv = addon.Debugger.logLevels.INFO
    if addon.State and addon.State.debugEnabled then
        lv = addon.Debugger.logLevels.DEBUG
    end
    addon:SetLogLevel(lv)
end

-- =========== Core Addon Frames & Locals  =========== --

-- Centralized addon state
local coreState = addon.State
if coreState.nextReset == nil then
    coreState.nextReset = 0
end

coreState.frames = coreState.frames or {}
local frames = coreState.frames
frames.main = frames.main or CreateFrame("Frame")

-- Addon UI frame used by event dispatcher
local mainFrame = frames.main

local Core = addon.Core

function Core.GetCurrentRaid()
    return coreState.currentRaid
end

function Core.SetCurrentRaid(raidNum)
    coreState.currentRaid = raidNum
    return coreState.currentRaid
end

function Core.GetLastBoss()
    return coreState.lastBoss
end

function Core.SetLastBoss(bossNid)
    coreState.lastBoss = bossNid
    return coreState.lastBoss
end

function Core.GetNextReset()
    return tonumber(coreState.nextReset) or 0
end

function Core.SetNextReset(nextReset)
    coreState.nextReset = tonumber(nextReset) or 0
    return coreState.nextReset
end

-- =========== Event System (WoW API events)  =========== --
-- Clean frame-based dispatcher (NO CallbackHandler here)
do
    -- listeners[event] = { obj1, obj2, ... }
    local listeners = {}

    local function HandleEvent(_, eventName, ...)
        local list = listeners[eventName]
        if not list then return end

        for i = 1, #list do
            local obj = list[i]
            local fn = obj and obj[eventName]
            if type(fn) == "function" then
                local ok, err = pcall(fn, obj, ...)
                if not ok then
                    addon:error(Diag.E.LogCoreEventHandlerFailed:format(tostring(eventName), tostring(err)))
                end
            end
        end
    end

    local function AddListener(obj, eventName)
        if type(eventName) ~= "string" or eventName == "" then
            error("Usage: RegisterEvent(\"EVENT_NAME\")", 3)
        end

        local list = listeners[eventName]
        if not list then
            list = {}
            listeners[eventName] = list
            mainFrame:RegisterEvent(eventName)
        else
            for i = 1, #list do
                if list[i] == obj then return end -- already registered
            end
        end

        list[#list + 1] = obj
    end

    local function RemoveListener(obj, eventName)
        local list = listeners[eventName]
        if not list then return end

        for i = #list, 1, -1 do
            if list[i] == obj then
                tremove(list, i)
            end
        end

        if #list == 0 then
            listeners[eventName] = nil
            mainFrame:UnregisterEvent(eventName)
        end
    end

    function addon:RegisterEvent(eventName)
        AddListener(self, eventName)
    end

    function addon:RegisterEvents(...)
        for i = 1, select("#", ...) do
            AddListener(self, select(i, ...))
        end
    end

    function addon:UnregisterEvent(eventName)
        RemoveListener(self, eventName)
    end

    function addon:UnregisterEvents()
        local keys = {}
        for eventName in pairs(listeners) do
            keys[#keys + 1] = eventName
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

local function bindModuleRequestRefresh(module, getFrame)
    local requestRefresh = Frames.MakeEventDrivenRefresher(getFrame, function()
        module:Refresh()
    end)

    function module:RequestRefresh()
        requestRefresh()
    end
end

local function bindModuleToggleHide(module, uiController)
    function module:Toggle()
        return uiController:Toggle()
    end

    function module:Hide()
        return uiController:Hide()
    end
end

local function makeModuleFrameGetter(module, globalFrameName)
    local getGlobalFrame = Frames.MakeFrameGetter(globalFrameName)
    return function()
        local frame = module.frame or getGlobalFrame()
        if frame and not module.frame then
            module.frame = frame
        end
        return frame
    end
end

Core.BindModuleRequestRefresh = bindModuleRequestRefresh
Core.BindModuleToggleHide = bindModuleToggleHide
Core.MakeModuleFrameGetter = makeModuleFrameGetter


local function ensureDBManager()
    local db = addon.DB
    if not (db and type(db.SetManager) == "function" and type(db.GetManager) == "function") then
        return nil
    end

    local manager = db.GetManager()
    if manager then
        return manager
    end

    local dbManager = addon.DBManager
    local defaultManager = dbManager and dbManager.GetDefaultManager and dbManager.GetDefaultManager() or nil
    if defaultManager then
        db.SetManager(defaultManager)
        return defaultManager
    end

    return nil
end

ensureDBManager()

function Core.EnsureRaidSchema(raid)
    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.NormalizeRaidRecord then
        return raidStore:NormalizeRaidRecord(raid)
    end
    return raid
end

function Core.EnsureRaidById(raidNum)
    local id = tonumber(raidNum)
    if not id then
        return nil, nil
    end

    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.GetRaidByIndex then
        return raidStore:GetRaidByIndex(id)
    end
    return nil, id
end

function Core.EnsureRaidByNid(raidNid)
    local nid = tonumber(raidNid)
    if not nid then
        return nil, nil, nil
    end

    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.GetRaidByNid then
        return raidStore:GetRaidByNid(nid)
    end
    return nil, nil, nid
end

function Core.GetRaidNidById(raidNum)
    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.GetRaidNidByIndex then
        return raidStore:GetRaidNidByIndex(raidNum)
    end
    local raid = Core.EnsureRaidById(raidNum)
    return raid and tonumber(raid.raidNid) or nil
end

function Core.GetRaidIdByNid(raidNid)
    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.GetRaidIndexByNid then
        return raidStore:GetRaidIndexByNid(raidNid)
    end
    local _, idx = Core.EnsureRaidByNid(raidNid)
    return idx
end

function Core.CreateRaidRecord(args)
    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.CreateRaidRecord then
        return raidStore:CreateRaidRecord(args)
    end
    args = args or {}
    local schemaVersion = Core.GetRaidSchemaVersion and Core.GetRaidSchemaVersion() or 1
    schemaVersion = tonumber(schemaVersion) or 1
    if schemaVersion < 1 then
        schemaVersion = 1
    end

    local raid = {
        schemaVersion = schemaVersion,
        raidNid = tonumber(args and args.raidNid),
        realm = args.realm,
        zone = args.zone,
        size = args.size,
        difficulty = args.difficulty,
        startTime = args.startTime or Time.GetCurrentTime(),
        endTime = args.endTime,
        players = {},
        bossKills = {},
        loot = {},
        changes = {},
        nextBossNid = 1,
        nextLootNid = 1,
        nextPlayerNid = 1,
    }

    return Core.EnsureRaidSchema(raid)
end

function Core.StripRuntimeRaidCaches(raid)
    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.StripRuntime then
        raidStore:StripRuntime(raid)
        return
    end
    if type(raid) ~= "table" then return end
    raid._runtime = nil
    raid._playersByName = nil
    raid._playerIdxByNid = nil
    raid._bossIdxByNid = nil
    raid._lootIdxByNid = nil
end


-- =========== Main Event Handlers  =========== --
local addonEvents = {
    CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM",
    CHAT_MSG_LOOT = "CHAT_MSG_LOOT",
    CHAT_MSG_ADDON = "CHAT_MSG_ADDON",
    CHAT_MSG_MONSTER_YELL = "CHAT_MSG_MONSTER_YELL",
    RAID_ROSTER_UPDATE = "RAID_ROSTER_UPDATE",
    PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
    COMBAT_LOG_EVENT_UNFILTERED = "COMBAT_LOG_EVENT_UNFILTERED",
    RAID_INSTANCE_WELCOME = "RAID_INSTANCE_WELCOME",
    PLAYER_DIFFICULTY_CHANGED = "PLAYER_DIFFICULTY_CHANGED",
    UPDATE_INSTANCE_INFO = "UPDATE_INSTANCE_INFO",
    LOOT_CLOSED = "LOOT_CLOSED",
    LOOT_OPENED = "LOOT_OPENED",
    LOOT_SLOT_CLEARED = "LOOT_SLOT_CLEARED",
    TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
    TRADE_REQUEST_CANCEL = "TRADE_REQUEST_CANCEL",
    TRADE_CLOSED = "TRADE_CLOSED",
    PLAYER_LOGOUT = "PLAYER_LOGOUT",
}

do
    local wowBusEvents = {
        LOOT_OPENED = WowEvents.LOOT_OPENED,
        LOOT_CLOSED = WowEvents.LOOT_CLOSED,
        LOOT_SLOT_CLEARED = WowEvents.LOOT_SLOT_CLEARED,
        TRADE_ACCEPT_UPDATE = WowEvents.TRADE_ACCEPT_UPDATE,
        TRADE_REQUEST_CANCEL = WowEvents.TRADE_REQUEST_CANCEL,
        TRADE_CLOSED = WowEvents.TRADE_CLOSED,
    }

    for eventName, busEventName in pairs(wowBusEvents) do
        local eventKey = busEventName
        addon[eventName] = function(_, ...)
            Bus.TriggerEvent(eventKey, ...)
        end
    end
end

-- ADDON_LOADED: Initializes the addon after loading.
function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    ensureDBManager()
    local lvl = addon.GetLogLevel and addon:GetLogLevel()
    addon:info(Diag.I.LogCoreLoaded:format(tostring(GetAddOnMetadata(addonName, "Version")),
        tostring(lvl), tostring(true)))
    addon.LoadOptions()
    local minimap = addon.Minimap
    if minimap and minimap.EnsureUI then
        minimap:EnsureUI()
    elseif minimap and minimap.OnLoad then
        minimap:OnLoad()
    end
    local reservesService = addon.Services and addon.Services.Reserves
    if reservesService and reservesService.Load then
        reservesService:Load()
    end
    for event in pairs(addonEvents) do
        self:RegisterEvent(event)
    end
    addon:debug(Diag.D.LogCoreEventsRegistered:format(addon.tLength(addonEvents)))
    self:RAID_ROSTER_UPDATE(true)
end

local rosterUpdateDebounceSeconds = 0.2

local function scheduleRaidInstanceChecksIfRecognized(instanceName, instanceType, instanceDiff, emitRecognizedLog)
    if instanceType ~= "raid" or L.RaidZones[instanceName] == nil then
        return false
    end
    if emitRecognizedLog then
        addon:debug(Diag.D.LogRaidInstanceRecognized:format(tostring(instanceName), tostring(instanceDiff)))
    end
    addon.Raid:ScheduleInstanceChecks()
    return true
end

local function processRaidRosterUpdate()
    local changed, delta = addon.Raid:UpdateRaidRoster()
    if not changed then
        return
    end

    -- Single source of truth for roster change notifications (join/update/leave delta).
    Bus.TriggerEvent(InternalEvents.RaidRosterDelta,
        delta, addon.Raid:GetRosterVersion(), Core.GetCurrentRaid())
end

-- RAID_ROSTER_UPDATE: Updates the raid roster when it changes.
function addon:RAID_ROSTER_UPDATE(forceImmediate)
    addon.CancelTimer(self._raidRosterUpdateHandle, true)
    self._raidRosterUpdateHandle = nil

    if forceImmediate then
        processRaidRosterUpdate()
        return
    end

    self._raidRosterUpdateHandle = addon.NewTimer(rosterUpdateDebounceSeconds, function()
        self._raidRosterUpdateHandle = nil
        processRaidRosterUpdate()
    end)
end

-- RAID_INSTANCE_WELCOME: Triggered when entering a raid instance.
function addon:RAID_INSTANCE_WELCOME(...)
    local instanceName, instanceType, instanceDiff = GetInstanceInfo()
    local _, nextReset = ...
    local resolvedNextReset = Core.SetNextReset(nextReset)
    addon:trace(Diag.D.LogRaidInstanceWelcome:format(tostring(instanceName), tostring(instanceType),
        tostring(instanceDiff), tostring(resolvedNextReset)))
    if instanceType == "raid" and not L.RaidZones[instanceName] then
        addon:warn(Diag.W.LogRaidUnmappedZone:format(tostring(instanceName), tostring(instanceDiff)))
    end
    if instanceType == "raid" then
        RequestRaidInfo()
    end
    scheduleRaidInstanceChecksIfRecognized(instanceName, instanceType, instanceDiff, true)
end

-- PLAYER_DIFFICULTY_CHANGED: Re-check raid session when raid difficulty changes.
function addon:PLAYER_DIFFICULTY_CHANGED()
    local instanceName, instanceType, instanceDiff = GetInstanceInfo()
    scheduleRaidInstanceChecksIfRecognized(instanceName, instanceType, instanceDiff, false)
end

-- UPDATE_INSTANCE_INFO: Re-check raid session after server pushes instance-save info refreshes.
function addon:UPDATE_INSTANCE_INFO()
    local instanceName, instanceType, instanceDiff = GetInstanceInfo()
    scheduleRaidInstanceChecksIfRecognized(instanceName, instanceType, instanceDiff, false)
end

-- PLAYER_ENTERING_WORLD: Performs initial checks when the player logs in.
function addon:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local module = self.Raid
    addon:trace(Diag.D.LogCorePlayerEnteringWorld)
    module:CancelInstanceChecks()
    -- Restart the first-check timer on login
    addon.CancelTimer(module.firstCheckHandle, true)
    module.firstCheckHandle = nil
    module.firstCheckHandle = addon.NewTimer(3, function() module:FirstCheck() end)
end

-- CHAT_MSG_LOOT: Adds looted items to the raid log.
function addon:CHAT_MSG_LOOT(msg)
    addon:trace(Diag.D.LogLootChatMsgLootRaw:format(tostring(msg)))
    if Core.GetCurrentRaid() then
        self.Raid:AddLoot(msg)
    end
end

-- CHAT_MSG_SYSTEM: Forwards roll messages to the Rolls module.
function addon:CHAT_MSG_SYSTEM(msg)
    addon.Rolls:CHAT_MSG_SYSTEM(msg)
end

-- CHAT_MSG_ADDON: Forwards addon communication messages to the Syncer module.
function addon:CHAT_MSG_ADDON(prefix, msg, channel, sender)
    local syncer = Core.GetSyncer and Core.GetSyncer() or nil
    if syncer and syncer.OnAddonMessage then
        syncer:OnAddonMessage(prefix, msg, channel, sender)
    end
end

-- CHAT_MSG_MONSTER_YELL: Logs a boss kill based on specific boss yells.
function addon:CHAT_MSG_MONSTER_YELL(...)
    local text = ...
    if L.BossYells[text] and Core.GetCurrentRaid() then
        addon:trace(Diag.D.LogBossYellMatched:format(tostring(text), tostring(L.BossYells[text])))
        self.Raid:AddBoss(L.BossYells[text])
    end
end

-- COMBAT_LOG_EVENT_UNFILTERED: Logs a boss kill when a boss unit dies.
function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
    if not Core.GetCurrentRaid() then return end

    -- Hot-path fast check: inspect the event type before unpacking extra args.
    local subEvent = select(2, ...)
    if subEvent ~= "UNIT_DIED" then return end

    -- 3.3.5a base params (8):
    -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags
    local destGUID, destName, destFlags = select(6, ...)
    if bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then return end

    -- LibCompat embeds GetCreatureId with the 3.3.5a GUID parsing rules.
    local npcId = destGUID and addon.GetCreatureId(destGUID)
    local bossLib = addon.BossIDs
    local bossIds = bossLib and bossLib.BossIDs
    if not (npcId and bossIds and bossIds[npcId]) then return end

    local boss = destName or bossLib:GetBossName(npcId)
    if boss then
        addon:trace(Diag.D.LogBossUnitDiedMatched:format(tonumber(npcId) or -1, tostring(boss)))
        self.Raid:AddBoss(boss)
    end
end

-- PLAYER_LOGOUT: Strip runtime-only raid caches before SavedVariables are written.
function addon:PLAYER_LOGOUT()
    local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
    if raidStore and raidStore.StripAllRuntime then
        raidStore:StripAllRuntime()
        return
    end
    if type(KRT_Raids) ~= "table" then return end
    for i = 1, #KRT_Raids do
        addon.Core.StripRuntimeRaidCaches(KRT_Raids[i])
    end
end
