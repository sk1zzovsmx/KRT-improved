# Wave Q3 Raid State getRaidQueries Owner Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the final memoized `getRaidQueries` owner wrapper from
`!KRT/Services/Raid/State.lua`.

**Architecture:** Keep Q3 scoped to Raid State boss-query helpers. Replace the cached
query wrapper with the optional Database query facade at use time, preserving boss context,
loot-source, roll-session, and boss dedupe behavior. Q3 should close the remaining
`getRaidQueries` memoized wrapper backlog lane.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT module registry, repo-local
Lua test harness.

---

## Classification

`complex-orchestrated`.

Reasons:

- The change touches `!KRT/Services/Raid/State.lua`, a runtime service boundary.
- The helper feeds boss context, loot-source attribution, roll-session boss recovery, and
  boss dedupe paths.
- Tests, backlog, and generated function catalogs are expected to change.
- The task needs mapping, TDD, implementation, review, and verification.

Use the project delegated workflow:

1. Parent maps and plans.
2. `code-mapper` confirms exact callers and branch behavior.
3. `spark_implementer` applies only the approved minimal patch.
4. Parent reviews the final diff, corrects if needed, and runs final gates.

## File Structure

Expected runtime file:

- Modify: `!KRT/Services/Raid/State.lua`

Expected tests:

- Create: `tests/audit_cleanup_wave_q3_raid_state_get_raid_queries_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`

Expected docs and generated files:

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/FN_CLUSTERS.md`
- Modify: `docs/TREE.md` if the new test/plan files or generated tree require it
- Create: `docs/superpowers/plans/2026-06-14-audit-cleanup-wave-q3-raid-state-get-raid-queries-owner-group.md`

Do not modify:

- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Database/DBRaidQueries.lua`
- `!KRT/!KRT.toc`
- SavedVariables schema or migrations
- XML files

## Current Map

`!KRT/Services/Raid/State.lua` currently owns the last memoized wrapper:

```lua
local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil

local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end
```

The wrapper is used by four private helpers:

```lua
local function findBossByNid(raid, bossNid)
    local queries = getRaidQueries()
    if queries and queries.FindBossByNid then
        return queries:FindBossByNid(raid, bossNid)
    end
    return nil
end

local function findBossByName(raid, bossName)
    local queries = getRaidQueries()
    if queries and queries.FindBossByName then
        return queries:FindBossByName(raid, bossName)
    end
    return nil
end

local function findBossBySourceNpcId(raid, sourceNpcId)
    local queries = getRaidQueries()
    if queries and queries.FindBossBySourceNpcId then
        return queries:FindBossBySourceNpcId(raid, sourceNpcId)
    end
    return nil
end

local function findBossBySourceKey(raid, sourceKey)
    local queries = getRaidQueries()
    if queries and queries.FindBossBySourceKey then
        return queries:FindBossBySourceKey(raid, sourceKey)
    end
    return nil
end
```

Important call paths include:

- `findBossByNid` feeds loot-window context validation, roll-session boss recovery,
  and active loot source reconstruction.
- `findBossByName` feeds unit/death-context fallback and loot-source boss creation.
- `findBossBySourceNpcId` feeds unit context and static loot-source dedupe.
- `findBossBySourceKey` feeds static loot-source dedupe.

Q3 should keep the explicit `Database/DBRaidQueries` registry dependency in
`!KRT/Services/Raid/State.lua`. The dependency keeps load-order intent clear and matches
Q1/Q2.

The test harness supports `h:load("!KRT/Services/Raid.lua")` as a compatibility alias that
loads the split Raid service files. That alias is test-only; production load order is
`!KRT/!KRT.toc`.

## Task 0: Mapping Gate

**Files:**

- Read: `!KRT/Services/Raid/State.lua`
- Read: `!KRT/Services/Loot/State.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Dispatch `code-mapper` read-only**

Ask the mapper to confirm:

```text
1. The local `getRaidQueries()` wrapper in Raid State has exactly four direct callers:
   `findBossByNid`, `findBossByName`, `findBossBySourceNpcId`, and `findBossBySourceKey`.
2. Those four helpers are private to `!KRT/Services/Raid/State.lua`.
3. The helper outputs feed boss context, loot source, and session recovery.
4. `Database/DBRaidQueries` should stay as an explicit registry dependency for Q3.
5. The smallest behavior test should prove late `Database.GetRaidQueriesOrNil` lookup after
   `h:load("!KRT/Services/Raid.lua")`.
