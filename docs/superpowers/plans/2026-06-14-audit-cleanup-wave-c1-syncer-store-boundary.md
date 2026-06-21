# Wave C1 Syncer Store Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten `DBSyncer.lua` query/store boundaries without changing logger
sync protocol, payload shape, merge semantics, or SavedVariables.

**Architecture:** Wave C1 stays inside `!KRT/Database/DBSyncer.lua` plus tests,
cleanup docs, and generated catalogs. The runtime patch removes the memoized
`GetRaidQueries` wrapper, uses the dynamic optional DB query facade, and extracts
small local helpers around snapshot header application, next-NID advancement,
runtime cleanup, and import-store acquisition.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT Database
facades, logger sync payloads over `KRTLogSync`, repo-local Lua/Python/
PowerShell gates.

---

## Classification

- `55to53`: `complex-orchestrated`
- Reason: touches a Database owner, sync merge/import behavior, test harness
  coverage, cleanup backlog docs, and generated catalogs.
- Required execution mode: use the project delegated workflow.
- Required mapping: use `code-mapper` first if implementation starts in a fresh
  session or if `DBSyncer.lua` has changed since this plan was written.
- Required implementation: delegate the runtime patch to `spark_implementer`.
- Parent review must inspect the final diff before closing the wave.

## File Structure

- Modify: `!KRT/Database/DBSyncer.lua`
  - Remove the file-local memoized `RaidQueries` cache.
  - Remove the private `getRaidQueries()` wrapper.
  - Make `resolveLootLooterNameFromMap(...)` call
    `Database.GetRaidQueriesOrNil()` at use time.
  - Add local helpers for snapshot header application, next-NID advancement,
    snapshot raid finalization, import-store acquisition, and import record
    creation.
  - Keep `buildSnapshotPayload(...)`, `parseSnapshotPayload(...)`,
    `applySnapshotToRaid(...)`, `importSnapshotAsNewRaid(...)`, and public
    `module:*` APIs private/public exactly as they are today.
- Modify: `tests/release_stabilization_spec.lua`
  - Add a behavior test proving `DBSyncer` uses the current query facade instead
    of a stale query object captured at load time.
- Create: `tests/audit_cleanup_wave_c1_syncer_store_boundary_spec.lua`
  - Guard helper shape, absence of the memoized query wrapper, backlog marker,
    and the dedicated release stabilization test.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Mark Wave C1 complete.
  - Remove `DBSyncer.lua` from the immediate default next-step slot.
- Generated: `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`, and
  `docs/TREE.md` after `py -3 tools/krt.py api-catalog-refresh`.

## Non-Goals

- Do not change `KRTLogSync` prefix, protocol version, row kinds, separators,
  encoded field order, chunking, request IDs, request modes, or debug text.
- Do not change import-vs-merge semantics for `REQ`, `PUSH`, or `SYNC`.
- Do not change SavedVariables shape or add migrations.
- Do not move sync code into a new file in this wave.
- Do not touch `!KRT/Database/DBRaidStore.lua`; C2 owns runtime-index follow-up.
- Do not modify controllers, widgets, services, XML, vendored libs, or
  `!KRT/CHANGELOG.md`.

---

### Task 0: Read-Only Mapping Checkpoint

**Files:**
- Read: `!KRT/Database/DBSyncer.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Confirm the current owner slice**

Run:

```powershell
rg -n "local RaidQueries|local function getRaidQueries|Database.GetRaidQueriesOrNil|resolveLootLooterNameFromMap|applySnapshotToRaid|importSnapshotAsNewRaid" `
  !KRT\Database\DBSyncer.lua tests\release_stabilization_spec.lua docs\TECH_CLEANUP_BACKLOG.md
```

Expected before implementation:

```text
!KRT\Database\DBSyncer.lua:51:    local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil
!KRT\Database\DBSyncer.lua:364:    local function getRaidQueries()
!KRT\Database\DBSyncer.lua:371:    local function resolveLootLooterNameFromMap(loot, playerNameByNid)
!KRT\Database\DBSyncer.lua:1009:    local function applySnapshotToRaid(raid, snapshot, updateMeta)
!KRT\Database\DBSyncer.lua:1160:    local function importSnapshotAsNewRaid(snapshot)
```

