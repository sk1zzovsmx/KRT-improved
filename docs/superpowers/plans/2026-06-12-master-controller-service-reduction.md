# Master Controller Service Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce `!KRT/Controllers/Master.lua` by moving non-frame Master orchestration helpers
into focused services while preserving all Master Loot, roll, trade, multi-award, and UI behavior.

**Architecture:** Keep `Controllers/Master.lua` as the owner of the parent frame lifecycle, widget
dispatch, Blizzard dropdown/popup glue, WoW forwarded handlers, and UI refresh. Add focused service
helpers for pending-award counter state and roll-announcement message planning, and move loot-window
multi-award slot/count helpers into the existing `Services/Loot` facade. All new helpers return
plans or data; the controller applies frame/UI side effects.

**Tech Stack:** World of Warcraft WotLK 3.3.5a, Interface 30300, Lua 5.1, KRT ModuleRegistry, KRT
TOC load order, repo-local Lua harness, PowerShell repo checks.

---

## 55to53 Execution Contract

Classification for implementation: `complex-orchestrated`.

Reason: this touches a controller boundary, service contracts, TOC load order, and behavior-sensitive
loot/roll/trade flows. The parent agent must not implement this plan directly. Use the repo-local
`55to53-orchestrator` workflow:

1. Parent reviews this plan and narrows the next task.
2. Parent uses `code-mapper` first if any task's call flow is unclear at execution time.
3. Parent delegates each implementation task to `spark_implementer` with closed instructions.
4. Parent reviews every diff before accepting it.
5. Parent runs the listed verification commands before closing the work.

## Boundary Rules

- `Services/Master/*` must not reference `addon.Controllers`, `addon.Widgets`, parent frames, or
  `addon.UI.Scaffold`.
- `Services/Master/*` must not call `CreateFrame`, `StaticPopup_Show`, `UIDropDownMenu_*`,
  `UI.Widgets.Call`, frame `:Show()`, frame `:Hide()`, or parent frame scripts.
- `Services/Loot/Service.lua` may use loot-window and bag APIs because it already owns loot and
  inventory runtime helpers.
- `Controllers/Master.lua` keeps `LOOT_*`, `TRADE_*`, `OPEN_MASTER_LOOT_LIST`,
  `UPDATE_MASTER_LOOT_LIST`, `UI_ERROR_MESSAGE`, popup confirmation, dropdown binding, frame
  refresh, widget calls, and button handlers.
- No SavedVariables shape changes.
- No user-facing behavior changes; do not add `!KRT/CHANGELOG.md` notes for this refactor unless a
  behavior change is intentionally introduced and approved by the parent.

## Target File Structure

Create:

```text
!KRT/Services/Master/AwardCounter.lua
!KRT/Services/Master/RollAnnouncements.lua
```

Modify:

```text
!KRT/!KRT.toc
!KRT/Controllers/Master.lua
!KRT/Services/Master/Service.lua
!KRT/Services/Loot/Service.lua
tests/master_model_services_spec.lua
tests/release_stabilization_spec.lua
docs/TREE.md
docs/FUNCTION_REGISTRY.csv
docs/FN_CLUSTERS.md
```

Do not modify:

```text
!KRT/Libs/*
!KRT/UI/*.xml
!KRT/Widgets/RaidGrid.lua
!KRT/Widgets/LootHints.lua
```

## Service Responsibilities

### `!KRT/Services/Master/AwardCounter.lua`

Owns the pending Master Loot award counter model currently embedded in
`Controllers/Master.lua` as `module._PendingCounter`.

Public facade methods added through `Services/Master/Service.lua`:

```lua
Master.EnsureAwardCounterState(state)
Master.QueueAwardCounterPending(state, opts)
Master.FindAwardCounterPendingBySlot(state, clearedSlot)
Master.RemoveAwardCounterPending(state, index, cancelTimer)
Master.ClearAwardCounterPending(state, reason, cancelTimer)
Master.FailAwardCounterPending(state, reason, cancelTimer)
Master.ConfirmAwardCounterPending(state, clearedSlot, cancelTimer)
```

The service returns pending entries or arrays of pending entries. The controller remains responsible
for:

- `module:ScheduleTimer(...)`
- `module:CancelTimer(...)`
- `addon:warn(...)`
- `addon:debug(...)`
- `Raid:AddPlayerCountForRollType(...)`
- `Loot:SetDistributionState(...)`
- `module:RequestRefresh(...)`

