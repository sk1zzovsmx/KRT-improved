-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local DBManager = feature.DBManager or {}
addon.DBManager = DBManager

-- ----- Internal state ----- --
DBManager.SavedVariables = DBManager.SavedVariables or {}
local SavedVariablesManager = DBManager.SavedVariables

-- ----- Private helpers ----- --
local function getAddonDbStore(storeKey)
    local db = feature.DB
    if type(db) ~= "table" then
        return nil
    end
    return db[storeKey]
end

-- ----- Public methods ----- --
function SavedVariablesManager:GetRaidStore()
    return getAddonDbStore("RaidStore")
end

function SavedVariablesManager:GetRaidQueries()
    return getAddonDbStore("RaidQueries")
end

function SavedVariablesManager:GetRaidMigrations()
    return getAddonDbStore("RaidMigrations")
end

function SavedVariablesManager:GetRaidValidator()
    return getAddonDbStore("RaidValidator")
end

function SavedVariablesManager:GetSyncer()
    return getAddonDbStore("Syncer")
end

function DBManager.GetDefaultManager()
    return SavedVariablesManager
end

do
    local name = "Database/DBManager"
    local deps = { "Init", "Database/DB" }
    -- Bootstrap exception: ModuleRegistry may not be loaded yet.
    local registry = addon.ModuleRegistry
    if registry then
        registry.AddModule(name, { deps = deps })
        registry.SetLoaded(name)
    else
        addon.ModuleRegistryPendingRegistrations = addon.ModuleRegistryPendingRegistrations or {}
        local pending = addon.ModuleRegistryPendingRegistrations
        pending[#pending + 1] = { name = name, deps = deps, loaded = true }
    end
end
