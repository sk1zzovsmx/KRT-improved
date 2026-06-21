# Master Service Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split pure Master runtime/model logic out of `!KRT/Controllers/Master.lua` into
`!KRT/Services/Master/*` without moving UI, frame, widget, popup, or controller ownership into
Services.

**Architecture:** Add a `Services/Master` service family that owns Master domain models only. The
first service owns workflow display models; the second service owns assignment candidate row models
built from data supplied by the controller. `Controllers/Master.lua` continues to own parent frame
lifecycle, WoW frame APIs, `LootFrame`, dropdowns, popups, and widget dispatch.

**Tech Stack:** World of Warcraft WotLK 3.3.5a, Interface 30300, Lua 5.1, KRT ModuleRegistry,
KRT TOC load order, local Lua test harness.

---

## AGENTS Boundary Contract

This split is allowed by `AGENTS.md` because `!KRT/Services/*` owns runtime service/model logic.
The following boundary is binding for every task in this plan:

- `Services/Master/*` must not call Controllers or Parents.
- `Services/Master/*` must not touch parent frames or named frame globals.
- `Services/Master/*` must not call `UI.Widgets.Call(...)`.
- `Services/Master/*` must not reference `addon.Widgets`, `addon.Controllers`, or child widgets.
- `Services/Master/*` must not use `CreateFrame`, `StaticPopup_Show`, `UIDropDownMenu_*`,
  frame `:Show()`, frame `:Hide()`, or parent frame scripts.
- `Controllers/Master.lua` keeps frame lifecycle, widget orchestration, dropdowns, popup
  confirmation, award side effects, and refresh scheduling.
- `Widgets/RaidGrid.lua` keeps the visual grid implementation.
- Upward communication from Services continues to use `addon.Bus` only when a service must emit an
  event. The planned files do not emit events.

## Target File Structure

Create:

```text
!KRT/Services/Master/Workflow.lua
!KRT/Services/Master/Assignment.lua
!KRT/Services/Master/Service.lua
```

Modify:

```text
!KRT/!KRT.toc
!KRT/Controllers/Master.lua
tests/module_registry_services_spec.lua
tests/release_stabilization_spec.lua
tests/controller_chunk_budget_spec.lua
docs/TREE.md
docs/FUNCTION_REGISTRY.csv
docs/FN_CLUSTERS.md
```

Do not modify:

```text
!KRT/Widgets/RaidGrid.lua
!KRT/Widgets/LootHints.lua
!KRT/Libs/*
```

## Service Responsibilities

### `!KRT/Services/Master/Workflow.lua`

Owns pure workflow/display models currently built by `Private.*` in
`!KRT/Controllers/Master.lua`.

Move these functions:

```text
Private.BuildMasterSrSummaryText
Private.BuildSessionWinnersModel
Private.BuildMasterWorkflowState
```

Rename them to:

```lua
Workflow.BuildSrSummaryText(opts, rollModel)
Workflow.BuildSessionWinnersModel(model)
Workflow.BuildState(opts)
```

Allowed dependencies:

```text
feature.L
feature.rollTypes
tonumber
type
```

Forbidden dependencies:

```text
feature.UI
feature.Controllers
feature.Widgets
LootFrame
StaticPopupDialogs
UIDropDownMenu_SetText
UI.Widgets.Call
module
Database
```

### `!KRT/Services/Master/Assignment.lua`

Owns pure candidate row construction for Master assignment flows. It must build row models from
input data supplied by `Controllers/Master.lua`; it must not read WoW loot frames or open UI.

Move and reshape these responsibilities:

```text
Private.BuildDebugRaidGridEntries
Private.CollectAssignmentTargetEntries
the row-building part of Private.CollectRaidGridEntries
Private.GetDebugRaidGridTargetCount
Private.IsRaidGridDebugFallbackEnabled
```

Do not move these functions:

```text
Private.GetRaidGridFrameAnchor
Private.GetSelectedMasterLootSlot
Private.GetSelectedMasterLootLink
Private.GetSelectedMasterLootQuality
Private.GetSelectedMasterLootTexture
Private.GetSelectedMasterLootCount
Private.HideBlizzardDropDownLists
Private.QueueHideBlizzardDropDownLists
Private.AcceptManualGridAward
Private.EnsureRaidGridConfirmPopup
Private.ShowManualGridAwardConfirm
Private.HandleManualGridEntry
Private.OpenManualAwardGrid
Private.OpenDebugRaidGrid
Private.RefreshManualAwardGrid
Private.GetAssignmentFieldByKey
Private.SetAssignmentTarget
Private.OpenAssignmentTargetGrid
Private.OnClickDropDown
```

