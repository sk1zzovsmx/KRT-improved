# Wave U1 UI Scaffold Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize the `UI.Scaffold.DefineModule` lifecycle helpers in
`!KRT/Modules/UI/Frames.lua` without changing frame behavior, controller/widget
public APIs, XML layout, or user-visible UI behavior.

**Architecture:** Wave U1 stays inside the shared UI infrastructure owner. The
patch extracts explicit local helper boundaries around scaffold config
validation, module frame loading, reference acquisition, and refresh dispatch.
Existing Controllers and Widgets keep calling `UI.Scaffold.DefineModule(cfg)`.
Generated module methods stay limited to the current surface:
`BindUI`, `EnsureUI`, `Toggle`, `Hide`, `RequestRefresh`, and `MarkDirty`.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT UI scaffold,
repo-local Lua/Python/PowerShell gates, delegated 55to53 workflow.

---

## Classification

- `55to53`: `complex-orchestrated`
- Reason: touches shared UI infrastructure, module lifecycle contracts, tests,
  cleanup backlog docs, and generated catalogs.
- Required execution mode: project delegated workflow.
- Required mapping: use `code-mapper` before implementation.
- Required implementation: delegate the runtime patch to `spark_implementer`.
- Parent review must inspect the final diff before closing the wave.

## File Structure

- Modify: `!KRT/Modules/UI/Frames.lua`
  - Add local helper boundaries for scaffold config validation, frame load
    state, reference acquisition, and refresh dispatch.
  - Keep all existing public namespace exports under `addon.UI.*`.
  - Keep `Frames.MakeEventDrivenRefresher(...)` as the only shared refresh
    driver path used by `Scaffold.DefineModule(...)`.
  - Do not add new generated module methods unless mapping proves an existing
    runtime contract requires it.
- Modify: `tests/release_stabilization_spec.lua`
  - Add one behavior guard that loads the real `!KRT/Modules/UI/Frames.lua`
    and verifies scaffold bind, localization, and refresh scheduling.
- Create: `tests/audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua`
  - Guard source shape, helper ordering, public method surface, backlog marker,
    and release test name.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Mark Wave U1 complete under the Wave U1 section.
  - Keep the Wave U1 scope and non-goals intact.
- Generated, if changed by `py -3 tools/krt.py api-catalog-refresh`:
  - `docs/FUNCTION_REGISTRY.csv`
  - `docs/FN_CLUSTERS.md`
  - `docs/TREE.md`

## Non-Goals

- Do not change frame layout, anchors, visibility rules, menu behavior, or
  tooltip behavior.
- Do not edit XML files or add XML `<Scripts>`/`<On...>` handlers.
- Do not migrate Controllers or Widgets to a new scaffold API.
- Do not add a new public scaffold API or generated module method during U1.
- Do not touch Services; services must remain UI-free.
- Do not edit SavedVariables, database schema, options schema, or migrations.
- Do not edit vendored libraries under `!KRT/Libs/*`.
- Do not edit `!KRT/CHANGELOG.md`; this is internal cleanup without
  user-visible behavior change.

---

### Task 0: Read-Only Mapping Checkpoint

