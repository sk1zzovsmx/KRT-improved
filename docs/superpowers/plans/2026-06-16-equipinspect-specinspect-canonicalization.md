# EquipInspect SpecInspect Canonicalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the equipment snapshot service to `EquipInspect` and make `SpecInspect` the canonical owner of talent/spec deduction, including secondary talent group capture.

**Architecture:** `addon.Services.EquipInspect` owns inspect queueing, `NotifyInspect`, equipment slots, average item level, timeout/retry state, and persisted raid attendance equipment snapshots. `addon.Services.SpecInspect` owns all talent/spec interpretation through `LibGroupTalents-1.0`, including active group, second group, spec icons, and active-display compatibility fields. Equipment snapshots may persist a copy of the `SpecInspect` talent snapshot for historical raid attendance, but they must not compute spec directly.

**Tech Stack:** WoW 3.3.5a Interface 30300, Lua 5.1, KRT service architecture, `LibGroupTalents-1.0`, `LibTalentQuery-1.0` only through `LibGroupTalents`, repo-local Lua source-contract tests.

---

## File Structure

- Rename: `!KRT/Services/RaidInspect.lua` -> `!KRT/Services/EquipInspect.lua`
  - Owns equipment inspect queue, current-raid gating, gear collection, avg item level, runtime statuses, and `NotifyInspect`.
  - Uses `Services.SpecInspect` for talent/spec data instead of calling `GetTalentTabInfo`.
- Modify: `!KRT/Services/SpecInspect.lua`
  - Adds canonical grouped talent snapshot API backed by `LibGroupTalents-1.0`.
  - Keeps `GetPlayerSpecSnapshot(name)` compatible for existing active-spec UI.
- Modify: `!KRT/Modules/Events.lua`
  - Rename internal event constants from `RaidInspect*` to `EquipInspect*`.
- Modify: `!KRT/!KRT.toc`
  - Load `Services\EquipInspect.lua` after `Services\SpecInspect.lua` and before `Services\Chat.lua`.
- Modify: `!KRT/Services/Logger/View.lua`
  - Read equipment snapshots through `Services.EquipInspect`, with persisted `raid.inspect` fallback.
- Modify: `!KRT/Controllers/Logger.lua`
  - Call `Services.EquipInspect:ForcePlayer(...)`.
  - Listen to `InternalEvents.EquipInspectUpdated` and `InternalEvents.EquipInspectCompleted`.
- Modify: `tests/spec_inspect_service_spec.lua`
  - Add failing tests for active + secondary talent groups.
- Rename/modify: `tests/raid_inspect_source_contract_spec.lua` -> `tests/equip_inspect_source_contract_spec.lua`
  - Enforce new service naming and no talent deduction in `EquipInspect`.
- Rename/modify: `tests/raid_inspect_service_spec.lua` -> `tests/equip_inspect_service_spec.lua`
  - Keep equipment queue behavior and assert spec metadata is copied from `SpecInspect`.
- Modify: `tests/module_registry_services_spec.lua`
  - Rename expected service registry contract to `Services/EquipInspect`.
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
  - Rename UI entrypoint registry coverage from `RaidInspect` to `EquipInspect`.
- Modify: `tests/logger_visual_refresh_spec.lua`
  - Update service/event strings used by Logger visual source contract.
- Modify: `docs/RAID_SCHEMA.md`
  - Rename the documented model to `EquipInspectSnapshot`, stored under the existing `raid.inspect` key.
- Modify: `docs/OVERVIEW.md`, `docs/ARCHITECTURE.md`, `docs/TREE.md`
  - Update service ownership wording and file tree.
- Modify: `!KRT/CHANGELOG.md`
  - Add one `## Unreleased` fix/architecture bullet.
- Generated: `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`, possibly `docs/TREE.md`
  - Refresh using repo tooling after source changes.

## Persisted Data Policy

Keep the persisted key `raid.inspect` for this wave. It already stores raid attendance inspect snapshots and changing it would require migration. Rename service/API/events to `EquipInspect`, but document the storage key as:

```markdown
## EquipInspectSnapshot (`raid.inspect`)
```

Existing historical snapshots with `specName`, `specIcon`, and `mainTalentTree` must still render. New snapshots may add:

```lua
talentSnapshot = {
    activeGroup = 1,
    numGroups = 2,
    groups = {
        [1] = {
            group = 1,
            specName = "Feral Combat",
            specIcon = "Interface\\Icons\\ability_druid_catform",
            mainTalentTree = 2,
            points = { 0, 55, 16 },
        },
        [2] = {
            group = 2,
            specName = "Restoration",
            specIcon = "Interface\\Icons\\spell_nature_healingtouch",
            mainTalentTree = 3,
            points = { 11, 0, 60 },
        },
    },
}
```

For UI compatibility, new equipment snapshots should also keep top-level active display fields:

```lua
specName = talentSnapshot.specName
specIcon = talentSnapshot.icon
mainTalentTree = talentSnapshot.mainTalentTree
secondarySpecName = talentSnapshot.secondarySpecName
secondarySpecIcon = talentSnapshot.secondaryIcon
```

