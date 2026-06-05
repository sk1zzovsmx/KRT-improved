# Core Persistence And Sync Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve Core persistence and logger sync robustness/performance in place.

**Status:** Implemented and verified in this workspace. Final evidence:
`tools/run-release-targeted-tests.ps1` passed with 188 tests,
`py -3 tools/krt.py repo-quality-check --check all` passed, and `tools/pre-commit.ps1` passed.

**Architecture:** Keep existing Core files and public APIs. Add local helpers and stricter guards only where they reduce
repeated work or malformed-input risk. Preserve SavedVariables shape and sync protocol version.

**Tech Stack:** WoW 3.3.5a addon Lua 5.1, repo Lua harness in `tests/release_stabilization_spec.lua`, PowerShell/Python
repo checks.

---

## File Map

- Modify: `tests/release_stabilization_spec.lua`
  - Keep the targeted harness aligned with current dataset paths.
  - Add focused regression tests for Core persistence and sync hardening.
- Modify: `!KRT/Core/DBRaidStore.lua`
  - Cache raid-NID index rebuilds conservatively.
  - Avoid cold runtime double normalization.
  - Use runtime signatures to detect stale indexes.
  - Preserve valid unique raid NIDs on insert.
- Modify: `!KRT/Core/DBRaidValidator.lua`
  - Skip `_runtime` during normalized clone.
  - Avoid duplicate migration pass when raid store normalization is available.
  - Reduce small per-raid allocations.
- Modify: `!KRT/Core/DBSyncer.lua`
  - Add empty text fast path.
  - Throttle expired-state cleanup.
  - Avoid ordered chunk copy.
  - Add fail-fast snapshot parse/schema guards.

## Task 1: Restore Targeted Test Baseline

**Files:**

- Modify: `tests/release_stabilization_spec.lua`

- [x] **Step 1: Update harness dataset paths**

Replace stale test-only paths:

```lua
"!KRT/Modules/IgnoredMobs.lua"
"!KRT/Modules/IgnoredItems.lua"
"!KRT/Modules/LootSourcesData.lua"
```

with:

```lua
"!KRT/Modules/Dataset/IgnoredMobs.lua"
"!KRT/Modules/Dataset/IgnoredItems.lua"
"!KRT/Modules/Dataset/LootSourcesData.lua"
```

- [x] **Step 2: Run targeted stabilization tests**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: `181 targeted stabilization test(s) passed.`

## Task 2: Raid Store And Validator Hardening

**Files:**

- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/Core/DBRaidStore.lua`
- Modify: `!KRT/Core/DBRaidValidator.lua`

- [ ] **Step 1: Add failing tests**

Add tests near the existing runtime cache tests:

```lua
test("runtime cache rebuilds when signature changes without explicit strip", function()
    local h = newHarness()
    h:load("!KRT/Core/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = store:CreateRaidRecord({
        raidNid = 10,
        zone = "Naxxramas",
        size = 25,
        difficulty = 4,
        startTime = 1000,
    })
    raid.players[1] = { playerNid = 1, name = "Alice" }
    local runtime1 = store:EnsureRaidRuntime(raid)
    assertEqual(runtime1.playerIdxByNid[1], 1, "expected first player index")

    raid.players[2] = { playerNid = 2, name = "Bob" }
    raid.nextPlayerNid = 3
    local runtime2 = store:EnsureRaidRuntime(raid)
    assertEqual(runtime2.playerIdxByNid[2], 2, "expected signature drift to rebuild runtime")
end)

test("raid insert preserves unique raid nid and replaces duplicate raid nid", function()
    local h = newHarness()
    local store = h:installRaidStore({
        { schemaVersion = 1, raidNid = 77, players = {}, bossKills = {}, loot = {}, changes = {}, attendance = {} },
    })

    local unique = store:CreateRaidRecord({ raidNid = 88, zone = "Naxxramas", size = 25, difficulty = 4 })
    local insertedUnique = store:InsertRaid(unique)
    assertEqual(insertedUnique.raidNid, 88, "expected unique raid nid to be preserved")

    local duplicate = store:CreateRaidRecord({ raidNid = 77, zone = "Ulduar", size = 25, difficulty = 4 })
    local insertedDuplicate = store:InsertRaid(duplicate)
    assertTrue(insertedDuplicate.raidNid ~= 77, "expected duplicate raid nid to be replaced")
    assertTrue(store:GetRaidByNid(insertedDuplicate.raidNid) == insertedDuplicate, "expected inserted raid to be indexed")
end)
```

Add a validator clone test near validator coverage:

```lua
test("raid validator skips runtime clone but still reports legacy runtime keys", function()
    local h = newHarness()
    local store = h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
            attendance = {},
            _runtime = { playersByName = { Alice = { name = "Alice" } } },
            _playersByName = {},
        },
    })
    h:load("!KRT/Modules/Dataset/IgnoredMobs.lua")
    h:load("!KRT/Core/DBRaidValidator.lua")
    h.Core.GetRaidValidator = function()
        return h.addon.DB.RaidValidator
    end

    local report = h.addon.DB.RaidValidator:ValidateAllRaids({ includeInfo = true, maxDetails = 20 })
    assertTrue(report.err > 0, "expected legacy runtime key to be reported")
    assertTrue(_G.KRT_Raids[1]._runtime ~= nil, "expected validation to leave source runtime intact")
    assertTrue(store:IsLegacyRuntimeKey("_playersByName"), "expected legacy key policy to remain available")