```

- [ ] **Step 2: Stop on scope conflict**

If the mapper finds cross-file callers, a need to change `DBRaidQueries`, or a load-order
dependency problem, stop and revise this plan before implementation.

## Task 1: Add Source Contract Test

**Files:**

- Create: `tests/audit_cleanup_wave_q3_raid_state_get_raid_queries_spec.lua`
- Read: `!KRT/Services/Raid/State.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Create the failing source contract test**

Create this file:

```lua
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
assertNotContains(
    source,
    "local function getRaidQueries()",
    "Raid State should not keep a local getRaidQueries wrapper"
)
assertNotContains(
    source,
    "Database.GetRaidQueries and Database.GetRaidQueries()",
    "Raid State should not use legacy lazy bootstrap cache"
)
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
assertContains(
    releaseSpec,
    'test("raid state resolves loot session boss through current query facade", function()',
    "release regression must cover current query facade"
)
assertContains(backlog, "Wave Q3 completed Raid State owner group", "backlog should record Q3 completion")
assertNotContains(remainingWrappers, "`!KRT/Services/Raid/State.lua`", "Raid State should leave remaining wrapper list")
assertContains(remainingWrappers, "None.", "remaining wrapper list should be closed")

print("audit cleanup wave Q3 Raid State getRaidQueries contract passed")
```

- [ ] **Step 2: Run the source contract test and verify RED**

Run:

```powershell
lua tests/audit_cleanup_wave_q3_raid_state_get_raid_queries_spec.lua
```

Expected before implementation:

```text
Raid State should use the optional query facade
```

or another expected failure caused by the old local cache/backlog state.

## Task 2: Add Behavior Regression Test

**Files:**

- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add a targeted late-facade test near existing Raid State boss-context tests**

Place this near existing loot boss-context or roll-session context tests:

```lua
test("raid state resolves loot session boss through current query facade", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 1, name = "OriginalBoss", time = 900 },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 2,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")

    local queryCalls = 0
    local currentQueries = {
        FindBossByNid = function(self, raid, bossNid)
            queryCalls = queryCalls + 1
            assertEqual(bossNid, 99, "expected query facade to inspect the remembered boss nid")
            return { bossNid = 99, name = "FacadeBoss" }
        end,
    }
    h.Database.GetRaidQueriesOrNil = function()
        return currentQueries
    end

    local Raid = h.addon.Services.Raid
    Raid:SetBossContextForLootSession(1, "ROLL:Q3", 99, 60)

    local bossNid = Raid:FindAndRememberBossContextForLootSession(1, "ROLL:Q3", {
        ttlSeconds = 60,
    })

    assertEqual(bossNid, 99, "expected session lookup to use current query facade")
    assertEqual(queryCalls, 1, "expected current query facade to be called once")
end)
```

- [ ] **Step 2: Run the behavior test and verify RED**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected before implementation:

```text
[TEST] raid state resolves loot session boss through current query facade
  FAIL: expected session lookup to use current query facade: expected=99 actual=0
```

This failure proves the old memoized cache captured the initial `DBRaidQueries` object and did
not use the late facade override.

## Task 3: Minimal Runtime Patch

**Files:**

- Modify: `!KRT/Services/Raid/State.lua`

- [ ] **Step 1: Remove the local cache wrapper**

Delete:

```lua
local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil

local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end
```

- [ ] **Step 2: Replace each boss-query helper lookup**

Change `findBossByNid` to:

```lua
local function findBossByNid(raid, bossNid)
    local queries = Database.GetRaidQueriesOrNil and Database.GetRaidQueriesOrNil()
    if queries and queries.FindBossByNid then
        return queries:FindBossByNid(raid, bossNid)
    end
    return nil
end
```

Change `findBossByName` to:

```lua
local function findBossByName(raid, bossName)
    local queries = Database.GetRaidQueriesOrNil and Database.GetRaidQueriesOrNil()
    if queries and queries.FindBossByName then
        return queries:FindBossByName(raid, bossName)
    end
    return nil
end
```

Change `findBossBySourceNpcId` to:

```lua
local function findBossBySourceNpcId(raid, sourceNpcId)
    local queries = Database.GetRaidQueriesOrNil and Database.GetRaidQueriesOrNil()
    if queries and queries.FindBossBySourceNpcId then
        return queries:FindBossBySourceNpcId(raid, sourceNpcId)
    end
    return nil
end
```

