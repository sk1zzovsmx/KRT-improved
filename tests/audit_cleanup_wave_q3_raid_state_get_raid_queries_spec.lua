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

local function sliceBetween(text, startNeedle, endNeedle)
    local startIndex = assert(text:find(startNeedle, 1, true), "missing start marker")
    local endIndex = assert(text:find(endNeedle, startIndex, true), "missing end marker")
    return text:sub(startIndex, endIndex - 1)
end

local source = read("!KRT/Services/Raid/State.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local remainingWrappers = sliceBetween(backlog, "Remaining memoized wrappers:", "callers remain in")

assertContains(source, "Database.GetRaidQueriesOrNil", "Raid State should use the optional query facade")
assertNotContains(source, "local RaidQueries =", "Raid State should not keep cached RaidQueries state")
assertNotContains(source, "local function getRaidQueries()", "Raid State should not keep a local getRaidQueries wrapper")
assertNotContains(source, "Database.GetRaidQueries and Database.GetRaidQueries()", "Raid State should not use legacy lazy bootstrap cache")
assertNotContains(source, "Database.GetRaidQueries()", "Raid State should not call Database.GetRaidQueries")
assertContains(source, "local function findBossByNid(raid, bossNid)", "findBossByNid helper should remain")
assertContains(source, "local function findBossByName(raid, bossName)", "findBossByName helper should remain")
assertContains(source, "local function findBossBySourceNpcId(raid, sourceNpcId)", "source npc helper should remain")
assertContains(source, "local function findBossBySourceKey(raid, sourceKey)", "source key helper should remain")
assertContains(source, ":FindBossByNid(raid, bossNid)", "boss nid query call is missing")
assertContains(source, ":FindBossByName(raid, bossName)", "boss name query call is missing")
assertContains(source, ":FindBossBySourceNpcId(raid, sourceNpcId)", "source npc query call is missing")
assertContains(source, ":FindBossBySourceKey(raid, sourceKey)", "source key query call is missing")
assertContains(source, '"Database/DBRaidQueries"', "Raid State must keep explicit query dependency")
assertContains(releaseSpec, 'test("raid state resolves loot session boss through current query facade", function()', "release regression must cover current query facade")
assertContains(backlog, "Wave Q3 completed Raid State owner group", "backlog should record Q3 completion")
assertNotContains(remainingWrappers, "`!KRT/Services/Raid/State.lua`", "Raid State should leave remaining wrapper list")
assertContains(remainingWrappers, "None.", "remaining wrapper list should be closed")

print("audit cleanup wave Q3 Raid State getRaidQueries contract passed")