If line numbers drift, continue only if the same symbols are still present.

- [ ] **Step 2: Confirm the existing sync behavior tests**

Run:

```powershell
rg -n "db syncer routes requests|db syncer imports push snapshots|db syncer snapshot payload|db syncer records sync payload" `
  tests\release_stabilization_spec.lua
```

Expected:

The output includes one match for each of these exact test names:

- `db syncer routes requests through whisper and group transports`
- `db syncer imports push snapshots and merges requested sync chunks`
- `db syncer snapshot payload uses nid references for repeated player fields`
- `db syncer records sync payload byte chunk metrics`

---

### Task 1: Add the C1 Source-Contract Test

**Files:**
- Create: `tests/audit_cleanup_wave_c1_syncer_store_boundary_spec.lua`

- [ ] **Step 1: Create the failing source-contract test**

Create `tests/audit_cleanup_wave_c1_syncer_store_boundary_spec.lua` with this
content:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstPos = assert(text:find(first, 1, true), "missing: " .. first)
    local secondPos = assert(text:find(second, 1, true), "missing: " .. second)
    assert(firstPos < secondPos, message or (first .. " must appear before " .. second))
end

local syncer = read("!KRT/Database/DBSyncer.lua")
local releaseSpec = read("tests/release_stabilization_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertNotContains(syncer, "local RaidQueries =", "DBSyncer must not memoize RaidQueries")
assertNotContains(syncer, "local function getRaidQueries()", "DBSyncer must not keep a query wrapper")
assertNotContains(
    syncer,
    "Database.GetRaidQueries and Database.GetRaidQueries()",
    "DBSyncer should use the optional dynamic query facade"
)

assertContains(syncer, "local function resolveLootLooterNameFromMap(loot, playerNameByNid)")
assertContains(syncer, "local queries = Database.GetRaidQueriesOrNil()")
assertContains(syncer, "return queries:ResolveLootLooterNameFromMap(loot, playerNameByNid)")

assertContains(syncer, "local function applySnapshotHeaderToRaid(raid, header)")
assertContains(syncer, "local function applySnapshotNextNids(raid, header)")
assertContains(syncer, "local function finalizeSnapshotRaid(raid)")
assertContains(syncer, "local function getSnapshotImportRaidStore()")
assertContains(syncer, "local function createRaidFromSnapshotHeader(raidStore, header)")

assertBefore(syncer, "local function applySnapshotHeaderToRaid", "local function applySnapshotToRaid")
assertBefore(syncer, "local function getSnapshotImportRaidStore", "local function importSnapshotAsNewRaid")
assertBefore(syncer, "local function createRaidFromSnapshotHeader", "local function importSnapshotAsNewRaid")

assertContains(syncer, "applySnapshotHeaderToRaid(raid, header)")
assertContains(syncer, "applySnapshotNextNids(raid, header)")
assertContains(syncer, "return finalizeSnapshotRaid(raid)")
assertContains(syncer, "local raidStore = getSnapshotImportRaidStore()")
assertContains(syncer, "local raid = createRaidFromSnapshotHeader(raidStore, header)")

assertContains(
    releaseSpec,
    'test("db syncer resolves loot looter through current query facade", function()'
)
assertContains(backlog, "Wave C1 completed: Syncer store boundary cleanup")

print("audit cleanup wave c1 syncer store boundary source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run:

```powershell
lua tests\audit_cleanup_wave_c1_syncer_store_boundary_spec.lua
```

Expected before implementation:

```text
DBSyncer must not memoize RaidQueries
```

If it fails later on the backlog marker instead, continue; that means the runtime
shape has already been patched and Task 4 still needs the docs update.

---

### Task 2: Add a Dynamic Query-Facade Behavior Test

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Insert the behavior test**

In `tests/release_stabilization_spec.lua`, place this test after the existing
`db syncer snapshot payload uses nid references for repeated player fields`
test and before `db syncer records sync payload byte chunk metrics`:

```lua
test("db syncer resolves loot looter through current query facade", function()
    local source = newHarness()
    local itemLink = source.registerItem(9003, "Dynamic Query Sync Blade")
    local itemString = source.addon.Item.GetItemStringFromLink(itemLink)
    source:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 79,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 2, class = "MAGE", join = 1000, countMS = 3 },
            },
            bossKills = {},
            loot = {
                {
                    lootNid = 101,
                    itemId = 9003,
                    itemName = "Dynamic Query Sync Blade",
                    itemString = itemString,
                    itemLink = itemLink,
                    itemRarity = 4,
                    itemTexture = "Icon9003",
                    itemCount = 1,
                    rollType = source.rollTypes.MAINSPEC,
                    rollValue = 98,
                    bossNid = 0,
                    time = 1015,
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 102,
        },
    })

    local staleQueries = {
        ResolveLootLooterNameFromMap = function()
            return "Stale"
        end,
    }
    source.Database.GetRaidQueries = function()
        return staleQueries
    end

    local snapshotMessages = {}
    source.addon.IsInGroup = function()
        return true
    end
    source.addon.IsInRaid = function()
        return false
    end
    source.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    _G.SendAddonMessage = function(prefix, payload, channel, target)
        snapshotMessages[#snapshotMessages + 1] = {
            prefix = prefix,
            payload = payload,
            channel = channel,
            target = target,
        }
    end

    source:load("!KRT/Modules/Comms.lua")
    source:load("!KRT/Modules/Base64.lua")
    source:load("!KRT/Database/DBSyncer.lua")

    local currentQueries = {
        ResolveLootLooterNameFromMap = function(_, loot, playerNameByNid)
            assertEqual(tonumber(loot and loot.lootNid), 101, "expected current query to receive the loot row")
            return playerNameByNid[1] or ""
        end,
    }
    source.Database.GetRaidQueries = function()
        return currentQueries
    end
    source.Database.GetRaidQueriesOrNil = function()
        return currentQueries
    end

    assertTrue(source.addon.DB.Syncer:BroadcastLoggerPush(79, "Bob") == true, "expected source push snapshot to send")

    local encodedParts = {}
    for i = 1, #snapshotMessages do
        local fields = {}
        for field in snapshotMessages[i].payload:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        encodedParts[tonumber(fields[6]) or i] = fields[8] or ""
    end

    local snapshotPayload = source.addon.Base64.Decode(table.concat(encodedParts, ""))
    assertTrue(type(snapshotPayload) == "string" and snapshotPayload ~= "", "expected decoded snapshot payload")

    local lootLooter = nil
    for line in snapshotPayload:gmatch("[^\n]+") do
        local fields = {}
        for field in line:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        if fields[1] == "L" then
            lootLooter = source.addon.Base64.Decode(fields[10] or "")
        end
    end

    assertEqual(lootLooter, "Alice", "expected DBSyncer to use the current query facade")
