# Controller Service Duplication Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce duplicated controller-owned logic by moving reusable model, validation, preview,
and SavedVariables helpers into services and modules without changing public controller APIs.

**Architecture:** Keep Controllers as frame owners and event/UI coordinators. Move pure model logic,
store access, validation, and formatting into existing services/modules where ownership already
exists, and introduce only two small services for controller-only domains that currently have no
service boundary: `Services/Spammer.lua` and `Services/Warnings.lua`. Implementation must preserve
WotLK 3.3.5a, Interface 30300, Lua 5.1, TOC load order, SavedVariables shape, and controller
request method names used by Widgets, EntryPoints, and config panels.

**Tech Stack:** World of Warcraft WotLK 3.3.5a, Interface 30300, Lua 5.1, KRT ModuleRegistry, KRT
TOC load order, repo-local Lua harness, PowerShell repo checks, delegated 55to53 workflow.

---

## 55to53 Execution Contract

Classification for implementation: `complex-orchestrated`.

Reason: this plan touches controller/service boundaries, public request methods, TOC load order,
SavedVariables-backed runtime state, and shared tests. The parent agent must not implement the code
directly. Use the repo-local workflow:

1. Parent narrows one task at a time.
2. Parent uses `code-mapper` first when a task's call flow is not already clear.
3. Parent delegates each implementation task to `spark_implementer` with closed instructions.
4. Spark applies only the current task's scoped patch.
5. Parent reviews every diff for behavior drift, load order, Lua 5.1 safety, and controller/service
   boundary violations.
6. Parent runs the listed checks before accepting each task.

No `!KRT/Libs/*` file is in scope. No SavedVariables shape change is allowed. Public controller
methods such as `Spammer:RequestPreview()`, `Warnings:RequestClearSavedWarnings()`, and
`Logger` popup handlers must remain callable.

## Current Structure Map

### Controllers

- `!KRT/Controllers/Master.lua`: owns the Master parent frame, loot/roll/trade event glue, widget
  calls, popups, dropdowns, and UI refresh. Recent service extraction already exists through
  `Services/Master/AwardCounter.lua` and `Services/Master/RollAnnouncements.lua`. Remaining issue:
  `Services/Master/FlowState.lua` reads `multiAward.index`, while the controller and Loot service use
  `multiAward.pos`.
- `!KRT/Controllers/Logger.lua`: owns Logger frame selection, edit popups, delete confirmations, and
  list refresh. Store/view/export/actions are already under `Services/Logger/*`. Remaining issue:
  roll-value validation is UI-local even though `Services/Logger/Actions.lua` mutates `rollValue`.
- `!KRT/Controllers/Warnings.lua`: owns the Warnings frame, SavedVariables store access,
  default-template installation, template preview, save/delete/clear, and announce requests.
  Remaining issue: non-frame model and persistence helpers have no service boundary.
- `!KRT/Controllers/Spammer.lua`: owns the LFM Spam frame and delegates ticking to `Services/Chat`.
  Remaining issue: SavedVariables access, output construction, preview state, and store mutation are
  still controller-local.

### Services

- `!KRT/Services/Master/*`: owns Master model helpers such as soft-res summary, flow state, button
  state, roll rows, assignment targets, award messages, loot spam, award counter, and roll
  announcements. Must not reference frames, Controllers, Widgets, or shared UI helpers.
- `!KRT/Services/Loot/*`: owns loot context, state, snapshots, pending awards, passive group loot,
  tracking, workflow, receipts, records, reconciliation, rules, distribution sessions, and public
  Loot facade behavior.
- `!KRT/Services/Logger/*`: owns Logger store, view models, exports, helpers, and mutations/actions.
- `!KRT/Services/Reserves.lua` plus `!KRT/Services/Reserves/*`: owns reserves parsing, aliases,
  display, sync, chat policy, and runtime/persisted reserves data.
- `!KRT/Services/Chat.lua`: owns chat-safe output and LFM spam ticker runtime.
- `!KRT/Services/Raid/*` and `!KRT/Services/Rolls/*`: own capability, roster, count, roll session,
  response, strategy, resolution, history, and display-model service logic.

### Modules, Database, Widgets, EntryPoints, Libs

- `!KRT/Modules/*`: reusable infrastructure and static data. `Modules/LootSourceCandidates.lua`
  already owns shared-source labels, shared-source parsing, and candidate copying, so it is the
  correct home for duplicated loot-source display model construction.
- `!KRT/Database/*`: DB schema, options, raid store, raid queries, validation, migrations, and sync.
  `Database/DBRaidQueries.lua` duplicates a loot-source model helper currently also in
  `Services/Logger/View.lua`.
- `!KRT/Widgets/*`: child UI widgets. Widgets must continue to call controller request methods
  through existing widget/controller dispatch.
- `!KRT/EntryPoints/*`: slash and minimap entrypoints. Slash currently has a manual reserves-count
  fallback that duplicates service logic because `Services.Reserves:GetCounts()` is not exported.
- `!KRT/Libs/*`: vendored libraries. Out of scope.

## Target File Structure

Create:

```text
!KRT/Services/Spammer.lua
!KRT/Services/Warnings.lua
```

Modify:

```text
!KRT/!KRT.toc
!KRT/Modules/LootSourceCandidates.lua
!KRT/Database/DBRaidQueries.lua
!KRT/Services/Master/FlowState.lua
!KRT/Services/Reserves.lua
!KRT/Services/Logger/View.lua
!KRT/Services/Logger/Actions.lua
!KRT/Controllers/Logger.lua
!KRT/Controllers/Spammer.lua
!KRT/Controllers/Warnings.lua
!KRT/EntryPoints/SlashEvents.lua
tests/controllers_cleanup_spec.lua
tests/master_service_split_spec.lua
tests/release_stabilization_spec.lua
tests/module_registry_services_spec.lua
tests/module_registry_ui_entrypoints_spec.lua
docs/TREE.md
docs/FUNCTION_REGISTRY.csv
docs/FN_CLUSTERS.md
```

Do not modify:

```text
!KRT/Libs/*
!KRT/UI/*.xml
SavedVariables schema files unless a parent-approved behavior change is added
```

## Baseline Evidence To Preserve

- `py -3 tools/krt.py repo-quality-check --check all`: expected baseline OK.
- `py -3 tools/krt.py repo-quality-check --check layering`: expected baseline OK.
- `lua tests/master_service_split_spec.lua`: expected baseline OK.
- `lua tests/release_stabilization_spec.lua`: expected baseline `286 tests passed`.
- `lua tests/controllers_cleanup_spec.lua`: current baseline failure is expected until Task 1:
  `Master must centralize namespace option reads`.
- Current generated census: 4 controller files, about 9766 controller lines, 506 controller
  functions; 55 service files, about 22286 service lines, 1134 service functions; function inventory
  about 2644 entries.

---

### Task 1: Reconcile The Stale Controller Cleanup Contract

**Files:**
- Modify: `tests/controllers_cleanup_spec.lua`
- Test: `tests/controllers_cleanup_spec.lua`

