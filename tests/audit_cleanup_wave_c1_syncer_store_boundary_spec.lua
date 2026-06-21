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

local syncer = read("!KRT/Database/DBSyncer.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertNotContains(syncer, "local RaidQueries =", "DBSyncer must not memoize RaidQueries")
assertNotContains(syncer, "local function getRaidQueries()", "DBSyncer must not keep a query wrapper")
assertNotContains(syncer, "Database.GetRaidQueries and Database.GetRaidQueries()", "DBSyncer should use the optional dynamic query facade")

assertContains(syncer, "local function resolveLootLooterNameFromMap(loot, playerNameByNid)")
assertContains(syncer, "local queries = Database.GetRaidQueriesOrNil()")
assertContains(syncer, "return queries:ResolveLootLooterNameFromMap(loot, playerNameByNid)")

assertContains(syncer, "local function applySnapshotHeaderToRaid(raid, header)")
assertContains(syncer, "local function applySnapshotNextNids(raid, header)")
assertContains(syncer, "local function finalizeSnapshotRaid(raid)")
assertContains(syncer, "local function getSnapshotImportRaidStore()")
assertContains(syncer, "local function createRaidFromSnapshotHeader(raidStore, header)")

assertBefore(syncer, "local function applySnapshotHeaderToRaid", "local function applySnapshotToRaid")
assertBefore(syncer, "local function getSnapshotImportRaidStore", "local function importSnapshotAsNewRaid")
assertBefore(syncer, "local function createRaidFromSnapshotHeader", "local function importSnapshotAsNewRaid")

assertContains(syncer, "applySnapshotHeaderToRaid(raid, header)")
assertContains(syncer, "applySnapshotNextNids(raid, header)")
assertContains(syncer, "return finalizeSnapshotRaid(raid)")
assertContains(syncer, "local raidStore = getSnapshotImportRaidStore()")
assertContains(syncer, "local raid = createRaidFromSnapshotHeader(raidStore, header)")

assertContains(releaseSpec, 'test("db syncer resolves loot looter through current query facade", function()')
assertContains(backlog, "Wave C1 completed: Syncer store boundary cleanup")

print("audit cleanup wave c1 syncer store boundary source contract passed")