end)
```

- [ ] **Step 2: Run the focused release test and verify it fails before implementation**

Run:

```powershell
lua tests\release_stabilization_spec.lua
```

Expected before implementation:

```text
[FAIL] db syncer resolves loot looter through current query facade
expected DBSyncer to use the current query facade
expected: Alice
actual: Stale
```

The full file runs all targeted stabilization tests. It is acceptable if output
contains many preceding `OK` lines before this failure.

---

### Task 3: Normalize `DBSyncer` Query and Store Boundaries

**Files:**
- Modify: `!KRT/Database/DBSyncer.lua`

- [ ] **Step 1: Remove the memoized query cache**

Delete this line near the top of the `do` block:

```lua
local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil
```

Delete the entire private wrapper:

```lua
local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end
```

- [ ] **Step 2: Use the dynamic optional DB query facade**

Replace `resolveLootLooterNameFromMap(...)` with:

```lua
local function resolveLootLooterNameFromMap(loot, playerNameByNid)
    local queries = Database.GetRaidQueriesOrNil()
    if queries and queries.ResolveLootLooterNameFromMap then
        return queries:ResolveLootLooterNameFromMap(loot, playerNameByNid)
    end
    return ""
end
```

Do not add a local wrapper around `Database.GetRaidQueriesOrNil()`. C1 is meant
to close the `DBSyncer` owner group from the remaining `getRaidQueries` list.

- [ ] **Step 3: Add snapshot boundary helpers**

Place these helpers after `resolveRaidByReference(...)` and before
`applySnapshotToRaid(...)`:

```lua
local function applySnapshotHeaderToRaid(raid, header)
    raid.schemaVersion = tonumber(header.schemaVersion) or tonumber(raid.schemaVersion) or 1
    raid.zone = header.zone or raid.zone
    raid.size = tonumber(header.size) or tonumber(raid.size)
    raid.difficulty = tonumber(header.difficulty) or tonumber(raid.difficulty)
    raid.realm = header.realm or raid.realm

    local startTime = tonumber(header.startTime)
    if startTime and startTime > 0 then
        raid.startTime = startTime
    end

    local endTime = tonumber(header.endTime)
    if endTime and endTime > 0 then
        raid.endTime = endTime
    end
