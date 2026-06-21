local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function countPlain(text, needle)
    local count = 0
    local startIndex = 1
    while true do
        local found = text:find(needle, startIndex, true)
        if not found then
            return count
        end
        count = count + 1
        startIndex = found + #needle
    end
end

local function assertBefore(text, first, second, message)
    local firstIndex = text:find(first, 1, true)
    local secondIndex = text:find(second, 1, true)
    assert(firstIndex, "missing first marker: " .. first)
    assert(secondIndex, "missing second marker: " .. second)
    assert(firstIndex < secondIndex, message or (first .. " must appear before " .. second))
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
        events = "-- events: none",
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
        events = "-- events: none",
    },
    {
        name = "Modules/Strings",
        path = "!KRT/Modules/Strings.lua",
        deps = { "Init", "Modules/Colors" },
        events = "-- events: none",
    },
    {
        name = "Modules/Item",
        path = "!KRT/Modules/Item.lua",
        deps = { "Init", "Modules/Timer", "Modules/Strings" },
        events = "-- events: no bus events; item cache polling uses the Timer dependency",
    },
    {
        name = "Modules/LootSourceCandidates",
        path = "!KRT/Modules/LootSourceCandidates.lua",
        deps = { "Init", "Modules/Strings" },
        events = "-- events: none",
    },
    {
        name = "Modules/Dataset/LootSourcesData",
        path = "!KRT/Modules/Dataset/LootSourcesData.lua",
        deps = { "Init", "Modules/LootSourceCandidates" },
        events = "-- events: none",
    },
    {
        name = "Modules/LootSources",
        path = "!KRT/Modules/LootSources.lua",
        deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/Dataset/LootSourcesData" },
        events = "-- events: none",
    },
    {
        name = "Modules/Dataset/IgnoredItems",
        path = "!KRT/Modules/Dataset/IgnoredItems.lua",
        deps = { "Init" },
        events = "-- events: none",
    },
    {
        name = "Modules/Dataset/IgnoredMobs",
        path = "!KRT/Modules/Dataset/IgnoredMobs.lua",
        deps = { "Init" },
        events = "-- events: none",
    },
    {
        name = "Modules/Comms",
        path = "!KRT/Modules/Comms.lua",
        deps = { "Init" },
        events = "-- events: owns addon-message send helpers and KRTVersion payload handling",
    },
    {
        name = "Modules/Time",
        path = "!KRT/Modules/Time.lua",
        deps = { "Init" },
        events = "-- events: none",
    },
    {
        name = "Modules/Base64",
        path = "!KRT/Modules/Base64.lua",
        deps = { "Init" },
        events = "-- events: none",
    },
    {
        name = "Modules/Json",
        path = "!KRT/Modules/Json.lua",
        deps = { "Init" },
        events = "-- events: none",
    },
    {
        name = "Modules/Sort",
        path = "!KRT/Modules/Sort.lua",
        deps = { "Init" },
        events = "-- events: none",
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
    assertContains(source, "local registry = feature.ModuleRegistry", expected.path .. " must localize ModuleRegistry from feature shared")
    assert(not source:find("local registry = addon.ModuleRegistry", 1, true), expected.path .. " must not read ModuleRegistry directly from addon root")
    if expected.events then
        assertContains(source, expected.events, expected.path .. " must document its KRT Lua Contract events")
    end
    assertContains(source, "registry.AddModule(name, { deps = deps })", expected.path .. " must register directly when registry exists")
    assertContains(source, "registry.SetLoaded(name)", expected.path .. " must mark directly when registry exists")
    for depIndex = 1, #expected.deps do
        assertContains(source, '"' .. expected.deps[depIndex] .. '"', expected.path .. " must declare required deps")
    end
end

local itemSource = read("!KRT/Modules/Item.lua")
assertContains(itemSource, "local Timer = feature.Timer", "Item module must localize Timer from feature shared")
assert(not itemSource:find("addon.Timer", 1, true), "Item module must use the local Timer dependency")
assertContains(itemSource, "local Deformat = feature.Deformat", "Item module must localize Deformat from feature shared")
assert(not itemSource:find("addon.Deformat", 1, true), "Item module must use the local Deformat dependency")

local initSource = read("!KRT/Init.lua")
assertContains(initSource, "Deformat = addon.Deformat", "feature shared must expose LibDeformat")

local colorsSource = read("!KRT/Modules/Colors.lua")
assertContains(colorsSource, "local GetClassColor = feature.GetClassColor", "Colors module must localize GetClassColor from feature shared")
assert(not colorsSource:find("addon.GetClassColor", 1, true), "Colors module must use the local GetClassColor dependency")

local lootSourcesSource = read("!KRT/Modules/LootSources.lua")
assertContains(lootSourcesSource, "local LootSourcesData = feature.LootSourcesData or {}", "LootSources module must localize LootSourcesData from feature shared")
assert(not lootSourcesSource:find("addon.LootSourcesData.", 1, true), "LootSources module must use the local LootSourcesData dependency")

local lootSourcesDataSource = read("!KRT/Modules/Dataset/LootSourcesData.lua")
assertContains(lootSourcesDataSource, "-- shared: local feature = addon.Database.GetFeatureShared()", "LootSourcesData must document its feature shared header dependency")
assertContains(
    lootSourcesDataSource,
    "-- exports: addon.LootSourcesData (static data tables; no public methods)",
    "LootSourcesData must document its static-dataset public-method exception"
)
assertContains(
    lootSourcesDataSource,
    "-- notes: static raid item source data for Vanilla through Wrath of the Lich King",
    "LootSourcesData must document its static dataset role as a note"
)
assert(not lootSourcesDataSource:find("function%s+LootSourcesData"), "LootSourcesData must remain a static dataset without public methods")

assertContains(lootSourcesSource, "local LootSourceCandidates = feature.LootSourceCandidates", "LootSources module should localize LootSourceCandidates from feature shared")
assertContains(
    lootSourcesDataSource,
    "local LootSourceCandidates = feature.LootSourceCandidates",
    "LootSourcesData module should localize LootSourceCandidates from feature shared"
)

local timerSource = read("!KRT/Modules/Timer.lua")
assertContains(timerSource, "-- shared: local feature = addon.Database.GetFeatureShared()", "Timer module must document its feature shared header dependency")
assertContains(timerSource, "-- ----- Public methods ----- --", "Timer module must use canonical public-method header")
assert(not timerSource:find("-- ----- Public static API ----- --", 1, true), "Timer module must not keep the non-canonical public static API section header")

local ignoredMobsSource = read("!KRT/Modules/Dataset/IgnoredMobs.lua")
assert(countPlain(ignoredMobsSource, "-- ----- Private helpers ----- --") == 1, "IgnoredMobs must keep a single canonical private-helper section marker")

local featureOwnedModuleTables = {
    {
        path = "!KRT/Modules/Dataset/LootSourcesData.lua",
        name = "LootSourcesData",
    },
    {
        path = "!KRT/Modules/Dataset/LootSources/Vanilla.lua",
        name = "LootSourcesData",
    },
    {
        path = "!KRT/Modules/Dataset/LootSources/BurningCrusade.lua",
        name = "LootSourcesData",
    },
    {
        path = "!KRT/Modules/Dataset/LootSources/Wrath.lua",
        name = "LootSourcesData",
    },
    {
        path = "!KRT/Modules/Item.lua",
        name = "Item",
    },
    {
        path = "!KRT/Modules/Timer.lua",
        name = "Timer",
    },
    {
        path = "!KRT/Modules/Comms.lua",
        name = "Comms",
    },
    {
        path = "!KRT/Modules/LootSources.lua",
        name = "LootSources",
    },
    {
        path = "!KRT/Modules/Dataset/IgnoredItems.lua",
        name = "IgnoredItems",
    },
    {
        path = "!KRT/Modules/Dataset/IgnoredMobs.lua",
        name = "IgnoredMobs",
    },
    {
        path = "!KRT/Modules/Bus.lua",
        name = "Bus",
    },
    {
        path = "!KRT/Modules/C.lua",
        name = "C",
    },
    {
        path = "!KRT/Modules/Base64.lua",
        name = "Base64",
    },
    {
        path = "!KRT/Modules/Colors.lua",
        name = "Colors",
    },
    {
        path = "!KRT/Modules/Events.lua",
        name = "Events",
    },
    {
        path = "!KRT/Modules/Features.lua",
        name = "Features",
    },
    {
        path = "!KRT/Modules/Json.lua",
        name = "Json",
    },
    {
        path = "!KRT/Modules/Sort.lua",
        name = "Sort",
    },
    {
        path = "!KRT/Modules/Strings.lua",
        name = "Strings",
    },
    {
        path = "!KRT/Modules/Time.lua",
        name = "Time",
    },
}

for i = 1, #featureOwnedModuleTables do
    local expected = featureOwnedModuleTables[i]
    local source = read(expected.path)
    assertContains(source, "local " .. expected.name .. " = feature." .. expected.name .. " or {}", expected.path .. " must bind owner table from feature shared")
    assert(not source:find("local " .. expected.name .. " = addon." .. expected.name, 1, true), expected.path .. " must not bind owner table directly from addon root")
end

local busSource = read("!KRT/Modules/Bus.lua")
assertContains(busSource, "-- events: owns addon.Bus callback registration and dispatch", "Bus must document internal event bus ownership")
assert(not busSource:find("-- events: document inbound/outbound events in module body", 1, true), "Bus must not keep the generic event placeholder")

local staticLootSourceDatasetFiles = {
    {
        path = "!KRT/Modules/Dataset/LootSources/Vanilla.lua",
        note = "-- notes: static raid loot source data for Classic Vanilla",
    },
    {
        path = "!KRT/Modules/Dataset/LootSources/BurningCrusade.lua",
        note = "-- notes: static raid loot source data for The Burning Crusade",
    },
    {
        path = "!KRT/Modules/Dataset/LootSources/Wrath.lua",
        note = "-- notes: static raid loot source data for Wrath of the Lich King",
    },
}
for i = 1, #staticLootSourceDatasetFiles do
    local spec = staticLootSourceDatasetFiles[i]
    local path = spec.path
    local source = read(path)
    assertContains(source, "-- shared: local feature = addon.Database.GetFeatureShared()", path .. " must document its feature shared header dependency")
    assertContains(source, spec.note, path .. " must document its static dataset exception as a note")
    assertContains(source, "-- events: none", path .. " must document static dataset event behavior")
    assert(countPlain(source, "-- ----- Private helpers ----- --") == 1, path .. " must keep a single canonical private-helper section marker")
    assert(countPlain(source, "-- ----- Public methods ----- --") == 1, path .. " must keep a single canonical public-methods section marker")
    assert(not source:find("local function appendLootSources", 1, true), path .. " must append static data without a local append helper")
    assertBefore(source, "-- ----- Internal state ----- --", "-- ----- Private helpers ----- --", path .. " must order internal state before private helpers")
    assertBefore(source, "-- ----- Private helpers ----- --", "-- ----- Public methods ----- --", path .. " must keep canonical helper/public section order")
    assertBefore(source, "-- ----- Public methods ----- --", "local lootSources = {", path .. " must declare the static data table in the public section")
    assertBefore(source, "local lootSources = {", "for i = 1, #lootSources do", path .. " must append static data with a Lua 5.1 numeric loop")
end

local commsSource = read("!KRT/Modules/Comms.lua")
assertContains(commsSource, "local shared = Database.GetFeatureShared()", "Comms must refresh delayed shared dependencies through Database")
assertContains(commsSource, "return shared and shared.Base64", "Comms must read delayed Base64 from feature shared")
assert(not commsSource:find("addon.Base64", 1, true), "Comms must not read Base64 from addon root")

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
local lootSourcesDataStatus = registry.GetStatus("Modules/Dataset/LootSourcesData")
assert(stringsStatus.LoadOrder < lootSourcesStatus.LoadOrder, "Modules/Strings must load before Modules/LootSources")
assert(lootSourcesDataStatus.LoadOrder < lootSourcesStatus.LoadOrder, "Modules/Dataset/LootSourcesData must load before Modules/LootSources")
local lootSourcesCandidatesStatus = registry.GetStatus("Modules/LootSourceCandidates")
assert(lootSourcesCandidatesStatus.LoadOrder < lootSourcesDataStatus.LoadOrder, "Modules/LootSourceCandidates must load before Modules/Dataset/LootSourcesData")
assert(lootSourcesCandidatesStatus.LoadOrder < lootSourcesStatus.LoadOrder, "Modules/LootSourceCandidates must load before Modules/LootSources")

local ok, issues = registry.GetLoadOrderStatus()
assert(ok == true, "pre-registry utility module sequence must validate in TOC order")
assert(issues == nil, "valid pre-registry utility module sequence must not report dependency issues")

print("module registry pre-registry modules source contract passed")
