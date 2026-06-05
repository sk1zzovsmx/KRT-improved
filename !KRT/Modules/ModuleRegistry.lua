-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, pairs = type, pairs

addon.ModuleRegistry = addon.ModuleRegistry or feature.ModuleRegistry or {}
local ModuleRegistry = addon.ModuleRegistry

-- ----- Internal state ----- --
local modules = {}
local modulesByName = {}
local registrationOrder = 0
local loadOrder = 0

-- ----- Private helpers ----- --
local function copyDeps(deps)
    local out = {}
    if type(deps) ~= "table" then
        return out
    end

    for i = 1, #deps do
        out[i] = deps[i]
    end
    return out
end

local function ensureRecord(name)
    local record = modulesByName[name]
    if record then
        return record
    end

    registrationOrder = registrationOrder + 1
    record = {
        Name = name,
        Deps = {},
        Loaded = false,
        RegisteredOrder = registrationOrder,
    }
    modules[#modules + 1] = record
    modulesByName[name] = record
    return record
end

local function copyRecord(record)
    if not record then
        return nil
    end

    return {
        Name = record.Name,
        Deps = copyDeps(record.Deps),
        Loaded = record.Loaded == true,
        LoadOrder = record.LoadOrder,
        RegisteredOrder = record.RegisteredOrder,
    }
end

local function clearTable(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function addIssue(issues, moduleName, dependency, reason)
    issues[#issues + 1] = {
        module = moduleName,
        dependency = dependency,
        reason = reason,
    }
end

-- ----- Public methods ----- --
function ModuleRegistry.AddModule(name, cfg)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local record = ensureRecord(name)
    record.Deps = copyDeps(cfg and cfg.deps)
    return copyRecord(record)
end

function ModuleRegistry.SetLoaded(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local record = ensureRecord(name)
    record.Loaded = true
    if not record.LoadOrder then
        loadOrder = loadOrder + 1
        record.LoadOrder = loadOrder
    end
    return copyRecord(record)
end

function ModuleRegistry.GetModules(out)
    out = out or {}
    clearTable(out)

    for i = 1, #modules do
        out[i] = copyRecord(modules[i])
    end
    return out
end

function ModuleRegistry.GetStatus(name)
    return copyRecord(modulesByName[name])
end

function ModuleRegistry.GetLoadOrderStatus()
    local issues = {}

    for i = 1, #modules do
        local record = modules[i]
        for depIndex = 1, #record.Deps do
            local dependency = record.Deps[depIndex]
            local depRecord = modulesByName[dependency]
            if not depRecord or not depRecord.Loaded then
                addIssue(issues, record.Name, dependency, "missing")
            elseif record.LoadOrder and depRecord.LoadOrder and depRecord.LoadOrder > record.LoadOrder then
                addIssue(issues, record.Name, dependency, "out_of_order")
            end
        end
    end

    if #issues > 0 then
        return false, issues
    end
    return true, nil
end

local pendingLoads = addon.ModuleRegistryPendingLoads
if type(pendingLoads) == "table" then
    for i = 1, #pendingLoads do
        ModuleRegistry.SetLoaded(pendingLoads[i])
        pendingLoads[i] = nil
    end
end

local pendingRegistrations = addon.ModuleRegistryPendingRegistrations
if type(pendingRegistrations) == "table" then
    for i = 1, #pendingRegistrations do
        local entry = pendingRegistrations[i]
        if type(entry) == "table" then
            ModuleRegistry.AddModule(entry.name, { deps = entry.deps })
            if entry.loaded == true then
                ModuleRegistry.SetLoaded(entry.name)
            end
        end
        pendingRegistrations[i] = nil
    end
end

ModuleRegistry.AddModule("Modules/ModuleRegistry", { deps = { "Init" } })
ModuleRegistry.SetLoaded("Modules/ModuleRegistry")