### `!KRT/Services/Master/RollAnnouncements.lua`

Owns the localized chat-message plan for starting MS/OS/SR/Free rolls. It does not send chat, mutate
roll state, start sessions, clear focus, or update distribution.

Public facade method:

```lua
Master.BuildRollAnnouncementPlan(opts)
```

Returned shape:

```lua
{
    message = "chat line",
    suffix = "High" or "Low",
    srList = "Alice, Bob" or nil,
}
```

### `!KRT/Services/Loot/Service.lua`

Add loot-owned helpers for remaining multi-award slot/count logic currently local to
`Controllers/Master.lua`:

```lua
function module:BuildMultiAwardSlotCandidates(itemLink)
function module:GetLootWindowItemCountByKey(itemKey)
```

These use existing `Item.GetItemStringFromLink`, `Item.GetItemIdFromLink`, `GetNumLootItems`,
`GetLootSlotLink`, and the Loot facade's current item table.

---

### Task 1: Award Counter Service Tests

**Files:**
- Modify: `tests/master_model_services_spec.lua`
- Test: `tests/master_model_services_spec.lua`

- [ ] **Step 1: Add AwardCounter test coverage**

In `tests/master_model_services_spec.lua`, add this line before loading
`!KRT/Services/Master/Service.lua`:

```lua
loadAddonFile(addon, "!KRT/Services/Master/AwardCounter.lua")
```

Append this block before the final `print("master model services spec passed")` line:

```lua

local awardState = Master.EnsureAwardCounterState()
local firstPending = Master.QueueAwardCounterPending(awardState, {
    itemLink = "[Blade]",
    itemIndex = 2,
    playerName = "Alice",
    rollType = rollTypes.MAINSPEC,
    rollValue = 98,
    sessionId = "roll-1",
    itemCount = 1,
})
assert(firstPending.itemKey == "[Blade]", "expected pending award item key")
assert(firstPending.itemIndex == 2, "expected pending award slot")
assert(firstPending.playerName == "Alice", "expected pending award player")
assert(Master.FindAwardCounterPendingBySlot(awardState, 2) == firstPending, "expected slot lookup")

local confirmed = Master.ConfirmAwardCounterPending(awardState, 2)
assert(confirmed == firstPending, "expected confirmed pending award")
assert(confirmed.counterApplied == true, "expected confirm to mark counter applied")
assert(Master.FindAwardCounterPendingBySlot(awardState, 2) == nil, "expected confirmed award removal")

Master.QueueAwardCounterPending(awardState, {
    itemLink = "[Ring]",
    itemIndex = 4,
    playerName = "Bob",
    rollType = rollTypes.OFFSPEC,
    rollValue = 77,
})
Master.QueueAwardCounterPending(awardState, {
    itemLink = "[Trinket]",
    itemIndex = 5,
    playerName = "Cara",
    rollType = rollTypes.FREE,
    rollValue = 11,
})
local failed = Master.FailAwardCounterPending(awardState, "Inventory is full.")
assert(#failed == 2, "expected all pending awards to fail")
assert(awardState.Awards[1] == nil, "expected failed awards to be cleared")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/master_model_services_spec.lua
```

Expected:

```text
cannot open !KRT/Services/Master/AwardCounter.lua
```

or:

```text
attempt to call field 'EnsureAwardCounterState'
```

- [ ] **Step 3: Commit the failing test**

```powershell
git add tests/master_model_services_spec.lua
git commit -m "test: cover master award counter service"
```

---

### Task 2: Award Counter Service Implementation

**Files:**
- Create: `!KRT/Services/Master/AwardCounter.lua`
- Modify: `!KRT/Services/Master/Service.lua`
- Modify: `!KRT/!KRT.toc`
- Test: `tests/master_model_services_spec.lua`

- [ ] **Step 1: Create `AwardCounter.lua`**

Create `!KRT/Services/Master/AwardCounter.lua` with this content:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master.AwardCounter
-- events: none
-- notes: pure Master pending-award counter model helpers
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local AwardCounter = Master.AwardCounter or {}
Master.AwardCounter = AwardCounter

local Item = feature.Item

local tinsert = table.insert
local tremove = table.remove
local tostring = tostring
local tonumber = tonumber
local type = type

-- ----- Internal state ----- --

-- ----- Private helpers ----- --
local function ensureState(state)
    if type(state) ~= "table" then
        state = {}
    end
    state.Awards = state.Awards or {}
    return state
