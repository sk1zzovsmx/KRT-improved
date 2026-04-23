-- Standalone tests for the new tiebreaker logic inside Resolution.
-- Run with: lua tests/resolution_tiebreaker_spec.lua

local failures = 0
local function assertEq(actual, expected, label)
    if actual ~= expected then
        failures = failures + 1
        print(string.format("FAIL %s: expected=%s got=%s", label, tostring(expected), tostring(actual)))
    end
end

-- Load Resolution.lua in isolation.
local function loadResolution()
    local f = assert(io.open("!KRT/Services/Rolls/Resolution.lua", "r"))
    local src = f:read("*a")
    f:close()
    local addon = {
        Services = { Rolls = {} },
        Core = {},
    }
    addon.Core.GetFeatureShared = function()
        return {
            rollTypes = { MAINSPEC = 1, OFFSPEC = 2, RESERVED = 3, DISENCHANT = 6, FREE = 5 },
            L = setmetatable({}, {
                __index = function(_, k)
                    return k
                end,
            }),
            Diag = {
                D = setmetatable({}, {
                    __index = function(_, k)
                        return function()
                            return k
                        end
                    end,
                }),
            },
        }
    end
    local chunk = assert(loadstring(src, "Resolution.lua"))
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
    return addon.Services.Rolls._Resolution, addon
end

local Resolution = loadResolution()

local function makeCtx(overrides)
    local ctx = {
        state = { responsesByPlayer = {} },
        rollTypes = { MAINSPEC = 1, OFFSPEC = 2, RESERVED = 3, FREE = 5 },
        responseStatus = { ROLL = "ROLL", PASS = "PASS", CANCELLED = "CANCELLED", ACTIVE = "ACTIVE", TIMED_OUT = "TIMED_OUT", INELIGIBLE = "INELIGIBLE" },
        reasonCodes = { NOT_IN_RAID = "NOT_IN_RAID" },
        isSelectableRollResponse = function(r)
            return r.status == "ROLL" and r.isEligible
        end,
        isPlusSystemEnabled = function()
            return false
        end,
        isSortAscending = function()
            return false
        end,
        getExpectedWinnerCount = function()
            return 1
        end,
        isTiebreakerByMSCountEnabled = function()
            return overrides.tiebreakerOn
        end,
        getMSCountsForNames = function()
            return overrides.msCounts or {}
        end,
    }
    for _, entry in ipairs(overrides.responses or {}) do
        ctx.state.responsesByPlayer[entry.name] = entry
    end
    return ctx
end

-- --- Case A: tiebreaker OFF, two rolls tie → alphabetical fallback ---
local ctxA = makeCtx({
    tiebreakerOn = false,
    responses = {
        { name = "Bob", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
    },
})
local resolvedA = Resolution.BuildResolvedEntries(ctxA, nil, ctxA.rollTypes.MAINSPEC)
assertEq(resolvedA[1].name, "Alice", "A: tiebreaker OFF → alphabetical")

-- --- Case B: tiebreaker ON, different MS counts → lower wins ---
local ctxB = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 2, Bob = 0 },
    responses = {
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
        { name = "Bob", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
    },
})
local resolvedB = Resolution.BuildResolvedEntries(ctxB, nil, ctxB.rollTypes.MAINSPEC)
assertEq(resolvedB[1].name, "Bob", "B: tiebreaker ON → fewer MS wins")

-- --- Case C: tiebreaker ON, same MS counts → alphabetical fallback ---
local ctxC = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 1, Bob = 1 },
    responses = {
        { name = "Bob", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
    },
})
local resolvedC = Resolution.BuildResolvedEntries(ctxC, nil, ctxC.rollTypes.MAINSPEC)
assertEq(resolvedC[1].name, "Alice", "C: same MS count → alphabetical fallback")

-- --- Case D: tiebreaker ON, SR bucket → tiebreaker does NOT apply ---
local ctxD = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 5, Bob = 0 },
    responses = {
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "SR", bestRoll = 95 },
        { name = "Bob", status = "ROLL", isEligible = true, bucket = "SR", bestRoll = 95 },
    },
})
local resolvedD = Resolution.BuildResolvedEntries(ctxD, nil, ctxD.rollTypes.RESERVED)
assertEq(resolvedD[1].name, "Alice", "D: SR ignores tiebreaker (alphabetical)")

-- --- Case E: BuildResolution sets resolvedByTiebreaker flag ---
local resolvedE = Resolution.BuildResolvedEntries(ctxB, nil, ctxB.rollTypes.MAINSPEC)
local resolution = Resolution.BuildResolution(ctxB, resolvedE, false)
assertEq(resolution.resolvedByTiebreaker, true, "E: flag set")
assertEq(resolution.tiebreakerWinnerName, "Bob", "E: winner name")
assertEq(resolution.tiebreakerWinnerCount, 0, "E: winner count")
assertEq(resolution.tiebreakerRunnerUpCount, 2, "E: runner-up count")

-- --- Case F: no roll tie at all → flag absent ---
local ctxF = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 0, Bob = 0 },
    responses = {
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 100 },
        { name = "Bob", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 50 },
    },
})
local resolvedF = Resolution.BuildResolvedEntries(ctxF, nil, ctxF.rollTypes.MAINSPEC)
local resolutionF = Resolution.BuildResolution(ctxF, resolvedF, false)
assertEq(resolutionF.resolvedByTiebreaker, nil, "F: no roll tie → flag absent")

if failures == 0 then
    print("OK")
else
    print(string.format("FAILED %d assertion(s)", failures))
    os.exit(1)
end
