# Technical Cleanup Backlog

Repo-wide cleanup program built on top of `docs/TECH_CLEANUP_WORKFLOW.md`.

Status date: 2026-03-14

## 1.1 Cleanup Snapshot (2026-04-05)

Completed in this pass:

- Removed redundant parent re-bootstrap from feature files:
  `addon.Controllers = addon.Controllers or {}` and
  `addon.Widgets = addon.Widgets or {}` now remain only in bootstrap.
- Removed redundant service re-bootstrap from feature/service files:
  `addon.Services = addon.Services or {}` now remains only in bootstrap.
- Removed fallback no-op shims for UI facade in EntryPoints/Controllers where
  `Modules/UI/Facade.lua` already guarantees `addon.UI:Call()` and related APIs.
- Removed broad `or {}` fallback aliases for `feature.Services` in feature files,
  keeping fail-fast behavior aligned with canonical bootstrap contracts.
- Reduced redundant `addon.DB` re-bootstrap in secondary Core DB files that load
  after bootstrap according to TOC order.
- Removed residual diagnostic fallbacks on `feature.Diag` and `feature.Events`
  (`or {}`) in Core/Init high-churn boundaries.
- Ran conservative deadcode scan (`fnmap-inventory` + `fnmap-classify`): no
  `delete` candidates with definite confidence; only merge/rename clusters.

Residual redundancy catalog (post-cleanup):

1. `addon.DB = addon.DB or {}` remains in:
   - `!KRT/Init.lua`
   Rationale: canonical bootstrap ownership.

2. `addon.Services.Logger = addon.Services.Logger or {}` remains in:
   - `!KRT/Init.lua`
   - `!KRT/Services/Logger/Store.lua`
   Rationale: Init is canonical bootstrap; Store keeps a compatibility fallback
   for harness/standalone module loads.

## 1. Audit Snapshot

Signals used for this backlog:

- `tools/check-layering.ps1`: passed
- `tools/check-ui-binding.ps1`: passed
- file-size scan for KRT-owned Lua and XML
- module contract scan for `module._ui`, `UIScaffold`, and frame getter usage

What this means:

- Parent UI ownership is now largely normalized.
- No binder regression or inline XML script regression is present.
- The next technical ROI is in large Services, EntryPoints, and a few infra files.

## 2. Status by Module

### 2.1 Controllers

- `!KRT/Controllers/Master.lua`: closed for baseline UI normalization, monitor only
- `!KRT/Controllers/Logger.lua`: closed for baseline UI normalization, monitor only
- `!KRT/Controllers/Warnings.lua`: closed for baseline UI normalization
- `!KRT/Controllers/Changes.lua`: closed for baseline UI normalization
- `!KRT/Controllers/Spammer.lua`: closed for baseline UI normalization

### 2.2 Widgets

- `!KRT/Widgets/Config.lua`: closed for baseline UI normalization
- `!KRT/Widgets/LootCounter.lua`: closed for baseline UI normalization
- `!KRT/Widgets/ReservesUI.lua`: closed for baseline UI normalization

### 2.3 Services

- `!KRT/Services/Raid.lua`: cleanup wave S1 in progress
- `!KRT/Services/Rolls.lua`: cleanup wave S2 in progress
- `!KRT/Services/Reserves.lua`: cleanup wave S3 in progress
- `!KRT/Services/Loot.lua`: monitor, medium priority only if duplication or ownership drift appears
- `!KRT/Services/Chat.lua`: hold, low priority
- `!KRT/Services/Debug.lua`: hold, low priority

### 2.4 EntryPoints

- `!KRT/EntryPoints/SlashEvents.lua`: cleanup wave E1 in progress
- `!KRT/EntryPoints/Minimap.lua`: cleanup wave E2 in progress

### 2.5 Core and Infra

- `!KRT/Core/DBSyncer.lua`: cleanup wave C1 in progress
- `!KRT/Core/DBRaidStore.lua`: cleanup wave C2 in progress
- `!KRT/Modules/UI/Frames.lua`: cleanup wave U1 in progress
- `!KRT/Init.lua`: cleanup wave B1 in progress

