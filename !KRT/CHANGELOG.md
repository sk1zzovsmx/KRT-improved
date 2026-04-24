# Changelog

All notable changes to !KRT will be documented in this file.

## Unreleased

Release-Version: 0.7.0-beta.1

### Enhancements

- **Slash diagnostics** - Added focused `/krt help <command>` pages plus
  `/krt version` and `/krt bug` local diagnostic summaries for support.
- **Group version check** - `/krt version` now requests KRT version details
  from grouped addon users through a dedicated addon-message prefix.
- **SoftRes runtime sync** - Added lightweight `/krt res sync` support for
  grouped KRT clients to request runtime-only SoftRes metadata/data from an
  authorized reserve owner without persisting received reserves.
- **Auto-loot suggestions** - Added a lightweight suggestion-only loot rules
  classifier for ignored items, enchanting materials, and quality BoE loot,
  including 3.3.5a tooltip-based bind detection; it does not auto-award or
  auto-trade items.
- **Logger UI polish** - Refreshed the Logger toward a MizusRaidTracker-style
  Wrath raid-log look with dark compact tables, yellow section titles,
  out-of-panel controls, and green selected rows.
- **Raid attendance ledger** - Added a per-player attendance ledger keyed by
  `playerNid`, updated from roster deltas, persisted as raid schema v4, and
  exported through a dedicated attendance CSV builder without replacing the
  existing loot-oriented raid export.
- **Loot source recovery** - Added a limited `LOOT_OPENED` boss-source fallback
  that scans dead target/mouseover/raid-target units by NPC ID classification
  when no valid loot-window context already exists.
- **Performance: Bus event dispatch** — Eliminated per-fire table allocation
  in `Bus.TriggerEvent`; reuses a static dispatch buffer to reduce GC pressure
  during active raiding (dozens of events/second).
- **Performance: Proc glow animation** — Throttled sparkle `OnUpdate` to ~30 FPS
  (was unthrottled at 60 FPS), cutting `SetPoint` layout recalculations by half
  during glow effects.
- **Performance: Roll UI model** — Decorated roll rows in-place instead of
  allocating + copying a new table per visible row per refresh; also simplified
  `copyVisibleRollRows` to reference existing rows directly.
- **Performance: Loot window item info** — When loot-slot hints are available
  (loot window path), skip the blocking `GetItemInfo` call and defer tooltip-
  based item cache warming through a timer queue, avoiding micro-freezes on
  `LOOT_OPENED` with many items.
- **Performance: Passive group loot** — Reuse a static `numbers` buffer in
  `extractGroupLootPatternValues` instead of allocating a new table per
  parsed loot message.

### Internal

- Consolidated `Services/Raid/Boss.lua` and `Services/Raid/Changes.lua` into
  `Services/Raid/Session.lua`; removed 2 redundant thin-wrapper files.
- Consolidated `Services/Loot/Sessions.lua` into `Services/Loot/State.lua`;
  removed 1 redundant thin-wrapper file.
- Cleaned `Services/Loot/PendingAwards.lua` public surface: removed 13
  internal helpers that were unnecessarily exported; only
  `NormalizePendingAwardItemKey` remains exposed for cross-module use.
- Removed 9 pure pass-through `PassiveGroupLoot` wrappers from
  `Services/Loot/Service.lua`; internal callers now call
  `PassiveGroupLoot.*` directly.
- Removed redundant `normalizeCandidateKey` local from
  `Services/Rolls/Service.lua`; calls `Sessions.NormalizeCandidateKey`
  directly.
- Removed 3 pass-through format methods from `Services/Reserves.lua`;
  `Widgets/ReservesUI.lua` now uses inline `L.*` format calls directly.
- Simplified verbose `getRaidService()` pattern in 3 Loot service files
  to the concise 1-line variant.
- Removed inline fallback loop from `resolveLootLooterName` in
  `Services/Loot/Service.lua`; delegates to canonical
  `Roster:GetPlayerName` instead of reimplementing player-by-NID lookup.