New API:

```lua
Assignment.BuildCandidateRows(candidates, classProvider)
Assignment.BuildDebugCandidateRows(count, rosterRows)
Assignment.BuildAssignmentTargetRows(groupedNames, classProvider)
Assignment.GetDebugTargetCount(debugState)
Assignment.IsDebugFallbackEnabled(debugState, debugEnabled)
```

Input shapes:

```lua
local candidates = {
    { name = "Alice", index = 1 },
    { name = "Bob", index = 2 },
}

local rosterRows = {
    { name = "Cara", class = "MAGE" },
    { name = "Dara", class = "PRIEST" },
}

local groupedNames = {
    [1] = { Alice = "Alice", Bob = "Bob" },
    [2] = { Cara = "Cara" },
}
```

Output row shape:

```lua
{
    name = "Alice",
    displayName = "Alice",
    index = 1,
    group = 1,
    class = "MAGE",
    debugOnly = true,
    realRoster = true,
}
```

`group`, `debugOnly`, and `realRoster` are included only when meaningful.

### `!KRT/Services/Master/Service.lua`

Owns the service facade and root export.

Expected exports:

```lua
addon.Services.Master
addon.Services.Master.Workflow
addon.Services.Master.Assignment
```

Facade methods:

```lua
Master.BuildWorkflowState(opts)
Master.BuildSessionWinnersModel(model)
Master.BuildSrSummaryText(opts, rollModel)
Master.BuildAssignmentCandidateRows(candidates, classProvider)
Master.BuildDebugCandidateRows(count, rosterRows)
Master.BuildAssignmentTargetRows(groupedNames, classProvider)
```

The facade must delegate to `Workflow` and `Assignment`. It must not duplicate implementation.

---

### Task 1: Record Baseline And Guardrails

**Files:**
- Read: `!KRT/Controllers/Master.lua`
- Read: `tests/controller_chunk_budget_spec.lua`
- Read: `!KRT/!KRT.toc`

- [ ] **Step 1: Capture current `Private` usage**

Run:

```powershell
rg -n "\bPrivate\." "!KRT\Controllers\Master.lua"
```

Expected: output includes workflow, RaidGrid, button, frame, and award helpers.

- [ ] **Step 2: Capture cross-addon `Private` usage**

Run:

```powershell
rg -n "\bPrivate\." "!KRT"
```

Expected: only `!KRT\Controllers\Master.lua` contains runtime `Private.` references.

- [ ] **Step 3: Capture current local budget**

Run:

```powershell
lua tests/controller_chunk_budget_spec.lua
```

Expected: pass. Record the reported slot counts if the test prints them.

- [ ] **Step 4: Do not edit runtime code in this task**

Expected: `git diff -- !KRT/Controllers/Master.lua` shows no new changes from this task.

---

### Task 2: Add Workflow Service Tests First

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Update the Master controller loader helper**

Find the helper that currently loads Master controller dependencies. Add these service loads before
`!KRT/Controllers/Master.lua` is loaded:

```lua
h:load("!KRT/Services/Master/Workflow.lua")
h:load("!KRT/Services/Master/Service.lua")
```

Expected: tests fail before implementation because the files do not exist.

- [ ] **Step 2: Change workflow tests to call the service**

In the test named `master workflow model names rolling and ready states without changing status
text`, replace:

```lua
local Master = h.addon.Controllers.Master
local Private = Master._Private

local idle = Private.BuildMasterWorkflowState({
```

with:

```lua
local Workflow = h.addon.Services.Master.Workflow

local idle = Workflow.BuildState({
```

Replace the other calls in that test:

```lua
Private.BuildMasterWorkflowState({
```

with:

```lua
Workflow.BuildState({
```

- [ ] **Step 3: Change capability workflow tests to call the service**

In the test named `master workflow model centralizes button capabilities without changing gating`,
replace:

```lua
local Master = h.addon.Controllers.Master
local Private = Master._Private
```

with:

```lua
local Workflow = h.addon.Services.Master.Workflow
```

Replace each:

```lua
Private.BuildMasterWorkflowState({
```

with:

```lua
Workflow.BuildState({
```

- [ ] **Step 4: Change session winners test to call the service**

In the test named `master workflow model exposes compact session winners`, replace:

```lua
local Private = h.addon.Controllers.Master._Private
local winners = Private.BuildSessionWinnersModel({
```