end

local function applySnapshotNextNids(raid, header)
    raid.nextPlayerNid = math.max(tonumber(raid.nextPlayerNid) or 1, tonumber(header.nextPlayerNid) or 1)
    raid.nextBossNid = math.max(tonumber(raid.nextBossNid) or 1, tonumber(header.nextBossNid) or 1)
    raid.nextLootNid = math.max(tonumber(raid.nextLootNid) or 1, tonumber(header.nextLootNid) or 1)
end

local function finalizeSnapshotRaid(raid)
    if Database and Database.StripRuntimeRaidCaches then
        Database.StripRuntimeRaidCaches(raid)
    end
    Database.EnsureRaidSchema(raid)

    return raid
end

local function getSnapshotImportRaidStore()
    return Database.GetRaidStoreOrNil("DBSyncer.ImportSnapshotAsNewRaid", { "CreateRaidRecord", "InsertRaid" })
end

local function createRaidFromSnapshotHeader(raidStore, header)
    return raidStore:CreateRaidRecord({
        realm = header.realm,
        zone = header.zone,
        size = tonumber(header.size),
        difficulty = tonumber(header.difficulty),
        startTime = tonumber(header.startTime) or Time.GetCurrentTime(),
        endTime = (tonumber(header.endTime) or 0) > 0 and tonumber(header.endTime) or nil,
    })
end
```

- [ ] **Step 4: Route header and finalization through the helpers**

Inside `applySnapshotToRaid(...)`, replace the current `if updateMeta then ...`
block with:

```lua
if updateMeta then
    applySnapshotHeaderToRaid(raid, header)
end
```

Near the end of `applySnapshotToRaid(...)`, replace:

```lua
raid.nextPlayerNid = math.max(tonumber(raid.nextPlayerNid) or 1, tonumber(header.nextPlayerNid) or 1)
raid.nextBossNid = math.max(tonumber(raid.nextBossNid) or 1, tonumber(header.nextBossNid) or 1)
raid.nextLootNid = math.max(tonumber(raid.nextLootNid) or 1, tonumber(header.nextLootNid) or 1)

if Database and Database.StripRuntimeRaidCaches then
    Database.StripRuntimeRaidCaches(raid)
end
Database.EnsureRaidSchema(raid)

return raid
```

with:

```lua
applySnapshotNextNids(raid, header)

return finalizeSnapshotRaid(raid)
```

- [ ] **Step 5: Route import persistence through the helpers**

Inside `importSnapshotAsNewRaid(...)`, replace:

```lua
local raidStore = Database.GetRaidStoreOrNil("DBSyncer.ImportSnapshotAsNewRaid", { "CreateRaidRecord", "InsertRaid" })
if not raidStore then
    return nil, nil
end

