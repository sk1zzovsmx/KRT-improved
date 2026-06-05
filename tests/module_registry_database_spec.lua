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
        name = "Database/DB",
        path = "!KRT/Database/DB.lua",
        toc = "Database\\DB.lua",
        deps = { "Init" },
        exports = {
            "function%s+DB%.[%w_]+%s*%(",
            "function%s+Database%.[%w_]+%s*%(",
        },
    },
    {
        name = "Database/DBOptions",
        path = "!KRT/Database/DBOptions.lua",
        toc = "Database\\DBOptions.lua",
        deps = { "Init" },
        exports = {
            "function%s+Options%.[%w_]+%s*%(",
            "function%s+namespaceMt:[%w_]+%s*%(",
        },
    },
    {
        name = "Database/DBSchema",
        path = "!KRT/Database/DBSchema.lua",
        toc = "Database\\DBSchema.lua",
        deps = { "Init" },
        exports = {
            "function%s+Database%.[%w_]+%s*%(",
        },
    },
    {
        name = "Database/DBManager",
        path = "!KRT/Database/DBManager.lua",
        toc = "Database\\DBManager.lua",
        deps = { "Init", "Database/DB" },
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
    { name = "Modules/UI/Visuals", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Effects" } },
    { name = "Modules/UI/Frames", deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings" } },
    { name = "Modules/UI/ListController", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Frames", "Modules/UI/Visuals" } },
    { name = "Modules/UI/MultiSelect", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/Bus", deps = { "Init", "Modules/ModuleRegistry" } },
}

local postRegistryCoreModules = {
    {
        name = "Database/DBRaidMigrations",
        path = "!KRT/Database/DBRaidMigrations.lua",
        toc = "Database\\DBRaidMigrations.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBSchema", "Modules/Strings" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Database/DBRaidStore",
        path = "!KRT/Database/DBRaidStore.lua",
        toc = "Database\\DBRaidStore.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBSchema", "Database/DBRaidMigrations", "Modules/Time", "Modules/Strings" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Database/DBRaidQueries",
        path = "!KRT/Database/DBRaidQueries.lua",
        toc = "Database\\DBRaidQueries.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBRaidStore", "Modules/Sort" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Database/DBRaidValidator",
        path = "!KRT/Database/DBRaidValidator.lua",
        toc = "Database\\DBRaidValidator.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBSchema", "Database/DBRaidMigrations", "Database/DBRaidStore", "Modules/Dataset/IgnoredMobs" },
        exports = { "function%s+module:[%w_]+%s*%(" },
    },
    {
        name = "Database/DBSyncer",
        path = "!KRT/Database/DBSyncer.lua",
        toc = "Database\\DBSyncer.lua",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DB",
            "Database/DBSchema",
            "Database/DBRaidStore",
            "Database/DBRaidQueries",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Timer",
            "Modules/Strings",
            "Modules/Time",
            "Modules/Comms",
        },
        exports = { "function%s+module:[%w_]+%s*%(" },
        events = "-- events: handles KRTLogSync addon-message traffic; listens OptionsLoaded, ConfigpersistentSync, RaidCreate",
    },
}

local toc = read("!KRT/!KRT.toc")
assertBefore(toc, "Init.lua", "Database\\DB.lua")
assertBefore(toc, "Database\\DB.lua", "Database\\DBManager.lua")
assertBefore(toc, "Database\\DBManager.lua", "Modules\\ModuleRegistry.lua")
assertBefore(toc, "Modules\\ModuleRegistry.lua", "Database\\DBRaidMigrations.lua")

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
    assertContains(source, "Bootstrap exception: ModuleRegistry may not be loaded yet.", expected.path .. " must document its pre-registry addon.ModuleRegistry lookup")
    assertContains(source, "loaded = true", expected.path .. " must mark pending entries loaded")
    assertContains(source, "registry.AddModule(name, { deps = deps })", expected.path .. " must register directly when registry exists")
    assertContains(source, "registry.SetLoaded(name)", expected.path .. " must mark directly when registry exists")
    assertDeps(getPreRegistryDeps(source), expected.deps, expected.name)
end

local preRegistryDbOwnerTables = {
    {
        path = "!KRT/Database/DB.lua",
        name = "DB",
    },
    {
        path = "!KRT/Database/DBManager.lua",
        name = "DBManager",
    },
    {
        path = "!KRT/Database/DBSchema.lua",
        name = "DBSchema",
    },
    {
        path = "!KRT/Database/DBOptions.lua",
        name = "Options",
    },
}

for i = 1, #preRegistryDbOwnerTables do
    local expected = preRegistryDbOwnerTables[i]
    local source = read(expected.path)
    assertContains(source, "local " .. expected.name .. " = feature." .. expected.name, expected.path .. " must bind owner table from feature shared")
    assertNotContains(
        source,
        "local " .. expected.name .. " = feature." .. expected.name .. " or addon." .. expected.name,
        expected.path .. " must not double-bind owner table through addon root"
    )
    assertNotContains(source, "local " .. expected.name .. " = addon." .. expected.name, expected.path .. " must not bind owner table directly from addon root")
end

local coreDbSource = read("!KRT/Database/DB.lua")
local coreDbDeps = getPreRegistryDeps(coreDbSource)
assertDeps(coreDbDeps, { "Init" }, "Database/DB")
for i = 1, #coreDbDeps do
    assert(coreDbDeps[i] ~= "Database/DBManager", "Database/DB must not depend on Database/DBManager")
end

local dbManagerSource = read("!KRT/Database/DBManager.lua")
assertDeps(getPreRegistryDeps(dbManagerSource), { "Init", "Database/DB" }, "Database/DBManager")
assertContains(coreDbSource, "local dbManager = feature.DBManager", "Database/DB must read DBManager from feature shared")
assertNotContains(coreDbSource, "local dbManager = addon.DBManager", "Database/DB must not read DBManager directly from addon root")
assertContains(dbManagerSource, "local db = feature.DB", "Database/DBManager must read DB from feature shared")
assertNotContains(dbManagerSource, "local db = addon.DB", "Database/DBManager must not read DB directly from addon root")

local dbOptionsSource = read("!KRT/Database/DBOptions.lua")
assertContains(dbOptionsSource, "-- shared: local feature = addon.Database.GetFeatureShared()", "Database/DBOptions must document its feature shared header dependency")
assertContains(dbOptionsSource, "local Bus = feature.Bus", "Database/DBOptions must localize Bus from feature shared")
assertNotContains(dbOptionsSource, "local bus = addon.Bus", "Database/DBOptions must not read Bus directly from addon root")
assertContains(dbOptionsSource, "local eventRoot = feature.Events", "Database/DBOptions must localize Events from feature shared")
assertNotContains(dbOptionsSource, "local eventRoot = feature.Events or addon.Events", "Database/DBOptions must not double-bind Events through addon root")
assertContains(dbOptionsSource, "local coreState = feature.coreState", "Database/DBOptions must localize core state from feature shared")
assertNotContains(dbOptionsSource, "local state = addon.State", "Database/DBOptions must not read State directly from addon root")
assertNotContains(dbOptionsSource, "runtime addon.State.debugEnabled", "Database/DBOptions comments must describe coreState debug ownership")
assertContains(dbOptionsSource, "-- ----- Public methods ----- --", "Database/DBOptions must use the canonical public-method header")
assertNotContains(dbOptionsSource, "-- ----- Public API ----- --", "Database/DBOptions must not use the old public API section header")

for i = 1, #postRegistryCoreModules do
    local expected = postRegistryCoreModules[i]
    local source = read(expected.path)
    local metadataStart = source:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local lastPublicFunction = findLastExportedFunction(source, expected.exports)

    assertContains(source, "local registry = feature.ModuleRegistry", expected.path .. " must localize ModuleRegistry from feature shared")
    assertNotContains(source, "local registry = addon.ModuleRegistry", expected.path .. " must not read ModuleRegistry directly from addon root")
    assertContains(source, 'registry.AddModule("' .. expected.name .. '"', expected.path .. " must direct-register module metadata")
    assertContains(source, 'registry.SetLoaded("' .. expected.name .. '")', expected.path .. " must mark direct registry module loaded")
    assertNotContains(source, "ModuleRegistryPendingRegistrations", expected.path .. " must not use pending fallback after ModuleRegistry loads")
    if expected.events then
        assertContains(source, expected.events, expected.path .. " must document concrete event ownership in the Lua contract")
        assertNotContains(source, "-- events: document inbound/outbound events in module body", expected.path .. " must not keep the generic event placeholder")
    end
    assert(lastPublicFunction, expected.path .. " must expose public functions before registry metadata")
    assert(lastPublicFunction < metadataStart, expected.path .. " registry metadata must appear after its last exported public function definition")
    assertDeps(getPostRegistryDeps(source, expected.name), expected.deps, expected.name)
end

local postRegistryDbNamespaceFiles = {
    { path = "!KRT/Database/DBRaidMigrations.lua", namespace = "RaidMigrations" },
    { path = "!KRT/Database/DBRaidStore.lua", namespace = "RaidStore" },
    { path = "!KRT/Database/DBRaidQueries.lua", namespace = "RaidQueries" },
    { path = "!KRT/Database/DBRaidValidator.lua", namespace = "RaidValidator" },
    { path = "!KRT/Database/DBSyncer.lua", namespace = "Syncer" },
}
for i = 1, #postRegistryDbNamespaceFiles do
    local expected = postRegistryDbNamespaceFiles[i]
    local source = read(expected.path)
    assertContains(source, "local DB = feature.DB", expected.path .. " must localize DB from feature shared")
    assertContains(source, "local module = DB." .. expected.namespace, expected.path .. " must bind module through the local DB namespace")
    assertNotContains(source, "local module = addon.DB." .. expected.namespace, expected.path .. " must not bind module through addon.DB")
end

local syncerDeps = getPostRegistryDeps(read("!KRT/Database/DBSyncer.lua"), "Database/DBSyncer")
local syncerHasBus = false
local syncerHasComms = false
for i = 1, #syncerDeps do
    assert(syncerDeps[i]:match("^Services/") == nil, "Database/DBSyncer must not declare Services dependencies")
    if syncerDeps[i] == "Modules/Bus" then
        syncerHasBus = true
    elseif syncerDeps[i] == "Modules/Comms" then
        syncerHasComms = true
    end
end
assert(syncerHasBus, "Database/DBSyncer must depend on Modules/Bus")
assert(syncerHasComms, "Database/DBSyncer must depend on Modules/Comms")

local syncerSource = read("!KRT/Database/DBSyncer.lua")
assertContains(syncerSource, "local coreState = feature.coreState", "Database/DBSyncer must localize core state from feature shared")
assertContains(syncerSource, "local UnitIsGroupLeader = feature.UnitIsGroupLeader", "Database/DBSyncer must localize group leader helper from feature shared")
assertContains(syncerSource, "local UnitIsGroupAssistant = feature.UnitIsGroupAssistant", "Database/DBSyncer must localize group assistant helper from feature shared")
assertNotContains(
    syncerSource,
    "local UnitIsGroupLeader = feature.UnitIsGroupLeader or addon.UnitIsGroupLeader",
    "Database/DBSyncer must not fall back to addon root group leader helper"
)
assertNotContains(
    syncerSource,
    "local UnitIsGroupAssistant = feature.UnitIsGroupAssistant or addon.UnitIsGroupAssistant",
    "Database/DBSyncer must not fall back to addon root group assistant helper"
)
assertNotContains(
    syncerSource,
    "local UnitIsGroupLeader = addon.UnitIsGroupLeader or feature.UnitIsGroupLeader",
    "Database/DBSyncer must not prefer addon root group leader helper"
)
assertNotContains(
    syncerSource,
    "local UnitIsGroupAssistant = addon.UnitIsGroupAssistant or feature.UnitIsGroupAssistant",
    "Database/DBSyncer must not prefer addon root group assistant helper"
)
assertNotContains(syncerSource, "local leaderFn = addon.UnitIsGroupLeader", "Database/DBSyncer must use local UnitIsGroupLeader dependency")
assertNotContains(syncerSource, "local assistantFn = addon.UnitIsGroupAssistant", "Database/DBSyncer must use local UnitIsGroupAssistant dependency")
assertNotContains(syncerSource, "addon.State and addon.State.selectedRaid", "Database/DBSyncer must use local coreState for selected raid lookup")

local raidStoreSource = read("!KRT/Database/DBRaidStore.lua")
assertContains(raidStoreSource, "local coreState = feature.coreState", "Database/DBRaidStore must localize core state from feature shared")
assertNotContains(raidStoreSource, "local coreState = feature.coreState or addon.State", "Database/DBRaidStore must not fall back to addon.State for core state")
assertNotContains(raidStoreSource, "addon.State.raidStore", "Database/DBRaidStore must use local coreState for raid-store runtime cache")

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
    Database = {
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

print("module registry database source contract passed")
