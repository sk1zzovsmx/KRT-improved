# Plus-one Tie-breaker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a runtime-configurable MS-count tie-breaker that resolves roll ties automatically without triggering a reroll whenever a distinguishing criterion is available. Default OFF.

**Architecture:** Extend existing Services/Rolls/Resolution comparator with a 4th sort key sourced from a new cross-raid read-only query in Services/Raid/Counts. Feature gated by `addon.options.tiebreakerMSCount` and exposed via a new Config panel. UI shows MS count only on tied rows. Chat announces when the tie-break resolves automatically.

**Tech Stack:** Lua 5.1 (WoW 3.3.5a client), KRT in-house module system, SavedVariables for persistence, pure-Lua standalone tests in `tests/*_spec.lua`.

**Spec:** [docs/superpowers/specs/2026-04-21-plus-one-tiebreaker-design.md](../specs/2026-04-21-plus-one-tiebreaker-design.md)

---

## Pre-flight notes for the engineer

1. **Pre-commit hook regenerates docs**: KRT's `tools/pre-commit.ps1` regenerates `docs/TREE.md`, `docs/FUNCTION_REGISTRY.csv`, and sibling catalogs on each commit. If a commit fails with "API catalogs are stale", re-stage the regenerated files and retry:
   ```bash
   git add docs/TREE.md docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/API_REGISTRY.csv docs/API_REGISTRY_PUBLIC.csv docs/API_REGISTRY_INTERNAL.csv docs/API_NOMENCLATURE_CENSUS.md
   git commit -C HEAD   # or retry the original -m
   ```