end

local function getItemKey(itemLink)
    if Item and Item.GetItemStringFromLink then
        return Item.GetItemStringFromLink(itemLink) or itemLink
    end
    return itemLink
end

local function cancelPending(pending, cancelTimer)
    if pending and pending.timeoutHandle and type(cancelTimer) == "function" then
        cancelTimer(pending.timeoutHandle)
        pending.timeoutHandle = nil
    end
end

-- ----- Public methods ----- --

function AwardCounter.EnsureState(state)
    return ensureState(state)
end

function AwardCounter.Queue(state, opts)
    state = ensureState(state)
    opts = opts or {}
    local pending = {
        itemLink = opts.itemLink,
        itemKey = getItemKey(opts.itemLink),
        itemIndex = tonumber(opts.itemIndex) or opts.itemIndex,
        playerName = opts.playerName,
        rollType = opts.rollType,
        rollValue = opts.rollValue,
        rollSessionId = opts.sessionId and tostring(opts.sessionId) or nil,
        itemCount = tonumber(opts.itemCount) or 1,
        counterApplied = false,
    }
    if pending.itemCount < 1 then
        pending.itemCount = 1
    end
    tinsert(state.Awards, pending)
    return pending
end

function AwardCounter.Remove(state, index, cancelTimer)
    state = ensureState(state)
    local awards = state.Awards
    local pending = awards[index]
    cancelPending(pending, cancelTimer)
    if pending then
        awards[index] = nil
        tremove(awards, index)
    end
    return pending
end

function AwardCounter.Clear(state, reason, cancelTimer)
    state = ensureState(state)
    local removed = {}
    for i = #state.Awards, 1, -1 do
        local pending = AwardCounter.Remove(state, i, cancelTimer)
        if pending then
            pending.clearReason = reason
            removed[#removed + 1] = pending
        end
    end
    return removed
end

function AwardCounter.FindBySlot(state, clearedSlot)
    state = ensureState(state)
    local slot = tonumber(clearedSlot)
    for i = 1, #state.Awards do
        local pending = state.Awards[i]
        if pending and pending.failed ~= true and pending.counterApplied ~= true then
            if not slot or tonumber(pending.itemIndex) == slot then
                return pending, i
            end
        end
    end
    return nil, nil
end

function AwardCounter.HasPending(state)
    state = ensureState(state)
    return state.Awards[1] ~= nil
end

function AwardCounter.Fail(state, reason, cancelTimer)
    state = ensureState(state)
    local failed = {}
    for i = #state.Awards, 1, -1 do
        local pending = AwardCounter.Remove(state, i, cancelTimer)
        if pending then
            pending.failed = true
            pending.failureReason = reason
            failed[#failed + 1] = pending
        end
    end
    return failed
end

function AwardCounter.Confirm(state, clearedSlot, cancelTimer)
    local pending, index = AwardCounter.FindBySlot(state, clearedSlot)
    if not pending then
        return nil
    end
    pending.counterApplied = true
    AwardCounter.Remove(state, index, cancelTimer)
    return pending
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/AwardCounter", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Item",
        },
    })
    registry.SetLoaded("Services/Master/AwardCounter")
end
```

- [ ] **Step 2: Expose AwardCounter through the Master facade**

In `!KRT/Services/Master/Service.lua`, add this local near the existing locals:

```lua
local AwardCounter = Master.AwardCounter
```

Add these facade functions before the registry block:

```lua
function Master.EnsureAwardCounterState(state)
    return AwardCounter.EnsureState(state)
end

function Master.QueueAwardCounterPending(state, opts)
    return AwardCounter.Queue(state, opts)
end

function Master.FindAwardCounterPendingBySlot(state, clearedSlot)
    return AwardCounter.FindBySlot(state, clearedSlot)
end

function Master.RemoveAwardCounterPending(state, index, cancelTimer)
    return AwardCounter.Remove(state, index, cancelTimer)
end

function Master.ClearAwardCounterPending(state, reason, cancelTimer)
    return AwardCounter.Clear(state, reason, cancelTimer)
end

function Master.FailAwardCounterPending(state, reason, cancelTimer)
    return AwardCounter.Fail(state, reason, cancelTimer)
end

function Master.ConfirmAwardCounterPending(state, clearedSlot, cancelTimer)
    return AwardCounter.Confirm(state, clearedSlot, cancelTimer)
