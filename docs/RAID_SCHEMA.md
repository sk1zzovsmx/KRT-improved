# Raid Schema Contract (`KRT_Raids`)

This document defines the canonical persisted shape of raid history records.
Current schema version: `5`.
Strict mode status: current-schema reads are enabled; retired payload keys are stripped.

## RaidRecord (`KRT_Raids[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `schemaVersion` | number | yes | `5` | Record schema version for normalization/validation. |
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
| `attendance` | table(array) | yes | `{}` | Canonical per-player attendance segments keyed by `playerNid`. |
| `inspect` | table(map) | no | `nil` | Optional raid-start inspect snapshots keyed by `playerNid`. |
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
| `countMS` | number | no | `0` | Main-spec LootCounter value. |
| `countOs` | number | no | `0` | Off-spec LootCounter value. |
| `countFree` | number | no | `0` | Free-roll LootCounter value. |
| `countSR` | number | no | `0` | SoftRes LootCounter value. |

## AttendanceRecord (`raid.attendance[i]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `playerNid` | number | yes | n/a | Stable player identifier inside raid. |
| `segments` | table(array) | yes | `{}` | Attendance segments for this player. |

## AttendanceSegment (`raid.attendance[i].segments[j]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `startTime` | number | yes | n/a | Segment start timestamp. |
| `endTime` | number/nil | no | `nil` | Segment end timestamp, `nil` when still active. |
| `subgroup` | number | no | `nil` | Raid subgroup when not the default group `1`. |
| `online` | boolean | no | `nil` | `false` means offline; omitted/`nil` means online. |

## EquipInspectSnapshot (`raid.inspect`)

`raid.inspect` is optional. Old raids may omit it.
`raid.inspect` remains the persisted key for compatibility. `EquipInspect`
owns equipment/iLvl capture; `SpecInspect` owns talent/spec deduction and may
provide copied active and secondary spec metadata inside each persisted
equipment snapshot.

Persisted root fields:
- `startedAt` (optional number)
- `completedAt` (optional number)
- `mode` (optional string)

Persisted player snapshot fields under `players[playerNid]`:
- `playerNid`
- `name`
- `guid`
- `class`
- `status`
- `reason`
- `inspectedAt`
- `avgIlvl`
- `specName`
- `specIcon`
- `mainTalentTree`
- `secondarySpecName`
- `secondarySpecIcon`
- `activeTalentGroup`
- `numTalentGroups`
- `secondaryTalentGroup`
- `secondaryMainTalentTree`
- `talentSnapshot`

Persisted item fields under `players[playerNid].items[slotId]`:
- `slot`
- `itemId`
- `itemLink`
- `texture`
- `quality`
- `ilvl`
- `enchantId`
- `gems`

Only final inspect states persist: `ready`, `skipped`, `timeout`, and `failed`.
Runtime states `queued` and `pending` must not persist. Inspect snapshots are
not included in DBSyncer or Logger export payloads in this phase.

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
| `source` | string | no | `nil` | Static provenance marker, for example `LootSources`, on synthetic source rows. |
| `sourceKind` | string | no | `nil` | Static source kind (`boss`, `trash`, `shared`, or `object`) when the row is not a real boss kill. |
| `sourceNpcId` | number | no | `nil` | NPC ID used by static source rows when available. |
| `sourceKey` | string | no | `nil` | Stable static dataset source key used to distinguish same-name raid/source records. |

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
| `lootSource` | table | no | `nil` | Optional structured source provenance copied from the live boss context or static loot-source resolver. |

## LootSourceRecord (`raid.loot[i].lootSource`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `kind` | string | no | `nil` | Source kind (`boss`, `trash`, `shared`, or `object`). |
| `bossNid` | number | no | `nil` | Boss/source row associated with this loot record. |
| `sourceNpcId` | number | no | `nil` | Source NPC ID when known; shared static rows store `0`. |
| `sourceName` | string | no | `nil` | Display source label. Shared static rows use `Shared`. |
| `sourceKey` | string | no | `nil` | Stable static dataset source key, including shared candidate keys for shared loot. |
| `candidates` | table(array) | no | `nil` | Shared-only compact candidate list for tooltip display. |
| `openedAt` | number | no | `nil` | LOOT_OPENED timestamp when captured from a loot-window source. |
| `snapshotId` | number | no | `nil` | Loot-window snapshot identifier when available. |

## LootSourceCandidate (`raid.loot[i].lootSource.candidates[j]`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| `name` | string | yes | n/a | Candidate boss/source display name. |
| `kind` | string | no | `boss` | Candidate source kind. |
| `npcId` | number | no | `nil` | Candidate NPC ID when known. |
| `sourceKey` | string | no | `nil` | Stable candidate source key used by runtime/UI metadata. |

### v5 Persistence Compaction

Schema v5 stores lean SV payloads:
- optional/default-only fields may be omitted from persisted rows,
- readers must apply defaults at read time (already done by DB/query paths),
- canonical IDs (`playerNid`, `bossNid`, `lootNid`) remain the source of truth.
- optional role assignees (`holder`, `banker`, `disenchanter`) persist only when set.
- attendance `online=true` is represented by omitted `online`; explicit `online=false` is persisted.
- zero LootCounter values may be omitted from persisted player rows and resolve to `0` at load time.

### Attendance Ledger

`raid.attendance` is the canonical per-player attendance ledger.
It is keyed by `playerNid`, not by player name, and stores join/leave/online/subgroup changes as segments.

### Retired Fields (Strict Mode)

- `players[].count` is not read; `countMS` is the canonical MS counter.
- `loot[].looter` is not read for winner resolution and is stripped on normalize/save.
- `bossKills[].attendanceMask` is stripped on normalize/save.

## ChangeRecord (`raid.changes[playerName] = spec`)

| Field | Type | Req | Default | Notes |
| --- | --- | --- | --- | --- |
| key `playerName` | string | yes | n/a | Canonical player name key in map. |
| value `spec` | string/nil | no | `nil` | Optional text annotation/spec. |

## Runtime caches (MUST NOT PERSIST)

Runtime-only data must stay under `raid._runtime` and must be stripped before SV save.
Save hardening runs through `Database.PrepareSavedVariablesForSave(...)`, which invokes raid normalization/compaction
and strips runtime caches before persistence.

Allowed runtime keys:
- `raid._runtime.playersByName`
- `raid._runtime.playerIdxByNid`
- `raid._runtime.bossIdxByNid`
- `raid._runtime.lootIdxByNid`
- `raid._runtime.bossByNid`
- `raid._runtime.lootByNid`

Retired root runtime cache keys must not be persisted and are removed on normalize/strip:
- `raid._playersByName`
- `raid._playerIdxByNid`
- `raid._bossIdxByNid`
- `raid._lootIdxByNid`
