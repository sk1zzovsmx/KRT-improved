local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function findLastPublicFunction(source, moduleName)
    local lastStart = nil
    local pattern = "function%s+" .. moduleName:gsub("([^%w])", "%%%1") .. "%.[%w_]+%s*%("
    local startIndex = 1
    while true do
        local found = source:find(pattern, startIndex)
        if not found then
            break
        end
        lastStart = found
        startIndex = found + 1
    end
    return lastStart
end

local expectedModules = {
    {
        name = "Modules/C",
        path = "!KRT/Modules/C.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Timer",
        path = "!KRT/Modules/Timer.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Events",
        path = "!KRT/Modules/Events.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Colors",
        path = "!KRT/Modules/Colors.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Strings",
        path = "!KRT/Modules/Strings.lua",
        deps = { "Init", "Modules/Colors" },
    },
    {
        name = "Modules/Item",
        path = "!KRT/Modules/Item.lua",
        deps = { "Init", "Modules/Timer", "Modules/Strings" },
    },
    {
        name = "Modules/LootSourcesData",
        path = "!KRT/Modules/LootSourcesData.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/LootSources",
        path = "!KRT/Modules/LootSources.lua",
        deps = { "Init", "Modules/Strings", "Modules/LootSourcesData" },
    },
    {
        name = "Modules/IgnoredItems",
        path = "!KRT/Modules/IgnoredItems.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/IgnoredMobs",
        path = "!KRT/Modules/IgnoredMobs.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Comms",
        path = "!KRT/Modules/Comms.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Time",
        path = "!KRT/Modules/Time.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Base64",
        path = "!KRT/Modules/Base64.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Sort",
        path = "!KRT/Modules/Sort.lua",
        deps = { "Init" },
    },
    {
        name = "Modules/Features",
        path = "!KRT/Modules/Features.lua",
        deps = { "Init" },
    },
}

local registrySource = read("!KRT/Modules/ModuleRegistry.lua")
assertContains(registrySource, "ModuleRegistryPendingRegistrations", "ModuleRegistry must consume queued pre-registry module registrations")
assertContains(registrySource, "ModuleRegistry.AddModule(entry.name, { deps = entry.deps })", "ModuleRegistry must register pending entries with their declared deps")
assertContains(registrySource, "if entry.loaded == true then", "ModuleRegistry must only mark pending entries loaded when requested")
assertContains(registrySource, "ModuleRegistry.SetLoaded(entry.name)", "ModuleRegistry must mark loaded pending entries")

for i = 1, #expectedModules do
    local expected = expectedModules[i]
    local source = read(expected.path)
    local metadataBlockStart = source:find('local name = "' .. expected.name .. '"', 1, true)
    local moduleTableName = expected.name:match("Modules/(.+)$")
    local lastPublicFunction = moduleTableName and findLastPublicFunction(source, moduleTableName)

    assertContains(source, 'local name = "' .. expected.name .. '"', expected.path .. " must declare module name")
    if lastPublicFunction then
        assert(lastPublicFunction < metadataBlockStart, expected.path .. " registry metadata must appear after its last public function definition")
    end
    assertContains(source, "ModuleRegistryPendingRegistrations", expected.path .. " must queue before registry load")
    assertContains(source, "loaded = true", expected.path .. " must mark file-load registration entries loaded")
    assertContains(source, "registry.AddModule(name, { deps = deps })", expected.path .. " must register directly when registry exists")
    assertContains(source, "registry.SetLoaded(name)", expected.path .. " must mark directly when registry exists")
    for depIndex = 1, #expected.deps do
        assertContains(source, '"' .. expected.deps[depIndex] .. '"', expected.path .. " must declare required deps")
    end
end

local pending = {}
for i = 1, #expectedModules do
    local expected = expectedModules[i]
    pending[i] = {
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
assert(#addon.ModuleRegistryPendingRegistrations == 0, "ModuleRegistry must clear consumed pending registrations")

local modules = registry.GetModules()
assert(modules[1].Name == "Init", "Init pending load marker must remain first")
for i = 1, #expectedModules do
    local expected = expectedModules[i]
    local record = modules[i + 1]
    assert(record.Name == expected.name, expected.name .. " must preserve pending registration order")
    assert(record.Loaded == true, expected.name .. " must be marked loaded")
    assert(#record.Deps == #expected.deps, expected.name .. " dependency count must match")
    for depIndex = 1, #expected.deps do
        assert(record.Deps[depIndex] == expected.deps[depIndex], expected.name .. " dependency graph must match")
    end
end
assert(modules[#expectedModules + 2].Name == "Modules/ModuleRegistry", "ModuleRegistry must self-register after consuming pre-registry utility modules")

local itemStatus = registry.GetStatus("Modules/Item")
local timerStatus = registry.GetStatus("Modules/Timer")
local stringsStatus = registry.GetStatus("Modules/Strings")
local colorsStatus = registry.GetStatus("Modules/Colors")
assert(colorsStatus.LoadOrder < stringsStatus.LoadOrder, "Modules/Colors must load before Modules/Strings")
assert(timerStatus.LoadOrder < itemStatus.LoadOrder, "Modules/Timer must load before Modules/Item")
assert(stringsStatus.LoadOrder < itemStatus.LoadOrder, "Modules/Strings must load before Modules/Item")

local lootSourcesStatus = registry.GetStatus("Modules/LootSources")
local lootSourcesDataStatus = registry.GetStatus("Modules/LootSourcesData")
assert(stringsStatus.LoadOrder < lootSourcesStatus.LoadOrder, "Modules/Strings must load before Modules/LootSources")
assert(lootSourcesDataStatus.LoadOrder < lootSourcesStatus.LoadOrder, "Modules/LootSourcesData must load before Modules/LootSources")

local ok, issues = registry.GetLoadOrderStatus()
assert(ok == true, "pre-registry utility module sequence must validate in TOC order")
assert(issues == nil, "valid pre-registry utility module sequence must not report dependency issues")

print("module registry pre-registry modules source contract passed")
