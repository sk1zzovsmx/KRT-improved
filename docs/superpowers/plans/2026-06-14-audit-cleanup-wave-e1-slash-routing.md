# Wave E1 Slash Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize slash entrypoint routing helpers while preserving every
existing `/krt` command, alias, help page, and dispatch target.

**Architecture:** `!KRT/EntryPoints/SlashEvents.lua` remains the owner of slash
registration, parsing, help, diagnostics, and dispatch. Wave E1 adds a single
local controller dispatch helper around the canonical
`Database.RequestControllerMethod(...)` surface, renames the slash widget helper
to match the entrypoint convention, and updates source-contract tests so literal
dispatch pairs remain validated after the helper normalization.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT entrypoint
routing, repo-local Lua/Python/PowerShell checks.

---

## Classification

- `55to53`: `complex-orchestrated`
- Reason: touches slash command routing, source-contract tests, generated
  catalogs, and cleanup backlog docs.
- Execution mode: use `code-mapper` if implementation context is not already
  fresh; use `spark_implementer` for the patch; parent reviews and corrects.

## File Structure

- Modify: `!KRT/EntryPoints/SlashEvents.lua`
  - Add `callControllerMethod(controllerName, methodName, ...)`.
  - Replace direct `Database.RequestControllerMethod("...", "...")` calls in
    slash handlers with `callControllerMethod("...", "...")`.
  - Rename local `callWidget(widgetId, methodName, ...)` to
    `callWidgetMethod(widgetId, methodName, ...)`.
  - Replace all `callWidget("...", "...")` calls with
    `callWidgetMethod("...", "...")`.
  - Leave command parsing, help output, service calls, sync calls, diagnostics,
    and option behavior unchanged.
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`
  - Update controller-dispatch source scanning so SlashEvents literal pairs are
    read from `callControllerMethod(...)`.
  - Update widget-dispatch source scanning so SlashEvents literal pairs are read
    from `callWidgetMethod(...)`.
- Create: `tests/audit_cleanup_wave_e1_slash_routing_spec.lua`
  - Guard the helper normalization and the exact controller/widget dispatch
    pairs used by `/krt` slash routes.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Mark Wave E1 completed and advance the default next-step list.
- Generated: `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`,
  `docs/TREE.md`, and any API catalog files changed by
  `py -3 tools/krt.py api-catalog-refresh`.

## Non-Goals

- Do not change command names, aliases, subcommand syntax, help text, or
  localized strings.
- Do not move slash command behavior into services, controllers, widgets, or
  new modules.
- Do not change logger sync request semantics, reserve sync semantics,
  validation output, bug report output, version checks, perf commands, debug
  commands, or minimap routing.
- Do not touch XML, widgets, controllers, SavedVariables shape, vendored libs,
  or `!KRT/CHANGELOG.md`.

---

### Task 1: Add the Wave E1 Source-Contract Test

**Files:**
- Create: `tests/audit_cleanup_wave_e1_slash_routing_spec.lua`

- [ ] **Step 1: Create the failing source-contract test**

Create `tests/audit_cleanup_wave_e1_slash_routing_spec.lua` with this content:

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

local slash = read("!KRT/EntryPoints/SlashEvents.lua")
local registry = read("tests/module_registry_ui_entrypoints_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(slash, "local function callControllerMethod(controllerName, methodName, ...)")
assertContains(slash, "return Database.RequestControllerMethod(controllerName, methodName, ...)")
assertNotContains(slash, 'Database.RequestControllerMethod("')

assertContains(slash, "local function callWidgetMethod(widgetId, methodName, ...)")
assertNotContains(slash, "local function callWidget(widgetId, methodName, ...)")
assertNotContains(slash, "callWidget(")

local controllerPairs = {
    { "Master", "ShowDebugRaidGrid" },
    { "Warnings", "Toggle" },
    { "Warnings", "RequestAnnounce" },
    { "Logger", "ToggleLootHistory" },
    { "Logger", "ToggleRaidAttendance" },
    { "Master", "Toggle" },
    { "Spammer", "Toggle" },
    { "Spammer", "RequestStart" },
    { "Spammer", "RequestStop" },
}

for i = 1, #controllerPairs do
    local pair = controllerPairs[i]
    assertContains(
        slash,
        'callControllerMethod("' .. pair[1] .. '", "' .. pair[2] .. '"',
        "missing slash controller dispatch: " .. pair[1] .. ":" .. pair[2]
    )
end

local widgetPairs = {
    { "Config", "Default" },
    { "Config", "Toggle" },
    { "LootCounter", "Toggle" },
    { "Reserves", "Toggle" },
    { "Reserves", "ToggleImport" },
}

for i = 1, #widgetPairs do
    local pair = widgetPairs[i]
    assertContains(
        slash,
        'callWidgetMethod("' .. pair[1] .. '", "' .. pair[2] .. '"',
        "missing slash widget dispatch: " .. pair[1] .. ":" .. pair[2]
    )
end

assertContains(registry, 'path = "!KRT/EntryPoints/SlashEvents.lua"')
assertContains(registry, 'pattern = \'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"\'')
assertContains(registry, 'pattern = \'callWidgetMethod%("([%w_]+)"%s*,%s*"([%w_]+)"\'')

assertContains(backlog, "Wave E1 completed: Slash routing helper normalization")

print("audit cleanup wave e1 slash routing source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run:

```powershell
lua tests\audit_cleanup_wave_e1_slash_routing_spec.lua
```

Expected:

```text
missing: local function callControllerMethod(controllerName, methodName, ...)
```

---

### Task 2: Normalize SlashEvents Routing Helpers

**Files:**
- Modify: `!KRT/EntryPoints/SlashEvents.lua`

- [ ] **Step 1: Add the controller routing helper**

In `!KRT/EntryPoints/SlashEvents.lua`, place this helper after
`isToggleCommand(sub)` and before `callSyncerMethod(...)`:

```lua
local function callControllerMethod(controllerName, methodName, ...)
    return Database.RequestControllerMethod(controllerName, methodName, ...)