2. **No interactive commits**: pass messages via heredoc, never amend.
3. **Lua 5.1 only**: no `goto`, no integer division `//`, no bitops outside LuaBitOp. Keep modules self-contained inside their `do … end` blocks (follow existing style).
4. **Run tests before each commit**: `lua tests/<new_spec>.lua` should print `OK` (or the test file's equivalent pass-line).
5. **Lint**: run `luacheck` via the project's `s-lint` skill or `tools/krt.py luacheck`. Fix any new warnings introduced by your changes.
6. **Existing tie-reroll flow is untouched**: if MS counts also tie, the comparator's alphabetical fallback keeps `requiresManualResolution = true` and the existing reroll path remains reachable. Do not duplicate or replace that logic.

---

## File Structure

**Files to create:**

| Path | Responsibility |
|---|---|
| `tests/player_ms_count_spec.lua` | Unit tests for new `GetPlayerMSCount` / `GetMSCountsForNames` |
| `tests/resolution_tiebreaker_spec.lua` | Unit tests for `compareResolvedEntries`, `areResolvedEntriesTied`, `BuildResolution` with the new criterion |

**Files to modify:**

| Path | Change |
|---|---|
| `!KRT/Modules/C.lua` | Add `TIEBREAKER_SCOPE` enum |
| `!KRT/Init.lua` | Seed `addon.options.tiebreakerMSCount` defaults |
| `!KRT/Services/Raid/Counts.lua` | Add `GetPlayerMSCount`, `GetMSCountsForNames` |
| `!KRT/Localization/localization.en.lua` | Add all new `L.*` strings |
| `!KRT/Localization/DiagnoseLog.en.lua` | Add `Diag.D.LogRollsTiebreakerApplied` |
| `!KRT/Services/Rolls/Resolution.lua` | Extend `BuildResolvedEntries`, `compareResolvedEntries`, `areResolvedEntriesTied`, `BuildResolution`, `BuildRowCounterText` |
| `!KRT/Services/Rolls/Service.lua` | Inject new ctx getters |
| `!KRT/Services/Rolls/Display.lua` | Pass tiebreaker signal to `BuildRowCounterText` |
| `!KRT/Controllers/Master.lua` | Emit `L.ChatTiebreakResolved` when tie-break resolves |
| `!KRT/Widgets/Config.lua` | New config panel (enabled / scope / n) |
| `!KRT/CHANGELOG.md` | Add entry for the new feature |

---

## Task 1 — Constants and defaults

**Files:**
- Modify: `!KRT/Modules/C.lua` (add enum)
- Modify: `!KRT/Init.lua` (seed defaults inside the existing options-defaults section)

- [ ] **Step 1.1: Add `TIEBREAKER_SCOPE` enum to `!KRT/Modules/C.lua`**

Locate the existing `C.rollTypes` block (around line 22). After its closing `}`, add:

```lua
C.TIEBREAKER_SCOPE = {
    CURRENT = "CURRENT",
    LAST_N = "LAST_N",
    ALL = "ALL",
}
```

- [ ] **Step 1.2: Seed `addon.options.tiebreakerMSCount` defaults in `Init.lua`**

Find the block where other `addon.options.*` defaults are applied at load time (search for `addon.options` assignments near options normalization). Add after the last existing default:

```lua
if type(addon.options.tiebreakerMSCount) ~= "table" then
    addon.options.tiebreakerMSCount = {}
end
do
    local opt = addon.options.tiebreakerMSCount
    if type(opt.enabled) ~= "boolean" then opt.enabled = false end
    if opt.scope ~= "CURRENT" and opt.scope ~= "LAST_N" and opt.scope ~= "ALL" then
        opt.scope = "CURRENT"
    end
    local n = tonumber(opt.n)
    if not n or n < 1 or n > 50 then opt.n = 5 end
end
```

- [ ] **Step 1.3: Commit**

```bash
git add "!KRT/Modules/C.lua" "!KRT/Init.lua"
git commit -m "feat(tiebreaker): add TIEBREAKER_SCOPE enum and options defaults

Introduces addon.options.tiebreakerMSCount schema (enabled/scope/n).
Defaults to disabled. Forward-compatible validation clamps invalid
values without crashing.

Refs: docs/superpowers/specs/2026-04-21-plus-one-tiebreaker-design.md"
```

If the pre-commit hook updates `docs/TREE.md` or other catalogs, re-stage those and retry.

---

## Task 2 — Cross-raid MS-count API (data layer + tests)

**Files:**
- Modify: `!KRT/Services/Raid/Counts.lua`
- Create: `tests/player_ms_count_spec.lua`

- [ ] **Step 2.1: Write the failing test (`tests/player_ms_count_spec.lua`)**

```lua
-- Standalone unit tests for Services/Raid/Counts new APIs.
-- Run with: lua tests/player_ms_count_spec.lua
--
-- The test file stubs the minimal KRT_Raids / addon.Core surface and
-- loads Counts.lua in isolation.

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
            GetCurrentRaid = function() return currentRaidNum end,
            EnsureRaidById = function(num) return raids[num] end,
            EnsureRaidSchema = function() end,
            GetRaidStoreOrNil = function() return nil end,
        },
        Events = { Internal = {} },
    }
    addon.Core.GetFeatureShared = function()
        return { Events = addon.Events, Core = addon.Core }
    end
    return addon
end

-- Load the Counts module source and execute it against our harness.
local function loadCounts(addon)
    local f = assert(io.open("!KRT/Services/Raid/Counts.lua", "r"))
    local src = f:read("*a"); f:close()
    -- The module uses "local addon = select(2, ...)", so pass it via loader.
    local chunk = assert(loadstring(src, "Counts.lua"))
    setfenv(chunk, setmetatable({ select = function(n, ...)
        if n == 2 then return addon end
        return select(n, ...)
    end }, { __index = _G }))
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
assertEq(Raid:GetPlayerMSCount("Alice", { scope = "ALL" }), 3,     "Alice ALL")
assertEq(Raid:GetPlayerMSCount("Bob",   { scope = "ALL" }), 1,     "Bob ALL")
assertEq(Raid:GetPlayerMSCount("Carol", { scope = "LAST_N", n = 2 }), 3, "Carol LAST_N=2")
assertEq(Raid:GetPlayerMSCount("Carol", { scope = "LAST_N", n = 1 }), 3, "Carol LAST_N=1")
assertEq(Raid:GetPlayerMSCount("Ghost", { scope = "ALL" }), 0,     "Ghost absent")
assertEq(Raid:GetPlayerMSCount(nil,     { scope = "ALL" }), 0,     "nil name")
assertEq(Raid:GetPlayerMSCount("Alice", nil), 0,                   "nil opts defaults to CURRENT")

-- --- GetMSCountsForNames (batch) ---
local map = Raid:GetMSCountsForNames({ "Alice", "Bob", "Ghost" }, { scope = "ALL" })
assertEq(map.Alice, 3, "batch ALL Alice")
assertEq(map.Bob,   1, "batch ALL Bob")
assertEq(map.Ghost, 0, "batch ALL Ghost")

-- LAST_N must match the sum of individual calls
local singleAlice = Raid:GetPlayerMSCount("Alice", { scope = "LAST_N", n = 2 })
local batchAlice  = (Raid:GetMSCountsForNames({ "Alice" }, { scope = "LAST_N", n = 2 })).Alice
assertEq(batchAlice, singleAlice, "batch == single for LAST_N=2")

-- Empty names
local empty = Raid:GetMSCountsForNames({}, { scope = "ALL" })
assertEq(next(empty) == nil, true, "empty names returns empty map")

if failures == 0 then print("OK") else print(string.format("FAILED %d assertion(s)", failures)); os.exit(1) end
```

- [ ] **Step 2.2: Run test to verify it fails**

Run: `lua tests/player_ms_count_spec.lua`
Expected: error or FAILs (because `GetPlayerMSCount` / `GetMSCountsForNames` do not yet exist on the module).

- [ ] **Step 2.3: Implement `GetPlayerMSCount` in `!KRT/Services/Raid/Counts.lua`**

Inside the existing `do … end` block in `Counts.lua` (the one that declares `module = addon.Services.Raid`), add these methods after the existing `GetPlayerCount` definition:

```lua
local function iterateRaidsForScope(scope, n, callback)
    -- callback(raid, raidNum) invoked in newest-first order, up to scope limit.
    local raids = _G.KRT_Raids
    if type(raids) ~= "table" then return end
    -- Build ordered list of numeric raid keys (newest last by id).
    local ids = {}
    for k in pairs(raids) do
        local num = tonumber(k)
        if num then ids[#ids + 1] = num end
    end
    table.sort(ids, function(a, b) return a > b end)
    if scope == "CURRENT" then
        local current = Core.GetCurrentRaid()
        if not current then return end
        local raid = Core.EnsureRaidById(current)
        if raid then
            Core.EnsureRaidSchema(raid)
            callback(raid, current)
        end
        return
    end
    local limit = (scope == "LAST_N") and (tonumber(n) or 0) or #ids
    if limit <= 0 then return end
    local visited = 0
    for _, raidNum in ipairs(ids) do
        if visited >= limit then break end
        local raid = Core.EnsureRaidById(raidNum)
        if raid then
            Core.EnsureRaidSchema(raid)
            callback(raid, raidNum)
        end
        visited = visited + 1
    end
end

local function sumCountMSForName(raid, name)
    -- Mirrors GetLootCounterRows dedup: iterate newest (last) to oldest, first hit wins.
    if not (raid and raid.players and name) then return 0 end
    for i = #raid.players, 1, -1 do
        local p = raid.players[i]
        if p and p.name == name then
            return tonumber(p.countMS) or 0
        end
    end
    return 0
end

function module:GetPlayerMSCount(name, opts)
    if type(name) ~= "string" or name == "" then return 0 end
    local scope = (opts and opts.scope) or "CURRENT"
    local n = opts and opts.n
    local total = 0
    iterateRaidsForScope(scope, n, function(raid)
        total = total + sumCountMSForName(raid, name)
    end)
    return total
end

function module:GetMSCountsForNames(names, opts, out)
    local result = out or {}
    if out then twipe(result) end
    if type(names) ~= "table" or #names == 0 then return result end
    local nameSet = {}
    for _, nm in ipairs(names) do
        if type(nm) == "string" and nm ~= "" then
            nameSet[nm] = true
            result[nm] = 0
        end
    end
    if next(nameSet) == nil then return result end
    local scope = (opts and opts.scope) or "CURRENT"
    local n = opts and opts.n
    iterateRaidsForScope(scope, n, function(raid)
        if not (raid and raid.players) then return end
        local seen = {}
        for i = #raid.players, 1, -1 do
            local p = raid.players[i]
            if p and p.name and nameSet[p.name] and not seen[p.name] then
                seen[p.name] = true
                result[p.name] = (result[p.name] or 0) + (tonumber(p.countMS) or 0)
            end
        end
    end)
    return result
end
```

Note: `iterateRaidsForScope` and `sumCountMSForName` are file-local helpers; place them near the other `local function` helpers above the `do` block.

- [ ] **Step 2.4: Run test to verify it passes**

Run: `lua tests/player_ms_count_spec.lua`
Expected: `OK`

- [ ] **Step 2.5: Run luacheck on modified file**

Run: `tools/krt.py luacheck "!KRT/Services/Raid/Counts.lua"` (or the project's standard lint entrypoint).
Expected: no new warnings.

- [ ] **Step 2.6: Commit**

```bash
git add "!KRT/Services/Raid/Counts.lua" tests/player_ms_count_spec.lua
git commit -m "feat(raid): add GetPlayerMSCount / GetMSCountsForNames

Read-only cross-raid queries for MS loot count. Support CURRENT /
LAST_N / ALL scopes. Batch variant does a single KRT_Raids pass for
multiple names. Deduplication follows GetLootCounterRows convention
(newest occurrence in a raid.players list wins).

Unit tests in tests/player_ms_count_spec.lua."
```

Re-stage regenerated doc catalogs if the pre-commit hook touches them.

---

## Task 3 — Localization strings

**Files:**
- Modify: `!KRT/Localization/localization.en.lua`
- Modify: `!KRT/Localization/DiagnoseLog.en.lua`

- [ ] **Step 3.1: Add new `L` strings to `localization.en.lua`**

Append at the end of the file (keep existing ordering conventions — locate the section that groups config strings for the roll/loot feature):

```lua
L.CfgTiebreakerHeader       = "Plus-one tie-breaker"
L.CfgTiebreakerEnabled      = "Break ties by MS count"
L.CfgTiebreakerEnabledTip   = "When two rolls tie, the player with fewer MS wins over the selected scope wins. Applies to MS/OS/FREE (not SR). Player renames and server transfers are not merged."
L.CfgTiebreakerScopeLabel   = "Count scope"
L.CfgTiebreakerScopeCurrent = "Current raid only"
L.CfgTiebreakerScopeLastN   = "Last N raids"
L.CfgTiebreakerScopeAll     = "All saved raids"
L.CfgTiebreakerNLabel       = "N (raids)"
L.ChatTiebreakResolved      = "%s wins the tie on %s (MS: %d vs %d)"
L.RollRowMSCountFmt         = "(MS %d)"
```

- [ ] **Step 3.2: Add diagnostic log string to `DiagnoseLog.en.lua`**

Append in the `Diag.D` section (follow existing alphabetical or grouped layout):

```lua
Diag.D.LogRollsTiebreakerApplied = "[Rolls] Tiebreaker applied: scope=%s n=%d, tied=%s, counts=%s, resolved=%s"
```

- [ ] **Step 3.3: Commit**

```bash
git add "!KRT/Localization/localization.en.lua" "!KRT/Localization/DiagnoseLog.en.lua"
git commit -m "i18n(tiebreaker): add MS-count tie-breaker strings"
```

---

## Task 4 — Rolls `ctx` enrichment

**Files:**
- Modify: `!KRT/Services/Rolls/Service.lua`

- [ ] **Step 4.1: Add new getters to `ctx`**

Inside `Service.lua`, find the ctx-builder (search for existing assignments like `shouldShowLootCounterDuringMSRoll = function()`). Add these siblings near that block:

```lua
isTiebreakerByMSCountEnabled = function()
    local opt = addon.options and addon.options.tiebreakerMSCount
    return type(opt) == "table" and opt.enabled == true
end,
getTiebreakerMSCountOpts = function()
    local opt = (addon.options and addon.options.tiebreakerMSCount) or {}
    local scope = opt.scope
    if scope ~= "CURRENT" and scope ~= "LAST_N" and scope ~= "ALL" then
        scope = "CURRENT"
    end
    local n = tonumber(opt.n)
    if not n or n < 1 then n = 5 end
    return { scope = scope, n = n }
end,
getMSCountsForNames = function(names)
    local raid = Services.Raid
    if not (raid and raid.GetMSCountsForNames) then return {} end
    local ctxSelf = addon.Services.Rolls and addon.Services.Rolls._ctx  -- if exposed; otherwise inline the opts call
    local opts
    if ctxSelf and ctxSelf.getTiebreakerMSCountOpts then
        opts = ctxSelf.getTiebreakerMSCountOpts()
    else
        local o = (addon.options and addon.options.tiebreakerMSCount) or {}
        opts = { scope = o.scope or "CURRENT", n = tonumber(o.n) or 5 }
    end
    return raid:GetMSCountsForNames(names, opts)
end,
```

If the ctx is a table returned from a constructor function and `getMSCountsForNames` needs to call `getTiebreakerMSCountOpts` on the same ctx, wire it as a method that reads from the just-built ctx (adapt to existing pattern — the file has a clear precedent in how `shouldShowLootCounterDuringMSRoll` is wired).

- [ ] **Step 4.2: Commit**

```bash
git add "!KRT/Services/Rolls/Service.lua"
git commit -m "feat(rolls): expose tiebreaker getters on Rolls ctx"
```

---

## Task 5 — Resolution: tiebreaker fields on entries + comparator

**Files:**
- Modify: `!KRT/Services/Rolls/Resolution.lua`
- Create: `tests/resolution_tiebreaker_spec.lua`

- [ ] **Step 5.1: Write the failing test (`tests/resolution_tiebreaker_spec.lua`)**

```lua
-- Standalone tests for the new tiebreaker logic inside Resolution.
-- Tests exercise compareResolvedEntries and areResolvedEntriesTied via
-- the module's public helpers, plus BuildResolution's new fields.
--
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
    local src = f:read("*a"); f:close()
    local addon = {
        Services = { Rolls = {} },
        Core = {},
    }
    addon.Core.GetFeatureShared = function()
        return {
            rollTypes = { MAINSPEC = 1, OFFSPEC = 2, RESERVED = 3, DISENCHANT = 6, FREE = 5 },
            L = setmetatable({}, { __index = function(_, k) return k end }),
            Diag = { D = setmetatable({}, { __index = function(_, k) return function() return k end end }) },
        }
    end
    local chunk = assert(loadstring(src, "Resolution.lua"))
    setfenv(chunk, setmetatable({ select = function(n, ...)
        if n == 2 then return addon end
        return select(n, ...)
    end }, { __index = _G }))
    chunk("!KRT", addon)
    return addon.Services.Rolls._Resolution, addon
end

local Resolution = loadResolution()

-- Build a fake ctx matching what BuildResolvedEntries reads.
local function makeCtx(overrides)
    local ctx = {
        state = { responsesByPlayer = {} },
        rollTypes = { MAINSPEC = 1, OFFSPEC = 2, RESERVED = 3, FREE = 5 },
        responseStatus = { ROLL = "ROLL", PASS = "PASS", CANCELLED = "CANCELLED", ACTIVE = "ACTIVE", TIMED_OUT = "TIMED_OUT", INELIGIBLE = "INELIGIBLE" },
        reasonCodes = { NOT_IN_RAID = "NOT_IN_RAID" },
        isSelectableRollResponse = function(r) return r.status == "ROLL" and r.isEligible end,
        isPlusSystemEnabled = function() return false end,
        isSortAscending = function() return false end,
        getExpectedWinnerCount = function() return 1 end,
        isTiebreakerByMSCountEnabled = function() return overrides.tiebreakerOn end,
        getMSCountsForNames = function() return overrides.msCounts or {} end,
    }
    for _, entry in ipairs(overrides.responses or {}) do
        ctx.state.responsesByPlayer[entry.name] = entry
    end
    return ctx
end

-- --- Case A: tiebreaker OFF, two rolls tie → alphabetical fallback (regression invariant) ---
local ctxA = makeCtx({
    tiebreakerOn = false,
    responses = {
        { name = "Bob",   status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
    },
})
local resolvedA = Resolution.BuildResolvedEntries(ctxA, nil, ctxA.rollTypes.MAINSPEC)
assertEq(resolvedA[1].name, "Alice", "tiebreaker OFF → alphabetical")

-- --- Case B: tiebreaker ON, different MS counts → lower wins ---
local ctxB = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 2, Bob = 0 },
    responses = {
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
        { name = "Bob",   status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
    },
})
local resolvedB = Resolution.BuildResolvedEntries(ctxB, nil, ctxB.rollTypes.MAINSPEC)
assertEq(resolvedB[1].name, "Bob", "tiebreaker ON → fewer MS wins")

-- --- Case C: tiebreaker ON, same MS counts → alphabetical fallback ---
local ctxC = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 1, Bob = 1 },
    responses = {
        { name = "Bob",   status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 95 },
    },
})
local resolvedC = Resolution.BuildResolvedEntries(ctxC, nil, ctxC.rollTypes.MAINSPEC)
assertEq(resolvedC[1].name, "Alice", "same MS count → alphabetical fallback")

-- --- Case D: tiebreaker ON, SR bucket → tiebreaker does NOT apply ---
local ctxD = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 5, Bob = 0 },
    responses = {
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "SR", bestRoll = 95 },
        { name = "Bob",   status = "ROLL", isEligible = true, bucket = "SR", bestRoll = 95 },
    },
})
local resolvedD = Resolution.BuildResolvedEntries(ctxD, nil, ctxD.rollTypes.RESERVED)
-- SR with same roll and no SR plus → alphabetical (Alice first even though her msCount is higher)
assertEq(resolvedD[1].name, "Alice", "SR ignores tiebreaker (B1)")

-- --- Case E: BuildResolution sets resolvedByTiebreaker flag when tie-break breaks a roll tie ---
local resolvedE = Resolution.BuildResolvedEntries(ctxB, nil, ctxB.rollTypes.MAINSPEC)
local resolution = Resolution.BuildResolution(ctxB, resolvedE, false)
assertEq(resolution.resolvedByTiebreaker, true,  "E: flag set")
assertEq(resolution.tiebreakerWinnerName, "Bob", "E: winner name")
assertEq(resolution.tiebreakerWinnerCount, 0,    "E: winner count")
assertEq(resolution.tiebreakerRunnerUpCount, 2,  "E: runner-up count")

-- --- Case F: no roll tie at all → flag absent ---
local ctxF = makeCtx({
    tiebreakerOn = true,
    msCounts = { Alice = 0, Bob = 0 },
    responses = {
        { name = "Alice", status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 100 },
        { name = "Bob",   status = "ROLL", isEligible = true, bucket = "MS", bestRoll = 50 },
    },
})
local resolvedF = Resolution.BuildResolvedEntries(ctxF, nil, ctxF.rollTypes.MAINSPEC)
local resolutionF = Resolution.BuildResolution(ctxF, resolvedF, false)
assertEq(resolutionF.resolvedByTiebreaker, nil, "F: no roll tie → flag absent")

if failures == 0 then print("OK") else print(string.format("FAILED %d assertion(s)", failures)); os.exit(1) end
```

- [ ] **Step 5.2: Run test to verify it fails**

Run: `lua tests/resolution_tiebreaker_spec.lua`
Expected: FAIL on cases B, D, E (tiebreaker not yet implemented) and possibly others.

- [ ] **Step 5.3: Extend `BuildResolvedEntries` in `!KRT/Services/Rolls/Resolution.lua`**

Replace the existing body of `Resolution.BuildResolvedEntries` with:

```lua
function Resolution.BuildResolvedEntries(ctx, itemId, currentRollType)
    local _, state = assertContext(ctx)
    local rollTypes = ctx.rollTypes or feature.rollTypes
    local usePlus = currentRollType == rollTypes.RESERVED and itemId and ctx.isPlusSystemEnabled and ctx.isPlusSystemEnabled()
    local plusGetter = itemId and function(name)
        return ctx.getPlusForItem and ctx.getPlusForItem(itemId, name) or 0
    end or nil
    local wantLow = ctx.isSortAscending and ctx.isSortAscending() or false

    local tiebreakerEnabled = ctx.isTiebreakerByMSCountEnabled and ctx.isTiebreakerByMSCountEnabled() == true
    local msCountMap = nil
    if tiebreakerEnabled and ctx.getMSCountsForNames then
        local names = {}
        for name, response in pairs(state.responsesByPlayer) do
            if ctx.isSelectableRollResponse and ctx.isSelectableRollResponse(response) then
                names[#names + 1] = name
            end
        end
        if #names > 0 then
            msCountMap = ctx.getMSCountsForNames(names) or {}
        end
    end

    local resolved = {}
    for name, response in pairs(state.responsesByPlayer) do
        if ctx.isSelectableRollResponse and ctx.isSelectableRollResponse(response) then
            local bucket = response.bucket
            resolved[#resolved + 1] = {
                name = name,
                bucket = bucket,
                bucketPriority = Resolution.GetBucketPriority(ctx, bucket, currentRollType),
                plus = Resolution.GetResponsePlus(ctx, itemId, response, plusGetter),
                roll = tonumber(response.bestRoll) or 0,
                tiebreakerCount = (msCountMap and msCountMap[name]) or 0,
                tiebreakerApplies = tiebreakerEnabled and bucket ~= "SR" and bucket ~= "INELIGIBLE",
            }
        end
    end

    table.sort(resolved, function(a, b)
        return compareResolvedEntries(a, b, wantLow, usePlus)
    end)

    return resolved, usePlus, plusGetter
end
```

- [ ] **Step 5.4: Extend the `compareResolvedEntries` local function**

Replace the existing body:

```lua
local function compareResolvedEntries(a, b, wantLow, usePlus)
    if a.bucketPriority ~= b.bucketPriority then
        return a.bucketPriority < b.bucketPriority
    end
    if usePlus and a.bucket == "SR" and b.bucket == "SR" and a.plus ~= b.plus then
        return a.plus > b.plus
    end
    if a.roll ~= b.roll then
        return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
    end
    if a.tiebreakerApplies and b.tiebreakerApplies and a.tiebreakerCount ~= b.tiebreakerCount then
        return a.tiebreakerCount < b.tiebreakerCount
    end
    return tostring(a.name) < tostring(b.name)
end
```

- [ ] **Step 5.5: Extend the `areResolvedEntriesTied` local function**

Replace the existing body:

```lua
local function areResolvedEntriesTied(a, b, usePlus)
    if not (a and b) then return false end
    if a.bucketPriority ~= b.bucketPriority or a.bucket ~= b.bucket then
        return false
    end
    if usePlus and a.bucket == "SR" and a.plus ~= b.plus then
        return false
    end
    if a.roll == nil or a.roll ~= b.roll then
        return false
    end
    if a.tiebreakerApplies and b.tiebreakerApplies and a.tiebreakerCount ~= b.tiebreakerCount then
        return false
    end
    return true
end
```

- [ ] **Step 5.6: Extend `BuildResolution` to populate the new fields**

Wrap the existing `BuildResolution` logic with roll-tie detection. After the existing variable setup (`resolution`, `appliedCutoff`), before the `groupStart/groupEnd` computation, add:

```lua
-- Roll-tie detection BEFORE tiebreaker criterion differentiates entries.
local rollTiedNames = {}
if appliedCutoff > 0 and resolvedEntries[appliedCutoff] then
    local cutoffEntry = resolvedEntries[appliedCutoff]
    for i = 1, #resolvedEntries do
        local e = resolvedEntries[i]
        if e.bucketPriority == cutoffEntry.bucketPriority
            and e.bucket == cutoffEntry.bucket
            and e.roll == cutoffEntry.roll
            and (not usePlus or e.bucket ~= "SR" or e.plus == cutoffEntry.plus) then
            rollTiedNames[#rollTiedNames + 1] = e.name
        end
    end
end
```

At the very end of the function (just before `return resolution`), add:

```lua
if #rollTiedNames > 1 and not resolution.requiresManualResolution then
    -- Check that all rollTied entries share tiebreakerApplies and the winner really differs on tiebreakerCount.
    local winnerEntry
    for i = 1, #resolvedEntries do
        if resolvedEntries[i].name == rollTiedNames[1] then
            winnerEntry = resolvedEntries[i]; break
        end
    end
    if winnerEntry and winnerEntry.tiebreakerApplies then
        local winnerName = resolution.autoWinners[1] and resolution.autoWinners[1].name
        if winnerName then
            -- Runner-up count: smallest count among roll-tied others that is > winner's count.
            local winnerCount = nil
            local runnerUpCount = nil
            for _, n in ipairs(rollTiedNames) do
                for _, e in ipairs(resolvedEntries) do
                    if e.name == n then
                        if n == winnerName then
                            winnerCount = e.tiebreakerCount
                        else
                            if not runnerUpCount or e.tiebreakerCount < runnerUpCount then
                                runnerUpCount = e.tiebreakerCount
                            end
                        end
                        break
                    end
                end
            end
            if winnerCount ~= nil and runnerUpCount ~= nil and winnerCount ~= runnerUpCount then
                resolution.resolvedByTiebreaker = true
                resolution.tiebreakerWinnerName = winnerName
                resolution.tiebreakerWinnerCount = winnerCount
                resolution.tiebreakerRunnerUpCount = runnerUpCount
            end
        end
    end
end
```

- [ ] **Step 5.7: Run test to verify it passes**

Run: `lua tests/resolution_tiebreaker_spec.lua`
Expected: `OK`

- [ ] **Step 5.8: Run the older existing tests to verify no regression**

Run: `lua tests/release_stabilization_spec.lua` (should still pass as before).

- [ ] **Step 5.9: Lint**

Run the project's luacheck entrypoint on `!KRT/Services/Rolls/Resolution.lua`. Fix any new warnings.

- [ ] **Step 5.10: Commit**

```bash
git add "!KRT/Services/Rolls/Resolution.lua" tests/resolution_tiebreaker_spec.lua
git commit -m "feat(rolls): MS-count tie-breaker in Resolution comparator

Populate tiebreakerCount/tiebreakerApplies on each resolved entry and
use the former as the 4th sort key (only for non-SR buckets). Extend
BuildResolution with resolvedByTiebreaker / winner / runner-up fields
so the UI and chat announce can surface the outcome."
```

---

## Task 6 — UI row display (U2) inside Resolution

**Files:**
- Modify: `!KRT/Services/Rolls/Resolution.lua`
- Modify: `!KRT/Services/Rolls/Display.lua`

- [ ] **Step 6.1: Extend `BuildRowCounterText` signature**

Current signature: `Resolution.BuildRowCounterText(ctx, itemId, response, currentRollType, plusGetter)`. Extend with two trailing optional params:

```lua
function Resolution.BuildRowCounterText(ctx, itemId, response, currentRollType, plusGetter, isTied, tiebreakerCount)
```

At the **start** of the function body, before the existing SR branch, add:

```lua
-- U2: show (MS N) when the row belongs to a tied group and the tie-break is active.
if isTied and ctx.isTiebreakerByMSCountEnabled and ctx.isTiebreakerByMSCountEnabled()
    and response.bucket ~= "SR" and response.bucket ~= "INELIGIBLE" then
    local count = tonumber(tiebreakerCount) or 0
    local L = feature.L
    return (L.RollRowMSCountFmt or "(MS %d)"):format(count)
end
```

This early-return takes precedence over the existing SR/MS loot-counter logic, so tied rows always surface the new info.

- [ ] **Step 6.2: Update the caller in `Display.lua`**

In `Services/Rolls/Display.lua`, find the loop that builds row display models (search for `BuildRowCounterText`). The caller already has access to `tieGroupByName` and `resolvedEntries`. Compute `isTied` from `tieGroupByName[name] ~= nil` and `tiebreakerCount` by looking up the resolved entry for that row:

```lua
local entry = resolvedByName[response.name]
local isTied = tieGroupByName[response.name] ~= nil
local tbCount = entry and entry.tiebreakerCount or 0
local counterText = Resolution.BuildRowCounterText(ctx, itemId, response, currentRollType, plusGetter, isTied, tbCount)
```

If `resolvedByName` (name→entry map) does not already exist in Display.lua, build it once per model rebuild:

```lua
local resolvedByName = {}
for _, e in ipairs(resolvedEntries) do resolvedByName[e.name] = e end
```

- [ ] **Step 6.3: Manual sanity (optional — in-game)**

With feature ON and 2 tied rolls, the UI should render `(MS N)` next to each tied row.

- [ ] **Step 6.4: Commit**

```bash
git add "!KRT/Services/Rolls/Resolution.lua" "!KRT/Services/Rolls/Display.lua"
git commit -m "feat(rolls-ui): show (MS N) on tied rows when tie-breaker is active"
```

---

## Task 7 — Chat announce (U4) in Controllers/Master

**Files:**
- Modify: `!KRT/Controllers/Master.lua`

- [ ] **Step 7.1: Emit `L.ChatTiebreakResolved` when the feature resolves a tie**

In `Controllers/Master.lua`, find where the winner is confirmed after a successful (non-reroll) resolution path — the code near the existing `announceOnWin` handler and `handleAwardRequest` around [Master.lua:1553](!KRT/Controllers/Master.lua#L1553) or shortly before the award commit. Locate the branch where `resolution.requiresManualResolution == false` and the award proceeds; just before (or immediately after) the existing winner announce, add:

```lua
if resolution and resolution.resolvedByTiebreaker and addon.options.announceOnWin then
    local itemLink = Loot.GetItemLink and Loot.GetItemLink() or ""
    ChatApi.Announce(Chat, L.ChatTiebreakResolved:format(
        tostring(resolution.tiebreakerWinnerName or ""),
        tostring(itemLink),
        tonumber(resolution.tiebreakerWinnerCount) or 0,
        tonumber(resolution.tiebreakerRunnerUpCount) or 0
    ))
end
```

Guard against double-announce: ensure this is only emitted once per award commit (a simple local flag `tiebreakAnnounced` reset at the start of `handleAwardRequest` works). Follow the same channel (`ChatApi.Announce`) that `L.ChatTieReroll` uses — see [Master.lua:1977](!KRT/Controllers/Master.lua#L1977).

- [ ] **Step 7.2: Commit**

```bash
git add "!KRT/Controllers/Master.lua"
git commit -m "feat(announce): chat-announce MS-count tie-break resolutions

Emits L.ChatTiebreakResolved after the standard award path when the
resolution was decided by the plus-one tie-breaker. Gated by the
existing announceOnWin option."
```

---

## Task 8 — Config panel UI

**Files:**
- Modify: `!KRT/Widgets/Config.lua`

- [ ] **Step 8.1: Add the new controls**

In `Widgets/Config.lua`, find the area where other option groups are laid out (search for existing checkbox helper calls or `L.Cfg*` usages). Add a new section below the nearest relevant one (roll/loot options):

```lua
-- --- Plus-one tie-breaker group ---
local tbHeader = makeHeader(container, L.CfgTiebreakerHeader)  -- use whatever header helper the file already provides
tbHeader:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -20)

local tbEnabled = makeCheckbox(container, L.CfgTiebreakerEnabled, L.CfgTiebreakerEnabledTip,
    function() return addon.options.tiebreakerMSCount and addon.options.tiebreakerMSCount.enabled end,
    function(checked)
        addon.options.tiebreakerMSCount = addon.options.tiebreakerMSCount or {}
        addon.options.tiebreakerMSCount.enabled = checked and true or false
    end)
tbEnabled:SetPoint("TOPLEFT", tbHeader, "BOTTOMLEFT", 0, -8)

local tbScopeDropdown = makeDropdown(container, L.CfgTiebreakerScopeLabel, {
    { value = "CURRENT", label = L.CfgTiebreakerScopeCurrent },
    { value = "LAST_N",  label = L.CfgTiebreakerScopeLastN   },
    { value = "ALL",     label = L.CfgTiebreakerScopeAll     },
}, function() return (addon.options.tiebreakerMSCount or {}).scope or "CURRENT" end,
   function(v)
       addon.options.tiebreakerMSCount = addon.options.tiebreakerMSCount or {}
       addon.options.tiebreakerMSCount.scope = v
       tbNSlider:SetShown(v == "LAST_N")
   end)
tbScopeDropdown:SetPoint("TOPLEFT", tbEnabled, "BOTTOMLEFT", 0, -8)

local tbNSlider = makeSlider(container, L.CfgTiebreakerNLabel, 1, 50, 1,
    function() return (addon.options.tiebreakerMSCount or {}).n or 5 end,
    function(v)
        addon.options.tiebreakerMSCount = addon.options.tiebreakerMSCount or {}
        addon.options.tiebreakerMSCount.n = v
    end)
tbNSlider:SetPoint("TOPLEFT", tbScopeDropdown, "BOTTOMLEFT", 0, -8)
tbNSlider:SetShown(((addon.options.tiebreakerMSCount or {}).scope or "CURRENT") == "LAST_N")

-- Disable children when master checkbox is off.
local function syncEnabledState()
    local on = (addon.options.tiebreakerMSCount or {}).enabled == true
    tbScopeDropdown:SetEnabled(on)
    tbNSlider:SetEnabled(on)
end
tbEnabled:HookScript("OnClick", syncEnabledState)
syncEnabledState()
```

Adapt the helper names (`makeHeader`, `makeCheckbox`, `makeDropdown`, `makeSlider`) to whatever the file already uses. If those helpers don't exist, match the exact pattern (direct `CreateFrame` calls + `SetScript("OnClick", ...)`) used by the neighboring option groups.

- [ ] **Step 8.2: Commit**

```bash
git add "!KRT/Widgets/Config.lua"
git commit -m "feat(config): Plus-one tie-breaker panel

Exposes enabled / scope / n controls. Default OFF. Scope dropdown
shows Current raid / Last N raids / All saved raids; N slider is
visible only when scope = LAST_N."
```

---

## Task 9 — Diagnostic log hook

**Files:**
- Modify: `!KRT/Services/Rolls/Resolution.lua`

- [ ] **Step 9.1: Emit `LogRollsTiebreakerApplied` once per resolution**

In `Resolution.BuildResolution`, after the block that populates `resolvedByTiebreaker` (or at the end of the function), add:

```lua
if resolution.resolvedByTiebreaker and isDebugEnabled() then
    local function namesJoin(list)
        return table.concat(list or {}, ",")
    end
    -- Build counts string: "A=0,B=2"
    local counts = {}
    for _, n in ipairs(rollTiedNames) do
        for _, e in ipairs(resolvedEntries) do
            if e.name == n then
                counts[#counts + 1] = string.format("%s=%d", n, e.tiebreakerCount)
                break
            end
        end
    end
    local opts = ctx.getTiebreakerMSCountOpts and ctx.getTiebreakerMSCountOpts() or { scope = "?", n = 0 }
    addon:debug(Diag.D.LogRollsTiebreakerApplied:format(
        tostring(opts.scope),
        tonumber(opts.n) or 0,
        namesJoin(rollTiedNames),
        table.concat(counts, ","),
        tostring(resolution.tiebreakerWinnerName)
    ))
end
```

- [ ] **Step 9.2: Commit**

```bash
git add "!KRT/Services/Rolls/Resolution.lua"
git commit -m "chore(rolls): debug log on tie-break resolution"
```

---

## Task 10 — CHANGELOG

**Files:**
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 10.1: Add an Unreleased entry**

At the top of the Unreleased/next section, add:

```markdown
### Added
- Plus-one tie-breaker: optional tie-break that resolves roll ties by
  favoring players with fewer MS wins over a configurable scope
  (current raid / last N raids / all saved raids). Default OFF. Shows
  `(MS N)` next to tied rows during roll windows and announces the
  outcome in chat when `announceOnWin` is enabled. Does not apply to
  SR bucket resolutions.
```

- [ ] **Step 10.2: Commit**

```bash
git add "!KRT/CHANGELOG.md"
git commit -m "docs(changelog): plus-one tie-breaker entry"
```

---

## Task 11 — End-to-end manual verification

**Files:** none (runtime checks in-game).

- [ ] **Step 11.1: Default load**

/reload. Confirm the Config panel shows the new group with `enabled` unchecked, dropdown/slider disabled. Perform a normal roll with a tied result — flow identical to pre-feature (Reroll button appears, etc).

- [ ] **Step 11.2: Enable + CURRENT**

Enable, set scope = CURRENT. Ensure two raid members have different `countMS` in the current raid (awarding one MS item via the normal flow is the simplest way). Start a roll, force a tie (`/roll 95` from both test characters if feasible, or use the macro approach used during prior testing). Confirm:
- No Reroll button; the winner is the player with fewer MS.
- `(MS N)` appears next to both tied rows.
- Chat announces `"<winner> wins the tie on <item> (MS: <w> vs <r>)"`.

- [ ] **Step 11.3: LAST_N = 2**

Set scope = LAST_N, n = 2. Force a tie where a member's MS wins come partly from the 3rd-newest raid. Confirm the older raid does NOT contribute to the count.

- [ ] **Step 11.4: ALL**

Set scope = ALL. Confirm count matches sum across every saved raid.

- [ ] **Step 11.5: Toggle mid-session**

During a live roll, flip `enabled` OFF → ON (or vice versa). Next resolution must reflect the new state.

- [ ] **Step 11.6: SR tie**

With feature ON, force an SR tie (same plus, same roll). Confirm the feature does NOT decide — alphabetical fallback or existing reroll path kicks in.

- [ ] **Step 11.7: All-equal counts**

With feature ON, force a roll tie where all tied players have equal MS counts. Confirm the existing reroll flow runs (Reroll button + `L.ChatTieReroll` announce).

- [ ] **Step 11.8: 3-way tie resolved**

With 3 tied players and distinct MS counts, confirm the chat announce shows the winner's count vs the next-best (lowest non-winner) count.

- [ ] **Step 11.9: Diagnostic log**

With `/krt debug on`, observe a single `[Rolls] Tiebreaker applied: …` line per resolution that uses the criterion. Confirm no log spam on normal rolls.

- [ ] **Step 11.10: Corrupted options**

Edit `KRT_Options.tiebreakerMSCount.scope = "BOGUS"` in the SavedVariables file, reload. Confirm fallback to CURRENT, no error spam.

---

## Self-Review notes

- [x] Spec coverage: every section (goals, architecture, decisions, API, data flow, error handling, config, testing) is mapped to at least one task. Manual checklist from spec §11 maps 1:1 to Task 11 steps.
- [x] No placeholders: every code step shows the code to write. No "TBD" / "add appropriate" / "similar to".
- [x] Type consistency: `tiebreakerMSCount` option shape, `TIEBREAKER_SCOPE` enum values ("CURRENT"/"LAST_N"/"ALL"), and `resolution.tiebreaker*` field names used consistently across tasks.
- [x] Test coverage: new unit specs cover the new query API (Task 2) and the new comparator + resolution fields (Task 5). Regression invariant (feature OFF ≡ pre-change behavior) tested explicitly.
- [x] Commit cadence: 10 commits total, each self-contained and individually revertable.
