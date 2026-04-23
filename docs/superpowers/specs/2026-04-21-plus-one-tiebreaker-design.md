# Plus-one tie-breaker — Design Spec

- **Date**: 2026-04-21
- **Feature ID**: F1 (from Gargul-inspired backlog)
- **Sub-project of**: Gargul-inspired loot features integration into KRT
- **Status**: design approved, pending implementation plan

## 1. Goal and non-goals

### Goal

When two or more players tie on a roll (same effective roll value within the same bucket), resolve the tie automatically by favoring the player who has won fewer MS items, using a player-level MS loot count. Count scope is runtime-configurable: current raid only, last N raids, or all saved raids.

### Non-goals

- Does not replace or modify the existing tie-reroll flow. If the new criterion also ties, the existing reroll flow triggers unchanged.
- Does not change SR bucket resolution. SR continues to use its plus system.
- Does not introduce cross-raid loot aggregation UI (that is F2, a separate spec).
- Does not add PackMule-style auto-assignment rules (F4).
- Does not modify DB schema or add a cached aggregate field.

## 2. User-facing behavior

1. A new config panel "Plus-one tie-breaker" exposes: `enabled` (checkbox, default OFF), `scope` (dropdown: Current raid / Last N raids / All saved raids), `n` (slider 1–50, visible only when scope = Last N).
2. When the feature is OFF, KRT behavior is bit-for-bit identical to today.
3. When ON, during a roll resolution:
   - If two entries tie on roll value within a non-SR bucket, the one with the lower MS count (over the configured scope) wins.
   - The roll UI shows `(MS N)` next to players that belong to a tied group, so the tie-break is transparent.
   - When the tie-break decides a winner automatically, chat announces: `"{winner} wins the tie on {item} (MS: {winnerCount} vs {nextCount})"`.
   - If MS counts also tie, the existing tie-reroll flow starts as today.

## 3. Architecture

```
Widgets/Config.lua           → reads/writes addon.options.tiebreakerMSCount
Services/Rolls/Service.lua   → injects new ctx getters into Resolution
Services/Rolls/Resolution.lua→ consumes ctx, applies tie-break in comparator + UI hints
Services/Raid/Counts.lua     → new cross-raid read-only queries
Controllers/Master.lua       → emits U4 chat announce when tie-break resolves
Modules/C.lua                → new TIEBREAKER_SCOPE enum
Localization/localization.en → new L strings
```

No new files. No new services. No DB migration.

## 4. Decisions (resolved during brainstorm)

| Decision | Value | Source |
|---|---|---|
| Count field | `countMS` only, for any roll type | C2 |
| Scope | Runtime-configurable CURRENT / LAST_N / ALL | S4 |
| Buckets | Apply only to MS/OS/FREE, SR untouched | B1 |
| Default state | OFF, full config panel (`enabled`, `scope`, `n`) | D4 |
| UI visibility | Show MS count only on tied rows | U2 |
| Announcement | Chat announce on automatic tie-break resolution | U4 |
| Integration approach | In-comparator with on-demand batch query | Approach A |

## 5. API surface

### 5.1 New constant (`Modules/C.lua`)

```lua
C.TIEBREAKER_SCOPE = {
    CURRENT = "CURRENT",
    LAST_N  = "LAST_N",
    ALL     = "ALL",
}
```

### 5.2 New options shape (`addon.options`)

```lua
addon.options.tiebreakerMSCount = {
    enabled = false,                       -- default OFF
    scope   = C.TIEBREAKER_SCOPE.CURRENT,  -- default conservative
    n       = 5,                           -- used only when scope == LAST_N
}
```

At load time, `Init.lua` seeds missing fields with defaults without clobbering user values.

### 5.3 New methods on `addon.Services.Raid` (extends `Services/Raid/Counts.lua`)

```lua
--- Read-only. Returns MS count for the given player across the requested scope.
--- @param name string character name
--- @param opts { scope: string, n: integer? }
--- @return integer msCount (0 when not found or on malformed input)
function module:GetPlayerMSCount(name, opts)

--- Read-only batch. Returns { [name] = msCount } for all listed names.
--- Single pass over KRT_Raids.
--- @param names string[]
--- @param opts  { scope: string, n: integer? }
--- @param out   table? optional reusable output table (wiped internally)
--- @return table map
function module:GetMSCountsForNames(names, opts, out)
```

