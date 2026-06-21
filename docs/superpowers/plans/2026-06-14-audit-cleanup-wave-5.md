# Audit Cleanup Wave 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Continue audit cleanup after Wave 4 by removing the Logger-owned memoized
`getRaidQueries` wrappers while preserving Logger behavior and module boundaries.

**Architecture:** Wave 5 uses the optional Database facade helper created in Wave 4:
`Database.GetRaidQueriesOrNil()`. The only runtime owner slice is Logger Store/Actions;
Database Syncer, Loot, and Raid memoized wrappers remain deferred for separate owner waves.

**Tech Stack:** World of Warcraft 3.3.5a, Interface 30300, Lua 5.1, KRT project workflow,
PowerShell repo tooling, Lua source-contract specs.

---

## Classification

Use the project `55to53` workflow.

- Classification: `complex-orchestrated`
- Reason: two runtime files change, Logger Store/Actions are shared service contracts, and
  Logger maintenance/edit behavior has release-stabilization coverage.
- Execution model: parent plans and reviews; `code-mapper` confirms the Logger owner slice
  first; `spark_implementer` applies the approved patch.
- Scope control: one owner group only. Do not refactor DB Syncer, Loot, or Raid wrappers.

## Branching

Start from the clean committed Wave 4 result.

```powershell
git checkout codex/audit-cleanup-wave-4-current
git status --short
git checkout -b codex/audit-cleanup-wave-5-current
```

Expected:

- `git status --short` has no output.
- The new branch is `codex/audit-cleanup-wave-5-current`.

If Wave 4 has already been merged into another integration branch before execution, stop and
update this Branching section with the exact base branch before editing.

Before editing:

```powershell
git status --short
lua tests\release_stabilization_spec.lua
```

Expected:

- `git status --short` has no output.
- `release_stabilization_spec.lua` exits `0`.

## Scope

Modify only:

- `tests/audit_cleanup_wave5_spec.lua`
- `!KRT/Services/Logger/Store.lua`
- `!KRT/Services/Logger/Actions.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

Generated docs may change after pre-commit hooks or explicit catalog refresh:

- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/API_NOMENCLATURE_CENSUS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_PUBLIC.csv`
- `docs/API_REGISTRY_INTERNAL.csv`
- `docs/TREE.md`

Do not modify in Wave 5:

- `!KRT/Libs/*`
- `!KRT/!KRT.toc`
- `!KRT/UI/*.xml`
- `!KRT/Database/DB.lua`
- `!KRT/Database/DBRaidQueries.lua`
- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Logger/View.lua`
- `!KRT/Services/Logger/Export.lua`
- `!KRT/Services/Logger/Helpers.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/State.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/CHANGELOG.md`, unless the implementation changes user-visible behavior

## Deferred Items

Keep these out of Wave 5:

- Any behavior change to `DB.RaidQueries` row projection.
- Any registry dependency changes for Logger Store or Logger Actions.
- Any conversion of `Database/DBSyncer.lua`, `Services/Loot/Service.lua`,
  `Services/Raid/State.lua`, or `Services/Raid/LootRecords.lua`.
- Any Logger View/Export follow-up.
- Any UI/XML cleanup.

---

### Task 1: Map Logger Store/Actions Query Ownership

**Files:** read-only

- `!KRT/Services/Logger/Store.lua`
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Database/DB.lua`
- `tests/release_stabilization_spec.lua`
- `tests/module_registry_services_spec.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Run the read-only mapper**

Use `code-mapper` with this prompt:

```text
Map Wave 5 Logger getRaidQueries cleanup. Do not edit files.

Read the Wave 5 files only. Report:
1. every Logger Store/Actions local getRaidQueries wrapper and whether it is memoized;
2. every method/function that consumes those wrappers;
3. whether Store/Actions can call Database.GetRaidQueriesOrNil() without changing registry deps;
4. the release-stabilization tests covering Logger Store/Actions behavior;
5. exact files that must stay out of this patch.

