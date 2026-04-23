# PackMule — Design Spec

**Date:** 2026-04-21
**Status:** Approved for implementation planning
**Scope:** Rule-based auto-assignment of loot on Master Looter, inspired by Gargul's PackMule.

---

## 1. Goals & Non-Goals

### Goals

- Automate distribution of low-value and routinely-awarded items (trash greens → disenchanter, specific tokens → designated player) so the raid leader can focus on contested loot.
- Always show a human-in-the-loop preview before any auto-assignment executes.
- Integrate cleanly with KRT's existing Loot, Reserves, and Rolls services without duplicating responsibilities.

### Non-Goals (explicitly out of scope for v1)

- Auto-start of roll sessions via rule action (revisit later).
- Random-target or role/class-based assignment.
- Drag-to-reorder rules in UI (delete + re-add is enough for v1).
- Import/export of rule strings (Gargul-compatible format).
- Per-raid-team or per-character rule profiles (rules are global).
- Chat announcements as a rule action (existing `announceOnWin` covers award announcements).

---

## 2. Design decisions (from brainstorming)

| Key | Decision | Label |
|-----|----------|-------|
| Match criteria | Quality threshold + specific itemIDs only | **M2** |
| Actions | Assign to player / assign to disenchanter / skip | **A2** |
| Trigger mode | Auto-evaluate, preview popup, single-click confirm | **T2** |
| Rule ordering | Two classes: ItemID rules always beat Quality rules | **O2** |
| Reserves interaction | Reserves always win — PackMule skips reserved items | **R1** |

---

## 3. Architecture

### Module layout

```
!KRT/
├── Services/Loot/
│   ├── PackMule/
│   │   ├── Rules.lua       -- data model + CRUD (pure, no UI deps)
│   │   ├── Matcher.lua     -- pure: (item, rules) → action | nil
│   │   └── Service.lua     -- orchestrator: hooks, preview, execute
│   └── Service.lua         -- emits LootFetched post-FetchLoot (new hook)
├── Controllers/
│   └── PackMuleConfirm.lua -- controller for preview popup
├── UI/
│   └── PackMuleConfirm.xml -- preview popup frame
└── Widgets/
    └── Config.lua          -- new tab "PackMule" for rule editing
```

### Responsibilities

- **Rules.lua** — data access, validation, persistence. No Loot / no UI imports.
- **Matcher.lua** — pure functions. Zero side-effects. Testable standalone.
- **Service.lua (PackMule)** — wires Matcher into the loot flow, publishes events, executes `GiveMasterLoot`.
- **PackMuleConfirm** — UI only: reads matches from an event payload, renders popup, emits Confirm/Cancel.

### Internal events (new)

| Event | Payload | Publisher | Subscriber |
|-------|---------|-----------|------------|
| `LootFetched` | `{ source }` | Loot/Service | PackMule/Service |
| `PackMuleMatched` | `[{ slot, itemLink, action, target }]` | PackMule/Service | PackMuleConfirm |
| `PackMuleExecuted` | `[{ slot, target, status }]` | PackMule/Service | Logger |
| `PackMuleCancelled` | `{}` | PackMule/Service | — |

### TOC order (insert after Loot/Service.lua, before Reserves)

```
Services/Loot/PackMule/Rules.lua
Services/Loot/PackMule/Matcher.lua
Services/Loot/PackMule/Service.lua
Controllers/PackMuleConfirm.lua
```

`KRT.xml` must include the new `UI/PackMuleConfirm.xml`.

---

## 4. Data model

### Rule schemas

**ItemID rule:**

```lua
{
    id        = "<uuid-ish string>",
    kind      = "item",
    enabled   = true,
    itemId    = 38268,
    itemName  = "Mote of Fire",        -- cached at save time, for display
    action    = { type = "assign", target = "Pippo" },
    createdAt = 1730000000,
}
```

**Quality rule:**

```lua
{
    id        = "...",
    kind      = "quality",
    enabled   = true,
    qualityMax = 2,                     -- 0..5 (Poor..Legendary)
    action    = { type = "assign", target = "__disenchanter__" },
    createdAt = 1730000000,
}
```

### Action payloads

- `{ type = "assign", target = "<player-name>" }` — exact player name as returned by the roster.
- `{ type = "assign", target = "__disenchanter__" }` — sentinel resolved at runtime to `KRT_Options.disenchanter`.
- `{ type = "skip" }` — no-op; item left in the loot window.

### SavedVariable

```lua
KRT_PackMule = {
    version      = 1,
    enabled      = true,
    itemRules    = { ... },            -- ordered list of ItemID rules
    qualityRules = { ... },            -- ordered list of Quality rules
}
```

Two separate lists enforce **O2** (ItemID beats Quality) structurally.

Add `KRT_PackMule` to `!KRT.toc` `## SavedVariables:` line.

### Validation (at load, in `Rules.lua`)

