-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

addon.DBManager = addon.DBManager or {}
local DBManager = addon.DBManager

DBManager.SavedVariables = DBManager.SavedVariables or {}
local SavedVariablesManager = DBManager.SavedVariables
DBManager.Default = SavedVariablesManager

function DBManager.CreateManager(stores)
    stores = stores or {}

    local manager = {}
    local state = {
        raidStore = stores.raidStore or stores.RaidStore or nil,
        raidQueries = stores.raidQueries or stores.RaidQueries or nil,
        raidMigrations = stores.raidMigrations or stores.RaidMigrations or nil,
        raidValidator = stores.raidValidator or stores.RaidValidator or nil,
        charStore = stores.charStore or stores.CharStore or nil,
        configStore = stores.configStore or stores.ConfigStore or nil,
    }

    function manager:GetRaidStore()
        return state.raidStore
    end

    function manager:GetRaidQueries()
        return state.raidQueries
    end

    function manager:GetRaidMigrations()
        return state.raidMigrations
    end

    function manager:GetRaidValidator()
        return state.raidValidator
    end

    function manager:GetCharStore()
        return state.charStore
    end

    function manager:GetConfigStore()
        return state.configStore
    end

    function manager:SetRaidStore(store)
        state.raidStore = store
        return state.raidStore
    end

    function manager:SetRaidQueries(store)
        state.raidQueries = store
        return state.raidQueries
    end

    function manager:SetRaidMigrations(store)
        state.raidMigrations = store
        return state.raidMigrations
    end

    function manager:SetRaidValidator(store)
        state.raidValidator = store
        return state.raidValidator
    end

    function manager:SetCharStore(store)
        state.charStore = store
        return state.charStore
    end

    function manager:SetConfigStore(store)
        state.configStore = store
        return state.configStore
    end

    return manager
end

function SavedVariablesManager:GetRaidStore()
    local db = addon.DB
    return db and db.RaidStore or nil
end

function SavedVariablesManager:GetRaidQueries()
    local db = addon.DB
    return db and db.RaidQueries or nil
end

function SavedVariablesManager:GetRaidMigrations()
    local db = addon.DB
    return db and db.RaidMigrations or nil
end

function SavedVariablesManager:GetRaidValidator()
    local db = addon.DB
    return db and db.RaidValidator or nil
end

function SavedVariablesManager:GetCharStore()
    return nil
end

function SavedVariablesManager:GetConfigStore()
    return nil
end

function DBManager.GetDefaultManager()
    return SavedVariablesManager
end