end

function Master.HasAwardCounterPending(state)
    return AwardCounter.HasPending(state)
end
```

Add `"Services/Master/AwardCounter"` to the `deps` table in the same file.

- [ ] **Step 3: Add the service to TOC load order**

In `!KRT/!KRT.toc`, add this line after `Services\Master\LootSpam.lua` and before
`Services\Master\Service.lua`:

```text
Services\Master\AwardCounter.lua
```

- [ ] **Step 4: Verify the service load order in the model spec**

Confirm this line appears before `loadAddonFile(addon, "!KRT/Services/Master/Service.lua")`:

```lua
loadAddonFile(addon, "!KRT/Services/Master/AwardCounter.lua")
```

- [ ] **Step 5: Run the focused test**

Run:

```powershell
lua tests/master_model_services_spec.lua
```

Expected:

```text
master model services spec passed
```

- [ ] **Step 6: Commit AwardCounter implementation**

```powershell
git add !KRT/Services/Master/AwardCounter.lua !KRT/Services/Master/Service.lua !KRT/!KRT.toc tests/master_model_services_spec.lua
git commit -m "refactor: add master award counter service"
```

---

### Task 3: Wire Master PendingCounter To AwardCounter

**Files:**
- Modify: `!KRT/Controllers/Master.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Replace `_PendingCounter` state initialization**

In `!KRT/Controllers/Master.lua`, replace:

```lua
module._PendingCounter = module._PendingCounter or { Awards = {} }
```

with:

```lua
module._PendingCounter = MasterService.EnsureAwardCounterState(module._PendingCounter)
```

- [ ] **Step 2: Replace `_PendingCounter` methods with thin controller wrappers**

Replace the method block from `function module._PendingCounter:CancelAward(pending)` through
`function module._PendingCounter:Queue(...)` with this controller-owned wrapper block:

```lua
    function module._PendingCounter:CancelAward(pending)
        if pending and pending.timeoutHandle then
            module:CancelTimer(pending.timeoutHandle)
            pending.timeoutHandle = nil
        end
    end

    function module._PendingCounter:Remove(index)
        return MasterService.RemoveAwardCounterPending(self, index, function(handle)
            module:CancelTimer(handle)
        end)
    end

    function module._PendingCounter:Clear(reason)
        local removed = MasterService.ClearAwardCounterPending(self, reason, function(handle)
            module:CancelTimer(handle)
        end)
        for i = 1, #removed do
            local pending = removed[i]
            if pending and addon.hasDebug then
                addon:debug(Diag.W.LogMLAwardCounterFailed:format(tostring(pending.itemLink), tostring(pending.playerName), tostring(reason or "clear")))
            end
        end
    end

    function module._PendingCounter:FindBySlot(clearedSlot)
        return MasterService.FindAwardCounterPendingBySlot(self, clearedSlot)
    end

    function module._PendingCounter:HasPending()
        return MasterService.HasAwardCounterPending(self)
    end

    function module._PendingCounter:IsFailureMessage(message)
        return Loot:IsMasterLootAwardFailureMessage(message)
    end

    function module._PendingCounter:Fail(reason)
        local failed = MasterService.FailAwardCounterPending(self, reason, function(handle)
            module:CancelTimer(handle)
        end)
        for i = 1, #failed do
            local pending = failed[i]
            addon:warn(Diag.W.LogMLAwardCounterFailed:format(tostring(pending.itemLink), tostring(pending.playerName), tostring(reason or "unknown")))
        end
        return failed[1] ~= nil
    end

    function module._PendingCounter:Confirm(clearedSlot, source)
        local pending = MasterService.ConfirmAwardCounterPending(self, clearedSlot, function(handle)
            module:CancelTimer(handle)
        end)
        if not pending then
            return false
        end

        Raid:AddPlayerCountForRollType(pending.playerName, pending.rollType, pending.itemCount or 1, Database.GetCurrentRaid())
        if addon.hasDebug then
            addon:debug(
                Diag.D.LogMLAwardCounterConfirmed:format(tostring(pending.itemLink), tostring(pending.playerName), tonumber(pending.rollType) or -1, tostring(source or "unknown"))
            )
        end
        updateLootDistribution("item_done", {
            itemLink = pending.itemLink,
            winnerName = pending.playerName,
        })
        return true
    end

    function module._PendingCounter:Queue(itemLink, itemIndex, playerName, rollType, rollValue, sessionId)
        local pending = MasterService.QueueAwardCounterPending(self, {
            itemLink = itemLink,
            itemIndex = itemIndex,
            playerName = playerName,
            rollType = rollType,
            rollValue = rollValue,
            sessionId = sessionId,
            itemCount = 1,
        })

        local timeout = tonumber(C.ML_AWARD_CONFIRM_TIMEOUT_SECONDS) or 4
        if timeout > 0 then
            local owner = self
            pending.timeoutHandle = module:ScheduleTimer(function()
                local awards = owner.Awards
                for i = #awards, 1, -1 do
                    if awards[i] == pending then
                        owner:Remove(i)
                        addon:warn(Diag.W.LogMLAwardCounterTimeout:format(timeout, tostring(pending.itemLink), tostring(pending.playerName), tostring(pending.itemIndex or "?")))
                        module:RequestRefresh()
                        return
                    end
                end
            end, timeout)
        end
        return pending
    end
```