local raid = raidStore:CreateRaidRecord({
    realm = header.realm,
    zone = header.zone,
    size = tonumber(header.size),
    difficulty = tonumber(header.difficulty),
    startTime = tonumber(header.startTime) or Time.GetCurrentTime(),
    endTime = (tonumber(header.endTime) or 0) > 0 and tonumber(header.endTime) or nil,
})
```

with:

```lua
local raidStore = getSnapshotImportRaidStore()
if not raidStore then
    return nil, nil
end

local raid = createRaidFromSnapshotHeader(raidStore, header)
```

- [ ] **Step 6: Verify source shape**

Run:

```powershell
rg -n "local RaidQueries|local function getRaidQueries|Database.GetRaidQueries and Database.GetRaidQueries" `
  !KRT\Database\DBSyncer.lua
rg -n "GetRaidQueriesOrNil|applySnapshotHeaderToRaid|applySnapshotNextNids|finalizeSnapshotRaid|getSnapshotImportRaidStore|createRaidFromSnapshotHeader" `
  !KRT\Database\DBSyncer.lua
```

Expected first command:

```text
```

Expected second command includes one match for each of these exact lines:

- `local queries = Database.GetRaidQueriesOrNil()`
- `local function applySnapshotHeaderToRaid(raid, header)`
- `local function applySnapshotNextNids(raid, header)`
- `local function finalizeSnapshotRaid(raid)`
- `local function getSnapshotImportRaidStore()`
- `local function createRaidFromSnapshotHeader(raidStore, header)`

---

### Task 4: Update the Cleanup Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Mark Wave C1 complete**

In `### Wave C1: Syncer Store Boundary`, extend `Current worktree progress` so
it includes these bullets:

```markdown
- DBSyncer no longer keeps a memoized `RaidQueries` cache or local
  `getRaidQueries()` wrapper
- loot looter resolution now uses `Database.GetRaidQueriesOrNil()` at snapshot
  build time
- snapshot header application, next-NID advancement, runtime cleanup, and import
  store acquisition now have explicit local helper boundaries
- Wave C1 completed: Syncer store boundary cleanup
```

Do not remove the existing three progress bullets for group sync gating, target
normalization, or sender failure bookkeeping.

- [ ] **Step 2: Advance the default next-step list**

Near the bottom, replace:

```markdown
1. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
3. `!KRT/Database/DBRaidStore.lua` runtime-index boundary follow-up only if C1 stays stable
```

with:

```markdown
1. one remaining `getRaidQueries` owner group, starting with `!KRT/Services/Loot/Service.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
3. `!KRT/Database/DBRaidStore.lua` runtime-index boundary follow-up only if C1 stays stable
```

- [ ] **Step 3: Run the C1 source-contract test**

Run:

```powershell
lua tests\audit_cleanup_wave_c1_syncer_store_boundary_spec.lua
```

Expected:

```text
audit cleanup wave c1 syncer store boundary source contract passed
```

---

### Task 5: Refresh Catalogs and Run Verification

**Files:**
- Modify generated files changed by the commands below.

- [ ] **Step 1: Refresh generated API/function catalogs**

Run:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

Expected:

```text
Function inventory complete.
Function classification complete.
API census complete.
Updated docs/TREE.md
```

- [ ] **Step 2: Verify generated catalogs are current**

Run:

```powershell
py -3 tools/krt.py api-catalog-check
```

Expected:

```text
API catalogs are up to date.
```

- [ ] **Step 3: Run focused tests**

Run:

```powershell
lua tests\audit_cleanup_wave_c1_syncer_store_boundary_spec.lua
lua tests\release_stabilization_spec.lua
```

Expected:

```text
audit cleanup wave c1 syncer store boundary source contract passed
290 targeted stabilization test(s) passed.
```

The targeted stabilization count may be higher if another test lands before C1.
The important gate is exit code `0`.

- [ ] **Step 4: Run release-targeted tests through the repo launcher**

Run:

```powershell
py -3 tools/krt.py run-release-targeted-tests
```

Expected:

```text
Targeted stabilization tests completed successfully.
```

- [ ] **Step 5: Run repository quality gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-layering.ps1
```

Expected:

```text
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
Lua syntax check passed.
Layering check passed.
```

- [ ] **Step 6: Run formatting and diff hygiene checks**

Run:

