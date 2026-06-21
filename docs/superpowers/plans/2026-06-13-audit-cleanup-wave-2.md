# Audit Cleanup Wave 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining low-risk audit cleanup items after Wave 1 without changing runtime
behavior, SavedVariables shape, UI contracts, or WoW 3.3.5a compatibility.

**Architecture:** Wave 2 is a narrow cleanup wave. It removes duplicated local glue where the
existing owner is clear, keeps public service facades intact, and does not move delicate DB,
sync, raid-runtime, loot, roll, or migration behavior.

**Tech Stack:** World of Warcraft 3.3.5a, Interface 30300, Lua 5.1, KRT project workflow,
PowerShell repo tooling, Lua source-contract specs.

---

## Classification

Use the project `55to53` workflow.

- Classification: `complex-orchestrated`
- Reason: more than one file is likely to change, runtime services and entrypoints are involved,
  and each patch needs review/check cycles.
- Execution model: parent plans and reviews; `spark_implementer` applies each approved patch.
- Mapping: use `code-mapper` before Task 2 if the branch has changed since this plan was written.

## Branching

Wave 1 currently ends at `2042957 test: align logger visual skin assertion` on
`codex/audit-cleanup-wave-1-current`.

Use one of these two branch starts:

```powershell
# Stacked execution, before Wave 1 is merged.
git checkout codex/audit-cleanup-wave-1-current
git checkout -b codex/audit-cleanup-wave-2-current
```

```powershell
# Conservative execution, after Wave 1 is merged into the integration branch.
git checkout codex/chat-service-package-refactor
git pull
git checkout -b codex/audit-cleanup-wave-2-current
```

Before editing:

```powershell
git status --short
py -3 tools/krt.py repo-quality-check --check all
lua tests\release_stabilization_spec.lua
```

Expected:

- `git status --short` has no output.
- `repo-quality-check --check all` exits `0`.
- `release_stabilization_spec.lua` exits `0`.

## Files

Modify:

- `tests/audit_cleanup_wave2_spec.lua`
- `!KRT/Services/Logger/View.lua`
- `!KRT/Services/Logger/Export.lua`
- `!KRT/Services/Reserves.lua`
- `!KRT/EntryPoints/SlashEvents.lua`
- `!KRT/Controllers/Logger.lua`

Generated docs may change after hooks or explicit catalog refresh:

- `docs/FN_CLUSTERS.md`
- `docs/FUNCTION_REGISTRY.csv`
- `docs/API_NOMENCLATURE_CENSUS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_PUBLIC.csv`
- `docs/API_REGISTRY_INTERNAL.csv`
- `docs/TREE.md`

Do not modify:

- `!KRT/Libs/*`
- `!KRT/Database/*`
- `!KRT/Services/Loot/*`
- `!KRT/Services/Rolls/*`
- `!KRT/Services/Loot/DistributionSession.lua`
- `!KRT/UI/*.xml`
- `!KRT/!KRT.toc`, unless a generated tree check reports drift from a real file change

## Deferred Items

Do not include these in Wave 2:

- `DBSyncer.lua` request tracking extraction.
- DB attendance segment consolidation across store and migrations.
- Raid/loot runtime invalidation ownership changes.
- `getModeSignature` centralization.
- Facade wrapper removal in `Services/Master/Service.lua`, `Services/Rolls/Service.lua`, or
  `Services/Logger/*`.
- `getClass` consolidation in Master assignment files. It is a P2 candidate, but a clean shared
  owner would require either a new helper module or a private cross-file helper contract. Keep it
  for a separate wave with a dedicated call-site map.

---

### Task 1: Add Wave 2 Source-Contract Harness

**Files:**

- Create: `tests/audit_cleanup_wave2_spec.lua`

- [ ] **Step 1: Create the initial test file for perf helper cleanup**

Create `tests/audit_cleanup_wave2_spec.lua` with this content:

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

local loggerView = read("!KRT/Services/Logger/View.lua")
local loggerExport = read("!KRT/Services/Logger/Export.lua")
local reserves = read("!KRT/Services/Reserves.lua")

assertNotContains(
    loggerView,
    "local function startPerf()",
    "Logger view should call the canonical perf start hook directly"
)
assertNotContains(
    loggerExport,
    "local function startPerf()",
    "Logger export should call the canonical perf start hook directly"
)
assertNotContains(
    reserves,
    "local function startPerf()",
    "Reserves should call the canonical perf start hook directly"
)

