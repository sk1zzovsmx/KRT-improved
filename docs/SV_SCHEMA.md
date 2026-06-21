# SavedVariables Schema Inventory

This file inventories the SavedVariables keys and args currently read/written by runtime code.
Scope: `KRT_*` SavedVariables declared in `!KRT/!KRT.toc` and persisted in the
WoW SavedVariables file for the addon.
Current raid schema version: `5`.

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

Observed persisted attendance fields:
- `attendance[].playerNid` (required number)
- `attendance[].segments[].startTime` (required number)
- `attendance[].segments[].endTime` (optional number)
- `attendance[].segments[].subgroup` (optional number; group `1` can be omitted)
- `attendance[].segments[].online` (optional boolean; omitted/`nil` means online, `false` means offline)

Observed optional inspect fields:
- `inspect.startedAt`
- `inspect.completedAt`
- `inspect.mode`
- `inspect.players[playerNid]` compact final per-player snapshot

Only final inspect states are persisted: `ready`, `skipped`, `timeout`, and
`failed`. Runtime queue states `queued` and `pending` are intentionally absent
after `/reload`.

v5 storage policy:
- optional/default-only fields can be omitted during save compaction,
- runtime readers resolve defaults when fields are omitted.

v5 attendance ledger:
- attendance entries are keyed by stable `playerNid`, not player name,
- lower schema versions are stamped to the current version at the DB boundary.

Retired/transient fields stripped during normalization:
- `players[].count` (old LootCounter field; `countMS` is canonical)
- `loot[].looter` (old winner reference; `looterNid` is canonical)
- `bossKills[].attendanceMask` (old attendance representation; `attendance[]` is canonical)

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
- `playerNameDisplay` is runtime-only and is stripped from SavedVariables on save.
- Old `original` fields and reserve-row `player` fields are not part of the current saved shape.
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

Type: strict nested schema-2 table.

Canonical shape:
- `_schema = 2`
- `Master.sortAscending`, `Master.useRaidWarning`, `Master.screenReminder`,
  `Master.announceOnWin`, `Master.announceOnHold`, `Master.announceOnBank`,
  `Master.announceOnDisenchant`
- `Loot.lootWhispers`, `Loot.ignoreStacks`
- `Rolls.countdownDuration`, `Rolls.countdownSimpleRaidMsg`, `Rolls.countdownRollsBlock`
- `Reserves.softResWhisperAdds`, `Reserves.softResWhisperReplies`,
  `Reserves.srImportMode`, `Reserves.nameAliases`
- `Minimap.minimapButton`, `Minimap.minimapPos`
- `LootCounter.showLootCounterDuringMSRoll`
- `UI.showTooltips`

Unknown top-level namespaces are removed during `Options.EnsureLoaded()`. Unknown keys inside a
registered namespace are ignored by normal accessors and rejected by namespace setters.

Runtime-only option state:
- `debug` is explicitly excluded from persistence.