**Files:**
- Read: `!KRT/Modules/UI/Frames.lua`
- Read: `!KRT/Controllers/Logger.lua`
- Read: `!KRT/Controllers/Master.lua`
- Read: `!KRT/Controllers/Spammer.lua`
- Read: `!KRT/Controllers/Warnings.lua`
- Read: `!KRT/Widgets/Config.lua`
- Read: `!KRT/Widgets/LootCounter.lua`
- Read: `!KRT/Widgets/ReservesUI.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `tests/module_registry_ui_spec.lua`
- Read: `tests/ui_api_namespace_spec.lua`
- Read: `tests/module_registry_ui_entrypoints_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Launch the delegated workflow for implementation**

  From `C:\Users\ferra\Downloads\KRT-improved`, use this handoff command if the
  work is started in a new Codex helper:

  ```powershell
  py -3 tools/krt.py codex-55to53 `
    --classification complex-orchestrated `
    --mode handoff `
    --branch-mode off `
    --prompt-file docs/superpowers/plans/2026-06-14-audit-cleanup-wave-u1-ui-scaffold-infrastructure.md `
    --output-file .codex/prompts/wave-u1-ui-scaffold-infrastructure.prompt.md
  ```

  If executing inside the current thread instead, still follow the same
  `code-mapper -> spark_implementer -> parent review` sequence.

- [ ] **Step 2: Map scaffold consumers before editing**

  Confirm every direct `Scaffold.DefineModule({` or
  `UI.Scaffold.DefineModule({` consumer still relies only on the current
  generated method surface. The current consumer list is:

  - `!KRT/Controllers/Logger.lua`
  - `!KRT/Controllers/Master.lua`
  - `!KRT/Controllers/Spammer.lua`
  - `!KRT/Controllers/Warnings.lua`
  - `!KRT/Widgets/Config.lua`
  - `!KRT/Widgets/LootCounter.lua`
  - `!KRT/Widgets/ReservesUI.lua`

  Mapping must specifically answer:

  - whether any consumer expects a generated `module:Show()` method;
  - whether any consumer depends on `cfg.onLoad`, `cfg.acquireRefs`,
    `cfg.bind`, `cfg.localize`, or `cfg.refresh` side effects beyond the
    current call order;
  - whether any consumer passes `initFrameOpts` that must continue to flow
    through `Frames.BindModuleFrame(...)`;
  - whether any existing entrypoint dispatch depends on scaffold behavior.

- [ ] **Step 3: Confirm the implementation remains U1-sized**

  Stop and return to the parent if mapping reveals that U1 needs controller,
  widget, XML, options, SavedVariables, or public API changes. That is outside
  this plan.

### Task 1: Add Scaffold Source-Contract Test First

**Files:**
- Create: `tests/audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua`

- [ ] **Step 1: Create the source-contract test scaffold**

  Start from the same pattern as the other `tests/audit_cleanup_wave_*_spec.lua`
  files: local `read`, `assertContains`, `assertNotContains`, `assertBefore`,
  and optional `countPlain` helpers.

- [ ] **Step 2: Guard the new helper boundaries**

  The test must read `!KRT/Modules/UI/Frames.lua` and assert these literals:

  ```lua
  local frames = read("!KRT/Modules/UI/Frames.lua")

  assertContains(frames, "local function validateScaffoldConfig(")
  assertContains(frames, "local function loadModuleFrame(")
  assertContains(frames, "local function acquireModuleRefs(")
  assertContains(frames, "local function dispatchModuleRefresh(")
  assertContains(frames, "validateScaffoldConfig(")
  assertContains(frames, "loadModuleFrame(module, frame, uiState, onLoadFrame, initFrameOpts)")
  assertContains(frames, "acquireModuleRefs(frame, uiState.FrameName, acquireRefs)")
  assertContains(frames, "dispatchModuleRefresh(module, refreshFn, uiState, frame, refs, dirty, reason)")
  ```

- [ ] **Step 3: Guard helper ordering**

  The test must prove helper definitions stay before `Scaffold.DefineModule`:

  ```lua
  assertBefore(frames, "local function validateScaffoldConfig(", "function Scaffold.DefineModule(cfg)")
  assertBefore(frames, "local function loadModuleFrame(", "function Scaffold.DefineModule(cfg)")
  assertBefore(frames, "local function acquireModuleRefs(", "function Scaffold.DefineModule(cfg)")
  assertBefore(frames, "local function dispatchModuleRefresh(", "function Scaffold.DefineModule(cfg)")
  ```

- [ ] **Step 4: Guard existing validation messages**

  Preserve the current exact error strings:

  ```lua
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.module must be a table")
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.getFrame must be a function")
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.acquireRefs must be a function")
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.bind must be a function")
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.localize must be a function")
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.onLoad must be a function")
  assertContains(frames, "UI.Scaffold.DefineModule: cfg.refresh must be a function")
  ```

- [ ] **Step 5: Guard the public generated method surface**

  Assert the current scaffold-generated methods still exist:

  ```lua
  assertContains(frames, "function module:MarkDirty(reason)")
  assertContains(frames, "function module:RequestRefresh(reason)")
  assertContains(frames, "function module:BindUI()")
  assertContains(frames, "function module:EnsureUI()")
  assertContains(frames, "function module:Toggle()")
  assertContains(frames, "function module:Hide()")
  ```

  Also assert U1 did not introduce a new generated `module:Show()` method:

  ```lua
  assertNotContains(frames, "function module:Show()")
  ```

- [ ] **Step 6: Guard release coverage and backlog marker**

  The test must read `tests/release_stabilization_spec.lua` and
  `docs/TECH_CLEANUP_BACKLOG.md`, then assert:

  ```lua
  local testName = 'test("ui scaffold define module keeps bind and refresh lifecycle centralized", function()'
  assertContains(releaseSpec, testName)
  assertContains(backlog, "Wave U1 completed: UI Scaffold infrastructure cleanup")
  ```

  End with:

  ```lua
  print("audit cleanup wave u1 ui scaffold infrastructure source contract passed")
  ```

- [ ] **Step 7: Verify the new source-contract test fails before code changes**

  Run:

  ```powershell
  lua tests/audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua
  ```

  Expected result before implementation: failure because helper literals and
  backlog completion marker are not present yet.

### Task 2: Add Behavior Coverage For Real Scaffold Lifecycle

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Insert the test near the existing UI frame/tooltips tests**

  Place the new test near the existing `h:load("!KRT/Modules/UI/Frames.lua")`
  tests so the UI infrastructure coverage remains grouped.

- [ ] **Step 2: Add this behavior test**

  Add the test with this name exactly:

  ```lua
  test("ui scaffold define module keeps bind and refresh lifecycle centralized", function()
      local h = newHarness()
      local frame = h.makeFrame(true, "KRTU1ScaffoldFrame")
      local driver = h.makeFrame(true, "KRTU1ScaffoldRefreshDriver")
      local calls = {}

      _G.KRTU1ScaffoldFrame = frame
      _G.CreateFrame = function()
          return driver
      end

      h:load("!KRT/Modules/UI/Frames.lua")

      local module = {}
      h.addon.UI.Scaffold.DefineModule({
          module = module,
          getFrame = function()
              return frame
          end,
          acquireRefs = function(boundFrame, frameName)
              calls[#calls + 1] = "refs:" .. tostring(frameName)
              assertEqual(boundFrame, frame, "expected acquireRefs to receive the module frame")
              return { Button = true }
          end,
          bind = function(frameName, boundFrame, refs)
              calls[#calls + 1] = "bind:" .. tostring(frameName) .. ":" .. tostring(refs.Button)
              assertEqual(boundFrame, frame, "expected bind to receive the module frame")
          end,
          localize = function(frameName, boundFrame, refs)
              calls[#calls + 1] = "localize:" .. tostring(frameName) .. ":" .. tostring(refs.Button)
              assertEqual(boundFrame, frame, "expected localize to receive the module frame")
          end,
          refresh = function(frameName, boundFrame, refs, dirty, reason)
              calls[#calls + 1] = "refresh:" .. tostring(frameName)
                  .. ":" .. tostring(dirty) .. ":" .. tostring(reason)
              assertEqual(boundFrame, frame, "expected refresh to receive the module frame")
              assertTrue(refs.Button == true, "expected refresh to receive acquired refs")
          end,
      })

      local boundFrame, refs = module:BindUI()

      assertEqual(boundFrame, frame, "expected BindUI to return the module frame")
      assertTrue(refs.Button == true, "expected BindUI to return acquired refs")
      assertEqual(calls[1], "refs:KRTU1ScaffoldFrame", "expected refs before bind")
      assertEqual(calls[2], "bind:KRTU1ScaffoldFrame:true", "expected bind after refs")
      assertEqual(calls[3], "localize:KRTU1ScaffoldFrame:true", "expected localize after bind")
      assertTrue(driver.OnUpdate ~= nil, "expected visible bind to schedule refresh")

      driver.OnUpdate(driver)
      assertEqual(calls[4], "refresh:KRTU1ScaffoldFrame:true:bind", "expected bind refresh")

      module:RequestRefresh("manual")
      assertTrue(driver.OnUpdate ~= nil, "expected manual refresh to schedule driver")
      driver.OnUpdate(driver)
      assertEqual(calls[5], "refresh:KRTU1ScaffoldFrame:true:manual", "expected manual refresh")

      assertEqual(module:EnsureUI(), frame, "expected EnsureUI to reuse bound frame")
      assertEqual(#calls, 5, "expected EnsureUI not to rebind or relocalize")
  end)
  ```

- [ ] **Step 3: Run the focused behavior test target**

  Run:

  ```powershell
  lua tests/release_stabilization_spec.lua
  ```

  Expected result before implementation: the new behavior test should still
  pass against current behavior if added without source changes. If it fails,
  fix the test harness assumptions before changing production code.

### Task 3: Centralize Scaffold Helpers

**Files:**
- Modify: `!KRT/Modules/UI/Frames.lua`

- [ ] **Step 1: Add `validateScaffoldConfig(...)`**

  Add the helper above `Scaffold.DefineModule(cfg)`:

  ```lua
  local function validateScaffoldConfig(module, getFrame, acquireRefs, bindHandlers, localize, onLoadFrame, refreshFn)
  ```

  Move the current inline validation into this helper. Preserve the exact
  validation conditions and exact error strings. Do not add new validation
  cases.

- [ ] **Step 2: Add `dispatchModuleRefresh(...)`**

  Add the helper above `Scaffold.DefineModule(cfg)`:

  ```lua
  local function dispatchModuleRefresh(module, refreshFn, uiState, frame, refs, dirty, reason)
  ```

  Preserve the current fallback order exactly:

  - call `refreshFn(uiState.FrameName, frame, refs, dirty, reason)` first;
  - otherwise call `module:RefreshUI(uiState.FrameName, frame, refs, dirty, reason)`;
  - otherwise call `module:Refresh(dirty, reason)`;
  - otherwise return `nil`.

- [ ] **Step 3: Add `loadModuleFrame(...)`**

  Add the helper above `Scaffold.DefineModule(cfg)`:

  ```lua
  local function loadModuleFrame(module, frame, uiState, onLoadFrame, initFrameOpts)
  ```

  Preserve the current load behavior exactly:

  - if `uiState.Loaded` is already true, return `uiState.FrameName`;
  - when `onLoadFrame` exists, call `onLoadFrame(frame)`;
  - otherwise call `Frames.BindModuleFrame(module, frame, initFrameOpts)`;
  - set `uiState.FrameName` to the returned frame name, or
    `(frame.GetName and frame:GetName())`, or the prior `uiState.FrameName`;
  - set `uiState.Loaded = uiState.FrameName ~= nil`;
  - return `uiState.FrameName`.

- [ ] **Step 4: Add `acquireModuleRefs(...)`**

  Add the helper above `Scaffold.DefineModule(cfg)`:

  ```lua
  local function acquireModuleRefs(frame, frameName, acquireRefs)
  ```

  Preserve the current fallback exactly:

  ```lua
  return acquireRefs and acquireRefs(frame, frameName) or {}
  ```

- [ ] **Step 5: Wire helpers into `Scaffold.DefineModule(cfg)`**

  Replace the inline validation block with:

  ```lua
  validateScaffoldConfig(module, getFrame, acquireRefs, bindHandlers, localize, onLoadFrame, refreshFn)
  ```

  Replace the inline refresh dispatch in `doRefresh()` with:

  ```lua
  local refs = module.refs
  return dispatchModuleRefresh(module, refreshFn, uiState, frame, refs, dirty, reason)
  ```

  Replace the inline load block in `module:BindUI()` with:

  ```lua
  loadModuleFrame(module, frame, uiState, onLoadFrame, initFrameOpts)
  ```

  Replace the refs expression in `module:BindUI()` with:

  ```lua
  local refs = acquireModuleRefs(frame, uiState.FrameName, acquireRefs)
  ```

- [ ] **Step 6: Keep generated methods unchanged**

  Do not add, remove, or rename these generated methods:

  - `module:MarkDirty(reason)`
  - `module:RequestRefresh(reason)`
  - `module:BindUI()`
  - `module:EnsureUI()`
  - `module:Toggle()`
  - `module:Hide()`

  Do not add `module:Show()` in this wave.

- [ ] **Step 7: Keep non-scaffold frame helpers untouched**

  Do not modify `Frames.MakeEventDrivenRefresher(...)`,
  `Frames.MakeFrameGetter(...)`, `Frames.BindModuleFrame(...)`,
  `makeUIFrameController(...)`, `Scaffold.CreateWidgetApi(...)`,
  `Scaffold.CreateListPanel(...)`, editbox helpers, popup helpers, or tooltip
  helpers unless a test fails because of the U1 refactor.

### Task 4: Update Cleanup Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Update Wave U1 progress**

  Under `### Wave U1: UI Scaffold Infrastructure`, keep the existing progress
  bullets and add these bullets:

  ```markdown
  - scaffold config validation now shares one local helper with the existing
    error contract
  - module frame load state, ref acquisition, and refresh dispatch now have
    explicit helper boundaries inside the scaffold
  - Wave U1 completed: UI Scaffold infrastructure cleanup
  ```

- [ ] **Step 2: Do not change unrelated backlog waves**

  Leave Wave B1, Wave C2, Wave E2, Wave S2, Wave S3, and any default next-step
  list unchanged unless there is an existing U1 entry that must be marked done.

### Task 5: Refresh Catalogs And Run Gates

**Files:**
- Generated if changed:
  - `docs/FUNCTION_REGISTRY.csv`
  - `docs/FN_CLUSTERS.md`
  - `docs/TREE.md`

- [ ] **Step 1: Run focused tests**

  ```powershell
  lua tests/audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua
  lua tests/release_stabilization_spec.lua
  lua tests/module_registry_ui_spec.lua
  lua tests/ui_api_namespace_spec.lua
  lua tests/module_registry_ui_entrypoints_spec.lua
  ```

- [ ] **Step 2: Run standard repo gates**

  ```powershell
  py -3 tools/krt.py repo-quality-check --check toc_files
  py -3 tools/krt.py repo-quality-check --check lua_uniformity
  py -3 tools/krt.py repo-quality-check --check raid_hardening
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
  ```

- [ ] **Step 3: Refresh generated docs**

  ```powershell
  py -3 tools/krt.py api-catalog-refresh
  ```

- [ ] **Step 4: Re-run source-contract test after generated docs refresh**

  ```powershell
  lua tests/audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua
  ```

### Task 6: Parent Review

**Files:**
- Review all changed files from `git diff --stat` and `git diff`.

- [ ] **Step 1: Confirm plan adherence**

  Parent review must verify:

  - only the planned files changed;
  - no XML files changed;
  - no Services changed;
  - no SavedVariables, database schema, options schema, or migrations changed;
  - no generated module methods were added or removed;
  - validation error strings are unchanged;
  - `cfg.refresh`, `module:RefreshUI`, and `module:Refresh` fallback order is
    unchanged;
  - visible-frame bind still schedules one event-driven refresh through
    `Frames.MakeEventDrivenRefresher(...)`.

- [ ] **Step 2: Review generated docs**

  If `api-catalog-refresh` changes generated docs, confirm those diffs are only
  function-line/catalog/tree updates caused by `Frames.lua`.

- [ ] **Step 3: Record manual smoke requirement for the user**

  Ask the user to run a WoW 3.3.5a in-client smoke after the code patch:

  - Login: no errors; `/krt` opens.
  - Toggle Master, Logger loot history, Logger raid attendance, Warnings,
    Spammer, Config, Reserves, and Loot Counter.
  - Confirm shown modules refresh and no duplicate binding/localization errors
    appear after `/reload`.

---

## Expected Final Diff Shape

- `!KRT/Modules/UI/Frames.lua` has small helper extractions near
  `Scaffold.DefineModule(cfg)`.
- `tests/release_stabilization_spec.lua` has one new scaffold behavior test.
- `tests/audit_cleanup_wave_u1_ui_scaffold_infrastructure_spec.lua` exists.
- `docs/TECH_CLEANUP_BACKLOG.md` marks U1 complete.
- Generated catalog docs may update after `py -3 tools/krt.py api-catalog-refresh`.

## Commit Message

Use this commit message after implementation and verification:

```text
Centralize UI scaffold lifecycle helpers
```
