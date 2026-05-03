# KRT - AGENTS.md (WoW 3.3.5a / Lua 5.1)

Context file for AI coding agents. Lives at repo root as `AGENTS.md`.
Keep lines <= 120 chars. Keep this file current.

Default: guidelines are non-binding; when in doubt, follow existing KRT patterns.
Exception: sections marked **BINDING** must be followed for every change.

Changelog: **CHANGELOG.md** is the single source of truth for behavior/user-visible changes.

Developer docs package (keep these files aligned when architecture/tooling changes):
- `docs/ARCHITECTURE.md` (architecture/layering map + UI/XML binding and template policy)
- `docs/OVERVIEW.md` (runtime ownership and module map)
- `docs/LUA_WRITING_RULES.md` (Lua writing rules and naming policy)
- `docs/DEV_CHECKS.md` (quick layering/tooling checks)
- `docs/AGENT_SKILLS.md` (agent skills + Mechanic companion workflow)
- `docs/KRT_MCP.md` (repo-local MCP server usage and tool inventory)
- `tools/krt.py` (cross-platform tooling entrypoint)

---

## Conversations (Self-Learning)

Update requirement:
- Before starting any task, scan the latest user message for new permanent rules/preferences.
- If a new durable rule is detected, update this file first, then do the task.

Do NOT record:
- one-off instructions for a single task,
- temporary exceptions.

Durable preferences learned from recent conversations:
- Prefer refactors to reduce code surface while adding new behavior; avoid keeping debug-only or
  redundant helper layers when a simpler implementation preserves the same contract.
- Prefer master-looter-only runtime behavior: non-master clients should not run roll/award gameplay flows.
- Prefer centralized Master Looter access policy via shared facade/helpers; avoid duplicating ML gate
  checks and warnings across controllers and entrypoints.
- Prefer capability-based access policy: looting flows require current Master Looter ownership, while
  leadership features (for example Raid Warnings, Changes, LFM spammer) should remain available to raid
  leader/assistant roles when appropriate.
- Prefer `Changes:Demand()` and `Changes:Announce()` to require raid leader/assistant permission in raid;
  being merely in raid is not sufficient.
- Prefer LootCounter grouped-count announce/spam actions to require raid leader/assistant permission in raid.
- Prefer centralized raid-role capability policy (`member`/`assistant`/`leader`/`master looter`) to drive
  enable/disable and action guards across UI/controllers, instead of ad-hoc per-feature role checks.
- Prefer `addon.Services.Raid` / `addon.Raid` as the canonical owner for capability queries and shared
  master-only guards, and `addon.Services.Chat` / `addon.Chat` as the canonical owner for announce/warn
  output; avoid root `addon:*` method facades except `addon:Print` compatibility for LibLogger.
- Prefer `Logger` public contracts to expose only cross-module/runtime ownership; keep Logger UI-local
  selection/edit/popup glue private to `Controllers/Logger.lua` whenever those helpers do not need to
  cross module boundaries.
- Prefer reducing `Unclassified` APIs only when there is a real ownership/contract problem behind them;
  do not rename or churn public methods only to satisfy taxonomy noise.
- Prefer underscore-prefixed internal APIs for cross-file package helpers that are not public
  contracts; do not leave them exposed as public `*Internal` methods on canonical owner tables.
- In `Controllers/Master.lua`, keep button/dropdown/cursor glue private unless a test or another
  module genuinely depends on the public handler contract.
- In `Services/Logger/*`, `Services/Raid/*`, and `Services/Reserves/*`, keep parser/cache/selection
  and other package-internal helpers on local helpers or underscore-prefixed owner-table fields rather
  than public APIs.
- Prefer simpler role-gated UI without extra explanatory tooltips for disabled actions unless explicitly requested.
- Do not introduce Ace dependencies (Ace2/Ace3); prefer native KRT + LibCompat patterns.
- Do not modify vendored libraries under `!KRT/Libs/*`; keep fixes in addon code.
- Avoid runtime backward-compat shims when refactoring; target the fresh-SV model directly.
- Prefer LuaRocks Lua Style Guide for formatting/layout when it does not conflict with KRT binding conventions.
- Prefer PascalCase for addon module table names.
- Prefer PascalCase for public exported methods on feature modules (`module:*`, `Store:*`, `View:*`, `Actions:*`,
  `Box:*`); keep WoW-required event names unchanged (UPPERCASE handlers).
- Prefer PascalCase for public/cross-module APIs in infrastructure namespaces too
  (`Core`, `Bus`, `Frames`, `UI*`, `Strings`, `Time`, `Comms`, `Base64`, `Colors`, `Item`, `Sort`).
- Prefer camelCase for utility functions and local variables; avoid snake_case for new naming.
- Keep file-local/private helpers in camelCase; keep Lua metamethods (`__index`, `__call`, etc.) unchanged.
- For naming migrations, prefer direct migration to canonical PascalCase call-sites with no legacy alias references;
  add temporary aliases only when explicitly requested.
- For API inventories and reports, separate `Public` and `Internal` surfaces; treat underscore methods
  and `._ui` targets as internal implementation APIs.
- For new/renamed public API methods, use a short verb taxonomy:
  queries (`Get/Find/Is/Can`), mutations (`Set/Add/Remove/Delete/Upsert`),
  lifecycle/UI (`Ensure/Bind/Localize/Request/RequestRefresh/Refresh/Toggle/Show/Hide`),
  plus exact hooks (`OnLoad`, `OnLoadFrame`, `AcquireRefs`, `BindHandlers`, `RefreshUI`).
- Keep staged API nomenclature checks automated in local gates/pre-commit to block new naming regressions.
- Prefer API cleanup work to start from a fresh full function/API census, then merge or remove redundant
  surfaces by canonical ownership instead of preserving parallel wrappers.