assertContains(loggerView, "addon:_PerfStart()", "Logger view should use addon:_PerfStart()")
assertContains(loggerExport, "addon:_PerfStart()", "Logger export should use addon:_PerfStart()")
assertContains(reserves, "addon:_PerfStart()", "Reserves should use addon:_PerfStart()")

print("audit cleanup wave2 source contract passed")
```

- [ ] **Step 2: Run the new test and verify it fails before implementation**

Run:

```powershell
lua tests\audit_cleanup_wave2_spec.lua
```

Expected failure on current Wave 1 code:

```text
Logger view should call the canonical perf start hook directly
```

The exact first failure may move if another file is already patched, but the test must fail before
Task 2 implementation.

---

### Task 2: Remove Duplicated `startPerf` Wrappers

**Files:**

- Modify: `!KRT/Services/Logger/View.lua`
- Modify: `!KRT/Services/Logger/Export.lua`
- Modify: `!KRT/Services/Reserves.lua`
- Modify: `tests/audit_cleanup_wave2_spec.lua`

- [ ] **Step 1: Confirm canonical perf hook ownership**

Run:

```powershell
rg -n "addon\._PerfStart|local function startPerf|startPerf\(" !KRT tests -g "*.lua"
```

Expected facts before editing:

- `addon._PerfStart` is defined in `!KRT/Init.lua`.
- `Logger/View.lua`, `Logger/Export.lua`, and `Reserves.lua` each define a local `startPerf`.
- These local wrappers only guard and call `addon:_PerfStart()`.

- [ ] **Step 2: Remove the local wrapper from Logger View**

In `!KRT/Services/Logger/View.lua`, delete this helper:

```lua
local function startPerf()
    if addon.hasPerf and addon._PerfStart then
        return addon:_PerfStart()
    end
    return nil
end
```

Replace each call like this:

```lua
local perfStart = startPerf()
```

with:

```lua
local perfStart = addon:_PerfStart()
```

- [ ] **Step 3: Remove the local wrapper from Logger Export**

In `!KRT/Services/Logger/Export.lua`, delete this helper:

```lua
local function startPerf()
    if addon.hasPerf and addon._PerfStart then
        return addon:_PerfStart()
    end
    return nil
end
```

Replace each call like this:

```lua
local perfStart = startPerf()
```

with:

```lua
local perfStart = addon:_PerfStart()
```

- [ ] **Step 4: Remove the local wrapper from Reserves**

In `!KRT/Services/Reserves.lua`, delete this helper:

```lua
local function startPerf()
    if addon.hasPerf and addon._PerfStart then
        return addon:_PerfStart()
    end
    return nil
end
```

Replace each call like this:

```lua
local perfStart = startPerf()
```

with:

```lua
local perfStart = addon:_PerfStart()
```

Do not change `finishPerf`, labels, detail strings, or chunking behavior.

- [ ] **Step 5: Verify focused tests**

Run:

```powershell
lua tests\audit_cleanup_wave2_spec.lua
lua tests\release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected:

- `audit_cleanup_wave2_spec.lua` prints `audit cleanup wave2 source contract passed`.
- `release_stabilization_spec.lua` reports targeted stabilization tests passed.
- Syntax and uniformity checks exit `0`.

- [ ] **Step 6: Commit Task 2**

Stage only the touched files and generated docs created by hooks:

```powershell
git add -- tests\audit_cleanup_wave2_spec.lua `
    !KRT\Services\Logger\View.lua `
    !KRT\Services\Logger\Export.lua `
    !KRT\Services\Reserves.lua
git status --short
git commit -m "refactor: call perf start hook directly"
```

If the pre-commit hook reports generated catalog drift, inspect and stage only generated docs:

```powershell
git status --short
git add -- docs\FN_CLUSTERS.md docs\FUNCTION_REGISTRY.csv `
    docs\API_NOMENCLATURE_CENSUS.md docs\API_REGISTRY.csv `
    docs\API_REGISTRY_PUBLIC.csv docs\API_REGISTRY_INTERNAL.csv docs\TREE.md
