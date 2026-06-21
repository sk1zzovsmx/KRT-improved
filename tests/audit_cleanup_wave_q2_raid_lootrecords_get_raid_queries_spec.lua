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

local source = read("!KRT/Services/Raid/LootRecords.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local remainingWrappers = sliceBetween(backlog, "Remaining memoized wrappers:", "- direct callers remain")

assertContains(source, "Database.GetRaidQueriesOrNil", "LootRecords should use the optional query facade")
assertNotContains(source, "local RaidQueries =", "LootRecords should not keep cached RaidQueries state")
assertNotContains(source, "local function getRaidQueries()", "LootRecords should not keep a local getRaidQueries wrapper")
assertNotContains(source, "Database.GetRaidQueries and Database.GetRaidQueries()", "LootRecords should not use legacy lazy bootstrap cache")
assertNotContains(source, "Database.GetRaidQueries()", "LootRecords should not call Database.GetRaidQueries")
assertContains(source, "local function resolveLootLooterName(raid, entry)", "resolver signature changed")
assertContains(source, ":ResolveLootLooterName(raid, entry)", "query resolver call is missing")
assertContains(source, "function module:GetHeldLootNid", "held-loot lookup should stay in LootRecords")
assertContains(source, "function module:GetLootNidByRollSessionId", "roll-session lookup should stay in LootRecords")
assertContains(source, '"Database/DBRaidQueries"', "LootRecords must keep explicit query dependency")
assertContains(releaseSpec, 'test("raid loot records resolve roll session looter through current query facade", function()', "release regression must cover current query facade")
assertContains(backlog, "Wave Q2 completed Raid LootRecords owner group", "backlog should record Q2 completion")
assertNotContains(remainingWrappers, "`!KRT/Services/Raid/LootRecords.lua`", "LootRecords should leave remaining memoized wrappers list")
assertContains(remainingWrappers, "`!KRT/Services/Raid/State.lua`", "Raid State should remain for Q3")

print("audit cleanup wave Q2 Raid LootRecords getRaidQueries contract passed")