- Prefer staged API-reduction refactors with explicit checkpoints; after each completed stage, regenerate
  `docs/*`, rerun the relevant checks, recatalog the surface, and only then continue to the next stage.
- In feature files under `Controllers/`, `Services/`, `Widgets/`, `EntryPoints/`, prefer canonical top-level
  section headers in order:
  `-- ----- Internal state ----- --`, `-- ----- Private helpers ----- --`,
  `-- ----- Public methods ----- --`.
- UI refactors: centralize shared UI glue/patterns in `Init.lua`; keep feature-specific UI logic in each module.
- Move helpers to dedicated `Modules/*` files only when they are generic and reused; avoid catch-all utility files.
- Keep diagnostic templates in `addon.Diagnose`; use severity buckets `I/W/E/D` (`DiagnoseLog.en.lua`).
- Prefer local `Diag` wrapper aliases over direct `Diagnose.*` chains in implementation files.
- For naming/API uniformization, choose the most repeated in-repo pattern and apply it consistently and robustly.
- For Logger visual refreshes, prefer a MizusRaidTracker-inspired Wrath raid-log look: Blizzard dialog frame,
  dark compact tables, yellow section titles, default KRT buttons outside list panels, and green selected rows.
- For Logger loot item icons, preserve an approximately `28x28` click target, a centered `26x26` icon texture,
  and a centered `32x32` quickslot-like border drawn outside the icon; avoid using button `NormalTexture`
  when it clips or overlays the item bitmap.
- For UI function naming, keep explicit `UI` in method names when it improves clarity; prefer readable names
  over ultra-short abbreviations.
- For module-local UI readability, prefer a local `UI` state/helper table:
  `UI.Bound`, `UI.Loaded`, `UI.isDirty`, `UI.AcquireRefs`, `UI.Localize`, `UI.Refresh`.
- Prefer one canonical UI lifecycle vocabulary across modules; avoid mixed synonyms for the same concept
  (for example `uiBound` vs `UI.Bound`, `UpdateUIFrame` vs `UI.Refresh`).
- Prefer a canonical UI module contract when feasible:
  `OnLoad`, `AcquireRefs`, `BindUI`, `EnsureUI`, `Toggle`, `Hide`, `RequestRefresh`, `Refresh`.
- Prefer the definitive UI contract via `UIScaffold.DefineModuleUi(cfg)` for Controllers/Widgets.
- Modules should implement only UI hooks (`AcquireRefs`, `BindHandlers`, `Localize`, `OnLoadFrame`,
  `RefreshUI`/`Refresh`), while scaffold-generated methods own `BindUI`, `EnsureUI`, `Toggle`,
  `Show`, `Hide`, `RequestRefresh`, `MarkDirty`, and cache fields (`frame`, `refs`, `_ui`).
- Keep UI state schema uniform: `module._ui = { Loaded, Bound, Localized, Dirty, Reason, FrameName }`.
- Prefer `Core.GetRaidStoreOrNil(contextTag, requiredMethods)` over ad-hoc
  `Core.GetRaidStore` nil/method checks to keep diagnostics and guard behavior uniform.
- Prefer homogeneous module structure/patterns across Lua modules; avoid one-off lifecycle variants
  unless behavior requires them.
- Prefer Lua fixes to follow the established local-helper/module pattern; use scoped local blocks or
  focused splits before moving private helpers onto tables just to work around local limits.
- For UI named-frame access standardization, prefer the dominant in-repo `_G[frameName .. suffix]`
  pattern over introducing static local ref caches only for stylistic cleanup.
- For XML and Lua analysis/reference, use Townlong-Yak FrameXML 3.3.5:
  `https://www.townlong-yak.com/framexml/3.3.5`.
- For custom button glow UX, prefer high-visibility dynamic pulses with geometry
  tightly aligned to each button's border (avoid diffuse/off-frame halos).
- For button-glow styling, prefer clean border pulses; avoid glossy/sweep
  "shiny" overlays unless explicitly requested for a specific patch.
- For glow architecture on WoW 3.3.5a, prefer local UI module implementations
  (for example LCG-like ports in `Modules/UI/Effects.lua`) over vendoring
  full modern glow libs.
- Keep glow/proc implementation details in `Modules/UI/Effects.lua`; keep
  `Modules/UI/Visuals.lua` focused on generic UI primitives and row visuals.
- Treat raid `players[].count` (LootCounter) as canonical persisted raid data; restoring/selecting an old current raid
  must preserve and reuse historical counts.
- Prefer a clean persisted raid schema: keep `players[]` as the canonical persisted player store; treat
  `_playersByName` as a derived runtime index/cache.
- Treat fresh SavedVariables as strict mode: avoid legacy/migration cleanups and avoid fallback to
  volatile array indices when stable NIDs (`playerNid`, `bossNid`, `lootNid`) are available.
- Prefer lean SavedVariables persistence: store only canonical restore-critical data; avoid persisting
  duplicated, derived, or runtime-only fields that can be rebuilt at load time.
- Keep `EntryPoints/SlashEvents.lua` focused on `/cmd` handling only.
- Keep main WoW event handlers centralized in `Init.lua`; modules should expose callable APIs used by those handlers.
- Prefer storing runtime-only addon state under `addon.State` (or feature state tables) over global runtime vars.
- Keep glow effects single-choice by method (`ACShine`, `Pixel`, `Proc`, `buttonOverlay`);
  avoid profile-name methods such as `SoftPulse`/`CombatPulse`.
- Prefer deterministic sorting with explicit tie-breakers; when primary values are equal, use stable secondary keys
  (for Logger Loot, prefer loot name, then IDs) to avoid random reordering between sorts.