end
```

- [ ] **Step 2: Rename the widget routing helper**

Replace the helper header:

```lua
local function callWidget(widgetId, methodName, ...)
```

with:

```lua
local function callWidgetMethod(widgetId, methodName, ...)
```

Leave the helper body unchanged:

```lua
    if UIWidgets and type(UIWidgets.Call) == "function" then
        return UIWidgets.Call(widgetId, methodName, ...)
    end
    notifyWidgetCallUnavailable(widgetId, methodName)
    return nil
```

- [ ] **Step 3: Convert widget dispatch calls**

Replace every `callWidget("...", "...")` in `SlashEvents.lua` with
`callWidgetMethod("...", "...")`.

The final literal calls must include:

```lua
callWidgetMethod("Config", "Default")
callWidgetMethod("Config", "Toggle")
callWidgetMethod("LootCounter", "Toggle")
callWidgetMethod("Reserves", "Toggle")
callWidgetMethod("Reserves", "ToggleImport")
```

- [ ] **Step 4: Convert controller dispatch calls**

Replace every slash-handler direct controller dispatch:

```lua
Database.RequestControllerMethod("Master", "ShowDebugRaidGrid", count or 25)
Database.RequestControllerMethod("Warnings", "Toggle")
Database.RequestControllerMethod("Warnings", "RequestAnnounce", sub)
Database.RequestControllerMethod("Logger", "ToggleLootHistory")
Database.RequestControllerMethod("Logger", "ToggleRaidAttendance")
Database.RequestControllerMethod("Master", "Toggle")
Database.RequestControllerMethod("Spammer", "Toggle")
Database.RequestControllerMethod("Spammer", "RequestStart")
Database.RequestControllerMethod("Spammer", "RequestStop")
```

with the same calls through `callControllerMethod(...)`:

```lua
callControllerMethod("Master", "ShowDebugRaidGrid", count or 25)
callControllerMethod("Warnings", "Toggle")
callControllerMethod("Warnings", "RequestAnnounce", sub)
callControllerMethod("Logger", "ToggleLootHistory")
callControllerMethod("Logger", "ToggleRaidAttendance")
callControllerMethod("Master", "Toggle")
callControllerMethod("Spammer", "Toggle")
callControllerMethod("Spammer", "RequestStart")
callControllerMethod("Spammer", "RequestStop")
```

This includes the root `/krt show` and `/krt toggle` branch in
`handleSlashCommand(msg)`.

- [ ] **Step 5: Verify the helper normalization by source search**

Run:

```powershell
rg -n "callWidget\(|Database\.RequestControllerMethod\(\"" "!KRT/EntryPoints/SlashEvents.lua"
```

Expected:

```text
```

The command must return no matches. `callWidgetMethod(...)` and
`Database.RequestControllerMethod(controllerName, methodName, ...)` inside the
new helper are allowed because this search looks only for literal direct calls.

---

### Task 3: Update EntryPoint Source-Contract Scans

**Files:**
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`

