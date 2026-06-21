# Audit Cleanup Wave 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Continue audit cleanup after Wave 2 with narrow P2 consolidation only, preserving
runtime behavior, SavedVariables shape, UI contracts, and WotLK 3.3.5a/Lua 5.1 compatibility.

**Architecture:** Wave 3 does not start large DB, sync, raid-runtime, Logger, or Master
extractions. It adds one small Master assignment helper with explicit load order, optionally
centralizes loot-source mode signature ownership in an already-loaded helper module, and maps
`getRaidQueries` without changing it unless a separate approved follow-up plan is created.

**Tech Stack:** World of Warcraft 3.3.5a, Interface 30300, Lua 5.1, KRT project workflow,
PowerShell repo tooling, Lua source-contract specs.

---

## Classification

Use the project `55to53` workflow.

- Classification: `complex-orchestrated`
- Reason: more than one file is likely to change, TOC/module-registry contracts are involved,
  and loot-source key generation touches shared runtime behavior.
- Execution model: parent plans and reviews; `spark_implementer` applies each approved patch.
- Mapping: use `code-mapper` before Task 3 if load order or isolated harness behavior is unclear;
  use `code-mapper` before any Task 4 decision that would modify `getRaidQueries`.

## Branching

Wave 3 should start from a clean Wave 2 result.

```powershell
git checkout codex/audit-cleanup-wave-2-current
git status --short
git checkout -b codex/audit-cleanup-wave-3-current
```

If Wave 2 has already been merged into another integration branch, start from that branch instead:

```powershell
git checkout <integration-branch>
git pull
git checkout -b codex/audit-cleanup-wave-3-current
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

## Scope

Modify only if the related task is executed:

- `tests/audit_cleanup_wave3_spec.lua`
- `!KRT/!KRT.toc`
- `!KRT/Services/Master/AssignmentHelpers.lua`
- `!KRT/Services/Master/AssignmentCandidates.lua`
- `!KRT/Services/Master/AssignmentTargets.lua`
- `!KRT/Services/Master/Service.lua`
- `tests/master_assignment_service_spec.lua`
- `tests/master_service_split_spec.lua`
- `tests/module_registry_services_spec.lua`
- `tests/release_stabilization_spec.lua`
- `!KRT/Modules/LootSourceCandidates.lua`
- `!KRT/Modules/LootSources.lua`
- `!KRT/Modules/Dataset/LootSourcesData.lua`
- `tests/module_registry_modules_spec.lua`
- `tests/module_registry_database_spec.lua`
- `tests/module_registry_ui_entrypoints_spec.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

Generated docs may change after hooks or explicit catalog refresh:

- `docs/FN_CLUSTERS.md`
- `docs/FUNCTION_REGISTRY.csv`
- `docs/API_NOMENCLATURE_CENSUS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_PUBLIC.csv`
- `docs/API_REGISTRY_INTERNAL.csv`
- `docs/TREE.md`

Do not modify in Wave 3:

- `!KRT/Libs/*`
- `!KRT/Database/DBSyncer.lua`
- `!KRT/Database/DBRaidMigrations.lua`
- `!KRT/Database/DBRaidStore.lua`
- `!KRT/Services/Loot/Service.lua`
- `!KRT/Services/Raid/State.lua`
- `!KRT/Services/Master/Service.lua` facade wrappers
- `!KRT/Services/Rolls/Service.lua` facade wrappers
- `!KRT/UI/*.xml`

## Deferred Items

Keep these out of Wave 3:

- `DBSyncer.lua` request tracking extraction.
- DB attendance segment consolidation across store and migrations.
- Raid/loot runtime invalidation ownership changes.
- Large Logger attendance or row-render extraction.
- Large Master controller extraction.
- Mass removal of facade wrappers in Master, Rolls, or Logger services.

---

### Task 1: Add Wave 3 Source-Contract Harness

**Files:**

- Create: `tests/audit_cleanup_wave3_spec.lua`

- [ ] **Step 1: Create the initial failing source-contract test**

Create `tests/audit_cleanup_wave3_spec.lua` with this content:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function readOptional(path)
    local file = io.open(path, "r")
    if not file then
        return ""
    end
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