Behavior:
- `CURRENT`: reads `currentRaid.players[].countMS`. Reuses `GetPlayerCount` where practical.
- `LAST_N`: iterates `KRT_Raids` newest-first, sums `countMS` for the first `n` raids that contain the player. Stops at list end if fewer raids exist.
- `ALL`: sums across every saved raid.
- Deduplication within a single raid follows the existing `GetLootCounterRows` convention: if a name appears multiple times in `raid.players`, only the latest occurrence counts (iterating from `#players` to `1` with a `seenByName` set).
- Returns 0 / `{}` on nil inputs; never raises.

### 5.4 New ctx fields in `Services/Rolls/Service.lua`

`ctx` passed to `Resolution.*` gains:

```lua
ctx.isTiebreakerByMSCountEnabled = function() return addon.options.tiebreakerMSCount.enabled == true end
ctx.getTiebreakerMSCountOpts     = function() return { scope = ..., n = ... } end  -- validated
ctx.getMSCountsForNames          = function(names) return Services.Raid:GetMSCountsForNames(names, ctx.getTiebreakerMSCountOpts()) end
```

### 5.5 New L strings

```lua
L.CfgTiebreakerHeader
L.CfgTiebreakerEnabled
L.CfgTiebreakerEnabledTip
L.CfgTiebreakerScopeLabel
L.CfgTiebreakerScopeCurrent
L.CfgTiebreakerScopeLastN
L.CfgTiebreakerScopeAll
L.CfgTiebreakerNLabel
L.ChatTiebreakResolved   -- "%s wins the tie on %s (MS: %d vs %d)"
L.RollRowMSCountFmt      -- "(MS %d)"
```

### 5.6 Extended `resolution` struct (from `BuildResolution`)

Existing fields (`autoWinners`, `tiedNames`, `requiresManualResolution`, `cutoff`, `topRollName`) remain unchanged. New fields, populated only when the feature is enabled and at least one roll-value tie was broken by the new criterion:

```lua
resolution.resolvedByTiebreaker    = true      -- boolean
resolution.tiebreakerWinnerName    = "Tizio"   -- string
resolution.tiebreakerWinnerCount   = 0         -- integer
resolution.tiebreakerRunnerUpCount = 2         -- integer (second-best among the roll-tied group)
```

When the feature is disabled or no roll-value tie was broken, the fields are absent.

### 5.7 Diagnostic log

```lua
Diag.D.LogRollsTiebreakerApplied  -- "[Rolls] Tiebreaker applied: scope=%s n=%d, tied={%s}, counts={%s}, resolved=%s"
```

Emitted once per resolution when the feature is enabled and at least one tie group exists, only under `addon.hasDebug`.

## 6. Data flow

1. `Rolls` service builds `ctx` with the 3 new getters.
2. `Resolution.BuildResolvedEntries(ctx, itemId, rollType)`:
   - Reads `tiebreakerEnabled` flag.
   - If enabled, collects the set of selectable response names and calls `ctx.getMSCountsForNames(names)` once.
   - Populates each entry with `tiebreakerCount` and `tiebreakerApplies = tiebreakerEnabled and bucket ~= "SR"`.
3. Comparator `compareResolvedEntries`:
   - Preserves existing order: bucketPriority → (SR) plus → roll value.
   - If both entries have `tiebreakerApplies == true` and counts differ → lower wins.
   - Otherwise falls back to alphabetical name as today.
4. `areResolvedEntriesTied` mirrors the comparator: two entries are not tied if `tiebreakerApplies` and counts differ.
5. `BuildRowCounterText` (extended to receive the entry, not just the response): when the row belongs to a tie group and the feature is enabled and bucket is not SR, appends `L.RollRowMSCountFmt:format(count)`.
6. To enable U4 (chat announce when tie-break resolves), `Resolution.BuildResolution` is extended to populate new fields:
   - `resolution.resolvedByTiebreaker` — boolean, true when at least one roll-value tie at or crossing the cutoff was broken by the new criterion (rather than by alphabetical fallback or manual resolution).
   - `resolution.tiebreakerWinnerName` — winner's name in that case.
   - `resolution.tiebreakerWinnerCount` — winner's MS count.
   - `resolution.tiebreakerRunnerUpCount` — second-best MS count among the roll-tied group (for the "vs" argument in the announce string).

   Detection logic inside `BuildResolution`: before applying the new comparator's tie-break, group entries by `(bucketPriority, bucket, plus-when-SR, roll)`; any group of size > 1 is a "roll-tied group". After sort, if the top-sorted entry of a roll-tied group won and the group's members now differ on `tiebreakerCount`, set the fields above.

