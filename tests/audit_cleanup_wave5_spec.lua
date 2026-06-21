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
local store = read("!KRT/Services/Logger/Store.lua")
local actions = read("!KRT/Services/Logger/Actions.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local releaseNeedle = "Database.GetRaidQueriesOrNil = function()"
local backlogNeedle = "Wave 5 follow-up: remaining `getRaidQueries` wrappers"

assertContains(db, "function Database.GetRaidQueriesOrNil()", "Wave 5 requires the Wave 4 optional query facade")
assertContains(store, "Database.GetRaidQueriesOrNil()", "Logger Store should use the Database query facade")
assertContains(actions, "Database.GetRaidQueriesOrNil()", "Logger Actions should use the Database query facade")
assertNotContains(store, "local RaidQueries =", "Logger Store should not keep a memoized RaidQueries cache")
assertNotContains(actions, "local RaidQueries =", "Logger Actions should not keep a memoized RaidQueries cache")
assertNotContains(store, "local function getRaidQueries()", "Logger Store should not keep a local query wrapper")
assertNotContains(actions, "local function getRaidQueries()", "Logger Actions should not keep a local query wrapper")
assertContains(store, '"Database/DBRaidQueries"', "Logger Store registry dependency should stay explicit")
assertContains(actions, '"Database/DBRaidQueries"', "Logger Actions registry dependency should stay explicit")
assertContains(releaseSpec, releaseNeedle, "release harness should provide the query facade")
assertContains(backlog, backlogNeedle, "backlog should record remaining wrappers after Logger cleanup")

print("audit cleanup wave5 source contract passed")
