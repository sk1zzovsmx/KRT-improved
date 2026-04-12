# Technical Cleanup Backlog

Repo-wide cleanup program built on top of `docs/TECH_CLEANUP_WORKFLOW.md`.

Status date: 2026-04-06

## 1.1 Cleanup Snapshot (2026-04-06)

Completed in this pass:

- Confirmed post-split `Raid` service topology:
  `!KRT/Services/Raid/{State,Capabilities,Changes,Counts,Roster,LootRecords,Session,Boss}.lua`
  now owns `addon.Services.Raid` end-to-end.
- Kept bootstrap ownership centralized: there is no standalone `!KRT/Services/Raid.lua`.
  The service table is anchored directly by the split modules.
- Regenerated docs catalogs for the current tree:
  `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`, `docs/API_REGISTRY*.csv`,
  `docs/API_NOMENCLATURE_CENSUS.md`, and `docs/TREE.md`.
- Re-ran split-wave analysis and refreshed redundancy evidence for
  `Raid/* <-> Loot.lua` bridge APIs and duplicate helper clusters.
- Completed S1b API contraction:
  - removed `Raid -> Loot` pass-through APIs from `!KRT/Services/Raid/State.lua`
  - migrated runtime call sites in `!KRT/Init.lua` and `!KRT/Controllers/Master.lua`
    to canonical `addon.Services.Loot` ingestion APIs
  - replaced `Loot -> Raid` `*Internal` bridge methods with narrower contracts
    (`FindOrCreateBossNidForLoot`, `FindAndRememberBossEventContextForLootSession`,
    `EnsureRaidPlayerNid`)
  - removed unused public aliases (`ResolveRaid`, `IncrementPlayerCount`,
    `DecrementPlayerCount`)
  - updated stabilization tests/harness for the new canonical `Loot` owner path

Residual redundancy catalog (post-split):

1. `merge-now` exact-clone candidates are exhausted in the current catalog.
   Rationale: no high-confidence merge target remains in `docs/FN_CLUSTERS.md`
   after the Chat/Raid contract wave re-catalog.

2. `Raid` still contains a lean loot-context bridge by design:
   `FindOrCreateBossNidForLoot`, `FindAndRememberBossEventContextForLootSession`,
   `EnsureRaidPlayerNid`.
   Rationale: narrow cross-service contract retained to avoid behavior regressions
   while keeping `Loot` as canonical ingestion owner.

3. Remaining catalog noise is now dominated by `name-collision` analysis, not by
   duplicated behavior.
   Rationale: these entries need owner/contract review, not mechanical merging.

## 1.2 API Redundancy Baseline (2026-04-06)

Fresh stage-0 recatalog completed with:

- `tools/fnmap-inventory.ps1`
- `tools/fnmap-classify.ps1`
- `tools/fnmap-api-census.ps1`
- `tools/update-tree.ps1`
- `py -3 tools/krt.py repo-quality-check --check all`

Current baseline:

- function inventory: `1642` entries
- API surface: `663` public+internal methods
- exact clones: `10`
- near clones: `6`
- name collisions: `341`

Stage-1 result snapshot:

- function inventory: `1609` entries
- API surface: `636` public+internal methods
- public API surface: `613`
- exact clones: `6`
- near clones: `0`
- name collisions: `295`

Final stage-2/stage-3 snapshot:

- function inventory: `1605` entries
- API surface: `637` public+internal methods
- public API surface: `614`
- exact clones: `0`
- near clones: `0`
- name collisions: `295`

Interpretation:

- The +1 API delta versus the stage-1 snapshot comes from promoting the shared
  tooltip helper to the canonical `addon.Frames.HideTooltip` surface.
- The mechanical duplication lane is now closed; the remaining work is contract
  review and selective naming/API simplification, not wrapper collapse.
- The first high-signal contract-cleanup lane is `Core/DB`, where DB-manager-backed
  getters were still exposed on two public surfaces (`addon.Core.*` and `addon.DB.*`)
  even though in-repo call sites already preferred `addon.Core.*`.