---

### Task 1: Add Failing SpecInspect Group Snapshot Tests

**Files:**
- Modify: `tests/spec_inspect_service_spec.lua`

- [ ] **Step 1: Update fake LibGroupTalents to accept group arguments**

Replace the existing `fakeLGT:GetUnitTalentSpec` and `fakeLGT:GetTalentTabInfo` helpers with grouped versions:

```lua
function fakeLGT:GetActiveTalentGroup(unit)
    local row = self.snapshots[unit]
    return row and row.activeGroup or nil
end

function fakeLGT:GetNumTalentGroups(unit)
    local row = self.snapshots[unit]
    return row and row.numGroups or nil
end

function fakeLGT:GetUnitTalentSpec(unit, group)
    local row = self.snapshots[unit]
    if row and row.raiseTalentError then
        error("talent read failed")
    end
    if not row then
        return nil
    end

    local groupIndex = tonumber(group) or tonumber(row.activeGroup) or 1
    local groupData = row.groups and row.groups[groupIndex] or row
    if not groupData then
        return nil
    end
    return groupData.specName, groupData.t1 or 0, groupData.t2 or 0, groupData.t3 or 0
end

function fakeLGT:GetTalentTabInfo(unit, tab, group)
    local row = self.snapshots[unit]
    if not row then
        return nil
    end

    local groupIndex = tonumber(group) or tonumber(row.activeGroup) or 1
    local groupData = row.groups and row.groups[groupIndex] or row
    if not groupData or not groupData.tabs then
        return nil
    end

    local data = groupData.tabs[tab]
    if not data then
        return nil
    end
    return data.name, data.icon, data.points or 0, data.background
end
```

- [ ] **Step 2: Replace Alice fixture with two talent groups**

Replace the current `fakeLGT.snapshots.raid1` assignment with:

```lua
fakeLGT.snapshots.raid1 = {
    activeGroup = 1,
    numGroups = 2,
    role = "tank",
    groups = {
        [1] = {
            specName = "Feral Combat",
            t1 = 0,
            t2 = 55,
            t3 = 16,
            tabs = {
                [1] = { name = "Balance", icon = "Interface\\Icons\\spell_nature_starfall", points = 0 },
                [2] = { name = "Feral Combat", icon = "Interface\\Icons\\ability_druid_catform", points = 55 },
                [3] = { name = "Restoration", icon = "Interface\\Icons\\spell_nature_healingtouch", points = 16 },
            },
        },
        [2] = {
            specName = "Restoration",
            t1 = 11,
            t2 = 0,
            t3 = 60,
            tabs = {
                [1] = { name = "Balance", icon = "Interface\\Icons\\spell_nature_starfall", points = 11 },
                [2] = { name = "Feral Combat", icon = "Interface\\Icons\\ability_druid_catform", points = 0 },
                [3] = { name = "Restoration", icon = "Interface\\Icons\\spell_nature_healingtouch", points = 60 },
            },
        },
    },
}
```

- [ ] **Step 3: Add failing assertions for grouped snapshot API**

After the existing Alice active snapshot assertions, add:

```lua
local talentSnapshot = assert(service:GetPlayerTalentSnapshot("Alice"), "Alice talent snapshot should be available")
assert(talentSnapshot.activeGroup == 1, "Alice active talent group should be captured")
assert(talentSnapshot.numGroups == 2, "Alice should expose both talent groups")
assert(talentSnapshot.specName == "Feral Combat", "active spec name should remain compatible")
assert(talentSnapshot.secondarySpecName == "Restoration", "secondary spec name should be captured")
assert(talentSnapshot.groups and talentSnapshot.groups[1], "active group details should be present")
assert(talentSnapshot.groups and talentSnapshot.groups[2], "secondary group details should be present")
assert(talentSnapshot.groups[1].specIcon == "Interface\\Icons\\ability_druid_catform", "active group icon should be captured")
assert(talentSnapshot.groups[2].specIcon == "Interface\\Icons\\spell_nature_healingtouch", "secondary group icon should be captured")
assert(talentSnapshot.groups[1].mainTalentTree == 2, "active group dominant tree should be Feral")
assert(talentSnapshot.groups[2].mainTalentTree == 3, "secondary group dominant tree should be Restoration")
```

- [ ] **Step 4: Run the test and verify it fails**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
```

Expected: FAIL with a message equivalent to:

```text
attempt to call method 'GetPlayerTalentSnapshot' (a nil value)
```

- [ ] **Step 5: Commit the failing test**

```powershell
git add tests/spec_inspect_service_spec.lua
git commit -m "test: cover grouped spec inspect snapshots"
```

---

### Task 2: Implement Canonical Grouped SpecInspect Snapshot API

**Files:**
- Modify: `!KRT/Services/SpecInspect.lua`
- Test: `tests/spec_inspect_service_spec.lua`

- [ ] **Step 1: Add active/secondary helper functions**

In `!KRT/Services/SpecInspect.lua`, after `buildSpecIcon`, add:

```lua
local function getTalentGroupCount(unit)
    if lgt and type(lgt.GetNumTalentGroups) == "function" then
        return tonumber(lgt:GetNumTalentGroups(unit)) or 1
    end
    return 1