with:

```lua
local Workflow = h.addon.Services.Master.Workflow
local winners = Workflow.BuildSessionWinnersModel({
```

- [ ] **Step 5: Run the red test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: fail with a missing `!KRT/Services/Master/Workflow.lua` or missing
`addon.Services.Master.Workflow` error.

---

### Task 3: Create `Services/Master/Workflow.lua`

**Files:**
- Create: `!KRT/Services/Master/Workflow.lua`
- Modify: `!KRT/!KRT.toc`

- [ ] **Step 1: Add TOC entry**

Insert the new file before `Controllers\Master.lua`:

```text
Services\Master\Workflow.lua
Services\Master\Service.lua
Widgets\RaidGrid.lua
Widgets\LootHints.lua
Controllers\Master.lua
```

During this task `Services\Master\Service.lua` may not exist yet. Add it in Task 4 before running
the TOC gate.

- [ ] **Step 2: Create the service file header and namespace**

Create `!KRT/Services/Master/Workflow.lua`:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master.Workflow
-- events: none
-- notes: pure Master workflow display models

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local Workflow = Master.Workflow or {}
Master.Workflow = Workflow

local L = feature.L
local rollTypes = feature.rollTypes

local type = type
local tonumber = tonumber

-- ----- Public methods ----- --
```

- [ ] **Step 3: Move `BuildMasterSrSummaryText`**

Move the existing body from `Private.BuildMasterSrSummaryText` in
`!KRT/Controllers/Master.lua` into:

```lua
function Workflow.BuildSrSummaryText(opts, rollModel)
    -- move the existing function body here without changing behavior
end
```

Inside the moved body, keep the same local names and return values.

- [ ] **Step 4: Move `BuildSessionWinnersModel`**

Move the existing body from `Private.BuildSessionWinnersModel` into:

```lua
function Workflow.BuildSessionWinnersModel(model)
    -- move the existing function body here without changing behavior
end
```

Inside the moved body, keep the same row ordering, state names, and `summaryText` output.

- [ ] **Step 5: Move `BuildMasterWorkflowState`**

Move the existing body from `Private.BuildMasterWorkflowState` into:

```lua
function Workflow.BuildState(opts)
    -- move the existing function body here without changing behavior
end
```

In the moved body, replace:

```lua
Private.BuildMasterSrSummaryText(opts, rollModel)
Private.BuildSessionWinnersModel(rollModel)
```

with:

```lua
Workflow.BuildSrSummaryText(opts, rollModel)
Workflow.BuildSessionWinnersModel(rollModel)
```

- [ ] **Step 6: Run the focused test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: fail only because `Services/Master/Service.lua` is not created or loaded yet, or pass if
the test loader can access `Workflow.lua` directly.

---

### Task 4: Create `Services/Master/Service.lua`

**Files:**
- Create: `!KRT/Services/Master/Service.lua`
- Modify: `!KRT/!KRT.toc`

- [ ] **Step 1: Create the facade file**

Create `!KRT/Services/Master/Service.lua`:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master
-- events: none
-- notes: Master service facade for domain/model helpers

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local Workflow = Master.Workflow

-- ----- Public methods ----- --

function Master.BuildWorkflowState(opts)
    return Workflow.BuildState(opts)
end

function Master.BuildSessionWinnersModel(model)
    return Workflow.BuildSessionWinnersModel(model)
end

function Master.BuildSrSummaryText(opts, rollModel)
    return Workflow.BuildSrSummaryText(opts, rollModel)
end
```

- [ ] **Step 2: Verify TOC order**

Ensure the TOC contains:

```text
Services\Master\Workflow.lua
Services\Master\Service.lua
Widgets\RaidGrid.lua
Widgets\LootHints.lua
Controllers\Master.lua
```

Expected: `Workflow.lua` loads before `Service.lua`, and both load before `Controllers\Master.lua`.

- [ ] **Step 3: Run the focused tests**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: workflow and session winner tests pass through `addon.Services.Master.Workflow`.

---

### Task 5: Redirect `Controllers/Master.lua` Workflow Calls

**Files:**
- Modify: `!KRT/Controllers/Master.lua`

- [ ] **Step 1: Add one service local**

Near the existing service locals:

```lua
local Services = feature.Services
local Loot = Services.Loot
local Raid = Services.Raid
local Rolls = Services.Rolls
local Chat = Services.Chat
```

add:

```lua
local MasterService = Services.Master
```

Keep this as one local. Do not add separate locals for `Workflow` or individual functions.

