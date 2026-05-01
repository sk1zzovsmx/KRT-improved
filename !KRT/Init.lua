-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local addonName = select(1, ...)

if not addon then
    error("KRT addon table not found in Init.lua")
end

-- ----- Internal state ----- --
addon.name = addon.name or addonName
addon.Core = addon.Core or {}
addon.L = addon.L or {}
addon.Diagnose = addon.Diagnose or {}
addon.State = addon.State or {}
addon.C = addon.C or {}
addon.Events = addon.Events or {}
addon.Events.Internal = addon.Events.Internal or {}
addon.Events.Wow = addon.Events.Wow or {}
addon.DB = addon.DB or {}
addon.Features = addon.Features or {}
addon.Controllers = addon.Controllers or {}
addon.Services = addon.Services or {}
addon.Services.Logger = addon.Services.Logger or {}
addon.Widgets = addon.Widgets or {}
addon.Bus = addon.Bus or {}
addon.Frames = addon.Frames or {}
addon.Time = addon.Time or {}

addon.Events.Internal.RaidRosterDelta = addon.Events.Internal.RaidRosterDelta or "RaidRosterDelta"

-- Canonical forwarded WoW-event names are PascalCase.
addon.Events.Wow.LootOpened = addon.Events.Wow.LootOpened or "wow.LOOT_OPENED"
addon.Events.Wow.LootClosed = addon.Events.Wow.LootClosed or "wow.LOOT_CLOSED"
addon.Events.Wow.LootSlotCleared = addon.Events.Wow.LootSlotCleared or "wow.LOOT_SLOT_CLEARED"
addon.Events.Wow.UiErrorMessage = addon.Events.Wow.UiErrorMessage or "wow.UI_ERROR_MESSAGE"
addon.Events.Wow.ChatMsgWhisper = addon.Events.Wow.ChatMsgWhisper or "wow.CHAT_MSG_WHISPER"
addon.Events.Wow.TradeAcceptUpdate = addon.Events.Wow.TradeAcceptUpdate or "wow.TRADE_ACCEPT_UPDATE"
addon.Events.Wow.TradeRequestCancel = addon.Events.Wow.TradeRequestCancel or "wow.TRADE_REQUEST_CANCEL"
addon.Events.Wow.TradeClosed = addon.Events.Wow.TradeClosed or "wow.TRADE_CLOSED"

local _G = _G
local pairs, type = pairs, type
local rawget, rawset = rawget, rawset
local getmetatable, setmetatable = getmetatable, setmetatable
local tostring, tonumber = tostring, tonumber
local GetRealmName = _G.GetRealmName
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local random = math.random
local gsub = string.gsub
local strsub, strlen = string.sub, string.len

local Core = addon.Core
local Diagnose = addon.Diagnose
local DEFAULT_PERF_THRESHOLD_MS = 5

local Diag = setmetatable({}, {
    __index = Diagnose,
    __newindex = function(_, key, value)
        Diagnose[key] = value
    end,
})

local legacyAliasMap = addon.LegacyAliases or {}
addon.LegacyAliases = legacyAliasMap

-- ----- Private helpers ----- --
local function isDebugEnabled()
    local state = addon.State
    return state and state.debugEnabled == true
end

local function isTraceEnabled()
    return addon.hasTrace ~= nil
end

local function getPerfThresholdMs()
    local threshold = tonumber(addon.State and addon.State.perfThresholdMs) or DEFAULT_PERF_THRESHOLD_MS
    if threshold < 0 then
        threshold = DEFAULT_PERF_THRESHOLD_MS
    end
    return threshold
end

local function getLegacyAliasWarnCache()
    local state = addon.State
    state.legacyAliasWarned = state.legacyAliasWarned or {}
    return state.legacyAliasWarned
end

local function getLegacyAliasWarnSite()
    local stackFn = _G.debugstack
    if type(stackFn) ~= "function" then
        return "unknown"
    end

    local stack = stackFn(4, 1, 0)
    if type(stack) ~= "string" then
        return tostring(stack or "unknown")
    end

    return stack:match("^[^\n]+") or stack
end

local function warnLegacyAliasAccess(aliasKey, targetPath)
    if not isDebugEnabled() then
        return
    end

    local site = getLegacyAliasWarnSite()
    local cacheKey = tostring(aliasKey) .. "|" .. tostring(site)
    local warned = getLegacyAliasWarnCache()
    if warned[cacheKey] then
        return
    end
    warned[cacheKey] = true

    if addon.warn then
        local template = (Diag.W and Diag.W.LogLegacyAliasAccess) or "[Compat] Legacy alias used alias=%s target=%s site=%s"
        addon:warn(template:format(tostring(aliasKey), tostring(targetPath or "?"), tostring(site)))
    end
end

local function callMetaIndex(indexMeta, tbl, key)
    if indexMeta == nil then
        return nil
    end
    if type(indexMeta) == "function" then
        return indexMeta(tbl, key)
    end
    return indexMeta[key]
end

