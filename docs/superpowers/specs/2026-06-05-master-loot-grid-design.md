# KRT Master Loot Grid Design

## Context

KRT should replace dropdown-based player selection in the Master controller with a
dedicated Blizzard-style grid built from KRT requirements and the Wrath 3.3.5a
FrameXML/API behavior.

The implementation must live inside `!KRT` and must preserve KRT's existing
Master Loot pipeline, especially validation, pending awards, logging, announce
messages, and SavedVariables contracts.

## Goals

- Replace the Blizzard Master Loot candidate dropdown with a dynamic KRT grid.
- Replace Hold, Bank, and DE target dropdowns with the same grid-style picker.
- Keep a maximum of 5 columns and no ScrollFrame.
- Resize the frame dynamically based on player count.
- Preserve Blizzard-style confirmation for items at or above the Master Loot
  quality threshold.
- Keep all real loot assignment inside KRT's `assignItem` flow.

## Non-Goals

- Do not create a second addon folder for this feature.
- Do not call `GiveMasterLoot` directly from the grid click handler.
- Do not change SavedVariables shape.
- Do not introduce Ace dependencies.
- Do not add XML scripts or XML event handlers.

## Approach

Use a KRT-specific widget for the player grid. The widget should be controlled by
`Controllers/Master.lua` and receive callbacks for the two supported modes:

- Award mode: shows current Master Loot candidates and awards the selected item.
- Target mode: shows raid or party players and stores a Hold, Bank, or DE target.

The widget may be implemented as `!KRT/Widgets/MasterLootGrid.lua` if keeping it
inside `Controllers/Master.lua` would make the controller harder to maintain. If
a separate widget file is added, it must be listed in `!KRT/!KRT.toc` before the
Master controller needs to call it, and `docs/TREE.md` must stay aligned.

## Award Mode

Award mode opens when the Blizzard Master Loot candidate dropdown would normally
open. It should close any open dropdown menus, collect current Master Loot
candidates, position near the LootFrame selected item when possible, and show the
grid.

Each grid entry must retain the real candidate index from `GetMasterLootCandidate`.
That index may be used for display diagnostics, but the final award should still
go through KRT's `assignItem(itemLink, playerName, rollTypes.MANUAL, 0)`.

Click behavior:

1. Resolve the current selected loot item and candidate player.
2. If item quality is at or above `MASTER_LOOT_THREHOLD`, show a KRT-owned
   confirmation popup that mirrors Blizzard confirmation behavior.
3. On confirmation, call the KRT award flow.
4. If item quality is below threshold, call the KRT award flow immediately.
5. Hide the grid after successful award or when the loot window closes.

The confirmation must not use Blizzard's native confirmation path in a way that
causes FrameXML to call `GiveMasterLoot` directly.

## Target Mode

Target mode replaces the three KRT assignment dropdowns:

- Hold target picker updates `raid.holder` and `lootState.holder`.
- Bank target picker updates `raid.banker` and `lootState.banker`.
- DE target picker updates `raid.disenchanter` and `lootState.disenchanter`.

Clicking a player in target mode must not award loot. The existing Hold, Bank,
and DE buttons continue to assign loot through `assignToTarget(...)`.

The roster source should match the current dropdown behavior: use
`addon.UnitIterator(true)`, preserve raid subgroup data when available, and keep
the selected target valid only while the player remains in the group.

## Grid Layout

The grid uses no ScrollFrame. It computes dimensions from candidate count:

```text
cols = min(5, count)
rows = max(1, ceil(count / cols))
```

Expected shapes:

```text
10 players = 5 x 2
20 players = 5 x 4
25 players = 5 x 5
40 players = 5 x 8
```

The frame should be clamped to screen, support Escape close through
`UISpecialFrames`, and use compact KRT/Blizzard styling consistent with the
Master and Logger UI direction.

## Events

KRT currently forwards loot-window events such as `LOOT_OPENED`, `LOOT_CLOSED`,
and `LOOT_SLOT_CLEARED`. The implementation needs a way to react to:

- `OPEN_MASTER_LOOT_LIST`
- `UPDATE_MASTER_LOOT_LIST`
- `LOOT_CLOSED`

Preferred integration is to add KRT event forwarding for the Master Loot list
events, then handle them in the Master controller. A localized `LootFrame`
`HookScript("OnEvent", ...)` remains acceptable only if it is simpler and stays
inside KRT ownership.

## Localization

All new user-facing strings must be added to `addon.L`. Diagnostic text must use
`addon.Diagnose` if diagnostics are needed. New strings must be English and
ASCII-only.

## Changelog

Add an `Unreleased` changelog entry describing the replacement of Master Loot
candidate and Hold/Bank/DE dropdown selection with the new grid picker.

## Verification

Run focused automated checks:

```powershell
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Manual in-game smoke checks:

- `/reload` loads with no Lua errors.
- Master Loot candidate arrow opens the KRT grid.
- Below-threshold candidate click awards through KRT.
- Above-threshold candidate click shows confirmation before awarding.
- Canceling confirmation does not award.
- Hold, Bank, and DE pickers update their configured targets.
- Hold, Bank, and DE buttons award to the configured targets.
- `LOOT_CLOSED` hides the grid.
