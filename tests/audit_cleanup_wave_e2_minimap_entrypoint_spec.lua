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
    local firstPos = assert(text:find(first, 1, true), "missing: " .. first)
    local secondPos = assert(text:find(second, 1, true), "missing: " .. second)
    assert(firstPos < secondPos, message or (first .. " must appear before " .. second))
end

local function countPlain(text, needle)
    local count = 0
    local index = 1

    while true do
        local found = text:find(needle, index, true)
        if not found then
            break
        end
        count = count + 1
        index = found + #needle
    end

    return count
end

local minimap = read("!KRT/EntryPoints/Minimap.lua")
local minimapXml = read("!KRT/UI/Minimap.xml")
local registry = read("tests/module_registry_ui_entrypoints_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(minimap, "local function callControllerMethod(controllerName, methodName, ...)")
assertContains(minimap, "return Database.RequestControllerMethod(controllerName, methodName, ...)")
assertNotContains(minimap, 'Database.RequestControllerMethod("')

assertContains(minimap, "local function isWidgetAvailable(widgetId)")
assertContains(minimap, "local function callWidgetMethod(widgetId, methodName, ...)")
assertContains(minimap, "if not isWidgetAvailable(widgetId) then")
assertContains(minimap, "return UIWidgets.Call(widgetId, methodName, ...)")
assertContains(minimap, 'return callWidgetMethod("LootCounter", "Toggle")')
assert(countPlain(minimap, "UIWidgets.IsEnabled(widgetId) and UIWidgets.IsRegistered(widgetId)") == 1)

local controllerPairs = {
    { "Master", "Toggle" },
    { "Logger", "ToggleLootHistory" },
    { "Logger", "ToggleRaidAttendance" },
    { "Warnings", "Toggle" },
    { "Spammer", "Toggle" },
}

for i = 1, #controllerPairs do
    local pair = controllerPairs[i]
    local needle = 'callControllerMethod("' .. pair[1] .. '", "' .. pair[2] .. '"'
    local message = "missing minimap controller dispatch: " .. pair[1] .. ":" .. pair[2]
    assertContains(minimap, needle, message)
end

local widgetPairs = {
    { "Reserves", "Toggle" },
    { "LootCounter", "Toggle" },
    { "Config", "Toggle" },
}

for i = 1, #widgetPairs do
    local pair = widgetPairs[i]
    local needle = 'callWidgetMethod("' .. pair[1] .. '", "' .. pair[2] .. '"'
    local message = "missing minimap widget dispatch: " .. pair[1] .. ":" .. pair[2]
    assertContains(minimap, needle, message)
end

assertContains(registry, 'path = "!KRT/EntryPoints/Minimap.lua"')
assertContains(registry, 'pattern = \'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"\'')
assertContains(registry, 'local lootHistoryDispatch = \'callControllerMethod("Logger", "ToggleLootHistory")\'')
assertContains(registry, 'local raidAttendanceDispatch = \'callControllerMethod("Logger", "ToggleRaidAttendance")\'')

assertBefore(minimap, "L.StrLootMaster", "L.StrLootReserve")
assertBefore(minimap, "L.StrLootReserve", "L.StrLootCounter")
assertBefore(minimap, "L.StrLootCounter", "L.StrLootHistory")
assertBefore(minimap, "L.StrLootHistory", "L.StrRaidAttendance")
assertBefore(minimap, "L.StrRaidAttendance", "RAID_WARNING")
assertBefore(minimap, "RAID_WARNING", "L.StrLFMSpam")
assertBefore(minimap, "L.StrLFMSpam", "L.StrClearIcons")

assertContains(minimap, 'self:SetScript("OnUpdate", moveButton)')
assertContains(minimap, 'self:SetScript("OnUpdate", nil)')
assertNotContains(minimapXml, "<Scripts>")
assertNotContains(minimapXml, "<On")

assertContains(backlog, "Wave E2 completed: Minimap entrypoint routing normalization")

print("audit cleanup wave e2 minimap entrypoint source contract passed")