local toc = read("!KRT/!KRT.toc")
local assignmentHelpers = readOptional("!KRT/Services/Master/AssignmentHelpers.lua")
local assignmentCandidates = read("!KRT/Services/Master/AssignmentCandidates.lua")
local assignmentTargets = read("!KRT/Services/Master/AssignmentTargets.lua")

assertContains(
    toc,
    "Services\\Master\\AssignmentHelpers.lua",
    "TOC should load Master assignment helpers before assignment row modules"
)
assertContains(
    assignmentHelpers,
    "-- exports: addon.Services.Master.AssignmentHelpers",
    "AssignmentHelpers should document its Master helper export"
)
assertContains(
    assignmentHelpers,
    "function AssignmentHelpers.ResolveClass(classProvider, name)",
    "AssignmentHelpers should own class-provider resolution"
)
assertContains(
    assignmentCandidates,
    "local AssignmentHelpers = Master.AssignmentHelpers",
    "AssignmentCandidates should localize AssignmentHelpers"
)
assertContains(
    assignmentTargets,
    "local AssignmentHelpers = Master.AssignmentHelpers",
    "AssignmentTargets should localize AssignmentHelpers"
)
assertContains(
    assignmentCandidates,
    "AssignmentHelpers.ResolveClass(classProvider, name)",
    "AssignmentCandidates should use shared class resolution"
)
assertContains(
    assignmentTargets,
    "AssignmentHelpers.ResolveClass(classProvider, name)",
    "AssignmentTargets should use shared class resolution"
)
assertNotContains(
    assignmentCandidates,
    "local function getClass(classProvider, name)",
    "AssignmentCandidates should not keep the duplicated local class helper"
)
assertNotContains(
    assignmentTargets,
    "local function getClass(classProvider, name)",
    "AssignmentTargets should not keep the duplicated local class helper"
)

