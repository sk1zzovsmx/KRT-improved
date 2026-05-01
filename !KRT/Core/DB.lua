-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core
local Diag = feature.Diag

assert(type(addon.DB) == "table", "KRT DB bootstrap missing addon.DB")
local DB = addon.DB

-- ----- Internal state ----- --
DB._manager = DB._manager or nil
local missingRaidStoreWarned = {}

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

local function warnMissingRaidStoreOnce(warnKey, template, fallbackFmt, arg1, arg2)
    if missingRaidStoreWarned[warnKey] then
        return
    end

    missingRaidStoreWarned[warnKey] = true
    if type(template) == "string" then
        addon:warn(template:format(arg1, arg2))
    else
        addon:warn(fallbackFmt, arg1, arg2)
    end
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

function Core.GetRaidStore()
    return getManagerStore("GetRaidStore")
end

function Core.GetRaidStoreOrNil(contextTag, requiredMethods)
    local raidStore = Core.GetRaidStore()
    local ctx = tostring(contextTag or "?")

    if type(raidStore) ~= "table" then
        local warnKey = "store:" .. ctx
        local template = Diag.W and Diag.W.LogRaidStoreUnavailable
        warnMissingRaidStoreOnce(warnKey, template, "[Core] RaidStore unavailable (context=%s)", ctx)
        return nil
    end

    if type(requiredMethods) == "table" then
        for i = 1, #requiredMethods do
            local method = requiredMethods[i]
            if type(method) == "string" and method ~= "" and type(raidStore[method]) ~= "function" then
                local warnKey = "method:" .. ctx .. ":" .. method
                local template = Diag.W and Diag.W.LogRaidStoreMethodMissing
                warnMissingRaidStoreOnce(warnKey, template, "[Core] RaidStore missing method %s (context=%s)", method, ctx)
                return nil
            end
        end
    end

    return raidStore
end

function Core.GetRaidQueries()
    return getManagerStore("GetRaidQueries")
end

function Core.GetRaidMigrations()
    return getManagerStore("GetRaidMigrations")
end

function Core.GetRaidValidator()
    return getManagerStore("GetRaidValidator")
end

function Core.GetSyncer()
    return getManagerStore("GetSyncer")
end

function Core.GetDB()
    return DB
end
