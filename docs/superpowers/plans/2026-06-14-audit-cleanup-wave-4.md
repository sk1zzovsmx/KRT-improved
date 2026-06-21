# Audit Cleanup Wave 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Continue audit cleanup after Wave 3 by removing the first safe slice of duplicated
`getRaidQueries` wrappers, while preserving Logger behavior, module-registry boundaries,
SavedVariables shape, and WotLK 3.3.5a/Lua 5.1 compatibility.

**Architecture:** Wave 4 centralizes optional raid-query access in the `Database/DB.lua`
facade, then converts only the dynamic Logger View/Export consumers to use that facade helper.
Memoized query caches in Database Syncer, Logger Store/Actions, Loot, and Raid services remain
deferred until a later owner-specific wave.

**Tech Stack:** World of Warcraft 3.3.5a, Interface 30300, Lua 5.1, KRT project workflow,
PowerShell repo tooling, Lua source-contract specs.

---

## Classification

Use the project `55to53` workflow.

- Classification: `complex-orchestrated`
- Reason: more than one file changes, shared Database facade behavior is involved, and Logger
  query-path behavior has release-stabilization coverage.
- Execution model: parent plans and reviews; `code-mapper` maps the current wrappers first;
  `spark_implementer` applies the approved patch.
- Scope control: one owner slice only. Do not refactor memoized `RaidQueries` caches in this
  wave.

## Branching

Start from the clean Wave 3 result after the in-client smoke test.

```powershell
git checkout codex/audit-cleanup-wave-3-current
git status --short
git checkout -b codex/audit-cleanup-wave-4-current
```

Expected:

- `git status --short` has no output before branch creation.
- The new branch is `codex/audit-cleanup-wave-4-current`.

If Wave 3 has already been merged into another integration branch before execution, stop and
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