- Prefer deterministic bugfixes over timing-dependent or fragile workaround-style fixes.
- Keep bootstrap ownership centralized in `Init.lua` for `addon.Core`, `addon.L`, `addon.Diagnose`,
  `addon.State`, `addon.C`, and `addon.Events`; do not re-bootstrap them in feature files.
- Prefer a uniform Lua file contract header with:
  `local addon = select(2, ...)` and `local feature = addon.Core.GetFeatureShared()`.
- Prefer bus-only architecture from `Init.lua`: no direct calls from Core to `addon.Master`/`addon.Logger`/other
  Parents; wire WoW events into `Bus.TriggerEvent("wow.EVENT", ...)` and let modules subscribe.
- Keep Logger-owned roster UI refresh logic inside `Controllers/Logger.lua` (subscribed via `RaidRosterDelta`),
  not in `Init.lua`.
- Prefer a unified root bootstrap/runtime entry file `!KRT/Init.lua`; do not split ownership between
  `Core/Init.lua` and `KRT.lua`.
- Prefer a widget facade/port via `addon.UI` (`Modules/UI/Facade.lua`) for Controller/EntryPoint -> Widget calls.
- Avoid direct references to `addon.LootCounter`, `addon.ReservesUI`, and `addon.Config` in
  `Controllers/*.lua` and `EntryPoints/*.lua`; use `addon.UI:Call(...)` instead.
- Prefer optional widget architecture with `addon.Features` flags and profile-aware toggles (`core` vs `full`).
- Keep XML layout-only: do not use `<Scripts>`/`<On...>` in `UI/*.xml` and `UI/Templates/*.xml`.
- Keep optional-widget behavior inside `addon.UI`, `UIScaffold`, and feature-local Lua wiring;
  there is no `Modules/UI/Binder` layer in the current tree.
- Keep Services pure: no frame lifecycle (`OnLoad`/`Refresh`) or UI delegation in `Services/*`;
  widgets should consume the canonical service surface, while nested `.Service` fields remain
  compatibility-only when present, and refresh via bus events (e.g. `ReservesDataChanged`).
- Keep item helpers consolidated in a dedicated infra module (for example `Modules/Item.lua`);
  expose item-link parsing and tooltip probes via `feature.Item`/`addon.Item`.
- Prefer dedicated reusable modules (`Bus`, `ListController`, `MultiSelect`, `Frames`, `Strings`,
  `Colors`, `Comms`, `Base64`, `Time`, `Sort`) over reviving `Modules/Utils.lua`.
- Prefer explicit canonical contracts and deterministic initialization over scattered defensive guards;
  when a dependency must exist, normalize it once at the module boundary/bootstrap rather than adding
  many per-call fallback branches.
- Treat `feature.X or addon.X` locals and `addon.Services.* = addon.Services.* or {}` guards as intentional
  test/bootstrap wiring until a dedicated `Core.GetFeatureShared()` and namespace-bootstrap stage replaces
  them coherently; do not remove those patterns piecemeal.
- Prefer `addon.Core` as the canonical public accessor surface for DB-backed contracts
  (`GetRaidStore`, `GetRaidStoreOrNil`, `GetRaidQueries`, `GetRaidMigrations`,
  `GetRaidValidator`, `GetSyncer`, `GetRaidSchemaVersion`); keep `addon.DB`/`addon.DBSchema`
  focused on concrete modules/state, not duplicate public getter facades.
- Prefer centralized MultiSelect modifier policies in `Modules/UI/MultiSelect.lua`
  with per-list scope keys; avoid per-controller CTRL/SHIFT gating flags.
- Prefer centralized event-name registry in `Modules/Events.lua` for internal bus events and
  wow-forwarded events (avoid ad-hoc string literals in modules).
- Prefer minimizing cross-service interlacing: keep loot ingestion/parsing ownership in
  `Services/Loot/Service.lua`, and avoid over-splitting `Services/Raid/*` into thin pass-through files.
- Prefer loot-context runtime internals (`LootContext`, `activeLoot`, loot-window session/snapshot
  state) to live under `Services/Loot/*`; keep `Services/Loot/Service.lua` focused on
  ingestion/parsing and public loot-service APIs, while `Services/Raid/State.lua` consumes shared helpers instead of
  owning those internals directly.
- Prefer splitting oversized service hotspots into focused sibling modules (for example
  `PendingAwards`, `PassiveGroupLoot`, `Tracking`, and `Rules`) while keeping `Services/Loot/Service.lua`
  as the stable public facade.
- Prefer namespaced module ownership under `addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`;
  keep temporary legacy aliases (`addon.Master`, `addon.Raid`, etc.) during soft migrations.
- Alias lockdown: keep legacy aliases as compatibility only; in debug mode, warn on legacy alias reads
  (`addon.Raid`, `addon.Logger`, etc.) to prevent new call sites from regressing.
- Prefer callsite guards for debug/trace logging (`if addon.hasDebug then ... end`) when message
  arguments need `format`/`tostring` work; do not rely on LibLogger level guards to skip evaluation.
- Prefer fast architecture verification via focused `rg` checks (XML inline scripts, widget facade calls,
  namespacing coverage, and legacy top-level access scans) before closing refactor tasks.
- Prefer gradual function/API deduplication: remove or consolidate similar helper functions to reduce drift,
  while preserving behavior and module ownership boundaries.
- Prefer reducing public API redundancy by collapsing pass-through wrappers into canonical service APIs;
  avoid exposing cross-service bridge methods as long-term public contracts when they can stay internal.
- Prefer centralized constants for shared timing windows/TTLs used across modules;
  avoid repeating the same hardcoded seconds in multiple files.
- Prefer AFD-oriented development workflow with pinned skills in `.agents/skills`;
  sync via `tools/sync-agent-skills.ps1`.