**Problem:** The cleanup test still expects the retired helper text
`local function getOption(namespace, key)`, while `!KRT/Controllers/Master.lua` already centralizes
option reads with `local GetOption = Options.GetValue`.

**Risk:** Low. This is a test-contract update only.

- [ ] **Step 1: Update the cleanup assertions**

In `tests/controllers_cleanup_spec.lua`, replace these five assertions:

```lua
assertContains(master, "local function getOption(namespace, key)", "Master must centralize namespace option reads")
assertContains(master, 'getOption("Master",', "Master namespace reads must use getOption")
assertContains(master, 'getOption("Loot",', "Loot namespace reads must use getOption")
assertContains(master, 'getOption("Rolls",', "Rolls namespace reads must use getOption")
assertContains(master, 'getOption("UI",', "UI namespace reads must use getOption")
```

with:

```lua
assertContains(master, "local GetOption = Options.GetValue", "Master must centralize namespace option reads")
assertContains(master, 'GetOption("Master",', "Master namespace reads must use GetOption")
assertContains(master, 'GetOption("Loot",', "Loot namespace reads must use GetOption")
assertContains(master, 'GetOption("Rolls",', "Rolls namespace reads must use GetOption")
assertContains(master, 'GetOption("UI",', "UI namespace reads must use GetOption")
```

- [ ] **Step 2: Verify the cleanup spec**

Run:

```powershell
lua tests/controllers_cleanup_spec.lua
```

Expected:

```text
controllers cleanup source contract passed
```

- [ ] **Step 3: Commit**

```powershell
git add tests/controllers_cleanup_spec.lua
git commit -m "test: align controller cleanup option contract"
```

---

### Task 2: Fix Multi-Award Position Ownership In FlowState

**Files:**
- Modify: `!KRT/Services/Master/FlowState.lua`
- Modify: `tests/master_service_split_spec.lua`
- Test: `tests/master_service_split_spec.lua`

**Problem:** `!KRT/Services/Master/FlowState.lua` reads `multiAward.index`, but the active
multi-award state in `!KRT/Controllers/Master.lua` and `!KRT/Services/Loot/Service.lua` uses
`multiAward.pos`. This can display `1/N` during later multi-award steps.

**Risk:** Low. The change only affects status text, with a compatibility fallback to `index`.

- [ ] **Step 1: Add a failing model assertion**

Append this block before `print("master service split spec passed")` in
`tests/master_service_split_spec.lua`:

```lua
local multiAwardState = Master.BuildWorkflowState({
    hasItem = true,
    hasLootAccess = true,
    lootState = {
        lootCount = 1,
        rollsCount = 2,
        multiAward = {
            active = true,
            pos = 2,
            total = 3,
            winners = {
                { name = "Alice" },
                { name = "Bob" },
                { name = "Cara" },
            },
        },
    },
    currentFlowState = "multi_award",
    currentMultiWinner = "Bob",
})
assert(multiAwardState.name == "multi_award", "expected multi-award workflow state")
assert(multiAwardState.statusText == "Multi 2/3 Bob", "expected multi-award position to use pos")
```

- [ ] **Step 2: Run the focused spec and confirm the failure**

Run:

```powershell
lua tests/master_service_split_spec.lua
```

Expected failure before implementation:

```text
expected multi-award position to use pos
```

- [ ] **Step 3: Patch FlowState**

In `!KRT/Services/Master/FlowState.lua`, replace:

```lua
        local position = tonumber(multiAward and multiAward.index) or 1
```

with:

```lua
        local position = tonumber(multiAward and multiAward.pos) or tonumber(multiAward and multiAward.index) or 1
```

- [ ] **Step 4: Verify**

Run:

```powershell
lua tests/master_service_split_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected:

```text
master service split spec passed
release stabilization spec passed
```

- [ ] **Step 5: Commit**

```powershell
git add !KRT/Services/Master/FlowState.lua tests/master_service_split_spec.lua
git commit -m "fix: read multi-award progress position from service state"
```

**In-game smoke:** Start a multi-award flow for duplicate loot, award the first winner, and confirm
the Master status text advances to `2/N` for the second winner.

---

### Task 3: Add The Reserves Count Facade And Remove Slash Fallback Counting

**Files:**
- Modify: `!KRT/Services/Reserves.lua`
- Modify: `!KRT/EntryPoints/SlashEvents.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Test: `tests/release_stabilization_spec.lua`

**Problem:** `!KRT/EntryPoints/SlashEvents.lua` has a manual `_G.KRT_Reserves` counter fallback in
`countReserves()`. `!KRT/Services/Reserves.lua` already has a private `countReserves(sourceData)`
helper but does not expose `GetCounts`.

**Risk:** Low. It replaces entrypoint-local counting with the service facade while preserving the
same return shape: `players, entries`.

- [ ] **Step 1: Add service facade tests**

Append this test near the existing Reserves tests in `tests/release_stabilization_spec.lua`:

```lua
test("reserves service exposes count facade for entrypoints", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { item = "A" },
                { item = "B" },
            },
        },
        Bob = {
            reserves = {
                { item = "C" },
            },
        },
    }

    h:load("!KRT/Services/Reserves.lua")

    local players, entries = h.addon.Services.Reserves:GetCounts(_G.KRT_Reserves)
    assertEqual(players, 2, "expected reserve player count")
    assertEqual(entries, 3, "expected reserve entry count")

    players, entries = h.addon.Services.Reserves:GetCounts()
    assertEqual(players, 2, "expected default reserve player count from SavedVariables")
    assertEqual(entries, 3, "expected default reserve entry count from SavedVariables")
end)
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected failure before implementation:

```text
attempt to call method 'GetCounts'
```

- [ ] **Step 3: Add `GetCounts` to the Reserves service**

In `!KRT/Services/Reserves.lua`, after `local function countReserves(sourceData)` and before
`local function finishPerf(...)`, insert:

```lua
    function Service:GetCounts(sourceData)
        if sourceData ~= nil then
            return countReserves(sourceData)
        end
        return countReserves(KRT_Reserves)
    end
```

- [ ] **Step 4: Remove entrypoint-local SavedVariables counting**

In `!KRT/EntryPoints/SlashEvents.lua`, replace `countReserves()` with:

```lua
local function countReserves()
    local reserves = Services and Services.Reserves
    if type(reserves) == "table" and type(reserves.GetCounts) == "function" then
        return reserves:GetCounts()
    end
    return 0, 0
end
```

- [ ] **Step 5: Verify**

Run:

```powershell
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check layering
```

Expected:

```text
release stabilization spec passed
PASS
```

- [ ] **Step 6: Commit**

```powershell
git add !KRT/Services/Reserves.lua !KRT/EntryPoints/SlashEvents.lua tests/release_stabilization_spec.lua
git commit -m "refactor: expose reserves counts through service"
```

**In-game smoke:** Run `/krt bug` with imported reserves and confirm the reserve player and entry
counts still appear in the diagnostic text.

---

### Task 4: Move Duplicated Loot Source Model Construction Into LootSourceCandidates

**Files:**
- Modify: `!KRT/Modules/LootSourceCandidates.lua`
- Modify: `!KRT/Database/DBRaidQueries.lua`
- Modify: `!KRT/Services/Logger/View.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Test: `tests/release_stabilization_spec.lua`
- Test: `tests/module_registry_services_spec.lua`

