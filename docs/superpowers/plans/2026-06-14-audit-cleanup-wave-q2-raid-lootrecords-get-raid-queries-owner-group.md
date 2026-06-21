# Wave Q2 Raid LootRecords getRaidQueries Owner Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the memoized `getRaidQueries` owner wrapper from
`!KRT/Services/Raid/LootRecords.lua`.

**Architecture:** Keep Q2 scoped to the Raid LootRecords owner group. Replace the stale local
query cache with the current optional Database query facade while preserving held-loot and
roll-session lookup behavior. Leave the Raid State owner group for Q3.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT module registry, repo-local Lua
test harness.

---

## Classification

`complex-orchestrated`.

Reasons:

- The change touches `!KRT/Services/Raid/LootRecords.lua`, a runtime service boundary.
- The helper feeds held-loot and roll-session lookup behavior.
- Tests, backlog, and generated function catalogs are expected to change.
- The task needs mapping, TDD, implementation, review, and verification.

Use the project delegated workflow:

1. Parent maps and plans.
2. `code-mapper` confirms the exact call paths and branch behavior.
3. `spark_implementer` applies only the approved minimal patch.
4. Parent reviews the final diff, corrects if needed, and runs final gates.

## File Structure

Expected runtime file:

- Modify: `!KRT/Services/Raid/LootRecords.lua`

Expected tests:

- Create: `tests/audit_cleanup_wave_q2_raid_lootrecords_get_raid_queries_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`

Expected docs and generated files:

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/FN_CLUSTERS.md`
- Modify: `docs/TREE.md` if the new test/plan files or generated tree require it
- Create: `docs/superpowers/plans/2026-06-14-audit-cleanup-wave-q2-raid-lootrecords-get-raid-queries-owner-group.md`

Do not modify:

- `!KRT/Services/Raid/State.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Database/DBRaidQueries.lua`
- `!KRT/!KRT.toc`
- SavedVariables schema or migrations
- XML files

## Current Map

`!KRT/Services/Raid/LootRecords.lua` currently owns:

```lua
local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil

local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end
```

The wrapper is used by:

```lua
local function resolveLootLooterName(raid, entry)
    local queries = getRaidQueries()
    if queries and queries.ResolveLootLooterName then
        return queries:ResolveLootLooterName(raid, entry)
    end
    return nil
end
```

`resolveLootLooterName(raid, entry)` feeds:

- `module:GetHeldLootNid(itemLink, raidNum, holderName, bossNid)`
- `module:GetLootNidByRollSessionId(rollSessionId, raidNum, holderName, bossNid)`

Q2 should not remove the explicit `Database/DBRaidQueries` registry dependency. That dependency
keeps load-order intent clear and matches the Q1 decision for Loot Service.

## Task 0: Mapping Gate

**Files:**

- Read: `!KRT/Services/Raid/LootRecords.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Dispatch `code-mapper` read-only**

Ask the mapper to confirm:

```text
1. The local `getRaidQueries()` wrapper in LootRecords has only one direct caller:
   `resolveLootLooterName(raid, entry)`.
2. `resolveLootLooterName` feeds both held-loot lookup and roll-session lookup.
3. `Database/DBRaidQueries` should stay as an explicit registry dependency for Q2.
4. `!KRT/Services/Raid/State.lua` remains out of scope for Q2.
5. The smallest behavior test should prove late `Database.GetRaidQueriesOrNil` lookup after
   `!KRT/Services/Raid.lua` has loaded.
```

- [ ] **Step 2: Stop on scope conflict**

If the mapper finds that removing the registry dependency is required, stop and revise this plan
before implementation. Do not fold dependency graph cleanup into Q2.

## Task 1: Add Source Contract Test

**Files:**

- Create: `tests/audit_cleanup_wave_q2_raid_lootrecords_get_raid_queries_spec.lua`
- Read: `!KRT/Services/Raid/LootRecords.lua`
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

