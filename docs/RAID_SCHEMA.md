# Raid Schema Contract (`KRT_Raids`)

This document defines the canonical persisted shape of raid history records.
Current schema version: `3`.
Legacy sunset status: strict canonical reads are enabled; legacy payload keys are diagnostics-only and stripped.

## RaidRecord (`KRT_Raids[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `schemaVersion` | number | yes | `3` | Record schema version for normalization/validation. |
| `raidNid` | number | yes | auto | Stable raid identifier (not array index). |
| `realm` | string | no | `nil` | Realm name when the raid started. |
| `zone` | string | no | `nil` | Raid zone name. |
| `size` | number | no | `nil` | Expected raid size (`10` or `25`). |
| `difficulty` | number | no | `nil` | 3.3.5a raid difficulty code. |
| `startTime` | number | yes | `time()` | Session start (unix seconds). |
| `endTime` | number | no | `nil` | Session end (unix seconds). |
| `holder` | string | no | `nil` | Optional current loot holder (Master UI target). |
| `banker` | string | no | `nil` | Optional current banker target (Master UI target). |
| `disenchanter` | string | no | `nil` | Optional current disenchanter target (Master UI target). |
| `players` | table(array) | yes | `{}` | Canonical persisted player records. |
| `bossKills` | table(array) | yes | `{}` | Canonical boss kill records. |
| `loot` | table(array) | yes | `{}` | Canonical loot records. |
| `changes` | table(map) | yes | `{}` | Player -> spec change map for MS changes UI. |
| `nextPlayerNid` | number | yes | `1` | Next stable `playerNid` allocator value. |
| `nextBossNid` | number | yes | `1` | Next stable `bossNid` allocator value. |
| `nextLootNid` | number | yes | `1` | Next stable `lootNid` allocator value. |

## PlayerRecord (`raid.players[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `playerNid` | number | yes | auto | Stable player identifier inside raid. |
| `name` | string | yes | `""` | Player character name. |
| `rank` | number | no | `0` | Raid rank at capture time. |
| `subgroup` | number | no | `1` | Raid subgroup at capture time. |
| `class` | string | no | `"UNKNOWN"` | Class token. |
| `join` | number | no | `nil` | Join timestamp. |
| `leave` | number/nil | no | `nil` | Leave timestamp, `nil` when active. |
| `count` | number | yes | `0` | LootCounter value, canonical persisted data. |

## BossKillRecord (`raid.bossKills[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `bossNid` | number | yes | auto | Stable boss-kill identifier inside raid. |
| `name` | string | yes | `""` | Boss name (or `_TrashMob_`). |
| `difficulty` | number | no | `0` | Difficulty captured for the kill. |
| `mode` | string | no | `"n"` | Normal/heroic shorthand (`n`/`h`). |
| `players` | table(array) | no | `{}` | `playerNid` values present for that kill. |
| `time` | number | no | `nil` | Kill timestamp. |
| `hash` | string | no | `nil` | Sync hash for the kill row. |

## LootRecord (`raid.loot[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `lootNid` | number | yes | auto | Stable loot identifier inside raid. |
| `itemId` | number | no | `nil` | Item ID. |
| `itemName` | string | no | `nil` | Item display name. |
| `itemString` | string | no | `nil` | Raw item string. |
| `itemLink` | string | no | `nil` | Full item link. |
| `itemRarity` | number | no | `nil` | Item rarity (`0` omitted in v3 compaction). |
| `itemTexture` | string | no | `nil` | Icon texture path. |
| `itemCount` | number | no | `nil` | Stack count (`1` omitted in v3 compaction). |
| `looterNid` | number | no | `nil` | Winner/receiver `playerNid` (canonical winner reference). |
| `rollType` | number | no | `nil` | Roll type enum (`0` omitted in v3 compaction). |
| `rollValue` | number | no | `nil` | Roll value (`0` omitted in v3 compaction). |
| `rollSessionId` | string | no | `nil` | Optional roll-session identifier (`RS:*`). |
| `bossNid` | number | no | `nil` | Source boss id (`0` omitted in v3 compaction). |
| `time` | number | no | `nil` | Loot timestamp. |
| `source` | string | no | `nil` | Optional loot origin marker (for example `TRADE_ONLY`). |

### v3 Persistence Compaction

Schema v3 keeps runtime behavior unchanged but stores leaner SV payloads:
- optional/default-only fields may be omitted from persisted rows,
- readers must apply defaults at read time (already done by DB/query paths),
- canonical IDs (`playerNid`, `bossNid`, `lootNid`) remain the source of truth.
- optional role assignees (`holder`, `banker`, `disenchanter`) persist only when set.

### Legacy Sunset (Strict Mode)

- `loot[].looter` is legacy-only: it is no longer read for winner resolution and is stripped on normalize/save.
- `bossKills[].attendanceMask` is legacy-only and stripped on normalize/save.
- Schema remains `v3`; a bump to `v4` is deferred until a net structural simplification is required.

## ChangeRecord (`raid.changes[playerName] = spec`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| key `playerName` | string | yes | n/a | Canonical player name key in map. |
| value `spec` | string/nil | no | `nil` | Optional text annotation/spec. |

## Runtime caches (MUST NOT PERSIST)

Runtime-only data must stay under `raid._runtime` and must be stripped before SV save.
Save hardening runs through `Core.PrepareSavedVariablesForSave(...)`, which invokes raid normalization/compaction
and strips runtime caches before persistence.

Allowed runtime keys:
- `raid._runtime.playersByName`
- `raid._runtime.playerIdxByNid`
- `raid._runtime.bossIdxByNid`
- `raid._runtime.lootIdxByNid`
- `raid._runtime.bossByNid`
- `raid._runtime.lootByNid`

Legacy top-level runtime keys must not be persisted and are removed on normalize/strip:
- `raid._playersByName`
- `raid._playerIdxByNid`
- `raid._bossIdxByNid`
- `raid._lootIdxByNid`