- [ ] **Step 2: Replace workflow call site**

Replace:

```lua
local workflowState = Private.BuildMasterWorkflowState({
```

with:

```lua
local workflowState = MasterService.BuildWorkflowState({
```

- [ ] **Step 3: Remove moved `Private` functions**

Delete these definitions from `!KRT/Controllers/Master.lua`:

```text
Private.BuildMasterSrSummaryText
Private.BuildSessionWinnersModel
Private.BuildMasterWorkflowState
```

- [ ] **Step 4: Verify no workflow helpers remain on `Private`**

Run:

```powershell
rg -n "BuildMasterSrSummaryText|BuildSessionWinnersModel|BuildMasterWorkflowState" "!KRT"
```

Expected: no matches in `!KRT/Controllers/Master.lua`; matches only in tests or docs are acceptable
until those references are updated.

- [ ] **Step 5: Run controller budget**

Run:

```powershell
lua tests/controller_chunk_budget_spec.lua
```

Expected: pass. `Master.lua` slot count must not increase above the current budget.

---

### Task 6: Add Assignment Service Tests First

**Files:**
- Create: `tests/master_assignment_service_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`

- [ ] **Step 1: Create focused assignment model tests**

Create `tests/master_assignment_service_spec.lua`:

```lua
local function newAddon()
    local addon = {
        Services = {},
        Database = {},
    }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
    }
    addon.Database.GetFeatureShared = function()
        return feature
    end
    return addon, feature
end

local addon = newAddon()
local chunk = assert(loadfile("!KRT/Services/Master/Assignment.lua"))
setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
chunk("!KRT", addon)

local Assignment = addon.Services.Master.Assignment

local rows = Assignment.BuildCandidateRows({
    { name = "Alice", index = 1 },
    { name = "Bob", index = 2 },
}, function(name)
    if name == "Alice" then
        return "MAGE"
    end
    return "PRIEST"
end)

assert(#rows == 2, "expected candidate rows")
assert(rows[1].name == "Alice", "expected first candidate name")
assert(rows[1].displayName == "Alice", "expected first candidate display name")
assert(rows[1].index == 1, "expected first candidate index")
assert(rows[1].class == "MAGE", "expected class provider result")

local debugRows, total = Assignment.BuildDebugCandidateRows(3, {
    { name = "Cara", class = "ROGUE" },
})
assert(total == 3, "expected debug count")
assert(#debugRows == 3, "expected roster row plus fake fillers")
assert(debugRows[1].name == "Cara", "expected real roster row first")
assert(debugRows[1].realRoster == true, "expected roster flag")
assert(debugRows[1].debugOnly == true, "expected debug flag")
assert(debugRows[2].name == "Player1", "expected fake filler")

local targetRows = Assignment.BuildAssignmentTargetRows({
    [2] = { Bob = "Bob" },
    [1] = { Alice = "Alice" },
}, function(name)
    if name == "Bob" then
        return "PRIEST"
    end
    return "MAGE"
end)
assert(#targetRows == 2, "expected target rows")
assert(targetRows[1].name == "Alice", "expected rows sorted by group then name")
assert(targetRows[1].group == 1, "expected group on target row")
assert(targetRows[2].name == "Bob", "expected second sorted row")

assert(Assignment.GetDebugTargetCount({ raidGridTargetCount = 12 }) == 12, "expected debug count")
assert(Assignment.GetDebugTargetCount({}) == 25, "expected default debug count")
assert(Assignment.IsDebugFallbackEnabled({ raidGridTargetCount = 12 }, false) == true, "expected state flag")
assert(Assignment.IsDebugFallbackEnabled({}, true) == true, "expected debug flag")
assert(Assignment.IsDebugFallbackEnabled({}, false) == false, "expected disabled fallback")

print("master assignment service spec passed")
```

- [ ] **Step 2: Run the red test**

Run:

```powershell
lua tests/master_assignment_service_spec.lua
```

Expected: fail because `!KRT/Services/Master/Assignment.lua` does not exist.

---

### Task 7: Create `Services/Master/Assignment.lua`

**Files:**
- Create: `!KRT/Services/Master/Assignment.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Services/Master/Service.lua`

- [ ] **Step 1: Add TOC entry**

Update TOC order:

```text
Services\Master\Workflow.lua
Services\Master\Assignment.lua
Services\Master\Service.lua
Widgets\RaidGrid.lua
Widgets\LootHints.lua
Controllers\Master.lua
```

- [ ] **Step 2: Create Assignment service**

