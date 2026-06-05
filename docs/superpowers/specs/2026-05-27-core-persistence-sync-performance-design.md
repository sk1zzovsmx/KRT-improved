# Core Persistence And Sync Performance Design

Date: 2026-05-27
Status: Approved for implementation planning

## Goal

Improve robustness and runtime cost of Core persistence and logger sync without changing public Core APIs, SavedVariables
shape, sync protocol version, or addon load order.

## Scope

In scope:

- In-place optimization of `!KRT/Core/DBRaidStore.lua`.
- In-place optimization of `!KRT/Core/DBRaidValidator.lua`.
- In-place optimization of `!KRT/Core/DBSyncer.lua`.
- Test harness upkeep needed to keep targeted stabilization tests aligned with current dataset paths.
- Focused tests for runtime cache invalidation, raid-NID uniqueness, sync malformed payload rejection, and chunk assembly.

Out of scope:

- Splitting Core files.
- Changing `!KRT/!KRT.toc`.
- Changing sync protocol version.
- Changing `KRT_Raids` or other SavedVariables shape.
- Removing existing migrations.
- Renaming public Core contracts.

## Design

`DBRaidStore` should avoid repeated full-history normalization when read paths only need an up-to-date raid-NID index.
The raid-NID index can remain runtime-only under `addon.State.raidStore`, but it should be reused while clean and rebuilt
only when the raid count changes or known mutators mark it dirty. Runtime indexes should also be guarded by their existing
signature so a caller that mutates raid rows without stripping runtime does not keep stale maps.

`DBRaidValidator` should remain read-only and validate source keys before normalization. Its normalized clone path should
avoid copying `_runtime`, avoid applying migrations twice when `RaidStore:NormalizeRaidRecord()` is available, and avoid
small per-raid allocations in counter validation.

`DBSyncer` should keep the protocol wire format stable while reducing avoidable allocations and malformed-input work.
Empty text fields should skip Base64 encode work. Incoming chunk completion should concatenate the already verified
`state.parts` table directly. Cleanup scans should be throttled instead of running on every addon message. Snapshot parsing
should fail fast for duplicate/missing headers, unknown row kinds, truncated known rows, invalid required NIDs, and future
schema versions.

## Verification

Required checks:

- `powershell -NoProfile -File tools/run-release-targeted-tests.ps1`
- `py -3 tools/krt.py repo-quality-check --check all`
- `powershell -NoProfile -File tools/pre-commit.ps1`

Targeted tests should cover:

- Runtime indexes rebuild when signature drifts after direct row mutation.
- `InsertRaid()` preserves a valid unique `raidNid` and assigns a new one for duplicates.
- Validator clone skips `_runtime` while still reporting legacy runtime keys.
- Sync rejects malformed snapshots without importing or mutating raids.
- Sync chunk assembly does not allocate an ordered copy and still imports/merges valid chunks.
