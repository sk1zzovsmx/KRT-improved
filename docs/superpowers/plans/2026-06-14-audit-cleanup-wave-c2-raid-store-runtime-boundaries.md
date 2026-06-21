# Wave C2 Raid Store Runtime Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten `DBRaidStore.lua` runtime-index ownership and invalidation
paths without changing persisted raid schema, SavedVariables shape, public store
APIs, or query behavior.

**Architecture:** Wave C2 stays inside the Database raid-store owner. The patch
centralizes runtime map-key ownership, runtime signature refresh, runtime strip
vs normalize cleanup, and loot-row runtime indexing. External consumers keep
calling `EnsureRaidRuntime`, `UpsertLootIndex`, and `StripRuntime` exactly as
they do today.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT Database
facades, repo-local Lua/Python/PowerShell gates.

---

## Classification

- `55to53`: `complex-orchestrated`
- Reason: touches a Database owner, runtime index contracts consumed by query
  helpers and services, test harness coverage, cleanup backlog docs, and
  generated catalogs.
- Required execution mode: project delegated workflow.
- Required mapping: use `code-mapper` before implementation.
- Required implementation: delegate the runtime patch to `spark_implementer`.
- Parent review must inspect the final diff before closing the wave.

## File Structure

- Modify: `!KRT/Database/DBRaidStore.lua`
  - Add one local runtime-index key list used by readiness and acquisition.
  - Add local helper boundaries for runtime collections and signature refresh.
  - Add helpers that separate normalize-time runtime cleanup from full strip.
  - Add one local helper for loot runtime-row indexing used by full rebuild and
    `UpsertLootIndex`.
  - Keep all existing public `module:*` methods and return contracts.
- Modify: `tests/release_stabilization_spec.lua`
  - Add a behavior guard proving an upserted existing loot row moves boss and
    looter runtime lists without rebuilding the runtime table.
- Create: `tests/audit_cleanup_wave_c2_raid_store_runtime_boundaries_spec.lua`
  - Guard source shape, helper ordering, backlog marker, and release test name.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Mark Wave C2 complete under the Wave C2 section.
  - Remove C2 from the default next-step list.
- Generated, if changed by `py -3 tools/krt.py api-catalog-refresh`:
  - `docs/FUNCTION_REGISTRY.csv`
  - `docs/FN_CLUSTERS.md`
  - `docs/TREE.md`

## Non-Goals

- Do not change persisted raid schema or add migrations.
- Do not change SavedVariables keys or stored raid field names.
- Do not add or remove public `DB.RaidStore` APIs.
- Do not move raid queries, validator code, services, controllers, widgets, XML,
  or vendored libraries.
- Do not change runtime index semantics for players, bosses, loot, or
  attendance.
- Do not change loot append, trade-only loot, logger history, raid roster, or
  sync behavior.
- Do not edit `!KRT/CHANGELOG.md`; this is internal cleanup without
  user-visible behavior change.

---

### Task 0: Read-Only Mapping Checkpoint