- The same contract lane also included schema-version access: `Core.GetRaidSchemaVersion`
  was already the in-repo owner, so the extra `addon.DBSchema.GetRaidSchemaVersion`
  surface was removable with low risk.

Interpretation:

- `name-collision` is mostly analysis noise and not immediate cleanup scope by itself.
- The actionable lane is `merge-now` plus duplicated public facades where one owner
  only forwards to another owner.
- `Services/Reserves.lua` remains the clearest high-value contraction target because
  it still exposes two public-looking entry surfaces for the same behavior.

Stage plan for the current API-reduction program:

1. `Stage 0` - regenerate catalogs, capture merge candidates, update docs/process.
2. `Stage 1` - collapse redundant public facade surfaces and trivial pass-through
   helpers with low behavior risk. Completed.
3. `Stage 2` - merge duplicated internal helpers where one canonical owner already
   exists (`Logger` popup refs and tooltip helpers). Completed.
4. `Stage 3` - regenerate catalogs again, update architecture/runtime docs, rerun
   full checks, and refresh the residual backlog. Completed.

Stage 1 target set:

- `!KRT/Services/Reserves.lua`
- `!KRT/Widgets/ReservesUI.lua`
- `!KRT/Controllers/Master.lua`
- `!KRT/Services/Rolls/Service.lua`
- `!KRT/EntryPoints/{SlashEvents,Minimap}.lua`
- `!KRT/Init.lua`

Stage 1 completed:

- collapsed `Services/Reserves.lua` to one canonical public owner table
  (`addon.Services.Reserves` / `addon.Reserves`)
- retained `.Service` only as a compatibility alias to the same table
- migrated `ReservesUI` to the canonical reserves owner
- replaced duplicated entrypoint controller-routing helpers with
  `addon.Core.RequestControllerMethod(...)`
- removed low-value `Services.Reserves` accessors duplicated in `Master` and `Rolls`

Stage 2 target set:

- `!KRT/Controllers/Logger.lua`
- `!KRT/Modules/UI/Frames.lua`
- `!KRT/Widgets/ReservesUI.lua`

Stage 2 completed:

- merged Logger popup helper pairs onto one shared `ensurePopupRefs(...)` path
- centralized tooltip hide wiring on `addon.Frames.HideTooltip`
- removed all `merge-now` exact-clone entries from `docs/FN_CLUSTERS.md`

Contract wave seed (`2026-04-06`):

- target owner: `!KRT/Core/DB.lua`
- scope: collapse duplicate DB-manager-backed public getter facades and keep one
  canonical public owner
- canonical contract: `addon.Core.*`
- non-goals: no changes to concrete DB module tables under `addon.DB.*`

Contract wave result snapshot (`2026-04-06`):

- scope completed:
  - removed redundant DB getter facades from `!KRT/Core/DB.lua`
  - removed redundant schema getter facade from `!KRT/Core/DBSchema.lua`
- canonical public owner confirmed:
  - `addon.Core.GetRaidStore`
  - `addon.Core.GetRaidStoreOrNil`
  - `addon.Core.GetRaidQueries`
  - `addon.Core.GetRaidMigrations`
  - `addon.Core.GetRaidValidator`
  - `addon.Core.GetSyncer`
  - `addon.Core.GetRaidSchemaVersion`
- metrics:
  - API surface: `637 -> 629`
  - public API surface: `614 -> 606`
  - name-collision count: `295 -> 288`
  - scanned Lua files: `53 -> 52`
- residual note:
  - `addon.DB` remains the concrete namespace for DB submodules and manager state
  - no in-repo call sites require the removed `addon.DB.*`/`addon.DBSchema.*` getter facades

Contract wave seed (`2026-04-06`, Chat/Raid ownership):

- target owners:
  - `!KRT/Services/Chat.lua`
  - `!KRT/Services/Raid/Capabilities.lua`