- `tests/audit_cleanup_wave4_spec.lua`
- `!KRT/Database/DB.lua`
- `!KRT/Services/Logger/View.lua`
- `!KRT/Services/Logger/Export.lua`
- `tests/release_stabilization_spec.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

Do not modify in Wave 4:

- `!KRT/Libs/*`
- `!KRT/!KRT.toc`
- `!KRT/UI/*.xml`
- `!KRT/Database/DBRaidQueries.lua`
- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Logger/Store.lua`
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/State.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/CHANGELOG.md`, unless the implementation changes user-visible behavior

## Deferred Items

Keep these out of Wave 4:

- Any behavior change to `DB.RaidQueries` row projection.
- Any registry dependency from Logger View/Export to `Database/DBRaidQueries`.
- Any conversion of memoized `RaidQueries` caches.
- Any request-tracking or snapshot cleanup in `Database/DBSyncer.lua`.
- Any Loot/Raid service facade cleanup.
- Any UI/XML cleanup.

---

### Task 1: Map Current `getRaidQueries` Ownership

**Files:** read-only

- `!KRT/Database/DB.lua`
- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Services/Logger/Export.lua`
- `!KRT/Services/Logger/Store.lua`
- `!KRT/Services/Logger/View.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Raid/State.lua`
- `tests/release_stabilization_spec.lua`
- `tests/module_registry_services_spec.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Run the read-only mapper**

Use `code-mapper` with this prompt:

```text
Map Wave 4 getRaidQueries cleanup. Do not edit files.

Read the files listed in the Wave 4 plan. Report:
1. every local getRaidQueries wrapper and whether it is dynamic lookup or memoized cache;
2. whether Logger View/Export can call a Database facade helper without depending on
   Database/DBRaidQueries;
3. isolated test harnesses that load Logger View/Export without loading Database/DB.lua;
4. exact files that must stay out of the first Wave 4 patch.

Do not propose broader cleanup. Keep the recommendation limited to the Logger View/Export slice.
```

Expected mapper result:

- `Services/Logger/View.lua` and `Services/Logger/Export.lua` use dynamic local wrappers.
- `Services/Logger/Store.lua`, `Services/Logger/Actions.lua`, `Services/Loot/Service.lua`,
  `Services/Raid/State.lua`, `Services/Raid/LootRecords.lua`, and `Database/DBSyncer.lua`
  keep memoized query caches and remain deferred.
- Logger View/Export must not add a `Database/DBRaidQueries` registry dependency.
- `tests/release_stabilization_spec.lua` needs a harness fallback for the new facade helper
  because some isolated tests load Logger files without loading `Database/DB.lua`.

- [ ] **Step 2: Parent gate**

Parent checks the mapper result. If the mapper recommends touching any deferred file, stop and
revise the plan before implementation.

---

### Task 2: Add Wave 4 Source-Contract Harness

**Files:**

- Create: `tests/audit_cleanup_wave4_spec.lua`

- [ ] **Step 1: Create the initial failing source-contract test**

Create `tests/audit_cleanup_wave4_spec.lua` with this content:

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
local loggerView = read("!KRT/Services/Logger/View.lua")
local loggerExport = read("!KRT/Services/Logger/Export.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(
    db,
    "function Database.GetRaidQueriesOrNil()",
    "DB facade should expose optional RaidQueries access"
)
assertContains(
    db,
    "return Database.GetRaidQueries()",
    "optional RaidQueries access should preserve dynamic GetRaidQueries overrides"
)
assertContains(
    loggerView,
    "Database.GetRaidQueriesOrNil()",
    "Logger View should use the Database facade helper"
)
assertContains(
    loggerExport,
    "Database.GetRaidQueriesOrNil()",
    "Logger Export should use the Database facade helper"
)
assertNotContains(
    loggerView,
    "local function getRaidQueries()",
    "Logger View should not keep the duplicated local query wrapper"
)
assertNotContains(
    loggerExport,
    "local function getRaidQueries()",
    "Logger Export should not keep the duplicated local query wrapper"
)
assertNotContains(
    loggerView,
    "\"Database/DBRaidQueries\"",
    "Logger View must not depend directly on DBRaidQueries"
)
assertNotContains(
    loggerExport,
    "\"Database/DBRaidQueries\"",
    "Logger Export must not depend directly on DBRaidQueries"
)
assertContains(
    releaseSpec,
    "Database.GetRaidQueriesOrNil = function()",
    "isolated release harness should expose the optional RaidQueries facade helper"
)
assertContains(
    backlog,
    "Wave 4 follow-up: remaining `getRaidQueries` wrappers",
    "cleanup backlog should record remaining memoized wrappers after the first Wave 4 slice"
)

print("audit cleanup wave4 source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

```powershell
lua tests\audit_cleanup_wave4_spec.lua
```

Expected failure before Task 3:

```text
DB facade should expose optional RaidQueries access
```

---

### Task 3: Add Optional RaidQueries Facade Access

**Files:**

- `!KRT/Database/DB.lua`
- `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add the production helper**

In `!KRT/Database/DB.lua`, directly after `function Database.GetRaidQueries()`, add:

```lua
function Database.GetRaidQueriesOrNil()
    if type(Database.GetRaidQueries) ~= "function" then
        return nil
    end

    return Database.GetRaidQueries()
end
```

Notes:

- Do not add warnings. Logger View/Export already tolerate missing query service by using
  fallback behavior or empty rows.
- Do not call `getManagerStore("GetRaidQueries")` directly in this helper. It must preserve
  dynamic `Database.GetRaidQueries` overrides used by isolated test harnesses.
- Do not change `Database.GetRaidQueries()` itself.

- [ ] **Step 2: Add the isolated harness helper**

In `tests/release_stabilization_spec.lua`, in `newHarness()` where the default Database methods
are installed, directly after:

```lua
Database.GetRaidQueries = function()
    return nil
end
```

add:

```lua
Database.GetRaidQueriesOrNil = function()
    if type(Database.GetRaidQueries) ~= "function" then
        return nil
    end
    return Database.GetRaidQueries()
end
```

Rationale: several release specs load Logger service files directly without loading
`!KRT/Database/DB.lua`; the harness must provide the same facade contract.

- [ ] **Step 3: Run the source-contract test**

```powershell
lua tests\audit_cleanup_wave4_spec.lua
```

Expected after Task 3 only:

- The test still fails because Logger View/Export and backlog are not updated yet.

---

### Task 4: Convert Logger View/Export Dynamic Wrappers

**Files:**

- `!KRT/Services/Logger/View.lua`
- `!KRT/Services/Logger/Export.lua`

- [ ] **Step 1: Update Logger View**

In `!KRT/Services/Logger/View.lua`:

- Remove the private `local function getRaidQueries()` block.
- Replace every:

```lua
local queries = getRaidQueries()
```

with:

```lua
local queries = Database.GetRaidQueriesOrNil()
```

Expected affected methods:

- `View:FillBossList`
- `View:FillRaidAttendeesList`
- `View:FillBossAttendeesList`
- `View:FillLootList`

- [ ] **Step 2: Update Logger Export**

In `!KRT/Services/Logger/Export.lua`:

- Remove the private `local function getRaidQueries()` block.
- Replace every:

```lua
local queries = getRaidQueries()
```

with:

```lua
local queries = Database.GetRaidQueriesOrNil()
```

Expected affected methods:

- `Export:GetLootCSV`
- `Export:GetRaidAttendanceCSV`

- [ ] **Step 3: Preserve Logger registry boundaries**

Do not change the `registry.AddModule(...)` dependency lists in either file.

Verify:

```powershell
rg -n '"Database/DBRaidQueries"' !KRT\Services\Logger\View.lua !KRT\Services\Logger\Export.lua
```

Expected:

- No output.

---

### Task 5: Update Cleanup Backlog

**Files:**

- `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Replace the Wave 3 follow-up section**

Replace the current section:

```text
### Wave 3 follow-up: `getRaidQueries` wrappers
```

with:

```text
### Wave 4 follow-up: remaining `getRaidQueries` wrappers

Wave 4 first slice centralizes optional dynamic query access through
`Database.GetRaidQueriesOrNil()` and removes the duplicated dynamic local wrappers from Logger
View/Export.

Remaining memoized wrappers after the first Wave 4 slice:
- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Services/Logger/Store.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Raid/State.lua`

Required before any later implementation:
- Map each memoized cache owner separately.
- Confirm whether late `Database.GetRaidQueries` assignment still needs cache refresh behavior.
- Split the remaining cleanup into one owner group per task.
```

Keep the direct caller note for:

- `!KRT/Controllers/Logger.lua`
- `!KRT/Database/DB.lua`
- `!KRT/Database/DBManager.lua`

Those direct callers are not part of wrapper cleanup.

- [ ] **Step 2: Run the source-contract test**

```powershell
lua tests\audit_cleanup_wave4_spec.lua
```

Expected:

```text
audit cleanup wave4 source contract passed
```

---

### Task 6: Verification Gates

**Files:** no edits unless a gate exposes a defect

- [ ] **Step 1: Run focused source and registry checks**

```powershell
lua tests\audit_cleanup_wave4_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\module_registry_database_spec.lua
```

Expected:

- All commands exit `0`.
- Logger View/Export still have no direct `Database/DBRaidQueries` dependency.

- [ ] **Step 2: Run release-stabilization coverage**

```powershell
lua tests\release_stabilization_spec.lua
```

Expected:

- Command exits `0`.
- Logger export tests still pass.
- Logger view shared-source and perf tests still pass.

- [ ] **Step 3: Run standard repo gates**

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

- All commands exit `0`.

- [ ] **Step 4: Inspect remaining wrappers**

```powershell
rg -n "local function getRaidQueries" !KRT
```

Expected remaining matches only in deferred memoized-cache owners:

- `!KRT/Database/DBSyncer.lua`
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Services/Logger/Store.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Raid/State.lua`

---

### Task 7: Parent Review And Closeout

**Files:** review only

- [ ] **Step 1: Review the diff**

```powershell
git diff -- `
  !KRT/Database/DB.lua `
  !KRT/Services/Logger/View.lua `
  !KRT/Services/Logger/Export.lua `
  tests/release_stabilization_spec.lua `
  tests/audit_cleanup_wave4_spec.lua `
  docs/TECH_CLEANUP_BACKLOG.md
```

Review checklist:

- `Database.GetRaidQueriesOrNil()` is a thin optional facade only.
- The helper preserves dynamic `Database.GetRaidQueries` overrides.
- Logger View/Export have no local `getRaidQueries` wrapper.
- Logger View/Export have no direct `Database/DBRaidQueries` dependency.
- Memoized owners remain untouched.
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

- The deferred memoized `RaidQueries` wrappers still need separate owner-specific mapping before
  any future cleanup.
