# Spec Role Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show WotLK talent spec icons beside player names in Master Loot and Loot Counter, backed by
`LibGroupTalents-1.0` and refreshed conservatively from ready checks or a manual slash command.

**Architecture:** Add a UI-free `addon.Services.SpecInspect` service that reads and refreshes
talent data through `LibGroupTalents-1.0`, caches normalized display snapshots, and emits a KRT bus
event when visible spec data changes. Master Loot and Loot Counter consume the service at render time
and never own talent inspection.

**Tech Stack:** WoW 3.3.5a, Lua 5.1, KRT module registry, `addon.Bus`, `LibGroupTalents-1.0`,
KRT XML templates, `Modules/UI/Visuals.lua`, source-level Lua tests.

---

## Classification And Delegation

- 55to53 classification: `complex-orchestrated`.
- Reason: this touches a new service, forwarded WoW events, slash commands, shared UI template,
  shared row renderer, Loot Counter widget, TOC order, localization, changelog, and tests.
- Implementation must be delegated to `spark_implementer` after this plan is approved.
- Parent review must inspect the final diff before completion.
- `code-mapper` was not required for this plan because ownership and call flow were mapped locally:
  `SpecInspect` owns talent data, `Init.lua` forwards `READY_CHECK`, `SlashEvents` owns `/krt`,
  `Visuals.lua` renders Master roll rows, and `LootCounter.lua` renders its own rows.

## File Structure

- Create `!KRT/Services/SpecInspect.lua`
  Runtime-only service. Reads `LibGroupTalents-1.0`, stores session cache, handles ready-check and
  forced refresh requests, and emits `Internal.SpecInspectUpdated`.
- Modify `!KRT/Modules/Events.lua`
  Add `Internal.SpecInspectUpdated` and `Wow.ReadyCheck`.
- Modify `!KRT/Init.lua`
  Seed and forward `READY_CHECK` through the existing WoW-event bus pattern.
- Modify `!KRT/!KRT.toc`
  Load `Services\SpecInspect.lua` after `Services\Raid\Roster.lua` and before UI consumers.
- Modify `!KRT/EntryPoints/SlashEvents.lua`
  Add `/krt specinspect`, `/krt inspectspec`, and `/krt specinspect force`.
- Modify `!KRT/Localization/localization.en.lua`
  Add slash help and concise command output strings.
- Modify `!KRT/UI/Templates/Common.xml`
  Add a named spec icon texture to `KRTSelectPlayerTemplate`.
- Modify `!KRT/Modules/UI/Visuals.lua`
  Render the Master roll row spec icon when `data.specIcon` exists.
- Modify `!KRT/Controllers/Master.lua`
  Add spec snapshot fields to copied roll rows and refresh the list on `SpecInspectUpdated`.
- Modify `!KRT/Widgets/LootCounter.lua`
  Add a row-local spec icon and refresh rows on `SpecInspectUpdated`.
- Modify `!KRT/CHANGELOG.md`
  Add an Unreleased note.
- Add `tests/spec_inspect_service_spec.lua`
  Harness coverage for service cache, refresh policy, role normalization, and library callbacks.
- Modify registry/source tests as needed:
  `tests/module_registry_services_spec.lua`, `tests/module_registry_ui_entrypoints_spec.lua`,
  and `tests/release_stabilization_spec.lua`.

---

### Task 1: Add Failing Service And Registry Tests

**Files:**
- Create: `tests/spec_inspect_service_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Create the failing `SpecInspect` service harness**

Create `tests/spec_inspect_service_spec.lua` with this content:

```lua
local callbacks = {}
local busEvents = {}
local now = 1000

local fakeLGT = {
    refreshed = {},
    snapshots = {},
}

function fakeLGT:GetUnitTalentSpec(unit)
    local row = self.snapshots[unit]
    if not row then
        return nil
    end
    return row.specName, row.t1 or 0, row.t2 or 0, row.t3 or 0
end

function fakeLGT:GetTalentTabInfo(unit, tab)
    local row = self.snapshots[unit]
    if not row or not row.tabs then
        return nil
    end
    local data = row.tabs[tab]
    if not data then
        return nil
    end
    return data.name, data.icon, data.points or 0, data.background