**Problem:** `getLootSourceModel(loot, boss)` is duplicated exactly in
`!KRT/Database/DBRaidQueries.lua` and `!KRT/Services/Logger/View.lua`. The logic belongs in
`!KRT/Modules/LootSourceCandidates.lua`, which already owns shared-source labels and candidate
copying.

**Risk:** Medium. Query output and Logger view output must remain byte-for-byte equivalent for
shared loot sources.

- [ ] **Step 1: Add module-level model tests**

Append this test near existing loot-source tests in `tests/release_stabilization_spec.lua`:

```lua
test("loot source candidates build shared source display model", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSourceCandidates.lua")

    local modelName, modelKind, modelCandidates, sourceKey =
        h.addon.LootSourceCandidates.BuildLootSourceModel({
            lootSource = {
                kind = "shared",
                sourceName = "Shared: Marrowgar / Deathwhisper",
                sourceKey = "shared:icc-opening",
                candidates = {
                    { name = "Marrowgar", npcId = 36612, kind = "boss" },
                    { name = "Deathwhisper", npcId = 36855, kind = "boss" },
                },
            },
        }, nil)

    assertEqual(modelName, "Shared", "expected shared display label")
    assertEqual(modelKind, "shared", "expected shared source kind")
    assertEqual(sourceKey, "shared:icc-opening", "expected source key to be preserved")
    assertEqual(#modelCandidates, 2, "expected copied shared candidates")
    assertEqual(modelCandidates[1].name, "Marrowgar", "expected first shared candidate")
end)
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected failure before implementation:

```text
attempt to call field 'BuildLootSourceModel'
```

- [ ] **Step 3: Add the shared helper**

In `!KRT/Modules/LootSourceCandidates.lua`, after `function LootSourceCandidates.Copy(...)`, insert:

```lua
function LootSourceCandidates.BuildLootSourceModel(loot, boss)
    local lootSource = type(loot and loot.lootSource) == "table" and loot.lootSource or nil
    local sourceKind = (lootSource and lootSource.kind) or (boss and boss.sourceKind) or nil
    local bossName = boss and boss.name or ""
    local lootSourceName = lootSource and lootSource.sourceName or nil
    local sourceName = lootSourceName or bossName or ""
    local sourceKey = lootSource and lootSource.sourceKey or boss and boss.sourceKey or nil

    if sourceKind == "shared" or LootSourceCandidates.IsLegacySharedText(sourceName) or LootSourceCandidates.IsLegacySharedText(bossName) then
        return SHARED_SOURCE_LABEL, "shared", LootSourceCandidates.Copy(lootSource and lootSource.candidates, lootSourceName or bossName), sourceKey
    end

    return sourceName, sourceKind, nil, sourceKey
end
```

- [ ] **Step 4: Replace the DB local helper**

In `!KRT/Database/DBRaidQueries.lua`, replace the body of local `getLootSourceModel(loot, boss)`
with:

```lua
        return LootSourceCandidates.BuildLootSourceModel(loot, boss)
```

Keep the local wrapper to limit call-site churn in this task.

- [ ] **Step 5: Replace the Logger View local helper**

In `!KRT/Services/Logger/View.lua`, replace the body of local `getLootSourceModel(loot, boss)` with:

```lua
    return LootSourceCandidates.BuildLootSourceModel(loot, boss)
```

Keep the local wrapper to limit call-site churn in this task.

- [ ] **Step 6: Update module registry service expectations**

In `tests/module_registry_services_spec.lua`, update the expected deps for
`Database/DBRaidQueries` if the test still lists only:

```lua
deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBRaidStore", "Modules/Sort" }
```

Use:

```lua
deps = {
    "Init",
    "Modules/ModuleRegistry",
    "Database/DB",
    "Database/DBRaidStore",
    "Modules/Sort",
    "Modules/LootSourceCandidates",
}
```

Then add `"Modules/LootSourceCandidates"` to the registry deps in
`!KRT/Database/DBRaidQueries.lua` if the module registration does not already list it.

- [ ] **Step 7: Verify**

Run:

```powershell
lua tests/release_stabilization_spec.lua
lua tests/module_registry_services_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected:

```text
release stabilization spec passed
module registry services spec passed
PASS
```

- [ ] **Step 8: Commit**

```powershell
git add !KRT/Modules/LootSourceCandidates.lua !KRT/Database/DBRaidQueries.lua !KRT/Services/Logger/View.lua tests/release_stabilization_spec.lua tests/module_registry_services_spec.lua
git commit -m "refactor: share loot source display model helper"
```

**In-game smoke:** Open Logger history for a raid with shared loot-source rows and confirm the
source label and candidate detail remain unchanged.

---

### Task 5: Make Logger Roll Value Validation Service-Owned

**Files:**
- Modify: `!KRT/Services/Logger/Actions.lua`
- Modify: `!KRT/Controllers/Logger.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Test: `tests/release_stabilization_spec.lua`

**Problem:** `!KRT/Controllers/Logger.lua` validates roll-value popup input in
`isValidRollValue(text)`, while `!KRT/Services/Logger/Actions.lua` independently applies
`tonumber(rollValue)` inside `applyLoggerLootMutation`. The service should own the normalization
contract so controller and non-controller callers behave the same.

**Risk:** Medium. Preserve numeric string `"0"` as valid and keep negative/non-numeric values from
mutating existing roll values.

- [ ] **Step 1: Add service validation tests**

Append this test near existing Logger action tests in `tests/release_stabilization_spec.lua`:

```lua
test("logger actions normalize roll values consistently", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {},
            loot = {
                { lootNid = 100, itemLink = "[Blade]", looterNid = 1, rollType = h.rollTypes.MAINSPEC, rollValue = 44 },
            },
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 101,
        },
    })
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local ok, value = Actions:NormalizeRollValue("0")
    assertTrue(ok == true, "expected zero string to be valid")
    assertEqual(value, 0, "expected zero string to normalize to number")

    ok = Actions:SetLootEntry(1, 100, "Alice", h.rollTypes.OFFSPEC, "0", "TEST_ZERO")
    assertTrue(ok == true, "expected zero roll value update to succeed")
    assertEqual(_G.KRT_Raids[1].loot[1].rollValue, 0, "expected zero roll value to be stored")

    ok, value = Actions:NormalizeRollValue("-1")
    assertTrue(ok == false, "expected negative roll values to be rejected")
    assertEqual(value, nil, "expected rejected roll value to return nil value")
end)
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected failure before implementation:

```text
attempt to call method 'NormalizeRollValue'
```

- [ ] **Step 3: Add the service normalizer**

In `!KRT/Services/Logger/Actions.lua`, after `trimText = function(value) ... end`, insert:

```lua
function Actions:NormalizeRollValue(text)
    local value = text and tonumber(text)
    if value == nil or value < 0 then
        return false, nil
    end
    return true, value
end
```

- [ ] **Step 4: Use the normalizer inside `applyLoggerLootMutation`**

In `!KRT/Services/Logger/Actions.lua`, replace:

```lua
    if tonumber(rollValue) then
        it.rollValue = tonumber(rollValue)
        expectedRollValue = tonumber(rollValue)
    end
```

with:

```lua
    if rollValue ~= nil then
        local rollOk, normalizedRollValue = Actions:NormalizeRollValue(rollValue)
        if rollOk then
            it.rollValue = normalizedRollValue
            expectedRollValue = normalizedRollValue
        end
    end
```

- [ ] **Step 5: Replace controller-local validation**

In `!KRT/Controllers/Logger.lua`, replace:

```lua
local function isValidRollValue(text)
    local value = text and tonumber(text)
    if not value or value < 0 then
        return false
    end
    return true, value
end
```

with:

```lua
local function isValidRollValue(text)
    local Actions = Services.Logger and Services.Logger.Actions
    if Actions and Actions.NormalizeRollValue then
        return Actions:NormalizeRollValue(text)
    end
    return false, nil
end
```

- [ ] **Step 6: Verify**

Run:

```powershell
lua tests/release_stabilization_spec.lua
lua tests/controllers_cleanup_spec.lua
```

Expected:

```text
release stabilization spec passed
controllers cleanup source contract passed
```

- [ ] **Step 7: Commit**

```powershell
git add !KRT/Services/Logger/Actions.lua !KRT/Controllers/Logger.lua tests/release_stabilization_spec.lua
git commit -m "refactor: centralize logger roll value normalization"
```

**In-game smoke:** Open Logger item roll edit, enter `0`, confirm the value is accepted and stored.
Enter `-1` and a non-number, confirm the popup rejects the value as before.

---

### Task 6: Extract Spammer Preview And Store Model Into A Service

**Files:**
- Create: `!KRT/Services/Spammer.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Controllers/Spammer.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
- Test: `tests/release_stabilization_spec.lua`
- Test: `tests/module_registry_services_spec.lua`
- Test: `tests/module_registry_ui_entrypoints_spec.lua`

**Problem:** `!KRT/Controllers/Spammer.lua` owns store access, channel table creation, saved draft
model building, output formatting, preview length, and clear-store behavior. Only UI field reads,
UI locking, and Chat spam ticker calls must stay in the controller.

**Risk:** Medium. The LFM message text, length, duration, saved `KRT_Spammer` fields, and channel
selection behavior must remain unchanged.

- [ ] **Step 1: Add service tests before creating the service**

Add this test after `spammer panel preview reads the saved LFM draft` in
`tests/release_stabilization_spec.lua`:

```lua
test("spammer service builds preview and clears saved draft", function()
    local h = newHarness()
    h:load("!KRT/Services/Spammer.lua")

    _G.KRT_Spammer = {
        Name = "ICC 25",
        Duration = "60",
        Tank = "1",
        Healer = "5",
        Melee = "8",
        Ranged = "10",
        Message = "full clear",
    }

    local Spammer = h.addon.Services.Spammer
    local preview = Spammer:BuildPreview(_G.KRT_Spammer, "LFM")
    assertTextContains(preview.output, "LFM ICC 25", "expected service preview to include raid name")
    assertTextContains(preview.output, "Need", "expected service preview to include role needs")
    assertEqual(preview.duration, "60", "expected service preview to keep duration")

    local cleared = Spammer:ClearStore(_G.KRT_Spammer, "60")
    assertEqual(cleared.Duration, "60", "expected clear to restore default duration")
    assertEqual(_G.KRT_Spammer.Name, nil, "expected clear to remove raid name")
end)
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected failure before implementation:

```text
cannot open !KRT/Services/Spammer.lua
```

- [ ] **Step 3: Create `!KRT/Services/Spammer.lua`**

Create the file with this content:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Spammer
-- events: none
-- notes: owns LFM spammer SavedVariables model and preview formatting
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Services = feature.Services
local Strings = feature.Strings

feature.EnsureServiceNamespace("Spammer")
local module = Services.Spammer

local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local pairs = pairs
local type = type
local tonumber = tonumber
local tostring = tostring
local strlen = string.len

local DEFAULT_DURATION_STR = "60"
local DEFAULT_OUTPUT = "LFM"

local function getDefaultDuration(defaultDuration)
    local value = tostring(defaultDuration or DEFAULT_DURATION_STR)
    if value == "" then
        return DEFAULT_DURATION_STR
    end
    return value
end

function module:GetStore()
    if type(KRT_Spammer) ~= "table" then
        KRT_Spammer = {}
    end
    return KRT_Spammer
end

function module:GetChannels(store)
    store = store or module:GetStore()
    if type(store.Channels) ~= "table" then
        store.Channels = {}
    end
    return store.Channels
end

function module:BuildStateFromStore(store, defaultDuration)
    store = store or module:GetStore()
    return {
        name = store.Name or "",
        tank = tonumber(store.Tank) or 0,
        tankClass = store.TankClass or "",
        healer = tonumber(store.Healer) or 0,
        healerClass = store.HealerClass or "",
        melee = tonumber(store.Melee) or 0,
        meleeClass = store.MeleeClass or "",
        ranged = tonumber(store.Ranged) or 0,
        rangedClass = store.RangedClass or "",
        message = store.Message or "",
        duration = tostring(store.Duration or getDefaultDuration(defaultDuration)),
    }
end

function module:BuildOutput(state, defaultOutput)
    local baseOutput = defaultOutput or DEFAULT_OUTPUT
    local source = (type(state) == "table") and state or {}
    local outBuf = { baseOutput }

    local name = source.name or ""
    if name ~= "" then
        tinsert(outBuf, " ")
        tinsert(outBuf, name)
    end

    local needParts = {}
    local function addNeed(count, label, class)
        count = tonumber(count) or 0
        if count <= 0 then
            return
        end

        local text = count .. " " .. label
        if class and class ~= "" then
            text = text .. " (" .. class .. ")"
        end
        needParts[#needParts + 1] = text
    end

    addNeed(source.tank, L.StrTank, source.tankClass)
    addNeed(source.healer, L.StrHealer, source.healerClass)
    addNeed(source.melee, L.StrMelee, source.meleeClass)
    addNeed(source.ranged, L.StrRanged, source.rangedClass)

    if #needParts > 0 then
        tinsert(outBuf, " - ")
        tinsert(outBuf, L.StrSpammerNeedStr)
        tinsert(outBuf, " ")
        tinsert(outBuf, tconcat(needParts, ", "))
    end

    if source.message and source.message ~= "" then
        tinsert(outBuf, " - ")
        if Strings.FindAchievement then
            tinsert(outBuf, Strings.FindAchievement(source.message))
        else
            tinsert(outBuf, source.message)
        end
    end

    local output = tconcat(outBuf)
    if output == baseOutput then
        return output
    end

    local total = (tonumber(source.tank) or 0) + (tonumber(source.healer) or 0) + (tonumber(source.melee) or 0) + (tonumber(source.ranged) or 0)
    local is25 = (name ~= "" and name:match("%f[%d]25%f[%D]")) ~= nil
    local maxSize = is25 and 25 or 10
    return output .. " (" .. (maxSize - total) .. "/" .. maxSize .. ")"
end

function module:BuildPreview(store, defaultOutput, defaultDuration)
    local state = module:BuildStateFromStore(store, defaultDuration)
    local output = module:BuildOutput(state, defaultOutput)
    return {
        output = output,
        length = strlen(output),
        duration = state.duration,
    }
end

function module:ClearStore(store, defaultDuration)
    store = store or module:GetStore()
    for k, _ in pairs(store) do
        if k ~= "Channels" then
            store[k] = nil
        end
    end
    store.Duration = getDefaultDuration(defaultDuration)
    return store
end

function module:SaveField(store, target, value)
    store = store or module:GetStore()
    if target == nil or target == "" then
        return false
    end
    store[target] = value
    return true
end

function module:SetChannelChecked(store, channel, checked)
    local channels = module:GetChannels(store)
    local exists = addon.tIndexOf(channels, channel)
    if checked and not exists then
        tinsert(channels, channel)
        return true
    end
    if not checked and exists then
        local i = exists
        while i do
            tremove(channels, i)
            i = addon.tIndexOf(channels, channel)
        end
        return true
    end
    return false
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Spammer", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
        },
    })
    registry.SetLoaded("Services/Spammer")