end

local function getActiveTalentGroup(unit)
    if lgt and type(lgt.GetActiveTalentGroup) == "function" then
        return tonumber(lgt:GetActiveTalentGroup(unit)) or 1
    end
    return 1
end

local function buildGroupSpecIcon(unit, group, dominantTab, specName)
    if not lgt or type(lgt.GetTalentTabInfo) ~= "function" then
        return nil
    end
    if isNonEmptyString(specName) and type(dominantTab) == "number" then
        local tabName, tabIcon = lgt:GetTalentTabInfo(unit, dominantTab, group)
        if tabName == specName and isNonEmptyString(tabIcon) then
            return tabIcon
        end
    end
    for tab = 1, 3 do
        local tabName, tabIcon = lgt:GetTalentTabInfo(unit, tab, group)
        if tabName == specName and isNonEmptyString(tabIcon) then
            return tabIcon
        end
    end
    return nil
end

local function buildTalentGroupSnapshot(unit, group)
    if not lgt or type(lgt.GetUnitTalentSpec) ~= "function" then
        return nil
    end

    local specName, t1, t2, t3 = lgt:GetUnitTalentSpec(unit, group)
    if not isNonEmptyString(specName) then
        return nil
    end

    local dominantTab = dominantTalentTab(specName, t1, t2, t3)
    local icon = buildGroupSpecIcon(unit, group, dominantTab, specName)
    return {
        group = group,
        specName = specName,
        specIcon = icon,
        mainTalentTree = dominantTab,
        points = { tonumber(t1) or 0, tonumber(t2) or 0, tonumber(t3) or 0 },
    }
end

local function findSecondaryGroup(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.groups) ~= "table" then
        return nil
    end
    for group = 1, snapshot.numGroups or 1 do
        if group ~= snapshot.activeGroup and snapshot.groups[group] then
            return snapshot.groups[group]
        end
    end
    return nil
end
```

- [ ] **Step 2: Replace `rebuildSnapshotFromLibrary` with grouped snapshot builder**

Replace the body of `rebuildSnapshotFromLibrary` with:

```lua
local function rebuildSnapshotFromLibrary(name, unit, reason, silent)
    local canReadTalents = lgt and type(lgt.GetUnitTalentSpec) == "function"
    if not canReadTalents or not isNonEmptyString(name) or not isNonEmptyString(unit) then
        return nil
    end

    local activeGroup = getActiveTalentGroup(unit)
    local numGroups = getTalentGroupCount(unit)
    local groups = {}
    for group = 1, numGroups do
        groups[group] = buildTalentGroupSnapshot(unit, group)
    end

    local active = groups[activeGroup] or groups[1]
    if not active then
        return nil
    end

    local role
    if type(lgt.GetUnitRole) == "function" then
        role = normalizeRole(lgt:GetUnitRole(unit))
    end
    local guid = UnitGUID(unit)

    local snapshot = {
        name = name,
        guid = guid,
        specName = active.specName,
        icon = active.specIcon,
        role = role,
        class = getClassForPlayer(name),
        updatedAt = now(),
        refreshReason = reason or "library",
        activeGroup = activeGroup,
        numGroups = numGroups,
        groups = groups,
        mainTalentTree = active.mainTalentTree,
    }

    local secondary = findSecondaryGroup(snapshot)
    if secondary then
        snapshot.secondarySpecName = secondary.specName
        snapshot.secondaryIcon = secondary.specIcon
        snapshot.secondaryGroup = secondary.group
        snapshot.secondaryMainTalentTree = secondary.mainTalentTree
    end

    local previous = cache[name]
    cache[name] = snapshot
    if not silent and emitDisplayUpdate and not snapshotDisplayEqual(previous, snapshot) then
        emitDisplayUpdate(snapshot, reason or "library")
    end
    return snapshot
end
```

- [ ] **Step 3: Add public grouped snapshot API**

After `module:GetPlayerSpecSnapshot`, add:

```lua
function module:GetPlayerTalentSnapshot(playerName)
    return self:GetPlayerSpecSnapshot(playerName)
end

function module:GetUnitTalentSnapshot(unit, playerName, reason, silent)
    local name = normalizePlayerRow(playerName)
    if not isNonEmptyString(name) then
        name = unit
    end
    if not isNonEmptyString(name) or not isNonEmptyString(unit) then
        return nil
    end
    local ok, snapshot = pcall(rebuildSnapshotFromLibrary, name, unit, reason or "unit", silent)
    if ok then
        return snapshot
    end
    return nil
end
```

- [ ] **Step 4: Run SpecInspect test**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
```

Expected:

```text
spec inspect service spec passed
```

- [ ] **Step 5: Run formatting check**

Run:

```powershell
stylua --check "!KRT/Services/SpecInspect.lua" tests/spec_inspect_service_spec.lua
```

Expected: exit code `0`.

- [ ] **Step 6: Commit SpecInspect API**

```powershell
git add "!KRT/Services/SpecInspect.lua" tests/spec_inspect_service_spec.lua
git commit -m "feat: canonicalize grouped spec inspect snapshots"
```

