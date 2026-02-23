-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
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
local type = type
local rawget, rawset = rawget, rawset
local getmetatable, setmetatable = getmetatable, setmetatable
local tostring = tostring

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

function Core.registerLegacyAlias(aliasKey, cfg)
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

function Core.registerLegacyAliasPath(aliasKey, namespaceKey, moduleKey)
    if type(aliasKey) ~= "string" or aliasKey == "" then
        return
    end
    if type(namespaceKey) ~= "string" or namespaceKey == "" then
        return
    end
    if type(moduleKey) ~= "string" or moduleKey == "" then
        return
    end

    Core.registerLegacyAlias(aliasKey, {
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
    Core.registerLegacyAliasPath(entry[1], entry[2], entry[3])
end

local function ensureLootRuntimeState()
    local state = addon.State
    state.loot = state.loot or {}

    local lootState = state.loot
    lootState.itemInfo = lootState.itemInfo or {}

    return state, lootState, lootState.itemInfo
end

function Core.getFeatureShared()
    local constants = addon.C
    local core = addon.Core
    local state, lootState, itemInfo = ensureLootRuntimeState()

    return {
        L = addon.L,
        Diag = Diag,
        Utils = addon.Utils,
        Events = addon.Events,
        Features = addon.Features,
        C = constants,
        Core = core,

        bindModuleRequestRefresh = core.bindModuleRequestRefresh,
        bindModuleToggleHide = core.bindModuleToggleHide,
        makeModuleFrameGetter = core.makeModuleFrameGetter,

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
        GetItemIndex = core.GetItemIndex,
    }
end
