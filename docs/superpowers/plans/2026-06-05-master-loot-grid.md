# Master Loot Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native KRT player-grid picker that replaces Master Loot candidate and Hold/Bank/DE dropdown selection while preserving KRT award flow.

**Architecture:** Add a focused `Widgets/MasterLootGrid.lua` widget with two modes: award and target selection. `Controllers/Master.lua` owns domain callbacks, confirmation, and persistence; the widget owns only frame creation, layout, display, and click dispatch. KRT forwards Master Loot list events through the existing bus so the controller can open and refresh the award grid.

**Tech Stack:** WoW 3.3.5a FrameXML, Lua 5.1, KRT controller/widget architecture, `tests/release_stabilization_spec.lua`, repo quality gates.

---

### Task 1: Add RED Tests For Native Grid Behavior

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Write tests for event forwarding and grid behavior**

Add tests that load `Widgets/MasterLootGrid.lua` and `Controllers/Master.lua`, then prove:

```lua
test("master loot list events are forwarded through the KRT bus", function()
    local h = newHarness()
    h:load("!KRT/Init.lua")
    local received = 0
    h.addon.Bus.RegisterCallback(h.addon.Events.Wow.OpenMasterLootList, function()
        received = received + 1
    end)
    h.addon:OPEN_MASTER_LOOT_LIST()
    assertEqual(received, 1, "expected OPEN_MASTER_LOOT_LIST to forward through the bus")
end)
```

Add widget/controller tests proving:

```lua
test("master native loot grid opens for master loot candidates", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob", "Cara" },
        selectedLootQuality = 3,
    })
    ctx.Master:OPEN_MASTER_LOOT_LIST()
    local grid = ctx.h.addon.Widgets.MasterLootGrid
    assertTrue(grid:IsShown(), "expected native grid to show for master loot candidates")
    assertEqual(grid:GetButtonCount(), 3, "expected one grid button per candidate")
end)
```

```lua
test("master native loot grid confirms above-threshold manual awards", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        selectedLootQuality = 4,
    })
    ctx.Master:OPEN_MASTER_LOOT_LIST()
    ctx.h.addon.Widgets.MasterLootGrid:ClickButtonForTest(2)
    assertEqual(#ctx.givenLoot, 0, "expected above-threshold click to wait for confirmation")
    local popup = _G.StaticPopupDialogs.KRT_MASTER_LOOT_GRID_CONFIRM
    popup.OnAccept(nil, popup._krtData)
    assertEqual(#ctx.givenLoot, 1, "expected confirmation to award through KRT")
    assertEqual(ctx.queuedAwards[1].rollType, ctx.h.rollTypes.MANUAL, "expected manual grid award to use Manual roll type")
end)
```

```lua
test("master target grid updates Hold Bank and DE targets without awarding", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        rosterNames = { "Alice", "Bob", "Cara" },
    })
    local raid = ctx.raid
    ctx.Master._Private.OpenAssignmentTargetGrid("holder")
    ctx.h.addon.Widgets.MasterLootGrid:ClickButtonForTest(3)
    assertEqual(raid.holder, "Cara", "expected target grid to persist holder")
    assertEqual(ctx.h.feature.lootState.holder, "Cara", "expected target grid to update holder state")
    assertEqual(#ctx.givenLoot, 0, "expected target selection not to award loot")
end)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `lua tests/release_stabilization_spec.lua`

Expected: FAIL because `OPEN_MASTER_LOOT_LIST`, `Widgets/MasterLootGrid.lua`, or the controller grid hooks do not exist yet.

### Task 2: Add MasterLootGrid Widget

**Files:**
- Create: `!KRT/Widgets/MasterLootGrid.lua`
- Modify: `!KRT/!KRT.toc`

- [ ] **Step 1: Implement the widget**

Create `addon.Widgets.MasterLootGrid` with:

```lua
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Colors = feature.Colors

local module = feature.Widgets.MasterLootGrid or {}
feature.Widgets.MasterLootGrid = module
addon.Widgets.MasterLootGrid = module