---

### Task 3: Write Failing Contracts For EquipInspect Rename

**Files:**
- Rename: `tests/raid_inspect_source_contract_spec.lua` -> `tests/equip_inspect_source_contract_spec.lua`
- Rename: `tests/raid_inspect_service_spec.lua` -> `tests/equip_inspect_service_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
- Modify: `tests/logger_visual_refresh_spec.lua`

- [ ] **Step 1: Rename source-contract test files**

Run:

```powershell
git mv tests/raid_inspect_source_contract_spec.lua tests/equip_inspect_source_contract_spec.lua
git mv tests/raid_inspect_service_spec.lua tests/equip_inspect_service_spec.lua
```

- [ ] **Step 2: Update source contract strings**

In `tests/equip_inspect_source_contract_spec.lua`, replace the RaidInspect contract block with:

```lua
assertContains(toc, "Services\\EquipInspect.lua", "TOC must load EquipInspect")
assertBefore(toc, "Services\\SpecInspect.lua", "Services\\EquipInspect.lua", "EquipInspect load order")
assertBefore(toc, "Services\\EquipInspect.lua", "Services\\Chat.lua", "EquipInspect load order")
assertNotContains(toc, "Services\\RaidInspect.lua", "TOC must not load the retired RaidInspect file")

local equipInspect = read("!KRT/Services/EquipInspect.lua")
assertContains(equipInspect, 'Timer.BindMixin(module, "EquipInspect")', "EquipInspect must use Timer mixin")
assertContains(equipInspect, "InternalEvents.RaidCreate", "EquipInspect must start from RaidCreate")
assertContains(equipInspect, "INSPECT_TALENT_READY", "EquipInspect must consume forwarded INSPECT_TALENT_READY as inspect-ready signal")
assertContains(equipInspect, "PLAYER_REGEN_ENABLED", "EquipInspect must resume after combat")
assertContains(equipInspect, "NotifyInspect(", "EquipInspect must own NotifyInspect calls")
assertContains(equipInspect, "Services.SpecInspect", "EquipInspect must delegate spec data to SpecInspect")
assertNotContains(equipInspect, "GetTalentTabInfo", "EquipInspect must not deduce specs directly")
assertNotContains(equipInspect, "RaidRosterDelta", "EquipInspect must not listen to roster deltas")
assertNotContains(equipInspect, "InspectFrame", "EquipInspect service must not reference UI frames")
assertNotContains(equipInspect, "C_Timer", "EquipInspect must not use Retail timers")
assertNotContains(equipInspect, "GetInspectSpecialization", "EquipInspect must not use Retail specialization APIs")
assertNotContains(equipInspect, "GetSpecialization", "EquipInspect must not use Retail specialization APIs")
assertNotContains(equipInspect, "table.move", "EquipInspect must stay Lua 5.1 compatible")
assertNotContains(equipInspect, "bit32", "EquipInspect must stay Lua 5.1 compatible")
```

Update event assertions in the same file:

```lua
assertContains(events, "Internal.EquipInspectStarted", "Events must expose equipment inspect start event")
assertContains(events, "Internal.EquipInspectUpdated", "Events must expose equipment inspect update event")
assertContains(events, "Internal.EquipInspectCompleted", "Events must expose equipment inspect completion event")
assertNotContains(events, "Internal.RaidInspectStarted", "Events must not expose retired RaidInspect start event")
```

Update Logger assertions:

```lua
assertContains(view, "getEquipInspectSnapshot", "Logger View must read EquipInspect snapshots")
assertContains(logger, "Services.EquipInspect:ForcePlayer", "Logger must allow manual equipment inspect force")
assertContains(logger, "InternalEvents.EquipInspectUpdated", "Logger must refresh on equipment inspect update")
assertNotContains(logger, "Services.RaidInspect", "Logger must not call retired RaidInspect service")
assertNotContains(logger, "InternalEvents.RaidInspectUpdated", "Logger must not listen to retired RaidInspect update event")
```

- [ ] **Step 3: Update service runtime test names**

In `tests/equip_inspect_service_spec.lua`, replace service load and event names:

```lua
loadAddonFile(addon, "!KRT/Services/EquipInspect.lua")

local service = assert(addon.Services.EquipInspect, "EquipInspect service must load")
```

In `featureShared.Events.Internal`, replace:

```lua
EquipInspectStarted = "EquipInspectStarted",
EquipInspectUpdated = "EquipInspectUpdated",
EquipInspectCompleted = "EquipInspectCompleted",
```

Update helper event checks:

```lua
if event and event[1] == "EquipInspectUpdated" and tonumber(event[3]) == tonumber(playerNid) and payload and payload.status == status then
    return true