**Files:**
- Read: `!KRT/Database/DBRaidStore.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Confirm the current owner slice**

Run:

```powershell
$pattern = "ROOT_RUNTIME_CACHE_KEYS|isRuntimeIndexReady|acquireRuntimeIndexMap|buildRuntimeSignature"
$pattern = $pattern + "|buildRuntimeIndexesForNormalizedRaid|EnsureRaidRuntime|UpsertLootIndex|StripRuntime"
rg -n $pattern !KRT\Database\DBRaidStore.lua tests\release_stabilization_spec.lua docs\TECH_CLEANUP_BACKLOG.md
```

Expected before implementation: the owner functions are present in
`!KRT/Database/DBRaidStore.lua`.

- [ ] **Step 2: Confirm current runtime behavior coverage**

Run:

```powershell
$pattern = "runtime cache reuses runtime|runtime cache indexes appended loot"
$pattern = $pattern + "|runtime cache builds logger history query indexes"
$pattern = $pattern + "|runtime cache rebuilds when signature changes"
$pattern = $pattern + "|raid query facade filters logger history|trade-only loot append patches runtime"
rg -n $pattern tests\release_stabilization_spec.lua
```

Expected output includes these test names:

```text
runtime cache reuses runtime until invalidated
runtime cache indexes appended loot without rebuilding runtime
runtime cache builds logger history query indexes
runtime cache rebuilds when signature changes without explicit strip
raid query facade filters logger history with runtime indexes
trade-only loot append patches runtime without full cache invalidation
```

---

### Task 1: Add the C2 Source-Contract Test

**Files:**
- Create: `tests/audit_cleanup_wave_c2_raid_store_runtime_boundaries_spec.lua`

- [ ] **Step 1: Create a source-contract test**

The test must assert:

- `local RUNTIME_INDEX_MAP_KEYS = {`
- all runtime map keys:
  - `playersByName`
  - `playerByNid`
  - `playerNidByName`
  - `playerIdxByNid`
  - `bossIdxByNid`
  - `bossByNid`
  - `bossPlayerSetByBossNid`
  - `lootIdxByNid`
  - `lootByNid`
  - `lootIdxByBossNid`
  - `lootIdxByLooterNid`
  - `attendanceIdxByPlayerNid`
  - `attendanceByPlayerNid`
- `local function acquireRuntimeIndexMaps(runtime)`
- `for i = 1, #RUNTIME_INDEX_MAP_KEYS do`
- `maps[key] = acquireRuntimeIndexMap(runtime, key)`
- readiness validation for `runtime[RUNTIME_INDEX_MAP_KEYS[i]]`
- `local function getRuntimeCollections(raid)`
- `local function buildRaidRuntimeSignature(raid)`
- `local function refreshRuntimeSignature(raid, runtime)`
- `runtime.signature = buildRaidRuntimeSignature(raid)`
- `local function normalizeRuntimeState(raid)`
- `local function stripRuntimeState(raid)`
- `local function indexLootRuntimeRow(runtime, loot, index, replaceExisting)`
- `indexLootRuntimeRow(runtime, lootRows[i], i, false)`
- `if not indexLootRuntimeRow(runtime, row, resolvedIndex, true) then`
- the new release test name
- `Wave C2 completed: Raid store runtime boundary cleanup`
- helper order:
  - runtime key list before `isRuntimeIndexReady`
  - `acquireRuntimeIndexMaps` before `buildRuntimeIndexesForNormalizedRaid`
  - `indexLootRuntimeRow` before `module:UpsertLootIndex`

Expected success output:

```text
audit cleanup wave c2 raid store runtime boundaries source contract passed
```

---

### Task 2: Add a Focused Runtime Upsert Behavior Test

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Insert the behavior test**

Place this test after `runtime cache builds logger history query indexes` and
before `runtime cache rebuilds when signature changes without explicit strip`:

```lua
test("runtime cache upsert moves loot index between boss and looter maps", function()
    local h = newHarness()
    h:load("!KRT/Database/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", countMS = 0 },
            { playerNid = 2, name = "Bob", countMS = 0 },
        },
        bossKills = {
            { bossNid = 10, name = "Patchwerk" },
            { bossNid = 20, name = "Grobbulus" },
        },
        loot = {
            { lootNid = 101, bossNid = 10, itemId = 9001, looterNid = 1 },
        },
        nextPlayerNid = 3,
        nextBossNid = 21,
        nextLootNid = 102,
    }

    local function hasListValue(list, value)
        if type(list) ~= "table" then
            return false
        end
        for i = 1, #list do
            if list[i] == value then
                return true
            end
        end
        return false
    end

    local runtime1 = store:EnsureRaidRuntime(raid)
    local row = raid.loot[1]
    row.bossNid = 20
    row.looterNid = 2

    local runtime2 = store:UpsertLootIndex(raid, row, 1)
    local runtime3 = store:EnsureRaidRuntime(raid)

    assertTrue(runtime2 == runtime1, "expected upsert to patch the existing runtime table")
    assertTrue(runtime3 == runtime1, "expected patched signature to avoid a full rebuild")
    assertTrue(not hasListValue(runtime1.lootIdxByBossNid[10], 1), "expected old boss index to be cleared")
    assertTrue(hasListValue(runtime1.lootIdxByBossNid[20], 1), "expected new boss index to be added")
    assertTrue(not hasListValue(runtime1.lootIdxByLooterNid[1], 1), "expected old looter index to be cleared")
    assertTrue(hasListValue(runtime1.lootIdxByLooterNid[2], 1), "expected new looter index to be added")
    assertTrue(runtime1.lootByNid[101] == row, "expected loot nid lookup to stay attached to the row")
end)
```

---

### Task 3: Centralize Runtime Index Map Ownership

**Files:**
- Modify: `!KRT/Database/DBRaidStore.lua`

- [ ] **Step 1: Add `RUNTIME_INDEX_MAP_KEYS`**

Add the key list immediately after `ROOT_RUNTIME_CACHE_KEYS`. The list must
contain the 13 runtime maps currently validated by `isRuntimeIndexReady`.

- [ ] **Step 2: Replace readiness with list-driven validation**

`isRuntimeIndexReady(runtime)` must return false unless `runtime` is a table and
every key in `RUNTIME_INDEX_MAP_KEYS` points to a table.

- [ ] **Step 3: Add `acquireRuntimeIndexMaps(runtime)`**

The helper must loop through `RUNTIME_INDEX_MAP_KEYS` and call
`acquireRuntimeIndexMap(runtime, key)` for each key.

- [ ] **Step 4: Use map acquisition in full runtime rebuild**

`buildRuntimeIndexesForNormalizedRaid` must acquire maps once, then write
through `maps.<key>`. Preserve loop order and filtering.

---

### Task 4: Centralize Runtime Signature and Loot Row Indexing

**Files:**
- Modify: `!KRT/Database/DBRaidStore.lua`

- [ ] **Step 1: Add runtime collection/signature helpers**

Add:

- `getRuntimeCollections(raid)`
- `buildRaidRuntimeSignature(raid)`
- `refreshRuntimeSignature(raid, runtime)`

Do not change `buildRuntimeSignature` content.

- [ ] **Step 2: Add normalize-vs-strip runtime helpers**

Add:

- `normalizeRuntimeState(raid)`
- `stripRuntimeState(raid)`

Use `normalizeRuntimeState` at the end of `NormalizeRaidRecord`. Use
`stripRuntimeState` in `StripRuntime`.

- [ ] **Step 3: Add `indexLootRuntimeRow`**

The helper must:

- validate table `runtime`, table `loot`, positive numeric index, and numeric
  `lootNid`
- update `runtime.lootIdxByNid`
- update `runtime.lootByNid`
- when `replaceExisting` is true, remove the row index from all old boss and
  looter lists before appending new mappings
- append positive `bossNid` and `looterNid` index-list entries
- return `true` on success and `false` on invalid input

- [ ] **Step 4: Use the helper in rebuild and upsert paths**

Use `indexLootRuntimeRow(runtime, lootRows[i], i, false)` in full rebuild.
Use `indexLootRuntimeRow(runtime, row, resolvedIndex, true)` in
`UpsertLootIndex`.

- [ ] **Step 5: Use signature helpers**

Use `buildRaidRuntimeSignature(raid)` in `EnsureRaidRuntime`.
Use `refreshRuntimeSignature(raid, runtime)` after full rebuild and upsert.

---

### Task 5: Update Cleanup Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Mark Wave C2 complete**

Under `### Wave C2: Raid Store Runtime Boundaries`, append:

```markdown
- runtime index-map ownership now uses one local key list shared by readiness
  and acquisition paths
- runtime signature refresh and normalize-vs-strip runtime cleanup now have
  explicit local helper boundaries
- loot runtime row indexing now shares one helper across full rebuild and
  targeted upsert paths
- Wave C2 completed: Raid store runtime boundary cleanup
```

- [ ] **Step 2: Update default next step**

Remove the C2 conditional line from `## 7. Default Next Step`.

---

### Task 6: Refresh Generated Catalogs and Run Gates

Run:

```powershell
lua tests\audit_cleanup_wave_c2_raid_store_runtime_boundaries_spec.lua
lua tests\release_stabilization_spec.lua
lua tests\module_registry_database_spec.lua
py -3 tools\krt.py repo-quality-check --check toc_files
py -3 tools\krt.py repo-quality-check --check lua_uniformity
py -3 tools\krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-lua-syntax.ps1
py -3 tools\krt.py api-catalog-refresh
```

Expected: all commands exit `0`.

---

## Spark Handoff Prompt

```text
Implement Wave C2 from the closed tasks in
docs/superpowers/plans/2026-06-14-audit-cleanup-wave-c2-raid-store-runtime-boundaries.md.

Scope:
- Runtime code may change only in !KRT/Database/DBRaidStore.lua.
- Add tests/audit_cleanup_wave_c2_raid_store_runtime_boundaries_spec.lua.
- Add the focused release stabilization test described in Task 2.
- Update docs/TECH_CLEANUP_BACKLOG.md for Wave C2 completion.
- Refresh generated catalogs only with py -3 tools/krt.py api-catalog-refresh.

Constraints:
- Keep the diff minimal.
- Do not change persisted raid schema, SavedVariables shape, public RaidStore API names,
  query behavior, services, controllers, widgets, XML, or vendored libraries.
- Preserve Lua 5.1 syntax and existing KRT style.
- Follow the plan tasks exactly. Do not add speculative cleanup.
```

---

## Execution Options

1. **Subagent-Driven (recommended)** - Parent uses `code-mapper` to confirm the
   current call paths and owner boundaries, delegates the bounded patch to
   `spark_implementer`, then reviews and corrects the final diff before closing.

2. **Inline Execution** - Parent implements the plan directly in this session,
   still following the same task order and running all verification gates.
