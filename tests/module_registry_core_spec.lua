local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstIndex = text:find(first, 1, true)
    local secondIndex = text:find(second, 1, true)
    assert(firstIndex, "missing TOC entry: " .. first)
    assert(secondIndex, "missing TOC entry: " .. second)
    assert(firstIndex < secondIndex, message or (first .. " must load before " .. second))
end

local function collectQuotedValues(text)
    local values = {}
    for value in text:gmatch('"([^"]+)"') do
        values[#values + 1] = value
    end
    return values
end

local function assertDeps(actual, expected, context)
    assert(#actual == #expected, context .. " dependency count must match")
    for i = 1, #expected do
        assert(actual[i] == expected[i], context .. " dependency " .. i .. " must be " .. expected[i])
    end
end

local function findLastExportedFunction(source, patterns)
    local lastStart = nil
    for i = 1, #patterns do
        local pattern = patterns[i]
        local startIndex = 1
        while true do
            local found = source:find(pattern, startIndex)
            if not found then
                break
            end
            if not lastStart or found > lastStart then
                lastStart = found
            end
            startIndex = found + 1
        end
    end
    return lastStart
end

local function getPreRegistryDeps(source)
    local depsText = source:match("local deps = {%s*(.-)%s*}")
    assert(depsText, "pre-registry metadata must declare local deps")
    return collectQuotedValues(depsText)
end

local function getPostRegistryDeps(source, moduleName)
    local registerStart = source:find('registry.AddModule("' .. moduleName .. '"', 1, true)
    assert(registerStart, moduleName .. " must direct-register dependency metadata")
    local depsStart = source:find("deps = {", registerStart, true)
    assert(depsStart, moduleName .. " must declare direct-register deps")
    local depsEnd = source:find("}", depsStart, true)
    assert(depsEnd, moduleName .. " must close direct-register deps")
    local depsText = source:sub(depsStart, depsEnd)
    return collectQuotedValues(depsText)
end

local preRegistryModules = {
    {
        name = "Core/DB",
        path = "!KRT/Core/DB.lua",
        toc = "Core\\DB.lua",
        deps = { "Init" },
        exports = {
            "function%s+DB%.[%w_]+%s*%(",
            "function%s+Core%.[%w_]+%s*%(",
        },
    },
    {
        name = "Core/Options",
        path = "!KRT/Core/Options.lua",
        toc = "Core\\Options.lua",
        deps = { "Init" },
        exports = {
            "function%s+Options%.[%w_]+%s*%(",
            "function%s+namespaceMt:[%w_]+%s*%(",
        },
    },
    {
        name = "Core/DBSchema",
        path = "!KRT/Core/DBSchema.lua",
        toc = "Core\\DBSchema.lua",
        deps = { "Init" },
        exports = {
            "function%s+Core%.[%w_]+%s*%(",
        },
    },
    {
        name = "Core/DBManager",
        path = "!KRT/Core/DBManager.lua",
        toc = "Core\\DBManager.lua",
        deps = { "Init", "Core/DB" },
        exports = {
            "function%s+SavedVariablesManager:[%w_]+%s*%(",
            "function%s+DBManager%.[%w_]+%s*%(",
        },
    },
}

local preRegistryUtilityModules = {
    { name = "Modules/C", deps = { "Init" } },
    { name = "Modules/Timer", deps = { "Init" } },
    { name = "Modules/Events", deps = { "Init" } },
    { name = "Modules/Colors", deps = { "Init" } },
    { name = "Modules/Strings", deps = { "Init", "Modules/Colors" } },
    { name = "Modules/Item", deps = { "Init", "Modules/Timer", "Modules/Strings" } },
    { name = "Modules/LootSourcesData", deps = { "Init" } },
    { name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/LootSourcesData" } },
    { name = "Modules/IgnoredItems", deps = { "Init" } },
    { name = "Modules/Dataset/IgnoredMobs", deps = { "Init" } },
    { name = "Modules/Comms", deps = { "Init" } },
    { name = "Modules/Time", deps = { "Init" } },
    { name = "Modules/Base64", deps = { "Init" } },
    { name = "Modules/Sort", deps = { "Init" } },
    { name = "Modules/Features", deps = { "Init" } },
}

local directRegistryModules = {
    { name = "Modules/UI/Facade", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Effects", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Visuals", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Frames", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/ListController", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Visuals" } },
    { name = "Modules/UI/MultiSelect", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/Bus", deps = { "Init", "Modules/ModuleRegistry" } },
}

local postRegistryCoreModules = {
    {
        name = "Core/DBRaidMigrations",
        path = "!KRT/Core/DBRaidMigrations.lua",
        toc = "Core\\DBRaidMigrations.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Core/DB", "Core/DBSchema", "Modules/Strings" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Core/DBRaidStore",
        path = "!KRT/Core/DBRaidStore.lua",
        toc = "Core\\DBRaidStore.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Core/DB", "Core/DBSchema", "Core/DBRaidMigrations", "Modules/Time", "Modules/Strings" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Core/DBRaidQueries",
        path = "!KRT/Core/DBRaidQueries.lua",
        toc = "Core\\DBRaidQueries.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Core/DB", "Core/DBRaidStore", "Modules/Sort" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Core/DBRaidValidator",
        path = "!KRT/Core/DBRaidValidator.lua",
        toc = "Core\\DBRaidValidator.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Core/DB", "Core/DBSchema", "Core/DBRaidMigrations", "Core/DBRaidStore", "Modules/Dataset/IgnoredMobs" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Core/DBSyncer",
        path = "!KRT/Core/DBSyncer.lua",
        toc = "Core\\DBSyncer.lua",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Core/DB",
            "Core/DBSchema",
            "Core/DBRaidStore",
            "Core/DBRaidQueries",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Time",
            "Modules/Comms",
        },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
}

local toc = read("!KRT/!KRT.toc")
assertBefore(toc, "Init.lua", "Core\\DB.lua")
assertBefore(toc, "Core\\DB.lua", "Core\\DBManager.lua")
assertBefore(toc, "Core\\DBManager.lua", "Modules\\ModuleRegistry.lua")
assertBefore(toc, "Modules\\ModuleRegistry.lua", "Core\\DBRaidMigrations.lua")

for i = 1, #preRegistryModules do
    local expected = preRegistryModules[i]
    local source = read(expected.path)
    local metadataStart = source:find('local name = "' .. expected.name .. '"', 1, true)
    local lastPublicFunction = findLastExportedFunction(source, expected.exports)

    assertContains(source, 'local name = "' .. expected.name .. '"', expected.path .. " must declare module name")
    assertContains(source, "local deps =", expected.path .. " must declare module deps")
    assert(lastPublicFunction, expected.path .. " must expose public functions before registry metadata")
    assert(lastPublicFunction < metadataStart, expected.path .. " registry metadata must appear after its last exported public function definition")
    assertContains(source, "ModuleRegistryPendingRegistrations", expected.path .. " must queue before registry load")
    assertContains(source, "loaded = true", expected.path .. " must mark pending entries loaded")
    assertContains(source, "registry.AddModule(name, { deps = deps })", expected.path .. " must register directly when registry exists")
    assertContains(source, "registry.SetLoaded(name)", expected.path .. " must mark directly when registry exists")
    assertDeps(getPreRegistryDeps(source), expected.deps, expected.name)
end

local coreDbSource = read("!KRT/Core/DB.lua")
local coreDbDeps = getPreRegistryDeps(coreDbSource)
assertDeps(coreDbDeps, { "Init" }, "Core/DB")
for i = 1, #coreDbDeps do
    assert(coreDbDeps[i] ~= "Core/DBManager", "Core/DB must not depend on Core/DBManager")
end

local dbManagerSource = read("!KRT/Core/DBManager.lua")
assertDeps(getPreRegistryDeps(dbManagerSource), { "Init", "Core/DB" }, "Core/DBManager")

for i = 1, #postRegistryCoreModules do
    local expected = postRegistryCoreModules[i]
    local source = read(expected.path)
    local metadataStart = source:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local lastPublicFunction = findLastExportedFunction(source, expected.exports)

    assertContains(source, "local registry = addon.ModuleRegistry", expected.path .. " must use direct registry lookup")
    assertContains(source, 'registry.AddModule("' .. expected.name .. '"', expected.path .. " must direct-register module metadata")
    assertContains(source, 'registry.SetLoaded("' .. expected.name .. '")', expected.path .. " must mark direct registry module loaded")
    assertNotContains(source, "ModuleRegistryPendingRegistrations", expected.path .. " must not use pending fallback after ModuleRegistry loads")
    assert(lastPublicFunction, expected.path .. " must expose public functions before registry metadata")
    assert(lastPublicFunction < metadataStart, expected.path .. " registry metadata must appear after its last exported public function definition")
    assertDeps(getPostRegistryDeps(source, expected.name), expected.deps, expected.name)
end

local syncerDeps = getPostRegistryDeps(read("!KRT/Core/DBSyncer.lua"), "Core/DBSyncer")
local syncerHasBus = false
local syncerHasComms = false
for i = 1, #syncerDeps do
    assert(syncerDeps[i]:match("^Services/") == nil, "Core/DBSyncer must not declare Services dependencies")
    if syncerDeps[i] == "Modules/Bus" then
        syncerHasBus = true
    elseif syncerDeps[i] == "Modules/Comms" then
        syncerHasComms = true
    end
end
assert(syncerHasBus, "Core/DBSyncer must depend on Modules/Bus")
assert(syncerHasComms, "Core/DBSyncer must depend on Modules/Comms")

local pending = {}
for i = 1, #preRegistryModules do
    local expected = preRegistryModules[i]
    pending[#pending + 1] = {
        name = expected.name,
        deps = expected.deps,
        loaded = true,
    }
end
for i = 1, #preRegistryUtilityModules do
    local expected = preRegistryUtilityModules[i]
    pending[#pending + 1] = {
        name = expected.name,
        deps = expected.deps,
        loaded = true,
    }
end

local addon = {
    Core = {
        GetFeatureShared = function()
            return {}
        end,
    },
    ModuleRegistryPendingLoads = { "Init" },
    ModuleRegistryPendingRegistrations = pending,
}

local chunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
chunk("!KRT", addon)

local registry = addon.ModuleRegistry
assert(#addon.ModuleRegistryPendingRegistrations == 0, "ModuleRegistry must clear consumed pending core registrations")

for i = 1, #directRegistryModules do
    local expected = directRegistryModules[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

for i = 1, #postRegistryCoreModules do
    local expected = postRegistryCoreModules[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

local ok, issues = registry.GetLoadOrderStatus()
if not ok then
    local issue = issues and issues[1] or {}
    error("core registry load order must validate; first issue=" .. tostring(issue.module) .. " -> " .. tostring(issue.dependency) .. " (" .. tostring(issue.reason) .. ")")
end
assert(issues == nil, "valid core registry sequence must not report dependency issues")

for i = 1, #preRegistryModules do
    local expected = preRegistryModules[i]
    local status = registry.GetStatus(expected.name)
    assert(status and status.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(status.Deps, expected.deps, expected.name)
end
for i = 1, #postRegistryCoreModules do
    local expected = postRegistryCoreModules[i]
    local status = registry.GetStatus(expected.name)
    assert(status and status.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(status.Deps, expected.deps, expected.name)
end

print("module registry core source contract passed")