- Keep Mechanic as external companion tooling (not vendored in addon runtime);
  bootstrap per-device via `tools/mech-bootstrap.ps1`.
- Prefer multi-device workflow using repo scripts and explicit addon path wrapper
  `tools/mech-krt.ps1` for Mechanic commands.
- Keep skill/tooling configuration stored in-repo (`tools/agent-skills.manifest.json`)
  with docs under `docs/AGENT_SKILLS.md` for deterministic setup.
- Prefer canonical repo-wide Lua writing rules in `docs/LUA_WRITING_RULES.md`;
  keep `.stylua.toml`, `.luacheckrc`, and `tools/check-lua-uniformity.ps1`
  aligned with that document.
- For roll-response lifecycle hardening, prefer this canonical policy:
  `PASS` reversible, `CANCELLED` reversible, `TIMED_OUT` terminal for the session,
  `INELIGIBLE` recoverable only through eligibility refresh, and only eligible `ROLL`
  responses may enter the resolver.
- For countdown-bypass intake (`countdownRollsBlock=false`), late rolls should stay visible
  with `OOT` tagging but must be excluded from resolver candidates, manual winner
  selection, and tie-reroll triggers.
- Treat `Rolls:GetDisplayModel().resolution` as an explicit public service contract;
  keep its stable fields documented (`autoWinners`, `tiedNames`, `topRollName`,
  `requiresManualResolution`, `cutoff`) instead of treating them as incidental internals.
- Treat `tests/release_stabilization_spec.lua` as the regression gate for changes in
  `Services/Rolls/Service.lua` and `Controllers/Master.lua`; run it whenever those modules change.
- Prefer repo-relative paths or placeholders in config/docs/examples; avoid personal absolute
  paths unless strictly required by the tool.
- Prefer simplified repo tooling that works on both Windows and Linux with automatic OS-aware
  execution; local runs should use Windows-native paths/tools, while cloud runs should use Linux-
  compatible paths/tools without requiring separate user workflows.
- Prefer release-channel resolution from changelog release metadata: under `## Unreleased`, keep
  `Release-Version: <version>` in `!KRT/CHANGELOG.md` using SemVer forms `x.y.z` (stable),
  `x.y.z-alpha.N` (internal/no publication), or `x.y.z-beta.N` (GitHub prerelease); workflows,
  tags, and assets should validate against that metadata instead of manual prerelease toggles.
- Prefer release publication only when the full SemVer increases; unchanged or lower versions
  must not publish a new release.
- Prefer semantic version bumps with this policy: increment `patch` for backward-compatible fixes
  and polish, increment `minor` for backward-compatible features or meaningful UI/workflow
  additions, and increment `major` only for breaking API/SavedVariables changes or required user
  migrations.
- Treat prerelease transitions (`alpha.N`, `beta.N`, or `-> stable`) as explicit SemVer versions;
  publish a new version instead of moving or replacing existing release tags/assets.
- Prefer branch-agnostic release automation: release workflows should accept pushes from any branch,
  and manual release dispatch should target any ref once the workflow exists on the default branch.
- Prefer manual release workflows to use the selected branch/ref directly; avoid redundant
  `target_ref` inputs when the Actions branch selector already defines release context.
- Prefer concise GitHub release notes with headings `Included Commits`,
  `New Functionality`, and `Enhancements/Improvement`; keep bullets short
  and avoid overly detailed release-note prose. In `Included Commits`,
  include commit short hashes alongside each subject.
- Prefer GitHub release notes to call out regressions/fixes explicitly when a
  release contains behavior corrections or recovery from prior regressions.
- For release artifacts, package only the addon folder `!KRT/`; do not include repo-level
  docs/tooling files in distributable ZIP outputs.
- Keep GitHub release asset download/checksum instructions out of root `README.md`;
  document them in dedicated release/tooling docs under `docs/` or `tools/`.
- For auto-loot rules, prefer automatic suggestions only; do not auto-award, auto-trade, or auto-assign loot
  unless explicitly requested.
- For passive Group Loot logging, prefer filtering low-value DE/Greed drops such as green-quality items,
  gems, and recipes out of the logger unless explicitly requested.
- For Whisper SoftRes, keep player whisper handling out of `EntryPoints/SlashEvents.lua`; put request parsing
  and response policy under Reserves/Chat-style service ownership, gate replies behind config, valid reserve
  data, and ML/leader/assistant authority, and send only chat-safe messages through
  `addon.Services.Chat`/`addon.Comms`.

---

## 1) Purpose

KRT (Kader Raid Tools) provides raid-lead QoL for WotLK 3.3.5a:
- loot handling (MS/OS/SR) + master-loot helpers,
- soft reserves (import/export, reserve list),
- loot history/logger,
- warnings/announces, LFM spammer,
- small utilities (export strings, helpers).

UI is XML + Lua (no Ace3 GUI). Libraries are vendored via LibStub.

---

## 2) Hard constraints (**BINDING**)

- Client/API: Wrath of the Lich King 3.3.5a (Interface 30300), Lua 5.1 runtime.
- Addon folder name: `!KRT` (leading `!` is intentional).
- No Ace3 dependencies (do not introduce Ace3).
- SavedVariables compatibility: do not break SV keys/shape without migration + CHANGELOG entry.

---

## 3) Modular feature policy (**BINDING**)

KRT is now modular by design:
- Unified bootstrap/runtime ownership for shared addon tables, runtime state, and global event wiring lives in
  `!KRT/Init.lua`.
- Feature implementations live in:
  - `!KRT/Controllers/*.lua` (top-level parent owners),
  - `!KRT/Services/*.lua` (runtime service/model modules),
  - `!KRT/Widgets/*.lua` (feature-specific UI controllers/widgets),
  - `!KRT/EntryPoints/*.lua` (slash/minimap entrypoints).
