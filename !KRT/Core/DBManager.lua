-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

addon.DBManager = addon.DBManager or {}
local DBManager = addon.DBManager

-- ----- Internal state ----- --
DBManager.SavedVariables = DBManager.SavedVariables or {}
local SavedVariablesManager = DBManager.SavedVariables
DBManager.Default = SavedVariablesManager

-- ----- Private helpers ----- --
local function getAddonDbStore(storeKey)
    local db = addon.DB
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
