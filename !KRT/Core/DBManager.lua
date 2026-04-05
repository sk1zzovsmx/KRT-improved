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
function DBManager.CreateManager(stores)
    stores = stores or {}

    local manager = {}
    local state = {
        raidStore = stores.raidStore,
        raidQueries = stores.raidQueries,
        raidMigrations = stores.raidMigrations,
        raidValidator = stores.raidValidator,
        syncer = stores.syncer,
        charStore = stores.charStore,
        configStore = stores.configStore,
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

    function manager:GetSyncer()
        return state.syncer
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

    function manager:SetSyncer(store)
        state.syncer = store
        return state.syncer
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

function SavedVariablesManager:GetCharStore()
    return nil
end

function SavedVariablesManager:GetConfigStore()
    return nil
end

function DBManager.GetDefaultManager()
    return SavedVariablesManager
end