local CFG = { maxCols = 5, buttonWidth = 150, buttonHeight = 28, gapX = 5, gapY = 4, padding = 22, headerHeight = 52 }
local frame
local buttons = {}
local entries = {}
local activeConfig
```

Public API:

```lua
function module:ShowPicker(config) end
function module:Hide() end
function module:IsShown() end
function module:Refresh(entriesOverride) end
function module:GetButtonCount() return #entries end
function module:ClickButtonForTest(index) ... end
```

The widget creates a Blizzard-dialog-style frame, dynamically lays out up to 5 columns, creates one button per entry, class-colors names when possible, calls `config.onSelect(entry)` on click, and never calls `GiveMasterLoot`.

- [ ] **Step 2: Add TOC entry**

Add `Widgets\MasterLootGrid.lua` before `Controllers\Master.lua` in `!KRT/!KRT.toc`.

- [ ] **Step 3: Run RED tests again**

Run: `lua tests/release_stabilization_spec.lua`

Expected: Remaining FAIL in controller/event wiring, not widget missing errors.

### Task 3: Wire Controller Award And Target Modes

**Files:**
- Modify: `!KRT/Controllers/Master.lua`
- Modify: `!KRT/Init.lua`
- Modify: `!KRT/Modules/Events.lua`

- [ ] **Step 1: Add event forwarding**

In `Init.lua`, seed and forward:

```lua
Wow.OpenMasterLootList = Wow.OpenMasterLootList or "wow.OPEN_MASTER_LOOT_LIST"
Wow.UpdateMasterLootList = Wow.UpdateMasterLootList or "wow.UPDATE_MASTER_LOOT_LIST"
```

Add `OPEN_MASTER_LOOT_LIST` and `UPDATE_MASTER_LOOT_LIST` to `addonEvents` and `wowBusEvents`.

- [ ] **Step 2: Add controller helpers**

In `Master.lua`, add helpers that:

- collect award candidates from `GetMasterLootCandidate(i)`
- collect target candidates from `dropDownData`
- show `Widgets.MasterLootGrid`
- show KRT confirmation for above-threshold awards
- call `assignItem(itemLink, playerName, rollTypes.MANUAL, 0)` only after confirmation when needed
- update `raid.holder`, `raid.banker`, or `raid.disenchanter` in target mode

- [ ] **Step 3: Replace dropdown open hooks**

Change the Hold/Bank/DE dropdown button hooks so clicking the dropdown button closes Blizzard dropdowns and opens the target grid for that target key.

- [ ] **Step 4: Add event methods**

Add:

```lua
function module:OPEN_MASTER_LOOT_LIST()
    Private.OpenManualAwardGrid()
end

function module:UPDATE_MASTER_LOOT_LIST()
    Private.RefreshManualAwardGrid()
end
```

Register both forwarded events with `registerWowForwarded(...)`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run: `lua tests/release_stabilization_spec.lua`

Expected: PASS or only unrelated pre-existing failures.

### Task 4: Update Text, Changelog, And Generated Tree

**Files:**
- Modify: `!KRT/Localization/localization.en.lua`
- Modify: `!KRT/CHANGELOG.md`
- Modify: `docs/TREE.md`

- [ ] **Step 1: Add localized strings**

Add strings such as:

```lua
L.StrMasterLootGridTitle = "Assign Loot"
L.StrMasterLootGridTargetTitle = "Select Target"
L.StrMasterLootGridEmpty = "No eligible players found."
L.TipMasterLootGridClickAward = "Click to assign loot."
L.TipMasterLootGridClickTarget = "Click to select this target."
L.PopupMasterLootGridConfirm = "Give %s to %s?"
```

- [ ] **Step 2: Add changelog entry**

Under `!KRT/CHANGELOG.md` `## Unreleased`, add a user-visible note that Master Loot candidate and Hold/Bank/DE target selection now use a dynamic grid picker.

- [ ] **Step 3: Refresh tree if needed**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1`

Expected: `docs/TREE.md` lists `!KRT/Widgets/MasterLootGrid.lua`.

### Task 5: Full Verification

**Files:**
- No new code edits unless checks reveal failures.

- [ ] **Step 1: Run required checks**

Run:

```powershell
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected: All commands exit 0.

- [ ] **Step 2: Review diff scope**

Run: `git diff --stat` and inspect changed files.

Expected: Changes are limited to the native Master Loot grid implementation, tests, localization, changelog, TOC, and generated tree/plan docs.