- Drop rules where `itemId` is not a positive integer.
- Drop rules where `qualityMax` is outside `[0, 5]`.
- Drop rules where `action.type` is not in `{"assign", "skip"}`.
- Drop `assign` rules with empty `target`.
- If `KRT_PackMule` is corrupted (wrong type) → reset to default `{ version=1, enabled=true, itemRules={}, qualityRules={} }` and log a warning.

---

## 5. Matching engine

### Public API (`Matcher`)

```lua
-- Pure. No side-effects.
-- item  = { itemId, itemLink, quality, slot, locked, quantity }
-- rules = { enabled, itemRules, qualityRules }
-- return: action table | nil
function Matcher.Match(item, rules)
```

### Algorithm

1. If `rules.enabled == false` → return `nil`.
2. If `item.locked == true` → return `nil` (already allocated by Blizzard).
3. Phase 1 — ItemID rules, in order:
   - For each rule with `enabled == true`, if `rule.itemId == item.itemId` → return `rule.action`.
4. Phase 2 — Quality rules, in order:
   - For each rule with `enabled == true`, if `item.quality <= rule.qualityMax` → return `rule.action`.
5. Return `nil`.

First-match-wins inside each phase. Phase 1 always precedes Phase 2.

---

## 6. Orchestrator (`PackMule/Service`)

### Public API

```lua
function PackMule:EvaluateLoot()   -- called after LootFetched; builds pending matches
function PackMule:ExecuteMatches() -- called on user Confirm; calls GiveMasterLoot
function PackMule:CancelMatches()  -- called on user Cancel or timeout
```

### EvaluateLoot flow

1. If not master looter → abort silently.
2. Iterate loot slots:
   - Skip items that are reserved (check `KRT_Reserves` via `Services.Reserves`).
   - Skip items with an active roll session (check `Rolls.HasActiveSessionFor(itemId)`).
   - Skip items present in `IgnoredItems`.
   - Call `Matcher.Match(item, rules)`.
   - If action returned: append `{ slot, itemLink, action, target = resolve(action.target) }` to pending matches.
3. If pending matches non-empty → publish `PackMuleMatched` with the list.

### ExecuteMatches flow

1. For each **user-checked** match (state tracked by the popup controller):
   - If `action.type == "skip"` → no-op, record `status = "skipped"`.
   - Else resolve candidateIndex via `Loot:GetCandidateIndex(slot, target)`.
   - If candidateIndex missing → record `status = "ineligible"` and continue.
   - Call `GiveMasterLoot(slot, candidateIndex)` → record `status = "ok"`.
2. Publish `PackMuleExecuted` with full result list.
3. Clear pending matches state.

### CancelMatches flow

- Clear pending matches. Publish `PackMuleCancelled`. No item is touched.

### Target resolution

```lua
function PackMule:ResolveTarget(target)
    if target == "__disenchanter__" then
        return addon.options.disenchanter
    end
    return target
end
```

If the resolved target is empty or not a loot candidate, the match is still added to pending matches but flagged `unresolved = true`. The preview popup shows such rows disabled with a warning label.

---

## 7. UI

### Preview popup (`PackMuleConfirm`)

```
┌─ PackMule Preview ──────────────────────────┐
│ 2 rules matched:                            │
│ [✓] [Shadowmourne Frag] → Pippo             │
│ [✓] [Linen Cloth]       → Deeroy (DE)       │
│                                             │
│ [Confirm (2)]                    [Cancel]   │
└─────────────────────────────────────────────┘
```

Behaviour:

- Checkbox per row, default ON. Deselecting excludes that match from execution.
- `Confirm (N)` shows count of selected matches. Disabled when N = 0.
- `Cancel` dismisses without executing.
- Auto-cancel timeout: **30 seconds** of no interaction → behaves as Cancel.
- If the loot window closes externally before Confirm, popup dismisses and pending matches are cleared.
- Row with `unresolved = true` (disenchanter missing, target not in raid) is rendered in red text, checkbox disabled, tooltip explains why.

### Config tab (`Widgets/Config.lua`, new "PackMule" tab)

```
┌─ PackMule ────────────────────────────────┐
│ [x] Enable PackMule                       │
│                                           │
│ ── Item Rules ────────────────────────── │
│ ┌──────────────────────────────────────┐ │
│ │ ✓ [38268] Mote of Fire → Pippo  [X] │ │
│ └──────────────────────────────────────┘ │
│ [+ Add Item Rule]                         │
│                                           │
│ ── Quality Rules ─────────────────────── │
│ ┌──────────────────────────────────────┐ │
│ │ ✓ Quality ≤ Uncommon → DE        [X] │ │
│ └──────────────────────────────────────┘ │
│ [+ Add Quality Rule]                      │
└───────────────────────────────────────────┘
```

- `Enable PackMule` toggles `KRT_PackMule.enabled`.
- Row checkbox toggles `rule.enabled` (keeps the rule, skips it at match time).
- `[X]` removes the rule with confirmation.
- `+ Add Item Rule` opens a small dialog: itemID input (accepts pasted itemLink; parses itemId out of it), target dropdown (raid roster + "Disenchanter" + "Skip").
- `+ Add Quality Rule` opens a small dialog: quality dropdown (Poor..Epic), target dropdown.
- Reordering in v1: delete + re-add (drag-to-reorder deferred).