local source = read("!KRT/Services/Raid/LootRecords.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local remainingWrappers = sliceBetween(backlog, "Remaining memoized wrappers:", "- direct callers remain")

assertContains(source, "Database.GetRaidQueriesOrNil", "LootRecords should use the optional query facade")
assertNotContains(source, "local RaidQueries =", "LootRecords should not keep cached RaidQueries state")
assertNotContains(source, "local function getRaidQueries()", "LootRecords should not keep getRaidQueries")
assertNotContains(source, "Database.GetRaidQueries and Database.GetRaidQueries()", "old bootstrap cache remains")
assertNotContains(source, "Database.GetRaidQueries()", "LootRecords should not call Database.GetRaidQueries")
assertContains(source, "local function resolveLootLooterName(raid, entry)", "resolver signature changed")
assertContains(source, ":ResolveLootLooterName(raid, entry)", "query resolver call is missing")
assertContains(source, "function module:GetHeldLootNid", "held-loot lookup should stay in LootRecords")
assertContains(source, "function module:GetLootNidByRollSessionId", "roll-session lookup should stay in LootRecords")
assertContains(source, '"Database/DBRaidQueries"', "LootRecords must keep explicit query dependency")
assertContains(
    releaseSpec,
    'test("raid loot records resolve roll session looter through current query facade", function()',
    "release regression must cover current facade usage"
)
assertContains(backlog, "Wave Q2 completed Raid LootRecords owner group", "backlog should record Q2")
assertNotContains(remainingWrappers, "`!KRT/Services/Raid/LootRecords.lua`", "LootRecords should leave remaining list")
assertContains(remainingWrappers, "`!KRT/Services/Raid/State.lua`", "Raid State should remain for Q3")

print("audit cleanup wave Q2 Raid LootRecords getRaidQueries contract passed")
```

- [ ] **Step 2: Run the source contract test and verify RED**

Run:

```powershell
lua tests/audit_cleanup_wave_q2_raid_lootrecords_get_raid_queries_spec.lua
```

Expected before implementation:

```text
FAIL: LootRecords should use the optional query facade
```

or another expected failure caused by the old local cache/backlog state.

## Task 2: Add Behavior Regression Test

**Files:**

- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add a targeted late-facade test near existing loot-record lookup tests**

Place this near the existing trade-only roll-session lookup test or near the held-loot lookup
tests:

```lua
test("raid loot records resolve roll session looter through current query facade", function()
    local h = newHarness()
    local link = h.registerItem(9166, "LootRecordFacadeBlade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "OtherRaider", countMS = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {
                {
                    lootNid = 1,
                    itemId = 9166,
                    itemName = "LootRecordFacadeBlade",
                    itemLink = link,
                    itemString = h.addon.Item.GetItemStringFromLink(link),
                    looterNid = 55,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 88,
                    rollSessionId = "ROLL:Q2",
                    bossNid = 10,
                    targetLooter = "TargetRaider",
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 2,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")

    local queryCalls = 0
    local currentQueries = {
        ResolveLootLooterName = function(self, raid, entry)
            queryCalls = queryCalls + 1
            assertEqual(entry.lootNid, 1, "expected query facade to inspect seeded loot")
            return entry.targetLooter
        end,
    }
    h.Database.GetRaidQueriesOrNil = function()
        return currentQueries
    end

    local Raid = h.addon.Services.Raid
    local lootNid = Raid:GetLootNidByRollSessionId("ROLL:Q2", 1, "TargetRaider", 10)

    assertEqual(lootNid, 1, "expected roll-session lookup to use current query facade")
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
[TEST] raid loot records resolve roll session looter through current query facade
  FAIL: expected roll-session lookup to use current query facade
```

This failure proves the old memoized cache captured the initial `DBRaidQueries` object and did not
use the late facade override.

## Task 3: Minimal Runtime Patch

**Files:**

- Modify: `!KRT/Services/Raid/LootRecords.lua`

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

- [ ] **Step 2: Replace the resolver lookup**

Change `resolveLootLooterName` to:

```lua
local function resolveLootLooterName(raid, entry)
    local queries = Database.GetRaidQueriesOrNil and Database.GetRaidQueriesOrNil()
    if queries and queries.ResolveLootLooterName then
        return queries:ResolveLootLooterName(raid, entry)
    end
    return nil
end
```

- [ ] **Step 3: Keep registry dependency unchanged**

Verify this dependency remains:

```lua
"Database/DBRaidQueries",
```

Do not change surrounding held-loot or roll-session lookup logic.

## Task 4: Backlog Update

**Files:**

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Update remaining memoized wrappers**

Under `### Wave 5 follow-up: remaining getRaidQueries wrappers`, remove:

```markdown
- `!KRT/Services/Raid/LootRecords.lua`
```

Leave:

```markdown
- `!KRT/Services/Raid/State.lua`
```

- [ ] **Step 2: Add Q2 completion note**

Add after the Q1 section:

```markdown
### Wave Q2: Raid LootRecords owner group

Wave Q2 completed Raid LootRecords owner group:
- `!KRT/Services/Raid/LootRecords.lua` moved from cached query wrappers to
  `Database.GetRaidQueriesOrNil()` calls and kept the explicit
  `Database/DBRaidQueries` registry dependency.

Remaining owner group:
- `!KRT/Services/Raid/State.lua`
```

- [ ] **Step 3: Fix Default Next Step**

In `## 7. Default Next Step`, replace the stale Loot recommendation with:

```markdown
1. the remaining `getRaidQueries` owner group in `!KRT/Services/Raid/State.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
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
  `!KRT/Services/Raid/LootRecords.lua` `getRaidQueries`.
- `docs/FN_CLUSTERS.md` still lists `getRaidQueries` only for
  `!KRT/Services/Raid/State.lua`.
- `docs/TREE.md` lists the new Q2 plan and audit test if generated.

If API census files only reorder unchanged API rows, do not keep unrelated churn.

## Task 6: Verification

**Files:**

- No edits.

- [ ] **Step 1: Run targeted tests**

Run:

```powershell
lua tests/audit_cleanup_wave_q2_raid_lootrecords_get_raid_queries_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected:

```text
audit cleanup wave Q2 Raid LootRecords getRaidQueries contract passed
293 or more targeted stabilization test(s) passed
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

`git diff --check` must exit `0`. An EOL warning on generated CSVs is acceptable only if there is
no whitespace error output.

## Task 7: Parent Review

**Files:**

- Review all changed files.

- [ ] **Step 1: Confirm scope**

Verify:

- `!KRT/Services/Raid/LootRecords.lua` is the only runtime Lua file changed.
- `!KRT/Services/Raid/State.lua` is unchanged.
- `Database/DBRaidQueries` remains an explicit LootRecords dependency.
- No SavedVariables, TOC, XML, or user-facing behavior changed.

- [ ] **Step 2: Confirm RED/GREEN evidence**

Verify:

- The Q2 source contract test fails on pre-patch code.
- The Q2 behavior regression fails on pre-patch code.
- Both pass on the final patch.

- [ ] **Step 3: Stop before commit**

Do not commit until the user has completed the in-client WoW 3.3.5 smoke test and reports no
errors.

After smoke, commit with:

```powershell
git add --all
git commit -m "Remove Raid LootRecords query cache wrapper"
```

Expected pre-commit result:

```text
Pre-commit checks completed.
```