- `!KRT/Modules/` remains reserved for utilities/constants/static data (e.g., `Utils.lua`, `C.lua`,
  `IgnoredItems.lua`, `IgnoredMobs.lua`) and must not become a feature folder.
- XML is split into feature-oriented files under `!KRT/UI/`, loaded via `!KRT/KRT.xml` include manifest.

Rules:
1) New feature modules SHOULD be placed in the appropriate folder among `Controllers/`, `Services/`,
   `Widgets/`,
   `EntryPoints/`, unless there is a strong reason to keep them in `Init.lua`.
2) `Init.lua` should stay focused on bootstrap/glue and shared infrastructure that must exist before features.
3) Prefer `addon.Core.GetFeatureShared()` in feature file headers for shared locals/runtime state bootstrap.
4) Public exports go on `addon.*`; avoid extra globals.
5) Any user-visible behavior changes or migration notes MUST be documented in `CHANGELOG.md`.

---

## 4) Load order (**BINDING**)

WoW file load order matters. Keep (or restore) this order in `!KRT/!KRT.toc`:

1) Libs/LibStub/LibStub.lua
2) Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua
3) Libs/LibBossIDs-1.0/lib.xml
4) Libs/LibDeformat-3.0/lib.xml
5) Libs/LibCompat-1.0/lib.xml
6) Libs/LibLogger-1.0/lib.xml
7) Init.lua
8) Core/DB.lua
9) Core/Options.lua
10) Core/DBSchema.lua
11) Core/DBManager.lua
12) Localization/localization.en.lua
13) Localization/DiagnoseLog.en.lua
14) UI/Templates/Common.xml
15) Modules/C.lua
16) Modules/Timer.lua
17) Modules/Events.lua
18) Modules/Colors.lua
19) Modules/Strings.lua
20) Modules/Item.lua
21) Modules/IgnoredItems.lua
22) Modules/IgnoredMobs.lua
23) Modules/Comms.lua
24) Modules/Time.lua
25) Modules/Base64.lua
26) Modules/Sort.lua
27) Modules/Features.lua
28) Modules/UI/Facade.lua
29) Modules/UI/Effects.lua
30) Modules/UI/Visuals.lua
31) Modules/UI/Frames.lua
32) Modules/UI/ListController.lua
33) Modules/UI/MultiSelect.lua
34) Modules/Bus.lua
35) Core/DBRaidMigrations.lua
36) Core/DBRaidStore.lua
37) Core/DBRaidQueries.lua
38) Core/DBRaidValidator.lua
39) Core/DBSyncer.lua
40) Services/Loot/Context.lua
41) Services/Loot/State.lua
42) Services/Loot/Snapshots.lua
43) Services/Loot/PendingAwards.lua
44) Services/Loot/PassiveGroupLoot.lua
45) Services/Loot/Tracking.lua
46) Services/Loot/Rules.lua
47) Services/Raid/State.lua
48) Services/Raid/Capabilities.lua
49) Services/Raid/Counts.lua
50) Services/Raid/Roster.lua
51) Services/Raid/Attendance.lua
52) Services/Raid/LootRecords.lua
53) Services/Raid/Session.lua
54) Services/Chat.lua
55) EntryPoints/Minimap.lua
56) EntryPoints/SlashEvents.lua
57) Services/Rolls/Countdown.lua
58) Services/Rolls/Sessions.lua
59) Services/Rolls/History.lua
60) Services/Rolls/Responses.lua
61) Services/Rolls/Resolution.lua
62) Services/Rolls/Display.lua
63) Services/Rolls/Service.lua
64) Services/Loot/Service.lua
65) Services/Debug.lua
66) Controllers/Master.lua
67) Widgets/LootCounter.lua
68) Services/Reserves/Import.lua
69) Services/Reserves/Display.lua
70) Services/Reserves/Sync.lua
71) Services/Reserves.lua
72) Services/Reserves/Chat.lua
73) Widgets/ReservesUI.lua
74) Services/Logger/Store.lua
75) Services/Logger/View.lua
76) Services/Logger/Export.lua
77) Services/Logger/Helpers.lua
78) Services/Logger/Actions.lua
79) Controllers/Logger.lua
80) Widgets/Config.lua
81) Controllers/Warnings.lua
82) Controllers/Changes.lua
83) Controllers/Spammer.lua
84) KRT.xml

---

## 5) Repo layout (actual)