end

function fakeLGT:GetUnitRole(unit)
    local row = self.snapshots[unit]
    return row and row.role or nil
end

function fakeLGT:RefreshTalentsByUnit(unit)
    self.refreshed[#self.refreshed + 1] = unit
end

function fakeLGT:RegisterCallback(owner, eventName, handler)
    callbacks[eventName] = callbacks[eventName] or {}
    callbacks[eventName][#callbacks[eventName] + 1] = { owner = owner, handler = handler }
end

local function fireLgt(eventName, ...)
    for i = 1, #(callbacks[eventName] or {}) do
        local cb = callbacks[eventName][i]
        cb.handler(eventName, ...)
    end
end

local function newAddon()
    local addon = { Services = {}, Database = {} }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
        Events = {
            Internal = {
                SpecInspectUpdated = "SpecInspectUpdated",
            },
            Wow = {
                ReadyCheck = "wow.READY_CHECK",
            },
            GetWowForwarded = function(name)
                return "wow." .. tostring(name)
            end,
        },
        Bus = {
            RegisterCallback = function(eventName, fn)
                busEvents[eventName] = busEvents[eventName] or {}
                busEvents[eventName][#busEvents[eventName] + 1] = fn
            end,
            TriggerEvent = function(eventName, ...)
                busEvents._triggered = busEvents._triggered or {}
                busEvents._triggered[#busEvents._triggered + 1] = { eventName, ... }
            end,
        },
        Strings = {
            NormalizeName = function(name)
                return name
            end,
        },
        ModuleRegistry = {
            AddModule = function() end,
            SetLoaded = function() end,
        },
    }
    feature.Services.Raid = {
        GetUnitID = function(_, name)
            return ({ Alice = "raid1", Bob = "raid2" })[name] or "none"
        end,
        GetPlayers = function(_, _, out)
            out = out or {}
            out[#out + 1] = { name = "Alice", class = "DRUID" }
            out[#out + 1] = { name = "Bob", class = "MAGE" }
            return out
        end,
        GetPlayerClass = function(_, name)
            return name == "Alice" and "DRUID" or "MAGE"
        end,
    }
    addon.Database.GetCurrentRaid = function()
        return 1
    end
    addon.Database.GetFeatureShared = function()
        return feature
    end
    feature.EnsureServiceNamespace = function(name)
        feature.Services[name] = feature.Services[name] or {}
        addon.Services[name] = feature.Services[name]
        return feature.Services[name]
    end
    return addon
end

local function loadAddonFile(addon, path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable({
        select = select,
        LibStub = function(name, silent)
            assert(name == "LibGroupTalents-1.0", "unexpected library lookup")
            assert(silent == true, "library lookup should be silent")
            return fakeLGT
        end,
        GetTime = function()
            return now
        end,
        UnitGUID = function(unit)
            return ({ raid1 = "GUID-A", raid2 = "GUID-B" })[unit]
        end,
    }, { __index = _G }))
    chunk("!KRT", addon)
end

fakeLGT.snapshots.raid1 = {
    specName = "Feral Combat",
    role = "tank",
    t1 = 0,
    t2 = 55,
    t3 = 16,
    tabs = {
        [2] = { name = "Feral Combat", icon = "Interface\\Icons\\ability_druid_catform" },
    },
}

local addon = newAddon()
loadAddonFile(addon, "!KRT/Services/SpecInspect.lua")

local service = assert(addon.Services.SpecInspect, "SpecInspect service must load")
local snapshot = assert(service:GetPlayerSpecSnapshot("Alice"), "Alice snapshot should be cached")
assert(snapshot.specName == "Feral Combat", "expected spec name from LibGroupTalents")
assert(snapshot.icon == "Interface\\Icons\\ability_druid_catform", "expected tree icon")
assert(snapshot.role == "TANK", "expected normalized tank role")

fakeLGT.refreshed = {}
local result = service:RefreshRaidSpecs({ reason = "test" })
assert(result.refreshed >= 1, "missing player should request a library refresh")
assert(fakeLGT.refreshed[1] == "raid2", "Bob should be refreshed through LibGroupTalents")

fakeLGT.snapshots.raid2 = {
    specName = "Frost",
    role = "caster",
    t1 = 0,
    t2 = 0,
    t3 = 57,
    tabs = {
        [3] = { name = "Frost", icon = "Interface\\Icons\\spell_frost_frostbolt02" },
    },
}
fireLgt("LibGroupTalents_Update", "GUID-B", "raid2", "Frost", 0, 0, 57)
local bob = assert(service:GetPlayerSpecSnapshot("Bob"), "Bob snapshot should update from callback")
assert(bob.role == "DAMAGER", "caster role should normalize to DAMAGER")
assert(bob.icon == "Interface\\Icons\\spell_frost_frostbolt02", "expected callback refresh icon")
assert(busEvents._triggered and #busEvents._triggered > 0, "SpecInspectUpdated should be emitted")

print("spec inspect service spec passed")
```

- [ ] **Step 2: Run the failing service spec**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
```

Expected: FAIL because `!KRT/Services/SpecInspect.lua` does not exist yet.

- [ ] **Step 3: Add source-level registry expectations**

In `tests/module_registry_services_spec.lua`, add `Services/SpecInspect` to the service lists used by
the file. Add the expected spec near the other top-level services:

```lua
local expectedSpecInspectService = {
    name = "Services/SpecInspect",
    path = "!KRT/Services/SpecInspect.lua",
    owner = "module",
    separator = ":",
    registryFromFeature = true,
    events = "-- events: listens wow.READY_CHECK and LibGroupTalents callbacks; emits SpecInspectUpdated",
    deps = {
        "Init",
        "Modules/ModuleRegistry",
        "Modules/Events",
        "Modules/Bus",
        "Modules/Strings",
        "Services/Raid/Roster",
    },
}
```

Then add:

```lua
assertServiceRegistryContract(expectedSpecInspectService)
```

Also include `expectedSpecInspectService` in any local `findExpectedSpec` list used for out-of-order
dependency checks.

- [ ] **Step 4: Add entrypoint source expectations for the new slash command**

In `tests/module_registry_ui_entrypoints_spec.lua`, extend the slash command assertions with:

```lua
local slashSource = read("!KRT/EntryPoints/SlashEvents.lua")
assertContains(slashSource, "cmdSpecInspect", "SlashEvents must define spec inspect aliases")
assertContains(slashSource, "handleSpecInspectCommand", "SlashEvents must route spec inspect commands")
assertContains(slashSource, "Services.SpecInspect", "SlashEvents must dispatch to SpecInspect service")
```

- [ ] **Step 5: Add release stabilization source checks**

In `tests/release_stabilization_spec.lua`, add source checks that fail until the implementation exists:

```lua
local specInspectSource = read("!KRT/Services/SpecInspect.lua")
assertContains(
    specInspectSource,
    'LibStub("LibGroupTalents-1.0", true)',
    "SpecInspect must use LibGroupTalents silently"
)
assertNotContains(specInspectSource, "NotifyInspect(", "SpecInspect must not call NotifyInspect directly")
assertContains(specInspectSource, "RefreshTalentsByUnit", "SpecInspect force refresh must delegate to LibGroupTalents")
```

- [ ] **Step 6: Run the focused failing tests**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected: FAIL on missing service/source expectations.

- [ ] **Step 7: Commit the failing tests**

Run:

```powershell
git add tests/spec_inspect_service_spec.lua
git add tests/module_registry_services_spec.lua
git add tests/module_registry_ui_entrypoints_spec.lua
git add tests/release_stabilization_spec.lua
git commit -m "test: cover spec inspector service contracts"
```

---

### Task 2: Implement SpecInspect Service And Ready-Check Wiring

**Files:**
- Create: `!KRT/Services/SpecInspect.lua`
- Modify: `!KRT/Modules/Events.lua`
- Modify: `!KRT/Init.lua`
- Modify: `!KRT/!KRT.toc`

- [ ] **Step 1: Add event names**

In `!KRT/Modules/Events.lua`, add:

```lua
Wow.ReadyCheck = Wow.ReadyCheck or "wow.READY_CHECK"
Internal.SpecInspectUpdated = "SpecInspectUpdated"
```

In `!KRT/Init.lua`, add bootstrap seeding:

```lua
Wow.ReadyCheck = Wow.ReadyCheck or "wow.READY_CHECK"
```

Then add `READY_CHECK` to `addonEvents` and `wowBusEvents`:

```lua
READY_CHECK = "READY_CHECK",
```

```lua
READY_CHECK = WowEvents.ReadyCheck,
```

- [ ] **Step 2: Add the service file**

Create `!KRT/Services/SpecInspect.lua` with this structure:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.SpecInspect
-- events: listens wow.READY_CHECK and LibGroupTalents callbacks; emits SpecInspectUpdated
-- notes: runtime-only spec display cache backed by LibGroupTalents-1.0
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Database = feature.Database
local Events = feature.Events
local Bus = feature.Bus
local Services = feature.Services
local Strings = feature.Strings

local InternalEvents = Events.Internal

local LibStub = LibStub
local GetTime = GetTime
local UnitGUID = UnitGUID
local tonumber, tostring, type = tonumber, tostring, type

feature.EnsureServiceNamespace("SpecInspect")
local module = Services.SpecInspect

local STALE_SECONDS = 30 * 60
local RETRY_SECONDS = 60

local cacheByName = {}
local cacheByGuid = {}
local rosterScratch = {}
local callbacksBound = false

local function getLgt()
    if type(LibStub) ~= "function" then
        return nil
    end
    return LibStub("LibGroupTalents-1.0", true)
end

local function normalizeName(name)
    if not name or name == "" then
        return nil
    end
    if Strings and Strings.NormalizeName then
        return Strings.NormalizeName(name, true)
    end
    return name
end

local function normalizeRole(role)
    if role == "tank" then
        return "TANK"
    end
    if role == "healer" then
        return "HEALER"
    end
    if role == "melee" or role == "caster" then
        return "DAMAGER"
    end
    return nil
end

local function getDominantTab(t1, t2, t3)
    t1 = tonumber(t1) or 0
    t2 = tonumber(t2) or 0
    t3 = tonumber(t3) or 0
    if t1 > t2 and t1 > t3 then
        return 1
    end
    if t2 > t1 and t2 > t3 then
        return 2
    end
    if t3 > t1 and t3 > t2 then
        return 3
    end
    return nil
end
```

Add the implementation functions below the helper block:

```lua
local function snapshotsDiffer(a, b)
    if not a or not b then
        return true
    end
    return a.specName ~= b.specName or a.icon ~= b.icon or a.role ~= b.role or a.guid ~= b.guid
end

local function storeSnapshot(name, snapshot)
    local key = normalizeName(name)
    if not key or type(snapshot) ~= "table" then
        return nil
    end
    local old = cacheByName[key]
    cacheByName[key] = snapshot
    if snapshot.guid then
        cacheByGuid[snapshot.guid] = snapshot
    end
    if snapshotsDiffer(old, snapshot) and Bus and Bus.TriggerEvent then
        Bus.TriggerEvent(InternalEvents.SpecInspectUpdated, key, snapshot)
    end
    return snapshot
end

local function buildSnapshotFromUnit(name, unit, reason)
    local lgt = getLgt()
    if not (lgt and unit and unit ~= "none") then
        return nil
    end

    local specName, t1, t2, t3 = lgt:GetUnitTalentSpec(unit)
    local tab = getDominantTab(t1, t2, t3)
    local icon
    if tab and lgt.GetTalentTabInfo then
        local tabName, tabIcon = lgt:GetTalentTabInfo(unit, tab)
        specName = specName or tabName
        icon = tabIcon
    end

    local role = lgt.GetUnitRole and normalizeRole(lgt:GetUnitRole(unit)) or nil
    if not (specName and icon) then
        return nil
    end

    return {
        name = normalizeName(name),
        guid = UnitGUID and UnitGUID(unit) or nil,
        specName = specName,
        icon = icon,
        role = role,
        class = Services.Raid and Services.Raid.GetPlayerClass and Services.Raid:GetPlayerClass(name) or nil,
        updatedAt = GetTime and GetTime() or 0,
        refreshReason = reason,
    }
end

local function shouldRefresh(snapshot, guid, force)
    if force then
        return true
    end
    if not snapshot then
        return true
    end
    if guid and snapshot.guid and snapshot.guid ~= guid then
        return true
    end
    if not (snapshot.specName and snapshot.icon) then
        return true
    end
    local now = GetTime and GetTime() or 0
    if (tonumber(snapshot.failedAt) or 0) > 0 and now - snapshot.failedAt < RETRY_SECONDS then
        return false
    end
    return now - (tonumber(snapshot.lastTalentRefreshAt or snapshot.updatedAt) or 0) > STALE_SECONDS
end

local function getUnitForName(name)
    local raid = Services.Raid
    if not (raid and raid.GetUnitID) then
        return nil
    end
    local unit = raid:GetUnitID(name)
    if unit == "none" then
        return nil
    end
    return unit
end
```

Add public API and callback binding:

```lua
function module:GetPlayerSpecSnapshot(name)
    return cacheByName[normalizeName(name)]
end

function module:RefreshPlayer(name, opts)
    opts = opts or {}
    local key = normalizeName(name)
    if not key then
        return false, "invalid_name"
    end
    local unit = getUnitForName(key)
    if not unit then
        return false, "missing_unit"
    end

    local snapshot = buildSnapshotFromUnit(key, unit, opts.reason or "refresh")
    if snapshot then
        storeSnapshot(key, snapshot)
    end

    local guid = UnitGUID and UnitGUID(unit) or nil
    if shouldRefresh(cacheByName[key], guid, opts.force == true) then
        local lgt = getLgt()
        if lgt and lgt.RefreshTalentsByUnit then
            lgt:RefreshTalentsByUnit(unit)
            cacheByName[key] = cacheByName[key] or { name = key, guid = guid }
            cacheByName[key].lastTalentRefreshAt = GetTime and GetTime() or 0
            cacheByName[key].refreshReason = opts.reason or "refresh"
            return true, "queued"
        end
        return false, "missing_library"
    end
    return true, "cached"
end

function module:RefreshRaidSpecs(opts)
    opts = opts or {}
    local raid = Services.Raid
    local raidId = Database.GetCurrentRaid and Database.GetCurrentRaid() or nil
    local result = { refreshed = 0, cached = 0, skipped = 0 }
    if not (raidId and raid and raid.GetPlayers) then
        return result
    end

    for i = #rosterScratch, 1, -1 do
        rosterScratch[i] = nil
    end
    local players = raid:GetPlayers(raidId, nil, rosterScratch) or rosterScratch
    for i = 1, #players do
        local row = players[i]
        local ok, state = self:RefreshPlayer(row and row.name, opts)
        if ok and state == "queued" then
            result.refreshed = result.refreshed + 1
        elseif ok then
            result.cached = result.cached + 1
        else
            result.skipped = result.skipped + 1
        end
    end
    return result
end

function module:ForceRefreshRaidSpecs(reason)
    return self:RefreshRaidSpecs({ force = true, reason = reason or "force" })
end

local function handleLibraryUpdate(_, guid, unit)
    if not unit then
        return
    end
    local name
    local raid = Services.Raid
    if raid and raid.GetPlayers then
        local raidId = Database.GetCurrentRaid and Database.GetCurrentRaid() or nil
        for i = #rosterScratch, 1, -1 do
            rosterScratch[i] = nil
        end
        local players = raid:GetPlayers(raidId, nil, rosterScratch) or rosterScratch
        for i = 1, #players do
            local row = players[i]
            if row and getUnitForName(row.name) == unit then
                name = row.name
                break
            end
        end
    end
    if not name then
        return
    end
    local snapshot = buildSnapshotFromUnit(name, unit, "library")
    if snapshot then
        snapshot.guid = snapshot.guid or guid
        storeSnapshot(name, snapshot)
    end
end

local function bindLibraryCallbacks()
    if callbacksBound then
        return
    end
    local lgt = getLgt()
    if not (lgt and lgt.RegisterCallback) then
        return
    end
    lgt.RegisterCallback(module, "LibGroupTalents_Update", handleLibraryUpdate)
    lgt.RegisterCallback(module, "LibGroupTalents_RoleChange", handleLibraryUpdate)
    lgt.RegisterCallback(module, "LibGroupTalents_UpdateComplete", function()
        module:RefreshRaidSpecs({ reason = "library_complete" })
    end)
    callbacksBound = true
end

bindLibraryCallbacks()

if Bus and Bus.RegisterCallback then
    Bus.RegisterCallback(Events.GetWowForwarded and Events.GetWowForwarded("READY_CHECK"), function()
        module:RefreshRaidSpecs({ reason = "ready_check" })
    end)
end
```

Finish the file with registry metadata:

```lua
local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/SpecInspect", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Services/Raid/Roster",
        },
    })
    registry.SetLoaded("Services/SpecInspect")
end
```

- [ ] **Step 3: Add TOC load order**

In `!KRT/!KRT.toc`, add:

```toc
Services\SpecInspect.lua
```

Place it after `Services\Raid\Roster.lua` and before UI consumers such as `EntryPoints\SlashEvents.lua`.

- [ ] **Step 4: Run service tests**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
lua tests/module_registry_services_spec.lua
```

Expected: PASS for these service checks; UI/slash checks are handled in Task 3 and Task 4.

- [ ] **Step 5: Commit service implementation**

Run:

```powershell
git add !KRT/Modules/Events.lua !KRT/Init.lua !KRT/Services/SpecInspect.lua !KRT/!KRT.toc
git add tests/spec_inspect_service_spec.lua tests/module_registry_services_spec.lua
git commit -m "feat: add spec inspect service"
```

---

### Task 3: Add Slash Commands And Localization

**Files:**
- Modify: `!KRT/EntryPoints/SlashEvents.lua`
- Modify: `!KRT/Localization/localization.en.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`

- [ ] **Step 1: Add localization strings**

In `!KRT/Localization/localization.en.lua`, near the command strings, add:

```lua
L.StrCmdSpecInspect = "refresh cached spec icons; use force to refresh all inspectable raid members"
L.MsgSpecInspectNoService = "Spec inspect service is unavailable."
L.MsgSpecInspectRefresh = "Spec inspect refresh: queued=%d cached=%d skipped=%d."
```

- [ ] **Step 2: Add aliases and help**

In `!KRT/EntryPoints/SlashEvents.lua`, add:

```lua
local cmdSpecInspect = { "specinspect", "inspectspec" }
```

Add it near the command alias declarations, then add this help entry to `showHelp()`:

```lua
printHelp("specinspect [force]", L.StrCmdSpecInspect)
```

Add this topic branch to `handleHelpCommand`:

```lua
elseif topic == "specinspect" or topic == "inspectspec" then
    addon:info(format(L.StrCmdCommands, "krt specinspect"), "KRT")
    printHelp("force", L.StrCmdSpecInspect)
```

- [ ] **Step 3: Implement slash handler**

Add this local handler before `handleSlashCommand`:

```lua
local function handleSpecInspectCommand(rest)
    local sub = Strings.SplitArgs(rest)
    local service = Services and Services.SpecInspect or nil
    if not service then
        addon:warn(L.MsgSpecInspectNoService)
        return
    end

    local result
    if sub == "force" then
        result = service:ForceRefreshRaidSpecs("slash_force")
    else
        result = service:RefreshRaidSpecs({ reason = "slash" })
    end
    result = result or {}
    addon:info(
        L.MsgSpecInspectRefresh,
        tonumber(result.refreshed) or 0,
        tonumber(result.cached) or 0,
        tonumber(result.skipped) or 0
    )
end
```

Register the aliases near the other `registerAliases` calls:

```lua
registerAliases(cmdSpecInspect, handleSpecInspectCommand)
```

- [ ] **Step 4: Run slash tests**

Run:

```powershell
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected: PASS.

- [ ] **Step 5: Commit slash commands**

Run:

```powershell
git add !KRT/EntryPoints/SlashEvents.lua !KRT/Localization/localization.en.lua
git add tests/module_registry_ui_entrypoints_spec.lua
git commit -m "feat: add spec inspect slash command"
```

---

### Task 4: Render Spec Icons In Master Loot Rows

**Files:**
- Modify: `!KRT/UI/Templates/Common.xml`
- Modify: `!KRT/Modules/UI/Visuals.lua`
- Modify: `!KRT/Controllers/Master.lua`
- Modify: `tests/master_roll_list_copy_spec.lua`

- [ ] **Step 1: Add XML texture to `KRTSelectPlayerTemplate`**

In `!KRT/UI/Templates/Common.xml`, inside `KRTSelectPlayerTemplate` ARTWORK layer, add the spec icon
before `$parentName`:

```xml
<Texture name="$parentSpecIcon" hidden="true">
    <Size>
        <AbsDimension x="12" y="12" />
    </Size>
    <Anchors>
        <Anchor point="LEFT" relativePoint="LEFT">
            <Offset>
                <AbsDimension x="2" y="0" />
            </Offset>
        </Anchor>
    </Anchors>
</Texture>
```

Move `$parentStar` to x `16` and move `$parentName` left anchor to x `30`:

```xml
<AbsDimension x="16" y="0" />
```

```xml
<AbsDimension x="30" y="0" />
```

- [ ] **Step 2: Render the spec icon in `Visuals.lua`**

In `getMasterRollRowRefs`, add:

```lua
specIcon = "SpecIcon",
```

In `Rows.DrawMasterRollRow`, add:

```lua
local specIcon = ui and (ui.specIcon or ui.SpecIcon) or nil
if specIcon then
    if data.specIcon and data.specIcon ~= "" then
        specIcon:SetTexture(data.specIcon)
        if specIcon.SetTexCoord then
            specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        specIcon:Show()
    else
        specIcon:Hide()
    end
end
```

- [ ] **Step 3: Enrich Master roll row data**

In `!KRT/Controllers/Master.lua`, update `copyMasterRollRowForList(source)`:

```lua
local specInspect = Services.SpecInspect
if specInspect and specInspect.GetPlayerSpecSnapshot and copy.name then
    local spec = specInspect:GetPlayerSpecSnapshot(copy.name)
    if spec then
        copy.specIcon = spec.icon
        copy.specName = spec.specName
        copy.specRole = spec.role
    end
end
```

Add `"SpecIcon"` to the Master roll list `_rowParts`:

```lua
_rowParts = { "Name", "Roll", "Counter", "Info", "Star", "SpecIcon" },
```

Register a refresh callback near the other Master bus callbacks:

```lua
Bus.RegisterCallback(InternalEvents.SpecInspectUpdated, function()
    invalidateRollUiModel()
    module._dirtyFlags.rolls = true
    module:RequestRefresh()
end)
```

- [ ] **Step 4: Extend the Master row copy test**

In `tests/master_roll_list_copy_spec.lua`, add checks:

```lua
assert(master:find("GetPlayerSpecSnapshot", 1, true), "Master roll rows must copy spec snapshot fields")
assert(master:find('"SpecIcon"', 1, true), "Master roll list must acquire the spec icon row part")
assert(master:find("SpecInspectUpdated", 1, true), "Master roll list must refresh on spec updates")
```

- [ ] **Step 5: Run Master UI tests**

Run:

```powershell
lua tests/master_roll_list_copy_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected: PASS.

- [ ] **Step 6: Commit Master row rendering**

Run:

```powershell
git add !KRT/UI/Templates/Common.xml !KRT/Modules/UI/Visuals.lua !KRT/Controllers/Master.lua
git add tests/master_roll_list_copy_spec.lua
git commit -m "feat: show spec icons in master loot rows"
```

---

### Task 5: Render Spec Icons In Loot Counter Rows

**Files:**
- Modify: `!KRT/Widgets/LootCounter.lua`
- Test: `tests/module_registry_ui_entrypoints_spec.lua`

- [ ] **Step 1: Add row icon layout**

In `!KRT/Widgets/LootCounter.lua`, add constants near the layout constants:

```lua
local SPEC_ICON_SIZE = 14
local SPEC_ICON_GAP = 4
```

In `ensureRow`, before creating `row.name`, create:

```lua
row.specIcon = row:CreateTexture(nil, "OVERLAY")
row.specIcon:SetSize(SPEC_ICON_SIZE, SPEC_ICON_SIZE)
row.specIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
row.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
row.specIcon:Hide()
```

Change the name left anchor:

```lua
row.name:SetPoint("LEFT", row, "LEFT", SPEC_ICON_SIZE + SPEC_ICON_GAP, 0)
```

- [ ] **Step 2: Update icon during refresh**

In `refreshLootCounter`, after resolving `name`, add:

```lua
local specInspect = Services.SpecInspect
local spec = specInspect and specInspect.GetPlayerSpecSnapshot and specInspect:GetPlayerSpecSnapshot(name) or nil
local specIcon = spec and spec.icon or nil
if row._lastSpecIcon ~= specIcon then
    if specIcon and specIcon ~= "" then
        row.specIcon:SetTexture(specIcon)
        row.specIcon:Show()
    else
        row.specIcon:Hide()
    end
    row._lastSpecIcon = specIcon
end
```

Add the bus refresh callback near existing Loot Counter bus callbacks:

```lua
Bus.RegisterCallback(InternalEvents.SpecInspectUpdated, requestRefresh)
```

- [ ] **Step 3: Add source check**

In `tests/module_registry_ui_entrypoints_spec.lua`, add:

```lua
local lootCounterSource = read("!KRT/Widgets/LootCounter.lua")
assertContains(lootCounterSource, "row.specIcon", "LootCounter must render spec icons")
assertContains(lootCounterSource, "GetPlayerSpecSnapshot", "LootCounter must consume SpecInspect snapshots")
assertContains(lootCounterSource, "SpecInspectUpdated", "LootCounter must refresh on spec updates")
```

- [ ] **Step 4: Run Loot Counter checks**

Run:

```powershell
lua tests/module_registry_ui_entrypoints_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected: PASS.

- [ ] **Step 5: Commit Loot Counter rendering**

Run:

```powershell
git add !KRT/Widgets/LootCounter.lua tests/module_registry_ui_entrypoints_spec.lua
git commit -m "feat: show spec icons in loot counter"
```

---

### Task 6: Changelog, Full Checks, And Parent Review

**Files:**
- Modify: `!KRT/CHANGELOG.md`

- [ ] **Step 1: Add changelog entry**

Under `## Unreleased` in `!KRT/CHANGELOG.md`, add:

```markdown
- Added runtime spec icons beside player names in Master Loot and Loot Counter, backed by
  `LibGroupTalents-1.0` and refreshable with `/krt specinspect`.
```

- [ ] **Step 2: Run focused tests**

Run:

```powershell
lua tests/spec_inspect_service_spec.lua
lua tests/master_roll_list_copy_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected: all PASS.

- [ ] **Step 3: Run repo gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected: all PASS.

- [ ] **Step 4: Review final diff**

Run:

```powershell
git diff --stat HEAD
git diff -- !KRT tests
```

Review requirements:

- No direct `NotifyInspect(` in KRT runtime.
- No changes under `!KRT/Libs/*`.
- `SpecInspect` has no frame/UI references.
- `READY_CHECK` is forwarded through Init/Bus, not handled by a service frame.
- Master row spec icon and star have separate anchors.
- Loot Counter reserves a stable icon slot.
- Slash command output uses localized strings.
- `!KRT/CHANGELOG.md` has the user-visible change under `## Unreleased`.

- [ ] **Step 5: Commit final changelog/check adjustments**

Run:

```powershell
git add !KRT/CHANGELOG.md
git commit -m "docs: note spec inspector"
```

- [ ] **Step 6: Parent review checkpoint**

The parent agent must review the final diff. If Spark implemented more than the plan, changed vendored
libraries, introduced direct inspect calls, skipped tests, or made broad refactors, the parent must
request a corrective patch before final response.

---

## Manual Smoke Checklist

- Login on WotLK 3.3.5a with no Lua errors.
- Join a raid and run `/krt`.
- Open Master Loot; player rows remain aligned before spec data is available.
- Run a ready check; known specs appear progressively without UI jumps.
- Run `/krt specinspect`; output reports queued/cached/skipped counts.
- Run `/krt specinspect force`; inspectable raid members refresh through the library.
- Open Loot Counter; names remain aligned and spec icons show when known.
- Confirm Master winner star and spec icon do not overlap.
- Confirm `/reload` loses runtime spec cache without SavedVariables migration errors.
