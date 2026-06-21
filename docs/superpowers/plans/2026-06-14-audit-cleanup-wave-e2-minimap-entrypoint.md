# Wave E2 Minimap EntryPoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize minimap entrypoint routing helpers while preserving the
existing minimap menu, button click, drag, visibility, and option behavior.

**Architecture:** `!KRT/EntryPoints/Minimap.lua` remains the owner of minimap
button lifecycle, menu routing, and drag script binding. Wave E2 adds a local
controller dispatch helper around `Database.RequestControllerMethod(...)`,
deduplicates widget availability checks through the existing minimap widget
helper path, and updates source-contract tests to validate the new literals.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, Blizzard
`UIDropDownMenu`/`EasyMenu`, KRT entrypoint routing, repo-local Lua/Python/
PowerShell checks.

---

## Classification

- `55to53`: `complex-orchestrated`
- Reason: touches entrypoint routing, source-contract tests, generated catalogs,
  and cleanup backlog docs.
- Execution mode: use `spark_implementer` for the patch; parent reviews and
  corrects. Use `code-mapper` only if implementation context is no longer fresh.

## File Structure

- Modify: `!KRT/EntryPoints/Minimap.lua`
  - Add `callControllerMethod(controllerName, methodName, ...)`.
  - Replace direct literal `Database.RequestControllerMethod("...", "...")`
    menu callbacks with `callControllerMethod("...", "...")`.
  - Make `callWidgetMethod(...)` use `isWidgetAvailable(widgetId)` instead of
    repeating the enabled/registered expression.
  - Keep `toggleLootCounterWidget()` as the centralized LootCounter route.
  - Leave menu labels, order, disabled states, `EasyMenu`, click bindings,
    drag behavior, option storage, and tooltip text unchanged.
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
  - Update minimap controller-dispatch scanning to read literal pairs from
    `callControllerMethod(...)`.
  - Update the minimap menu contract literals for Logger routes.
- Create: `tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua`
  - Guard the helper normalization, exact controller/widget dispatch pairs,
    menu order, XML layout-only status, drag `OnUpdate` confinement, and backlog
    completion marker.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Mark Wave E2 completed and remove the minimap follow-up from the default
    next-step list.
- Generated: `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`,
  `docs/TREE.md`, and any API catalog files changed by
  `py -3 tools/krt.py api-catalog-refresh`.

## Non-Goals

- Do not change minimap menu labels, order, separators, disabled-state logic, or
  action targets.
- Do not change minimap XML anchors, sizes, textures, frame name, or strata.
- Do not change drag semantics: Shift-left drag remains ring mode; Alt-left drag
  remains free mode; `OnUpdate` remains confined to active drag.
- Do not change right-click Config toggle, left-click menu open/close, tooltip
  strings, minimap option keys, SavedVariables shape, or localization.
- Do not touch controllers, widgets, services, vendored libs, or
  `!KRT/CHANGELOG.md`.

---

### Task 1: Add the Wave E2 Source-Contract Test

**Files:**
- Create: `tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua`

- [ ] **Step 1: Create the failing source-contract test**

Create `tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua` with this
content:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstPos = assert(text:find(first, 1, true), "missing: " .. first)
    local secondPos = assert(text:find(second, 1, true), "missing: " .. second)
    assert(firstPos < secondPos, message or (first .. " must appear before " .. second))
end

local function countPlain(text, needle)
    local count = 0
    local index = 1

    while true do
        local found = text:find(needle, index, true)
        if not found then
            break
        end
        count = count + 1
        index = found + #needle
    end

    return count
end