7. `Controllers/Master` checks `resolution.resolvedByTiebreaker` after resolution and, when true, emits `L.ChatTiebreakResolved:format(winnerName, itemLink, winnerCount, runnerUpCount)` via the same announce channel used for `announceOnWin`.

## 7. Error handling and edge cases

| # | Case | Behavior |
|---|---|---|
| 1 | Feature ON, no saved raids | All counts = 0 → alphabetical fallback. No crash. |
| 2 | Player rename / server xfer | Not merged. Treated as distinct identities. Documented as limitation in the tooltip. |
| 3 | Player absent from all saved raids | Count = 0, favored in tie-break (semantically: new player, no prior wins). |
| 4 | `scope = LAST_N` with `n > raid count` | Iterates all available; no error. |
| 5 | Called outside any raid context | `CURRENT` returns 0; no crash. |
| 6 | Tie-break resolves → `requiresManualResolution = false` → award flows normally, no reroll. |
| 7 | Tie-break does not resolve (counts also tie) → `requiresManualResolution = true` → existing reroll flow runs unchanged. |
| 8 | Config toggle flipped mid-session | Next `BuildResolvedEntries` call applies the new state. No stale cache. |
| 9 | 3+ way tie resolved to single winner | Chat announce uses winner's count vs next-best count among the tied group. |
| 10 | Malformed options (corrupt SavedVariable) | Validator falls back to `CURRENT` / `n=5` / `enabled=false`; logs debug. |
| 11 | `KRT_Raids` non-table | Reuses existing `Core.EnsureRaidById` / `Core.EnsureRaidSchema` guards; returns 0 / `{}`. |

## 8. Performance

- One batch query per resolution (not per comparator call).
- `CURRENT` scope: O(1) effective (reads existing in-memory struct).
- `ALL` scope with 500 raids × 40 players: ~20k iterations, <2ms on target hardware.
- `GetMSCountsForNames` builds an `O(1)` name lookup set upfront; inner loop consults it, no nested `ipairs(names)`.

No caching is introduced in F1. If F2's larger workloads demand it, a memoized layer can be added without changing F1's public API.

## 9. Testing

1. **Static**: luacheck and stylua clean. No new globals introduced.
2. **Unit** (`tests/unit/`): `GetPlayerMSCount` and `GetMSCountsForNames` with stubbed `KRT_Raids`; `compareResolvedEntries` table-driven covering tie/no-tie × feature on/off × SR/non-SR.
3. **Regression invariant**: with `enabled=false`, comparator output is bit-for-bit identical to current.
4. **Manual in-game checklist** (see Section 11 below).
5. **Diagnostic log** verified to emit once per resolution under `/krt debug on`.

## 10. Acceptance criteria

- Feature OFF → no behavior change, no new strings visible, no log noise.
- Feature ON → described resolution logic applied consistently across MS, OS, FREE rolls.
- Config panel persists across `/reload` and `/logout`.
- No new DB migration; `KRT_Raids` and `KRT_Players` schemas unchanged.
- Chat announce line formatted correctly for binary and n-way ties.
- Existing tie-reroll flow reachable whenever MS counts also tie.

## 11. Manual verification checklist

1. Default load: feature OFF, panel hidden controls disabled, behavior unchanged.
2. Enable + `CURRENT`: stage two tied rolls with different `countMS`, confirm correct winner, chat announce fires.
3. Enable + `LAST_N=3`: confirm raids older than the third newest are excluded.
4. Enable + `ALL`: confirm sum across multiple saved raids.
5. Toggle mid-session: next roll reflects new state.
6. SR tie → feature does not apply, current SR behavior intact.
7. 3-way tie resolved automatically → announce uses winner vs second-best counts.
8. 3-way tie with all equal counts → existing reroll flow triggers.
9. Run outside any raid → no crash, counts = 0.
10. Corrupt `KRT_Options.tiebreakerMSCount` (manual edit) → validator fallback, no error.

## 12. Out of scope for this spec

- Cross-raid award history viewer (F2 — separate spec after F1 ships).
- Trade verification enhancements (F3).
- PackMule rules (F4).
- MS/OS unified roll session semantics (already done in KRT).
- Tie auto-reroll full-auto trigger (already implemented as click-to-reroll).
