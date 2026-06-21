# RaidInspect Attendance Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-shot raid-start inspect snapshot service and show attendance plus inspect
snapshots in the dedicated Raid Attendance window.

**Architecture:** `addon.Services.RaidInspect` owns inspect queueing, compact persisted snapshots,
runtime queue state, and inspect event handling. `addon.Services.Raid` keeps attendance lifecycle
ownership. `addon.Services.Logger.View` enriches read-only attendance rows, and
`addon.Controllers.Logger` renders the two-column Attendance UI without triggering inspect.

**Tech Stack:** WoW WotLK 3.3.5a, Lua 5.1, KRT module registry, `addon.Bus`,
`feature.Timer`, forwarded WoW events, KRT XML templates, source-level Lua tests, in-game smoke.

---

## Classification And Delegation

- Planning-only change classification: `bounded`.
- Future implementation classification: `complex-orchestrated`.
- Reason: implementation touches a new service, event forwarding, raid attendance lifecycle,
  SavedVariables content, TOC order, Logger read-models, FrameXML, controller row rendering, source
  tests, and changelog.
- Use the project 55to53 workflow for implementation. Parent maps/reviews, `spark_implementer`
  applies narrow code patches, and parent reviews/corrects before closing.
- `code-mapper` is recommended before implementation if any mapped line numbers drift from this
  plan.

## Non-Negotiable Behavior

- Attendance tracking remains continuous through roster deltas.
- RaidInspect runs once after `RaidCreate`, delayed by 3 seconds.
- RaidInspect does not start from frame open, row selection, or `RaidRosterDelta`.
- Manual force is allowed for one player only when the selected raid is the current raid.
- `queued` and `pending` are runtime-only. Persist only `ready`, `skipped`, `timeout`, and `failed`.
- Old raids with no `raid.inspect` display `Not inspected`.
- Do not sync `raid.inspect` through DBSyncer and do not add inspect fields to exports in this
  phase.
- Keep all runtime code Lua 5.1 and WotLK 3.3.5a compatible. Do not use `C_Timer`, `C_*`,
  `GetInspectSpecialization`, `Enum`, `table.move`, `bit32`, or Retail APIs.
- Do not cite other addons in code, comments, docs, commits, UI text, or diagnostics.

## Current Code Map

- `!KRT/Modules/Events.lua`
  Owns canonical internal and forwarded WoW event names. `Events.GetWowForwarded(eventName)` returns
  `Events.Wow[eventName]` or `"wow." .. eventName`.
- `!KRT/Init.lua`
  Seeds bootstrap event names in `seedBootstrapEvents()`, registers `addonEvents`, and maps selected
  WoW events to bus events through `wowBusEvents`.
- `!KRT/Services/Raid/Attendance.lua`
  Currently consumes only `Internal.RaidRosterDelta` and exposes `module:GetAttendanceEntry`.
- `!KRT/Services/Raid/State.lua`
  `module:Create()` populates `raid.players`, sets current raid, and emits `Internal.RaidCreate`.
  `module:End()` fills missing `player.leave`, sets `raid.endTime`, and clears current raid.
- `!KRT/Services/Raid/Roster.lua`
  Exposes `module:GetPlayers`, `module:GetPlayerName`, `module:GetPlayerClass`, and
  `module:GetUnitID(name)`.
- `!KRT/Services/Logger/View.lua`
  `View:FillRaidAttendeesList(out, raid)` uses `Database.GetRaidQueriesOrNil().GetRaidAttendance`
  when available and falls back to `raid.players`.
- `!KRT/Controllers/Logger.lua`
  `initializeRaidAttendanceFrame()` owns the dedicated Attendance window. Current player list row
  parts are `{ "Name", "Join", "Leave" }`.
- `!KRT/UI/Logger.xml`
  `KRTLoggerRaidAttendeeButton` currently defines `Name`, `Join`, and `Leave` font strings.
  `KRTRaidAttendanceRaidAttendees` currently has Name, Join, and Leave headers and width 265.
- `!KRT/!KRT.toc`
  `Services\SpecInspect.lua` loads after `Services\Raid\Session.lua`; `Services\Chat.lua` follows.

## File Structure

- Create `!KRT/Services/RaidInspect.lua`
  UI-free service. Owns one active inspect request, runtime queue state, compact persisted snapshots
  under `raid.inspect.players[playerNid]`, and bus updates.
- Modify `!KRT/!KRT.toc`
  Add `Services\RaidInspect.lua` after `Services\SpecInspect.lua` and before `Services\Chat.lua`.
- Modify `!KRT/Modules/Events.lua`
  Add `Internal.RaidAttendanceChanged`, `Internal.RaidInspectStarted`,
  `Internal.RaidInspectUpdated`, and `Internal.RaidInspectCompleted`.
- Modify `!KRT/Init.lua`
  Seed and forward `INSPECT_READY` and `PLAYER_REGEN_ENABLED` using the existing `Events.Wow`
  pattern.
- Modify `!KRT/Services/Raid/Attendance.lua`
  Add initial roster seeding on `RaidCreate`, open-segment close-all helper, public
  `SeedAttendanceFromCurrentRoster`, and public `CloseAttendanceForRaid`.
- Modify `!KRT/Services/Raid/State.lua`
  Call `module:CloseAttendanceForRaid(raid, currentTime, "raid_end")` before clearing current raid.
- Modify `!KRT/Services/Logger/View.lua`
  Enrich attendance rows with inspect data. Do not start inspect from View.
- Modify `!KRT/Controllers/Logger.lua`
  Change the dedicated Attendance window layout to two visible panels, render iLvl/spec/inspect
  columns, add right-click force, optional Force button behavior, sorting, and refresh callbacks.
- Modify `!KRT/UI/Logger.xml`
  Add attendee row fields and headers for `Ilvl`, `Spec`, and `InspectStatus`/`Inspect`.
- Modify `!KRT/CHANGELOG.md`
  Add an Unreleased behavior note.
- Modify `docs/RAID_SCHEMA.md` and `docs/SV_SCHEMA.md`
  Document optional `raid.inspect` compact snapshot fields.
- Add `tests/raid_inspect_service_spec.lua`
  Runtime harness for queue, force, completion, runtime-only states, and validation behavior.
- Add or modify `tests/raid_inspect_source_contract_spec.lua`
  Source contract coverage for no roster-delta trigger, load order, event forwarding, and UI wiring.
- Modify registry/source tests as needed:
  `tests/module_registry_services_spec.lua`, `tests/module_registry_ui_entrypoints_spec.lua`,
  `tests/logger_visual_refresh_spec.lua`, and targeted sections in `tests/release_stabilization_spec.lua`.

---

### Task 1: Add Failing Source Contracts