local function callMetaNewIndex(newIndexMeta, tbl, key, value)
    if newIndexMeta == nil then
        rawset(tbl, key, value)
        return
    end
    if type(newIndexMeta) == "function" then
        newIndexMeta(tbl, key, value)
        return
    end
    newIndexMeta[key] = value
end

local function installLegacyAliasProxy()
    if addon._legacyAliasProxyInstalled then
        return
    end

    local existingMeta = getmetatable(addon)
    local meta = type(existingMeta) == "table" and existingMeta or {}
    local oldIndex = meta.__index
    local oldNewIndex = meta.__newindex

    meta.__index = function(tbl, key)
        local aliasEntry = legacyAliasMap[key]
        if aliasEntry and type(aliasEntry.get) == "function" then
            local value = aliasEntry.get()
            warnLegacyAliasAccess(key, aliasEntry.targetPath)
            if value ~= nil then
                return value
            end
        end
        return callMetaIndex(oldIndex, tbl, key)
    end

    meta.__newindex = function(tbl, key, value)
        local aliasEntry = legacyAliasMap[key]
        if aliasEntry and type(aliasEntry.set) == "function" then
            aliasEntry.set(value)
            -- Keep legacy aliases virtual so reads pass through __index and can be warned.
            rawset(tbl, key, nil)
            return
        end
        callMetaNewIndex(oldNewIndex, tbl, key, value)
    end

    local ok = pcall(setmetatable, addon, meta)
    if ok then
        addon._legacyAliasProxyInstalled = true
    end
end

-- ----- Public methods ----- --
function Core.RegisterLegacyAlias(aliasKey, cfg)
    if type(aliasKey) ~= "string" or aliasKey == "" then
        return
    end

    local entry = legacyAliasMap[aliasKey]
    if not entry then
        entry = {}
        legacyAliasMap[aliasKey] = entry
    end

    if type(cfg) == "table" then
        if type(cfg.get) == "function" then
            entry.get = cfg.get
        end
        if type(cfg.set) == "function" then
            entry.set = cfg.set
        end
        entry.targetPath = cfg.targetPath or entry.targetPath
    end

    rawset(addon, aliasKey, nil)
end

function Core.RegisterLegacyAliasPath(aliasKey, namespaceKey, moduleKey)
    if type(aliasKey) ~= "string" or aliasKey == "" then
        return
    end
    if type(namespaceKey) ~= "string" or namespaceKey == "" then
        return
    end
    if type(moduleKey) ~= "string" or moduleKey == "" then
        return
    end

    Core.RegisterLegacyAlias(aliasKey, {
        targetPath = namespaceKey .. "." .. moduleKey,
        get = function()
            local ns = rawget(addon, namespaceKey)
            return ns and ns[moduleKey] or nil
        end,
        set = function(value)
            local ns = rawget(addon, namespaceKey)
            if type(ns) ~= "table" then
                ns = {}
                rawset(addon, namespaceKey, ns)
            end
            ns[moduleKey] = value
        end,
    })
end

installLegacyAliasProxy()

function addon:IsPerfModeEnabled()
    return self.State and self.State.perfEnabled == true
end

function addon:SetPerfMode(enabled)
    local state = self.State or {}
    self.State = state
    state.perfEnabled = enabled and true or false
    self.hasPerf = state.perfEnabled and true or nil
    return state.perfEnabled
end

function addon:GetPerfThresholdMs()
    return getPerfThresholdMs()
end

function addon:SetPerfThresholdMs(value)
    local threshold = tonumber(value)
    if not threshold or threshold < 0 then
        return nil
    end
    local state = self.State or {}
    self.State = state
    state.perfThresholdMs = threshold
    return threshold
end

addon._PerfStart = function(self)
    if not self.hasPerf then
        return nil
    end
    local getTime = _G.GetTime
    if type(getTime) ~= "function" then
        return nil
    end
    return getTime()
end

addon._PerfFinish = function(self, label, startedAt, details)
    if not (self.hasPerf and startedAt) then
        return nil
    end
    local getTime = _G.GetTime
    if type(getTime) ~= "function" then
        return nil
    end

    local elapsedMs = (getTime() - startedAt) * 1000
    if elapsedMs < getPerfThresholdMs() then
        return elapsedMs
    end

    local suffix = ""
    if details and details ~= "" then
        suffix = " " .. tostring(details)
    end
    local template = (Diag.I and Diag.I.LogPerfBlock) or "[Perf] %s %.1fms%s"
    if self.info then
        self:info(template:format(tostring(label or "?"), elapsedMs, suffix))
    end
    return elapsedMs
end

local LEGACY_ALIAS_PATHS = {
    { "Master", "Controllers", "Master" },
    { "Logger", "Controllers", "Logger" },
    { "Warnings", "Controllers", "Warnings" },
    { "Changes", "Controllers", "Changes" },
    { "Spammer", "Controllers", "Spammer" },

    { "Raid", "Services", "Raid" },
    { "Loot", "Services", "Loot" },
    { "Rolls", "Services", "Rolls" },
    { "Chat", "Services", "Chat" },
    { "Syncer", "DB", "Syncer" },
    { "Reserves", "Services", "Reserves" },

    { "LootCounter", "Widgets", "LootCounter" },
    { "ReservesUI", "Widgets", "ReservesUI" },
    { "Config", "Widgets", "Config" },
}