Create `!KRT/Services/Master/Assignment.lua`:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master.Assignment
-- events: none
-- notes: pure Master assignment candidate row models

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local Assignment = Master.Assignment or {}
Master.Assignment = Assignment

local tinsert = table.insert
local pairs = pairs
local type = type
local tostring = tostring
local tonumber = tonumber

local DEFAULT_DEBUG_COUNT = 25
local MAX_DEBUG_COUNT = 40
local MIN_DEBUG_COUNT = 1

local DEBUG_CLASSES = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "DRUID",
}

-- ----- Private helpers ----- --

local function clampDebugCount(count)
    local total = tonumber(count) or DEFAULT_DEBUG_COUNT
    total = math.floor(total)
    if total < MIN_DEBUG_COUNT then
        total = MIN_DEBUG_COUNT
    elseif total > MAX_DEBUG_COUNT then
        total = MAX_DEBUG_COUNT
    end
    return total
end

local function getClass(classProvider, name)
    if type(classProvider) == "function" then
        return classProvider(name)
    end
    return nil
end

-- ----- Public methods ----- --

function Assignment.BuildCandidateRows(candidates, classProvider)
    local result = {}
    if type(candidates) ~= "table" then
        return result
    end
    for i = 1, #candidates do
        local candidate = candidates[i]
        local name = candidate and candidate.name
        if name and name ~= "" then
            tinsert(result, {
                name = name,
                displayName = name,
                index = candidate.index or i,
                class = getClass(classProvider, name),
            })
        end
    end
    return result
end