end
```

- [ ] **Step 4: Load the service before the controller**

In `!KRT/!KRT.toc`, insert:

```text
Services\Spammer.lua
```

before:

```text
Controllers\Spammer.lua
```

- [ ] **Step 5: Register the service in registry tests**

In `tests/module_registry_services_spec.lua`, add an expected service entry:

```lua
{
    name = "Services/Spammer",
    path = "!KRT/Services/Spammer.lua",
    owner = "module",
    separator = ":",
    deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
    events = "-- events: none",
}
```

Use the same list/table pattern as existing service entries in the file.

- [ ] **Step 6: Wire the controller to the service**

In `!KRT/Controllers/Spammer.lua`, add after `local Chat = Services.Chat`:

```lua
local SpammerService = Services.Spammer
```

Add to the API block after `ChatApi`:

```lua
local SpammerApi = {
    BuildOutput = requireServiceMethod("Spammer", SpammerService, "BuildOutput"),
    BuildPreview = requireServiceMethod("Spammer", SpammerService, "BuildPreview"),
    BuildStateFromStore = requireServiceMethod("Spammer", SpammerService, "BuildStateFromStore"),
    ClearStore = requireServiceMethod("Spammer", SpammerService, "ClearStore"),
    GetChannels = requireServiceMethod("Spammer", SpammerService, "GetChannels"),
    GetStore = requireServiceMethod("Spammer", SpammerService, "GetStore"),
    SaveField = requireServiceMethod("Spammer", SpammerService, "SaveField"),
    SetChannelChecked = requireServiceMethod("Spammer", SpammerService, "SetChannelChecked"),
}
```

Replace `getSpammerStore()` with:

```lua
    local function getSpammerStore()
        return SpammerApi.GetStore(SpammerService)
    end
```

Replace `getSpammerChannels(store)` with:

```lua
    local function getSpammerChannels(store)
        return SpammerApi.GetChannels(SpammerService, store)
    end
```

Replace the body of `buildSpammerOutput(state, defaultOutput)` with:

```lua
        return SpammerApi.BuildOutput(SpammerService, state, defaultOutput)
```

Replace `buildStateFromStore(store)` with:

```lua
    local function buildStateFromStore(store)
        return SpammerApi.BuildStateFromStore(SpammerService, store, DEFAULT_DURATION_STR)
    end
```

Replace `buildPanelPreview()` with:

```lua
    local function buildPanelPreview()
        return SpammerApi.BuildPreview(SpammerService, getSpammerStore(), DEFAULT_OUTPUT, DEFAULT_DURATION_STR)
    end
```

In `saveSpammer`, replace direct channel mutation with:

```lua
            SpammerApi.SetChannelChecked(SpammerService, store, channel, checked)
```

and replace:

```lua
            store[target] = value
```

with:

```lua
            SpammerApi.SaveField(SpammerService, store, target, value)
```

In `clearSpammer`, replace the loop that clears store keys and the direct `store.Duration` write
with:

```lua
        SpammerApi.ClearStore(SpammerService, store, DEFAULT_DURATION_STR)
```

Keep UI resets, `stopSpam()`, `finalOutput`, `duration`, `loaded`, and `previewDirty` in the
controller.

- [ ] **Step 7: Update UI entrypoint registry expectations**

In `tests/module_registry_ui_entrypoints_spec.lua`, update TOC order assertions so
`Services/Spammer` is expected before `Controllers/Spammer`. Add a direct out-of-order assertion:

```lua
assertOutOfOrder("Controllers/Spammer", "Services/Spammer")
```

using the existing helper style in that file.

- [ ] **Step 8: Verify**

Run:

```powershell
lua tests/release_stabilization_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected:

```text
release stabilization spec passed
module registry services spec passed
module registry ui entrypoints spec passed
PASS
```

- [ ] **Step 9: Commit**

```powershell
git add !KRT/Services/Spammer.lua !KRT/Controllers/Spammer.lua !KRT/!KRT.toc tests/release_stabilization_spec.lua tests/module_registry_services_spec.lua tests/module_registry_ui_entrypoints_spec.lua
git commit -m "refactor: move spammer draft model to service"
```

**In-game smoke:** Open LFM Spam, edit fields, preview, start, stop, clear, and reload. Confirm
saved draft behavior, selected channels, duration, and preview text match the pre-refactor behavior.

---

### Task 7: Extract Warnings Templates, Preview, And Store Mutation Into A Service

