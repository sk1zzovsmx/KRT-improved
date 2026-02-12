--[[
    KRT.lua
]]

local addonName, addon = ...
addon = addon or {}
addon.name = addon.name or addonName
addon.L = addon.L or {}
addon.Diagnose = addon.Diagnose or {}

local Diagnose = addon.Diagnose
local Diag = setmetatable({}, {
    __index = Diagnose,
})
local Utils = addon.Utils
local C = addon.C

local _G = _G
_G["KRT"] = addon

-- =========== Saved Variables  =========== --
-- These variables are persisted across sessions for the addon.

KRT_Raids = KRT_Raids or {}
KRT_Players = KRT_Players or {}
KRT_Reserves = (type(KRT_Reserves) == "table") and KRT_Reserves or {}
KRT_Warnings = KRT_Warnings or {}
KRT_Spammer = KRT_Spammer or {}
KRT_Options = KRT_Options or {}

-- Runtime-only session state (not persisted in TOC SavedVariables)
KRT_CurrentRaid = KRT_CurrentRaid or nil
KRT_LastBoss = KRT_LastBoss or nil
KRT_NextReset = KRT_NextReset or 0

-- =========== External Libraries / Bootstrap  =========== --
local Compat = LibStub("LibCompat-1.0")
addon.Compat = Compat
addon.BossIDs = LibStub("LibBossIDs-1.0")
addon.Debugger = LibStub("LibLogger-1.0")
addon.Deformat = LibStub("LibDeformat-3.0")
addon.CallbackHandler = LibStub("CallbackHandler-1.0")

Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
addon.Debugger:Embed(addon)

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
addon.State = addon.State or {}
local coreState = addon.State

coreState.frames = coreState.frames or {}
local frames = coreState.frames
frames.main = frames.main or CreateFrame("Frame")

-- Addon UI frame used by event dispatcher
local mainFrame = frames.main

addon.Core = addon.Core or {}
local Core = addon.Core

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
                table.remove(list, i)
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

-- Alias: redirect to Utils for backwards compatibility
-- (function moved to Utils.lua; this wrapper allows existing code to use addon:makeUIFrameController(...))
function addon:makeUIFrameController(getFrame, requestRefreshFn)
    return Utils.makeUIFrameController(getFrame, requestRefreshFn)
end

local function bindModuleRequestRefresh(module, getFrame)
    local requestRefresh = Utils.makeEventDrivenRefresher(getFrame, function()
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
    local getGlobalFrame = Utils.makeFrameGetter(globalFrameName)
    return function()
        local frame = module.frame or getGlobalFrame()
        if frame and not module.frame then
            module.frame = frame
        end
        return frame
    end
end

Core.bindModuleRequestRefresh = bindModuleRequestRefresh
Core.bindModuleToggleHide = bindModuleToggleHide
Core.makeModuleFrameGetter = makeModuleFrameGetter

-- Shared feature header context for extracted runtime modules.
local function ensureLootRuntimeState()
    addon.State = addon.State or {}
    local state = addon.State
    state.loot = state.loot or {}

    local lootState = state.loot
    lootState.itemInfo = lootState.itemInfo or {}
    lootState.currentRollType = lootState.currentRollType or 4
    lootState.currentRollItem = lootState.currentRollItem or 0
    lootState.currentItemIndex = lootState.currentItemIndex or 0
    lootState.itemCount = lootState.itemCount or 1
    lootState.lootCount = lootState.lootCount or 0
    lootState.rollsCount = lootState.rollsCount or 0
    lootState.itemTraded = lootState.itemTraded or 0
    lootState.rollStarted = lootState.rollStarted or false
    if lootState.opened == nil then lootState.opened = false end
    if lootState.fromInventory == nil then lootState.fromInventory = false end
    lootState.pendingAwards = lootState.pendingAwards or {}

    return state, lootState, lootState.itemInfo
end

local function getCurrentItemIndex()
    local _, lootState = ensureLootRuntimeState()
    return lootState.currentItemIndex
end

function Core.getFeatureShared()
    local constants = C or addon.C or {}
    local state, lootState, itemInfo = ensureLootRuntimeState()

    return {
        L = addon.L,
        Diag = Diag,
        Utils = Utils,
        C = constants,
        Core = Core,

        bindModuleRequestRefresh = bindModuleRequestRefresh,
        bindModuleToggleHide = bindModuleToggleHide,
        makeModuleFrameGetter = makeModuleFrameGetter,

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
        GetItemIndex = getCurrentItemIndex,
    }
end

-- =========== Raid Helpers Module  =========== --
-- [MIGRATED] See Features/Raid.lua

-- =========== Chat Output Helpers  =========== --
-- [MIGRATED] See Features/Chat.lua

-- =========== Minimap Button Module  =========== --
-- [MIGRATED] See Features/Minimap.lua

-- =========== Rolls Helpers Module  =========== --
-- [MIGRATED] See Features/Rolls.lua

-- =========== Loot Helpers Module  =========== --
-- [MIGRATED] See Features/Loot.lua

-- =========== Master Looter Frame Module  =========== --
-- [MIGRATED] See Features/Master.lua

-- =========== Loot Counter Module  =========== --
-- [MIGRATED] See Features/LootCounter.lua

-- =========== Reserves Module  =========== --
-- [MIGRATED] See Features/Reserves.lua

-- =========== Reserve Import Window Module  =========== --
-- [MIGRATED] See Features/ReservesImport.lua

-- =========== Configuration Frame Module  =========== --
-- [MIGRATED] See Features/Config.lua

-- =========== Warnings Frame Module  =========== --
-- [MIGRATED] See Features/Warnings.lua

-- =========== MS Changes Module  =========== --
-- [MIGRATED] See Features/Changes.lua

-- =========== LFM Spam Module  =========== --
-- [MIGRATED] See Features/Spammer.lua

-- =========== Logger Frame =========== --
-- [MIGRATED] See Features/Logger.lua

-- =========== Slash Commands  =========== --
-- [MIGRATED] See Features/SlashEvents.lua

-- =========== Main Event Handlers  =========== --
-- [MIGRATED] See Features/SlashEvents.lua