---

## 8. Integration points

### Hook — `Loot/Service.lua` emits `LootFetched`

Inside `FetchLoot()`, at the end of the successful path:

```lua
Bus:Publish(InternalEvents.LootFetched, { source = source })
```

`source` is the existing caller context string (`"LOOT_OPENED"`, `"LOOT_SLOT_CLEARED"`, etc.). PackMule subscribes and no-ops for certain sources (only `"LOOT_OPENED"` triggers a fresh evaluation; reruns on `LOOT_SLOT_CLEARED` are suppressed to avoid double-evaluation during multi-item distributions).

### Hook — Rolls existence check

`PackMule/Service` needs `Rolls.HasActiveSessionFor(itemId)`. If that method does not yet exist, add it as a small read-only method on `Services/Rolls/Service.lua` (returns `true` if any active session targets that itemId).

### Hook — Reserves check

Reuse `Services.Reserves.GetReserveCountForItem(itemId, itemName)` existing API. Positive count → skip.

### Hook — Logger

`PackMuleExecuted` listener in `Services/Logger/Actions.lua` logs a `PACKMULE_EXEC` action kind with per-item status. Reuses the existing logger persistence pipeline.

---

## 9. Error handling & edge cases

| Case | Behaviour |
|------|-----------|
| Not master looter | EvaluateLoot no-ops immediately. |
| PackMule disabled | No-op (enabled flag short-circuits). |
| No rules match | No popup, normal loot flow continues. |
| Target not in raid | Match flagged `unresolved`, shown disabled in preview. |
| Target offline / out of range | `GiveMasterLoot` silently fails; status `ineligible` in execution log. |
| `__disenchanter__` unresolved (option unset) | Match flagged `unresolved`, warning in debug log. |
| Item reserved | Skipped before Match is called (R1). |
| Roll already active on item | Skipped before Match is called. |
| Item in IgnoredItems | Skipped before Match is called. |
| Loot window closes before Confirm | Popup dismisses, matches cleared, `PackMuleCancelled` published. |
| Corrupted `KRT_PackMule` | Reset to default at load, warning logged. |
| Duplicate itemID rules | First (by list order) wins. UI badges duplicates with an icon. |
| Future addon upgrade | `version` field supports migrations if schema evolves. |

---

## 10. Testing plan

### Matcher — automated (standalone)

- `tests/PackMule_Matcher_test.lua` runnable with `lua5.1` (no WoW API dependencies).
- Scenarios:
  - No rules → nil
  - Only itemID rule that matches → action
  - Only itemID rule that does not match → nil
  - Only quality rule, item below threshold → action
  - Only quality rule, item above threshold → nil
  - Both kinds, itemID wins (O2)
  - `rules.enabled = false` → nil
  - `rule.enabled = false` → skipped
  - `item.locked = true` → nil

### Manual raid test plan

1. Single itemID rule → preview → Confirm → item correctly awarded.
2. Single quality rule → preview → Confirm → item goes to disenchanter.
3. Multiple matches, deselect one → only selected executes.
4. Cancel → no item moved.
5. Reserved item present → skipped from preview.
6. Active roll session on item → skipped from preview.
7. Target offline → row disabled, shown as unresolved.
8. Disenchanter option unset → quality-DE rule shown as unresolved.
9. Loot window closes mid-preview → popup dismisses silently.
10. Corrupted SavedVariable → `/reload` does not crash; default is restored.

### Debug mode

With `addon.hasDebug` enabled: per-item evaluation trace (matched rule id, or reason for skip) via `Diag.D.*`. New Diag keys (`LogPackMuleEval`, `LogPackMuleMatched`, `LogPackMuleSkipped`, `LogPackMuleExecuted`, `LogPackMuleCancelled`).

---

## 11. Open questions / future work

- **Import/export**: desirable for sharing rule sets between raid leaders. Candidate format: base64(JSON) using existing `Base64` module. Deferred.
- **Drag-to-reorder**: useful once users accumulate many item rules. Deferred.
- **Auto-start-roll action**: powerful but conflicts with manual roll flow. Requires careful design around concurrent-roll prevention. Deferred.
- **Role/class targets**: requires a role resolver over the roster (KRT does not currently expose one cleanly). Deferred.
- **Per-raid-team profiles**: add only if users ask.

---

## 12. Out-of-spec dependencies

- May need to add a small read-only method to Rolls service: `Rolls.HasActiveSessionFor(itemId) → bool`. Additive; no change to existing roll behaviour.
- `Loot:GetCandidateIndex` utility: if not already exposed as a public method, extract the logic currently used by `Master.lua:3337` (`GiveMasterLoot`) into `Services.Loot` with a stable public name.

Both are small, localised, and should be handled as prerequisite steps in the implementation plan.
