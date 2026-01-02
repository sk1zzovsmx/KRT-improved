--[[
    KRT_CoreTemplate.lua
    - Canonical core bootstrap (WotLK 3.3.5a • Lua 5.1).
    - Adapt to match existing KRT.lua patterns (monolithic addon).
]]

local addonName, addon = ...
addon = addon or {}
addon.name = addon.name or addonName

_G["KRT"] = addon

---------------------------------------------------------------------------
-- SavedVariables init (defaults + migrations)
---------------------------------------------------------------------------
local function InitSavedVariables()
    KRT_Options = KRT_Options or {}
    KRT_Debug = KRT_Debug or {}

    KRT_Options.schemaVersion = KRT_Options.schemaVersion or 1
    KRT_Options.migrations = KRT_Options.migrations or {}

    -- ApplyDefaults(KRT_Options, defaults) -- see KRT_SVTemplate.lua
    -- RunMigrations(KRT_Options)           -- see KRT_SVTemplate.lua
end

---------------------------------------------------------------------------
-- Core init (modules, UI, slash)
---------------------------------------------------------------------------
local function InitModules()
    -- Example:
    -- addon.Raid:Init()
    -- addon.Rolls:Init()
end

local function InitUI()
    -- Example:
    -- addon.Config:Init()
    -- addon.Master:Init()
end

---------------------------------------------------------------------------
-- Single event frame (prefer one place to register WoW events)
---------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame")

mainFrame:SetScript("OnEvent", function(_, event, ...)
    local fn = addon[event]
    if type(fn) == "function" then
        fn(addon, ...)
    end
end)

mainFrame:RegisterEvent("ADDON_LOADED")

function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    mainFrame:UnregisterEvent("ADDON_LOADED")

    InitSavedVariables()
    InitModules()
    InitUI()
end
