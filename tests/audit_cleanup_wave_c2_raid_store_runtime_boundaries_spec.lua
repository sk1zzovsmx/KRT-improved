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
    local firstPos = assert(text:find(first, 1, true), "missing: " .. first)
    local secondPos = assert(text:find(second, 1, true), "missing: " .. second)
    assert(firstPos < secondPos, message or (first .. " must appear before " .. second))
end

local raidStore = read("!KRT/Database/DBRaidStore.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(raidStore, "local RUNTIME_INDEX_MAP_KEYS = {")
assertContains(raidStore, '"playersByName",')
assertContains(raidStore, '"playerByNid",')
assertContains(raidStore, '"playerNidByName",')
assertContains(raidStore, '"playerIdxByNid",')
assertContains(raidStore, '"bossIdxByNid",')
assertContains(raidStore, '"bossByNid",')
assertContains(raidStore, '"bossPlayerSetByBossNid",')
assertContains(raidStore, '"lootIdxByNid",')
assertContains(raidStore, '"lootByNid",')
assertContains(raidStore, '"lootIdxByBossNid",')
assertContains(raidStore, '"lootIdxByLooterNid",')
assertContains(raidStore, '"attendanceIdxByPlayerNid",')
assertContains(raidStore, '"attendanceByPlayerNid",')
assertContains(raidStore, "local function acquireRuntimeIndexMaps(runtime)")
assertContains(raidStore, "for i = 1, #RUNTIME_INDEX_MAP_KEYS do")
assertContains(raidStore, "maps[key] = acquireRuntimeIndexMap(runtime, key)")
assertContains(raidStore, 'type(runtime[RUNTIME_INDEX_MAP_KEYS[i]]) == "table"')
assertContains(raidStore, "local function getRuntimeCollections(raid)")
assertContains(raidStore, "local function buildRaidRuntimeSignature(raid)")
assertContains(raidStore, "local function refreshRuntimeSignature(raid, runtime)")
assertContains(raidStore, "runtime.signature = buildRaidRuntimeSignature(raid)")
assertContains(raidStore, "local function normalizeRuntimeState(raid)")
assertContains(raidStore, "local function stripRuntimeState(raid)")
assertContains(raidStore, "local function indexLootRuntimeRow(runtime, loot, index, replaceExisting)")
assertContains(raidStore, "indexLootRuntimeRow(runtime, lootRows[i], i, false)")
assertContains(raidStore, "if not indexLootRuntimeRow(runtime, row, resolvedIndex, true) then")
assertBefore(raidStore, "local RUNTIME_INDEX_MAP_KEYS = {", "local function isRuntimeIndexReady")

local acquireMaps = "local function acquireRuntimeIndexMaps(runtime)"
local buildRuntime = "local function buildRuntimeIndexesForNormalizedRaid"
local indexLoot = "local function indexLootRuntimeRow(runtime, loot, index, replaceExisting)"

assertBefore(raidStore, acquireMaps, buildRuntime)
assertBefore(raidStore, indexLoot, "function module:UpsertLootIndex")

assertContains(releaseSpec, 'test("runtime cache upsert moves loot index between boss and looter maps", function()')
assertContains(backlog, "Wave C2 completed: Raid store runtime boundary cleanup")

print("audit cleanup wave c2 raid store runtime boundaries source contract passed")
