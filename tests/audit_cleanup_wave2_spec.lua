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

local loggerView = read("!KRT/Services/Logger/View.lua")
local loggerExport = read("!KRT/Services/Logger/Export.lua")
local reserves = read("!KRT/Services/Reserves.lua")
local logger = read("!KRT/Controllers/Logger.lua")

assertNotContains(loggerView, "local function startPerf()", "Logger view should call the canonical perf start hook directly")
assertNotContains(loggerExport, "local function startPerf()", "Logger export should call the canonical perf start hook directly")
assertNotContains(reserves, "local function startPerf()", "Reserves should call the canonical perf start hook directly")

assertContains(loggerView, "local perfStart = addon.hasPerf and addon._PerfStart and addon:_PerfStart() or nil", "Logger view should use the canonical guarded perf start call")
assertContains(loggerExport, "local perfStart = addon.hasPerf and addon._PerfStart and addon:_PerfStart() or nil", "Logger export should use the canonical guarded perf start call")
assertContains(reserves, "local perfStart = addon.hasPerf and addon._PerfStart and addon:_PerfStart() or nil", "Reserves should use the canonical guarded perf start call")

local slashEvents = read("!KRT/EntryPoints/SlashEvents.lua")

assertContains(slashEvents, "local function showToggleHelp(commandRoot)", "SlashEvents should share one toggle-help wrapper")
assertNotContains(slashEvents, "local function showLootHelp()", "SlashEvents should not keep the old loot help wrapper")
assertNotContains(slashEvents, "local function showCounterHelp()", "SlashEvents should not keep the old counter help wrapper")
assertContains(slashEvents, 'showToggleHelp("krt ml")', "Master loot help should use shared toggle help")
assertContains(slashEvents, 'showToggleHelp("krt counter")', "Counter help should use shared toggle help")

print("audit cleanup wave2 source contract passed")