- [ ] **Step 3: Run the release stabilization spec**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected:

```text
release stabilization spec passed
```

- [ ] **Step 4: Run focused model tests**

Run:

```powershell
lua tests/master_model_services_spec.lua
lua tests/master_service_split_spec.lua
```

Expected:

```text
master model services spec passed
master service split spec passed
```

- [ ] **Step 5: Commit controller wiring**

```powershell
git add !KRT/Controllers/Master.lua
git commit -m "refactor: delegate master pending counter model"
```

---

### Task 4: Roll Announcement Plan Tests

**Files:**
- Modify: `tests/master_model_services_spec.lua`
- Test: `tests/master_model_services_spec.lua`

- [ ] **Step 1: Add localized strings to the test harness**

In `tests/master_model_services_spec.lua`, add these strings inside the existing `feature.L` table:

```lua
ChatRollMS = "MS roll %s",
ChatRollMSMultipleHigh = "MS roll high %s x%d",
ChatRollMSMultipleLow = "MS roll low %s x%d",
ChatRollSR = "SR roll %s for %s",
ChatRollSRMultipleHigh = "SR roll high %s for %s x%d",
ChatRollSRMultipleLow = "SR roll low %s for %s x%d",
```

- [ ] **Step 2: Add RollAnnouncements test coverage**

In `tests/master_model_services_spec.lua`, add this line before loading
`!KRT/Services/Master/Service.lua`:

```lua
loadAddonFile(addon, "!KRT/Services/Master/RollAnnouncements.lua")
```

Append this block before the final `print("master model services spec passed")` line:

```lua

local msPlan = Master.BuildRollAnnouncementPlan({
    itemLink = "[Blade]",
    rollType = rollTypes.MAINSPEC,
    chatKey = "ChatRollMS",
    selectedItemCount = 2,
    sortAscending = false,
})
assert(msPlan.message == "MS roll high [Blade] x2", "expected high multi MS roll message")
assert(msPlan.suffix == "High", "expected descending roll suffix")

local srPlan = Master.BuildRollAnnouncementPlan({
    itemLink = "[Ring]",
    rollType = rollTypes.RESERVED,
    chatKey = "ChatRollSR",
    selectedItemCount = 1,
    sortAscending = true,
    srList = "Alice, Bob",
})
assert(srPlan.message == "SR roll Alice, Bob for [Ring]", "expected SR list in roll message")
assert(srPlan.srList == "Alice, Bob", "expected SR list to be returned")
```

- [ ] **Step 3: Run the test and verify it fails**

Run:

```powershell
lua tests/master_model_services_spec.lua
```

Expected:

```text
cannot open !KRT/Services/Master/RollAnnouncements.lua
```

or:

```text
attempt to call field 'BuildRollAnnouncementPlan'
```

- [ ] **Step 4: Commit the failing test**

```powershell
git add tests/master_model_services_spec.lua
git commit -m "test: cover master roll announcement plans"
```

---

### Task 5: Roll Announcement Service Implementation

**Files:**
- Create: `!KRT/Services/Master/RollAnnouncements.lua`
- Modify: `!KRT/Services/Master/Service.lua`
- Modify: `!KRT/!KRT.toc`
- Test: `tests/master_model_services_spec.lua`

- [ ] **Step 1: Create `RollAnnouncements.lua`**