git commit -m "refactor: call perf start hook directly"
```

---

### Task 3: Unify Slash Toggle Help Wrappers

**Files:**

- Modify: `tests/audit_cleanup_wave2_spec.lua`
- Modify: `!KRT/EntryPoints/SlashEvents.lua`

- [ ] **Step 1: Extend the Wave 2 source-contract test**

Append this block before the final `print(...)` line in `tests/audit_cleanup_wave2_spec.lua`:

```lua
local slashEvents = read("!KRT/EntryPoints/SlashEvents.lua")

assertContains(
    slashEvents,
    "local function showToggleHelp(commandRoot)",
    "SlashEvents should share one toggle-help wrapper"
)
assertNotContains(
    slashEvents,
    "local function showLootHelp()",
    "SlashEvents should not keep the old loot help wrapper"
)
assertNotContains(
    slashEvents,
    "local function showCounterHelp()",
    "SlashEvents should not keep the old counter help wrapper"
)
assertContains(slashEvents, 'showToggleHelp("krt ml")', "Master loot help should use shared toggle help")
assertContains(slashEvents, 'showToggleHelp("krt counter")', "Counter help should use shared toggle help")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run:

```powershell
lua tests\audit_cleanup_wave2_spec.lua
```

Expected failure on current Wave 1 code:

```text
SlashEvents should share one toggle-help wrapper
```

- [ ] **Step 3: Replace the duplicated helpers**

In `!KRT/EntryPoints/SlashEvents.lua`, replace:

```lua
local function showLootHelp()
    addon:info(format(L.StrCmdCommands, "krt ml"), "KRT")
    printHelp("toggle", L.StrCmdToggle)
end

local function showCounterHelp()
    addon:info(format(L.StrCmdCommands, "krt counter"), "KRT")
    printHelp("toggle", L.StrCmdToggle)
end
```

with:

```lua
local function showToggleHelp(commandRoot)
    addon:info(format(L.StrCmdCommands, commandRoot), "KRT")
    printHelp("toggle", L.StrCmdToggle)
end
```

- [ ] **Step 4: Update call sites**

Replace the master-loot help call:

```lua
showLootHelp()
```

with:

```lua
showToggleHelp("krt ml")
```

Replace the counter help call:

```lua
showCounterHelp()
```

with:

```lua
showToggleHelp("krt counter")
```

- [ ] **Step 5: Verify focused tests**

Run:

```powershell
lua tests\audit_cleanup_wave2_spec.lua
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected:

- `audit_cleanup_wave2_spec.lua` prints `audit cleanup wave2 source contract passed`.
- Syntax and uniformity checks exit `0`.

- [ ] **Step 6: Commit Task 3**

```powershell
git add -- tests\audit_cleanup_wave2_spec.lua !KRT\EntryPoints\SlashEvents.lua
git status --short
git commit -m "refactor: share slash toggle help wrapper"
```

Stage generated docs only if hooks report catalog drift.

---

### Task 4: Share Logger Attendee Popup Reset Hook

**Files:**

- Modify: `tests/audit_cleanup_wave2_spec.lua`
- Modify: `!KRT/Controllers/Logger.lua`

- [ ] **Step 1: Extend the Wave 2 source-contract test**

Append this block before the final `print(...)` line in `tests/audit_cleanup_wave2_spec.lua`:

```lua
local logger = read("!KRT/Controllers/Logger.lua")

assertContains(
    logger,
    "local function resetPopupNameEditBox(box)",
    "Logger should centralize attendee popup name reset"
)
assertContains(logger, "onShow = resetPopupNameEditBox", "Attendee popup OnShow should reuse reset helper")
assertContains(logger, "onHide = resetPopupNameEditBox", "Attendee popup OnHide should reuse reset helper")
assertNotContains(
    logger,
    "onShow = function(b)\n"
        .. "            local refs = ensurePopupRefs(b)\n"
        .. "            UI.EditBoxes.Reset(refs and refs.name)",
    "Attendee popup OnShow should not keep an inline duplicate reset body"
)
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run:

```powershell
lua tests\audit_cleanup_wave2_spec.lua
```

Expected failure on current Wave 1 code:

```text
Logger should centralize attendee popup name reset
```

- [ ] **Step 3: Add the local reset helper**

