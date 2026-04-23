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

-- === Fixture: 3 raids ===
-- Raid 1 (oldest): Alice MS=1, Bob MS=0
-- Raid 2:          Alice MS=2, Bob MS=1, Carol MS=0
-- Raid 3 (newest): Alice MS=0, Bob MS=0, Carol MS=3
local raids = {
    [1] = { players = { { name = "Alice", countMS = 1 }, { name = "Bob", countMS = 0 } } },
    [2] = { players = { { name = "Alice", countMS = 2 }, { name = "Bob", countMS = 1 }, { name = "Carol", countMS = 0 } } },
    [3] = { players = { { name = "Alice", countMS = 0 }, { name = "Bob", countMS = 0 }, { name = "Carol", countMS = 3 } } },
}
local addon = buildHarness(raids, 3)
local Raid = loadCounts(addon)

-- --- GetPlayerMSCount ---
assertEq(Raid:GetPlayerMSCount("Alice", { scope = "CURRENT" }), 0, "Alice CURRENT")
assertEq(Raid:GetPlayerMSCount("Alice", { scope = "ALL" }), 3, "Alice ALL")
assertEq(Raid:GetPlayerMSCount("Bob", { scope = "ALL" }), 1, "Bob ALL")
assertEq(Raid:GetPlayerMSCount("Carol", { scope = "LAST_N", n = 2 }), 3, "Carol LAST_N=2")
assertEq(Raid:GetPlayerMSCount("Carol", { scope = "LAST_N", n = 1 }), 3, "Carol LAST_N=1")
assertEq(Raid:GetPlayerMSCount("Ghost", { scope = "ALL" }), 0, "Ghost absent")
assertEq(Raid:GetPlayerMSCount(nil, { scope = "ALL" }), 0, "nil name")
assertEq(Raid:GetPlayerMSCount("Alice", nil), 0, "nil opts defaults to CURRENT")

-- --- GetMSCountsForNames (batch) ---
local map = Raid:GetMSCountsForNames({ "Alice", "Bob", "Ghost" }, { scope = "ALL" })
assertEq(map.Alice, 3, "batch ALL Alice")
assertEq(map.Bob, 1, "batch ALL Bob")
assertEq(map.Ghost, 0, "batch ALL Ghost")

local singleAlice = Raid:GetPlayerMSCount("Alice", { scope = "LAST_N", n = 2 })
local batchAlice = (Raid:GetMSCountsForNames({ "Alice" }, { scope = "LAST_N", n = 2 })).Alice
assertEq(batchAlice, singleAlice, "batch == single for LAST_N=2")

local empty = Raid:GetMSCountsForNames({}, { scope = "ALL" })
assertEq(next(empty) == nil, true, "empty names returns empty map")

if failures == 0 then
    print("OK")
else
    print(string.format("FAILED %d assertion(s)", failures))
    os.exit(1)
end