print("audit cleanup wave3 source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

```powershell
lua tests\audit_cleanup_wave3_spec.lua
```

Expected failure before Task 2:

```text
TOC should load Master assignment helpers before assignment row modules
```

- [ ] **Step 3: Commit the failing harness only if the branch policy allows red commits**

Default KRT practice is to avoid committing a failing test alone. If using strict TDD commits is
required for the run, commit the failing harness separately; otherwise leave it staged/unstaged and
include it in the Task 2 green commit.

---

### Task 2: Share Master Assignment Class Resolution

**Files:**

- Create: `!KRT/Services/Master/AssignmentHelpers.lua`
- Modify: `!KRT/!KRT.toc`
- Modify: `!KRT/Services/Master/AssignmentCandidates.lua`
- Modify: `!KRT/Services/Master/AssignmentTargets.lua`
- Modify: `!KRT/Services/Master/Service.lua`
- Modify: `tests/master_assignment_service_spec.lua`
- Modify: `tests/master_service_split_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `tests/audit_cleanup_wave3_spec.lua`

- [ ] **Step 1: Add the helper to the TOC before both consumers**

In `!KRT/!KRT.toc`, replace:

```text
Services\Master\RollRows.lua
Services\Master\AssignmentCandidates.lua
Services\Master\AssignmentTargets.lua
Services\Master\DebugRaidGrid.lua
```

with:

```text
Services\Master\RollRows.lua
Services\Master\AssignmentHelpers.lua
Services\Master\AssignmentCandidates.lua
Services\Master\AssignmentTargets.lua
Services\Master\DebugRaidGrid.lua
```

- [ ] **Step 2: Create the helper module**

Create `!KRT/Services/Master/AssignmentHelpers.lua`:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master.AssignmentHelpers
-- events: none
-- notes: pure Master assignment shared helpers
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local AssignmentHelpers = Master.AssignmentHelpers or {}
Master.AssignmentHelpers = AssignmentHelpers

local type = type

-- ----- Internal state ----- --

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

function AssignmentHelpers.ResolveClass(classProvider, name)
    if type(classProvider) == "function" then
        return classProvider(name)
    end
    return nil
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/AssignmentHelpers", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
        },
    })
    registry.SetLoaded("Services/Master/AssignmentHelpers")
end
```

- [ ] **Step 3: Update `AssignmentCandidates.lua`**

In `!KRT/Services/Master/AssignmentCandidates.lua`, after:

```lua
local AssignmentCandidates = Master.AssignmentCandidates or {}
Master.AssignmentCandidates = AssignmentCandidates
```

add:

```lua
local AssignmentHelpers = Master.AssignmentHelpers
```

Delete the duplicated helper:

```lua
local function getClass(classProvider, name)
    if type(classProvider) == "function" then
        return classProvider(name)
    end
    return nil
end
```

Replace:

```lua
class = getClass(classProvider, name),
```

with:

```lua
class = AssignmentHelpers.ResolveClass(classProvider, name),
```

Update the direct registry deps from:

```lua
deps = {
    "Init",
    "Modules/ModuleRegistry",
},
```

to:

```lua
deps = {
    "Init",
    "Modules/ModuleRegistry",
    "Services/Master/AssignmentHelpers",
},
```

- [ ] **Step 4: Update `AssignmentTargets.lua`**

In `!KRT/Services/Master/AssignmentTargets.lua`, after:

```lua
local AssignmentTargets = Master.AssignmentTargets or {}
Master.AssignmentTargets = AssignmentTargets
```

add:

```lua
local AssignmentHelpers = Master.AssignmentHelpers
```

Delete the duplicated helper:

```lua
local function getClass(classProvider, name)
    if type(classProvider) == "function" then
        return classProvider(name)
    end
    return nil
end
```

Replace:

```lua
class = getClass(classProvider, name),
```

with:

```lua
class = AssignmentHelpers.ResolveClass(classProvider, name),
```

Update the direct registry deps from:

```lua
deps = {
    "Init",
    "Modules/ModuleRegistry",
},
```

to:

```lua
deps = {
    "Init",
    "Modules/ModuleRegistry",
    "Services/Master/AssignmentHelpers",
},
```

- [ ] **Step 5: Update the focused assignment spec load order**

In `tests/master_assignment_service_spec.lua` and `tests/master_service_split_spec.lua`, replace:

```lua
loadAddonFile("!KRT/Services/Master/AssignmentCandidates.lua")
loadAddonFile("!KRT/Services/Master/AssignmentTargets.lua")
```

with:

```lua
loadAddonFile("!KRT/Services/Master/AssignmentHelpers.lua")
loadAddonFile("!KRT/Services/Master/AssignmentCandidates.lua")
loadAddonFile("!KRT/Services/Master/AssignmentTargets.lua")
```

In `tests/release_stabilization_spec.lua`, update the `loadMasterController(h)` helper by adding:

```lua
h:load("!KRT/Services/Master/AssignmentHelpers.lua")
```

immediately before:

```lua
h:load("!KRT/Services/Master/AssignmentCandidates.lua")
```

In `tests/master_assignment_service_spec.lua`, after:

```lua
local AssignmentCandidates = addon.Services.Master.AssignmentCandidates
local AssignmentTargets = addon.Services.Master.AssignmentTargets
```

add:

```lua
local AssignmentHelpers = addon.Services.Master.AssignmentHelpers
```

Before the first `BuildRows` assertion block, add:

```lua
assert(AssignmentHelpers.ResolveClass(function(name)
    return name == "Alice" and "MAGE" or nil
end, "Alice") == "MAGE", "expected shared assignment class resolver")
assert(AssignmentHelpers.ResolveClass(nil, "Alice") == nil, "expected nil class without provider")
```

- [ ] **Step 6: Update `tests/module_registry_services_spec.lua`**

In `!KRT/Services/Master/Service.lua`, insert:

```lua
"Services/Master/AssignmentHelpers",
```

immediately before:

```lua
"Services/Master/AssignmentCandidates",
```

in the direct registry deps for `Services/Master/Service`.

In `expectedMasterServices`, insert this entry immediately before
`Services/Master/AssignmentCandidates`:

```lua
{
    name = "Services/Master/AssignmentHelpers",
    path = "!KRT/Services/Master/AssignmentHelpers.lua",
    owner = "AssignmentHelpers",
    separator = ".",
    deps = { "Init", "Modules/ModuleRegistry" },
    registryFromFeature = true,
    events = "-- events: none",
    note = "-- notes: pure Master assignment shared helpers",
},
```

Change the `Services/Master/AssignmentCandidates` deps from:

```lua
deps = { "Init", "Modules/ModuleRegistry" },
```

to:

```lua
deps = { "Init", "Modules/ModuleRegistry", "Services/Master/AssignmentHelpers" },
```

Change the `Services/Master/AssignmentTargets` deps from:

```lua
deps = { "Init", "Modules/ModuleRegistry" },
```

to:

```lua
deps = { "Init", "Modules/ModuleRegistry", "Services/Master/AssignmentHelpers" },
```

In the Master service facade expected deps, insert:

```lua
"Services/Master/AssignmentHelpers",
```

immediately before:

```lua
"Services/Master/AssignmentCandidates",
```

In `moduleTocPaths`, insert:

```lua
["Services/Master/AssignmentHelpers"] = "Services\\Master\\AssignmentHelpers.lua",
```

immediately before:

```lua
["Services/Master/AssignmentCandidates"] = "Services\\Master\\AssignmentCandidates.lua",
```

- [ ] **Step 7: Run focused checks**

```powershell
lua tests\audit_cleanup_wave3_spec.lua
lua tests\master_assignment_service_spec.lua
lua tests\master_service_split_spec.lua
lua tests\master_model_services_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected:

- `audit_cleanup_wave3_spec.lua` prints `audit cleanup wave3 source contract passed`.
- Assignment and registry specs exit `0`.
- TOC, syntax, and uniformity checks exit `0`.

- [ ] **Step 8: Review and commit Task 2**

Run a spec-compliance review and code-quality review before committing.

```powershell
git status --short
git add -- tests\audit_cleanup_wave3_spec.lua `
    !KRT\!KRT.toc `
    !KRT\Services\Master\AssignmentHelpers.lua `
    !KRT\Services\Master\AssignmentCandidates.lua `
    !KRT\Services\Master\AssignmentTargets.lua `
    !KRT\Services\Master\Service.lua `
    tests\master_assignment_service_spec.lua `
    tests\master_service_split_spec.lua `
    tests\module_registry_services_spec.lua `
    tests\release_stabilization_spec.lua
git commit -m "refactor: share master assignment class helper"
```

If pre-commit reports generated catalog drift, inspect and stage only generated docs:

```powershell
git status --short
git add -- docs\FN_CLUSTERS.md docs\FUNCTION_REGISTRY.csv `
    docs\API_NOMENCLATURE_CENSUS.md docs\API_REGISTRY.csv `
    docs\API_REGISTRY_PUBLIC.csv docs\API_REGISTRY_INTERNAL.csv docs\TREE.md
git commit -m "refactor: share master assignment class helper"
```

---

### Task 3: Centralize Loot Source Mode Signature

**Files:**

- Modify: `tests/audit_cleanup_wave3_spec.lua`
- Modify: `!KRT/Modules/LootSourceCandidates.lua`
- Modify: `!KRT/Modules/LootSources.lua`
- Modify: `!KRT/Modules/Dataset/LootSourcesData.lua`
- Modify: `tests/module_registry_modules_spec.lua`
- Modify: `tests/module_registry_database_spec.lua`
- Modify: `tests/module_registry_services_spec.lua`
- Modify: `tests/module_registry_ui_entrypoints_spec.lua`

- [ ] **Step 1: Extend Wave 3 source-contract test**

Append this block before the final `print(...)` line in
`tests/audit_cleanup_wave3_spec.lua`:

```lua
local lootSourceCandidates = read("!KRT/Modules/LootSourceCandidates.lua")
local lootSources = read("!KRT/Modules/LootSources.lua")
local lootSourcesData = read("!KRT/Modules/Dataset/LootSourcesData.lua")

assertContains(
    lootSourceCandidates,
    "function LootSourceCandidates.GetModeSignature(modes)",
    "LootSourceCandidates should own loot-source mode signatures"
)
assertContains(
    lootSources,
    "local LootSourceCandidates = feature.LootSourceCandidates",
    "LootSources should localize LootSourceCandidates"
)
assertContains(
    lootSourcesData,
    "local LootSourceCandidates = feature.LootSourceCandidates",
    "LootSourcesData should localize LootSourceCandidates"
)
assertContains(
    lootSources,
    "LootSourceCandidates.GetModeSignature(candidate and candidate.modes)",
    "LootSources should use the shared mode signature helper"
)
assertContains(
    lootSourcesData,
    "LootSourceCandidates.GetModeSignature(source and source.modes)",
    "LootSourcesData should use the shared mode signature helper"
)
assertNotContains(
    lootSources,
    "local function getModeSignature(modes)",
    "LootSources should not keep the duplicated mode signature helper"
)
assertNotContains(
    lootSourcesData,
    "local function getModeSignature(modes)",
    "LootSourcesData should not keep the duplicated mode signature helper"
)
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

```powershell
lua tests\audit_cleanup_wave3_spec.lua
```

Expected failure before implementation:

```text
LootSourceCandidates should own loot-source mode signatures
```

- [ ] **Step 3: Add mode signature ownership to `LootSourceCandidates.lua`**

In `!KRT/Modules/LootSourceCandidates.lua`, change the local aliases from:

```lua
local type, tostring, tonumber = type, tostring, tonumber
```

to:

```lua
local type, tostring, tonumber = type, tostring, tonumber
local pairs = pairs
local tconcat = table.concat
```

After the shared source constants, add:

```lua
local MODE_KEY_ORDER = {
    "normal10",
    "normal20",
    "normal25",
    "normal40",
    "heroic10",
    "heroic25",
}
```

Under `-- ----- Public methods ----- --`, before `GetSharedLabel`, add:

```lua
function LootSourceCandidates.GetModeSignature(modes)
    if type(modes) ~= "table" then
        return "any"
    end

    local out = {}
    for i = 1, #MODE_KEY_ORDER do
        local mode = MODE_KEY_ORDER[i]
        if modes[mode] == true then
            out[#out + 1] = mode
        end
    end

    return (#out > 0) and tconcat(out, ",") or "any"
end
```

Do not use `pairs()` for the output order; the source key must stay deterministic.

- [ ] **Step 4: Update `LootSources.lua`**

In `!KRT/Modules/LootSources.lua`, after:

```lua
local Strings = feature.Strings
```

add:

```lua
local LootSourceCandidates = feature.LootSourceCandidates
```

Remove `local tconcat = table.concat` only if no remaining code uses it. If it remains needed,
leave it in place.

Delete the local `MODE_KEY_ORDER` table and the duplicated:

```lua
local function getModeSignature(modes)
    if type(modes) ~= "table" then
        return "any"
    end

    local out = {}
    for i = 1, #MODE_KEY_ORDER do
        local mode = MODE_KEY_ORDER[i]
        if modes[mode] == true then
            out[#out + 1] = mode
        end
    end

    return (#out > 0) and tconcat(out, ",") or "any"
end
```

In `buildCandidateSourceKey`, replace:

```lua
getModeSignature(candidate and candidate.modes)
```

with:

```lua
LootSourceCandidates.GetModeSignature(candidate and candidate.modes)
```

Update direct registry deps from:

```lua
local deps = { "Init", "Modules/Strings", "Modules/Dataset/LootSourcesData" }
```

to:

```lua
local deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/Dataset/LootSourcesData" }
```

- [ ] **Step 5: Update `LootSourcesData.lua`**

In `!KRT/Modules/Dataset/LootSourcesData.lua`, after:

```lua
local feature = addon.Database.GetFeatureShared()
```

add:

```lua
local LootSourceCandidates = feature.LootSourceCandidates
```

Remove:

```lua
local tconcat = table.concat
```

only if no remaining code uses it after the local helper removal.

Delete the local `MODE_KEY_ORDER` table and the duplicated:

```lua
local function getModeSignature(modes)
    if type(modes) ~= "table" then
        return "any"
    end

    local out = {}
    for i = 1, #MODE_KEY_ORDER do
        local mode = MODE_KEY_ORDER[i]
        if modes[mode] == true then
            out[#out + 1] = mode
        end
    end

    return (#out > 0) and tconcat(out, ",") or "any"
end
```

In `buildSourceKey`, replace:

```lua
getModeSignature(source and source.modes)
```

with:

```lua
LootSourceCandidates.GetModeSignature(source and source.modes)
```

Update the direct registry deps from:

```lua
local deps = { "Init" }
```

to:

```lua
local deps = { "Init", "Modules/LootSourceCandidates" }
```

If the file currently uses inline `registry.AddModule(name, { deps = deps })`, keep that pattern
and only change the `deps` value.

- [ ] **Step 6: Update registry specs without renaming historical module keys**

In `tests/module_registry_modules_spec.lua`, replace:

```lua
{
    name = "Modules/Dataset/LootSourcesData",
    path = "!KRT/Modules/Dataset/LootSourcesData.lua",
    deps = { "Init" },
    events = "-- events: none",
},
{
    name = "Modules/LootSources",
    path = "!KRT/Modules/LootSources.lua",
    deps = { "Init", "Modules/Strings", "Modules/Dataset/LootSourcesData" },
    events = "-- events: none",
},
```

with:

```lua
{
    name = "Modules/Dataset/LootSourcesData",
    path = "!KRT/Modules/Dataset/LootSourcesData.lua",
    deps = { "Init", "Modules/LootSourceCandidates" },
    events = "-- events: none",
},
{
    name = "Modules/LootSources",
    path = "!KRT/Modules/LootSources.lua",
    deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/Dataset/LootSourcesData" },
    events = "-- events: none",
},
```

In `tests/module_registry_services_spec.lua`, replace:

```lua
{ name = "Modules/Dataset/LootSourcesData", deps = { "Init" } },
{ name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/Dataset/LootSourcesData" } },
```

with:

```lua
{ name = "Modules/Dataset/LootSourcesData", deps = { "Init", "Modules/LootSourceCandidates" } },
{
    name = "Modules/LootSources",
    deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/Dataset/LootSourcesData" },
},
```

In `tests/module_registry_database_spec.lua`, preserve its existing historical names and replace:

```lua
{ name = "Modules/LootSourcesData", deps = { "Init" } },
{ name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/LootSourcesData" } },
```

with:

```lua
{ name = "Modules/LootSourcesData", deps = { "Init", "Modules/LootSourceCandidates" } },
{
    name = "Modules/LootSources",
    deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/LootSourcesData" },
},
```

In `tests/module_registry_ui_entrypoints_spec.lua`, preserve its existing historical names and
replace:

```lua
{ name = "Modules/LootSourcesData", deps = { "Init" } },
{ name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/LootSourcesData" } },
```

with:

```lua
{ name = "Modules/LootSourcesData", deps = { "Init", "Modules/LootSourceCandidates" } },
{
    name = "Modules/LootSources",
    deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/LootSourcesData" },
},
```

- [ ] **Step 7: Run focused checks**

```powershell
lua tests\audit_cleanup_wave3_spec.lua
lua tests\module_registry_modules_spec.lua
lua tests\module_registry_database_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\module_registry_ui_entrypoints_spec.lua
lua tests\release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected:

- Wave3 source-contract test passes.
- Module registry specs pass.
- `release_stabilization_spec.lua` still reports all targeted tests passing.
- TOC, syntax, and uniformity checks exit `0`.

- [ ] **Step 8: Review and commit Task 3**

Run a spec-compliance review and code-quality review before committing.

```powershell
git status --short
git add -- tests\audit_cleanup_wave3_spec.lua `
    !KRT\Modules\LootSourceCandidates.lua `
    !KRT\Modules\LootSources.lua `
    !KRT\Modules\Dataset\LootSourcesData.lua `
    tests\module_registry_modules_spec.lua `
    tests\module_registry_database_spec.lua `
    tests\module_registry_services_spec.lua `
    tests\module_registry_ui_entrypoints_spec.lua
git commit -m "refactor: share loot source mode signature"
```

If pre-commit reports generated catalog drift, inspect and stage only generated docs:

```powershell
git status --short
git add -- docs\FN_CLUSTERS.md docs\FUNCTION_REGISTRY.csv `
    docs\API_NOMENCLATURE_CENSUS.md docs\API_REGISTRY.csv `
    docs\API_REGISTRY_PUBLIC.csv docs\API_REGISTRY_INTERNAL.csv docs\TREE.md
git commit -m "refactor: share loot source mode signature"
```

---

### Task 4: Map `getRaidQueries` And Stop Before Runtime Refactor

**Files:**

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

This task deliberately does not change runtime code. `getRaidQueries` spans Database, Logger,
Loot, Raid, and DBSyncer ownership, and several wrappers cache the facade for isolated harnesses.
Wave 3 should record a current map and defer implementation to a dedicated Wave4 plan if the map
shows a safe slice.

- [ ] **Step 1: Generate the current call-site map**

Run:

```powershell
rg -n "local function getRaidQueries|GetRaidQueries\(" !KRT tests -g "*.lua"
```

Expected current runtime owners include:

```text
!KRT\Database\DBSyncer.lua
!KRT\Services\Logger\View.lua
!KRT\Services\Logger\Store.lua
!KRT\Services\Logger\Export.lua
!KRT\Services\Logger\Actions.lua
!KRT\Services\Loot\Service.lua
!KRT\Services\Raid\State.lua
!KRT\Services\Raid\LootRecords.lua
```

- [ ] **Step 2: Add a Wave 3 backlog note**

In `docs/TECH_CLEANUP_BACKLOG.md`, add or update a Wave 3 note under the cleanup backlog section:

```markdown
### Wave 3 follow-up: `getRaidQueries` wrappers

Current decision: do not refactor `getRaidQueries` wrappers in Wave 3.

Reason:
- The wrappers cross Database, Logger, Loot, Raid, and DBSyncer ownership.
- Some call sites memoize the facade to preserve isolated harness behavior.
- Direct replacement is likely safe only for a smaller slice such as Logger View/Export, but that
  should be planned separately after code-mapper confirms call flow and test coverage.

Required before implementation:
- Map whether each wrapper is dynamic lookup or memoized cache.
- Identify tests that load the file before `Database.GetRaidQueries` exists.
- Split any change into a dedicated Wave4 task with one owner group per commit.
```

If the file already has a more specific entry for `getRaidQueries`, update that entry instead of
adding a duplicate heading.

- [ ] **Step 3: Run documentation/source checks**

```powershell
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
git diff --check
```

Expected:

- Lua checks still exit `0`.
- `git diff --check` exits `0`.

- [ ] **Step 4: Review and commit Task 4**

```powershell
git status --short
git add -- docs\TECH_CLEANUP_BACKLOG.md
git commit -m "docs: record getRaidQueries wave 3 decision"
```

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
git commit -m "docs: refresh cleanup wave 3 catalogs"
```

- [ ] **Step 3: Run final targeted tests**

```powershell
lua tests\audit_cleanup_wave3_spec.lua
lua tests\master_assignment_service_spec.lua
lua tests\master_model_services_spec.lua
lua tests\module_registry_modules_spec.lua
lua tests\module_registry_database_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\module_registry_ui_entrypoints_spec.lua
lua tests\release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check all
git status --short
```

Expected:

- `audit_cleanup_wave3_spec.lua` prints `audit cleanup wave3 source contract passed`.
- All listed specs exit `0`.
- `release_stabilization_spec.lua` reports targeted stabilization tests passed.
- `repo-quality-check --check all` exits `0`.
- `git status --short` has no output.

- [ ] **Step 4: Request final code review**

Use a read-only reviewer over the full Wave 3 range:

```powershell
git log --oneline --max-count 10
git diff --stat <wave3-base-sha>..HEAD
git diff <wave3-base-sha>..HEAD
```

Review requirements:

- Behavior-preserving cleanup only.
- No SavedVariables shape change.
- No vendored library edits.
- No XML changes.
- Master assignment helper has explicit TOC and registry ownership.
- Loot source mode signatures remain deterministic and source keys are unchanged.
- `getRaidQueries` is documented only; no runtime wrappers changed in Wave 3.
- Generated docs changes are limited to inventory/catalog/tree drift.
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
- Remaining risk: in-client smoke test on WoW 3.3.5a for Master assignment UI, loot-source
  attribution/source keys, and normal addon load.