### 2.6 XML

- `!KRT/UI/Logger.xml`: closed for structural cleanup
- `!KRT/UI/Master.xml`: closed for structural cleanup
- `!KRT/UI/Config.xml`: closed for structural cleanup
- `!KRT/UI/LootCounter.xml`: closed for structural cleanup
- `!KRT/UI/Reserves.xml`: closed for structural cleanup
- `!KRT/UI/Warnings.xml`: closed for structural cleanup
- `!KRT/UI/Changes.xml`: closed for structural cleanup
- `!KRT/UI/Spammer.xml`: closed for structural cleanup
- `!KRT/UI/Minimap.xml`: hold, low priority
- `!KRT/UI/ReservesTemplates.xml`: hold, low priority

## 3. Priority Order

### P1: Service Monolith Cleanup

These files are the highest-value technical cleanup targets because they are
large, central, and still own mixed concerns.

1. `!KRT/Services/Raid.lua` - about 1885 lines
2. `!KRT/Services/Rolls.lua` - about 1781 lines
3. `!KRT/Services/Reserves.lua` - about 1635 lines

### P2: Routing and Infra Cleanup

These files are smaller than the service monoliths but still good cleanup
targets because they sit on repo-wide boundaries.

1. `!KRT/EntryPoints/SlashEvents.lua` - about 689 lines
2. `!KRT/EntryPoints/Minimap.lua` - about 406 lines
3. `!KRT/Core/DBSyncer.lua` - about 1442 lines
4. `!KRT/Core/DBRaidStore.lua` - about 799 lines
5. `!KRT/Modules/UI/Frames.lua` - about 719 lines

### P3: Bootstrap Follow-up

1. `!KRT/Init.lua` - about 1413 lines

This should stay a follow-up lane. Do not reopen it early unless a cleanup wave
proves a residual owner clearly belongs elsewhere.

## 4. Recommended Cleanup Waves

### Wave S1: Raid Service

Owner files:
- `!KRT/Services/Raid.lua`

Scope:
- separate roster tracking, live-unit caching, raid-instance checks, and loot
  bookkeeping into clearer internal clusters
- tighten state ownership and helper naming
- reduce mixed responsibilities inside long helper chains

Current worktree progress:
- timer cancellation and delayed roster-refresh scheduling are centralized
- placeholder player creation and playerNid recovery now share one helper path

Non-goals:
- no gameplay behavior changes
- no SavedVariables shape changes
- no UI work

Validation:
- `tools/check-layering.ps1`
- `tools/check-lua-syntax.ps1`
- targeted `luacheck` while iterating
- broader Lua gates before closing the wave

Smoke path:
- login
- raid detection
- roster updates
- boss/loot registration paths

### Wave S2: Rolls Service

Owner files:
- `!KRT/Services/Rolls.lua`

Scope:
- separate session, eligibility, response-state, and resolver helpers more
  clearly
- make public service contract easier to audit
- reduce risk from long stateful functions

Current worktree progress:
- current roll context recovery is centralized for submit, validate, and display flows
- response-state preparation and seeding now share one helper path

Non-goals:
- no winner-policy changes
- no visible roll-flow behavior changes

Validation:
- all standard Lua gates
- `tools/krt.py run-release-targeted-tests`

Smoke path:
- start roll
- accept rolls
- pass, cancel, timeout
- tie reroll
- award flow through `Master`

### Wave S3: Reserves Service

Owner files:
- `!KRT/Services/Reserves.lua`

Scope:
- separate import parsing, runtime indexes, display-list building, and pending
  item-info refresh logic
- reduce legacy-payload handling drift where safe
- keep service-only ownership with no UI leakage

Current worktree progress:
- reserve-index rebuild and change publication now share one helper path
- itemId-based entry scans now use one helper for item-data updates and multi-reserve checks