**Files:**
- Create: `tests/raid_inspect_source_contract_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
- Modify: `tests/logger_visual_refresh_spec.lua`

- [ ] **Step 1: Create the source contract spec**

Create `tests/raid_inspect_source_contract_spec.lua` with this content:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message .. " missing: " .. needle)
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message .. " must not contain: " .. needle)
end

local function assertBefore(text, left, right, message)
    local leftIndex = assert(text:find(left, 1, true), message .. " missing left: " .. left)
    local rightIndex = assert(text:find(right, 1, true), message .. " missing right: " .. right)
    assert(leftIndex < rightIndex, message)
end

local toc = read("!KRT/!KRT.toc")
local events = read("!KRT/Modules/Events.lua")
local init = read("!KRT/Init.lua")
local attendance = read("!KRT/Services/Raid/Attendance.lua")
local raidState = read("!KRT/Services/Raid/State.lua")
local view = read("!KRT/Services/Logger/View.lua")
local logger = read("!KRT/Controllers/Logger.lua")
local xml = read("!KRT/UI/Logger.xml")

assertContains(toc, "Services\\RaidInspect.lua", "TOC must load RaidInspect")
assertBefore(toc, "Services\\SpecInspect.lua", "Services\\RaidInspect.lua", "RaidInspect load order")
assertBefore(toc, "Services\\RaidInspect.lua", "Services\\Chat.lua", "RaidInspect load order")

local raidInspect = read("!KRT/Services/RaidInspect.lua")
assertContains(raidInspect, "Timer.BindMixin(module, \"RaidInspect\")", "RaidInspect must use Timer mixin")
assertContains(raidInspect, "InternalEvents.RaidCreate", "RaidInspect must start from RaidCreate")
assertContains(raidInspect, "INSPECT_READY", "RaidInspect must consume forwarded INSPECT_READY")
assertContains(raidInspect, "PLAYER_REGEN_ENABLED", "RaidInspect must resume after combat")
assertContains(raidInspect, "NotifyInspect(", "RaidInspect owns NotifyInspect calls")
assertNotContains(raidInspect, "RaidRosterDelta", "RaidInspect must not listen to roster deltas")
assertNotContains(raidInspect, "C_Timer", "RaidInspect must not use Retail timers")
assertNotContains(raidInspect, "C_", "RaidInspect must not use C_* APIs")
assertNotContains(raidInspect, "GetInspectSpecialization", "RaidInspect must not use Retail inspect API")
assertNotContains(raidInspect, "GetSpecialization", "RaidInspect must not use Retail specialization API")
assertNotContains(raidInspect, "table.move", "RaidInspect must stay Lua 5.1 compatible")
assertNotContains(raidInspect, "bit32", "RaidInspect must stay Lua 5.1 compatible")

assertContains(events, "Internal.RaidAttendanceChanged", "Events must expose attendance refresh event")
assertContains(events, "Internal.RaidInspectStarted", "Events must expose inspect start event")
assertContains(events, "Internal.RaidInspectUpdated", "Events must expose inspect update event")
assertContains(events, "Internal.RaidInspectCompleted", "Events must expose inspect completion event")
assertContains(init, "Wow.InspectReady", "Init must seed InspectReady forwarded event")
assertContains(init, "Wow.PlayerRegenEnabled", "Init must seed PlayerRegenEnabled forwarded event")
assertContains(init, "INSPECT_READY = \"INSPECT_READY\"", "Init must register INSPECT_READY")
assertContains(init, "PLAYER_REGEN_ENABLED = \"PLAYER_REGEN_ENABLED\"", "Init must register PLAYER_REGEN_ENABLED")

assertContains(attendance, "SeedAttendanceFromCurrentRoster", "Attendance must seed initial roster")
assertContains(attendance, "CloseAttendanceForRaid", "Attendance must close open segments on raid end")
assertContains(attendance, "InternalEvents.RaidAttendanceChanged", "Attendance must emit refresh event")
assertContains(raidState, "CloseAttendanceForRaid", "Raid End must close attendance")

assertContains(view, "getRaidInspectSnapshot", "Logger View must read RaidInspect snapshots")
assertContains(view, "enrichAttendanceRowsWithInspect", "Logger View must enrich attendance rows")
assertNotContains(view, "StartRaidSnapshot", "Logger View must not start inspect")
assertNotContains(view, "ForcePlayer", "Logger View must not force inspect")

assertContains(xml, "$parentIlvl", "Attendance row template must include iLvl text")
assertContains(xml, "$parentSpec", "Attendance row template must include spec text")
assertContains(xml, "$parentInspectStatus", "Attendance row template must include inspect status text")
assertContains(xml, "$parentHeaderIlvl", "Attendance list must include iLvl header")
assertContains(xml, "$parentHeaderSpec", "Attendance list must include spec header")
assertContains(xml, "$parentHeaderInspect", "Attendance list must include inspect header")

assertContains(logger, "RAID_INSPECT_SLOTS", "Logger must define inspect slot render order")
assertContains(logger, "renderAttendanceInspectIcons", "Logger must render inspect icons")
assertContains(logger, "Services.RaidInspect:ForcePlayer", "Logger must allow manual force")
assertContains(logger, "InternalEvents.RaidInspectUpdated", "Logger must refresh on inspect update")
assertContains(logger, "setAttendancePanelVisible(refs.bosses, false)", "Attendance frame must hide bosses panel")
assertNotContains(logger, "StartRaidSnapshot", "Logger controller must not start raid inspect")

print("raid inspect source contract passed")
```

- [ ] **Step 2: Run the new source contract and verify it fails**

Run:

```powershell
lua tests/raid_inspect_source_contract_spec.lua
```

Expected: FAIL because `!KRT/Services/RaidInspect.lua` does not exist yet and event/UI wiring has
not been added.

- [ ] **Step 3: Update module registry source specs**

In `tests/module_registry_services_spec.lua`, add an expected service entry near
`Services/SpecInspect`:

```lua
local expectedRaidInspectService = {
    name = "Services/RaidInspect",
    path = "!KRT/Services/RaidInspect.lua",
    deps = {
        "Init",
        "Modules/ModuleRegistry",
        "Modules/Events",
        "Modules/Bus",
        "Modules/Timer",
        "Modules/Strings",
        "Services/Raid/Roster",
        "Services/Raid/Attendance",
    },
}
```

Add it to the service expectation list and TOC path map used by the file. Keep the exact
`assertServiceRegistryContract(expectedRaidInspectService)` style already used for
`expectedSpecInspectService`.

In `tests/module_registry_ui_entrypoints_spec.lua`, add the same service metadata only if that test
mirrors all service load contracts. Use the same dependency order.

- [ ] **Step 4: Update logger visual source spec**

In `tests/logger_visual_refresh_spec.lua`, add source assertions:

```lua
assert(logger:find("RAID_INSPECT_SLOTS", 1, true), "Logger must define inspect item slot order")
assert(logger:find("renderAttendanceInspectIcons", 1, true), "Logger must render inspect icons in attendance rows")
assert(logger:find("HeaderIlvl", 1, true), "Logger must bind iLvl sort header")
assert(logger:find("HeaderSpec", 1, true), "Logger must bind spec sort header")
assert(loggerXml:find('$parentHeaderInspect', 1, true), "Attendance XML must define Inspect items header")
assert(loggerXml:find('$parentInspectStatus', 1, true), "Attendance rows must define inspect status anchor")
```

- [ ] **Step 5: Run source contracts and verify failures are meaningful**

Run:

```powershell
lua tests/raid_inspect_source_contract_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected: each failure names missing RaidInspect, event, XML, or registry wiring.

- [ ] **Step 6: Commit failing source contracts**

```powershell
git add `
  tests/raid_inspect_source_contract_spec.lua `
  tests/module_registry_services_spec.lua `
  tests/module_registry_ui_entrypoints_spec.lua `
  tests/logger_visual_refresh_spec.lua
git commit -m "test: cover raid inspect attendance contracts"
```

---

### Task 2: Add Failing RaidInspect Runtime Harness

**Files:**
- Create: `tests/raid_inspect_service_spec.lua`

- [ ] **Step 1: Create the runtime harness**

Create `tests/raid_inspect_service_spec.lua` with this content:

```lua
local busEvents = {}
local timers = {}
local notifyCalls = {}
local clearCalls = 0
local now = 1000
local currentRaid = 1
local inCombat = false

local raid = {
    raidNid = 1,
    players = {
        { playerNid = 1, name = "Alice", class = "DRUID", join = 1000 },
        { playerNid = 2, name = "Bob", class = "MAGE", join = 1000 },
    },
    attendance = {},
}

local function fire(eventName, ...)
    local list = busEvents[eventName] or {}
    for i = 1, #list do
        list[i](eventName, ...)
    end
end