local minimap = read("!KRT/EntryPoints/Minimap.lua")
local minimapXml = read("!KRT/UI/Minimap.xml")
local registry = read("tests/module_registry_ui_entrypoints_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(minimap, "local function callControllerMethod(controllerName, methodName, ...)")
assertContains(minimap, "return Database.RequestControllerMethod(controllerName, methodName, ...)")
assertNotContains(minimap, 'Database.RequestControllerMethod("')

assertContains(minimap, "local function isWidgetAvailable(widgetId)")
assertContains(minimap, "local function callWidgetMethod(widgetId, methodName, ...)")
assertContains(minimap, "if not isWidgetAvailable(widgetId) then")
assertContains(minimap, "return UIWidgets.Call(widgetId, methodName, ...)")
assertContains(minimap, 'return callWidgetMethod("LootCounter", "Toggle")')
assert(countPlain(minimap, "UIWidgets.IsEnabled(widgetId) and UIWidgets.IsRegistered(widgetId)") == 1)

local controllerPairs = {
    { "Master", "Toggle" },
    { "Logger", "ToggleLootHistory" },
    { "Logger", "ToggleRaidAttendance" },
    { "Warnings", "Toggle" },
    { "Spammer", "Toggle" },
}

for i = 1, #controllerPairs do
    local pair = controllerPairs[i]
    local needle = 'callControllerMethod("' .. pair[1] .. '", "' .. pair[2] .. '"'
    local message = "missing minimap controller dispatch: " .. pair[1] .. ":" .. pair[2]
    assertContains(minimap, needle, message)
end

local widgetPairs = {
    { "Reserves", "Toggle" },
    { "LootCounter", "Toggle" },
    { "Config", "Toggle" },
}

for i = 1, #widgetPairs do
    local pair = widgetPairs[i]
    local needle = 'callWidgetMethod("' .. pair[1] .. '", "' .. pair[2] .. '"'
    local message = "missing minimap widget dispatch: " .. pair[1] .. ":" .. pair[2]
    assertContains(minimap, needle, message)
end

assertContains(registry, 'path = "!KRT/EntryPoints/Minimap.lua"')
assertContains(registry, 'pattern = \'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"\'')
assertContains(registry, 'local lootHistoryDispatch = \'callControllerMethod("Logger", "ToggleLootHistory")\'')
assertContains(registry, 'local raidAttendanceDispatch = \'callControllerMethod("Logger", "ToggleRaidAttendance")\'')

assertBefore(minimap, "L.StrLootMaster", "L.StrLootReserve")
assertBefore(minimap, "L.StrLootReserve", "L.StrLootCounter")
assertBefore(minimap, "L.StrLootCounter", "L.StrLootHistory")
assertBefore(minimap, "L.StrLootHistory", "L.StrRaidAttendance")
assertBefore(minimap, "L.StrRaidAttendance", "RAID_WARNING")
assertBefore(minimap, "RAID_WARNING", "L.StrLFMSpam")
assertBefore(minimap, "L.StrLFMSpam", "L.StrClearIcons")

assertContains(minimap, 'self:SetScript("OnUpdate", moveButton)')
assertContains(minimap, 'self:SetScript("OnUpdate", nil)')
assertNotContains(minimapXml, "<Scripts>")
assertNotContains(minimapXml, "<On")

assertContains(backlog, "Wave E2 completed: Minimap entrypoint routing normalization")

print("audit cleanup wave e2 minimap entrypoint source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run:

```powershell
lua tests\audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
```

Expected:

```text
missing: local function callControllerMethod(controllerName, methodName, ...)
```

---

### Task 2: Normalize Minimap Routing Helpers

**Files:**
- Modify: `!KRT/EntryPoints/Minimap.lua`

- [ ] **Step 1: Deduplicate widget availability in the widget route helper**

Replace the current `callWidgetMethod(...)` body:

```lua
local function callWidgetMethod(widgetId, methodName, ...)
    if not (UIWidgets.IsEnabled(widgetId) and UIWidgets.IsRegistered(widgetId)) then
        return nil
    end
    return UIWidgets.Call(widgetId, methodName, ...)
end
```

with:

```lua
local function callWidgetMethod(widgetId, methodName, ...)
    if not isWidgetAvailable(widgetId) then
        return nil
    end
    return UIWidgets.Call(widgetId, methodName, ...)
end
```

- [ ] **Step 2: Add the controller routing helper**

Place this helper after `callWidgetMethod(...)` and before
`toggleLootCounterWidget()`:

```lua
local function callControllerMethod(controllerName, methodName, ...)
    return Database.RequestControllerMethod(controllerName, methodName, ...)
end
```

- [ ] **Step 3: Convert minimap menu controller dispatch calls**

Replace every direct literal controller dispatch in `buildMenu()`:

```lua
Database.RequestControllerMethod("Master", "Toggle")
Database.RequestControllerMethod("Logger", "ToggleLootHistory")
Database.RequestControllerMethod("Logger", "ToggleRaidAttendance")
Database.RequestControllerMethod("Warnings", "Toggle")
Database.RequestControllerMethod("Spammer", "Toggle")
```

with the same calls through `callControllerMethod(...)`:

```lua
callControllerMethod("Master", "Toggle")
callControllerMethod("Logger", "ToggleLootHistory")
callControllerMethod("Logger", "ToggleRaidAttendance")
callControllerMethod("Warnings", "Toggle")
callControllerMethod("Spammer", "Toggle")
```

Do not change menu labels, order, separators, disabled flags, or surrounding
raid-capability checks.

- [ ] **Step 4: Verify source shape**

Run:

```powershell
rg -n "Database\.RequestControllerMethod\(\"" "!KRT/EntryPoints/Minimap.lua"
rg -n "callWidgetMethod|callControllerMethod|toggleLootCounterWidget" "!KRT/EntryPoints/Minimap.lua"
```

Expected first command:

```text
```

Expected second command includes:

```text
local function callWidgetMethod(widgetId, methodName, ...)
local function callControllerMethod(controllerName, methodName, ...)
local function toggleLootCounterWidget()
```

---

### Task 3: Update EntryPoint Source-Contract Scans

**Files:**
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`

- [ ] **Step 1: Update the minimap controller dispatch scan pattern**

In `assertControllerDispatchContracts()`, change only the minimap scan from:

```lua
{
    path = "!KRT/EntryPoints/Minimap.lua",
    pattern = 'Database%.RequestControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
},
```

to:

```lua
{
    path = "!KRT/EntryPoints/Minimap.lua",
    pattern = 'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
},
```

- [ ] **Step 2: Update minimap menu contract literals**

In `assertMinimapRaidMenuContract()`, replace:

```lua
local lootHistoryDispatch = 'Database.RequestControllerMethod("Logger", "ToggleLootHistory")'
local raidAttendanceDispatch = 'Database.RequestControllerMethod("Logger", "ToggleRaidAttendance")'
```

with:

```lua
local lootHistoryDispatch = 'callControllerMethod("Logger", "ToggleLootHistory")'
local raidAttendanceDispatch = 'callControllerMethod("Logger", "ToggleRaidAttendance")'
```

Leave the Reserves widget literal and menu-order assertions unchanged.

- [ ] **Step 3: Run focused source tests**

Run:

```powershell
lua tests\audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
lua tests\module_registry_ui_entrypoints_spec.lua
```

Expected after Task 4 adds the backlog marker:

```text
audit cleanup wave e2 minimap entrypoint source contract passed
module registry UI entrypoints source contract passed
```

At this point the E2 test may still fail only on the backlog completion marker.
That marker is added in Task 4.

---

### Task 4: Update the Cleanup Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Mark Wave E2 complete**

In `### Wave E2: Minimap EntryPoint`, extend `Current worktree progress` so it
reads:

```markdown
Current worktree progress:
- controller and widget dispatch from the minimap menu now share helper paths
- loot-counter fallback routing is centralized without changing menu behavior
- minimap controller routes now use a local `callControllerMethod(...)` helper
  over `Database.RequestControllerMethod(...)`
- minimap widget routes now share `isWidgetAvailable(...)` and
  `callWidgetMethod(...)`
- menu labels, menu order, disabled-state checks, drag behavior, and XML layout
  are unchanged
- Wave E2 completed: Minimap entrypoint routing normalization
```

- [ ] **Step 2: Advance the default next-step list**

Near the bottom, replace:

```markdown
If continuing the cleanup program immediately, start with:

1. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
3. `!KRT/EntryPoints/Minimap.lua` boundary cleanup follow-up
```

with:

```markdown
If continuing the cleanup program immediately, start with:

1. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
3. `!KRT/Database/DBRaidStore.lua` runtime-index boundary follow-up only if C1 stays stable
```

- [ ] **Step 3: Run the Wave E2 source-contract test**

Run:

```powershell
lua tests\audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
```

Expected:

```text
audit cleanup wave e2 minimap entrypoint source contract passed
```

---

### Task 5: Refresh Catalogs and Run Verification

**Files:**
- Modify generated files changed by the commands below.

- [ ] **Step 1: Refresh generated API/function catalogs**

Run:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

Expected:

```text
API census complete. Unique API surface=...
Updated docs/TREE.md
```

- [ ] **Step 2: Verify generated catalogs are current**

Run:

```powershell
py -3 tools/krt.py api-catalog-check
```

Expected:

```text
API catalogs are up to date.
```

- [ ] **Step 3: Run focused tests**

Run:

```powershell
lua tests\audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
lua tests\module_registry_ui_entrypoints_spec.lua
lua tests\release_stabilization_spec.lua
```

Expected:

```text
audit cleanup wave e2 minimap entrypoint source contract passed
module registry UI entrypoints source contract passed
289 targeted stabilization test(s) passed.
```

- [ ] **Step 4: Run release-targeted tests**

Run:

```powershell
py -3 tools/krt.py run-release-targeted-tests
```

Expected:

```text
Targeted stabilization tests completed successfully.
```

- [ ] **Step 5: Run repository gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-ui-binding.ps1
```

Expected:

```text
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
Lua syntax check passed.
UI binding checks passed.
```

- [ ] **Step 6: Run formatting and diff hygiene checks**

Run:

```powershell
stylua --check !KRT\EntryPoints\Minimap.lua tests\audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
stylua --check tests\module_registry_ui_entrypoints_spec.lua
git diff --check
git status --short
```

Expected:

```text
```

`git diff --check` must have no errors. `git status --short` must show only the
intended Wave E2 files and generated catalog files.

---

### Task 6: Parent Review, Commit, and Smoke Handoff

**Files:**
- Review all changed files.

- [ ] **Step 1: Inspect the final diff**

Run:

```powershell
git diff --stat
git diff -- !KRT/EntryPoints/Minimap.lua
git diff -- tests/module_registry_ui_entrypoints_spec.lua
git diff -- tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
git diff -- docs/TECH_CLEANUP_BACKLOG.md
```

Expected:

```text
```

Review expectations:

- Minimap menu text, order, separators, disabled-state checks, and action targets
  are unchanged.
- Controller dispatches go through `callControllerMethod(...)`.
- Widget dispatches go through `callWidgetMethod(...)`.
- `toggleLootCounterWidget()` remains the centralized LootCounter route.
- `OnUpdate` remains used only for minimap drag and is cleared on mouse-up.
- `!KRT/UI/Minimap.xml` remains layout-only and unchanged unless a structural
  cleanup was explicitly required.
- Source-contract tests validate the literal minimap dispatch pairs.

- [ ] **Step 2: Commit the Wave E2 patch**

Run:

```powershell
git add -- `
  "!KRT/EntryPoints/Minimap.lua" `
  "tests/module_registry_ui_entrypoints_spec.lua" `
  "tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua" `
  "docs/TECH_CLEANUP_BACKLOG.md" `
  "docs/superpowers/plans/2026-06-14-audit-cleanup-wave-e2-minimap-entrypoint.md" `
  "docs/FUNCTION_REGISTRY.csv" `
  "docs/FN_CLUSTERS.md" `
  "docs/TREE.md"

git commit -m "Normalize minimap routing helpers"
```

If the pre-commit hook reports catalog drift, stage the exact generated files
listed by the hook and retry the same commit command.

- [ ] **Step 3: Confirm the commit and clean working tree**

Run:

```powershell
git status --short
git show --stat --oneline --decorate --no-renames HEAD
```

Expected:

```text
<clean status, followed by the Wave E2 commit stat>
```

`git status --short` must be empty.

## In-Client Smoke Checklist

Run this on WoW 3.3.5a after the commit:

- `/reload` with no Lua errors.
- Minimap button is visible if the saved `Minimap.minimapButton` option is true.
- Left-click minimap button opens the menu.
- Left-click again or opening elsewhere can close the menu without errors.
- Right-click minimap button opens Config.
- Menu item `Loot Master` opens/toggles Master when allowed.
- Menu item `Loot Reserve` opens/toggles Reserves when the widget is available.
- Menu item `Loot Counter` toggles only while in a raid.
- Menu items `Loot History` and `Raid Attendance` open their Logger views.
- Menu items `Raid Warning` and `LFM Spam` open their controllers.
- Menu item `Clear Icons` remains gated by raid icon capability.
- Shift-left drag keeps the button on the minimap ring.
- Alt-left drag keeps free drag behavior.

## Self-Review

- Spec coverage: this plan covers helper normalization, source-contract updates,
  backlog update, catalog refresh, full gates, commit, and smoke handoff.
- Placeholder scan: no placeholder tasks are left; every edit step includes
  exact paths, concrete code, exact commands, and expected results.
- Type/name consistency: the local helper names are `callControllerMethod`,
  `callWidgetMethod`, `isWidgetAvailable`, and `toggleLootCounterWidget`; source
  scans use those exact names.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-06-14-audit-cleanup-wave-e2-minimap-entrypoint.md`.

Two execution options:

1. Subagent-Driven (recommended) - dispatch a focused implementation subagent,
   then parent review and correction before commit.
2. Inline Execution - execute this plan in the current session with checkpoints.
