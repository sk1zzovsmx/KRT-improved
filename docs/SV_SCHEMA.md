# SavedVariables Schema Inventory

This file inventories the SavedVariables keys and args currently read/written by runtime code.
Scope: `KRT_*` SavedVariables declared in `!KRT/!KRT.toc` and persisted in the
WoW SavedVariables file for the addon.
Current raid schema version: `3`.

## Canonical Name Terms

- `PlayerName`: canonical persisted player name kept in readable display casing.
- `PlayerLookupKey`: runtime-only normalized lowercase key used for deterministic lookup.

## Top-Level SavedVariables

- `KRT_Raids`
- `KRT_Players`
- `KRT_Reserves`
- `KRT_Warnings`
- `KRT_Spammer`
- `KRT_Options`

## KRT_Raids

Type: `array<RaidRecord>`

Canonical schema is documented in `docs/RAID_SCHEMA.md`.

Observed persisted loot extras (also written by runtime):
- `loot[].rollSessionId` (optional string)
- `loot[].source` (optional string, for example `TRADE_ONLY`)

Observed persisted raid role assignees (optional):
- `holder` (string, Master Loot hold target)
- `banker` (string, Master Loot bank target)
- `disenchanter` (string, Master Loot disenchant target)

v3 storage optimization:
- optional/default-only fields can be omitted during save compaction,
- runtime readers resolve defaults when fields are omitted.

Legacy fields accepted/transient during normalization:
- `loot[].looter` (legacy winner reference; normalized into `looterNid` then cleared)
- `bossKills[].attendanceMask` (legacy; cleared)
- Load/save hardening emits diagnostics when these legacy fields are detected.

Runtime-only keys (must not persist):
- `raid._runtime`
- `raid._playersByName`
- `raid._playerIdxByNid`
- `raid._bossIdxByNid`
- `raid._lootIdxByNid`

SV sanity checklist is defined in `docs/SV_SANITY_CHECKLIST.md`.

## KRT_Players

Type: `map<RealmName, map<PlayerName, PlayerMeta>>`

`PlayerMeta` fields currently written:
- `name` (string)
- `level` (number)
- `race` (string)
- `raceL` (string)
- `class` (string)
- `classL` (string)
- `sex` (number)

## KRT_Reserves

Type: `map<PlayerName, ReservePlayerRecord>`

`ReservePlayerRecord`:
- `reserves` (`array<ReserveEntry>`)

`ReserveEntry` fields currently written:
- `rawID` (number)
- `itemLink` (string or nil)
- `itemName` (string or nil)
- `itemIcon` (string or nil)
- `quantity` (number, default `1`)
- `class` (string or nil)
- `spec` (string or nil)
- `note` (string or nil)
- `plus` (number, default `0`)
- `source` (string or nil)

Notes:
- Persisted `PlayerName` keys in this store use readable display casing.
- Example: `"  FeRRa  "` is normalized and persisted as `PlayerName = "Ferra"`.
- Runtime lookup keys are derived with `Strings.NormalizeLower` and are not persisted.
- Legacy load compatibility migrates old lowercase-key + `playerNameDisplay`,
  old `original`, and `reserve.player` fields to the canonical saved shape.
- `playerNameDisplay` is runtime/transient only and is stripped from SavedVariables on save.
- Load/save hardening emits diagnostics when legacy `original` / row `player`
  fields are detected.
- Import mode is not stored here; it is mirrored in `KRT_Options.srImportMode`.

## KRT_Warnings

Type: `array<WarningRecord>`

`WarningRecord` fields:
- `name` (string or number)
- `content` (string)

## KRT_Spammer

Type: `map<string, any>`

Known persisted keys:
- `Duration` (string)
- `Channels` (`array<number|string>`)
- `Name` (string or nil)
- `Tank` (string or nil)
- `TankClass` (string or nil)
- `Healer` (string or nil)
- `HealerClass` (string or nil)
- `Melee` (string or nil)
- `MeleeClass` (string or nil)
- `Ranged` (string or nil)
- `RangedClass` (string or nil)
- `Message` (string or nil)

Notes:
- Non-channel fields map directly from `KRTSpammer` edit-box suffix names.
- `Clear()` wipes all keys except `Channels` and restores `Duration`.

## KRT_Options

Type: `map<string, boolean|number|string|nil>`

Default keys (`Options.defaultValues`):
- `sortAscending` (boolean)
- `useRaidWarning` (boolean)
- `announceOnWin` (boolean)
- `announceOnHold` (boolean)
- `announceOnBank` (boolean)
- `announceOnDisenchant` (boolean)
- `lootWhispers` (boolean)
- `screenReminder` (boolean)
- `ignoreStacks` (boolean)
- `showTooltips` (boolean)
- `showLootCounterDuringMSRoll` (boolean)
- `minimapButton` (boolean)
- `countdownSimpleRaidMsg` (boolean)
- `countdownDuration` (number)
- `countdownRollsBlock` (boolean)
- `srImportMode` (number: `0` multi, `1` plus)

Additional persisted key used by minimap:
- `minimapPos` (number angle)

Runtime-only option state:
- `debug` is explicitly excluded from persistence.