end
```

- [ ] **Step 4: Add fake SpecInspect dependency to equipment runtime test**

In `tests/equip_inspect_service_spec.lua`, inside `fake.Services`, add:

```lua
fake.Services.SpecInspect = {
    GetUnitTalentSnapshot = function(_, unit)
        if unit == "raid1" then
            return {
                specName = "Feral Combat",
                icon = "Interface\\Icons\\ability_druid_catform",
                mainTalentTree = 2,
                activeGroup = 1,
                numGroups = 2,
                secondarySpecName = "Restoration",
                secondaryIcon = "Interface\\Icons\\spell_nature_healingtouch",
                secondaryGroup = 2,
                secondaryMainTalentTree = 3,
                groups = {
                    [1] = {
                        group = 1,
                        specName = "Feral Combat",
                        specIcon = "Interface\\Icons\\ability_druid_catform",
                        mainTalentTree = 2,
                        points = { 0, 55, 16 },
                    },
                    [2] = {
                        group = 2,
                        specName = "Restoration",
                        specIcon = "Interface\\Icons\\spell_nature_healingtouch",
                        mainTalentTree = 3,
                        points = { 11, 0, 60 },
                    },
                },
            }
        end
        return nil
    end,
}
```

- [ ] **Step 5: Add runtime assertions for copied SpecInspect data**

After `local aliceSnapshot = service:GetSnapshot(currentRaid, 1)`, add:

```lua
assert(aliceSnapshot.specName == "Feral Combat", "EquipInspect should copy active spec name from SpecInspect")
assert(aliceSnapshot.specIcon == "Interface\\Icons\\ability_druid_catform", "EquipInspect should copy active spec icon from SpecInspect")
assert(aliceSnapshot.secondarySpecName == "Restoration", "EquipInspect should copy secondary spec name from SpecInspect")
assert(aliceSnapshot.secondarySpecIcon == "Interface\\Icons\\spell_nature_healingtouch", "EquipInspect should copy secondary spec icon from SpecInspect")
assert(aliceSnapshot.talentSnapshot and aliceSnapshot.talentSnapshot.groups[2], "EquipInspect should persist grouped talent snapshot from SpecInspect")
```

- [ ] **Step 6: Run renamed tests and verify failures**

Run:

```powershell
lua tests/equip_inspect_source_contract_spec.lua
lua tests/equip_inspect_service_spec.lua
```

Expected: FAIL because `!KRT/Services/EquipInspect.lua`, `Services.EquipInspect`, and `EquipInspect*` events do not exist yet.

- [ ] **Step 7: Commit failing rename contracts**

```powershell
git add tests/equip_inspect_source_contract_spec.lua tests/equip_inspect_service_spec.lua tests/module_registry_services_spec.lua tests/module_registry_ui_entrypoints_spec.lua tests/logger_visual_refresh_spec.lua
git commit -m "test: rename raid inspect contracts to equip inspect"
```

---

### Task 4: Rename RaidInspect Service To EquipInspect

**Files:**
- Rename: `!KRT/Services/RaidInspect.lua` -> `!KRT/Services/EquipInspect.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Modules/Events.lua`
- Modify: `!KRT/Controllers/Logger.lua`
- Modify: `!KRT/Services/Logger/View.lua`
- Modify: registry/source-contract tests listed in Task 3

- [ ] **Step 1: Move service file**

Run:

```powershell
git mv "!KRT/Services/RaidInspect.lua" "!KRT/Services/EquipInspect.lua"
```

- [ ] **Step 2: Update service header and namespace**

In `!KRT/Services/EquipInspect.lua`, replace the header block with:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.EquipInspect
-- events: listens wow.INSPECT_TALENT_READY and wow.PLAYER_REGEN_ENABLED; emits EquipInspectStarted/EquipInspectUpdated/EquipInspectCompleted
```

Replace the namespace block with:

```lua
feature.EnsureServiceNamespace("EquipInspect")
local module = Services.EquipInspect
Timer.BindMixin(module, "EquipInspect")
```

- [ ] **Step 3: Update event names inside service**

Replace event emitters in `!KRT/Services/EquipInspect.lua`:

```lua
Bus.TriggerEvent(InternalEvents.EquipInspectStarted, raidId, reason or "start")
Bus.TriggerEvent(InternalEvents.EquipInspectCompleted, raidId)
Bus.TriggerEvent(InternalEvents.EquipInspectUpdated, raidId, playerNid, snapshot)
```

- [ ] **Step 4: Update module registry registration**

At the bottom of `!KRT/Services/EquipInspect.lua`, replace:

```lua
registry.AddModule("Services/EquipInspect", {
    deps = {
        "Init",
        "Modules/Events",
        "Modules/Timer",
        "Services/Raid/Attendance",
        "Services/SpecInspect",
    },
})
registry.SetLoaded("Services/EquipInspect")
```

- [ ] **Step 5: Update TOC load order**

In `!KRT/!KRT.toc`, replace:

```text
Services\RaidInspect.lua
```

with:

```text
Services\EquipInspect.lua
```

Keep it after `Services\SpecInspect.lua` and before `Services\Chat.lua`.

- [ ] **Step 6: Update event registry**

In `!KRT/Modules/Events.lua`, replace the three RaidInspect internal constants with:

```lua
Internal.EquipInspectStarted = "EquipInspectStarted"
Internal.EquipInspectUpdated = "EquipInspectUpdated"
Internal.EquipInspectCompleted = "EquipInspectCompleted"
```