**Files:**
- Create: `!KRT/Services/Warnings.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Controllers/Warnings.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
- Modify: `tests/controllers_cleanup_spec.lua`
- Test: `tests/release_stabilization_spec.lua`
- Test: `tests/controllers_cleanup_spec.lua`

**Problem:** `!KRT/Controllers/Warnings.lua` owns default templates, store access, preview
formatting, clear, save, delete, and template classification. The controller should keep only frame
state, row selection, editbox/panel refresh, and announce calls through `Services/Chat`.

**Risk:** Medium. Preserve in-place mutation of `KRT_Warnings`, fresh SavedVariables seeding, stock
template retention, preview text, and controller request method names.

- [ ] **Step 1: Add service tests before creating the service**

Add this test before the existing Warnings controller tests in `tests/release_stabilization_spec.lua`:

```lua
test("warnings service owns templates preview and clear policy", function()
    local h = newHarness()
    _G.KRT_Warnings = {}
    h:load("!KRT/Services/Warnings.lua")

    local Warnings = h.addon.Services.Warnings
    local result = Warnings:EnsureDefaultTemplates(_G.KRT_Warnings)
    local second = Warnings:EnsureDefaultTemplates(_G.KRT_Warnings)
    local preview = Warnings:BuildTemplatePreview(_G.KRT_Warnings, "No raid warnings configured.")

    assertEqual(result.added, 6, "expected default templates to be added")
    assertEqual(second.added, 0, "expected template install to be idempotent")
    assertEqual(#_G.KRT_Warnings, 6, "expected stock templates in SavedVariables")
    assertTextContains(preview.text, "Pull", "expected service preview to include Pull")

    table.insert(_G.KRT_Warnings, { name = "Custom", content = "Custom warning." })
    local clearResult = Warnings:ClearSavedWarnings(_G.KRT_Warnings, false)
    assertEqual(clearResult.removed, 1, "expected custom warning to be removed")
    assertEqual(clearResult.total, 6, "expected stock warnings to remain")
    assertTrue(preview.text:find("Custom", 1, true) == nil, "expected original preview text to remain immutable")
end)
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected failure before implementation:

```text
cannot open !KRT/Services/Warnings.lua
```

- [ ] **Step 3: Create `!KRT/Services/Warnings.lua`**

Create the file with this content:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Warnings
-- events: none
-- notes: owns raid-warning SavedVariables model helpers
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Services = feature.Services
local Strings = feature.Strings

feature.EnsureServiceNamespace("Warnings")
local module = Services.Warnings

local tconcat = table.concat
local tinsert = table.insert
local tremove = table.remove
local type = type
local tonumber = tonumber
local tostring = tostring
local lower = string.lower

local defaultWarningTemplates = {
    { name = "StrRaidWarningTemplatePullName", content = "StrRaidWarningTemplatePullContent", fallbackName = "Pull", fallbackContent = "Pull in 10 seconds." },
    { name = "StrRaidWarningTemplateSpreadName", content = "StrRaidWarningTemplateSpreadContent", fallbackName = "Spread", fallbackContent = "Spread out." },
    { name = "StrRaidWarningTemplateStackName", content = "StrRaidWarningTemplateStackContent", fallbackName = "Stack", fallbackContent = "Stack on marker." },
    { name = "StrRaidWarningTemplateStopName", content = "StrRaidWarningTemplateStopContent", fallbackName = "Stop DPS", fallbackContent = "Stop DPS now." },
    { name = "StrRaidWarningTemplateBloodlustName", content = "StrRaidWarningTemplateBloodlustContent", fallbackName = "Bloodlust", fallbackContent = "Use Bloodlust/Heroism now." },
    { name = "StrRaidWarningTemplateBreakName", content = "StrRaidWarningTemplateBreakContent", fallbackName = "Break", fallbackContent = "Break time. Be back soon." },
}

function module:GetStore()
    if type(KRT_Warnings) ~= "table" then
        KRT_Warnings = {}
    end
    return KRT_Warnings
end

function module:GetTemplateValue(template, key, fallbackKey)
    local value = template and L[template[key]]
    if type(value) == "string" and value ~= "" and value ~= template[key] and value ~= ("L." .. template[key]) then
        return value
    end
    return template and template[fallbackKey] or ""
end

function module:NormalizeTemplateName(value)
    local text = Strings.TrimText(value or "")
    return text ~= "" and lower(text) or nil
end

function module:IsDefaultTemplateWarning(warning)
    if type(warning) ~= "table" then
        return false
    end
    local warningName = module:NormalizeTemplateName(warning.name)
    local warningContent = tostring(warning.content or "")
    for i = 1, #defaultWarningTemplates do
        local template = defaultWarningTemplates[i]
        local templateName = module:NormalizeTemplateName(module:GetTemplateValue(template, "name", "fallbackName"))
        local templateContent = module:GetTemplateValue(template, "content", "fallbackContent")
        if warningName == templateName and warningContent == templateContent then
            return true
        end
    end
    return false
end

function module:CollectStockWarnings(warnings)
    local stock = {}
    if type(warnings) ~= "table" then
        return stock
    end
    for i = 1, #warnings do
        local warning = warnings[i]
        if module:IsDefaultTemplateWarning(warning) then
            stock[#stock + 1] = {
                name = warning.name,
                content = warning.content,
            }
        end
    end
    return stock
end

function module:EnsureDefaultTemplates(warnings)
    warnings = warnings or module:GetStore()
    local existing = {}
    for i = 1, #warnings do
        local key = module:NormalizeTemplateName(warnings[i] and warnings[i].name)
        if key then
            existing[key] = true
        end
    end

    local added = 0
    for i = 1, #defaultWarningTemplates do
        local template = defaultWarningTemplates[i]
        local name = module:GetTemplateValue(template, "name", "fallbackName")
        local key = module:NormalizeTemplateName(name)
        if key and not existing[key] then
            tinsert(warnings, {
                name = name,
                content = module:GetTemplateValue(template, "content", "fallbackContent"),
            })
            existing[key] = true
            added = added + 1
        end
    end

    return {
        added = added,
        total = #warnings,
    }
end

function module:BuildTemplatePreview(warnings, emptyText)
    warnings = warnings or module:GetStore()
    local lines = {}
    for i = 1, #warnings do
        local warning = warnings[i]
        if warning then
            lines[#lines + 1] = tostring(i) .. ". " .. tostring(warning.name or "") .. ": " .. tostring(warning.content or "")
        end
    end
    if #lines == 0 then
        lines[1] = emptyText or L.StrConfigRaidWarningPreviewEmpty or ""
    end
    return {
        text = tconcat(lines, "\n"),
        total = #warnings,
    }
end

function module:ClearSavedWarnings(warnings, includeStock)
    warnings = warnings or module:GetStore()
    local removed = #warnings
    local keptStock = includeStock == false and module:CollectStockWarnings(warnings) or nil
    for i = #warnings, 1, -1 do
        tremove(warnings, i)
    end
    if keptStock then
        for i = 1, #keptStock do
            tinsert(warnings, keptStock[i])
        end
        removed = removed - #keptStock
        if removed < 0 then
            removed = 0
        end
    end
    return {
        removed = removed,
        total = #warnings,
    }
end

function module:DeleteWarning(warnings, warningID)
    warnings = warnings or module:GetStore()
    warningID = tonumber(warningID)
    if not warningID or not warnings[warningID] then
        return false, #warnings
    end
    tremove(warnings, warningID)
    return true, #warnings
end

function module:SaveWarning(warnings, warningContent, warningName, warningID, isEdit)
    warnings = warnings or module:GetStore()
    warningID = warningID and tonumber(warningID) or 0
    warningName = Strings.TrimText(warningName)
    warningContent = Strings.TrimText(warningContent)
    if warningName == "" then
        warningName = (isEdit and warningID > 0) and warningID or (#warnings + 1)
    end
    if warningContent == "" then
        return false, nil, "empty_content"
    end
    if isEdit and warningID > 0 and warnings[warningID] ~= nil then
        warnings[warningID].name = warningName
        warnings[warningID].content = warningContent
        return true, warningID, nil
    end
    tinsert(warnings, { name = warningName, content = warningContent })
    return true, #warnings, nil
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Warnings", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
        },
    })
    registry.SetLoaded("Services/Warnings")