Change `findBossBySourceKey` to:

```lua
local function findBossBySourceKey(raid, sourceKey)
    local queries = Database.GetRaidQueriesOrNil and Database.GetRaidQueriesOrNil()
    if queries and queries.FindBossBySourceKey then
        return queries:FindBossBySourceKey(raid, sourceKey)
    end
    return nil
end
```

- [ ] **Step 3: Keep registry dependency unchanged**

Verify this dependency remains:

```lua
"Database/DBRaidQueries",
```

Do not change boss-context, loot-source, `AddBoss`, or `GetLoot` logic.

## Task 4: Backlog Update

**Files:**

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Close remaining memoized wrapper list**

Under `### Wave 5 follow-up: remaining getRaidQueries wrappers`, replace:

```markdown
Remaining memoized wrappers:
- `!KRT/Services/Raid/State.lua`
```

with:

```markdown
Remaining memoized wrappers:
- None.
```

- [ ] **Step 2: Add Q3 completion note**

Add after the Q2 section:

```markdown
### Wave Q3: Raid State owner group

Wave Q3 completed Raid State owner group:
- `!KRT/Services/Raid/State.lua` moved the final cached boss query wrapper to
  `Database.GetRaidQueriesOrNil()` calls and kept the explicit
  `Database/DBRaidQueries` registry dependency.

Remaining owner groups:
- None.
```

- [ ] **Step 3: Fix Default Next Step**

In `## 7. Default Next Step`, replace:

```markdown
1. the remaining `getRaidQueries` owner group in `!KRT/Services/Raid/State.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
```

with:

```markdown
1. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
2. bootstrap follow-up in `!KRT/Init.lua` only if a later inventory proves a residual owner
```

## Task 5: Generated Docs Refresh

**Files:**

- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/FN_CLUSTERS.md`
- Modify: `docs/TREE.md` if changed by tooling

- [ ] **Step 1: Refresh function inventory and tree docs**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

- [ ] **Step 2: Review generated changes**

Expected:

- `docs/FUNCTION_REGISTRY.csv` no longer lists
  `!KRT/Services/Raid/State.lua` `getRaidQueries`.
- `docs/FN_CLUSTERS.md` no longer lists `getRaidQueries`.
- `docs/TREE.md` lists the new Q3 plan and audit test if generated.

If API census files only reorder unchanged API rows, do not keep unrelated churn.

## Task 6: Verification

**Files:**

- No edits.

- [ ] **Step 1: Run targeted tests**

Run:

```powershell
lua tests/audit_cleanup_wave_q3_raid_state_get_raid_queries_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected:

```text
audit cleanup wave Q3 Raid State getRaidQueries contract passed
294 or more targeted stabilization test(s) passed
module registry services source contract passed
module registry UI entrypoints source contract passed
```

- [ ] **Step 2: Run repo gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
git diff --check
```

Expected:

```text
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
Lua syntax check passed.
```

`git diff --check` must exit `0`. An EOL warning on generated CSVs is acceptable only if there
is no whitespace error output.

## Task 7: Parent Review

**Files:**

- Review all changed files.

- [ ] **Step 1: Confirm scope**

Verify:

- `!KRT/Services/Raid/State.lua` is the only runtime Lua file changed.
- `!KRT/Services/Raid/LootRecords.lua` is unchanged after Q2.
- `!KRT/Services/Loot/Service.lua` is unchanged after Q1.
- `Database/DBRaidQueries` remains an explicit Raid State dependency.
- No SavedVariables, TOC, XML, or user-facing behavior changed.

- [ ] **Step 2: Confirm RED/GREEN evidence**

Verify:

- The Q3 source contract test fails on pre-patch code.
- The Q3 behavior regression fails on pre-patch code.
- Both pass on the final patch.

- [ ] **Step 3: Stop before commit**

Do not commit until the user has completed the in-client WoW 3.3.5 smoke test and reports no
errors.

After smoke, commit with:

```powershell
git add --all
git commit -m "Remove Raid State query cache wrapper"
```

Expected pre-commit result:

```text
Pre-commit checks completed.
```

## Self-Review

- Spec coverage: Q3 covers the final `getRaidQueries` owner group in
  `!KRT/Services/Raid/State.lua`, including source contract, behavior regression, docs, generated
  catalogs, review, and smoke-gated commit.
- Placeholder scan: no placeholder tasks remain.
- Type consistency: the runtime patch keeps the existing helper signatures and method-call syntax.
