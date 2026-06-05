# Passive Group Loot RollId-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce passive Group Loot spike risk by making native `rollId` sessions the primary item/session identity and reusing one parsed loot context through the hot path.

**Architecture:** `Services/Loot/PassiveGroupLoot.lua` owns transient roll sessions and returns structured parse context. `Init.lua` forwards that context into `Services/Loot/Service.lua`, and `Service.lua` consumes it to skip redundant winner parsing and ambiguous item matching while retaining the existing fallback path.

**Tech Stack:** WoW 3.3.5a Lua 5.1, native loot roll APIs (`START_LOOT_ROLL`, `GetLootRollItemLink`, `GetLootRollItemInfo`), KRT Bus and service modules, Busted release stabilization tests.

---

### Task 1: Preserve and Complete Structured Passive Context

**Files:**
- Modify: `!KRT/Services/Loot/PassiveGroupLoot.lua`
- Modify: `!KRT/Services/Loot/Service.lua`
- Modify: `!KRT/Init.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add failing tests for context forwarding**

Add tests near the existing `CHAT_MSG_LOOT` and passive group-loot tests that assert:

```lua
local observedContext
local loot = {
    ObserveGroupLootMessage = function(_, msg)
        return "winner", { kind = "winner", msg = msg, itemLink = "item-link" }
    end,
    AddLoot = function(_, msg, rollType, rollValue, parsed)
        observedContext = parsed
    end,
}
h.services.Loot = loot
h.addon:CHAT_MSG_LOOT("winner-loot")
assertEqual(observedContext.kind, "winner", "expected parsed passive context to reach AddLoot")
```

- [ ] **Step 2: Run the focused test and confirm failure or current coverage gap**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```

Expected before the implementation is complete: failure around missing forwarded context or no test coverage for it.

- [ ] **Step 3: Ensure `ObserveGroupLootMessage` returns `(observedType, parsedContext)`**

Keep `AddGroupLootMessage` backward-compatible by returning only `observedType`. Add or preserve:

```lua
function PassiveGroupLoot.AddGroupLootMessage(owner, msg)
    local observedType = PassiveGroupLoot.ObserveGroupLootMessage(owner, msg)
    return observedType
end
```

- [ ] **Step 4: Forward context through `Init.lua`**

Use:

```lua
local raidService, observedType, parsedLoot = observePassiveLootMessage(msg)
lootService:AddLoot(msg, nil, nil, parsedLoot)
```

in both `CHAT_MSG_LOOT` and winner handling in `CHAT_MSG_SYSTEM`.

- [ ] **Step 5: Consume parsed context in `Loot:AddLoot`**

Use `parsedGroupLoot` in `parseLootChatMessage` for winner fallback and in `isPassiveWinnerMessage` so the service does not reparse the same winner.

### Task 2: Make RollId Sessions Richer and Safer

**Files:**
- Modify: `!KRT/Services/Loot/PassiveGroupLoot.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add failing tests for roll metadata**

Add assertions that `AddPassiveLootRoll(rollId, rollTime)` stores `rollId`, `sessionId`, `itemLink`, `itemKey`, `startedAt`, `expiresAt`, and metadata from `GetLootRollItemInfo` when present.

- [ ] **Step 2: Add session metadata in `AddPassiveLootRoll`**

When creating or refreshing an entry, set:

```lua
entry.startedAt = entry.startedAt or GetTime()
entry.expiresAt = expiresAt
entry.itemName = itemName
entry.itemRarity = itemRarity
entry.itemTexture = itemTexture
```

Use `GetLootRollItemInfo(rollId)` only when available.

- [ ] **Step 3: Keep duplicate items separated**

Preserve `state.byRollId[rollId]` as authoritative and keep `state.byItemKey[itemKey]` as a list. `GetPassiveLootRollEntry(itemLink)` must keep returning nil when more than one active session matches the same item.

### Task 3: Attach Session Details to Parsed Context

**Files:**
- Modify: `!KRT/Services/Loot/PassiveGroupLoot.lua`
- Modify: `!KRT/Services/Loot/Service.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add tests for context enrichment**

For a winner message after `START_LOOT_ROLL`, assert the returned parsed context includes the matching `sessionId`, `rollId`, `itemKey`, and `bossNid`.

- [ ] **Step 2: Add helper to resolve session for parsed messages**

Resolve by `rollId` first:

```lua
local entry = PassiveGroupLoot.GetPassiveLootRollEntryByRollId(rollId)
    or PassiveGroupLoot.GetPassiveLootRollEntry(itemLink)
```

Do not guess when `GetPassiveLootRollEntry(itemLink)` returns nil because duplicate active sessions exist.

- [ ] **Step 3: Enrich `buildParsedGroupLootResult`**

Include session fields when a session is found:

```lua
sessionId = entry and entry.sessionId or nil,
itemKey = entry and entry.itemKey or PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink),
bossNid = entry and entry.bossNid or nil,
isPassiveWinner = kind == "winner",
```

- [ ] **Step 4: Prefer enriched values in `Loot:AddLoot`**

If `parsedGroupLoot.kind == "winner"` and it matches `msg`, pass its `sessionId` into roll outcome resolution or prefer it before item-only lookup.

### Task 4: Verify and Document

**Files:**
- Modify: `!KRT/CHANGELOG.md`
- Test: repository checks

- [ ] **Step 1: Add a concise changelog bullet**

Under `## Unreleased`, add a performance bullet describing that passive Group Loot now reuses native roll sessions to reduce repeated parsing during loot bursts.

- [ ] **Step 2: Run focused tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```

Expected: PASS.

- [ ] **Step 3: Run static checks**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check layering
```

Expected: both pass.

- [ ] **Step 4: Review dirty worktree carefully**

Run:

```powershell
git diff -- !KRT/Services/Loot/PassiveGroupLoot.lua !KRT/Services/Loot/Service.lua !KRT/Init.lua tests/release_stabilization_spec.lua !KRT/CHANGELOG.md
```

Expected: only scoped changes for rollId-first passive Group Loot and tests.

