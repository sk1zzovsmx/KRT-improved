local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstIndex = text:find(first, 1, true)
    local secondIndex = text:find(second, 1, true)
    assert(firstIndex, "missing TOC entry: " .. first)
    assert(secondIndex, "missing TOC entry: " .. second)
    assert(firstIndex < secondIndex, message or (first .. " must load before " .. second))
end

local source = read("!KRT/Modules/ModuleRegistry.lua")
local initSource = read("!KRT/Init.lua")
local toc = read("!KRT/!KRT.toc")

assertContains(source, "local addon = select(2, ...)", "ModuleRegistry must use the standard addon header")
assertContains(source, "local feature = addon.Database.GetFeatureShared()", "ModuleRegistry must use the feature shared header")
assertContains(source, "addon.ModuleRegistry", "ModuleRegistry must export addon.ModuleRegistry")
assertContains(source, "-- ----- Internal state ----- --", "ModuleRegistry must use canonical internal-state header")
assertContains(source, "-- ----- Private helpers ----- --", "ModuleRegistry must use canonical private-helper header")
assertContains(source, "-- ----- Public methods ----- --", "ModuleRegistry must use canonical public-method header")

assertContains(source, "function ModuleRegistry.AddModule", "ModuleRegistry must expose AddModule")
assertContains(source, "function ModuleRegistry.SetLoaded", "ModuleRegistry must expose SetLoaded")
assertContains(source, "function ModuleRegistry.GetLoadOrderStatus", "ModuleRegistry must expose GetLoadOrderStatus")
assertContains(source, "function ModuleRegistry.GetStatus", "ModuleRegistry must expose GetStatus")
assertContains(source, "function ModuleRegistry.GetModules", "ModuleRegistry must expose GetModules")

assertContains(initSource, "ModuleRegistry", "Init.lua must include module-registry bootstrap marker handling")
assertContains(initSource, 'SetLoaded("Init")', "Init.lua must mark Init loaded when ModuleRegistry is available")
assertContains(initSource, "ModuleRegistryPendingLoads", "Init.lua must queue Init when ModuleRegistry is not loaded yet")
assertContains(source, "ModuleRegistryPendingLoads", "ModuleRegistry must consume queued bootstrap load markers")

assertBefore(toc, "Modules\\Features.lua", "Modules\\ModuleRegistry.lua")
assertBefore(toc, "Modules\\ModuleRegistry.lua", "Modules\\UI\\Facade.lua")

local addon = {
    Database = {
        GetFeatureShared = function()
            return {}
        end,
    },
    ModuleRegistryPendingLoads = { "Init" },
}

local chunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
chunk("!KRT", addon)

local registry = addon.ModuleRegistry
assert(type(registry) == "table", "addon.ModuleRegistry must be a table")
assert(type(registry.AddModule) == "function", "AddModule must be callable")
assert(type(registry.SetLoaded) == "function", "SetLoaded must be callable")
assert(type(registry.GetLoadOrderStatus) == "function", "GetLoadOrderStatus must be callable")
assert(type(registry.GetStatus) == "function", "GetStatus must be callable")
assert(type(registry.GetModules) == "function", "GetModules must be callable")

local initStatus = registry.GetStatus("Init")
assert(initStatus and initStatus.Loaded == true, "ModuleRegistry must consume queued Init bootstrap markers")
assert(#addon.ModuleRegistryPendingLoads == 0, "ModuleRegistry must clear consumed bootstrap markers")
local registryStatus = registry.GetStatus("Modules/ModuleRegistry")
assert(registryStatus and registryStatus.Loaded == true, "ModuleRegistry must register and mark itself loaded")
assert(#registryStatus.Deps == 1 and registryStatus.Deps[1] == "Init", "ModuleRegistry must depend on Init")

registry.AddModule("Database", { deps = {} })
registry.AddModule("Feature", { deps = { "Database" } })
registry.SetLoaded("Database")
registry.SetLoaded("Feature")

local coreStatus = registry.GetStatus("Database")
local featureStatus = registry.GetStatus("Feature")
assert(coreStatus and coreStatus.Loaded == true, "SetLoaded must mark an existing module loaded")
assert(featureStatus and featureStatus.LoadOrder > coreStatus.LoadOrder, "LoadOrder must be monotonic")

coreStatus.Loaded = false
assert(registry.GetStatus("Database").Loaded == true, "GetStatus must return a copy")

local modules = registry.GetModules()
assert(#modules == 4, "GetModules must include bootstrap, registry, and registered modules")
assert(modules[1].Name == "Init", "GetModules must preserve bootstrap marker order")
assert(modules[2].Name == "Modules/ModuleRegistry", "GetModules must preserve registry self-registration order")
assert(modules[3].Name == "Database", "GetModules must preserve registration order")
assert(modules[4].Name == "Feature", "GetModules must preserve registration order")
modules[3].Loaded = false
assert(registry.GetStatus("Database").Loaded == true, "GetModules must not expose internal records")

local out = {}
assert(registry.GetModules(out) == out, "GetModules must write into and return the provided output table")
assert(#out == 4, "GetModules(out) must copy all module records")

local ok, issues = registry.GetLoadOrderStatus()
assert(ok == true, "GetLoadOrderStatus must pass when dependencies are loaded earlier")
assert(issues == nil, "GetLoadOrderStatus must return nil issues for valid order")

registry.AddModule("MissingDep", { deps = { "NotRegistered" } })
local missingOk, missingIssues = registry.GetLoadOrderStatus()
assert(missingOk == false, "GetLoadOrderStatus must fail for missing dependencies")
assert(type(missingIssues) == "table" and #missingIssues >= 1, "GetLoadOrderStatus must return issue details")
assert(missingIssues[#missingIssues].module == "MissingDep", "missing dependency issue must include module")
assert(missingIssues[#missingIssues].dependency == "NotRegistered", "missing dependency issue must include dependency")
assert(missingIssues[#missingIssues].reason == "missing", "missing dependency issue must use reason=missing")

registry.AddModule("OutOfOrderDep", { deps = { "LateDep" } })
registry.SetLoaded("OutOfOrderDep")
registry.SetLoaded("LateDep")
local orderOk, orderIssues = registry.GetLoadOrderStatus()
assert(orderOk == false, "GetLoadOrderStatus must fail for out-of-order dependencies")
assert(type(orderIssues) == "table" and #orderIssues >= 1, "GetLoadOrderStatus must return out-of-order issue details")
assert(orderIssues[#orderIssues].module == "OutOfOrderDep", "out-of-order issue must include module")
assert(orderIssues[#orderIssues].dependency == "LateDep", "out-of-order issue must include dependency")
assert(orderIssues[#orderIssues].reason == "out_of_order", "out-of-order issue must use reason=out_of_order")

registry.SetLoaded("Implicit")
local implicitStatus = registry.GetStatus("Implicit")
assert(implicitStatus and implicitStatus.Loaded == true, "SetLoaded must create missing entries")
assert(type(implicitStatus.LoadOrder) == "number", "SetLoaded-created entries must receive LoadOrder")

print("module registry source contract passed")