- [ ] **Step 1: Replace the controller dispatch scan**

In `assertControllerDispatchContracts()`, replace the current single
`dispatchPattern` implementation:

```lua
local function assertControllerDispatchContracts()
    local sources = {
        "!KRT/EntryPoints/SlashEvents.lua",
        "!KRT/EntryPoints/Minimap.lua",
    }
    local dispatchPattern = 'Database%.RequestControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"'
    local total = 0

    for i = 1, #sources do
        local sourcePath = sources[i]
        local source = read(sourcePath)
        local count = 0

        for controllerName, methodName in source:gmatch(dispatchPattern) do
            assertControllerDispatchPair(controllerName, methodName, sourcePath)
            count = count + 1
            total = total + 1
        end

        assert(count > 0, sourcePath .. " must contain literal controller dispatch pairs")
    end

    assert(total > 0, "controller dispatch sweep must find literal dispatch pairs")
end
```

with this scan table:

```lua
local function assertControllerDispatchContracts()
    local scans = {
        {
            path = "!KRT/EntryPoints/SlashEvents.lua",
            pattern = 'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
        {
            path = "!KRT/EntryPoints/Minimap.lua",
            pattern = 'Database%.RequestControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
    }
    local total = 0

    for i = 1, #scans do
        local scan = scans[i]
        local source = read(scan.path)
        local count = 0

        for controllerName, methodName in source:gmatch(scan.pattern) do
            assertControllerDispatchPair(controllerName, methodName, scan.path)
            count = count + 1
            total = total + 1
        end

        assert(count > 0, scan.path .. " must contain literal controller dispatch pairs")
    end

    assert(total > 0, "controller dispatch sweep must find literal dispatch pairs")
end
```

- [ ] **Step 2: Replace the SlashEvents widget scan pattern**

In `assertWidgetDispatchContracts()`, change only the SlashEvents scan from:

```lua
{
    path = "!KRT/EntryPoints/SlashEvents.lua",
    pattern = 'callWidget%("([%w_]+)"%s*,%s*"([%w_]+)"',
    required = true,
},
```

to:

```lua
{
    path = "!KRT/EntryPoints/SlashEvents.lua",
    pattern = 'callWidgetMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
    required = true,
},
```

- [ ] **Step 3: Run focused source tests**

Run:

```powershell
lua tests\audit_cleanup_wave_e1_slash_routing_spec.lua
lua tests\module_registry_ui_entrypoints_spec.lua
```

Expected:

```text
audit cleanup wave e1 slash routing source contract passed
module registry ui/entrypoints source contract passed
```

At this point the E1 test may still fail only on the backlog completion marker.
That marker is added in Task 4.

---

### Task 4: Update the Cleanup Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Mark Wave E1 complete**

In `### Wave E1: Slash Routing`, extend `Current worktree progress` so it
reads:

```markdown
Current worktree progress:
- controller method dispatch now shares one helper path across toggle and action commands
- slash controller routes now use a local `callControllerMethod(...)` helper over
  `Database.RequestControllerMethod(...)`
- slash widget routes now use a local `callWidgetMethod(...)` helper over
  `addon.UI.Widgets.Call(...)`
- command syntax, help text, sync commands, validation output, and diagnostic
  summaries are unchanged
- Wave E1 completed: Slash routing helper normalization
```

- [ ] **Step 2: Advance the default next-step list**

Near the bottom, replace:

```markdown
If continuing the cleanup program immediately, start with:

1. `!KRT/EntryPoints/SlashEvents.lua` boundary cleanup follow-up
2. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
3. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
```

with:

```markdown
If continuing the cleanup program immediately, start with:

1. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
2. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
3. `!KRT/EntryPoints/Minimap.lua` boundary cleanup follow-up
```

- [ ] **Step 3: Run the Wave E1 source-contract test**

Run:

```powershell
lua tests\audit_cleanup_wave_e1_slash_routing_spec.lua
```

Expected:

```text
audit cleanup wave e1 slash routing source contract passed
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
lua tests\audit_cleanup_wave_e1_slash_routing_spec.lua
lua tests\module_registry_ui_entrypoints_spec.lua
lua tests\release_stabilization_spec.lua
```

Expected:

```text
audit cleanup wave e1 slash routing source contract passed
module registry ui/entrypoints source contract passed
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
```

Expected:

```text
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
Lua syntax check passed.
```

- [ ] **Step 6: Run formatting and diff hygiene checks**

Run:

```powershell
stylua --check !KRT\EntryPoints\SlashEvents.lua tests\audit_cleanup_wave_e1_slash_routing_spec.lua
stylua --check tests\module_registry_ui_entrypoints_spec.lua
git diff --check
git status --short
```

Expected:

```text
```

`git diff --check` must have no errors. `git status --short` must show only the
intended Wave E1 files and generated catalog files.

---

### Task 6: Parent Review, Commit, and Smoke Handoff

**Files:**
- Review all changed files.

- [ ] **Step 1: Inspect the final diff**

Run:

```powershell
git diff --stat
git diff -- !KRT/EntryPoints/SlashEvents.lua
git diff -- tests/module_registry_ui_entrypoints_spec.lua
git diff -- tests/audit_cleanup_wave_e1_slash_routing_spec.lua
git diff -- docs/TECH_CLEANUP_BACKLOG.md
```

Expected:

```text
```

Review expectations:

- Slash command syntax and aliases are unchanged.
- `SlashEvents.lua` still owns slash parsing/help/diagnostics/dispatch.
- Controller dispatches go through `callControllerMethod(...)`.
- Widget dispatches go through `callWidgetMethod(...)`.
- Logger sync dispatches still go through `callSyncerMethod(...)` and
  `callSyncerMethodWithTarget(...)`.
- Reserves/validate/perf/debug/bug/version behavior is unchanged.
- Source-contract tests still validate literal dispatch pairs.

- [ ] **Step 2: Commit the Wave E1 patch**

Run:

```powershell
git add -- `
  "!KRT/EntryPoints/SlashEvents.lua" `
  "tests/module_registry_ui_entrypoints_spec.lua" `
  "tests/audit_cleanup_wave_e1_slash_routing_spec.lua" `
  "docs/TECH_CLEANUP_BACKLOG.md" `
  "docs/superpowers/plans/2026-06-14-audit-cleanup-wave-e1-slash-routing.md" `
  "docs/FUNCTION_REGISTRY.csv" `
  "docs/FN_CLUSTERS.md" `
  "docs/TREE.md"

git commit -m "Normalize slash routing helpers"
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
<clean status, followed by the Wave E1 commit stat>
```

`git status --short` must be empty.

## In-Client Smoke Checklist

Run this on WoW 3.3.5a after the commit:

- `/reload` with no Lua errors.
- `/krt` prints root help.
- `/krt logger` toggles loot history.
- `/krt logger req <raidId|raidNid> <player>` still routes to logger sync.
- `/krt logger push <raidId|raidNid> <player>` still routes to logger sync.
- `/krt logger sync` still requests logger sync.
- `/krt loot` and `/krt ml` toggle Loot Master.
- `/krt counter` toggles Loot Counter.
- `/krt reserves` toggles reserves list.
- `/krt reserves import` opens the import view.
- `/krt reserves check` prints readiness.
- `/krt validate raids` still prints validation output.
- `/krt bug` and `/krt version` still print diagnostics.

## Self-Review

- Spec coverage: this plan covers routing helper normalization, source-contract
  updates, backlog update, catalog refresh, full gates, commit, and smoke handoff.
- Placeholder scan: no placeholder tasks are left; every edit step includes
  exact paths, concrete code, exact commands, and expected results.
- Type/name consistency: the local helper names are `callControllerMethod` and
  `callWidgetMethod`; source-contract scans use those exact names.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-06-14-audit-cleanup-wave-e1-slash-routing.md`.

Two execution options:

1. Subagent-Driven (recommended) - dispatch a focused implementation subagent,
   then parent review and correction before commit.
2. Inline Execution - execute this plan in the current session with checkpoints.