- [ ] **Step 7: Update Logger View service access**

In `!KRT/Services/Logger/View.lua`, rename `getRaidInspectSnapshot` to `getEquipInspectSnapshot` and use:

```lua
local function getEquipInspectSnapshot(raid, playerNid)
    local equipInspect = Services.EquipInspect
    local nid = tonumber(playerNid)
    if not nid then
        return nil
    end

    if equipInspect and type(equipInspect.GetSnapshot) == "function" then
        local snapshot = equipInspect:GetSnapshot(raid, nid)
        if snapshot then
            return snapshot
        end
    end

    local inspectData = raid and raid.inspect
    local players = inspectData and inspectData.players
    if type(players) ~= "table" then
        return nil
    end

    return players[nid] or players[tostring(nid)]
end
```

In `enrichAttendanceRowsWithInspect`, replace:

```lua
local snapshot = getEquipInspectSnapshot(raid, rowId)
```

- [ ] **Step 8: Update Logger controller calls and callbacks**

In `!KRT/Controllers/Logger.lua`, replace:

```lua
if Services.EquipInspect and Services.EquipInspect.ForcePlayer then
    Services.EquipInspect:ForcePlayer(selectedRaid, selectedPlayer)
end
```

Replace event callback registrations:

```lua
Bus.RegisterCallback(InternalEvents.EquipInspectUpdated, function(_, raidId)
    if module._isRaidAttendanceViewingCurrentRaid(raidId) then
        module._requestAttendanceBoundListsRefresh("equip-inspect-updated")
    end
end)

Bus.RegisterCallback(InternalEvents.EquipInspectCompleted, function(_, raidId)
    if module._isRaidAttendanceViewingCurrentRaid(raidId) then
        module._requestAttendanceBoundListsRefresh("equip-inspect-completed")
    end
end)
```

- [ ] **Step 9: Replace test registry strings**

In `tests/module_registry_services_spec.lua` and `tests/module_registry_ui_entrypoints_spec.lua`, replace the expected service object with:

```lua
local expectedEquipInspectService = {
    name = "Services/EquipInspect",
    path = "!KRT/Services/EquipInspect.lua",
    deps = {
        "Init",
        "Modules/Events",
        "Modules/Timer",
        "Services/Raid/Attendance",
        "Services/SpecInspect",
    },
}
```

Replace `expectedRaidInspectService` references with `expectedEquipInspectService`.

- [ ] **Step 10: Run rename contract tests**

Run:

```powershell
lua tests/equip_inspect_source_contract_spec.lua
lua tests/equip_inspect_service_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected: source/registry tests pass; service test may still fail on direct spec deduction until Task 5 removes `GetTalentTabInfo`.

- [ ] **Step 11: Commit service rename**

```powershell
git add "!KRT/Services/EquipInspect.lua" "!KRT/!KRT.toc" "!KRT/Modules/Events.lua" "!KRT/Controllers/Logger.lua" "!KRT/Services/Logger/View.lua" tests/equip_inspect_source_contract_spec.lua tests/equip_inspect_service_spec.lua tests/module_registry_services_spec.lua tests/module_registry_ui_entrypoints_spec.lua tests/logger_visual_refresh_spec.lua
git commit -m "refactor: rename raid inspect service to equip inspect"
```

---

### Task 5: Move Spec Deduction Out Of EquipInspect

**Files:**
- Modify: `!KRT/Services/EquipInspect.lua`
- Modify: `tests/equip_inspect_service_spec.lua`

- [ ] **Step 1: Remove direct talent API local**

In `!KRT/Services/EquipInspect.lua`, delete:

```lua
local GetTalentTabInfo = GetTalentTabInfo or noop
```

- [ ] **Step 2: Replace `detectMainSpec` with SpecInspect adapter**

Delete the old `detectMainSpec(unit)` helper and add:

```lua
local function getSpecInspectSnapshot(unit, player)
    local specInspect = Services.SpecInspect
    if not (specInspect and type(specInspect.GetUnitTalentSnapshot) == "function") then
        return nil
    end

    local playerName = player and player.name or unit
    return specInspect:GetUnitTalentSnapshot(unit, playerName, "equip_inspect", true)
end

local function copySpecSnapshotFields(snapshot, talentSnapshot)
    if type(snapshot) ~= "table" or type(talentSnapshot) ~= "table" then
        return
    end

    snapshot.talentSnapshot = talentSnapshot
    snapshot.specName = talentSnapshot.specName
    snapshot.specIcon = talentSnapshot.icon
    snapshot.mainTalentTree = talentSnapshot.mainTalentTree
    snapshot.activeTalentGroup = talentSnapshot.activeGroup
    snapshot.numTalentGroups = talentSnapshot.numGroups
    snapshot.secondarySpecName = talentSnapshot.secondarySpecName
    snapshot.secondarySpecIcon = talentSnapshot.secondaryIcon
    snapshot.secondaryTalentGroup = talentSnapshot.secondaryGroup
    snapshot.secondaryMainTalentTree = talentSnapshot.secondaryMainTalentTree