- scope: remove redundant root addon method facades for announce/warn output and
  raid capability queries/guards
- canonical public owners:
  - `addon.Services.Chat` / `addon.Chat`
  - `addon.Services.Raid` / `addon.Raid`
- compatibility exception:
  - keep `addon:Print` only, because `LibLogger-1.0` still calls it directly

Contract wave result snapshot (`2026-04-06`, Chat/Raid ownership):

- scope completed:
  - removed root addon method facades from `!KRT/Services/Chat.lua` and `!KRT/Init.lua`
    for:
    - `addon:Announce`
    - `addon:ShowMasterOnlyWarning`
    - `addon:GetRaidRoleState`
    - `addon:GetRaidCapabilityState`
    - `addon:CanUseRaidCapability`
    - `addon:CanUseMasterOnlyFeatures`
    - `addon:IsMasterOnlyBlocked`
    - `addon:EnsureMasterOnlyAccess`
  - removed redundant service-only pass-throughs from
    `!KRT/Services/Raid/Capabilities.lua`:
    - `CanUseMasterOnlyFeatures`
    - `IsMasterOnlyBlocked`
  - migrated in-repo call sites to canonical service owners in:
    - `!KRT/Controllers/Master.lua`
    - `!KRT/Controllers/Changes.lua`
    - `!KRT/Widgets/LootCounter.lua`
    - `!KRT/Services/Rolls/Service.lua`
    - `!KRT/EntryPoints/Minimap.lua`
    - `!KRT/EntryPoints/SlashEvents.lua`
    - `!KRT/Core/DBSyncer.lua`
    - `!KRT/Init.lua`
  - updated the stabilization harness/tests to the service-owned capability contract
- metrics:
  - function inventory: `1605 -> 1593`
  - API surface: `629 -> 620`
  - public API surface: `606 -> 597`
  - name-collision count: `288 -> 284`
  - `merge-now`: remains empty
- residual note:
  - `addon:Print` is now the only intentional root-method compatibility hook
  - announce/warn output and capability guards are now service-owned contracts,
    not root addon method facades

Contract wave seed (`2026-04-06`, Logger public contract cleanup):

- target owners:
  - `!KRT/Controllers/Logger.lua`
  - `!KRT/Services/Logger/{Actions,Store,View}.lua`
- scope:
  - shrink Logger public surface by privatizing UI-local controller helpers
  - reduce `Unclassified` only where the method was public by ownership accident,
    not because of taxonomy noise
- canonical contract:
  - keep public Logger controller surface focused on lifecycle/state and
    cross-module actions
  - keep service/public Logger methods only when another module truly consumes them

Contract wave result snapshot (`2026-04-06`, Logger public contract cleanup):

- scope completed:
  - privatized Logger controller-only helpers from `!KRT/Controllers/Logger.lua`:
    - `NeedRaid`
    - `NeedBoss`
    - `NeedLoot`
    - `Run`
    - `ResetSelections`
    - `SelectRaid`
    - `SelectBoss`
    - `SelectBossPlayer`
    - `SelectPlayer`
    - `SelectItem`
    - `OnLootRowEnter`
    - `OnLootRowLeave`
  - privatized additional Logger UI-local helpers:
    - `Boss:Edit`
    - `BossBox:Fill`
    - `BossBox:Save`
    - `AttendeesBox:Save`
    - `Loot:Sort`
    - `Loot:OnEnter`
  - privatized Logger service helpers that did not need to cross file/module
    boundaries:
    - `Actions:Commit`
    - `Store:BossIdx`
    - `Store:LootIdx`
    - `Store:PlayerIdx`
    - `View:EscapeCsvField`
    - `View:BuildRows`
- metrics:
  - API surface: `620 -> 596`
  - public API surface: `597 -> 573`
  - public `Unclassified`: `269 -> 245`
  - name-collision count: `284 -> 277`
  - Logger public `Unclassified`: `37 -> 13`
  - `merge-now`: remains empty
