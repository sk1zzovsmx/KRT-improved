# Runtime Cleanup Follow-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining cleanup backlog by making public runtime facades
the only production path, removing local duplicate fallbacks, documenting vendor
policy, and verifying with KRT gates.

**Architecture:** Keep behavior unchanged while tightening ownership boundaries.
`Modules/Comms.lua`, `Modules/Strings.lua`, and `Database/DB.lua` remain the
canonical owners; consumers bind these APIs directly instead of carrying logic
clones.

**Tech Stack:** WotLK 3.3.5a addon, Lua 5.1, KRT PowerShell/Python quality gates, Lua release stabilization tests.

---

### Task 1: Public Comms Payload Contract

**Files:**
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `!KRT/Services/Loot/DistributionSession.lua`
- Modify: `docs/LUA_ALIGNMENT_MATRIX.md`

- [x] **Step 1: Write the failing test**

Change the comms payload test to use `h.addon.Comms.Payload` and assert that
production services do not call `Comms._Payload`.

- [x] **Step 2: Run the focused test**

Run: `lua tests/release_stabilization_spec.lua`
Expected before implementation: failure if any public payload method is missing
or consumer text still references `_Payload`.

- [x] **Step 3: Remove private payload consumer fallback**

Bind `Comms.Payload` directly in `DistributionSession.lua`; keep the local
encode/decode wrappers only as semantic adapters around the public payload API.

- [x] **Step 4: Run the focused test again**

Run: `lua tests/release_stabilization_spec.lua`
Expected after implementation: `262 targeted stabilization test(s) passed.`

### Task 2: Canonical String Helpers

**Files:**
- Modify: `!KRT/Services/Raid/State.lua`
- Modify: `!KRT/Services/Reserves/Aliases.lua`
- Modify: `!KRT/Services/Reserves/Import.lua`
- Modify: `!KRT/Services/Reserves/Chat.lua`
- Modify: `!KRT/Services/Loot/DistributionSession.lua`

- [x] **Step 1: Write structural guard**

Add or update a release-stabilization structural assertion so KRT-owned
consumers do not reimplement string trim/normalization when `feature.Strings`
is required by load order.

- [x] **Step 2: Run the focused test**

Run: `lua tests/release_stabilization_spec.lua`
Expected before implementation: failure on at least one local string helper clone.

- [x] **Step 3: Replace helper clones**

Replace local trim/normalize implementations with aliases to `Strings.TrimText`,
`Strings.NilIfEmpty`, `Strings.NormalizeText`, `Strings.NormalizeName`, or
`Strings.NormalizeLower`.

- [x] **Step 4: Run the focused test again**

Run: `lua tests/release_stabilization_spec.lua`
Expected after implementation: all release stabilization tests pass.

### Task 3: Single Boss-Record Predicate Owner

**Files:**
- Modify: `!KRT/Database/DB.lua`
- Modify: `!KRT/Database/DBRaidQueries.lua`
- Modify: `!KRT/Database/DBRaidStore.lua`
- Modify: `!KRT/Services/Logger/View.lua`
- Modify: `docs/LUA_ALIGNMENT_MATRIX.md`

- [x] **Step 1: Write owner test**

Add a structural assertion that only `Database/DB.lua` defines `local function isBossFightRecord`.

- [x] **Step 2: Run the focused test**

Run: `lua tests/release_stabilization_spec.lua`
Expected before implementation: failure because DBRaidQueries, DBRaidStore, and Logger View still define local clones.

- [x] **Step 3: Promote public predicate**

Expose `Database.IsBossFightRecord` in `DB.lua`, keep `_IsBossFightRecord` as
compatibility alias, and have consumers bind the canonical predicate without
fallback clones.

- [x] **Step 4: Run the focused test again**

Run: `lua tests/release_stabilization_spec.lua`
Expected after implementation: all release stabilization tests pass.

### Task 4: Focused UI Scaffold/List Cleanup

**Files:**
- Modify: `!KRT/Controllers/Logger.lua`
- Modify: `!KRT/Modules/UI/ListController.lua`
- Modify: `docs/UI_CODING_RULES.md`

- [x] **Step 1: Add helper contract guard**

Add a structural assertion for any new `UI.Lists` helper used by Logger list controllers.

- [x] **Step 2: Extract repeated list helpers**

Add a small `UI.Lists` helper for stable row-name creation, then replace the
repeated list closures that match the helper exactly.

- [x] **Step 3: Run focused checks**

Run: `lua tests/release_stabilization_spec.lua`
Expected after implementation: all release stabilization tests pass.

### Task 5: Vendor Duplicate Decision

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/OVERVIEW.md`
- Modify: `docs/DEV_CHECKS.md`
- Modify: `!KRT/CHANGELOG.md`

- [x] **Step 1: Document decision**

State that nested vendor copies remain intentionally untouched because
`!KRT/Libs/**` is third-party package content and current packaging does not
permit removal.

- [x] **Step 2: Add verification note**

Document that release packaging must be changed before deleting nested vendor copies.

### Task 6: Final Verification and Commit

**Files:**
- Generated docs may change from API catalog refresh.

- [x] **Step 1: Run final gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
lua tests/release_stabilization_spec.lua
git diff --check
```

- [x] **Step 2: Commit**

Commit runtime/doc changes together with refreshed generated API docs if the pre-commit hook updates them.