end
```

- [ ] **Step 3: Change ready detail building to accept player**

Replace `buildReadyDetails(unit)` with:

```lua
local function buildReadyDetails(unit, player)
    local items, avgIlvl = collectItems(unit)
    local talentSnapshot = getSpecInspectSnapshot(unit, player)
    return {
        items = items,
        avgIlvl = avgIlvl,
        talentSnapshot = talentSnapshot,
    }
end
```

- [ ] **Step 4: Copy SpecInspect fields into persisted equipment snapshot**

In `finalizeRequest`, replace:

```lua
local details = buildReadyDetails(unit)
```

with:

```lua
local player = getPlayerByNid(raid, playerNid)
local details = buildReadyDetails(unit, player)
```

After building the `snapshot = { ... }` table, delete assignments that read `details.specName`, `details.specIcon`, and `details.mainTalentTree`, then add:

```lua
copySpecSnapshotFields(snapshot, details.talentSnapshot)
```

- [ ] **Step 5: Run equipment service test**

Run:

```powershell
lua tests/equip_inspect_service_spec.lua
```

Expected:

```text
raid inspect service spec passed
```

The printed string may still say `raid inspect service spec passed` until Step 6.

- [ ] **Step 6: Rename runtime test print message**

In `tests/equip_inspect_service_spec.lua`, replace the final print with:

```lua
print("equip inspect service spec passed")
```

- [ ] **Step 7: Run source contract and service tests**

Run:

```powershell
lua tests/equip_inspect_source_contract_spec.lua
lua tests/equip_inspect_service_spec.lua
```

Expected:

```text
equip inspect source contract passed
equip inspect service spec passed
```

- [ ] **Step 8: Commit spec/equip ownership split**

```powershell
git add "!KRT/Services/EquipInspect.lua" tests/equip_inspect_service_spec.lua tests/equip_inspect_source_contract_spec.lua
git commit -m "refactor: delegate inspect specs to spec inspect"
```

---

### Task 6: Update Logger, Visual Contracts, And Historical Fallbacks

**Files:**
- Modify: `!KRT/Services/Logger/View.lua`
- Modify: `!KRT/Controllers/Logger.lua`
- Modify: `tests/logger_visual_refresh_spec.lua`
- Modify: `tests/equip_inspect_source_contract_spec.lua`

- [ ] **Step 1: Keep historical active spec fallback in Logger View**

In `enrichAttendanceRowsWithInspect`, keep current active-field fallback:

```lua
row.specName = snapshot.specName
row.specFmt = snapshot.specName or ""
```

Add secondary fields for future UI use:

```lua
row.secondarySpecName = snapshot.secondarySpecName
row.secondarySpecIcon = snapshot.secondarySpecIcon
```

- [ ] **Step 2: Update Logger visual source contract**

In `tests/logger_visual_refresh_spec.lua`, add or update:

```lua
assert(logger:find("Services.EquipInspect:ForcePlayer", 1, true), "Logger must force equipment inspect through EquipInspect")
assert(logger:find("InternalEvents.EquipInspectUpdated", 1, true), "Logger must refresh attendance on EquipInspect updates")
assert(not logger:find("Services.RaidInspect", 1, true), "Logger must not call retired RaidInspect service")
```

- [ ] **Step 3: Run Logger visual contract**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
```

Expected:

```text
logger visual refresh source contract passed
```

- [ ] **Step 4: Commit Logger integration**

```powershell
git add "!KRT/Services/Logger/View.lua" "!KRT/Controllers/Logger.lua" tests/logger_visual_refresh_spec.lua tests/equip_inspect_source_contract_spec.lua
git commit -m "refactor: update logger to equip inspect events"
```

---

### Task 7: Update Docs, Schema, Changelog, And Generated Catalogs

**Files:**
- Modify: `docs/RAID_SCHEMA.md`
- Modify: `docs/OVERVIEW.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `!KRT/CHANGELOG.md`
- Generated: `docs/TREE.md`
- Generated: `docs/FUNCTION_REGISTRY.csv`
- Generated: `docs/FN_CLUSTERS.md`
- Generated if changed by tooling: `docs/API_REGISTRY*.csv`, `docs/API_NOMENCLATURE_CENSUS.md`

- [ ] **Step 1: Update RAID schema heading and fields**

In `docs/RAID_SCHEMA.md`, replace:

```markdown
## RaidInspectSnapshot (`raid.inspect`)
```

with:

```markdown
## EquipInspectSnapshot (`raid.inspect`)
```

Add this paragraph under the heading:

```markdown
`raid.inspect` remains the persisted key for compatibility. `EquipInspect`
owns equipment/iLvl capture; `SpecInspect` owns talent/spec deduction and may
provide copied active and secondary spec metadata inside each persisted
equipment snapshot.
```

- [ ] **Step 2: Update architecture/overview wording**

In `docs/OVERVIEW.md`, replace the old service sentence with:

```markdown
- `addon.Services.EquipInspect` owns raid attendance equipment snapshots,
  inspect queueing, item capture, average item level, and manual force actions.
