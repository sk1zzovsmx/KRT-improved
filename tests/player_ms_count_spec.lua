-- Standalone unit tests for Services/Raid/Counts new APIs.
-- Run with: lua tests/player_ms_count_spec.lua

local failures = 0
local function assertEq(actual, expected, label)
    if actual ~= expected then
        failures = failures + 1
        print(string.format("FAIL %s: expected=%s got=%s", label, tostring(expected), tostring(actual)))
    end
end

-- Build a fake addon object exposing only what Counts.lua requires.
local function buildHarness(raids, currentRaidNum)
    _G.KRT_Raids = raids
    local addon = {
        Services = { Raid = {} },
        Core = {
            GetCurrentRaid = function()
                return currentRaidNum
            end,
            EnsureRaidById = function(num)
                return raids[num]
            end,
            EnsureRaidSchema = function() end,
            GetRaidStoreOrNil = function()
                return nil
            end,
        },
        Events = { Internal = {} },
    }
    addon.Core.GetFeatureShared = function()
        return { Events = addon.Events, Core = addon.Core }
    end
    return addon
end

local function loadCounts(addon)
    local f = assert(io.open("!KRT/Services/Raid/Counts.lua", "r"))
    local src = f:read("*a")
    f:close()
    local chunk = assert(loadstring(src, "Counts.lua"))
    setfenv(
        chunk,
        setmetatable({
            select = function(n, ...)
                if n == 2 then
                    return addon
                end
                return select(n, ...)
            end,
        }, { __index = _G })
    )
    chunk("!KRT", addon)
    return addon.Services.Raid
end

-- === Fixture: current raid with known MS counts ===
-- Alice MS=2, Bob MS=0, Carol MS=3 in the current raid. Older raids are ignored.
local raids = {
    [1] = { players = { { name = "Alice", countMS = 1 }, { name = "Bob", countMS = 0 } } },
    [2] = { players = { { name = "Alice", countMS = 2 }, { name = "Bob", countMS = 0 }, { name = "Carol", countMS = 3 } } },
}
local addon = buildHarness(raids, 2)
local Raid = loadCounts(addon)

-- --- GetPlayerMSCount (current raid only) ---
assertEq(Raid:GetPlayerMSCount("Alice"), 2, "Alice current")
assertEq(Raid:GetPlayerMSCount("Bob"), 0, "Bob current")
assertEq(Raid:GetPlayerMSCount("Carol"), 3, "Carol current")
assertEq(Raid:GetPlayerMSCount("Ghost"), 0, "Ghost absent")
assertEq(Raid:GetPlayerMSCount(nil), 0, "nil name")
assertEq(Raid:GetPlayerMSCount(""), 0, "empty name")

-- --- GetMSCountsForNames (batch) ---
local map = Raid:GetMSCountsForNames({ "Alice", "Bob", "Carol", "Ghost" })
assertEq(map.Alice, 2, "batch Alice")
assertEq(map.Bob, 0, "batch Bob")
assertEq(map.Carol, 3, "batch Carol")
assertEq(map.Ghost, 0, "batch Ghost")

-- Batch result must match individual queries for every player.
assertEq(map.Alice, Raid:GetPlayerMSCount("Alice"), "batch == single for Alice")
assertEq(map.Carol, Raid:GetPlayerMSCount("Carol"), "batch == single for Carol")

-- Empty names returns empty map.
local empty = Raid:GetMSCountsForNames({})
assertEq(next(empty) == nil, true, "empty names returns empty map")

-- Missing current raid returns zeros, not errors.
local addon2 = buildHarness(raids, nil)
local Raid2 = loadCounts(addon2)
assertEq(Raid2:GetPlayerMSCount("Alice"), 0, "nil currentRaid => 0")
local map2 = Raid2:GetMSCountsForNames({ "Alice" })
assertEq(map2.Alice, 0, "nil currentRaid batch => 0")

if failures == 0 then
    print("OK")
else
    print(string.format("FAILED %d assertion(s)", failures))
    os.exit(1)
end