Non-goals:
- no reserve rules change
- no import format change unless explicitly requested

Validation:
- all standard Lua gates
- reserves-focused smoke path after `/reload`

Smoke path:
- import multi mode
- import plus mode
- reserve counts
- list refresh after item info resolves

### Wave E1: Slash Routing

Owner files:
- `!KRT/EntryPoints/SlashEvents.lua`

Scope:
- keep the file focused on slash parsing and dispatch only
- reduce inline formatting/report helpers if they belong to owners or services
- normalize routing helpers around `Core.GetController(...)` and `addon.UI`

Current worktree progress:
- controller method dispatch now shares one helper path across toggle and action commands

Non-goals:
- no command syntax changes
- no help-text behavior changes

Validation:
- standard Lua gates

Smoke path:
- `/krt`
- `/krt logger`
- `/krt loot`
- `/krt reserves`
- `/krt validate`

### Wave E2: Minimap EntryPoint

Owner files:
- `!KRT/EntryPoints/Minimap.lua`
- `!KRT/UI/Minimap.xml` only if structural cleanup becomes necessary

Scope:
- simplify menu-building and widget/controller routing
- reduce fallback shim drift where canonical owners already exist
- keep the allowed drag `OnUpdate` path explicit and isolated

Current worktree progress:
- controller and widget dispatch from the minimap menu now share helper paths
- loot-counter fallback routing is centralized without changing menu behavior

Non-goals:
- no menu option changes unless tied to cleanup correctness

Validation:
- standard Lua gates
- `tools/check-ui-binding.ps1` if XML also changes

Smoke path:
- minimap open
- drag
- menu actions
- widget toggles

### Wave C1: Syncer Store Boundary

Owner files:
- `!KRT/Core/DBSyncer.lua`

Scope:
- separate protocol parsing, merge logic, and persistence boundaries
- reduce long-function pressure and improve deterministic merge helpers

Current worktree progress:
- group sync gating now shares one helper across request, push, and sync entrypoints
- target normalization and pending-request registration now use one helper path
- sync sender failure bookkeeping now shares one helper across merge and payload-validation paths

Non-goals:
- no sync payload contract changes without explicit migration plan

Validation:
- standard Lua gates
- sync-specific manual smoke if available

### Wave C2: Raid Store Runtime Boundaries

Owner files:
- `!KRT/Core/DBRaidStore.lua`

Scope:
- tighten runtime-index ownership
- make invalidation and rebuild paths easier to audit
- reduce duplication with query/validator helpers where possible

Current worktree progress:
- NID allocation for raid, player, boss, and loot normalization now shares one helper path
- runtime table acquisition, runtime index-map reset, and runtime signature building now share local helpers

Non-goals:
- no persisted raid schema changes

Validation:
- standard Lua gates
- `tools/krt.py run-raid-validator --saved-variables-path <path>` if impacted

### Wave U1: UI Scaffold Infrastructure

Owner files:
- `!KRT/Modules/UI/Frames.lua`

Scope:
- keep scaffold contract explicit and centralized
- prune drift between frame helpers and module UI lifecycle helpers
- avoid expanding infra API surface without clear reuse

Current worktree progress:
- frame-name resolution now shares one helper across generic frame helper entrypoints
- UI-bound checks and show-with-refresh flow now share local helper paths inside the scaffold

Non-goals:
- no broad UI behavior rewrite

Validation:
- standard Lua gates
- smoke only on modules touched by scaffold behavior

### Wave B1: Bootstrap Follow-up

Owner files:
- `!KRT/Init.lua`

Scope:
- move residual feature-specific glue out only when ownership is clear
- keep bootstrap ownership centralized without becoming a catch-all

Current worktree progress:
- raid-store access now shares one helper path across core schema and SavedVariables boundaries
- raid and service lookups in WoW event handlers now share helpers and no longer route boss logging through legacy `self.Raid`

Non-goals:
- no speculative splitting
- no event-wiring rewrite without evidence

Validation:
- broad Lua gates
- full addon smoke