- `addon.Services.SpecInspect` owns UI-free talent/spec snapshots backed by
  `LibGroupTalents-1.0`, including active and secondary talent groups.
```

In `docs/ARCHITECTURE.md`, add:

```markdown
`Services/EquipInspect.lua` must not deduce talent specs directly. It may copy
the current `Services.SpecInspect` talent snapshot into persisted attendance
equipment snapshots for historical display.
```

- [ ] **Step 3: Add changelog entry**

Under `## Unreleased` -> `### Fixes` in `!KRT/CHANGELOG.md`, add:

```markdown
- **Inspect ownership** - Renamed raid attendance equipment inspection to
  EquipInspect and made SpecInspect the canonical owner of active and secondary
  talent/spec snapshots.
```

- [ ] **Step 4: Refresh generated docs**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
py -3 tools/krt.py api-catalog-check
```

Expected:

```text
API catalogs are up to date.
```

- [ ] **Step 5: Run grep audit**

Run:

```powershell
rg -n "RaidInspect|RaidInspectUpdated|RaidInspectStarted|RaidInspectCompleted|Services\\\\RaidInspect|Services/RaidInspect|RaidInspect.lua" "!KRT" tests docs -S
```

Expected remaining matches only in:

```text
docs/superpowers/plans/2026-06-15-raidinspect-attendance-redesign.md
docs/superpowers/plans/2026-06-16-equipinspect-specinspect-canonicalization.md
```

- [ ] **Step 6: Commit docs and generated catalogs**

```powershell
git add docs/RAID_SCHEMA.md docs/OVERVIEW.md docs/ARCHITECTURE.md docs/TREE.md docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/API_REGISTRY.csv docs/API_REGISTRY_INTERNAL.csv docs/API_REGISTRY_PUBLIC.csv docs/API_NOMENCLATURE_CENSUS.md "!KRT/CHANGELOG.md"
git commit -m "docs: update equip inspect ownership"
```

---

### Task 8: Full Verification Gate

**Files:**
- No planned source edits.

- [ ] **Step 1: Run focused tests**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
lua tests/equip_inspect_service_spec.lua
lua tests/equip_inspect_source_contract_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected:

```text
spec inspect service spec passed
equip inspect service spec passed
equip inspect source contract passed
logger visual refresh source contract passed
```

Registry tests should exit `0`.

- [ ] **Step 2: Run repo quality gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
py -3 tools/krt.py repo-quality-check --check ui_binding
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py api-catalog-check
git diff --check
```

Expected:

```text
TOC file checks passed.
Lua uniformity checks passed.
UI binding checks passed.
Lua syntax check passed.
API catalogs are up to date.
```

- [ ] **Step 3: Run final grep audit**

Run:

```powershell
rg -n "GetTalentTabInfo" "!KRT/Services/EquipInspect.lua"
rg -n "Services\\.RaidInspect|InternalEvents\\.RaidInspect|RaidInspect.lua" "!KRT" tests -S
```

Expected:

```text
No matches in EquipInspect for GetTalentTabInfo.
No live addon/test references to Services.RaidInspect, InternalEvents.RaidInspect*, or RaidInspect.lua.
```

- [ ] **Step 4: Manual in-game smoke checklist**

Use a WotLK 3.3.5a client:

```text
1. Login: no Lua errors.
2. /krt opens.
3. Create/current raid appears in Raid Attendance.
4. EquipInspect starts after raid creation and updates rows.
5. Online inspectable player shows iLvl and item icons.
6. Active spec icon still appears.
7. Character with dual spec stores active and secondary spec metadata.
8. Force button refreshes current player equipment snapshot.
9. /reload keeps persisted raid.inspect snapshots.
10. Historical raid attendance still renders old snapshots with active spec fallback.
```

- [ ] **Step 5: Commit any verification-only generated changes**

If `api-catalog-check` or `update-tree.ps1` generated additional diffs:

```powershell
git add docs/TREE.md docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/API_REGISTRY.csv docs/API_REGISTRY_INTERNAL.csv docs/API_REGISTRY_PUBLIC.csv docs/API_NOMENCLATURE_CENSUS.md
git commit -m "chore: refresh generated registries"
```

If there are no diffs:

```powershell
git status --short
```

Expected:

```text
No output.
```

---

## Self-Review

**Spec coverage:** The plan covers the requested architecture: `SpecInspect` deduces specializations, `EquipInspect` owns equipment inspection, and `RaidInspect` naming is removed from live addon/test contracts. It also adds secondary talent group capture through `LibGroupTalents-1.0`.

**Placeholder scan:** Every task lists concrete files, code snippets, commands, and expected outcomes; no deferred implementation markers remain.

**Type consistency:** The new canonical APIs are consistently named `GetPlayerTalentSnapshot` and `GetUnitTalentSnapshot`. Equipment snapshots keep active compatibility fields `specName`, `specIcon`, and `mainTalentTree`, while grouped data lives under `talentSnapshot`.

**Risk notes:** The persisted key remains `raid.inspect` to avoid SavedVariables migration. `LibTalentQuery-1.0` remains internal to `LibGroupTalents-1.0`; KRT code must not call it directly.