- Replaced inline `string.find` item-link parsing in
  `Services/Loot/Service.lua` with canonical `Item.GetItemStringFromLink`
  and `Item.GetItemIdFromLink`; removed unused `ITEM_LINK_PATTERN` local.
- Centralized `requireServiceMethod` in `Core.RequireServiceMethod`;
  removed 4 identical copies from Controllers (Master, Warnings, Spammer,
  Changes).
- Removed `resolveRaidDifficulty` and `getRaidSizeFromDifficulty`
  pass-through wrappers from `Services/Raid/Session.lua`; call sites use
  internal `_ResolveRaidDifficultyInternal`/`_GetRaidSizeFromDifficultyInternal`
  directly.
- Eliminated `getRaidService()` wrapper functions from 5 Service files
  (Chat, Rolls/Service, Loot/Service, Loot/PassiveGroupLoot, Loot/Tracking);
  replaced with direct `Services.Raid` access.
- Removed `getLootModule()` pass-through from `Services/Rolls/Service.lua`;
  replaced with direct `Services.Loot` access.
- Simplified 6 defensive item-helper wrappers in `Controllers/Master.lua`
  to direct `Loot.*` delegation (load order guarantees availability).
- Added `UIScaffold.EnsureModuleUi(module)` factory in `Modules/UI/Frames.lua`;
  replaced 8 identical inline `_ui` schema initializations across Controllers
  and Widgets with single-line factory calls.

### Fixed

- Fixed Master loading on Lua 5.1/WoW clients by reducing chunk-scope locals in
  `Controllers/Master.lua`.
- Fixed Master assignment dropdown clicks (`Hold`/`Bank`/`Disenchant`) using the
  wrong `UIDropDownMenu` callback argument order, which could trigger
  `UIDropDownMenu.lua:862` (`filterText` nil) on selection.
- Fixed multi-item boss loot attribution in Master Loot windows: once the first
  item resolves the boss correctly, later items from the same open boss loot
  window now keep that scoped boss context instead of falling back to
  `_TrashMob_` after the short event context expires.
- Fixed Award and Hold/Trade boss propagation so loot-window event context is
  snapped on open, carried on the roll session, and reused by trade-only
  fallbacks instead of reclassifying the loot source late.
- Tightened Boss/Trash attribution on `LOOT_OPENED`: an explicitly opened
  non-boss corpse now blocks recent boss-context recovery, while boss corpse
  mouseover can restore the correct boss scope without relying on late loot
  receipt heuristics.

## Archived (not published)

### [0.7.0-beta.3] - 2026-04-06

### Added

- Added dedicated `Services/Raid/*` modules (`State`, `Roster`, `Counts`,
  `Session`, `Boss`, `LootRecords`, `Changes`, `Capabilities`) so raid data,
  loot ownership, roster helpers, loot-counter state, and capability checks now
  expose focused canonical APIs outside the old monolithic `Services/Raid.lua`.
- Added canonical raid capability and loot-context APIs such as
  `CanUseCapability`, `EnsureMasterOnlyAccess`, `CanBroadcastChanges`,
  `FindAndRememberBossContextForLootSession`, and `FindOrCreateBossNidForLoot`
  to centralize controller/service access rules.
- Added changelog-driven GitHub release note generation in `tools/krt.py` and
  the publish workflow, with concise `Included Commits`,
  `New Functionality`, and `Enhancements/Improvement` sections.

### Changed

- Split the previous monolithic `Services/Raid.lua` implementation into focused
  `Services/Raid/*` files and migrated loot/runtime call-sites to canonical
  Raid/Loot service ownership, reducing redundant bridge wrappers and aliases.
- Aligned the remaining loot-bridge APIs to the repo verb taxonomy and
  canonical PascalCase contracts, then refreshed API catalogs and cleanup docs
  to match the reduced public surface after the cleanup wave.
- GitHub release publishing now uses changelog-derived summaries plus an exact
  commit-range compare link instead of raw auto-generated release notes.

