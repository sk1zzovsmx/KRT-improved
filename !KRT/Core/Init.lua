-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local addonName = select(1, ...)

if not addon then
    error("KRT addon table not found in Core/Init.lua")
end

addon.name = addon.name or addonName
addon.Core = addon.Core or {}
addon.L = addon.L or {}
addon.Diagnose = addon.Diagnose or {}
addon.State = addon.State or {}
addon.C = addon.C or {}
addon.Events = addon.Events or {}
addon.Features = addon.Features or {}
addon.Controllers = addon.Controllers or {}
addon.Services = addon.Services or {}
addon.Widgets = addon.Widgets or {}

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
local lower = string.lower

local Core = addon.Core
local Diagnose = addon.Diagnose

local Diag = setmetatable({}, {
    __index = Diagnose,
    __newindex = function(_, key, value)
        Diagnose[key] = value
    end,
})

local legacyAliasMap = addon.LegacyAliases or {}
addon.LegacyAliases = legacyAliasMap

local function isDebugEnabled()
    local state = addon.State
    return state and state.debugEnabled == true
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
        local template = (Diag.W and Diag.W.LogLegacyAliasAccess)
            or "[Compat] Legacy alias used alias=%s target=%s site=%s"
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
    { "Syncer", "Services", "Syncer" },
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

addon.Options = addon.Options or {}
local Options = addon.Options

Options.defaultValues = Options.defaultValues or {
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
    showLootCounterDuringMSRoll = false,
    minimapButton = true,
    countdownSimpleRaidMsg = false,
    countdownDuration = 5,
    countdownRollsBlock = true,
    srImportMode = 0,
}

local function copyFlat(dst, src)
    for key, value in pairs(src or {}) do
        dst[key] = value
    end
    return dst
end

function Options.NewOptions()
    return copyFlat({}, Options.defaultValues)
end

function Options.IsDebugEnabled()
    return addon and addon.State and addon.State.debugEnabled == true
end

function Options.ApplyDebugSetting(enabled)
    local state = addon.State
    state.debugEnabled = enabled and true or false

    local levels = addon and addon.Debugger and addon.Debugger.logLevels
    local level = enabled and (levels and levels.DEBUG) or (levels and levels.INFO)
    if level and addon and addon.SetLogLevel then
        addon:SetLogLevel(level)
    end
end

function Options.SetOption(key, value)
    if type(key) ~= "string" or key == "" then
        return false
    end

    local options = addon and addon.options
    if type(options) ~= "table" then
        if type(KRT_Options) == "table" then
            options = KRT_Options
        else
            options = {}
            KRT_Options = options
        end
        addon.options = options
    end

    options[key] = value

    if type(KRT_Options) == "table" and KRT_Options ~= options then
        KRT_Options[key] = value
    end

    return true
end

function Options.LoadOptions()
    local options = Options.NewOptions()
    if type(KRT_Options) == "table" then
        copyFlat(options, KRT_Options)
    end

    options.debug = nil
    KRT_Options = options
    addon.options = options

    Options.ApplyDebugSetting(false)
    return options
end

function Options.RestoreDefaults()
    local options = Options.NewOptions()
    KRT_Options = options
    addon.options = options
    Options.ApplyDebugSetting(false)
    return options
end

addon.LoadOptions = Options.LoadOptions


do
    local Events = addon.Events
    Events.Internal = Events.Internal or {}
    Events.Wow = Events.Wow or {}

    local Internal = Events.Internal
    local Wow = Events.Wow

    Internal.AddRoll = "AddRoll"
    Internal.LoggerLootLogRequest = "LoggerLootLogRequest"
    Internal.LoggerSelectRaid = "LoggerSelectRaid"
    Internal.LoggerSelectBoss = "LoggerSelectBoss"
    Internal.LoggerSelectPlayer = "LoggerSelectPlayer"
    Internal.LoggerSelectBossPlayer = "LoggerSelectBossPlayer"
    Internal.LoggerSelectItem = "LoggerSelectItem"
    Internal.PlayerCountChanged = "PlayerCountChanged"
    Internal.RaidCreate = "RaidCreate"
    Internal.RaidLeave = "RaidLeave"
    Internal.RaidLootUpdate = "RaidLootUpdate"
    Internal.RaidRosterDelta = "RaidRosterDelta"
    Internal.ReservesDataChanged = "ReservesDataChanged"
    Internal.SetItem = "SetItem"

    Internal.ConfigSortAscending = "ConfigsortAscending"
    Internal.ConfigShowLootCounterDuringMSRoll = "ConfigshowLootCounterDuringMSRoll"

    Wow.LOOT_OPENED = "wow.LOOT_OPENED"
    Wow.LOOT_CLOSED = "wow.LOOT_CLOSED"
    Wow.LOOT_SLOT_CLEARED = "wow.LOOT_SLOT_CLEARED"
    Wow.TRADE_ACCEPT_UPDATE = "wow.TRADE_ACCEPT_UPDATE"
    Wow.TRADE_REQUEST_CANCEL = "wow.TRADE_REQUEST_CANCEL"
    Wow.TRADE_CLOSED = "wow.TRADE_CLOSED"

    function Events.ConfigOptionChanged(optionName)
        if type(optionName) ~= "string" or optionName == "" then
            return nil
        end
        return "Config" .. optionName
    end

    function Events.WowForwarded(eventName)
        if type(eventName) ~= "string" or eventName == "" then
            return nil
        end
        return Wow[eventName] or ("wow." .. tostring(eventName))
    end

