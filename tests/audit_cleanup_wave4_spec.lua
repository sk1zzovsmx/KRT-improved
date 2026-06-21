local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing: " .. needle), 0)
    end
end

local function assertNotContains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected: " .. needle), 0)
    end
end

local db = read("!KRT/Database/DB.lua")
local loggerView = read("!KRT/Services/Logger/View.lua")
local loggerExport = read("!KRT/Services/Logger/Export.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(db, "function Database.GetRaidQueriesOrNil()", "DB facade should expose optional RaidQueries access")
assertContains(db, "return Database.GetRaidQueries()", "optional RaidQueries access should preserve dynamic GetRaidQueries overrides")
assertContains(loggerView, "Database.GetRaidQueriesOrNil()", "Logger View should use the Database facade helper")
assertContains(loggerExport, "Database.GetRaidQueriesOrNil()", "Logger Export should use the Database facade helper")
assertNotContains(loggerView, "local function getRaidQueries()", "Logger View should not keep the duplicated local query wrapper")
assertNotContains(loggerExport, "local function getRaidQueries()", "Logger Export should not keep the duplicated local query wrapper")
assertNotContains(loggerExport, "local rows = {}", "Logger Export should build CSV content without per-export row table accumulation in GetLootCSV/GetRaidAttendanceCSV")
assertNotContains(loggerExport, "rows[#rows + 1] = {", "Logger Export should build CSV content without preallocating row arrays in GetLootCSV/GetRaidAttendanceCSV")
assertNotContains(loggerView, '"Database/DBRaidQueries"', "Logger View must not depend directly on DBRaidQueries")
assertNotContains(loggerExport, '"Database/DBRaidQueries"', "Logger Export must not depend directly on DBRaidQueries")
assertContains(releaseSpec, "Database.GetRaidQueriesOrNil = function()", "isolated release harness should expose the optional RaidQueries facade helper")
assertContains(backlog, "Wave 4 centralized optional dynamic query access", "cleanup backlog should record the Wave4 optional dynamic query centralization")

print("audit cleanup wave4 source contract passed")