- residual note:
  - remaining Logger public `Unclassified` entries are now mostly deliberate
    service/controller contracts (`Loot.SetLootEntry`, `Store.Resolve*`, `View.Fill*`,
    export-state helpers), not file-local UI glue
  - the next `Unclassified` lane should focus on ownership-heavy contracts, not
    bulk renames

Contract wave seed (`2026-04-06`, internal-surface ownership cleanup):

- target owners:
  - `!KRT/Controllers/Master.lua`
  - `!KRT/Controllers/Logger.lua`
  - `!KRT/Services/Logger/Store.lua`
  - `!KRT/Services/Raid/{Roster,State}.lua`
  - `!KRT/Services/Reserves.lua`
  - `!KRT/Widgets/ReservesUI.lua`
  - `!KRT/Services/Debug.lua`
- scope:
  - convert residual package-internal helpers from public surfaces to local or
    underscore-prefixed owner-table fields
  - keep `Rolls` unchanged unless a real ownership contraction exists
- canonical contract:
  - public owner tables expose lifecycle/state/cross-module behavior only
  - package-internal helpers use underscore-prefixed owner-table fields or stay
    file-local

Contract wave result snapshot (`2026-04-06`, internal-surface ownership cleanup):

- scope completed:
  - `!KRT/Controllers/Logger.lua`
    - localized export-state helpers (`IsCsvVisible`, `MarkCsvDirty`,
      `EnsureCsvFresh`, `RefreshCsv`)
  - `!KRT/Services/Logger/Store.lua`
    - moved looter/player resolve helpers and cache invalidation to internal
      underscore surface
  - `!KRT/Controllers/Master.lua`
    - privatized dropdown/cursor glue and non-contract button handlers
      (`BtnOS`, `BtnSR`, `BtnFree`, `BtnClear`, `BtnHold`, `BtnBank`,
      `BtnDisenchant`, `BtnReserveList`, `BtnLootCounter`, `BtnSelectedItem`,
      `OnClickDropDown`, `TryAcceptInventoryItemFromCursor`, `ResetItemCount`,
      `ClearCurrentItemView`)
  - `!KRT/Services/Raid/{Roster,State}.lua`
    - converted roster/runtime helper methods from public `*Internal` names to
      underscore-prefixed owner-table fields
  - `!KRT/Services/Reserves.lua`
    - internalized import-strategy/pending-item/update-cache helpers and removed
      unused `ParseCSV` facade
  - `!KRT/Widgets/ReservesUI.lua`
    - migrated pending-item checks to the internal underscore surface
  - `!KRT/Services/Rolls/Service.lua`
    - reviewed and intentionally left unchanged in this wave because remaining
      candidates are covered service contracts, not ownership accidents
- metrics:
  - function inventory: `1593 -> 1591`
  - API surface: `596 -> 558`
  - public API surface: `573 -> 535`
  - public `Unclassified`: `245 -> 215`
  - name-collision count: `277 -> 275`
  - Logger public `Unclassified`: `13 -> 6`
  - `merge-now`: remains empty
- residual note:
  - remaining high-signal public `Unclassified` counts are now:
    - `addon.Controllers.Master`: `4`
    - `addon.Services.Raid`: `15`
    - `addon.Services.Reserves`: `15`
    - `addon.Services.Rolls`: `18`
  - the residual lane is now contract naming/taxonomy review, not accidental
    public helper exposure

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

- `!KRT/Controllers/Master.lua`: internal-surface ownership wave completed; only
  explicitly consumed button handlers remain public
- `!KRT/Controllers/Logger.lua`: Logger contract wave completed; public UI-local
  glue reduced, monitor only
- `!KRT/Controllers/Warnings.lua`: closed for baseline UI normalization
- `!KRT/Controllers/Changes.lua`: closed for baseline UI normalization
- `!KRT/Controllers/Spammer.lua`: closed for baseline UI normalization

### 2.2 Widgets