function Assignment.BuildDebugCandidateRows(count, rosterRows)
    local total = clampDebugCount(count)
    local result = {}
    local seen = {}

    if type(rosterRows) == "table" then
        for i = 1, #rosterRows do
            local row = rosterRows[i]
            local name = row and row.name
            if name and name ~= "" and not seen[name] then
                tinsert(result, {
                    name = name,
                    displayName = name,
                    index = #result + 1,
                    class = row.class or DEBUG_CLASSES[(#result % #DEBUG_CLASSES) + 1],
                    debugOnly = true,
                    realRoster = true,
                })
                seen[name] = true
            end
        end
    end

    if #result > total then
        total = #result
    end

    local fakeIndex = 1
    while #result < total do
        local name = "Player" .. tostring(fakeIndex)
        fakeIndex = fakeIndex + 1
        if not seen[name] then
            tinsert(result, {
                name = name,
                displayName = name,
                index = #result + 1,
                class = DEBUG_CLASSES[(#result % #DEBUG_CLASSES) + 1],
                debugOnly = true,
            })
            seen[name] = true
        end
    end

    return result, total
end

function Assignment.GetDebugTargetCount(debugState)
    return debugState and debugState.raidGridTargetCount or DEFAULT_DEBUG_COUNT
end

function Assignment.IsDebugFallbackEnabled(debugState, debugEnabled)
    if debugState and debugState.raidGridTargetCount then
        return true
    end
    return debugEnabled == true
end

function Assignment.BuildAssignmentTargetRows(groupedNames, classProvider)
    local result = {}
    if type(groupedNames) ~= "table" then
        return result
    end
    for group = 1, 8 do
        local names = groupedNames[group]
        if type(names) == "table" then
            for name in pairs(names) do
                tinsert(result, {
                    name = name,
                    displayName = name,
                    group = group,
                    class = getClass(classProvider, name),
                })
            end
        end
    end
    table.sort(result, function(a, b)
        if a.group == b.group then
            return tostring(a.name or "") < tostring(b.name or "")
        end
        return (tonumber(a.group) or 0) < (tonumber(b.group) or 0)
    end)
    return result
end
```

- [ ] **Step 3: Add facade aliases**

In `!KRT/Services/Master/Service.lua`, add:

```lua
local Assignment = Master.Assignment

function Master.BuildAssignmentCandidateRows(candidates, classProvider)
    return Assignment.BuildCandidateRows(candidates, classProvider)
end

function Master.BuildDebugCandidateRows(count, rosterRows)
    return Assignment.BuildDebugCandidateRows(count, rosterRows)
end

function Master.BuildAssignmentTargetRows(groupedNames, classProvider)
    return Assignment.BuildAssignmentTargetRows(groupedNames, classProvider)
end
```

- [ ] **Step 4: Run assignment test**

Run:

```powershell
lua tests/master_assignment_service_spec.lua
```

Expected: pass with `master assignment service spec passed`.

---

### Task 8: Redirect Master Candidate Row Building

**Files:**
- Modify: `!KRT/Controllers/Master.lua`

- [ ] **Step 1: Add local helper to collect raw Master Loot candidates**

Keep WoW API access in `Controllers/Master.lua`:

```lua
local function collectMasterLootCandidates()
    local result = {}
    if type(GetMasterLootCandidate) ~= "function" then
        return result
    end
    for i = 1, 40 do
        local name = GetMasterLootCandidate(i)
        if name and name ~= "" then
            tinsert(result, {
                name = name,
                index = i,
            })
        end
    end
    return result
end
```

- [ ] **Step 2: Add local helper to collect roster rows for debug preview**

Keep unit iteration in the controller:

```lua
local function collectRaidGridRosterRows()
    local result = {}
    local seen = {}
    if addon.UnitIterator then
        for unit in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" and not seen[name] then
                local className = Raid and Raid.GetPlayerClass and Raid:GetPlayerClass(name) or nil
                if not className and UnitClass then
                    local _, classFileName = UnitClass(unit)
                    className = classFileName
                end
                tinsert(result, {
                    name = name,
                    class = className,
                })
                seen[name] = true
            end
        end
    end
    return result
end
```

- [ ] **Step 3: Add class provider helper**

```lua
local function getRaidGridPlayerClass(name)
    if Raid and Raid.GetPlayerClass then
        return Raid:GetPlayerClass(name)
    end
    return nil
end
```

- [ ] **Step 4: Replace `Private.CollectRaidGridEntries`**

Replace the body of `Private.CollectRaidGridEntries` with a call to the service:

```lua
Private.CollectRaidGridEntries = function()
    return MasterService.BuildAssignmentCandidateRows(collectMasterLootCandidates(), getRaidGridPlayerClass)
end
```

This keeps the public `Private` function temporarily so fewer call sites change in one step.

- [ ] **Step 5: Replace `Private.BuildDebugRaidGridEntries`**

Replace the body with:

```lua
Private.BuildDebugRaidGridEntries = function(count, includeRoster)
    local rosterRows = {}
    if includeRoster ~= false then
        rosterRows = collectRaidGridRosterRows()
    end
    return MasterService.BuildDebugCandidateRows(count, rosterRows)
end
```

- [ ] **Step 6: Replace debug state helpers**

Replace:

```lua
Private.GetDebugRaidGridTargetCount = function()
    local debugState = feature.coreState and feature.coreState.debug or nil
    return debugState and debugState.raidGridTargetCount or 25
end
```

with:

```lua
Private.GetDebugRaidGridTargetCount = function()
    local debugState = feature.coreState and feature.coreState.debug or nil
    return MasterService.Assignment.GetDebugTargetCount(debugState)
end
```

Replace:

```lua
Private.IsRaidGridDebugFallbackEnabled = function()
    local debugState = feature.coreState and feature.coreState.debug or nil
    if debugState and debugState.raidGridTargetCount then
        return true
    end
    return Options and Options.IsDebugEnabled and Options.IsDebugEnabled() == true
end
```

with:

```lua
Private.IsRaidGridDebugFallbackEnabled = function()
    local debugState = feature.coreState and feature.coreState.debug or nil
    return MasterService.Assignment.IsDebugFallbackEnabled(debugState, isDebugEnabled())
end
```

- [ ] **Step 7: Replace `Private.CollectAssignmentTargetEntries`**

Keep `prepareDropDowns()` in the controller. Replace the row-building body with:

```lua
Private.CollectAssignmentTargetEntries = function()
    if prepareDropDowns then
        prepareDropDowns()
    end
    return MasterService.BuildAssignmentTargetRows(module._dropDownData, getRaidGridPlayerClass)
end
```

- [ ] **Step 8: Run focused tests**

Run:

```powershell
lua tests/master_assignment_service_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/controller_chunk_budget_spec.lua
```

Expected: all pass.

---

### Task 9: Remove Temporary Private Wrappers For Moved Assignment Logic

**Files:**
- Modify: `!KRT/Controllers/Master.lua`

- [ ] **Step 1: Replace call sites for candidate entries**

Replace:

```lua
local entries = Private.CollectRaidGridEntries()
```

with:

```lua
local entries = MasterService.BuildAssignmentCandidateRows(
    collectMasterLootCandidates(),
    getRaidGridPlayerClass
)
```

- [ ] **Step 2: Replace call sites for debug entries**

Replace:

```lua
entries = Private.BuildDebugRaidGridEntries(Private.GetDebugRaidGridTargetCount(), true)
```

with:

```lua
entries = MasterService.BuildDebugCandidateRows(
    Private.GetDebugRaidGridTargetCount(),
    collectRaidGridRosterRows()
)
```

Replace:

```lua
local entries, total = Private.BuildDebugRaidGridEntries(count)
```

with:

```lua
local entries, total = MasterService.BuildDebugCandidateRows(count, collectRaidGridRosterRows())
```

- [ ] **Step 3: Replace call site for assignment target rows**

Replace:

```lua
entries = Private.CollectAssignmentTargetEntries(),
```

with:

```lua
entries = MasterService.BuildAssignmentTargetRows(module._dropDownData, getRaidGridPlayerClass),
```

Keep the surrounding `prepareDropDowns()` call before `UI.Widgets.Call(...)`.

- [ ] **Step 4: Delete moved `Private` wrapper definitions**

Delete these definitions:

```text
Private.CollectRaidGridEntries
Private.BuildDebugRaidGridEntries
Private.GetDebugRaidGridTargetCount
Private.IsRaidGridDebugFallbackEnabled
Private.CollectAssignmentTargetEntries
```

- [ ] **Step 5: Keep selected loot helpers in controller**

Verify these functions still live in `Controllers/Master.lua`:

```text
Private.GetSelectedMasterLootSlot
Private.GetSelectedMasterLootLink
Private.GetSelectedMasterLootQuality
Private.GetSelectedMasterLootTexture
Private.GetSelectedMasterLootCount
```

Expected: they remain in the controller because they read `LootFrame` and WoW loot APIs.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
lua tests/master_assignment_service_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/controller_chunk_budget_spec.lua
```

Expected: all pass, and `Private.*` count in `Master.lua` decreases.

---

### Task 10: Register New Services In Source Contracts

**Files:**
- Modify: `tests/module_registry_services_spec.lua`

- [ ] **Step 1: Add expected Master service metadata**

Add an `expectedMasterServices` table near the other service family metadata:

```lua
local expectedMasterServices = {
    {
        name = "Services/Master/Workflow",
        path = "!KRT/Services/Master/Workflow.lua",
        owner = "Workflow",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        events = "-- events: none",
        note = "-- notes: pure Master workflow display models",
    },
    {
        name = "Services/Master/Assignment",
        path = "!KRT/Services/Master/Assignment.lua",
        owner = "Assignment",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        events = "-- events: none",
        note = "-- notes: pure Master assignment candidate row models",
    },
    {
        name = "Services/Master/Service",
        path = "!KRT/Services/Master/Service.lua",
        owner = "Master",
        separator = ".",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Services/Master/Workflow",
            "Services/Master/Assignment",
        },
        events = "-- events: none",
        note = "-- notes: Master service facade for domain/model helpers",
    },
}
```

- [ ] **Step 2: Add the family to the existing service assertion loop**

Find the loop that asserts `expectedRollServices`, `expectedLootServices`, `expectedRaidServices`,
or similar service tables. Add `expectedMasterServices` to the same assertion path.

The assertion must validate:

```text
header
events marker
notes marker
direct ModuleRegistry metadata
public exported function owner
TOC path
TOC order
```

- [ ] **Step 3: Add TOC ordering assertions**

Add assertions equivalent to:

```lua
assertBefore(toc, "Services\\Master\\Workflow.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\Assignment.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\Service.lua", "Controllers\\Master.lua")
assertBefore(toc, "Services\\Master\\Service.lua", "Widgets\\RaidGrid.lua")
```

If the project prefers widgets before services in this area, keep only the controller-order
assertion. The binding requirement is that Master services load before `Controllers\Master.lua`.

- [ ] **Step 4: Run service registry test**

Run:

```powershell
lua tests/module_registry_services_spec.lua
```

Expected: pass.

---

### Task 11: Add ModuleRegistry Metadata To New Services

**Files:**
- Modify: `!KRT/Services/Master/Workflow.lua`
- Modify: `!KRT/Services/Master/Assignment.lua`
- Modify: `!KRT/Services/Master/Service.lua`

- [ ] **Step 1: Register Workflow**

Add after namespace locals in `Workflow.lua`:

```lua
local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/Workflow", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
        },
    })
    registry.SetLoaded("Services/Master/Workflow")
end
```

- [ ] **Step 2: Register Assignment**

Add after namespace locals in `Assignment.lua`:

```lua
local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/Assignment", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
        },
    })
    registry.SetLoaded("Services/Master/Assignment")
end
```

- [ ] **Step 3: Register Service facade**

Add after namespace locals in `Service.lua`:

```lua
local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/Service", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Services/Master/Workflow",
            "Services/Master/Assignment",
        },
    })
    registry.SetLoaded("Services/Master/Service")
end
```

- [ ] **Step 4: Run registry tests**

Run:

```powershell
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected: both pass.

---

### Task 12: Reduce Test Dependency On `Master._Private`

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Verify workflow tests no longer use `_Private`**

Run:

```powershell
rg -n "_Private.*BuildMasterWorkflowState|BuildMasterWorkflowState|BuildSessionWinnersModel" tests
```

Expected: workflow and session winner tests use `addon.Services.Master.Workflow`.

- [ ] **Step 2: Keep controller behavior tests on `_Private`**

These test calls may remain for this split:

```text
Master._Private.LoadFrame
Master._Private.RefreshFrame
Master._Private.OpenAssignmentTargetGrid
Master._Private.BtnAward
Master._Private.BtnMS
Master._Private.BtnCountdown
Master._Private.BtnSelectItem
Master._Private.BuildLootReserveUiState
```

Reason: those functions still represent controller/frame/button behavior or LootHints wrappers.

- [ ] **Step 3: Run private usage inventory**

Run:

```powershell
rg -n "_Private" tests !KRT docs
```

Expected: fewer test call sites than before the split. Remaining call sites are controller-behavior
tests, not pure model tests.

---

### Task 13: Update Generated Docs And Tree

**Files:**
- Modify: `docs/TREE.md`
- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/FN_CLUSTERS.md`

- [ ] **Step 1: Update tree**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

If new service files are not listed because they are untracked, update `docs/TREE.md` manually with:

```text
|   |-- Services
|   |   |-- Master
|   |   |   |-- Assignment.lua
|   |   |   |-- Service.lua
|   |   |   |-- Workflow.lua
```

- [ ] **Step 2: Regenerate function inventory**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
```

Expected: function registry moves workflow and assignment model functions from Controllers to
Services/Master.

- [ ] **Step 3: Avoid changelog for behavior-neutral service split**

Do not add a changelog entry for this split unless behavior, user-visible text, commands,
SavedVariables, or UI output changes.

---

### Task 14: Final Verification

**Files:**
- Read: all modified files

- [ ] **Step 1: Run focused tests**

Run:

```powershell
lua tests/master_assignment_service_spec.lua
lua tests/controller_chunk_budget_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected:

```text
master assignment service spec passed
controller chunk budget spec passed
module registry services source contract passed
module registry UI entrypoints source contract passed
262 targeted stabilization test(s) passed.
```

- [ ] **Step 2: Run syntax and repo gates**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check all
git diff --check
```

Expected:

```text
Lua syntax check passed.
Lua uniformity checks passed.
Raid hardening checks passed.
TOC file checks passed.
UI binding checks passed.
git diff --check exits 0
```

- [ ] **Step 3: Verify AGENTS boundary**

Run:

```powershell
$pattern = "UI\.Widgets|addon\.Widgets|addon\.Controllers|CreateFrame|StaticPopup"
$pattern = $pattern + "|UIDropDownMenu|LootFrame|:Show\(|:Hide\("
rg -n $pattern "!KRT\Services\Master"
```

Expected: no matches.

- [ ] **Step 4: Verify `Private` reduction**

Run:

```powershell
rg -n "\bPrivate\." "!KRT\Controllers\Master.lua"
```

Expected: no workflow model helpers and no assignment row model helpers remain on `Private`.
Frame, popup, button, dropdown, and award helpers may remain.

- [ ] **Step 5: Verify local budget did not regress**

Run:

```powershell
lua tests/controller_chunk_budget_spec.lua
```

Expected: pass. `Master.lua` must remain at or below the configured budget.

---

## Expected End State

After executing this plan:

- `!KRT/Services/Master/Workflow.lua` owns pure Master workflow models.
- `!KRT/Services/Master/Assignment.lua` owns pure assignment candidate row models.
- `!KRT/Services/Master/Service.lua` exports `addon.Services.Master`.
- `Controllers/Master.lua` keeps UI, frame, widget, popup, dropdown, and award ownership.
- `Widgets/RaidGrid.lua` keeps visual grid rendering and click dispatch.
- `Master._Private` remains only for controller behavior still tested through the harness.
- Pure model tests no longer call `Master._Private`.
- The service split complies with AGENTS service boundaries.
- The Lua 5.1 local budget remains below the configured threshold.