Do not propose broader cleanup. Keep the recommendation limited to Logger Store/Actions.
```

Expected mapper result:

- `Services/Logger/Store.lua` has one memoized cache and one consumer:
  `resolveLootLooterName`.
- `Services/Logger/Actions.lua` has one memoized cache and four consumers:
  `findBossByNid`, `findBossByName`, `findBossBySourceNpcId`, and
  `findBossBySourceKey`.
- Store/Actions already depend on `Database/DBRaidQueries`; Wave 5 must not change those
  registry dependency lists.
- `tests/release_stabilization_spec.lua` defines `Database.GetRaidQueriesOrNil` in the harness
  and loads `Database/DBRaidQueries.lua` before Logger Store/Actions in isolated loads.

- [ ] **Step 2: Parent gate**

Parent checks the mapper result. If the mapper recommends touching DB Syncer, Loot, Raid,
DBRaidQueries, or Logger View/Export, stop and revise the plan before implementation.

---

### Task 2: Add Wave 5 Source-Contract Harness

**Files:**

- Create: `tests/audit_cleanup_wave5_spec.lua`

- [ ] **Step 1: Create the initial failing source-contract test**

Create `tests/audit_cleanup_wave5_spec.lua` with this content:

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

local db = read("!KRT/Database/DB.lua")
local store = read("!KRT/Services/Logger/Store.lua")
local actions = read("!KRT/Services/Logger/Actions.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local releaseNeedle = "Database.GetRaidQueriesOrNil = function()"
local backlogNeedle = "Wave 5 follow-up: remaining `getRaidQueries` wrappers"

assertContains(db, "function Database.GetRaidQueriesOrNil()", "Wave 5 requires the Wave 4 optional query facade")
assertContains(store, "Database.GetRaidQueriesOrNil()", "Logger Store should use the Database query facade")
assertContains(actions, "Database.GetRaidQueriesOrNil()", "Logger Actions should use the Database query facade")
assertNotContains(store, "local RaidQueries =", "Logger Store should not keep a memoized RaidQueries cache")
assertNotContains(actions, "local RaidQueries =", "Logger Actions should not keep a memoized RaidQueries cache")
assertNotContains(store, "local function getRaidQueries()", "Logger Store should not keep a local query wrapper")
assertNotContains(actions, "local function getRaidQueries()", "Logger Actions should not keep a local query wrapper")
assertContains(store, "\"Database/DBRaidQueries\"", "Logger Store registry dependency should stay explicit")
assertContains(actions, "\"Database/DBRaidQueries\"", "Logger Actions registry dependency should stay explicit")
assertContains(releaseSpec, releaseNeedle, "release harness should provide the query facade")
assertContains(backlog, backlogNeedle, "backlog should record remaining wrappers after Logger cleanup")

print("audit cleanup wave5 source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

```powershell
lua tests\audit_cleanup_wave5_spec.lua
```

Expected failure before Task 3:

```text
Logger Store should use the Database query facade
```

---

### Task 3: Convert Logger Store

**Files:**

- `!KRT/Services/Logger/Store.lua`

- [ ] **Step 1: Remove the local cache and wrapper**

In `!KRT/Services/Logger/Store.lua`, remove this file-scope cache:

```lua
local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil
```

Remove the private helper block:

```lua
local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end
```

- [ ] **Step 2: Replace the only Store query lookup**

In `resolveLootLooterName`, replace:

```lua
local queries = getRaidQueries()
```

with:

```lua
local queries = Database.GetRaidQueriesOrNil()
```

Expected method after the local query line:

```lua
resolveLootLooterName = function(raid, loot)
    local queries = Database.GetRaidQueriesOrNil()
    if queries and queries.ResolveLootLooterName then
        return queries:ResolveLootLooterName(raid, loot)
    end
    return nil
end
```

- [ ] **Step 3: Preserve registry dependencies**

Do not change the `registry.AddModule("Services/Logger/Store", ...)` dependency list.

Verify:

```powershell
rg -n `
  "local RaidQueries|local function getRaidQueries|Database.GetRaidQueriesOrNil|Database/DBRaidQueries" `
  !KRT\Services\Logger\Store.lua