In `!KRT/Controllers/Logger.lua`, add this helper immediately after `ensurePopupRefs`:

```lua
local function resetPopupNameEditBox(box)
    local refs = ensurePopupRefs(box)
    UI.EditBoxes.Reset(refs and refs.name)
end
```

- [ ] **Step 4: Replace the attendee popup inline callbacks**

In the `makePopupBox("AttendeesBox", "KRTLoggerPlayerBox", { ... })` config, replace:

```lua
onShow = function(b)
    local refs = ensurePopupRefs(b)
    UI.EditBoxes.Reset(refs and refs.name)
end,
onHide = function(b)
    local refs = ensurePopupRefs(b)
    UI.EditBoxes.Reset(refs and refs.name)
end,
```

with:

```lua
onShow = resetPopupNameEditBox,
onHide = resetPopupNameEditBox,
```

Do not change BossBox callbacks. BossBox `onShow` and `onHide` are behaviorally different and must
remain separate.

- [ ] **Step 5: Verify focused tests**

Run:

```powershell
lua tests\audit_cleanup_wave2_spec.lua
lua tests\logger_visual_refresh_spec.lua
lua tests\controllers_cleanup_spec.lua
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected:

- All three Lua specs exit `0`.
- Syntax and uniformity checks exit `0`.

- [ ] **Step 6: Commit Task 4**

```powershell
git add -- tests\audit_cleanup_wave2_spec.lua !KRT\Controllers\Logger.lua
git status --short
git commit -m "refactor: share logger popup reset hook"
```

Stage generated docs only if hooks report catalog drift.

---

### Task 5: Final Catalog Refresh And Verification

**Files:**

- Modify generated docs only if tools report drift.

- [ ] **Step 1: Run the full repo gate**

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected:

- All checks exit `0`.
- If catalog drift is reported, run the generated-doc commands in Step 2.

- [ ] **Step 2: Refresh generated docs only if needed**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\update-tree.ps1
```

Stage only generated docs:

```powershell
git add -- docs\FN_CLUSTERS.md docs\FUNCTION_REGISTRY.csv `
    docs\API_NOMENCLATURE_CENSUS.md docs\API_REGISTRY.csv `
    docs\API_REGISTRY_PUBLIC.csv docs\API_REGISTRY_INTERNAL.csv docs\TREE.md
```

Commit only if there are staged generated-doc changes:

```powershell
git status --short
git commit -m "docs: refresh cleanup wave 2 catalogs"
```

- [ ] **Step 3: Run final targeted tests**

```powershell
lua tests\audit_cleanup_wave2_spec.lua
lua tests\release_stabilization_spec.lua
lua tests\logger_visual_refresh_spec.lua
lua tests\controllers_cleanup_spec.lua
lua tests\controller_chunk_budget_spec.lua
lua tests\master_model_services_spec.lua
lua tests\master_service_split_spec.lua
py -3 tools/krt.py repo-quality-check --check all
git status --short
```

Expected:

- `audit_cleanup_wave2_spec.lua` prints `audit cleanup wave2 source contract passed`.
- `release_stabilization_spec.lua` reports targeted stabilization tests passed.
- All listed specs exit `0`.
- `repo-quality-check --check all` exits `0`.
- `git status --short` has no output.

- [ ] **Step 4: Request final code review**

Use a read-only reviewer over the full Wave 2 range:

```powershell
git log --oneline --max-count 10
git diff --stat <wave2-base-sha>..HEAD
git diff <wave2-base-sha>..HEAD
```

Review requirements:

- Behavior-preserving cleanup only.
- No SavedVariables shape change.
- No vendored library edits.
- No XML script handlers.
- No new public service API unless already approved by the parent.
- Generated docs changes are limited to inventory/catalog drift.
- Tests/checks listed in Step 3 pass.

- [ ] **Step 5: Stop before merge**

Do not merge, push, or discard from the implementation subagent. The parent agent must decide the
completion option after final review.

## Final Response Requirements

When execution completes, report:

- Chosen classification.
- Mini plan followed.
- Whether `code-mapper` was used.
- Whether `spark_implementer` was used.
- Files changed.
- Commits created.
- Tests/checks run with exit status.
- Remaining risk: in-client smoke test on WoW 3.3.5a for slash help, Logger popup behavior, and
  performance logging paths.
