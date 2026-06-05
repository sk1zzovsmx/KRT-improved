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

local expectedModules = {
    {
        name = "Modules/UI/Facade",
        path = "!KRT/Modules/UI/Facade.lua",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Modules/UI/Effects",
        path = "!KRT/Modules/UI/Effects.lua",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Modules/UI/Visuals",
        path = "!KRT/Modules/UI/Visuals.lua",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Modules/UI/Frames",
        path = "!KRT/Modules/UI/Frames.lua",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Modules/UI/ListController",
        path = "!KRT/Modules/UI/ListController.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Visuals" },
    },
    {
        name = "Modules/UI/MultiSelect",
        path = "!KRT/Modules/UI/MultiSelect.lua",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Modules/UI/OptionsLayout",
        path = "!KRT/Modules/UI/OptionsLayout.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Frames" },
    },
    {
        name = "Modules/Bus",
        path = "!KRT/Modules/Bus.lua",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
}

local registrySource = read("!KRT/Modules/ModuleRegistry.lua")
local toc = read("!KRT/!KRT.toc")
assertContains(
    registrySource,
    'ModuleRegistry.AddModule("Modules/ModuleRegistry", { deps = { "Init" } })',
    "ModuleRegistry must register itself after consuming pending bootstrap loads"
)
assertContains(registrySource, 'ModuleRegistry.SetLoaded("Modules/ModuleRegistry")', "ModuleRegistry must mark itself loaded after consuming pending bootstrap loads")
assertBefore(toc, "Modules\\ModuleRegistry.lua", "Modules\\Bus.lua")
assertBefore(toc, "Modules\\Bus.lua", "Database\\DBRaidMigrations.lua")
assertBefore(toc, "Modules\\Bus.lua", "Database\\DBRaidStore.lua")
assertBefore(toc, "Modules\\Bus.lua", "Database\\DBRaidQueries.lua")
assertBefore(toc, "Modules\\Bus.lua", "Database\\DBRaidValidator.lua")

for i = 1, #expectedModules do
    local expected = expectedModules[i]
    local source = read(expected.path)
    assertContains(source, 'registry.AddModule("' .. expected.name .. '"', expected.path .. " must register required ModuleRegistry metadata")
    for depIndex = 1, #expected.deps do
        assertContains(source, '"' .. expected.deps[depIndex] .. '"', expected.path .. " must declare required deps")
    end
    assertContains(source, 'registry.SetLoaded("' .. expected.name .. '")', expected.path .. " must mark its registry module loaded")
end

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
local registryStatus = registry.GetStatus("Modules/ModuleRegistry")
assert(registryStatus and registryStatus.Loaded == true, "ModuleRegistry must be loaded in runtime registry")
assert(#registryStatus.Deps == 1 and registryStatus.Deps[1] == "Init", "ModuleRegistry must depend on Init")

for i = 1, #expectedModules do
    local expected = expectedModules[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

local ok, issues = registry.GetLoadOrderStatus()
assert(ok == true, "declared UI module sequence must validate in TOC order")
assert(issues == nil, "valid UI module sequence must not report dependency issues")

for i = 1, #expectedModules do
    local expected = expectedModules[i]
    local status = registry.GetStatus(expected.name)
    assert(status and status.Loaded == true, expected.name .. " must be loaded in registry")
    assert(#status.Deps == #expected.deps, expected.name .. " dependency count must match")
    for depIndex = 1, #expected.deps do
        assert(status.Deps[depIndex] == expected.deps[depIndex], expected.name .. " dependency graph must match")
    end
end

print("module registry UI source contract passed")