```

Expected:

- One `Database.GetRaidQueriesOrNil()` match.
- One `"Database/DBRaidQueries"` match in the registry dependency list.
- No `local RaidQueries` match.
- No `local function getRaidQueries` match.

---

### Task 4: Convert Logger Actions

**Files:**

- `!KRT/Services/Logger/Actions.lua`

- [ ] **Step 1: Remove the local cache and wrapper**

In `!KRT/Services/Logger/Actions.lua`, remove this file-scope cache:

```lua
local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil
```

Remove the private helper block:

```lua
local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end
```

- [ ] **Step 2: Replace the Actions query lookups**

Replace each:

```lua
local queries = getRaidQueries()
```

with:

```lua
local queries = Database.GetRaidQueriesOrNil()
```

Expected affected functions:

- `findBossByNid`
- `findBossByName`
- `findBossBySourceNpcId`
- `findBossBySourceKey`

- [ ] **Step 3: Preserve registry dependencies**

Do not change the `registry.AddModule("Services/Logger/Actions", ...)` dependency list.

Verify:

```powershell
rg -n `
  "local RaidQueries|local function getRaidQueries|Database.GetRaidQueriesOrNil|Database/DBRaidQueries" `
  !KRT\Services\Logger\Actions.lua
```

Expected:

- Four `Database.GetRaidQueriesOrNil()` matches.
- One `"Database/DBRaidQueries"` match in the registry dependency list.
- No `local RaidQueries` match.
- No `local function getRaidQueries` match.

---

### Task 5: Update Cleanup Backlog

**Files:**

- `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Replace the Wave 4 follow-up section heading and body**

Replace:

```text
### Wave 4 follow-up: remaining `getRaidQueries` wrappers
```

with:

```text
### Wave 5 follow-up: remaining `getRaidQueries` wrappers

Wave 4 centralized optional dynamic query access through
`Database.GetRaidQueriesOrNil()` in `!KRT/Database/DB.lua` and removed dynamic wrappers from
Logger View/Export.

Wave 5 removed the Logger-owned memoized query caches from:
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Services/Logger/Store.lua`

Remaining memoized wrappers:
- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Raid/State.lua`
- direct callers remain in `!KRT/Controllers/Logger.lua`, `!KRT/Database/DB.lua`,
  and `!KRT/Database/DBManager.lua`.

Required before any later implementation:
- Map each remaining owner separately.
- Confirm whether late `Database.GetRaidQueries` assignment still needs cache refresh behavior.
- Split the remaining cleanup into one owner group per task.
```

- [ ] **Step 2: Run the source-contract test**

```powershell
lua tests\audit_cleanup_wave5_spec.lua
```

Expected:

```text
audit cleanup wave5 source contract passed
```

---

### Task 6: Verification Gates

**Files:** no edits unless a gate exposes a defect

- [ ] **Step 1: Run focused source and registry checks**

```powershell
lua tests\audit_cleanup_wave5_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\release_stabilization_spec.lua
```

Expected:

- All commands exit `0`.
- `release_stabilization_spec.lua` reports all targeted stabilization tests passed.

- [ ] **Step 2: Run standard repo gates**

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

- All commands exit `0`.

- [ ] **Step 3: Inspect remaining wrappers**

```powershell
rg -n "local function getRaidQueries" !KRT
```

Expected remaining matches only in deferred memoized-cache owners:

- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Raid/State.lua`

- [ ] **Step 4: Run pre-commit/catalog checks before commit**

```powershell
git diff --check
git diff --stat
```

If pre-commit reports API catalog drift, stage the generated catalog files listed by the hook
and rerun the commit. Do not stage unrelated files.

---

### Task 7: Parent Review And Closeout

**Files:** review only

- [ ] **Step 1: Review the diff**

```powershell
git diff -- `
  !KRT/Services/Logger/Store.lua `
  !KRT/Services/Logger/Actions.lua `
  tests/audit_cleanup_wave5_spec.lua `
  docs/TECH_CLEANUP_BACKLOG.md
```

Review checklist:

- Logger Store has no file-scope `RaidQueries` cache.
- Logger Actions has no file-scope `RaidQueries` cache.
- Logger Store/Actions have no local `getRaidQueries` wrapper.
- Store/Actions use `Database.GetRaidQueriesOrNil()`.
- Store/Actions registry deps still include `Database/DBRaidQueries`.
- DB Syncer, Loot, and Raid wrappers remain untouched.
- No SavedVariables, XML, TOC, or changelog changes were introduced.

- [ ] **Step 2: Run whitespace diff check**

```powershell
git diff --check
```

Expected:

- No output.

- [ ] **Step 3: Record final status for the user**

Final response must include:

- Mini plan followed.
- Files changed.
- Summary of changes.
- Tests/checks run.
- Remaining risks.

Expected remaining risk:

- The remaining memoized `RaidQueries` wrappers in DB Syncer, Loot, and Raid still need
  separate owner-specific mapping before any future cleanup.