- `!KRT/Widgets/Config.lua`: closed for baseline UI normalization
- `!KRT/Widgets/LootCounter.lua`: closed for baseline UI normalization
- `!KRT/Widgets/ReservesUI.lua`: closed for baseline UI normalization

### 2.3 Services

- `!KRT/Services/Raid/State.lua`: wave S1/S1b plus internal-surface ownership
  cleanup completed, monitor only
- `!KRT/Services/Raid/{Capabilities,Changes,Counts,Roster,LootRecords,Session,Boss}.lua`:
  split completed; Chat/Raid contract wave completed in `Capabilities`; `Roster`
  internal helper exposure reduced, monitor only
- `!KRT/Services/Rolls/Service.lua`: reviewed in the ownership wave; no safe contract
  contraction identified, monitor only with stabilization tests
- `!KRT/Services/Reserves.lua`: ownership/internal-surface cleanup completed;
  parser/cache helper exposure reduced
- `!KRT/Services/Loot/Service.lua`: wave S1b completed (canonical ingestion + narrowed raid bridge)
- `!KRT/Services/Chat.lua`: contract wave completed, canonical announce/warn owner confirmed
- `!KRT/Services/Logger/{Actions,Store,View}.lua`: Logger contract wave completed;
  file-local helper surfaces reduced; store-internal helpers moved to underscore APIs
- `!KRT/Services/Debug.lua`: hold, low priority

### 2.4 EntryPoints

- `!KRT/EntryPoints/SlashEvents.lua`: contract wave completed, uses service-owned ML guard
- `!KRT/EntryPoints/Minimap.lua`: contract wave completed, uses service-owned capability queries

### 2.5 Core and Infra

- `!KRT/Core/DBSyncer.lua`: contract wave completed, uses service-owned capability query
- `!KRT/Core/DBRaidStore.lua`: cleanup wave C2 in progress
- `!KRT/Modules/UI/Frames.lua`: cleanup wave U1 in progress
- `!KRT/Init.lua`: contract wave completed, root chat/capability facades removed

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

### P1: Service API Redundancy Collapse

These files are the highest-value cleanup targets because they still expose
duplicated/pass-through contracts or heavy bridge logic across services.

1. `!KRT/Services/Rolls/Service.lua` - about 726 lines
2. `!KRT/Services/Reserves.lua` - about 1713 lines
3. `!KRT/Services/Loot/Service.lua` - about 2049 lines
4. `!KRT/Services/Raid/State.lua` - about 847 lines

### P2: Routing and Infra Cleanup

These files are smaller than the P1 services but still good cleanup targets
because they sit on repo-wide boundaries.

1. `!KRT/EntryPoints/SlashEvents.lua` - about 691 lines
2. `!KRT/EntryPoints/Minimap.lua` - about 413 lines
3. `!KRT/Core/DBSyncer.lua` - about 1454 lines
4. `!KRT/Core/DBRaidStore.lua` - about 755 lines
5. `!KRT/Modules/UI/Frames.lua` - about 889 lines

### P3: Bootstrap Follow-up

1. `!KRT/Init.lua` - about 1514 lines

This should stay a follow-up lane. Do not reopen it early unless a cleanup wave
proves a residual owner clearly belongs elsewhere.

## 4. Recommended Cleanup Waves

### Wave S1: Raid/Loot Bridge and API Cleanup

Owner files:
- `!KRT/Services/Raid/State.lua`
- `!KRT/Services/Raid/LootRecords.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Init.lua`
- `!KRT/Controllers/Master.lua`

Scope:
- remove duplicated public pass-through methods on `Raid` that only forward to
  `Loot` (`AddLoot`, `AddPassiveLootRoll`, `AddGroupLootMessage`,
  `LogTradeOnlyLoot`, `IsIgnoredItem`) once call sites are migrated
- reduce `Loot -> Raid` bridge coupling by collapsing `*Internal` methods into
  narrower contracts
