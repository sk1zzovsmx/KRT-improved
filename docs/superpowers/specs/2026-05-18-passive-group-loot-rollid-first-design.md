# KRT Passive Group Loot RollId-First - Design

**Date:** 2026-05-18
**Approach:** Use native loot-roll IDs as the primary temporary session key for passive Group Loot.

## Goals

1. Reduce CPU work in Group Loot and Need Before Greed bursts by avoiding repeated chat parsing.
2. Treat `START_LOOT_ROLL` and native `rollId` state as the primary source for item/session identity.
3. Keep chat parsing focused on player choice, roll result, winner, and receipt messages.
4. Preserve current passive logging behavior, low-value filtering, pending-award matching, and loot-counter updates.
5. Keep the implementation local to KRT services; do not add runtime dependencies or Ace libraries.
6. Add regression coverage for duplicate items, late winner messages, and filtered passive loot.

## Non-Goals

1. Do not introduce a third-party group-loot parser library.
2. Do not change user-visible loot rules, auto-loot suggestions, or award behavior.
3. Do not require Master Looter mode for passive Group Loot observation.
4. Do not persist roll sessions in SavedVariables.
5. Do not rewrite the complete loot service or Logger refresh architecture in this stage.

## Problem

KRT currently observes passive Group Loot by parsing chat messages in `Services/Loot/PassiveGroupLoot.lua`.
`CHAT_MSG_LOOT` first calls `Loot:AddGroupLootMessage(msg)`, then may call `Loot:AddLoot(msg)`.
The winner path can parse the same message again inside `parseLootChatMessage()` and
`PassiveGroupLoot.IsPassiveLootWinnerMessage(msg)`.

This is fragile and expensive during bursts because chat messages are used both as event classification and
as item/session identity. WoW already provides a better key: `START_LOOT_ROLL(rollId, rollTime)`.

## Proposed Model

`PassiveGroupLoot.AddPassiveLootRoll(owner, rollId, rollTime)` creates or updates a roll session keyed by
native `rollId`.

Session shape:

```lua
{
    rollId = 123,
    sessionId = "GL:12",
    itemLink = "|cffa335ee|Hitem:...|h[Item]|h|r",
    itemKey = "item:...",
    itemName = "Item",
    itemRarity = 4,
    itemTexture = "Interface\\Icons\\...",
    startedAt = 12345.6,
    expiresAt = 12390.6,
    bossNid = 42,
    choicesByPlayer = {},
    rollsByPlayer = {},
    winner = nil,
}
```

Required indexes:

- `state.byRollId[rollId] = session`
- `state.bySessionId[sessionId] = session`
- `state.byItemKey[itemKey] = { session, ... }`

`itemKey` remains a fallback for chat messages that do not expose a reliable `rollId`.

## Event Flow

1. `START_LOOT_ROLL(rollId, rollTime)`
   - Read `GetLootRollItemLink(rollId)`.
   - Read `GetLootRollItemInfo(rollId)` when available for cheap item metadata.
   - Create or refresh the session expiry from `rollTime` plus the existing grace window.
   - Capture boss context once for the session.

2. `CHAT_MSG_LOOT` and `CHAT_MSG_SYSTEM`
   - Parse the message once through a new internal classifier.
   - Resolve the matching session by `rollId` when present, otherwise by active `itemKey`.
   - Update pending awards, choices, rolls, or winner state from the parsed message.
   - Return both the observed kind and a structured passive context.

3. `Loot:AddLoot(msg, rollType, rollValue, passiveContext)`
   - If `passiveContext` is present, prefer its `itemLink`, `rollType`, `rollValue`, `sessionId`,
     `bossNid`, and winner flag.
   - Skip redundant `PassiveGroupLoot.ParseGroupLootWinner(msg)` and
     `PassiveGroupLoot.IsPassiveLootWinnerMessage(msg)` calls.
   - Keep the current fallback parser for messages that cannot be matched to a session.

## Internal Contracts

`PassiveGroupLoot.AddGroupLootMessage(owner, msg)` should return:

```lua
return "winner", {
    kind = "winner",
    rollId = 123,
    sessionId = "GL:12",
    itemLink = "...",
    itemKey = "item:...",
    playerName = "Player",
    rollType = rollTypes.GREED,
    rollValue = 87,
    bossNid = 42,
    isPassiveWinner = true,
}
```

For compatibility while the refactor lands, callers should accept both old and new return forms:

```lua
local observedType, passiveContext = lootService:AddGroupLootMessage(msg)
```

`observedType` remains `"selection"`, `"winner"`, or nil.

## Fallback Rules

1. If no roll session exists, use the existing chat parsing path.
2. If multiple active sessions have the same `itemKey`, do not guess unless a `rollId` is available.
3. If a winner arrives after the session expires, allow the existing pending-award TTL to match it only when
   the item/player pair is unique.
4. If the item is filtered as low-value passive loot, consume the matching session/pending state and do not log it.
5. If `GetLootRollItemInfo` is unavailable or incomplete, continue with `GetLootRollItemLink` and `GetItemInfo`.

## Duplicate Item Policy

Two simultaneous Group Loot rolls for the same item must stay separate. `rollId` is authoritative.
`itemKey` is only a fallback when there is exactly one active session for that item.

This prevents the current ambiguous case where matching by item alone can merge or misattribute duplicate
rolls in the same burst.

## Performance Expectations

The change should reduce hot-path work by:

- parsing each relevant chat message once;
- avoiding winner reparse inside `AddLoot`;
- avoiding repeated item/session lookup by item link when `rollId` is known;
- capturing passive roll boss context once per `START_LOOT_ROLL` session;
- reducing duplicate pending-award upgrades for the same message.

This stage does not coalesce `RaidLootUpdate` or incrementally update raid runtime indexes. Those are follow-up
performance tasks if profiling still shows spikes after the parser/session change.

## Test Plan

Add or extend Lua tests for:

1. `START_LOOT_ROLL` creates a session with `rollId`, `itemLink`, `itemKey`, and `sessionId`.
2. Repeated `START_LOOT_ROLL` for the same `rollId` refreshes the same session.
3. Two simultaneous rolls for the same item get distinct sessions.
4. Selection chat attaches to the correct `rollId` session when possible.
5. Winner chat returns a passive context consumed by `Loot:AddLoot`.
6. `Loot:AddLoot` with passive context skips redundant winner parsing.
7. Filtered green/gem/recipe passive loot consumes session state without logging.
8. Late winner fallback still works for unique item/player pending awards.
9. `RaidLootUpdate` fires once per logged loot entry.

Run focused loot/roll regression tests after implementation and run the standard Lua syntax/layering checks.

## Implementation Scope

Primary files:

- `!KRT/Services/Loot/PassiveGroupLoot.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Init.lua`
- `tests/release_stabilization_spec.lua` or a focused passive group-loot spec

Optional docs:

- `!KRT/CHANGELOG.md` for user-visible performance behavior.

