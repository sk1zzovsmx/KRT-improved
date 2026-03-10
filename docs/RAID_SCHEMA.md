# Raid Schema Contract (`KRT_Raids`)

This document defines the canonical persisted shape of raid history records.
Current schema version: `2`.

## RaidRecord (`KRT_Raids[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `schemaVersion` | number | yes | `2` | Record schema version for migrations. |
| `raidNid` | number | yes | auto | Stable raid identifier (not array index). |
| `realm` | string | no | `nil` | Realm name when the raid started. |
| `zone` | string | no | `nil` | Raid zone name. |
| `size` | number | no | `nil` | Expected raid size (`10` or `25`). |
| `difficulty` | number | no | `nil` | 3.3.5a raid difficulty code. |
| `startTime` | number | yes | `time()` | Session start (unix seconds). |
| `endTime` | number | no | `nil` | Session end (unix seconds). |
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
| `itemRarity` | number | no | `0` | Item rarity. |
| `itemTexture` | string | no | `nil` | Icon texture path. |
| `itemCount` | number | no | `1` | Stack count for the award. |
| `looterNid` | number | no | `nil` | Winner/receiver `playerNid`. |
| `rollType` | number | no | `0` | Roll type enum value. |
| `rollValue` | number | no | `0` | Roll value or manual marker value. |
| `bossNid` | number | no | `0` | Source boss stable id (`0` allowed for unknown). |
| `time` | number | no | `nil` | Loot timestamp. |

## ChangeRecord (`raid.changes[name] = spec`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| key `name` | string | yes | n/a | Player name key in map. |
| value `spec` | string/nil | no | `nil` | Optional text annotation/spec. |

## Runtime caches (MUST NOT PERSIST)

Runtime-only data must stay under `raid._runtime` and must be stripped before SV save.

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