## 5. Low-Priority Holds

These are not strong cleanup candidates right now.

- `!KRT/Services/Chat.lua`: small and single-purpose
- `!KRT/Services/Debug.lua`: useful as synthetic tooling, keep as-is unless it
  blocks testability
- `!KRT/Services/Loot.lua`: monitor after `Raid` and `Rolls`; do not reopen
  early without duplicate-ownership evidence
- `!KRT/UI/Minimap.xml`: only structural cleanup if paired with `Minimap.lua`
- `!KRT/UI/ReservesTemplates.xml`: cleanup only if a template-owner issue shows up

## 6. Guardrails for This Backlog

1. Do not reopen already-stable UI parent owners without a concrete bug or UX
   change.
2. Prefer one owner wave at a time.
3. Keep service cleanup service-only unless a direct owner boundary forces a
   small paired change.
4. Run targeted tests whenever `Master` or `Rolls` are touched.
5. Use `docs/TECH_CLEANUP_WORKFLOW.md` for the per-wave execution checklist.

## 7. Default Next Step

If continuing the cleanup program immediately, start with:

1. `!KRT/Services/Raid.lua`
2. `!KRT/Services/Rolls.lua`
3. `!KRT/Services/Reserves.lua`

That sequence gives the best technical ROI while keeping the already-stable UI
owner layer closed.

## 8. Services Redundancy Catalog (Analysis-only, 2026-04-05)

Scope of this catalog:

- `!KRT/Services/Raid.lua`
- `!KRT/Services/Rolls.lua`
- `!KRT/Services/Reserves.lua`

No behavior changes were applied in this pass. This section records only
verified redundancy signals with direct file evidence.

### 8.1 High-confidence structural redundancies

1. `Reserves`: duplicated API surface (`Service:*` + `module:*` delegate 1:1).
  Evidence examples:
  - `Service:Save` at line 807 and `module:Save` at line 1602
  - `Service:Load` at line 814 and `module:Load` at line 1606
  - `Service:GetImportMode` at line 877 and `module:GetImportMode` at line 1642
  - `Service:ParseImport` at line 1186 and `module:ParseImport` at line 1662
  - `Service:GetPlayersForItem` at line 1502 and `module:GetPlayersForItem`
    at line 1706
  Assessment: pure delegation boilerplate, high maintenance overhead.
  Suggested cleanup lane: S3, with compatibility-preserving public facade.

2. `Rolls`: legacy alias with equivalent behavior.
  Evidence:
  - `module:GetDisplayModel` at line 1878
  - `module:FetchRolls` at line 1883 (legacy alias returning `GetDisplayModel`)
  Assessment: intentional compatibility alias; redundancy is known and low risk.
  Suggested cleanup lane: S2, only after call-site census.

3. `Raid`: local alias with equivalent behavior.
  Evidence:
  - `module:GetRaid` at line 1489
  - `module:ResolveRaid` at line 1616 (returns `module:GetRaid`)
  Assessment: semantic alias, low immediate cost, but redundant surface.
  Suggested cleanup lane: S1, only with usage verification.

### 8.2 Medium-confidence technical redundancies

1. `Raid` DB facade wrappers are repeated with similar guard + dispatch shape:
  `GetRaidChanges` (line 1504), `UpsertRaidChange` (line 1523),
  `DeleteRaidChange` (line 1538), `ClearRaidChanges` (line 1553).
  Assessment: mostly intentional service boundary, but helper extraction could
  reduce repeated control flow.

2. `Rolls` module methods expose local helper outputs almost verbatim:
  `GetRollSession` (line 1887), `GetRollSessionItemKey` (line 1891),
  `EnsureRollSession` (line 1904), `FinalizeRollSession` (line 1992).
  Assessment: likely acceptable service API, but naming/collision noise remains.

### 8.3 Deadcode outcome for these Services

- No definite delete candidates were identified in this pass.
- Current signals are redundancy/alias clusters (`merge`/`rename`), not safe
  deadcode removals.