for i = 1, #LEGACY_ALIAS_PATHS do
    local entry = LEGACY_ALIAS_PATHS[i]
    Core.RegisterLegacyAliasPath(entry[1], entry[2], entry[3])
end

local function installCompatGlobalFunctions()
    if addon._globalCompatInstalled then
        return
    end

    _G.table.shuffle = function(t)
        if type(t) ~= "table" then
            return t
        end

        local n = #t
        while n > 1 do
            local k = random(1, n)
            t[n], t[k] = t[k], t[n]
            n = n - 1
        end
        return t
    end

    _G.table.reverse = function(t, count)
        if type(t) ~= "table" then
            return t
        end

        local maxIndex = tonumber(count) or #t
        if maxIndex < 2 then
            return t
        end
        if maxIndex > #t then
            maxIndex = #t
        end

        local i, j = 1, maxIndex
        while i < j do
            t[i], t[j] = t[j], t[i]
            i = i + 1
            j = j - 1
        end
        return t
    end

    _G.string.trim = function(str)
        if str == nil then
            return ""
        end
        return gsub(tostring(str), "^%s*(.-)%s*$", "%1")
    end

    _G.string.startsWith = function(str, piece)
        if type(str) ~= "string" or type(piece) ~= "string" then
            return false
        end
        return strsub(str, 1, strlen(piece)) == piece
    end

    _G.string.endsWith = function(str, piece)
        if type(str) ~= "string" or type(piece) ~= "string" then
            return false
        end
        local lenPiece = strlen(piece)
        if #str < lenPiece then
            return false
        end
        return strsub(str, -lenPiece) == piece
    end

    addon._globalCompatInstalled = true
end

installCompatGlobalFunctions()

