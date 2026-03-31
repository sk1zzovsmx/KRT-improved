# Changelog

All notable changes to !KRT will be documented in this file.

## Unreleased

Release-Version: 0.6.2b

### Changed

- Hardened master-looter-only behavior in raid context:
  non-master clients no longer run loot/roll ingestion
  (`CHAT_MSG_LOOT`/`CHAT_MSG_SYSTEM`) and slash/minimap
  entrypoints now block master-only modules.
- Centralized raid-role capability checks so loot, raid-warning,
  changes broadcast, ready-check, and raid-icon actions derive
  their enabled/disabled state from a shared policy.
- Temporarily disabled the Logger Export tab again while the
  export workflow remains staged off.

## [0.6.2b] - 2026-03-21

### Changed

- Disabled the Logger Export tab by default while the export workflow remains work in progress.

## [0.6.0b] - 2026-03-08

### Changed

- Added new feature