- remove duplicate helper implementations flagged by `docs/FN_CLUSTERS.md` in
  the raid/loot boundary (`resolveRollSessionIdForLoot`,
  `bindLootNidToRollSession`, `resolveRaidDifficulty`, `getRaidSizeFromDifficulty`,
  `isUnknownName`)

Current worktree progress:
- monolithic `!KRT/Services/Raid.lua` has already been split into focused
  `Services/Raid/*.lua` modules
- passive/group loot ingestion and trade-only creation are centralized in
  `!KRT/Services/Loot/Service.lua`, and runtime call sites no longer fall back to
  `Raid` wrappers
- `Raid` pass-through wrappers and `*Internal` bridge methods were removed and
  replaced by narrow bridge contracts for boss context/player resolution

Non-goals:
- no gameplay policy changes
- no SavedVariables shape changes
- no UI layout changes

Validation:
- `tools/check-layering.ps1`
- `tools/check-lua-syntax.ps1`
- targeted `luacheck` while iterating
- `tools/krt.py run-release-targeted-tests` when touching `Rolls`/`Master`

Smoke path:
- login and `/reload`
- raid detection + roster updates
- passive loot winner capture from chat/system events
- master-loot award and trade-only fallback

### Wave S2: Rolls Service

Owner files:
- `!KRT/Services/Rolls/Service.lua`

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
- raid and service lookups in WoW event handlers now share helpers and no
  longer route boss logging through legacy `self.Raid`

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

1. `!KRT/Services/Rolls/Service.lua` API contraction and helper dedup
2. `!KRT/Services/Reserves.lua` facade dedup (`Service:*` + `module:*`)
3. `!KRT/EntryPoints/SlashEvents.lua` boundary cleanup follow-up

That sequence gives the best technical ROI while keeping the already-stable UI
owner layer closed.

## 8. Services Redundancy Catalog (Post-S1b, 2026-04-06)

Scope of this catalog:

- `!KRT/Services/Raid/*.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Rolls/Service.lua`
- `!KRT/Services/Reserves.lua`
- `!KRT/Init.lua`
- `!KRT/Controllers/Master.lua`

This pass applied code changes and re-ran validation/catalog generation.

### 8.1 Completed reductions in this pass

1. Removed `Raid -> Loot` pass-through APIs from
   `!KRT/Services/Raid/State.lua` (`AddLoot`, `AddPassiveLootRoll`,
   `AddGroupLootMessage`, `LogTradeOnlyLoot`, `IsIgnoredItem`).
   Runtime callers now use `addon.Services.Loot` directly.

2. Removed wide `Loot -> Raid` public `*Internal` bridge surface and replaced
   it with narrow methods:
   `FindOrCreateBossNidForLoot`, `FindAndRememberBossEventContextForLootSession`,
   `EnsureRaidPlayerNid`.

3. Removed redundant/unused aliases with no external call sites:
   `Raid:ResolveRaid`, `Raid:IncrementPlayerCount`, `Raid:DecrementPlayerCount`.

4. Removed defensive cross-service `type(method) == "function"` checks on the
   Loot/Raid boundary where load-order contracts already guarantee ownership.

### 8.2 Remaining high-confidence redundancies

1. No high-confidence `merge-now` duplicates remain after the stage-2 recatalog.
   Evidence: `docs/FN_CLUSTERS.md` merge-now table is empty.

2. Remaining follow-up is contract review only:
   - `name-collision` entries that represent different owners with similar names
   - intentional bridge APIs such as the lean `Raid <-> Loot` boundary

### 8.3 Current API impact snapshot

- Public API surface reduced from `640` to `535` methods across the full program.
- Total API surface reduced from `663` to `558` methods across the full program.
- Public `Unclassified` reduced from `269` to `215` across the staged contract waves.
- Name-collision count reduced from `341` to `275`.
- Exact clone count reduced from `10` to `0` (`docs/FN_CLUSTERS.md` class summary).

### 8.4 Deadcode outcome for these Services

- No additional safe hard-delete candidates were identified in this pass.
- Remaining work is mainly dedup/API contraction, not deadcode purge.
