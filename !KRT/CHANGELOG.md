# Changelog

All notable changes to !KRT will be documented in this file.

## Unreleased

Release-Version: 0.7.0-beta.1

### Changed

- Logger loot now shows the item tooltip on mouse over the item icon only and
  anchors it to the cursor, with an `itemId` fallback hyperlink when a stored
  `itemLink` is missing.

- Extended synthetic raid-roll debug helper: `/krt debug raid rolls`
  now accepts optional `tie` mode (`/krt debug raid rolls tie`) to
  submit deterministic high-priority ties across a random 2-3 subset
  of synthetic players, making tie-resolution testing faster.
- Fixed single-winner tie flow in Master UI: tie reroll is now available
  even when the winner list is in pick mode and no manual winner has been
  selected yet.
- Countdown late-roll handling now honors `countdownRollsBlock`: when disabled,
  rolls submitted after countdown expiry remain accepted and are marked as
  `OOT` in the rolls Info column, but `OOT` responses are excluded from
  resolver candidates, manual winner selection, and tie-reroll triggers.
- Improved Master status readability: long status lines now wrap instead of
  clipping (for example countdown-bypassed rolling status), and the rolls
  header/list anchors were shifted to preserve spacing.
- Master roll intake now reopens correctly after `MS/OS/SR/FREE`
  announcements even when the Rolls service pre-bootstraps the roll session;
  opening roll intake restores the canonical `rollStarted` state so countdown
  can be started again from the Countdown button.
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
- Isolated passive Group Loot pending awards from Master Looter
  award resolution: switching from Group Loot/NBG to ML no
  longer reuses stale `GL:*` pending sessions on the first
  ML award.
- Centralized raid-role capability checks so loot, raid-warning,
  changes broadcast, ready-check, and raid-icon actions derive
  their enabled/disabled state from a shared policy.
- Temporarily disabled the Logger Export tab again while the
  export workflow remains staged off.
- Extracted Logger Store/View/Actions into `Services/Logger/Store.lua`,
  `Services/Logger/View.lua`, and `Services/Logger/Actions.lua`;
  Controllers/Logger.lua now imports them via `addon.Services.Logger`.
  No behavior changes.
- Hardened Master loot-slot resolution so award/trade flows keep matching
  the same item even when the live loot window hyperlink payload differs
  from the stored item link; multi-award slot scanning now uses the same
  itemId fallback.
- Hardened boss-context recovery for loot logging: boss events now populate
  a dedicated short-lived context independent from `lastBoss`; loot logging
  consumes that event context first, then falls back to recent real boss
  kills and only finally to the current target / `_TrashMob_`.
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
  and countdown lifecycle APIs are now exposed by `Services/Rolls.lua`
  (`GetDisplayedWinner`, `GetResolvedWinner`, `ShouldUseTieReroll`,
  `StartCountdown`, `StopCountdown`, `FinalizeRollSession`).
  `Controllers/Master.lua` now delegates to those services with local
  compatibility fallbacks. No behavior changes.
- Continued Master phase 4 countdown cleanup: `Controllers/Master.lua`
  no longer owns local countdown runtime state/timers and now derives
  countdown state from `Services/Rolls.lua` (`IsCountdownRunning`) while
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

## [0.6.2b] - 2026-03-21

### Changed

- Disabled the Logger Export tab by default while the export workflow remains work in progress.

## [0.6.0b] - 2026-03-08

### Changed

- Added new feature
