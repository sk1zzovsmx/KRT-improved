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

local source = read("!KRT/Services/Loot/Service.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(source, "Database.GetRaidQueriesOrNil", "Loot service should read queries through the optional query facade")
assertNotContains(source, "local RaidQueries =", "Loot service should not keep cached RaidQueries state")
assertNotContains(source, "local function getRaidQueries()", "Loot service should not keep a local getRaidQueries wrapper")
assertNotContains(source, "Database.GetRaidQueries and Database.GetRaidQueries()", "Loot service should not use legacy lazy bootstrap cache")
assertNotContains(source, "Database.GetRaidQueries()", "Loot service should not call Database.GetRaidQueries after wave Q1")
assertContains(source, "local function resolveStoredLootLooterName(raid, raidNum, loot)", "Loot service should keep resolveStoredLootLooterName signature")
assertContains(source, ":ResolveLootLooterName(raid, loot)", "Loot service should resolve looter through current query facade")
assertContains(source, "raidService:GetPlayerName(looterNid, raidNum)", "Loot service should preserve Raid service fallback path")
assertContains(source, '"Database/DBRaidQueries"', "Loot service must keep explicit query dependency for Q1")
assertContains(releaseSpec, 'test("loot service resolves stored looter through current query facade", function()', "release regression must cover current facade usage")
assertContains(backlog, "Wave Q1 completed Loot Service owner group", "backlog should record Wave Q1 completion")
assertContains(backlog, "!KRT/Services/Raid/LootRecords.lua", "backlog should keep Raid LootRecords for a later owner wave")
assertContains(backlog, "!KRT/Services/Raid/State.lua", "backlog should keep Raid State for a later owner wave")

print("audit cleanup wave Q1 loot getRaidQueries contract passed")