### [0.7.0-beta.2] - 2026-04-06

### Added

- Introduced scoped loot-boss session tracking for passive Group Loot and
  trade follow-up flows, so later loot receipts can reuse the original boss
  context without relying on implicit `lastBoss` inheritance.

### Changed

- Tightened boss/trash loot association policy: loot records now resolve
  `bossNid` from scoped roll-session context (including passive Group Loot
  sessions) and only use short-lived boss-event context for non-passive flows.
  The previous recent-boss and current-target recovery heuristics were removed,
  and missing scoped context now falls back directly to `_TrashMob_`.
- Localized the synthetic trash bucket label through `L.StrTrashMobName`
  while keeping legacy `_TrashMob_` compatibility in logger and validator
  flows.

### Fixed

- Fixed incorrect boss attribution in loot history when scoped context was
  missing or stale: loot receipts no longer recover boss ownership from recent
  kills or the current target and now fall back cleanly to the trash bucket.
- Fixed trade-only loot and roll-session lookups inheriting stale boss context
  from implicit `lastBoss`; they now use explicit/scoped context with the same
  trash fallback policy.

## [0.7.0-beta.1] - 2026-04-05

### Added

- Extended synthetic raid-roll debug helper: `/krt debug raid rolls` now
  accepts optional `tie` mode (`/krt debug raid rolls tie`) to submit
  deterministic high-priority ties across a random 2-3 subset of synthetic
  players, making tie-resolution testing faster.

### Changed

- Logger loot now shows the item tooltip on mouse over the item icon only and
  anchors it to the cursor, with an `itemId` fallback hyperlink when a stored
  `itemLink` is missing.
- Countdown late-roll handling now honors `countdownRollsBlock`: when disabled,
  rolls submitted after countdown expiry remain accepted and are marked as
  `OOT` in the rolls Info column, but `OOT` responses are excluded from
  resolver candidates, manual winner selection, and tie-reroll triggers.
- Improved Master status readability: long status lines now wrap instead of
  clipping (for example countdown-bypassed rolling status), and the rolls
  header/list anchors were shifted to preserve spacing.
- Hardened master-looter-only behavior in raid context:
  non-master clients no longer run loot/roll ingestion
  (`CHAT_MSG_LOOT`/`CHAT_MSG_SYSTEM`) and slash/minimap
  entrypoints now block master-only modules.
- Restored passive Logger history for non-master loot modes:
  Group Loot / Need Before Greed outcomes now log into the
  current raid history with `NE`, `GR`, and `DE` roll types
  while keeping master-only gameplay flows blocked. When the
  server also emits numeric group-roll lines, the Logger now
  preserves that `rollValue` too. Passive winner messages now
  materialize Logger rows immediately, while later duplicate
  loot receipts are deduplicated. Self roll lines now feed the
  same `rollValue` pipeline, and late numeric passive updates can
  backfill a winner row that was logged before the value arrived.
  Raw chat lines such as "Need Roll - 67 for ... by ..." are now
  parsed too, so those values no longer fall through as passive
  zero-value wins.
- Centralized raid-role capability checks so loot, raid-warning,
  changes broadcast, ready-check, and raid-icon actions derive
  their enabled/disabled state from a shared policy.
- Published release metadata now uses SemVer forms
  (`x.y.z`, `x.y.z-alpha.N`, `x.y.z-beta.N`) in `Release-Version`
  and TOC versioning so workflows and packaged assets resolve
  consistently.
- Temporarily disabled the Logger Export tab again while the
  export workflow remains staged off.
- Extracted Logger Store/View/Actions into `Services/Logger/Store.lua`,
  `Services/Logger/View.lua`, and `Services/Logger/Actions.lua`;
  `Controllers/Logger.lua` now imports them via `addon.Services.Logger`.
  No behavior changes.