Create `!KRT/Services/Master/RollAnnouncements.lua` with this content:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master.RollAnnouncements
-- events: none
-- notes: pure Master roll-announcement chat message plans
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local RollAnnouncements = Master.RollAnnouncements or {}
Master.RollAnnouncements = RollAnnouncements

local L = feature.L
local rollTypes = feature.rollTypes

local tonumber = tonumber
local type = type

-- ----- Internal state ----- --

-- ----- Private helpers ----- --
local function getSuffix(sortAscending)
    if sortAscending == true then
        return "Low"
    end
    return "High"
end

local function getTemplate(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return L[key]
end

-- ----- Public methods ----- --

function RollAnnouncements.BuildPlan(opts)
    opts = opts or {}
    local itemLink = opts.itemLink
    local chatKey = opts.chatKey
    local selectedItemCount = tonumber(opts.selectedItemCount) or 1
    local suffix = getSuffix(opts.sortAscending)
    local message

    if selectedItemCount < 1 then
        selectedItemCount = 1
    end

    if opts.rollType == rollTypes.RESERVED then
        local srList = opts.srList or ""
        if selectedItemCount > 1 then
            message = getTemplate(chatKey .. "Multiple" .. suffix):format(srList, itemLink, selectedItemCount)
        else
            message = getTemplate(chatKey):format(srList, itemLink)
        end
        return {
            message = message,
            srList = srList,
            suffix = suffix,
        }
    end

    if selectedItemCount > 1 then
        message = getTemplate(chatKey .. "Multiple" .. suffix):format(itemLink, selectedItemCount)
    else
        message = getTemplate(chatKey):format(itemLink)
    end
    return {
        message = message,
        suffix = suffix,
    }
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/RollAnnouncements", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
        },
    })
    registry.SetLoaded("Services/Master/RollAnnouncements")
end
```

- [ ] **Step 2: Expose RollAnnouncements through the Master facade**

In `!KRT/Services/Master/Service.lua`, add this local near the existing locals:

```lua
local RollAnnouncements = Master.RollAnnouncements
```

Add this facade function before the registry block:

```lua
function Master.BuildRollAnnouncementPlan(opts)
    return RollAnnouncements.BuildPlan(opts)
end
```

Add `"Services/Master/RollAnnouncements"` to the `deps` table in the same file.

- [ ] **Step 3: Add the service to TOC load order**

In `!KRT/!KRT.toc`, add this line after `Services\Master\AwardCounter.lua` and before
`Services\Master\Service.lua`:

```text
Services\Master\RollAnnouncements.lua
```

- [ ] **Step 4: Verify the service load order in the model spec**

Confirm this line appears before `loadAddonFile(addon, "!KRT/Services/Master/Service.lua")`:

```lua
loadAddonFile(addon, "!KRT/Services/Master/RollAnnouncements.lua")
```

- [ ] **Step 5: Run the focused test**

Run:

```powershell
lua tests/master_model_services_spec.lua
```

Expected:

```text
master model services spec passed
```

- [ ] **Step 6: Commit RollAnnouncements implementation**

```powershell
git add !KRT/Services/Master/RollAnnouncements.lua !KRT/Services/Master/Service.lua !KRT/!KRT.toc tests/master_model_services_spec.lua
git commit -m "refactor: add master roll announcement service"
```

---

### Task 6: Wire `announceRoll` To RollAnnouncement Plans

**Files:**
- Modify: `!KRT/Controllers/Master.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Replace local message construction in `announceRoll`**

In `!KRT/Controllers/Master.lua`, inside `local function announceRoll(rollType, chatMsg)`, replace
the local `message` construction block with this code:

```lua
            local srList = nil
            if rollType == rollTypes.RESERVED then
                local reserves = Services.Reserves
                srList = reserves and reserves.FormatReservedPlayersLine and reserves:FormatReservedPlayersLine(itemID, false, false, false, true) or ""
            end

            local plan = MasterService.BuildRollAnnouncementPlan({
                chatKey = chatMsg,
                itemLink = itemLink,
                rollType = rollType,
                selectedItemCount = lootState.selectedItemCount,
                sortAscending = GetOption("Master", "sortAscending") == true,
                srList = srList,
            })
            local message = plan and plan.message or nil
```

Keep the existing `ChatApi.Announce(Chat, message)` call below this block.

- [ ] **Step 2: Run roll behavior tests**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected:

```text
release stabilization spec passed
```

- [ ] **Step 3: Run focused service tests**

Run:

