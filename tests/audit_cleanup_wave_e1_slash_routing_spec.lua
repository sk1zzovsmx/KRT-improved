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

local slash = read("!KRT/EntryPoints/SlashEvents.lua")
local registry = read("tests/module_registry_ui_entrypoints_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(slash, "local function callControllerMethod(controllerName, methodName, ...)")
assertContains(slash, "return Database.RequestControllerMethod(controllerName, methodName, ...)")
assertNotContains(slash, 'Database.RequestControllerMethod("')

assertContains(slash, "local function callWidgetMethod(widgetId, methodName, ...)")
assertNotContains(slash, "local function callWidget(widgetId, methodName, ...)")
assertNotContains(slash, "callWidget(")

local controllerPairs = {
    { "Master", "ShowDebugRaidGrid" },
    { "Warnings", "Toggle" },
    { "Warnings", "RequestAnnounce" },
    { "Logger", "ToggleLootHistory" },
    { "Logger", "ToggleRaidAttendance" },
    { "Master", "Toggle" },
    { "Spammer", "Toggle" },
    { "Spammer", "RequestStart" },
    { "Spammer", "RequestStop" },
}

for i = 1, #controllerPairs do
    local pair = controllerPairs[i]
    assertContains(slash, 'callControllerMethod("' .. pair[1] .. '", "' .. pair[2] .. '"', "missing slash controller dispatch: " .. pair[1] .. ":" .. pair[2])
end

local widgetPairs = {
    { "Config", "Default" },
    { "Config", "Toggle" },
    { "LootCounter", "Toggle" },
    { "Reserves", "Toggle" },
    { "Reserves", "ToggleImport" },
}

for i = 1, #widgetPairs do
    local pair = widgetPairs[i]
    assertContains(slash, 'callWidgetMethod("' .. pair[1] .. '", "' .. pair[2] .. '"', "missing slash widget dispatch: " .. pair[1] .. ":" .. pair[2])
end

assertContains(registry, 'path = "!KRT/EntryPoints/SlashEvents.lua"')
assertContains(registry, 'pattern = \'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"\'')
assertContains(registry, 'pattern = \'callWidgetMethod%("([%w_]+)"%s*,%s*"([%w_]+)"\'')

assertContains(backlog, "Wave E1 completed: Slash routing helper normalization")

print("audit cleanup wave e1 slash routing source contract passed")