```
!KRT/
  !KRT.toc
  Init.lua                 # unified bootstrap + shared runtime glue + main event wiring
  KRT.xml                  # unified UI include manifest/orchestrator

  Core/
    DB.lua                 # DB facade/bootstrap
    Options.lua            # options namespace/defaults + flat-schema migration
    DBSchema.lua           # canonical raid schema
    DBManager.lua          # DB manager/factory
    DBRaidMigrations.lua   # raid SV migrations
    DBRaidStore.lua        # canonical raid store + runtime indexes
    DBRaidQueries.lua      # raid read/query helpers
    DBRaidValidator.lua    # raid schema validation helpers
    DBSyncer.lua           # logger synchronization store/protocol backend

  Controllers/
    Master.lua             # master-loot parent owner
    Logger.lua             # logger parent owner (UI/controller; data via Services/Logger/)
    Warnings.lua           # warnings parent owner
    Changes.lua            # changes parent owner
    Spammer.lua            # spammer parent owner

  Services/
    Raid/
      State.lua            # raid core state + shared internals
      Capabilities.lua     # raid role/capability policy
      Counts.lua           # loot counter/player count APIs
      Roster.lua           # player lookup/class/rank helper APIs
      Attendance.lua       # player attendance ledger from roster deltas
      LootRecords.lua      # loot-record lookup/matching/resolution APIs
      Session.lua          # raid/session facade + boss query/icon + changes data APIs
    Chat.lua               # output helpers (Print/Announce)
    Rolls/
      Countdown.lua        # countdown runtime helper (loaded before Service.lua)
      Sessions.lua         # roll-session lifecycle, tie-reroll, and current-context helpers
      History.lua          # raw roll entries, per-item trackers, and local roll-state helpers
      Responses.lua        # response lifecycle, eligibility, and incoming-roll helpers
      Resolution.lua       # resolver ordering, cutoff ties, and row-policy helpers
      Display.lua          # display-model assembly and winner/display helpers
      Service.lua          # roll tracking, sorting, winner logic (public service facade)
    Loot/
      Service.lua          # loot parsing, item selection, export strings, public service API
      Context.lua          # loot-context normalization/projection helpers
      State.lua            # activeLoot + legacy mirror synchronization + session helpers
      Snapshots.lua        # loot-window item snapshot state helpers
      PendingAwards.lua    # pending-award lifecycle helpers + consume/refresh policy
      PassiveGroupLoot.lua # passive group-loot parser/state/winner helpers
      Tracking.lua         # runtime tracking/debug snapshot builders
      Rules.lua            # suggestion-only auto-loot rule classifier
    Debug.lua              # synthetic raid/roll test helpers for local addon testing
    Reserves/
      Import.lua           # import parser/strategy helpers (loaded before Reserves.lua)
      Display.lua          # grouped display/player-format helpers (loaded before Reserves.lua)
      Chat.lua             # opt-in !sr/!softres whisper response policy
    Reserves.lua           # soft reserves service/model + canonical public facade
    Logger/
      Store.lua            # logger stable-ID indexing + data access
      View.lua             # view-model row builders and label formatters
      Export.lua           # logger CSV export builders
      Helpers.lua          # logger UI label/title formatting helpers
      Actions.lua          # logger mutations + commit/cascade + selection validation

  Widgets/
    LootCounter.lua        # loot counter UI + data
    ReservesUI.lua         # reserve list + import frame controller + row/header rendering
    Config.lua             # options UI logic

  EntryPoints/
    Minimap.lua            # minimap button + context menu
    SlashEvents.lua        # slash command router

  UI/
    Templates/
      Common.xml           # shared XML templates
    Minimap.xml            # minimap button frame
    ReservesTemplates.xml  # reserve list templates
    Reserves.xml           # reserve list UI + reserve import window UI
    Logger.xml             # logger templates + frames
    Config.xml             # config UI
    Spammer.xml            # spammer UI
    Warnings.xml           # warnings UI
    Master.xml             # item selection + master looter UI
    LootCounter.xml        # loot counter UI
    Changes.xml            # changes UI

  Localization/
    localization.en.lua    # user-facing strings (enUS) -> addon.L
    DiagnoseLog.en.lua     # diagnostic templates (enUS) -> addon.Diagnose

  Modules/
    C.lua                  # constants/enums/patterns (addon.C)
    Timer.lua              # timer mixin/stat helpers backed by LibCompat (addon.Timer)
    Events.lua             # centralized event-name registry (addon.Events)
    Colors.lua             # color normalization/class-color helpers (addon.Colors)
    Strings.lua            # text normalization and chat parsing helpers (addon.Strings)
    Item.lua               # item-link parsing + tooltip probe helpers (addon.Item)
    IgnoredItems.lua       # canonical item-ignore lookup used by loot logging
    IgnoredMobs.lua        # canonical raid add/phase-ignore lookup used by boss filtering
    Comms.lua              # addon chat/whisper/sync helpers (addon.Comms)
    Time.lua               # time/difficulty helpers (addon.Time)
    Base64.lua             # base64 codec helpers (addon.Base64)
    Sort.lua               # sort comparators + tie-breakers (addon.Sort)
    Features.lua           # feature flags/profile toggles (addon.Features)
    UI/
      Facade.lua           # widget facade (addon.UI) with Register/Call no-op routing
      Effects.lua          # glow/proc button effects backend (addon.UIEffects)
      Visuals.lua          # UI primitives + row visuals (addon.UIPrimitives/addon.UIRowVisuals)
      Frames.lua           # frame helpers + UI scaffold/orchestration (addon.Frames/addon.UIScaffold)
      ListController.lua   # reusable scroll-list controller (addon.ListController)
      MultiSelect.lua      # reusable multiselect state helpers (addon.MultiSelect)
    Bus.lua                # internal callback bus + metrics (addon.Bus)

  Libs/
    LibStub/
    CallbackHandler-1.0/
    LibBossIDs-1.0/
    LibDeformat-3.0/
    LibCompat-1.0/
    LibLogger-1.0/
```

---

## 6) Globals & SavedVariables (**BINDING**)

### 6.1 Intentional globals (allowed)

- `_G["KRT"] = addon` is set by `Init.lua` for debugging/interop.
- Named XML frames become globals (normal WoW UI behavior). Examples:
  - `KRTConfig`, `KRTWarnings`, `KRTMaster`, `KRTLogger`, `KRTChanges`, `KRTSpammer`
  - `KRTLootCounterFrame`, `KRTReserveListFrame`, `KRTImportWindow`, `KRTItemSelectionFrame`
  - `KRTLoggerBossBox`, `KRT_MINIMAP_GUI`
- `Init.lua` intentionally defines a few global convenience helpers:
  - `table.shuffle`, `table.reverse`, `string.trim`, `string.startsWith`, `string.endsWith`

Do not introduce additional non-frame globals (tables/vars/functions) unless explicitly required and documented.

### 6.2 SavedVariables (account)

These keys are persisted and must remain compatible:
- `KRT_Raids`
- `KRT_Players`
- `KRT_Reserves`
- `KRT_Warnings`
- `KRT_Spammer`
- `KRT_Options`

---

## 7) Language & strings (**BINDING**)