end)
```

- [ ] **Step 2: Verify tests fail**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: new runtime/index tests fail before implementation.

- [ ] **Step 3: Implement store and validator changes**

In `DBRaidStore.lua`:

- Add dirty/clean helpers for `storeState.raidIdxByNid`.
- Replace unconditional read-path `rebuildRaidNidIndex()` with conservative `ensureRaidNidIndex()`.
- Extract private normalized runtime index builder and call it from `EnsureRaidRuntime()`.
- Compare `runtime.signature` before reusing a ready runtime.
- Preserve valid unique `raid.raidNid` in `InsertRaid()`.

In `DBRaidValidator.lua`:

- Change the clone helper to skip `_runtime`.
- Apply migrations directly only if no raid store normalization is available.
- Replace the per-call `checks` table in `validateNidCounters()` with direct helper calls.

- [ ] **Step 4: Verify green**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: targeted tests pass.

## Task 3: DBSyncer Hot Path And Parser Hardening

**Files:**

- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/Core/DBSyncer.lua`

- [ ] **Step 1: Add failing tests**

Add tests near the existing DBSyncer tests:

```lua
test("db syncer rejects malformed snapshot payloads without import", function()
    local h = newHarness()
    h:installRaidStore({})
    h.addon.IsInGroup = function()
        return true
    end
    h.addon.IsInRaid = function()
        return false
    end
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Core/DBSyncer.lua")

    local function sendPayload(payload)
        local encoded = h.addon.Base64.Encode(payload)
        local msg = table.concat({ "SN", "1", tostring(#h.logs.warn + 1), "PUSH", "77", "1", "1", encoded }, "\t")
        h.addon.DB.Syncer:OnAddonMessage("KRTLogSync", msg, "WHISPER", "Alice")
    end

    sendPayload(table.concat({ "P\t1\tAlice\t0\t1\tMAGE\t0\t0\t0" }, "\n"))
    sendPayload(table.concat({
        "H\t1\t1\t77\tTmF4eHJhbWFz\t25\t4\tVGVzdFJlYWxt\t1000\t0\t1\t1\t1",
        "X\tbad",
    }, "\n"))
    sendPayload(table.concat({
        "H\t1\t999\t77\tTmF4eHJhbWFz\t25\t4\tVGVzdFJlYWxt\t1000\t0\t1\t1\t1",
    }, "\n"))

    assertEqual(#_G.KRT_Raids, 0, "expected malformed snapshots to import nothing")
    assertContains(h.logs.warn, "Diag.W.LogSyncParseFailed", "expected parse failure warning")
end)
```

- [ ] **Step 2: Verify test fails**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: malformed snapshot test fails before parser hardening.

- [ ] **Step 3: Implement syncer changes**

In `DBSyncer.lua`:

- Return `""` immediately from `encodeText(nil)` and `encodeText("")`.
- Add throttling to `cleanupExpiredState()` calls from addon-message intake.
- Reject duplicate/missing headers, unknown row kinds, truncated known rows, invalid required NIDs, and future schema versions in `parseSnapshotPayload()`.
- In completed chunk assembly, validate all `state.parts[i]` then call `tconcat(state.parts, "")` directly.
- Keep `PROTOCOL_VERSION = 1`.

- [ ] **Step 4: Verify green**

Run:

```powershell
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected: targeted tests pass.

## Task 4: Full Verification

**Files:**

- No planned source edits.

- [ ] **Step 1: Run repo quality check**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all checks pass.

- [ ] **Step 2: Run pre-commit gate**

Run:

```powershell
powershell -NoProfile -File tools/pre-commit.ps1
```

Expected: gate passes.
