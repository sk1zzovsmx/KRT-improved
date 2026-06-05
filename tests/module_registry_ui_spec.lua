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
        deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Effects" },
    },
    {
        name = "Modules/UI/Frames",
        path = "!KRT/Modules/UI/Frames.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings" },
    },
    {
        name = "Modules/UI/ListController",
        path = "!KRT/Modules/UI/ListController.lua",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Frames", "Modules/UI/Visuals" },
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
    assertContains(source, "local registry = feature.ModuleRegistry", expected.path .. " must localize ModuleRegistry from feature shared")
    assert(not source:find("local registry = addon.ModuleRegistry", 1, true), expected.path .. " must not read ModuleRegistry directly from addon root")
    for depIndex = 1, #expected.deps do
        assertContains(source, '"' .. expected.deps[depIndex] .. '"', expected.path .. " must declare required deps")
    end
    assertContains(source, 'registry.SetLoaded("' .. expected.name .. '")', expected.path .. " must mark its registry module loaded")
end

local featureOwnedUiModuleTables = {
    {
        path = "!KRT/Modules/UI/Facade.lua",
        name = "UI",
    },
    {
        path = "!KRT/Modules/UI/Effects.lua",
        name = "UIEffects",
    },
    {
        path = "!KRT/Modules/UI/Visuals.lua",
        name = "UIPrimitives",
    },
    {
        path = "!KRT/Modules/UI/Visuals.lua",
        name = "UIRowVisuals",
    },
    {
        path = "!KRT/Modules/UI/Frames.lua",
        name = "Frames",
    },
    {
        path = "!KRT/Modules/UI/Frames.lua",
        name = "UIScaffold",
    },
    {
        path = "!KRT/Modules/UI/ListController.lua",
        name = "ListController",
    },
    {
        path = "!KRT/Modules/UI/MultiSelect.lua",
        name = "MultiSelect",
    },
    {
        path = "!KRT/Modules/UI/OptionsLayout.lua",
        name = "OptionsLayout",
    },
}

for i = 1, #featureOwnedUiModuleTables do
    local expected = featureOwnedUiModuleTables[i]
    local source = read(expected.path)
    assertContains(source, "local " .. expected.name .. " = feature." .. expected.name .. " or {}", expected.path .. " must bind owner table from feature shared")
    assert(not source:find("local " .. expected.name .. " = addon." .. expected.name, 1, true), expected.path .. " must not bind owner table directly from addon root")
end

local facadeSource = read("!KRT/Modules/UI/Facade.lua")
assertContains(facadeSource, "local Features = feature.Features", "Facade must localize Features from feature shared")
assert(not facadeSource:find("local Features = addon.Features", 1, true), "Facade must not read Features from addon root")

local listControllerSource = read("!KRT/Modules/UI/ListController.lua")
assertContains(listControllerSource, "local UIRowVisuals = feature.UIRowVisuals", "ListController must localize row visuals from feature shared")
assertContains(listControllerSource, "local UIPrimitives = feature.UIPrimitives", "ListController must localize UI primitives from feature shared")
assertContains(listControllerSource, "local Frames = feature.Frames", "ListController must localize Frames from feature shared")
assert(not listControllerSource:find("addon.UIRowVisuals", 1, true), "ListController must not read row visuals from addon root")
assert(not listControllerSource:find("addon.UIPrimitives", 1, true), "ListController must not read UI primitives from addon root")
assert(not listControllerSource:find("addon.Frames", 1, true), "ListController must not read Frames from addon root")

local framesSource = read("!KRT/Modules/UI/Frames.lua")
assertContains(framesSource, "local C = feature.C", "Frames must localize C from feature shared")
assertContains(framesSource, "local Strings = feature.Strings", "Frames must localize Strings from feature shared")
assertContains(framesSource, "local coreState = feature.coreState", "Frames must localize core state from feature shared")
assert(not framesSource:find("addon.C", 1, true), "Frames must not read C from addon root")
assert(not framesSource:find("addon.Strings", 1, true), "Frames must not read Strings from addon root")
assert(not framesSource:find("addon.State and addon.State.debugEnabled", 1, true), "Frames must use local coreState for debugEnabled")

local multiSelectSource = read("!KRT/Modules/UI/MultiSelect.lua")
assertContains(multiSelectSource, "local coreState = feature.coreState", "MultiSelect must localize core state from feature shared")
assert(not multiSelectSource:find("addon and addon.State and addon.State.debugEnabled", 1, true), "MultiSelect must use local coreState for debugEnabled")

local visualsSource = read("!KRT/Modules/UI/Visuals.lua")
assertContains(visualsSource, "local UIEffects = feature.UIEffects", "Visuals must localize UI effects from feature shared")
assert(not visualsSource:find("addon.UIEffects", 1, true), "Visuals must not read UI effects from addon root")

local optionsLayoutSource = read("!KRT/Modules/UI/OptionsLayout.lua")
assertContains(optionsLayoutSource, "-- ----- Internal state ----- --", "OptionsLayout must use canonical internal-state header")
assertContains(optionsLayoutSource, "-- ----- Private helpers ----- --", "OptionsLayout must use canonical private-helper header")
assertContains(optionsLayoutSource, "-- ----- Public methods ----- --", "OptionsLayout must use canonical public-method header")

local uiEventHeaders = {
    {
        path = "!KRT/Modules/UI/Facade.lua",
        events = "-- events: none",
    },
    {
        path = "!KRT/Modules/UI/Effects.lua",
        events = "-- events: none; owns UI effect OnUpdate drivers",
    },
    {
        path = "!KRT/Modules/UI/Visuals.lua",
        events = "-- events: none",
    },
    {
        path = "!KRT/Modules/UI/Frames.lua",
        events = "-- events: none; owns shared refresh driver",
    },
    {
        path = "!KRT/Modules/UI/ListController.lua",
        events = "-- events: none; owns deferred list refresh driver",
    },
    {
        path = "!KRT/Modules/UI/MultiSelect.lua",
        events = "-- events: none",
    },
}

for i = 1, #uiEventHeaders do
    local spec = uiEventHeaders[i]
    local source = read(spec.path)
    assertContains(source, spec.events, spec.path .. " must document concrete event ownership in the Lua contract")
    assert(not source:find("-- events: document inbound/outbound events in module body", 1, true), spec.path .. " must not keep the generic event placeholder")
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

local preRegistryUtilityModules = {
    { name = "Modules/C", deps = { "Init" } },
    { name = "Modules/Colors", deps = { "Init" } },
    { name = "Modules/Strings", deps = { "Init", "Modules/Colors" } },
}

for i = 1, #preRegistryUtilityModules do
    local expected = preRegistryUtilityModules[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

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