function Core.GetController(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local controllers = addon.Controllers
    return controllers and controllers[name] or nil
end

function Core.RequestControllerMethod(name, methodName, ...)
    if type(methodName) ~= "string" or methodName == "" then
        return nil
    end
    local controller = Core.GetController(name)
    local method = controller and controller[methodName]
    if type(method) ~= "function" then
        return nil
    end
    return method(controller, ...)
end

function Core.GetPlayerName()
    local state = addon.State
    state.player = state.player or {}
    local name = state.player.name or addon.UnitFullName("player")
    state.player.name = name
    return name
end

function Core.GetRealmName()
    local realm = GetRealmName and GetRealmName() or ""
    if type(realm) ~= "string" then
        return ""
    end
    return realm
end

function Core.GetUnitRank(unit, fallback)
    local groupLeader = addon.UnitIsGroupLeader or UnitIsGroupLeader
    local groupAssistant = addon.UnitIsGroupAssistant or UnitIsGroupAssistant

    if groupLeader and groupLeader(unit) then
        return 2
    end
    if groupAssistant and groupAssistant(unit) then
        return 1
    end
    return fallback or 0
end

-- Options/SavedVariables management lives in Core/Options.lua.
-- IsDebugEnabled / ApplyDebugSetting are exposed on addon.Options there.
-- Namespace registrations are owned by the modules that use them.

function Core.EnsureLootRuntimeState()
    local state = addon.State
    state.loot = state.loot or {}
    state.raid = state.raid or {}

    local lootState = state.loot
    local raidState = state.raid
    lootState.itemInfo = lootState.itemInfo or {}
    lootState.currentRollType = tonumber(lootState.currentRollType) or 4
    lootState.currentRollItem = tonumber(lootState.currentRollItem) or 0
    lootState.currentItemIndex = tonumber(lootState.currentItemIndex) or 0
    lootState.nextRollSessionId = tonumber(lootState.nextRollSessionId) or 1
    if lootState.nextRollSessionId < 1 then
        lootState.nextRollSessionId = 1
    end

    local selectedItemCount = tonumber(lootState.selectedItemCount) or 1
    if selectedItemCount < 1 then
        selectedItemCount = 1
    end
    lootState.selectedItemCount = selectedItemCount

    raidState.lastLootCount = tonumber(raidState.lastLootCount) or 1
    if raidState.lastLootCount < 1 then
        raidState.lastLootCount = 1
    end

    local lootContext = type(raidState.lootContext) == "table" and raidState.lootContext or {}
    raidState.lootContext = lootContext

    local LootStateHelpers = addon.Services and addon.Services.Loot and addon.Services.Loot._State
    if LootStateHelpers and LootStateHelpers.SyncRuntimeState then
        lootContext = LootStateHelpers.SyncRuntimeState(raidState)
        raidState.lootContext = lootContext
    else
        local LootContext = addon.Services and addon.Services.Loot and addon.Services.Loot._Context
        local normalizeBossEventContext = LootContext and LootContext.NormalizeBossEventContext
        local normalizeLootSessionState = LootContext and LootContext.NormalizeLootSessionState
        local normalizeLootSnapshotState = LootContext and LootContext.NormalizeLootSnapshotState
        local buildActiveLootContext = LootContext and LootContext.BuildActiveLootContext
        local projectLootWindowBossContext = LootContext and LootContext.ProjectLootWindowBossContext
        local projectLootSourceState = LootContext and LootContext.ProjectLootSourceState

        if
            normalizeBossEventContext
            and normalizeLootSessionState
            and normalizeLootSnapshotState
            and buildActiveLootContext
            and projectLootWindowBossContext
            and projectLootSourceState
        then
            lootContext.eventBoss = normalizeBossEventContext(raidState.bossEventContext or lootContext.eventBoss)
            raidState.bossEventContext = lootContext.eventBoss
            lootContext.activeLoot =
                buildActiveLootContext(lootContext.activeLoot, raidState.lootWindowBossContext or lootContext.activeWindow, raidState.lootSource or lootContext.source)
            lootContext.activeWindow = projectLootWindowBossContext(lootContext.activeLoot)
            raidState.lootWindowBossContext = lootContext.activeWindow
            lootContext.sessions = normalizeLootSessionState(raidState.lootBossSessions or lootContext.sessions)
            raidState.lootBossSessions = lootContext.sessions
            lootContext.snapshots = normalizeLootSnapshotState(raidState.lootWindowItemSnapshots or lootContext.snapshots)
            raidState.lootWindowItemSnapshots = lootContext.snapshots
            lootContext.source = projectLootSourceState(lootContext.activeLoot)
            raidState.lootSource = lootContext.source
        else
            -- During early bootstrap, Loot context services may not be loaded yet.
            -- Keep runtime/legacy state mirrored without hard-failing load.
            lootContext.eventBoss = raidState.bossEventContext or lootContext.eventBoss or nil
            raidState.bossEventContext = lootContext.eventBoss

            lootContext.activeWindow = raidState.lootWindowBossContext or lootContext.activeWindow or nil
            raidState.lootWindowBossContext = lootContext.activeWindow

            lootContext.sessions = raidState.lootBossSessions or lootContext.sessions or nil
            raidState.lootBossSessions = lootContext.sessions

            lootContext.snapshots = raidState.lootWindowItemSnapshots or lootContext.snapshots or nil
            raidState.lootWindowItemSnapshots = lootContext.snapshots

            lootContext.source = raidState.lootSource or lootContext.source or nil
            raidState.lootSource = lootContext.source
        end
    end

    lootState.lootCount = tonumber(lootState.lootCount) or 0
    if lootState.lootCount < 0 then
        lootState.lootCount = 0
    end
    lootState.rollsCount = tonumber(lootState.rollsCount) or 0
    if lootState.rollsCount < 0 then
        lootState.rollsCount = 0
    end
    lootState.itemTraded = tonumber(lootState.itemTraded) or 0
    if lootState.itemTraded < 0 then
        lootState.itemTraded = 0
    end

    lootState.rollStarted = lootState.rollStarted == true
    if lootState.rollStarted and type(lootState.rollSession) ~= "table" then
        local sid = "RS:" .. tostring(lootState.nextRollSessionId)
        lootState.nextRollSessionId = lootState.nextRollSessionId + 1
        lootState.rollSession = {
            id = sid,
            itemKey = nil,
            itemId = nil,
            itemLink = nil,
            rollType = tonumber(lootState.currentRollType) or 4,
            lootNid = tonumber(lootState.currentRollItem) or 0,
            bossNid = nil,
            startedAt = GetTime(),
            endsAt = nil,
            source = "lootWindow",
            expectedWinners = selectedItemCount,
            active = true,
        }
    end
    if type(lootState.rollSession) == "table" then
        local session = lootState.rollSession
        if session.id == nil or session.id == "" then
            session.id = "RS:" .. tostring(lootState.nextRollSessionId)
            lootState.nextRollSessionId = lootState.nextRollSessionId + 1
        else
            session.id = tostring(session.id)
        end
        session.itemKey = session.itemKey or nil
        session.itemId = tonumber(session.itemId) or nil
        session.itemLink = session.itemLink or nil
        session.rollType = tonumber(session.rollType) or tonumber(lootState.currentRollType) or 4
        session.lootNid = tonumber(session.lootNid) or tonumber(lootState.currentRollItem) or 0
        session.bossNid = tonumber(session.bossNid) or nil
        session.startedAt = tonumber(session.startedAt) or GetTime()
        session.endsAt = tonumber(session.endsAt) or nil
        session.source = session.source or "lootWindow"
        session.expectedWinners = tonumber(session.expectedWinners) or selectedItemCount
        if session.expectedWinners < 1 then
            session.expectedWinners = 1
        end
        session.active = session.active ~= false
        lootState.currentRollType = session.rollType
        lootState.currentRollItem = session.lootNid
    end

    if lootState.opened == nil then
        lootState.opened = false
    end
    if lootState.fromInventory == nil then
        lootState.fromInventory = false
    end
    lootState.pendingAwards = lootState.pendingAwards or {}

    return state, lootState, lootState.itemInfo, raidState
end

function Core.GetItemIndex()
    local _, lootState = Core.EnsureLootRuntimeState()
    return tonumber(lootState.currentItemIndex) or 0
end

function Core.GetFeatureShared()
    local constants = addon.C or {}
    local core = addon.Core
    local state, lootState, itemInfo, raidState = core.EnsureLootRuntimeState()

    return {
        L = addon.L,
        Diag = Diag,
        Options = addon.Options,
        Events = addon.Events,
        Features = addon.Features,
        C = constants,
        Core = core,
        DB = addon.DB,
        Bus = addon.Bus,

        Strings = addon.Strings,
        Colors = addon.Colors,
        Time = addon.Time,
        Base64 = addon.Base64,
        Comms = addon.Comms,
        Sort = addon.Sort,
        Item = addon.Item,
        IgnoredItems = addon.IgnoredItems,
        IgnoredMobs = addon.IgnoredMobs,

        UI = addon.UI,
        Frames = addon.Frames,
        UIScaffold = addon.UIScaffold,
        UIPrimitives = addon.UIPrimitives,
        UIRowVisuals = addon.UIRowVisuals,
        ListController = addon.ListController,
        MultiSelect = addon.MultiSelect,

        Services = addon.Services,
        Controllers = addon.Controllers,
        Widgets = addon.Widgets,

        BindModuleRequestRefresh = core.BindModuleRequestRefresh,
        BindModuleToggleHide = core.BindModuleToggleHide,
        MakeModuleFrameGetter = core.MakeModuleFrameGetter,

        UnitIsGroupLeader = addon.UnitIsGroupLeader,
        UnitIsGroupAssistant = addon.UnitIsGroupAssistant,
        tContains = _G.tContains,

        ITEM_LINK_PATTERN = constants.ITEM_LINK_PATTERN,
        rollTypes = constants.rollTypes,
        lootTypesColored = constants.lootTypesColored,
        itemColors = constants.itemColors,
        RAID_TARGET_MARKERS = constants.RAID_TARGET_MARKERS,
        K_COLOR = constants.K_COLOR,
        RT_COLOR = constants.RT_COLOR,

        coreState = state,
        raidState = raidState,
        lootState = lootState,
        itemInfo = itemInfo,
        GetItemIndex = core.GetItemIndex or function()
            return 0
        end,
    }
end

do
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
    local Events = feature.Events or addon.Events
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

    -- Rimuovi le API timer globali iniettate da LibCompat:Embed: i moduli devono
    -- usare il mixin addon.Timer (Timer.BindMixin + self:ScheduleTimer/...). Module
    -- Timer è in Layer 4 e non è disponibile qui (Layer 1); l'embed di addon
    -- avviene in ADDON_LOADED, prima che gli handler di evento siano registrati.
    addon.After = nil
    addon.NewTimer = nil
    addon.NewTicker = nil
    addon.CancelTimer = nil

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

        local function handleEvent(_, eventName, ...)
            local list = listeners[eventName]
            if not list then
                return
            end

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

        local function addListener(obj, eventName)
            if type(eventName) ~= "string" or eventName == "" then
                error('Usage: RegisterEvent("EVENT_NAME")', 3)
            end

            local list = listeners[eventName]
            if not list then
                list = {}
                listeners[eventName] = list
                mainFrame:RegisterEvent(eventName)
            else
                for i = 1, #list do
                    if list[i] == obj then
                        return
                    end -- already registered
                end
            end

            list[#list + 1] = obj
        end

        local function removeListener(obj, eventName)
            local list = listeners[eventName]
            if not list then
                return
            end

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
            addListener(self, eventName)
        end

        function addon:RegisterEvents(...)
            for i = 1, select("#", ...) do
                addListener(self, select(i, ...))
            end
        end

        function addon:UnregisterEvent(eventName)
            removeListener(self, eventName)
        end

        function addon:UnregisterEvents()
            local keys = {}
            for eventName in pairs(listeners) do
                keys[#keys + 1] = eventName
            end
            for i = 1, #keys do
                removeListener(self, keys[i])
            end
        end

        function addon:UnregisterAllEvents()
            self:UnregisterEvents()
        end

        mainFrame:SetScript("OnEvent", handleEvent)

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

    function Core.RequireServiceMethod(serviceName, serviceTable, methodName)
        assert(type(serviceTable) == "table", "KRT missing service: " .. tostring(serviceName))
        local method = serviceTable[methodName]
        assert(type(method) == "function", "KRT missing service method: " .. tostring(serviceName) .. "." .. tostring(methodName))
        return method
    end

    local function getService(serviceName)
        local services = addon.Services
        if type(services) ~= "table" then
            return nil
        end
        return services[serviceName]
    end

    local function getRaidService()
        return getService("Raid")
    end

    local function getRaidStoreOrNil(contextTag, requiredMethods)
        if not Core.GetRaidStoreOrNil then
            return nil
        end
        return Core.GetRaidStoreOrNil(contextTag, requiredMethods)
    end

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
        local raidStore = getRaidStoreOrNil("Core.EnsureRaidSchema", { "NormalizeRaidRecord" })
        if raidStore then
            return raidStore:NormalizeRaidRecord(raid)
        end
        return raid
    end

    function Core.EnsureRaidById(raidNum)
        local id = tonumber(raidNum)
        if not id then
            return nil, nil
        end

        local raidStore = getRaidStoreOrNil("Core.EnsureRaidById", { "GetRaidByIndex" })
        if raidStore then
            return raidStore:GetRaidByIndex(id)
        end
        return nil, id
    end

    function Core.EnsureRaidByNid(raidNid)
        local nid = tonumber(raidNid)
        if not nid then
            return nil, nil, nil
        end

        local raidStore = getRaidStoreOrNil("Core.EnsureRaidByNid", { "GetRaidByNid" })
        if raidStore then
            return raidStore:GetRaidByNid(nid)
        end
        return nil, nil, nid
    end

    function Core.GetRaidNidById(raidNum)
        local raidStore = getRaidStoreOrNil("Core.GetRaidNidById", { "GetRaidNidByIndex" })
        if raidStore then
            return raidStore:GetRaidNidByIndex(raidNum)
        end
        local raid = Core.EnsureRaidById(raidNum)
        return raid and tonumber(raid.raidNid) or nil
    end

    function Core.GetRaidIdByNid(raidNid)
        local raidStore = getRaidStoreOrNil("Core.GetRaidIdByNid", { "GetRaidIndexByNid" })
        if raidStore then
            return raidStore:GetRaidIndexByNid(raidNid)
        end
        local _, idx = Core.EnsureRaidByNid(raidNid)
        return idx
    end

    function Core.StripRuntimeRaidCaches(raid)
        local raidStore = getRaidStoreOrNil("Core.StripRuntimeRaidCaches", { "StripRuntime" })
        if raidStore then
            raidStore:StripRuntime(raid)
            return
        end
        if type(raid) ~= "table" then
            return
        end
        raid._runtime = nil
        raid._playersByName = nil
        raid._playerIdxByNid = nil
        raid._bossIdxByNid = nil
        raid._lootIdxByNid = nil
    end

    function Core.NormalizeSavedVariablesAfterLoad()
        local raidStore = getRaidStoreOrNil("Core.NormalizeSavedVariablesAfterLoad", { "NormalizeAllRaids" })
        if raidStore and type(raidStore.NormalizeAllRaids) == "function" then
            raidStore:NormalizeAllRaids("load")
            return
        end
        if type(KRT_Raids) ~= "table" then
            return
        end
        for i = 1, #KRT_Raids do
            Core.EnsureRaidSchema(KRT_Raids[i])
        end
    end

    function Core.PrepareSavedVariablesForSave(contextTag)
        local raidStore = getRaidStoreOrNil("Core.PrepareSavedVariablesForSave", { "PrepareAllRaidsForSave" })
        if raidStore then
            if type(raidStore.PrepareAllRaidsForSave) == "function" then
                raidStore:PrepareAllRaidsForSave()
            elseif type(raidStore.StripAllRuntime) == "function" then
                raidStore:StripAllRuntime()
            end
        elseif type(KRT_Raids) == "table" then
            for i = 1, #KRT_Raids do
                Core.StripRuntimeRaidCaches(KRT_Raids[i])
            end
        end

        local reservesService = getService("Reserves")
        if reservesService and type(reservesService.Save) == "function" then
            reservesService:Save(contextTag or "save")
        end
    end

    -- =========== Main Event Handlers  =========== --
    local addonEvents = {
        CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM",
        CHAT_MSG_LOOT = "CHAT_MSG_LOOT",
        CHAT_MSG_WHISPER = "CHAT_MSG_WHISPER",
        START_LOOT_ROLL = "START_LOOT_ROLL",
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
        UI_ERROR_MESSAGE = "UI_ERROR_MESSAGE",
        TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
        TRADE_REQUEST_CANCEL = "TRADE_REQUEST_CANCEL",
        TRADE_CLOSED = "TRADE_CLOSED",
        PLAYER_LOGOUT = "PLAYER_LOGOUT",
    }

    do
        local wowBusEvents = {
            LOOT_OPENED = WowEvents.LootOpened,
            LOOT_CLOSED = WowEvents.LootClosed,
            LOOT_SLOT_CLEARED = WowEvents.LootSlotCleared,
            UI_ERROR_MESSAGE = WowEvents.UiErrorMessage,
            CHAT_MSG_WHISPER = WowEvents.ChatMsgWhisper,
            TRADE_ACCEPT_UPDATE = WowEvents.TradeAcceptUpdate,
            TRADE_REQUEST_CANCEL = WowEvents.TradeRequestCancel,
            TRADE_CLOSED = WowEvents.TradeClosed,
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
        if name ~= addonName then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        ensureDBManager()
        local lvl = addon.GetLogLevel and addon:GetLogLevel()
        addon:info(Diag.I.LogCoreLoaded:format(tostring(GetAddOnMetadata(addonName, "Version")), tostring(lvl), tostring(true)))
        if addon.Options and addon.Options.EnsureLoaded then
            addon.Options.EnsureLoaded()
            addon.Options.SetDebugEnabled(false)
        end
        -- Bind Timer mixin sull'addon (Layer 4 ora disponibile) per i timer di Init.
        if addon.Timer and addon.Timer.BindMixin then
            addon.Timer.BindMixin(addon, "Core")
        end
        local minimap = addon.Minimap
        if minimap and minimap.EnsureUI then
            minimap:EnsureUI()
        elseif minimap and minimap.OnLoad then
            minimap:OnLoad()
        end
        local reservesService = getService("Reserves")
        if reservesService and reservesService.Load then
            reservesService:Load()
        end
        if addon.Comms and addon.Comms.EnsureVersionPrefix then
            addon.Comms:EnsureVersionPrefix()
        end
        local reservesSync = reservesService and reservesService._Sync or nil
        if reservesSync and reservesSync.EnsurePrefix then
            reservesSync:EnsurePrefix()
        end
        Core.NormalizeSavedVariablesAfterLoad()
        for event in pairs(addonEvents) do
            self:RegisterEvent(event)
        end
        if isDebugEnabled() then
            addon:debug(Diag.D.LogCoreEventsRegistered:format(addon.tLength(addonEvents)))
        end
        self:RAID_ROSTER_UPDATE(true)
    end

    local rosterUpdateDebounceSeconds = 0.2

    local function scheduleRaidInstanceChecksIfRecognized(instanceName, instanceType, instanceDiff, emitRecognizedLog)
        local raidService = getRaidService()
        if instanceType ~= "raid" or L.RaidZones[instanceName] == nil then
            return false
        end
        if not raidService then
            return false
        end
        if emitRecognizedLog then
            if isDebugEnabled() then
                addon:debug(Diag.D.LogRaidInstanceRecognized:format(tostring(instanceName), tostring(instanceDiff)))
            end
        end
        raidService:ScheduleInstanceChecks()
        return true
    end

    local function processRaidRosterUpdate()
        local raidService = getRaidService()
        if not raidService then
            return
        end

        local changed, delta = raidService:UpdateRaidRoster()
        if not changed then
            return
        end

        -- Single source of truth for roster change notifications (join/update/leave delta).
        Bus.TriggerEvent(InternalEvents.RaidRosterDelta, delta, raidService:GetRosterVersion(), Core.GetCurrentRaid())
    end

    -- RAID_ROSTER_UPDATE: Updates the raid roster when it changes.
    function addon:RAID_ROSTER_UPDATE(forceImmediate)
        if self._raidRosterUpdateHandle then
            self:CancelTimer(self._raidRosterUpdateHandle)
            self._raidRosterUpdateHandle = nil
        end

        if forceImmediate then
            processRaidRosterUpdate()
            return
        end

        self._raidRosterUpdateHandle = self:ScheduleTimer(function()
            self._raidRosterUpdateHandle = nil
            processRaidRosterUpdate()
        end, rosterUpdateDebounceSeconds)
    end

    -- RAID_INSTANCE_WELCOME: Triggered when entering a raid instance.
    function addon:RAID_INSTANCE_WELCOME(...)
        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        local _, nextReset = ...
        local resolvedNextReset = Core.SetNextReset(nextReset)
        if isTraceEnabled() then
            addon:trace(Diag.D.LogRaidInstanceWelcome:format(tostring(instanceName), tostring(instanceType), tostring(instanceDiff), tostring(resolvedNextReset)))
        end
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
        local module = getRaidService()
        if not module then
            return
        end
        if isTraceEnabled() then
            addon:trace(Diag.D.LogCorePlayerEnteringWorld)
        end
        module:CancelInstanceChecks()
        -- Restart the first-check timer on login (timer owned by raid service module).
        if module.firstCheckHandle then
            module:CancelTimer(module.firstCheckHandle)
            module.firstCheckHandle = nil
        end
        module.firstCheckHandle = module:ScheduleTimer(function()
            module:FirstCheck()
        end, 3)
    end

    local function observePassiveLootMessage(msg)
        local currentRaid = Core.GetCurrentRaid()
        local raidService = getRaidService()
        local lootService = getService("Loot")
        if not currentRaid then
            return raidService, nil
        end

        if lootService and lootService.AddGroupLootMessage then
            return raidService, lootService:AddGroupLootMessage(msg)
        end

        return raidService, nil
    end

    -- CHAT_MSG_LOOT: Adds looted items to the raid log.
    function addon:CHAT_MSG_LOOT(msg)
        local perfStart = addon.hasPerf and addon:_PerfStart() or nil
        if isTraceEnabled() then
            addon:trace(Diag.D.LogLootChatMsgLootRaw:format(tostring(msg)))
        end
        local currentRaid = Core.GetCurrentRaid()
        local raidService, observedType = observePassiveLootMessage(msg)
        local lootService = getService("Loot")
        if not (currentRaid and raidService) then
            if perfStart then
                addon:_PerfFinish("CHAT_MSG_LOOT", perfStart, "raid=none")
            end
            return
        end

        local canObservePassiveLoot = raidService.CanObservePassiveLoot and raidService:CanObservePassiveLoot()
        if canObservePassiveLoot and (observedType == nil or observedType == "winner") then
            if lootService and lootService.AddLoot then
                lootService:AddLoot(msg)
            end
        end
        if perfStart then
            addon:_PerfFinish("CHAT_MSG_LOOT", perfStart, "raid=" .. tostring(currentRaid) .. " observed=" .. tostring(observedType))
        end
    end

    -- CHAT_MSG_SYSTEM: Forwards roll messages to the Rolls module.
    function addon:CHAT_MSG_SYSTEM(msg)
        local perfStart = addon.hasPerf and addon:_PerfStart() or nil
        local currentRaid = Core.GetCurrentRaid()
        local raidService, observedType = observePassiveLootMessage(msg)
        local lootService = getService("Loot")
        if currentRaid and raidService then
            local canObservePassiveLoot = raidService.CanObservePassiveLoot and raidService:CanObservePassiveLoot()
            if canObservePassiveLoot and observedType == "winner" then
                if lootService and lootService.AddLoot then
                    lootService:AddLoot(msg)
                end
            end
        end

        if Core.GetCurrentRaid() and raidService and raidService.CanUseCapability and not raidService:CanUseCapability("loot") then
            if perfStart then
                addon:_PerfFinish("CHAT_MSG_SYSTEM", perfStart, "raid=" .. tostring(currentRaid) .. " observed=" .. tostring(observedType) .. " blocked=loot")
            end
            return
        end
        local rollsService = getService("Rolls")
        if rollsService and rollsService.CHAT_MSG_SYSTEM then
            rollsService:CHAT_MSG_SYSTEM(msg)
        end
        if perfStart then
            addon:_PerfFinish("CHAT_MSG_SYSTEM", perfStart, "raid=" .. tostring(currentRaid) .. " observed=" .. tostring(observedType))
        end
    end

    function addon:START_LOOT_ROLL(rollId, rollTime)
        local perfStart = addon.hasPerf and addon:_PerfStart() or nil
        local currentRaid = Core.GetCurrentRaid()
        local lootService = getService("Loot")
        if currentRaid and lootService and lootService.AddPassiveLootRoll then
            lootService:AddPassiveLootRoll(rollId, rollTime)
        end
        if perfStart then
            addon:_PerfFinish("START_LOOT_ROLL", perfStart, "raid=" .. tostring(currentRaid) .. " rollId=" .. tostring(rollId))
        end
    end

    -- CHAT_MSG_ADDON: Forwards addon communication messages to the Syncer module.
    function addon:CHAT_MSG_ADDON(prefix, msg, channel, sender)
        if addon.Comms and addon.Comms.RequestVersionMessageHandling and addon.Comms:RequestVersionMessageHandling(prefix, msg, channel, sender) then
            return
        end
        local reservesService = getService("Reserves")
        local reservesSync = reservesService and reservesService._Sync or nil
        if reservesSync and reservesSync.RequestMessageHandling and reservesSync:RequestMessageHandling(prefix, msg, channel, sender) then
            return
        end
        local syncer = Core.GetSyncer and Core.GetSyncer() or nil
        if syncer and syncer.OnAddonMessage then
            syncer:OnAddonMessage(prefix, msg, channel, sender)
        end
    end

    -- CHAT_MSG_MONSTER_YELL: Logs a boss kill based on specific boss yells.
    function addon:CHAT_MSG_MONSTER_YELL(...)
        local text = ...
        local raidService = getRaidService()
        if raidService and L.BossYells[text] and Core.GetCurrentRaid() then
            if isTraceEnabled() then
                addon:trace(Diag.D.LogBossYellMatched:format(tostring(text), tostring(L.BossYells[text])))
            end
            raidService:AddBoss(L.BossYells[text])
        end
    end

    -- COMBAT_LOG_EVENT_UNFILTERED: Delegates boss-kill detection to the Raid service.
    function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
        local raidService = getRaidService()
        if raidService and raidService.COMBAT_LOG_EVENT_UNFILTERED then
            raidService:COMBAT_LOG_EVENT_UNFILTERED(...)
        end
    end

    -- PLAYER_LOGOUT: Prepare canonical SavedVariables payloads before persistence.
    function addon:PLAYER_LOGOUT()
        Core.PrepareSavedVariablesForSave("logout")
    end
end