```powershell
stylua --check !KRT\Database\DBSyncer.lua `
  tests\release_stabilization_spec.lua `
  tests\audit_cleanup_wave_c1_syncer_store_boundary_spec.lua
git diff --check
git status --short
```

Expected:

```text
```

`git diff --check` must have no errors. `git status --short` must show only the
intended Wave C1 files and generated catalog files.

---

### Task 6: Parent Review, Commit, and Smoke Handoff

**Files:**
- Review all changed files.

- [ ] **Step 1: Inspect the final diff**

Run:

```powershell
git diff --stat
git diff -- !KRT/Database/DBSyncer.lua
git diff -- tests/release_stabilization_spec.lua
git diff -- tests/audit_cleanup_wave_c1_syncer_store_boundary_spec.lua
git diff -- docs/TECH_CLEANUP_BACKLOG.md
```

Review expectations:

- `DBSyncer.lua` has no `local RaidQueries` cache.
- `DBSyncer.lua` has no local `getRaidQueries()` helper.
- Query access uses `Database.GetRaidQueriesOrNil()` directly at use time.
- Sync protocol constants, field separators, row kinds, and public methods are
  unchanged.
- `applySnapshotToRaid(...)` still merges players, attendance, bosses, loot,
  and next-NID fields in the same order.
- `importSnapshotAsNewRaid(...)` still creates a raid through RaidStore and then
  inserts it through RaidStore.
- No UI, service, XML, SavedVariables, or changelog file changed.

- [ ] **Step 2: Commit the Wave C1 patch**

Run:

```powershell
git add -- `
  "!KRT/Database/DBSyncer.lua" `
  "tests/release_stabilization_spec.lua" `
  "tests/audit_cleanup_wave_c1_syncer_store_boundary_spec.lua" `
  "docs/TECH_CLEANUP_BACKLOG.md" `
  "docs/superpowers/plans/2026-06-14-audit-cleanup-wave-c1-syncer-store-boundary.md" `
  "docs/FUNCTION_REGISTRY.csv" `
  "docs/FN_CLUSTERS.md" `
  "docs/TREE.md"

git commit -m "Normalize syncer store boundary"
```

If the pre-commit hook reports catalog drift, stage only the generated files
listed by the hook and retry the same commit command.

- [ ] **Step 3: Confirm the commit and clean working tree**

Run:

```powershell
git status --short --branch
git show --stat --oneline --decorate --no-renames HEAD
```

Expected:

```text
## codex/audit-cleanup-wave-c1-syncer-store-boundary
<clean status, followed by the Wave C1 commit stat>
```

## In-Client Smoke Checklist

Run this on WoW 3.3.5a after the commit:

- `/reload` with no Lua errors.
- Enter a raid/group with another KRT client if available.
- Trigger a targeted logger request and confirm it uses whisper transport.
- Trigger current raid sync and confirm group transport sends one request.
- Push logger sync from a source client and confirm the target imports one raid.
- Request sync into the current raid and confirm it merges into the current raid
  instead of creating a duplicate.
- Confirm Logger history refreshes after imported or merged sync data.
- Confirm no warnings for valid chunks and malformed chunks still warn instead
  of importing partial data.

## Self-Review

- Spec coverage: the plan covers C1 owner scope, the remaining `DBSyncer`
  `getRaidQueries` owner group, store/import helper boundaries, docs, catalogs,
  verification, commit, and smoke handoff.
- Placeholder scan: no task uses placeholder implementation text; each code edit
  names exact files, helpers, replacement snippets, commands, and expected
  results.
- Type/name consistency: helper names are
  `applySnapshotHeaderToRaid`, `applySnapshotNextNids`,
  `finalizeSnapshotRaid`, `getSnapshotImportRaidStore`, and
  `createRaidFromSnapshotHeader` throughout the plan.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-06-14-audit-cleanup-wave-c1-syncer-store-boundary.md`.

Two execution options:

1. Subagent-Driven (recommended) - dispatch focused implementation subagents,
   then parent review and correction before commit.
2. Inline Execution - execute this plan in the current session with checkpoints.