```powershell
lua tests/master_model_services_spec.lua
lua tests/master_service_split_spec.lua
```

Expected:

```text
master model services spec passed
master service split spec passed
```

- [ ] **Step 4: Commit controller announcement wiring**

```powershell
git add !KRT/Controllers/Master.lua
git commit -m "refactor: delegate master roll announcement planning"
```

---

### Task 7: Loot Multi-Award Helper Tests

**Files:**
- Modify: `tests/release_stabilization_spec.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add Loot helper assertions near existing Loot multi-award tests**

In `tests/release_stabilization_spec.lua`, near the existing assertions for
`BuildMultiAwardState`, add this test block:

```lua
do
    local h = newHarness()
    local Loot = h.addon.Services.Loot
    local itemLink = "|cffa335ee|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r"

    _G.GetNumLootItems = function()
        return 3
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return itemLink
        end
        if slot == 2 then
            return "|cffa335ee|Hitem:19019:1:0:0:0:0:0:0|h[Thunderfury]|h|r"
        end
        return "|cffa335ee|Hitem:18803:0:0:0:0:0:0:0|h[Finkle's Lava Dredger]|h|r"
    end

    local slots, slotMap = Loot:BuildMultiAwardSlotCandidates(itemLink)
    assertEqual(#slots, 2, "expected matching multi-award loot slots")
    assertTrue(slotMap[1] == true, "expected first slot in map")
    assertTrue(slotMap[2] == true, "expected second matching item id in map")

    Loot:AddItem(itemLink, 4)
    local itemKey = h.addon.Item.GetItemStringFromLink(itemLink) or itemLink
    assertEqual(Loot:GetLootWindowItemCountByKey(itemKey), 4, "expected current item count by item key")
end
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected:

```text
attempt to call method 'BuildMultiAwardSlotCandidates'
```

or:

```text
attempt to call method 'GetLootWindowItemCountByKey'
```

- [ ] **Step 3: Commit the failing test**

```powershell
git add tests/release_stabilization_spec.lua
git commit -m "test: cover loot multi-award slot helpers"
```

---

### Task 8: Implement Loot Multi-Award Helpers And Wire Master

**Files:**
- Modify: `!KRT/Services/Loot/Service.lua`
- Modify: `!KRT/Controllers/Master.lua`
- Test: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add helper functions to `Services/Loot/Service.lua`**

In `!KRT/Services/Loot/Service.lua`, add these local helpers near `findLootSlotIndex`:

```lua
    local function buildMultiAwardSlotCandidates(itemLink)
        local slots = {}
        local slotMap = {}
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        local wantedId = Item.GetItemIdFromLink(itemLink)
        for slot = 1, (GetNumLootItems() or 0) do
            local link = GetLootSlotLink(slot)
            if link then
                local slotKey = Item.GetItemStringFromLink(link) or link
                local slotId = Item.GetItemIdFromLink(link)
                if slotKey == wantedKey or (wantedId and slotId and slotId == wantedId) then
                    slots[#slots + 1] = slot
                    slotMap[slot] = true
                end
            end
        end
        return slots, slotMap
    end

    local function getLootWindowItemCountByKey(itemKey)
        local currentCount = 0
        for i = 1, (lootState.lootCount or 0) do
            local it = getItem(i)
            if it and it.itemKey == itemKey then
                currentCount = tonumber(it.count) or 1
                break
            end
        end
        return currentCount
    end
```

- [ ] **Step 2: Expose helper methods through the Loot facade**

Near the existing public helper methods at the bottom of `Services/Loot/Service.lua`, add:

```lua
    function module:BuildMultiAwardSlotCandidates(itemLink)
        return buildMultiAwardSlotCandidates(itemLink)
    end

    function module:GetLootWindowItemCountByKey(itemKey)
        return getLootWindowItemCountByKey(itemKey)
    end
```

- [ ] **Step 3: Replace duplicate helpers in `Controllers/Master.lua`**

In `!KRT/Controllers/Master.lua`, replace the body of `buildMultiAwardSlotCandidates(itemLink)` with:

```lua
        return Loot:BuildMultiAwardSlotCandidates(itemLink)
```

Replace the body of `getCurrentMultiAwardCount(itemKey)` with:

```lua
        return Loot:GetLootWindowItemCountByKey(itemKey)
```

- [ ] **Step 4: Run the release stabilization spec**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected:

```text
release stabilization spec passed
```

- [ ] **Step 5: Run syntax checks**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

```text
Lua syntax check passed
```

- [ ] **Step 6: Commit Loot helper extraction**

```powershell
git add !KRT/Services/Loot/Service.lua !KRT/Controllers/Master.lua tests/release_stabilization_spec.lua
git commit -m "refactor: move multi-award loot helpers to loot service"
```

---

### Task 9: Module Registry, Generated Docs, And Final Verification

**Files:**
- Modify: `docs/TREE.md`
- Modify: `docs/FUNCTION_REGISTRY.csv`
- Modify: `docs/FN_CLUSTERS.md`
- Test: repo checks

- [ ] **Step 1: Run TOC and registry checks**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
lua tests/module_registry_services_spec.lua
```

Expected:

```text
PASS
module registry services spec passed
```

- [ ] **Step 2: Run Lua uniformity and hardening checks**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
```

Expected:

```text
PASS
PASS
```

- [ ] **Step 3: Run release stabilization and focused specs**

Run:

```powershell
lua tests/master_model_services_spec.lua
lua tests/master_service_split_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected:

```text
master model services spec passed
master service split spec passed
release stabilization spec passed
```

- [ ] **Step 4: Update generated docs**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

Expected:

```text
docs updated without script errors
```

- [ ] **Step 5: Inspect public surface changes**

Run:

```powershell
rg -n "Master\\.EnsureAwardCounterState|Master\\.BuildRollAnnouncementPlan|BuildMultiAwardSlotCandidates|GetLootWindowItemCountByKey" !KRT docs tests
```

Expected:

```text
!KRT\Services\Master\Service.lua
!KRT\Services\Loot\Service.lua
!KRT\Controllers\Master.lua
tests\master_model_services_spec.lua
tests\release_stabilization_spec.lua
docs\FUNCTION_REGISTRY.csv
```

- [ ] **Step 6: Run final syntax check**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

```text
Lua syntax check passed
```

- [ ] **Step 7: Review the final diff**

Run:

```powershell
git diff -- !KRT/Controllers/Master.lua !KRT/Services/Master !KRT/Services/Loot/Service.lua !KRT/!KRT.toc tests docs
```

Review requirements:

- `Controllers/Master.lua` still owns frame, widget, popup, dropdown, and WoW event behavior.
- No service references `addon.Controllers`, `addon.Widgets`, `UI.Widgets`, `UI.Scaffold`, or frames.
- No SavedVariables keys or schema changed.
- `!KRT/!KRT.toc` loads new `Services/Master/*` files before `Services/Master/Service.lua`.
- No XML files changed.
- No vendored files changed.

- [ ] **Step 8: Commit generated docs and verification pass**

```powershell
git add docs/TREE.md docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md
git commit -m "docs: refresh master service reduction inventories"
```

## Manual Smoke Checklist

Run these in a WotLK 3.3.5a client after automated checks pass:

- Login with no Lua errors.
- `/krt` opens the Master frame.
- Loot window opens and shows loot items.
- MS, OS, SR, and Free roll announcements match previous text.
- Countdown start, stop, and finalize behavior matches previous behavior.
- Awarding one item from Master Loot increments the correct counter once.
- Multi-award of identical loot-window items awards each selected winner once.
- Inventory trade to another player still starts trade and logs the final award.
- Inventory self-keep still logs the final award.
- Hold, Bank, and Disenchant targets still work from dropdowns and raid grid.
- `/reload` preserves expected SavedVariables and runtime state resets.

## Self-Review

Spec coverage:

- Pending award counter extraction is covered by Tasks 1-3.
- Roll announcement planning is covered by Tasks 4-6.
- Multi-award loot helper reuse is covered by Tasks 7-8.
- Repo checks, generated docs, and manual smoke are covered by Task 9.

Placeholder scan:

- The plan contains concrete file paths, method names, code snippets, commands, and expected outputs.

Type consistency:

- Facade methods use `Master.*` dot functions.
- Loot facade helpers use colon methods because `Services/Loot/Service.lua` exposes public service
  behavior on `module`.
- Controller wrappers preserve the existing `module._PendingCounter:*` call style.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-12-master-controller-service-reduction.md`.
Two execution options:

1. **Subagent-Driven (recommended)** - Parent dispatches a fresh implementation agent per task and
   reviews between tasks.
2. **Inline Execution** - Execute tasks in this session using `superpowers:executing-plans`, with
   review checkpoints.
