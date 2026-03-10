-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core

addon.DB = addon.DB or {}
local DB = addon.DB

-- ----- Internal state ----- --
DB._manager = DB._manager or nil

-- ----- Private helpers ----- --
local function getDefaultManager()
    local dbManager = addon.DBManager
    if dbManager and type(dbManager.GetDefaultManager) == "function" then
        return dbManager.GetDefaultManager()
    end
    return nil
end

local function ensureManager()
    if DB._manager then
        return DB._manager
    end
    DB._manager = getDefaultManager()
    return DB._manager
end

local function getManagerStore(methodName)
    local manager = ensureManager()
    if not manager then
        return nil
    end

    local getter = manager[methodName]
    if type(getter) ~= "function" then
        return nil
    end

    return getter(manager)
end

-- ----- Public methods ----- --
function DB.SetManager(manager)
    if manager == nil or type(manager) == "table" then
        DB._manager = manager
        return true
    end
    return false
end

function DB.GetManager()
    return ensureManager()
end

function DB.GetRaidStore()
    return getManagerStore("GetRaidStore")
end

function Core.GetRaidStore()
    return DB.GetRaidStore()
end

function DB.GetRaidQueries()
    return getManagerStore("GetRaidQueries")
end

function Core.GetRaidQueries()
    return DB.GetRaidQueries()
end

function DB.GetRaidMigrations()
    return getManagerStore("GetRaidMigrations")
end

function Core.GetRaidMigrations()
    return DB.GetRaidMigrations()
end

function DB.GetRaidValidator()
    return getManagerStore("GetRaidValidator")
end

function Core.GetRaidValidator()
    return DB.GetRaidValidator()
end

function DB.GetSyncer()
    return getManagerStore("GetSyncer")
end

function Core.GetSyncer()
    return DB.GetSyncer()
end

function DB.GetCharStore()
    return getManagerStore("GetCharStore")
end

function DB.GetConfigStore()
    return getManagerStore("GetConfigStore")
end

function Core.GetDB()
    return DB
end