end

do
    local Features = addon.Features
    Features.WidgetFlags = Features.WidgetFlags or {}
    Features.Profiles = Features.Profiles or {
        full = {
            Config = true,
            LootCounter = true,
            Reserves = true,
        },
        core = {
            Config = false,
            LootCounter = false,
            Reserves = false,
        },
    }

    local function normalizeProfile(profileName)
        if type(profileName) ~= "string" or profileName == "" then
            return "full"
        end
        return lower(profileName)
    end

    local function applyProfileFlags(profileName)
        local profileKey = normalizeProfile(profileName)
        local profileFlags = Features.Profiles[profileKey] or Features.Profiles.full
        local flags = Features.WidgetFlags

        for widgetId in pairs(flags) do
            flags[widgetId] = nil
        end
        for widgetId, enabled in pairs(profileFlags or {}) do
            flags[widgetId] = enabled == true
        end

        Features.Profile = profileKey
        return profileKey
    end

    function Features:SetProfile(profileName)
        return applyProfileFlags(profileName)
    end

    function Features:Set(widgetId, enabled)
        if type(widgetId) ~= "string" or widgetId == "" then
            return false
        end
        self.WidgetFlags[widgetId] = enabled == true
        return true
    end

    function Features:IsEnabled(widgetId)
        if type(widgetId) ~= "string" or widgetId == "" then
            return false
        end

        local flag = self.WidgetFlags[widgetId]
        if flag == nil then
            return true
        end
        return flag == true
    end

    function Features:GetProfile()
        return self.Profile or "full"
    end

    local requestedProfile = _G.KRT_FEATURE_PROFILE
    if type(requestedProfile) ~= "string" or requestedProfile == "" then
        requestedProfile = Features.Profile or "full"
    end
    applyProfileFlags(requestedProfile)

    local overrides = _G.KRT_FEATURE_FLAGS
    if type(overrides) == "table" then
        for widgetId, enabled in pairs(overrides) do
            Features:Set(widgetId, enabled)
        end
    end
end

function Core.EnsureLootRuntimeState()
    local state = addon.State
    state.loot = state.loot or {}

    local lootState = state.loot
    lootState.itemInfo = lootState.itemInfo or {}
    lootState.currentRollType = tonumber(lootState.currentRollType) or 4
    lootState.currentRollItem = tonumber(lootState.currentRollItem) or 0
    lootState.currentItemIndex = tonumber(lootState.currentItemIndex) or 0

    lootState.itemCount = tonumber(lootState.itemCount) or 1
    if lootState.itemCount < 1 then
        lootState.itemCount = 1
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

    if lootState.opened == nil then
        lootState.opened = false
    end
    if lootState.fromInventory == nil then
        lootState.fromInventory = false
    end
    lootState.pendingAwards = lootState.pendingAwards or {}

    return state, lootState, lootState.itemInfo
end

function Core.GetItemIndex()
    local _, lootState = Core.EnsureLootRuntimeState()
    return tonumber(lootState.currentItemIndex) or 0
end

function Core.GetFeatureShared()
    local constants = addon.C or {}
    local core = addon.Core
    local state, lootState, itemInfo = core.EnsureLootRuntimeState()

    return {
        L = addon.L,
        Diag = Diag,
        Options = addon.Options,
        Events = addon.Events,
        Features = addon.Features,
        C = constants,
        Core = core,
        Bus = addon.Bus,

        Strings = addon.Strings,
        Colors = addon.Colors,
        Time = addon.Time,
        Base64 = addon.Base64,
        Comms = addon.Comms,
        ItemProbe = addon.ItemProbe,

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
        lootState = lootState,
        itemInfo = itemInfo,
        GetItemIndex = core.GetItemIndex or function()
            return 0
        end,
    }
end