local function newAddon()
    local addon = { Services = {}, Database = {} }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
        Events = {
            Internal = {
                RaidCreate = "RaidCreate",
                RaidInspectStarted = "RaidInspectStarted",
                RaidInspectUpdated = "RaidInspectUpdated",
                RaidInspectCompleted = "RaidInspectCompleted",
            },
            Wow = {
                InspectReady = "wow.INSPECT_READY",
                PlayerRegenEnabled = "wow.PLAYER_REGEN_ENABLED",
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
        Timer = {
            BindMixin = function(target)
                function target:ScheduleTimer(fn, delay)
                    timers[#timers + 1] = { fn = fn, delay = delay }
                    return #timers
                end
                function target:CancelTimer(handle)
                    if timers[handle] then
                        timers[handle].cancelled = true
                    end
                end
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

    addon.Database.GetFeatureShared = function()
        return feature
    end
    addon.Database.GetCurrentRaid = function()
        return currentRaid
    end
    addon.Database.EnsureRaidById = function(id)
        if tonumber(id) == 1 then
            return raid
        end
        return nil
    end
    addon.Database.EnsureRaidSchema = function(row)
        row.players = row.players or {}
        row.attendance = row.attendance or {}
        return row
    end
    addon.Database.GetPlayerName = function()
        return "Player"
    end

    feature.EnsureServiceNamespace = function(...)
        local scope = feature.Services
        local addonScope = addon.Services
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            scope[key] = scope[key] or {}
            addonScope[key] = scope[key]
            scope = scope[key]
            addonScope = addonScope[key]
        end
        return scope
    end

    feature.Services.Raid = {
        GetUnitID = function(_, name)
            return ({ Alice = "raid1", Bob = "raid2" })[name] or "none"
        end,
        GetPlayerName = function(_, playerNid)
            if tonumber(playerNid) == 1 then
                return "Alice"
            elseif tonumber(playerNid) == 2 then
                return "Bob"
            end
            return nil
        end,
        GetPlayers = function()
            return raid.players
        end,
    }

    return addon
end

local function loadAddonFile(addon, path)
    local chunk = assert(loadfile(path))
    setfenv(
        chunk,
        setmetatable({
            select = select,
            type = type,
            tonumber = tonumber,
            tostring = tostring,
            pairs = pairs,
            ipairs = ipairs,
            table = table,
            math = math,
            string = string,
            time = function()
                return now
            end,
            GetTime = function()
                return now
            end,
            InCombatLockdown = function()
                return inCombat
            end,
            UnitExists = function(unit)
                return unit == "raid1" or unit == "raid2"
            end,
            UnitIsConnected = function(unit)
                return unit ~= "raid2"
            end,
            UnitGUID = function(unit)
                return ({ raid1 = "GUID-A", raid2 = "GUID-B" })[unit]
            end,
            UnitLevel = function()
                return 80
            end,
            CanInspect = function(unit)
                return unit == "raid1"
            end,
            CheckInteractDistance = function(unit, index)
                return unit == "raid1" and index == 1
            end,
            NotifyInspect = function(unit)
                notifyCalls[#notifyCalls + 1] = unit
            end,
            ClearInspectPlayer = function()
                clearCalls = clearCalls + 1
            end,
            GetInventoryItemLink = function(unit, slot)
                if unit == "raid1" and (slot == 1 or slot == 16) then
                    local itemId = tostring(slot == 1 and 51242 or 50737)
                    return "|cffa335ee|Hitem:" .. itemId
                        .. ":3817:40113:40113:0:0:0:0:80|h[Test Item]|h|r"
                end
                return nil
            end,
            GetInventoryItemTexture = function(unit, slot)
                if unit == "raid1" and (slot == 1 or slot == 16) then
                    return "Interface\\Icons\\INV_Misc_QuestionMark"
                end
                return nil
            end,
            GetInventoryItemQuality = function(unit, slot)
                if unit == "raid1" and (slot == 1 or slot == 16) then
                    return 4
                end
                return nil
            end,
            GetItemInfo = function()
                return nil, nil, nil, 264
            end,
            GetTalentTabInfo = function(tab, inspect)
                assert(inspect == true, "talents must be read from inspected target")
                if tab == 1 then
                    return "Balance", "Interface\\Icons\\Spell_Nature_StarFall", 57
                elseif tab == 2 then
                    return "Feral Combat", "Interface\\Icons\\Ability_Druid_CatForm", 0
                elseif tab == 3 then
                    return "Restoration", "Interface\\Icons\\Spell_Nature_HealingTouch", 14
                end
                return nil
            end,
            CreateFrame = function(kind, name)
                local frame = {}
                function frame:SetOwner() end
                function frame:ClearLines() end
                function frame:SetHyperlink() end
                function frame:NumLines()
                    return 0
                end
                return frame
            end,
            UIParent = {},
            ITEM_LEVEL = "Item Level %d",
            _G = setmetatable({}, {
                __index = function()
                    return nil
                end,
            }),
        }, { __index = _G })
    )
    chunk("!KRT", addon)
end

local addon = newAddon()
loadAddonFile(addon, "!KRT/Services/RaidInspect.lua")
local service = assert(addon.Services.RaidInspect, "RaidInspect service must load")

local ok, reason = service:StartRaidSnapshot(nil)
assert(ok == false and reason == "missing_raid", "nil raid should be rejected")

ok, reason = service:StartRaidSnapshot(2)
assert(ok == false and reason == "not_current_raid", "historical raid should be rejected")

ok, reason = service:ForcePlayer(2, 1)
assert(ok == false and reason == "not_current_raid", "historical force should be rejected")

ok, reason = service:ForcePlayer(1, 99)
assert(ok == false and reason == "missing_player", "missing player should be rejected")

ok = service:StartRaidSnapshot(1, { reason = "raid_start" })
assert(ok == true, "current raid snapshot should start")
assert(#timers > 0, "snapshot should schedule work")

timers[#timers].fn()
assert(#notifyCalls == 1 and notifyCalls[1] == "raid1", "Alice should be the first inspect target")
local runtime = assert(service:GetRuntimeStatus(1, 1), "Alice should have runtime status")
assert(runtime.status == "pending", "active player should be pending")
assert(not (raid.inspect and raid.inspect.players and raid.inspect.players[1]), "pending must not persist")

service:StartRaidSnapshot(1, { reason = "raid_start" })
assert(#notifyCalls == 1, "duplicate queued active player should not notify twice")

fire("wow.INSPECT_READY", "GUID-A")
local alice = assert(service:GetSnapshot(raid, 1), "Alice snapshot should exist")
assert(alice.status == "ready", "Alice should be ready after INSPECT_READY")
assert(alice.avgIlvl == 264, "average iLvl should be computed from captured items")
assert(alice.specName == "Balance", "main talent tree should be captured")
assert(alice.items and alice.items[1] and alice.items[16], "ready snapshot should store inspected items")
assert(clearCalls > 0, "inspect completion should clear inspect target")

local bob = service:GetSnapshot(raid, 2)
assert(bob and bob.status == "skipped" and bob.reason == "offline", "offline Bob should be skipped")

ok = service:ForcePlayer(1, 1)
assert(ok == true, "current raid player force should queue even when ready")

assert(
    not (raid.inspect.players[1].status == "queued" or raid.inspect.players[1].status == "pending"),
    "runtime statuses must not persist"
)

print("raid inspect service spec passed")
```

- [ ] **Step 2: Run the harness and verify it fails before implementation**

Run:

```powershell
lua tests/raid_inspect_service_spec.lua
```

Expected: FAIL because `!KRT/Services/RaidInspect.lua` does not exist.

- [ ] **Step 3: Commit failing runtime harness**

```powershell
git add tests/raid_inspect_service_spec.lua
git commit -m "test: cover raid inspect service behavior"
```

---

### Task 3: Wire Events And Attendance Lifecycle

**Files:**
- Modify: `!KRT/Modules/Events.lua`
- Modify: `!KRT/Init.lua`
- Modify: `!KRT/Services/Raid/Attendance.lua`
- Modify: `!KRT/Services/Raid/State.lua`

- [ ] **Step 1: Add internal event names**

In `!KRT/Modules/Events.lua`, after the existing raid event constants, add:

```lua
Internal.RaidAttendanceChanged = Internal.RaidAttendanceChanged or "RaidAttendanceChanged"
Internal.RaidInspectStarted = Internal.RaidInspectStarted or "RaidInspectStarted"
Internal.RaidInspectUpdated = Internal.RaidInspectUpdated or "RaidInspectUpdated"
Internal.RaidInspectCompleted = Internal.RaidInspectCompleted or "RaidInspectCompleted"
```

- [ ] **Step 2: Seed forwarded inspect events**

In `!KRT/Init.lua`, inside `seedBootstrapEvents()`, add:

```lua
Wow.InspectReady = Wow.InspectReady or "wow.INSPECT_READY"
Wow.PlayerRegenEnabled = Wow.PlayerRegenEnabled or "wow.PLAYER_REGEN_ENABLED"
```

In `addonEvents`, add:

```lua
INSPECT_READY = "INSPECT_READY",
PLAYER_REGEN_ENABLED = "PLAYER_REGEN_ENABLED",
```

In `wowBusEvents`, add:

```lua
INSPECT_READY = WowEvents.InspectReady,
PLAYER_REGEN_ENABLED = WowEvents.PlayerRegenEnabled,
```

- [ ] **Step 3: Add attendance helpers**

In `!KRT/Services/Raid/Attendance.lua`, below `openSegment`, add:

```lua
local function findRaidPlayerByName(raid, name)
    local players = raid and raid.players or nil
    if type(players) ~= "table" or not name then
        return nil
    end

    for i = #players, 1, -1 do
        local player = players[i]
        if type(player) == "table" and player.name == name then
            return player
        end
    end

    return nil
end

local function closeAllOpenSegments(raid, timestamp)
    local attendance = raid and raid.attendance or nil
    local changed = false

    if type(attendance) ~= "table" then
        return false
    end

    for i = 1, #attendance do
        local entry = attendance[i]
        if type(entry) == "table" then
            changed = closeOpenSegment(entry, timestamp) or changed
        end
    end

    return changed
end
```

- [ ] **Step 4: Add attendance public methods**

In `!KRT/Services/Raid/Attendance.lua`, before the existing `GetAttendanceEntry`, add:

```lua
function module:SeedAttendanceFromCurrentRoster(raidId, reason)
    local resolvedRaidId = tonumber(raidId) or tonumber(Database.GetCurrentRaid()) or 0
    if resolvedRaidId <= 0 then
        return false
    end

    local raid = Database.EnsureRaidById(resolvedRaidId)
    if not raid then
        return false
    end

    Database.EnsureRaidSchema(raid)

    local timestamp = Time.GetCurrentTime()
    local changed = false
    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0

    for i = 1, numRaid do
        local name, _, subgroup, _, _, _, _, online = GetRaidRosterInfo(i)
        if name and name ~= "" then
            local player = findRaidPlayerByName(raid, name)
            local playerNid = player and tonumber(player.playerNid) or nil

            if playerNid and playerNid > 0 then
                local entry = ensureAttendanceEntry(raid, playerNid)
                if entry then
                    local startTime = tonumber(player.join) or timestamp
                    openSegment(entry, startTime, subgroup, online)
                    changed = true
                end
            end
        end
    end

    if changed and Bus and InternalEvents and InternalEvents.RaidAttendanceChanged then
        Bus.TriggerEvent(InternalEvents.RaidAttendanceChanged, resolvedRaidId, reason or "seed")
    end

    return changed
end

function module:CloseAttendanceForRaid(raidOrId, timestamp, reason)
    local raid = type(raidOrId) == "table" and raidOrId or Database.EnsureRaidById(raidOrId)
    if not raid then
        return false
    end

    Database.EnsureRaidSchema(raid)

    local changed = closeAllOpenSegments(raid, tonumber(timestamp) or Time.GetCurrentTime())

    if changed and Bus and InternalEvents and InternalEvents.RaidAttendanceChanged then
        Bus.TriggerEvent(InternalEvents.RaidAttendanceChanged, tonumber(raid.raidNid), reason or "close")
    end

    return changed
end
```

- [ ] **Step 5: Register attendance seed on raid create**

In `!KRT/Services/Raid/Attendance.lua`, near the existing callback registration, add:

```lua
if Bus and Bus.RegisterCallback and InternalEvents and InternalEvents.RaidCreate then
    Bus.RegisterCallback(InternalEvents.RaidCreate, function(_, raidId)
        module:SeedAttendanceFromCurrentRoster(raidId, "raid_create")
    end)
end
```

Keep the existing `RaidRosterDelta` callback unchanged.

- [ ] **Step 6: Close attendance in Raid End**

In `!KRT/Services/Raid/State.lua`, inside `module:End()`, after `raid.endTime = currentTime`
and before `Database.SetCurrentRaid(nil)`, add:

```lua
if type(module.CloseAttendanceForRaid) == "function" then
    module:CloseAttendanceForRaid(raid, currentTime, "raid_end")
end
```

- [ ] **Step 7: Run targeted tests**

Run:

```powershell
lua tests/raid_inspect_source_contract_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check raid_hardening
```

Expected: source contract still fails only on missing RaidInspect, logger UI, and registry pieces;
Lua syntax and raid hardening pass.

- [ ] **Step 8: Commit event and attendance lifecycle changes**

```powershell
git add !KRT/Modules/Events.lua !KRT/Init.lua !KRT/Services/Raid/Attendance.lua !KRT/Services/Raid/State.lua
git commit -m "feat: seed and close raid attendance"
```

---

### Task 4: Add RaidInspect Service

**Files:**
- Create: `!KRT/Services/RaidInspect.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`

- [ ] **Step 1: Add TOC entry**

In `!KRT/!KRT.toc`, add `Services\RaidInspect.lua` exactly here:

```text
Services\Raid\Session.lua
Services\SpecInspect.lua
Services\RaidInspect.lua
Services\Chat.lua
```

- [ ] **Step 2: Create the service shell**

Create `!KRT/Services/RaidInspect.lua` with this header and dependency block:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.RaidInspect
-- events: listens RaidCreate, wow.INSPECT_READY, wow.PLAYER_REGEN_ENABLED
-- events: emits RaidInspectStarted, RaidInspectUpdated, RaidInspectCompleted

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Database = feature.Database
local Services = feature.Services
local Events = feature.Events
local Bus = feature.Bus
local Timer = feature.Timer
local Strings = feature.Strings

local InternalEvents = Events.Internal

local type, tonumber, tostring = type, tonumber, tostring
local tinsert, tremove = table.insert, table.remove
local floor = math.floor

feature.EnsureServiceNamespace("RaidInspect")
local module = Services.RaidInspect

Timer.BindMixin(module, "RaidInspect")

local INSPECT_THROTTLE_SECONDS = 1.75
local INSPECT_TIMEOUT_SECONDS = 8
local INSPECT_DELAY_AFTER_RAID_CREATE = 3.0

local SLOT_IDS = {
    1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18,
}

local FINAL_STATUSES = {
    ready = true,
    skipped = true,
    timeout = true,
    failed = true,
}

local queue = {}
local queued = {}
local active = nil
local inspectTimer = nil
local timeoutTimer = nil
local runtime = {}
```

- [ ] **Step 3: Implement compact data helpers**

Add helpers that:

- resolve a raid from id or table;
- resolve a player row by `playerNid`;
- create `raid.inspect = { players = {} }` only when persisting final data;
- normalize player names through `Strings.NormalizeName` when available;
- parse item links using the `item:` fields from the spec;
- store gem IDs only;
- compute average item level across captured items with item levels;
- never store runtime `queued` or `pending` under `raid.inspect`.

Use these status writers:

```lua
local function setRuntimeStatus(raidId, playerNid, status, reason)
    local key = makeQueueKey(raidId, playerNid)
    runtime[key] = {
        raidId = tonumber(raidId),
        playerNid = tonumber(playerNid),
        status = status,
        reason = reason,
    }
    return runtime[key]
end

local function clearRuntimeStatus(raidId, playerNid)
    runtime[makeQueueKey(raidId, playerNid)] = nil
end

local function persistFinalSnapshot(raid, player, status, reason, snapshot)
    if not FINAL_STATUSES[status] then
        return nil
    end

    raid.inspect = type(raid.inspect) == "table" and raid.inspect or {}
    raid.inspect.players = type(raid.inspect.players) == "table" and raid.inspect.players or {}

    local playerNid = tonumber(player and player.playerNid)
    local row = snapshot or {}
    row.playerNid = playerNid
    row.name = player and player.name or row.name
    row.status = status
    row.reason = reason
    row.inspectedAt = time()

    raid.inspect.players[playerNid] = row
    return row
end
```

- [ ] **Step 4: Implement queue validation and public methods**

Implement these public methods with the exact return contracts below:

```lua
function module:StartRaidSnapshot(raidId, opts)
    -- false, "missing_raid" when raidId is nil or cannot resolve.
    -- false, "not_current_raid" when raidId is not Database.GetCurrentRaid().
    -- true when at least validation passed, even if all players are already ready.
end

function module:ForcePlayer(raidId, playerNid)
    -- false, "not_current_raid" for historical raids.
    -- false, "missing_player" when playerNid is not in raid.players.
    -- true when exactly one current-raid player is queued with force=true.
end

function module:ForceRaid(raidId)
    -- false, "not_current_raid" for historical raids.
    -- true after queueing current raid players with force=true.
end

function module:GetPersistedSnapshot(raidOrId, playerNid)
    -- return raid.inspect.players[playerNid] or nil.
end

function module:GetRuntimeStatus(raidId, playerNid)
    -- return runtime[raidId:playerNid] or nil.
end

function module:GetSnapshot(raidOrId, playerNid)
    -- runtime queued/pending first, then persisted final snapshot, then nil.
end

function module:ClearQueue()
    -- cancel timers, clear queue/queued/runtime, clear active.
end
```

Queue only players already present in `raid.players` at the moment `StartRaidSnapshot` runs.
Skip an already `ready` persisted snapshot unless `opts.force == true`.

- [ ] **Step 5: Implement inspect processing**

Process one active inspect at a time:

```lua
local function processNext()
    if active then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        scheduleNext(0.2)
        return
    end
    if InspectFrame and InspectFrame:IsShown() then
        scheduleNext(INSPECT_THROTTLE_SECONDS)
        return
    end

    local request = tremove(queue, 1)
    if not request then
        emitCompletedIfIdle()
        return
    end

    queued[request.key] = nil

    if tonumber(Database.GetCurrentRaid()) ~= tonumber(request.raidId) then
        finalizeRequest(request, "skipped", "not_current_raid")
        return
    end

    local unit = resolveUnit(request)
    if not unit or unit == "none" then
        finalizeRequest(request, "skipped", "missing_unit")
        return
    end
    if UnitIsConnected and UnitIsConnected(unit) == false then
        finalizeRequest(request, "skipped", "offline")
        return
    end
    if CheckInteractDistance and not CheckInteractDistance(unit, 1) then
        finalizeRequest(request, "skipped", "out_of_range")
        return
    end
    if CanInspect and not CanInspect(unit) then
        finalizeRequest(request, "skipped", "cannot_inspect")
        return
    end

    active = request
    active.unit = unit
    active.guid = UnitGUID and UnitGUID(unit) or nil
    setRuntimeStatus(request.raidId, request.playerNid, "pending", request.reason)
    emitUpdated(request, module:GetRuntimeStatus(request.raidId, request.playerNid), "pending")

    local ok = pcall(NotifyInspect, unit)
    if not ok then
        finalizeRequest(request, "failed", "notify_failed")
        return
    end

    timeoutTimer = module:ScheduleTimer(function()
        finalizeRequest(request, "timeout", "inspect_timeout")
    end, INSPECT_TIMEOUT_SECONDS)
end
```

Name the local helpers consistently with the service body. Keep them local, not exported, except
private underscore methods if a test or callback needs `module:_CompleteInspect(guid)`.

- [ ] **Step 6: Implement `INSPECT_READY` completion**

When `INSPECT_READY` fires:

- ignore if there is no active request;
- ignore if the event guid does not match `active.guid`;
- read slots from `SLOT_IDS`;
- read item links, textures, quality, item IDs, enchant ID, gem IDs, and item level;
- compute `avgIlvl` to two decimal precision by storing a numeric value, not a formatted string;
- read main inspected talent tab with `GetTalentTabInfo(tab, true)`;
- persist a `ready` snapshot;
- clear runtime status for that player;
- call `ClearInspectPlayer()` when available;
- emit `RaidInspectUpdated`;
- schedule the next queue item after `INSPECT_THROTTLE_SECONDS`.

Use this talent helper:

```lua
local function readMainTalentTree()
    if not GetTalentTabInfo then
        return nil, nil
    end

    local bestName, bestIcon
    local bestPoints = -1

    for tab = 1, 3 do
        local name, icon, points = GetTalentTabInfo(tab, true)
        points = tonumber(points) or 0
        if points > bestPoints then
            bestPoints = points
            bestName = name
            bestIcon = icon
        end
    end

    return bestName, bestIcon
end
```

- [ ] **Step 7: Register bus callbacks**

At the bottom of `!KRT/Services/RaidInspect.lua`, register:

```lua
if Bus and InternalEvents and InternalEvents.RaidCreate then
    Bus.RegisterCallback(InternalEvents.RaidCreate, function(_, raidId)
        module:ScheduleTimer(function()
            module:StartRaidSnapshot(raidId, { reason = "raid_start" })
        end, INSPECT_DELAY_AFTER_RAID_CREATE)
    end)
end

local inspectReadyEvent = Events.GetWowForwarded and Events.GetWowForwarded("INSPECT_READY")
if inspectReadyEvent then
    Bus.RegisterCallback(inspectReadyEvent, function(_, guid)
        module:_CompleteInspect(guid)
    end)
end

local regenEvent = Events.GetWowForwarded and Events.GetWowForwarded("PLAYER_REGEN_ENABLED")
if regenEvent then
    Bus.RegisterCallback(regenEvent, function()
        module:_ScheduleNext(0.2)
    end)
end
```

Do not register for `InternalEvents.RaidRosterDelta`.

- [ ] **Step 8: Register module metadata**

At the bottom of `!KRT/Services/RaidInspect.lua`, add:

```lua
local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/RaidInspect", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Timer",
            "Modules/Strings",
            "Services/Raid/Roster",
            "Services/Raid/Attendance",
        },
    })
    registry.SetLoaded("Services/RaidInspect")
end
```

- [ ] **Step 9: Run service tests**

Run:

```powershell
lua tests/raid_inspect_service_spec.lua
lua tests/raid_inspect_source_contract_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected: service and module registry tests pass. Source contract may still fail on Logger View/UI
until later tasks.

- [ ] **Step 10: Commit RaidInspect service**

```powershell
git add `
  !KRT/Services/RaidInspect.lua `
  !KRT/!KRT.toc `
  tests/raid_inspect_service_spec.lua `
  tests/module_registry_services_spec.lua `
  tests/module_registry_ui_entrypoints_spec.lua
git commit -m "feat: add raid inspect snapshot service"
```

---

### Task 5: Enrich Logger Attendance Rows

**Files:**
- Modify: `!KRT/Services/Logger/View.lua`

- [ ] **Step 1: Add snapshot lookup helper**

In `!KRT/Services/Logger/View.lua`, before `View:FillRaidAttendeesList`, add:

```lua
local function getRaidInspectSnapshot(raid, playerNid)
    local inspectService = Services.RaidInspect
    if inspectService and inspectService.GetSnapshot then
        return inspectService:GetSnapshot(raid, playerNid)
    end

    local inspect = raid and raid.inspect or nil
    local players = inspect and inspect.players or nil
    if type(players) ~= "table" then
        return nil
    end

    return players[tonumber(playerNid)]
end

local function enrichAttendanceRowsWithInspect(raid, rows)
    if type(rows) ~= "table" then
        return rows
    end

    for i = 1, #rows do
        local row = rows[i]
        local playerNid = row and (row.id or row.playerNid)
        local snapshot = row and getRaidInspectSnapshot(raid, playerNid) or nil

        row.inspect = snapshot
        row.inspectStatus = snapshot and snapshot.status or "not_inspected"
        row.inspectReason = snapshot and snapshot.reason or nil
        row.avgIlvl = snapshot and snapshot.avgIlvl or nil
        row.specName = snapshot and snapshot.specName or nil
        row.specIcon = snapshot and snapshot.specIcon or nil

        if row.avgIlvl then
            row.avgIlvlFmt = string.format("%.2f", row.avgIlvl)
        else
            row.avgIlvlFmt = ""
        end

        row.specFmt = row.specName or ""
    end

    return rows
end
```

- [ ] **Step 2: Enrich query-backed attendance rows**

In `View:FillRaidAttendeesList`, change the query-backed branch from:

```lua
local result = queries:GetRaidAttendance(raid, out)
finishPerf("Logger.View.FillRaidAttendeesList", perfStart, raid, out)
return result
```

to:

```lua
local result = queries:GetRaidAttendance(raid, out)
enrichAttendanceRowsWithInspect(raid, out)
finishPerf("Logger.View.FillRaidAttendeesList", perfStart, raid, out)
return result
```

- [ ] **Step 3: Enrich fallback attendance rows**

After fallback `buildRows(...)`, add:

```lua
enrichAttendanceRowsWithInspect(raid, out)
```

- [ ] **Step 4: Run Logger View tests**

Run:

```powershell
lua tests/raid_inspect_source_contract_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected: source contract still fails only on Logger UI/XML pieces if those are not implemented.
Release stabilization passes or exposes rows that need stale field clearing in `DBRaidQueries`.

- [ ] **Step 5: Commit Logger View enrichment**

```powershell
git add !KRT/Services/Logger/View.lua tests/release_stabilization_spec.lua
git commit -m "feat: show raid inspect data in attendance rows"
```

---

### Task 6: Update Attendance XML Structure

**Files:**
- Modify: `!KRT/UI/Logger.xml`

- [ ] **Step 1: Add attendee row fields**

Inside `KRTLoggerRaidAttendeeButton`, after `$parentLeave`, add `Ilvl`, `Spec`, and
`InspectStatus` font strings:

```xml
<FontString name="$parentIlvl" inherits="GameFontHighlightSmall" justifyH="CENTER" justifyV="MIDDLE">
    <Size>
        <AbsDimension x="42" y="18" />
    </Size>
    <Anchors>
        <Anchor point="TOPLEFT" relativeTo="$parentLeave" relativePoint="TOPRIGHT">
            <Offset>
                <AbsDimension x="6" y="0" />
            </Offset>
        </Anchor>
    </Anchors>
</FontString>
<FontString name="$parentSpec" inherits="GameFontHighlightSmall" justifyH="LEFT" justifyV="MIDDLE">
    <Size>
        <AbsDimension x="80" y="18" />
    </Size>
    <Anchors>
        <Anchor point="TOPLEFT" relativeTo="$parentIlvl" relativePoint="TOPRIGHT">
            <Offset>
                <AbsDimension x="6" y="0" />
            </Offset>
        </Anchor>
    </Anchors>
</FontString>
<FontString name="$parentInspectStatus" inherits="GameFontDisableSmall" justifyH="LEFT" justifyV="MIDDLE">
    <Size>
        <AbsDimension x="250" y="18" />
    </Size>
    <Anchors>
        <Anchor point="TOPLEFT" relativeTo="$parentSpec" relativePoint="TOPRIGHT">
            <Offset>
                <AbsDimension x="6" y="0" />
            </Offset>
        </Anchor>
    </Anchors>
</FontString>
```

- [ ] **Step 2: Widen the player panel**

Change `KRTRaidAttendanceRaidAttendees` width from 265 to 607:

```xml
<AbsDimension x="607" y="430" />
```

Keep `KRTRaidAttendanceBosses` defined in XML. Do not delete it.

- [ ] **Step 3: Add attendee headers**

Inside `KRTRaidAttendanceRaidAttendees`, after `$parentHeaderLeave`, add:

```xml
<Button name="$parentHeaderIlvl" inherits="KRTLoggerTableHeader">
    <Size>
        <AbsDimension x="42" y="20" />
    </Size>
    <Anchors>
        <Anchor point="TOPLEFT" relativeTo="$parentHeaderLeave" relativePoint="TOPRIGHT" />
    </Anchors>
</Button>
<Button name="$parentHeaderSpec" inherits="KRTLoggerTableHeader">
    <Size>
        <AbsDimension x="80" y="20" />
    </Size>
    <Anchors>
        <Anchor point="TOPLEFT" relativeTo="$parentHeaderIlvl" relativePoint="TOPRIGHT" />
    </Anchors>
</Button>
<Button name="$parentHeaderInspect" inherits="KRTLoggerTableHeader">
    <Size>
        <AbsDimension x="250" y="20" />
    </Size>
    <Anchors>
        <Anchor point="TOPLEFT" relativeTo="$parentHeaderSpec" relativePoint="TOPRIGHT" />
    </Anchors>
</Button>
```

- [ ] **Step 4: Add optional Force button**

Inside `KRTRaidAttendanceRaidAttendees`, add a button after `$parentDeleteBtn`:

```xml
<Button name="$parentForceInspectBtn" inherits="KRTActionButtonTemplate">
    <Size>
        <AbsDimension x="65" y="25" />
    </Size>
    <Anchors>
        <Anchor point="LEFT" relativeTo="$parentDeleteBtn" relativePoint="RIGHT">
            <Offset>
                <AbsDimension x="3" y="0" />
            </Offset>
        </Anchor>
    </Anchors>
</Button>
```

- [ ] **Step 5: Run XML/source checks**

Run:

```powershell
lua tests/raid_inspect_source_contract_spec.lua
lua tests/logger_visual_refresh_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check ui_binding
```

Expected: XML parses through existing gates. Source contracts still fail only on Logger controller
logic if not implemented yet.

- [ ] **Step 6: Commit XML changes**

```powershell
git add !KRT/UI/Logger.xml tests/logger_visual_refresh_spec.lua
git commit -m "feat: add raid inspect attendance columns"
```

---

### Task 7: Render Inspect Columns In Logger Controller

**Files:**
- Modify: `!KRT/Controllers/Logger.lua`

- [ ] **Step 1: Expand attendance width model**

Replace `LOGGER_ATTENDANCE_COLUMN_MIN_WIDTHS` and `LOGGER_ATTENDANCE_COLUMN_RATIOS` with:

```lua
local LOGGER_ATTENDANCE_COLUMN_MIN_WIDTHS = {
    name = 92,
    join = LOGGER_ATTENDANCE_TIME_COLUMN_MIN_WIDTH,
    leave = LOGGER_ATTENDANCE_TIME_COLUMN_MIN_WIDTH,
    ilvl = 42,
    spec = 80,
    inspect = 250,
}

local LOGGER_ATTENDANCE_COLUMN_RATIOS = {
    name = 0.20,
    join = 0.08,
    leave = 0.08,
    ilvl = 0.07,
    spec = 0.16,
    inspect = 0.41,
}
```

Change `getAttendanceColumnWidths(frameName)` budget from 2 gaps to 5 gaps:

```lua
local budget = getLoggerListColumnBudget(frameName, LOGGER_ROW_LEFT_INSET, 5)
```

- [ ] **Step 2: Position new headers and row parts**

In `applyAttendanceListColumnWidths`, include `HeaderIlvl`, `HeaderSpec`, and `HeaderInspect`:

```lua
positionLoggerHeaderColumns(frameName, {
    { header = _G[frameName .. "HeaderName"], width = widths.name, trailingGap = true },
    { header = _G[frameName .. "HeaderJoin"], width = widths.join, trailingGap = true },
    { header = _G[frameName .. "HeaderLeave"], width = widths.leave, trailingGap = true },
    { header = _G[frameName .. "HeaderIlvl"], width = widths.ilvl, trailingGap = true },
    { header = _G[frameName .. "HeaderSpec"], width = widths.spec, trailingGap = true },
    { header = _G[frameName .. "HeaderInspect"], width = widths.inspect, trailingGap = false },
}, LOGGER_PANEL_SCROLL_LEFT_OFFSET + LOGGER_ROW_LEFT_INSET)
```

In `applyAttendanceRowColumnWidths`, set all widths:

```lua
setWidgetWidth(ui.Name, widths.name)
setWidgetWidth(ui.Join, widths.join)
setWidgetWidth(ui.Leave, widths.leave)
setWidgetWidth(ui.Ilvl, widths.ilvl)
setWidgetWidth(ui.Spec, widths.spec)
setWidgetWidth(ui.InspectStatus, widths.inspect)
```

- [ ] **Step 3: Add inspect icon helpers**

Near the dedicated Attendance frame helpers, add:

```lua
local RAID_INSPECT_SLOTS = {
    1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18,
}

local RAID_INSPECT_ICON_SIZE = 14
local RAID_INSPECT_ICON_GAP = 2

local function getInspectStatusLabel(status, reason)
    if status == "queued" then
        return "Queued"
    elseif status == "pending" then
        return "Pending"
    elseif status == "ready" then
        return ""
    elseif status == "skipped" then
        return reason and ("Skipped: " .. tostring(reason)) or "Skipped"
    elseif status == "timeout" then
        return "Timeout"
    elseif status == "failed" then
        return reason and ("Failed: " .. tostring(reason)) or "Failed"
    end

    return "Not inspected"
end
```

Then add `ensureAttendanceInspectIcons(row, ui)` and `renderAttendanceInspectIcons(row, ui,
playerNid, snapshot)` using `CreateFrame("Button", nil, row)`. Every draw must reset
`playerNid`, `itemLink`, `statusText`, texture, desaturation, and show/hide state for recycled rows.

- [ ] **Step 4: Hide Bosses panel in Attendance layout**

In `refreshRaidAttendanceLayout`, change Bosses visibility and player width:

```lua
setAttendancePanelVisible(refs.raids, true)
setAttendancePanelVisible(refs.raidAttendees, true)
setAttendancePanelVisible(refs.bosses, false)

placePanel(refs.raids, "TOPLEFT", history, "TOPLEFT", 0, 0, 335, 430)
placePanel(refs.raidAttendees, "TOPLEFT", refs.raids, "TOPRIGHT", 7, 0, 607, 430)

applyRaidListColumnWidths(ATTENDANCE_RAIDS_FRAME)
applyAttendanceListColumnWidths(ATTENDANCE_PLAYERS_FRAME)
```

Do not delete `attendanceBossesController` or XML Bosses definitions.

- [ ] **Step 5: Update player list binding**

In the dedicated attendance players controller:

- change `_rowParts` to:

```lua
_rowParts = { "Name", "Join", "Leave", "Ilvl", "Spec", "InspectStatus" },
```

- set header labels:

```lua
_G[n .. "HeaderIlvl"]:SetText("iLvl")
_G[n .. "HeaderSpec"]:SetText("Spec")
_G[n .. "HeaderInspect"]:SetText("Inspect items")
```

- bind sort headers for `ilvl` and `spec`;
- keep no sort for inspect items;
- in `drawRow`, set row ID from `it.id or it.playerNid`, write all text columns, and call
  `renderAttendanceInspectIcons(row, ui, row._krtPlayerNid, it.inspect)`.

Use this draw row shape:

```lua
drawRow = UI.Lists.CreateRowRenderer(function(row, it)
    if not row._krtAttendanceBound then
        UI.Frames.SetScriptSafely(row, "OnClick", function(self, button)
            selectAttendancePlayer(self, button)
        end)
        row._krtAttendanceBound = true
    end

    row._krtPlayerNid = it.id or it.playerNid
    if row.SetID and row._krtPlayerNid then
        row:SetID(row._krtPlayerNid)
    end

    local ui = row._p
    applyAttendanceRowColumnWidths(ui, ATTENDANCE_PLAYERS_FRAME)

    ui.Name:SetText(it.name or "")
    local r, g, b = Colors.GetClassColor(it.class)
    ui.Name:SetVertexColor(r, g, b)
    ui.Join:SetText(it.joinFmt or "")
    ui.Leave:SetText(it.leaveFmt or "")
    ui.Ilvl:SetText(it.avgIlvlFmt or "")
    ui.Spec:SetText(it.specFmt or "")

    renderAttendanceInspectIcons(row, ui, row._krtPlayerNid, it.inspect)
end)
```

- [ ] **Step 6: Add sorters**

Add these sorters:

```lua
ilvl = function(a, b, asc)
    return CompareNumbers(a.avgIlvl, b.avgIlvl, asc, 0)
end,
spec = function(a, b, asc)
    return compareStrings(a.specName, b.specName, asc)
end,
```

- [ ] **Step 7: Wire Force button**

In the players controller `localize` block, bind `$parentForceInspectBtn`:

```lua
local forceBtn = _G[n .. "ForceInspectBtn"]
if forceBtn then
    forceBtn:SetText("Force")

    UI.Frames.SetScriptSafely(forceBtn, "OnClick", function()
        local raidId = module.attendanceSelectedRaid
        local playerNid = module.attendanceSelectedPlayer

        if not raidId or not playerNid then
            return
        end

        if tonumber(Database.GetCurrentRaid()) ~= tonumber(raidId) then
            return
        end

        if Services.RaidInspect and Services.RaidInspect.ForcePlayer then
            Services.RaidInspect:ForcePlayer(raidId, playerNid)

            if attendancePlayersController then
                attendancePlayersController:Dirty()
            end
        end
    end)
end
```

In `postUpdate`, enable the button only for a selected player in the current raid.

- [ ] **Step 8: Add refresh callbacks**

Inside `initializeRaidAttendanceFrame()`, after controllers are created, register:

```lua
if Bus and InternalEvents and InternalEvents.RaidInspectUpdated then
    Bus.RegisterCallback(InternalEvents.RaidInspectUpdated, function(_, raidId)
        if tonumber(raidId) ~= tonumber(module.attendanceSelectedRaid) then
            return
        end
        if attendancePlayersController then
            attendancePlayersController:Dirty()
        end
    end)
end

if Bus and InternalEvents and InternalEvents.RaidInspectCompleted then
    Bus.RegisterCallback(InternalEvents.RaidInspectCompleted, function(_, raidId)
        if tonumber(raidId) ~= tonumber(module.attendanceSelectedRaid) then
            return
        end
        if attendancePlayersController then
            attendancePlayersController:Dirty()
        end
    end)
end

if Bus and InternalEvents and InternalEvents.RaidAttendanceChanged then
    Bus.RegisterCallback(InternalEvents.RaidAttendanceChanged, function(_, raidId)
        if tonumber(raidId) ~= tonumber(module.attendanceSelectedRaid) then
            return
        end
        if attendancePlayersController then
            attendancePlayersController:Dirty()
        end
    end)
end
```

These callbacks refresh display only. They must not call `StartRaidSnapshot`.

- [ ] **Step 9: Run UI source tests**

Run:

```powershell
lua tests/raid_inspect_source_contract_spec.lua
lua tests/logger_visual_refresh_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check ui_binding
```

Expected: tests pass or report only stale string assertions that need test updates.

- [ ] **Step 10: Commit Logger controller rendering**

```powershell
git add !KRT/Controllers/Logger.lua tests/logger_visual_refresh_spec.lua
git commit -m "feat: render raid inspect attendance rows"
```

---

### Task 8: Add Changelog And Schema Docs

**Files:**
- Modify: `!KRT/CHANGELOG.md`
- Modify: `docs/RAID_SCHEMA.md`
- Modify: `docs/SV_SCHEMA.md`

- [ ] **Step 1: Add changelog entry**

Under `## Unreleased` in `!KRT/CHANGELOG.md`, add:

```markdown
- **Raid attendance inspect snapshots** - Added one-shot raid-start inspect snapshots to the
  dedicated Raid Attendance window. Attendance continues to track joins/leaves throughout the raid,
  while inspect data is captured only at raid start or through explicit current-raid player force.
```

- [ ] **Step 2: Document raid schema**

In `docs/RAID_SCHEMA.md`, add an optional `inspect` row to the raid table and a compact section:

```markdown
## RaidInspectSnapshot (`raid.inspect`)

`raid.inspect` is optional. Old raids may omit it.

Persisted fields:
- `startedAt`, `completedAt`, and `mode`
- `players[playerNid].playerNid`
- `players[playerNid].name`
- `players[playerNid].guid`
- `players[playerNid].status`
- `players[playerNid].reason`
- `players[playerNid].inspectedAt`
- `players[playerNid].avgIlvl`
- `players[playerNid].specName`
- `players[playerNid].specIcon`
- `players[playerNid].items[slotId].slot`
- `players[playerNid].items[slotId].itemId`
- `players[playerNid].items[slotId].itemLink`
- `players[playerNid].items[slotId].texture`
- `players[playerNid].items[slotId].quality`
- `players[playerNid].items[slotId].ilvl`
- `players[playerNid].items[slotId].enchantId`
- `players[playerNid].items[slotId].gems`

Runtime-only statuses `queued` and `pending` are never persisted.
```

- [ ] **Step 3: Document SavedVariables note**

In `docs/SV_SCHEMA.md`, add:

```markdown
Observed optional inspect fields:
- `inspect.startedAt`, `inspect.completedAt`, `inspect.mode`
- `inspect.players[playerNid]` compact per-player final snapshot

Only final inspect states are persisted: `ready`, `skipped`, `timeout`, and `failed`.
Runtime queue states `queued` and `pending` are intentionally absent after `/reload`.
```

- [ ] **Step 4: Run docs-sensitive checks**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
```

Expected: checks pass. If generated docs drift, run the documented generation command and review the
diff before staging generated outputs.

- [ ] **Step 5: Commit docs**

```powershell
git add !KRT/CHANGELOG.md docs/RAID_SCHEMA.md docs/SV_SCHEMA.md
git commit -m "docs: note raid inspect snapshots"
```

---

### Task 9: Final Verification And Parent Review

**Files:**
- Review all changed files.

- [ ] **Step 1: Run full local gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
lua tests/raid_inspect_service_spec.lua
lua tests/raid_inspect_source_contract_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected: all commands exit 0.

- [ ] **Step 2: Inspect for forbidden triggers**

Run:

```powershell
$pattern = "StartRaidSnapshot|ForceRaid|ForcePlayer|NotifyInspect|RaidRosterDelta|C_Timer" `
  + "|GetInspectSpecialization|GetSpecialization|table.move|bit32"
rg -n $pattern !KRT
```

Expected:
- `NotifyInspect` appears only in `!KRT/Services/RaidInspect.lua`.
- `StartRaidSnapshot` appears only in `!KRT/Services/RaidInspect.lua`.
- `ForcePlayer` appears in `!KRT/Services/RaidInspect.lua` and Logger manual force UI.
- `RaidInspect.lua` does not contain `RaidRosterDelta`.
- No forbidden WotLK-incompatible APIs appear in new code.

- [ ] **Step 3: Parent diff review checklist**

Review `git diff --stat` and `git diff` for:

- no changes under `!KRT/Libs/*`;
- no XML `<Scripts>` or `<On...>` handlers;
- no Ace2/Ace3 dependency additions;
- no `DBSyncer` inspect syncing;
- no Logger View inspect starts;
- no inspect start from frame open or row selection;
- Bosses attendance panel hidden, not removed;
- runtime `queued`/`pending` never persisted to `raid.inspect`;
- manual force guarded to the current raid;
- old raid fallback shows `Not inspected`;
- `!KRT/CHANGELOG.md` updated under `## Unreleased`.

- [ ] **Step 4: Manual in-game smoke**

Run this in a WotLK 3.3.5a client:

```text
1. Start a raid with players already present.
2. Open Raid Attendance and confirm Raid List plus Player List are visible.
3. Confirm Bosses panel is not visible in the Attendance window.
4. Confirm Player List columns are Player, Join, Leave, iLvl, Spec, Inspect items.
5. Wait at least 3 seconds after RaidCreate.
6. Confirm inspect statuses progress Queued/Pending/Ready or a final skipped/timeout/failed status.
7. Confirm ready rows show item icons, average iLvl, and spec.
8. Mouse over item icons and confirm item tooltip opens.
9. Add a player after raid start.
10. Confirm attendance tracks Join but inspect remains Not inspected.
11. Right-click the inspect area or click Force for that current-raid player.
12. Confirm forced inspect updates the selected row only.
13. End the raid.
14. Confirm Leave values are filled and attendance segments are closed.
15. Reload UI.
16. Confirm final snapshots persist and Queued/Pending do not persist.
17. Select an older raid with no inspect data.
18. Confirm rows show Not inspected and force is disabled or ignored.
```

- [ ] **Step 5: Commit final corrections**

If review or smoke produces fixes in the files covered by this plan:

```powershell
git add `
  !KRT/Modules/Events.lua `
  !KRT/Init.lua `
  !KRT/Services/Raid/Attendance.lua `
  !KRT/Services/Raid/State.lua `
  !KRT/Services/RaidInspect.lua `
  !KRT/!KRT.toc `
  !KRT/Services/Logger/View.lua `
  !KRT/UI/Logger.xml `
  !KRT/Controllers/Logger.lua `
  !KRT/CHANGELOG.md `
  docs/RAID_SCHEMA.md `
  docs/SV_SCHEMA.md `
  tests/raid_inspect_service_spec.lua `
  tests/raid_inspect_source_contract_spec.lua `
  tests/module_registry_services_spec.lua `
  tests/module_registry_ui_entrypoints_spec.lua `
  tests/logger_visual_refresh_spec.lua `
  tests/release_stabilization_spec.lua
git commit -m "fix: tighten raid inspect attendance behavior"
```

## Self-Review

- Spec coverage: covered one-shot startup, no roster-delta inspect, no UI-triggered inspect,
  manual force, runtime-vs-persisted statuses, attendance seed/close, two-column Attendance UI,
  icon rendering, old raid fallback, tests, changelog, and smoke.
- Placeholder scan: this plan avoids open-ended implementation placeholders and uses exact paths for
  commands.
- Type consistency: public service methods use colon calls; inspect snapshots use `playerNid`,
  `avgIlvl`, `specName`, `specIcon`, `items`, `status`, and `reason` consistently across service,
  View, and Logger renderer tasks.
- Remaining implementation risk: WotLK inspect is asynchronous and shared with the Blizzard inspect
  UI. The service must stay conservative: one active request, throttling, combat retry, timeout,
  stale raid checks, and final parent review before completion.