KRT is standardized on English.

Rules:
1) All new/modified content must be English (comments, logs, UI labels, chat text).
2) User-facing strings MUST go through `addon.L` (Localization/localization.en.lua).
3) Log/debug templates MUST go through `addon.Diagnose` (Localization/DiagnoseLog.en.lua).
4) Prefer format placeholders over sentence concatenation (use `format(L.Key, a, b)`).
5) Prefer ASCII-only in code/comments/logs (avoid typographic quotes/dashes and emojis).

---

## 8) Call style: `:` vs `.` (**BINDING**)

Lua method call depends on whether the function expects `self`:

- Use `:` for true methods (first parameter is `self`):
  - `addon:info(...)`, `addon:ADDON_LOADED(...)`, `module:Toggle()`, `Store:GetRaid(...)`
- Use `.` for plain functions (no `self`):
  - `Utils.getRaid(...)`, `addon.Options.EnsureLoaded()`, `addon.Options.Set(key, value)`, `addon.Timer.BindMixin(target, name)`

Rule: do not mechanically convert `.` <-> `:` unless you verified the function signature.

---

## 9) UI refresh policy: event-driven (**BINDING**)

KRT is actively refactoring away from polling-style UI updates.

Rules:
- Prefer on-demand UI redraws via `Utils.makeEventDrivenRefresher(getFrame, updateFn)`.
- Modules should expose:
  - `module:Refresh()` (pure redraw) and `module:RequestRefresh()` (throttled request).
- Avoid setting `OnUpdate` on feature frames to poll state.
- Allowed exceptions:
  - minimap drag movement,
  - LibCompat internal timers,
  - Utils internal driver frames used by `makeEventDrivenRefresher`.

For scroll lists:
- Prefer `Utils.makeListController({...})` + `controller:Dirty()` over manual row loops.
- For multi-selection, use `Utils.MultiSelect_*` with stable IDs.

---

## 10) Options access pattern

- SV table is `KRT_Options`, structured as nested namespaces (schema 2).
- Each module owns a namespace and registers its defaults at file load:
  ```lua
  local cfg = addon.Options.AddNamespace("Rolls", { countdownDuration = 5, ... })
  cfg:Get("countdownDuration")          -- read
  cfg:Set("countdownDuration", 10)       -- write (emits OptionChanged via Bus)
  cfg:ResetDefaults()                    -- per-namespace reset
  ```
- Read-only flat shortcut: `addon.options.<key>` resolves O(1) through `keyToNamespace`.
  Writes via `addon.options.x = v` are forbidden (raises) — use `namespace:Set` or
  `addon.Options.Set(key, value)` (dispatcher).
- `addon.Options.EnsureLoaded()` runs on ADDON_LOADED and migrates legacy flat schema 1 → nested schema 2 once.
- Bus events emitted: `addon.Events.Internal.OptionChanged(namespace, key, old, new)`,
  `OptionsReset(namespace)`, `OptionsLoaded`.
- Exception: `debug` is runtime-only state on `addon.State.debugEnabled` and must not be persisted.

---

## 11) Module map (runtime `addon.*`)

Top-level feature modules on `addon.*`:
- `addon.Raid`          - compatibility alias to canonical `addon.Services.Raid`
- `addon.Chat`          - compatibility alias to canonical `addon.Services.Chat`
- `addon.Minimap`       - minimap button + EasyMenu
- `addon.Rolls`         - roll tracking, sorting, winner logic
- `addon.Loot`          - loot parsing, item selection, export strings
- `addon.Master`        - master-loot helpers, award/trade tracking
- `addon.LootCounter`   - loot counter UI + data
- `addon.Reserves`      - soft reserves service facade (data/model APIs)
- `addon.ReservesUI`    - reserve list UI widget owner
- `addon.ReservesUI.Import` - reserve import UI widget owner
- `addon.Config`        - options UI + defaults/load
- `addon.Warnings`      - warnings list + announce helpers
- `addon.Changes`       - MS changes list + announce
- `addon.Spammer`       - LFM spam helper
- `addon.Logger`        - loot logger UI + raid editor
- `addon.Syncer`        - logger synchronization protocol (request/push + merge)

Namespaced service-only module:
- `addon.Services.Debug` - synthetic raid/roll test helpers for current-raid testing
- `addon.Services.Rolls._Countdown` - rolls countdown runtime helper surface
- `addon.Services.Rolls._Sessions` - rolls session/tie-reroll helper surface
- `addon.Services.Rolls._History` - rolls raw-history and tracker helper surface
- `addon.Services.Rolls._Responses` - rolls response/eligibility helper surface
- `addon.Services.Rolls._Resolution` - rolls resolver and row-policy helper surface
- `addon.Services.Rolls._Display` - rolls display-model and winner helper surface
- `addon.Services.Reserves._Import` - reserves import parser helper surface
- `addon.Services.Reserves._Display` - reserves grouped display/player formatting helper surface

Root-method compatibility exception:
- `addon:Print` remains a compatibility hook required by `LibLogger-1.0`.
- Avoid root addon method facades for chat/capability contracts; target
  `addon.Services.Chat` / `addon.Chat` and `addon.Services.Raid` / `addon.Raid` directly.

`addon.Logger` internal structure (pattern for complex modules):
- `addon.Logger.Store`   - data access helpers + stable-ID indexing (Services/Logger/Store.lua)
- `addon.Logger.View`    - view-model row builders (UI-friendly data) (Services/Logger/View.lua)
- `addon.Logger.Export`  - Logger CSV export builders (Services/Logger/Export.lua)
- `addon.Logger.Helpers` - UI label/title formatting helpers (Services/Logger/Helpers.lua)
- `addon.Logger.Actions` - mutations + commit/refresh boundaries (Services/Logger/Actions.lua)