end
```

- [ ] **Step 4: Load the service before the controller**

In `!KRT/!KRT.toc`, insert:

```text
Services\Warnings.lua
```

before:

```text
Controllers\Warnings.lua
```

- [ ] **Step 5: Register the service in registry tests**

In `tests/module_registry_services_spec.lua`, add:

```lua
{
    name = "Services/Warnings",
    path = "!KRT/Services/Warnings.lua",
    owner = "module",
    separator = ":",
    deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
    events = "-- events: none",
}
```

- [ ] **Step 6: Wire Warnings controller to the service**

In `!KRT/Controllers/Warnings.lua`, add after `local Chat = Services.Chat`:

```lua
local WarningsService = Services.Warnings
```

Add after `ChatApi`:

```lua
local WarningsApi = {
    BuildTemplatePreview = requireServiceMethod("Warnings", WarningsService, "BuildTemplatePreview"),
    ClearSavedWarnings = requireServiceMethod("Warnings", WarningsService, "ClearSavedWarnings"),
    DeleteWarning = requireServiceMethod("Warnings", WarningsService, "DeleteWarning"),
    EnsureDefaultTemplates = requireServiceMethod("Warnings", WarningsService, "EnsureDefaultTemplates"),
    GetStore = requireServiceMethod("Warnings", WarningsService, "GetStore"),
    SaveWarning = requireServiceMethod("Warnings", WarningsService, "SaveWarning"),
}
```

Replace `getWarningsStore()` with:

```lua
    local function getWarningsStore()
        return WarningsApi.GetStore(WarningsService)
    end
```

Replace `ensureDefaultTemplates(refreshReason)` with:

```lua
    local function ensureDefaultTemplates(refreshReason)
        local result = WarningsApi.EnsureDefaultTemplates(WarningsService, getWarningsStore())
        warningsDirty = true
        fetched = false
        if refreshReason ~= false and module.RequestRefresh then
            module:RequestRefresh(refreshReason or "templates")
        end
        return result
    end
```

Replace `module:RequestTemplatePreview()` with:

```lua
    function module:RequestTemplatePreview()
        return WarningsApi.BuildTemplatePreview(WarningsService, getWarningsStore(), L.StrConfigRaidWarningPreviewEmpty or "")
    end
```

Replace `module:RequestClearSavedWarnings(includeStock)` with:

```lua
    function module:RequestClearSavedWarnings(includeStock)
        local result = WarningsApi.ClearSavedWarnings(WarningsService, getWarningsStore(), includeStock)
        resetWarningState()
        warningsDirty = true
        fetched = false
        if module.RequestRefresh then
            module:RequestRefresh("clear_saved")
        end
        return result
    end
```

Replace the mutation body of `deleteWarning(btn)` after the selected-id checks with:

```lua
        local deleted, count = WarningsApi.DeleteWarning(WarningsService, warnings, selectedID)
        if not deleted then
            selectedID = nil
            warningsDirty = true
            module:RequestRefresh()
            return
        end
        if count <= 0 then
            selectedID = nil
        elseif count == 1 then
            selectedID = 1
        elseif selectedID > count then
            selectedID = selectedID - 1
        end
        warningsDirty = true
        module:RequestRefresh()
```

Replace the persistence branch inside `saveWarning(wContent, wName, wID)` with:

```lua
        local ok, savedID, reason = WarningsApi.SaveWarning(WarningsService, warnings, wContent, wName, wID, isEdit)
        if not ok then
            if reason == "empty_content" then
                addon:error(L.StrWarningsError)
            end
            return
        end
        isEdit = false
```

Keep editbox resets, selection state, controller dirty flags, and `module:RequestRefresh()` in the
controller.

- [ ] **Step 7: Update cleanup contract after Warnings extraction**

In `tests/controllers_cleanup_spec.lua`, replace:

```lua
assertContains(warnings, "local function getWarningsStore()", "Warnings SavedVariables access must be centralized")
assertContains(warnings, "tremove(warnings, selectedID)", "Warnings delete must mutate the SavedVariables table in place")
```

with:

```lua
assertContains(warnings, "local function getWarningsStore()", "Warnings SavedVariables access must be centralized")
assertContains(warnings, "WarningsApi.DeleteWarning", "Warnings delete must delegate store mutation to the service")
```

Keep:

```lua
assertNotContains(warnings, "KRT_Warnings = oldWarnings", "Warnings delete must not replace the SavedVariables table")
```

- [ ] **Step 8: Update UI entrypoint registry expectations**

In `tests/module_registry_ui_entrypoints_spec.lua`, add a TOC order assertion:

```lua
assertOutOfOrder("Controllers/Warnings", "Services/Warnings")
```

using the existing helper style in that file.

- [ ] **Step 9: Verify**

Run:

```powershell
lua tests/release_stabilization_spec.lua
lua tests/controllers_cleanup_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected:

```text
release stabilization spec passed
controllers cleanup source contract passed
module registry services spec passed
module registry ui entrypoints spec passed
PASS
```

- [ ] **Step 10: Commit**

```powershell
git add !KRT/Services/Warnings.lua !KRT/Controllers/Warnings.lua !KRT/!KRT.toc tests/release_stabilization_spec.lua tests/controllers_cleanup_spec.lua tests/module_registry_services_spec.lua tests/module_registry_ui_entrypoints_spec.lua
git commit -m "refactor: move warning store helpers to service"
```

**In-game smoke:** Open Warnings, seed templates, save a custom warning, edit it, announce it, delete
it, clear all warnings, decline stock deletion, and reload. Confirm `KRT_Warnings` remains an array
mutated in place.

---

### Task 8: Remove Remaining Exact Clone Helpers In Low-Risk Modules

**Files:**
- Modify: `!KRT/Services/Logger/Export.lua`
- Modify: `!KRT/Services/Logger/View.lua`
- Modify: `!KRT/Services/Reserves.lua`
- Modify: `!KRT/Services/Master/AssignmentCandidates.lua`
- Modify: `!KRT/Services/Master/AssignmentTargets.lua`
- Modify: `!KRT/Modules/Dataset/LootSourcesData.lua`
- Modify: `!KRT/Modules/LootSources.lua`
- Test: `tests/release_stabilization_spec.lua`
- Test: `tests/master_service_split_spec.lua`

**Problem:** The generated function census still reports exact clones:
`startPerf`, `getClass`, and `getModeSignature`. These are not controller boundary violations, so run
this task after Tasks 1-7 are green.

**Risk:** Low to medium. This is mechanical, but it touches multiple modules and should stay in a
single small batch with no behavior changes.

- [ ] **Step 1: Confirm clone locations**

Run:

```powershell
rg -n "local function startPerf|local function getClass|local function getModeSignature" !KRT/Services !KRT/Modules
```

Expected lines include:

```text
!KRT\Services\Logger\Export.lua
!KRT\Services\Logger\View.lua
!KRT\Services\Reserves.lua
!KRT\Services\Master\AssignmentCandidates.lua
!KRT\Services\Master\AssignmentTargets.lua
!KRT\Modules\Dataset\LootSourcesData.lua
!KRT\Modules\LootSources.lua
```

- [ ] **Step 2: Extract only `getClass` into an existing Master helper**

In `!KRT/Services/Master/AssignmentCandidates.lua`, add a public helper before
`BuildRows`:

```lua
function AssignmentCandidates.GetClass(classProvider, name)
    if not classProvider or not name then
        return nil
    end
    local ok, value = pcall(classProvider, name)
    if ok then
        return value
    end
    return nil
end
```

Replace local `getClass(classProvider, name)` calls in the same file with:

```lua
AssignmentCandidates.GetClass(classProvider, name)
```

In `!KRT/Services/Master/AssignmentTargets.lua`, replace local `getClass(classProvider, name)` calls
with:

```lua
AssignmentCandidates.GetClass(classProvider, name)
```

and add this local near the top after `local AssignmentTargets = Master.AssignmentTargets ...`:

```lua
local AssignmentCandidates = Master.AssignmentCandidates
```

Update the registry deps for `Services/Master/AssignmentTargets` to include:

```lua
"Services/Master/AssignmentCandidates",
```

- [ ] **Step 3: Leave `startPerf` and `getModeSignature` for a later focused plan**

Run:

```powershell
rg -n "local function startPerf|local function getModeSignature" !KRT/Services !KRT/Modules
```

Expected: the command still reports `startPerf` and `getModeSignature`. That is accepted for this
plan because those clones are outside the controller/service boundary objective.

- [ ] **Step 4: Verify**

Run:

```powershell
lua tests/master_service_split_spec.lua
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected:

```text
master service split spec passed
release stabilization spec passed
PASS
```

- [ ] **Step 5: Commit**

```powershell
git add !KRT/Services/Master/AssignmentCandidates.lua !KRT/Services/Master/AssignmentTargets.lua
git commit -m "refactor: share master assignment class helper"
```

**In-game smoke:** Open Master assignment target flows and confirm class-colored candidate/target
rows still display the same classes.

---

### Task 9: Refresh Inventories And Run Final Gates

**Files:**
- Modify: `docs/TREE.md`
- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/FN_CLUSTERS.md`
- Test: repo checks

**Problem:** The user explicitly requested updated censuses. Generated docs must match TOC and
function inventory after service extraction.

**Risk:** Low. Generated docs can be noisy; parent review must verify only expected inventory changes
are present.

- [ ] **Step 1: Run generated-doc refresh**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

Expected:

```text
scripts complete without PowerShell errors
```

- [ ] **Step 2: Run required repo gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

```text
PASS
PASS
PASS
Lua syntax check passed
```

- [ ] **Step 3: Run focused Lua specs**

Run:

```powershell
lua tests/controllers_cleanup_spec.lua
lua tests/master_service_split_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected:

```text
controllers cleanup source contract passed
master service split spec passed
release stabilization spec passed
module registry services spec passed
module registry ui entrypoints spec passed
```

- [ ] **Step 4: Check boundary violations**

Run:

```powershell
rg -n "addon\\.Controllers|addon\\.Widgets|UI\\.Scaffold|UI\\.Widgets|CreateFrame|StaticPopup_Show|UIDropDownMenu" !KRT/Services !KRT/Modules
```

Expected: no new matches in files created or modified by Tasks 1-8. Existing unrelated matches must
be reviewed by parent before closing.

- [ ] **Step 5: Check retired controller-local helpers are gone**

Run:

```powershell
rg -n "local function buildSpammerOutput|local function getTemplateValue|local function collectStockWarnings|local function isValidRollValue|local function getLootSourceModel|multiAward and multiAward\\.index" !KRT/Controllers !KRT/Services !KRT/Database
```

Expected:

```text
no matches for controller-local Spammer, Warnings, Logger validation, duplicated loot source helper, or index-only multiAward lookup
```

- [ ] **Step 6: Review final diff**

Run:

```powershell
git diff --stat
git diff -- !KRT tests docs
```

Parent review checklist:

- Controllers still own frames, scripts, popups, editboxes, selection state, and refresh.
- Services do not reference Controllers, Widgets, frames, `addon.UI.Scaffold`, or `UI.Widgets`.
- `!KRT/!KRT.toc` loads `Services/Warnings.lua` before `Controllers/Warnings.lua` and
  `Services/Spammer.lua` before `Controllers/Spammer.lua`.
- Public controller request methods remain present.
- `KRT_Warnings` and `KRT_Spammer` tables are mutated in place and keep their existing shape.
- No vendored files or XML layout files changed.

- [ ] **Step 7: Commit generated docs**

```powershell
git add docs/TREE.md docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md
git commit -m "docs: refresh controller service inventories"
```

## Manual Smoke Checklist

Run after automated checks pass in a WotLK 3.3.5a client:

- Login with no Lua errors.
- `/krt` opens Master; Master status text updates during multi-award and roll flows.
- `/krt bug` reports reserve counts with and without imported reserves.
- Logger history opens; shared loot-source rows show the same label and candidates as before.
- Logger item roll edit accepts `0` and rejects negative/non-numeric input.
- LFM Spam preview, start, stop, channel selection, clear, and reload preserve prior behavior.
- Warnings seed stock templates, save, edit, announce, delete, clear, and reload preserve prior
  behavior.
- `/reload` keeps `KRT_Warnings`, `KRT_Spammer`, and other SavedVariables in the expected shape.

## Self-Review

Spec coverage:

- File map and responsibilities are documented in Current Structure Map.
- Controller issues are covered by Tasks 2, 5, 6, and 7.
- Service/module reuse is covered by Tasks 3, 4, 5, 6, and 7.
- Concrete refactors are split into small tasks with files, risks, commands, and in-game tests.
- Lua 5.1 and WotLK constraints are preserved by avoiding modern APIs, Ace dependencies, XML changes,
  and SavedVariables shape changes.
- Census refresh is covered by Task 9.

Placeholder scan:

- The plan contains concrete file paths, method names, code snippets, commands, and expected outputs.
- No incomplete-plan marker text is present.

Type and API consistency:

- New service public methods use colon calls on service tables.
- Existing controller request methods keep their names and return shapes.
- `Spammer:RequestPreview()` still returns `{ output, length, duration }`.
- `Warnings:RequestTemplatePreview()` still returns `{ text, total }`.
- `Warnings:RequestClearSavedWarnings(includeStock)` still returns `{ removed, total }`.
- `Reserves:GetCounts(sourceData)` returns `players, entries`.
- `Logger.Actions:NormalizeRollValue(text)` returns `ok, value`.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-06-12-controller-service-duplication-reduction.md`.
Two execution options:

1. **Subagent-Driven (recommended)** - Parent dispatches a fresh Spark implementation task per
   checklist task, then reviews and verifies each diff before continuing.
2. **Inline Execution** - Execute the checklist in this session with `superpowers:executing-plans`,
   but still use the repo-local 55to53 workflow for any complex code patch.
