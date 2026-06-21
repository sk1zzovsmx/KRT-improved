# Wave Q1: Loot getRaidQueries Owner Group

Status: implementation wave.

## Goal

Remove the remaining memoized `getRaidQueries` owner pattern from
`!KRT/Services/Loot/Service.lua` while preserving passive loot upgrade behavior.

This wave starts from the backlog references:

- `docs/TECH_CLEANUP_BACKLOG.md`, Wave 5 follow-up
- `docs/TECH_CLEANUP_BACKLOG.md`, Default Next Step

## Classification

Complex-orchestrated.

Reasons:

- Touches a runtime service under `!KRT/Services/Loot/*`.
- Changes a shared Database query access path used during loot backfill.
- Needs behavior coverage for late `Database.GetRaidQueriesOrNil` assignment semantics.
- Needs backlog and generated API documentation review after the patch.

Execution should use the project delegated workflow:

1. Parent maps and plans.
2. `code-mapper` confirms the exact call path and branch behavior.
3. `spark_implementer` applies only the approved minimal patch.
4. Parent reviews, corrects if needed, and runs final gates.

## Scope

Primary runtime file:

- `!KRT/Services/Loot/Service.lua`

Expected test files:

- `tests/audit_cleanup_wave_q1_loot_get_raid_queries_spec.lua`
- `tests/release_stabilization_spec.lua`

Expected documentation and generated files:

- `docs/TECH_CLEANUP_BACKLOG.md`
- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/TREE.md` if regenerated tooling changes it

## Non-Goals

- Do not change SavedVariables shape.
- Do not change loot award, trade, passive group loot, or roll resolution behavior.
- Do not touch `!KRT/Services/Raid/LootRecords.lua` in this wave.
- Do not touch `!KRT/Services/Raid/State.lua` in this wave.
- Do not remove the `Database/DBRaidQueries` registry dependency from Loot Service in Q1.

If mapping proves the registry dependency should be removed, stop and revise the plan instead of
folding that boundary decision into this wave.

## Current Map

`!KRT/Services/Loot/Service.lua` currently owns a local memoized query reference:

- `local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil`
- `local function getRaidQueries()`

The wrapper is used by `resolveStoredLootLooterName(raid, raidNum, loot)`, which resolves a
stored looter name through `queries:ResolveLootLooterName(raid, loot)` and then falls back to
`Services.Raid:GetPlayerName(looterNid, raidNum)`.

That helper participates in `findUpgradeablePassiveLootEntry(...)`, so the regression risk is
passive logged-loot upgrade and late roll backfill matching.

The mapper confirmed that trade-only fallback reuse is a separate branch through
`Reconcile.FindTradeOnlyFallback(...)`; it is nearby regression coverage but does not prove this
query path.

Other remaining owners stay out of Q1:

- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Raid/State.lua`

`!KRT/Database/DBSyncer.lua` is already on the optional query facade after Wave C1.

## Implementation Plan

### 1. Mapping Gate

Use `code-mapper` read-only before implementation.

Confirm:

- The only Loot Service caller of the local wrapper is `resolveStoredLootLooterName`.
- `resolveStoredLootLooterName` still needs the Raid service fallback.
- The relevant behavior surface is passive logged-loot upgrade/backfill matching.
- Keeping the explicit `Database/DBRaidQueries` registry dependency is still valid for Q1.

### 2. Add Source Contract Test

Create `tests/audit_cleanup_wave_q1_loot_get_raid_queries_spec.lua`.

The test should fail before the implementation and assert that Loot Service:

- Uses `Database.GetRaidQueriesOrNil()`.
- Does not define `local RaidQueries =`.
- Does not define `local function getRaidQueries()`.
- Does not call `Database.GetRaidQueries` through a memoized local bootstrap.
- Keeps `resolveStoredLootLooterName(raid, raidNum, loot)`.
- Keeps `queries:ResolveLootLooterName(raid, loot)`.
- Keeps the Raid service `GetPlayerName(looterNid, raidNum)` fallback.
- Keeps the explicit `"Database/DBRaidQueries"` module registry dependency for Q1.

The same test should assert backlog progress:

- `docs/TECH_CLEANUP_BACKLOG.md` records Wave Q1 completion once implemented.
- The backlog still lists the Raid owner groups left for later waves.

### 3. Add Behavior Regression Test

Extend `tests/release_stabilization_spec.lua` with one focused test.

Suggested test name:

- `loot service resolves stored looter through current query facade`

The test should load Loot Service first, then override the Database query facade with a custom
`GetRaidQueriesOrNil` result. It should create an existing passive logged-loot row whose
`looterNid` cannot be resolved by the Raid fallback, then call
`Loot:UpgradeLoggedPassiveLootRoll(...)` for the matching looter and roll session.

Expected assertions:

- The custom query facade is called after Loot Service has already loaded.
- The existing passive row is upgraded.
- No duplicate loot row is created.
- The Raid fallback behavior remains available but is not required for that case.

This proves Q1 removes the stale local cache behavior rather than only changing source shape.

### 4. Minimal Runtime Patch

In `!KRT/Services/Loot/Service.lua`:

- Remove the local `RaidQueries` cache.
- Remove `local function getRaidQueries()`.
- Replace the wrapper call in `resolveStoredLootLooterName` with
  `Database.GetRaidQueriesOrNil()`.
- Preserve nil-safe behavior when the facade is unavailable.
- Preserve the Raid service fallback exactly.
- Keep the module registry dependency on `Database/DBRaidQueries`.

Do not rewrite surrounding loot logic.

### 5. Backlog Update

Update `docs/TECH_CLEANUP_BACKLOG.md` to record:

- Wave Q1 completed the Loot Service owner group.
- `!KRT/Services/Loot/Service.lua` no longer has a memoized `getRaidQueries` wrapper.
- Remaining owner groups are `!KRT/Services/Raid/LootRecords.lua` and
  `!KRT/Services/Raid/State.lua`.
- `!KRT/Database/DBSyncer.lua` remains completed by Wave C1.

### 6. Generated Docs

After code edits, run the API catalog refresh path used by the repo hooks.

Expected files to review:

- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/TREE.md`

Only keep generated changes that are real consequences of the patch.

### 7. Verification

Run:

```powershell
lua tests/audit_cleanup_wave_q1_loot_get_raid_queries_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
git diff --check
```

If generated docs drift is reported, run the repo-local refresh command indicated by the failing
gate and then rerun the affected tests.

## Parent Review Checklist

Before closing the wave, verify:

- The diff matches this plan and stays limited to the Loot owner group.
- The source contract test fails on the old pattern and passes on the new pattern.
- The behavior test proves late facade lookup after Loot Service load.
- No Raid service owner files were changed.
- No registry dependency was removed from Loot Service.
- No SavedVariables, TOC load order, XML, or user-visible behavior changed.
- `docs/TECH_CLEANUP_BACKLOG.md` points to the next remaining owner group.