Namespaced service modules (loaded before Controller):
- `addon.Services.Logger.Store`   - canonical Store service table
- `addon.Services.Logger.View`    - canonical View service table
- `addon.Services.Logger.Export`  - canonical Export service table
- `addon.Services.Logger.Helpers` - canonical Helpers service table
- `addon.Services.Logger.Actions` - canonical Actions service table

Implementation placement (current wave):
- `Init.lua`: unified bootstrap/runtime core + main gameplay/logger logic + `Core.GetFeatureShared()`
- `Controllers/*.lua`, `Services/*.lua`, `Widgets/*.lua`, `EntryPoints/*.lua`

External modules:
- `addon.C`     (Modules/C.lua)
- `addon.Timer` (Modules/Timer.lua)
- `addon.Events` (Modules/Events.lua)
- `addon.Colors` (Modules/Colors.lua)
- `addon.Strings` (Modules/Strings.lua)
- `addon.Item` (Modules/Item.lua)
- `addon.IgnoredItems` (Modules/IgnoredItems.lua)
- `addon.IgnoredMobs` (Modules/IgnoredMobs.lua)
- `addon.Comms` (Modules/Comms.lua)
- `addon.Time` (Modules/Time.lua)
- `addon.Base64` (Modules/Base64.lua)
- `addon.Sort` (Modules/Sort.lua)
- `addon.UIEffects` (Modules/UI/Effects.lua)
- `addon.UIPrimitives` (Modules/UI/Visuals.lua)
- `addon.UIRowVisuals` (Modules/UI/Visuals.lua)
- `addon.Frames` (Modules/UI/Frames.lua)
- `addon.UIScaffold` (Modules/UI/Frames.lua)
- `addon.MultiSelect` (Modules/UI/MultiSelect.lua)
- `addon.ListController` (Modules/UI/ListController.lua)
- `addon.Bus` (Modules/Bus.lua)
- `addon.Features` (Modules/Features.lua)
- `addon.UI`    (Modules/UI/Facade.lua)

---

## 12) Lua 5.1 coding standard (**BINDING**)

Non-negotiables:
1) No accidental globals: everything is `local` unless intentionally exported.
2) Prefer locals for performance/readability.
3) Avoid environment hacks in addon logic (`getfenv/setfenv` only for niche debug tools).

Formatting:
- Indentation: 4 spaces (legacy code may contain tabs; do not mass-reformat).
- No trailing whitespace. No semicolons.

Errors/returns:
- Recoverable failure: `return nil, "reason"` or `return false` with a localized error message.
- Programmer errors/invariants: `assert()` or `error()`.

Iteration:
- Arrays are 1-indexed.
- If holes are possible, do not rely on `#t`.
- Prefer `for i = 1, #arr do ... end` for sequences; `pairs()` for maps.

---

## 13) Logging (LibLogger-1.0)

Use consistent levels:
- error: breaks functionality or corrupts state
- warn: abnormal but non-blocking behavior
- info: major lifecycle events (raid created, award, trade, boss kill)
- debug/trace: detailed flow (avoid spam, especially in combat)

Throttle high-frequency sources (roster bursts, combat log, UI refresh loops) with LibCompat timers.

---

## 14) WoW 3.3.5a compatibility

- Do not use modern APIs (`C_Timer`, `C_` namespaces, etc.).
- Avoid `io/os/debug` (not available in WoW runtime).
- Respect combat lockdown (avoid secure frame changes in combat).

---

## 15) Manual test checklist

- Login: no errors; `/krt` opens.
- Raid detection: instance/difficulty detected; current raid created; roster updates.
- Rolls: MS/OS/SR works; stable sorting; deterministic winner.
- Reserves: import/export; caps; roll gating consistent.
- Logger: loot entries append; filters; delete flows; selection highlight works.
- Master: award/trade tracking; multi-award; `/krt counter` toggles Loot Counter.
- Warnings/Changes/Spammer: correct channels + throttling; no UI spam.
- Persistency: `/reload` keeps SV and expected state.

---

## 16) Do / Don't

Do:
- small testable changes,
- reuse templates and Utils controllers,
- keep state local to module blocks,
- keep feature logic in `Controllers/*.lua` / `Services/*.lua` / `Widgets/*.lua` / `EntryPoints/*.lua`,
  and shared infra in `Init.lua`,
- document user-visible changes in CHANGELOG.md.

Don't:
- Ace3,
- long blocking loops,
- new SV keys without migration,
- new globals (beyond allowed ones).

---

## 17) Static analysis (`.luacheckrc`)

- Keep `.luacheckrc` aligned with current addon globals and frame names.
- When XML introduces/removes named frames, update `.luacheckrc` global allowlist in the same change.
- Prefer additive, explicit entries grouped under a `KRT addon globals` comment block.

---

## 18) Architecture layering (Parents/Services + Bus) (**BINDING**)

- 5 top-level Parents: `Changes`, `MasterLoot` (`addon.Master`), `Warnings`, `Logger`, `Spammer`.
- Parent owner files live under `!KRT/Controllers/` (folder naming), while "Parent" remains the architecture term.
- Services MUST NOT call Parents or touch Parent frames.
- Services MUST NOT reference Widgets or delegate UI (`addon.*UI`, `module.UI`, `Get*UI` patterns).
- Upward communication uses internal bus (`Bus.RegisterCallback` / `Bus.TriggerEvent`).
- EntryPoint toggle exception: `EntryPoints/SlashEvents.lua` and `EntryPoints/Minimap.lua` may call
  `Parent:Toggle()`.
- Prefer existing events (`SetItem`, `RaidRosterDelta`) over new UI micro-events.
- UI ownership: Master frame UI code lives in `Master` (or Master View helpers).
- Child widgets attach Parent->Child only.