- Started the Changes slimdown implementation without adding new service files:
  raid-scoped changes CRUD, broadcast capability checks, and announce/demand
  text builders now live in `Services/Raid.lua`, while
  `Controllers/Changes.lua` is reduced to UI state, list rendering, and action
  wiring. No behavior changes.
- Continued slimdown with Spammer phase 2 without adding new service files:
  spam output building, duration normalization, channel send path, and
  runtime cycle state/timer control now live in `Services/Chat.lua`
  (`BuildSpammerOutput`, `NormalizeSpamDuration`, `SendSpamOutput`,
  `GetSpamRuntimeState`, `StartSpamCycle`, `PauseSpamCycle`,
  `StopSpamCycle`), while `Controllers/Spammer.lua` stays focused on
  refs/binding, localization, input lock visuals, countdown text, and refresh.
  No behavior changes.
- Continued with conservative Warnings phase 3: kept warning CRUD/UI ownership
  in `Controllers/Warnings.lua` and extracted only the announce path into
  `Services/Chat.lua` via `NormalizeWarningMessage` and
  `AnnounceWarningMessage` (including raid-warning permission fallback notice).
  No behavior changes.
- Started Master phase 4 micro-extractions without adding new service files:
  held-inventory loot slot matching/resolution moved to `Services/Raid.lua`
  (`MatchHeldInventoryLoot`, `ResolveHeldLootNid`), while winner/tie helpers
  and countdown lifecycle APIs are now exposed by `Services/Rolls/Service.lua`
  (`GetDisplayedWinner`, `GetResolvedWinner`, `ShouldUseTieReroll`,
  `StartCountdown`, `StopCountdown`, `FinalizeRollSession`).
  `Controllers/Master.lua` now delegates to those services with local
  compatibility fallbacks. No behavior changes.
- Continued Master phase 4 countdown cleanup: `Controllers/Master.lua`
  no longer owns local countdown runtime state/timers and now derives
  countdown state from `Services/Rolls/Service.lua` (`IsCountdownRunning`) while
  delegating start/stop/finalize entirely to Rolls service APIs.
  No behavior changes.
- Completed dedicated Master hardening step before fallback removal:
  `Controllers/Master.lua` now validates required Raid/Rolls method contracts
  at load time and uses direct service calls for winner/tie resolution,
  held-loot resolution, candidate resolution, expected-winner sync, and
  countdown lifecycle (removed legacy compatibility fallback branches).
  No behavior changes.
- Applied the same dedicated hardening to the remaining slimdown controllers:
  `Controllers/Changes.lua`, `Controllers/Spammer.lua`, and
  `Controllers/Warnings.lua` now validate required service contracts at load
  time and use direct service calls (removed residual compatibility fallback
  branches to Raid/Chat). Test harness service defaults were aligned to the
  hardened contracts. No behavior changes.

### Fixed

- Fixed single-winner tie flow in Master UI: tie reroll is now available
  even when the winner list is in pick mode and no manual winner has been
  selected yet.
- Master roll intake now reopens correctly after `MS/OS/SR/FREE`
  announcements even when the Rolls service pre-bootstraps the roll session;
  opening roll intake restores the canonical `rollStarted` state so countdown
  can be started again from the Countdown button.
- Isolated passive Group Loot pending awards from Master Looter
  award resolution: switching from Group Loot/NBG to ML no
  longer reuses stale `GL:*` pending sessions on the first
  ML award.
- Hardened Master loot-slot resolution so award/trade flows keep matching
  the same item even when the live loot window hyperlink payload differs
  from the stored item link; multi-award slot scanning now uses the same
  itemId fallback.
- Hardened boss-context recovery for loot logging: boss events now populate
  a dedicated short-lived context independent from `lastBoss`; loot logging
  consumes that event context first, then falls back to recent real boss
  kills and only finally to the current target / `_TrashMob_`.

## [0.6.2b] - 2026-03-21

### Changed

- Disabled the Logger Export tab by default while the export workflow remains work in progress.

## [0.6.0b] - 2026-03-08

### Changed

- Added new feature
