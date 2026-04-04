# Changelog

All notable changes to !KRT will be documented in this file.

## Unreleased

Release-Version: 0.6.2b

### Changed

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

## [0.6.2b] - 2026-03-21

### Changed

- Disabled the Logger Export tab by default while the export workflow remains work in progress.

## [0.6.0b] - 2026-03-08

### Changed

- Added new feature
