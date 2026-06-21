# Wave S3 Reserves Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize the Reserves service facade to one local owner table without
changing the public `addon.Services.Reserves` contract.

**Architecture:** `!KRT/Services/Reserves.lua` already publishes one runtime
table, `addon.Services.Reserves`, but the file still uses both `module` and a
local `Service` alias for the same table. Wave S3 removes the local `Service`
alias, defines public methods on `module:*`, keeps `_Sync` package-internal, and
updates tests/catalogs so the source contract matches the canonical owner.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT service
facade, repo-local PowerShell/Python/Lua checks.

---

## Classification

- `55to53`: `complex-orchestrated`
- Reason: touches a shared service facade, source contracts, generated
  catalogs, and cleanup backlog docs.
- Execution mode: use `code-mapper` first if implementation context is not
  already fresh; use `spark_implementer` for the patch; parent reviews the diff.

## File Structure

- Modify: `!KRT/Services/Reserves.lua`
  - Keep `local module = Reserves` as the only local public owner.
  - Remove `local Service = module`.
  - Convert `function Service:*` definitions to `function module:*`.
  - Convert internal same-table calls from `Service:*` to `module:*`.
  - Keep `Sync` internal methods on `module._Sync`.
- Modify: `tests/module_registry_services_spec.lua`
  - Update the expected owner for `Services/Reserves` from `Service` to
    `module`.
- Create: `tests/audit_cleanup_wave_s3_reserves_spec.lua`
  - Add a source-contract guard for the owner normalization.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Mark Wave S3 complete and advance the next cleanup candidates.
- Generated: `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`,
  `docs/TREE.md`, and any API catalog files changed by the repo tooling.
  - Include only files changed by `py -3 tools/krt.py api-catalog-refresh`.

## Non-Goals

- Do not remove any public `addon.Services.Reserves:*` method.
- Do not change `KRT_Reserves` or `KRT_Options.Reserves` shape.
- Do not change import formats, alias policy, sync wire format, whisper policy,
  display/readiness shape, local-vs-synced precedence, or item-info refresh
  behavior.
- Do not move logic between `Reserves.lua` and `Services/Reserves/*`.
- Do not touch XML, widgets, controllers, slash entrypoints, or vendored libs.
- Do not add a changelog entry; this is internal cleanup only.

---

### Task 1: Add the Wave S3 Source-Contract Test

**Files:**
- Create: `tests/audit_cleanup_wave_s3_reserves_spec.lua`

- [ ] **Step 1: Create the failing source-contract test**

Create `tests/audit_cleanup_wave_s3_reserves_spec.lua` with this full content:

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

local reserves = read("!KRT/Services/Reserves.lua")
local moduleRegistry = read("tests/module_registry_services_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(reserves, "local module = Reserves")
assertNotContains(reserves, "local Service = module")
assertNotContains(reserves, "function Service:")
assertNotContains(reserves, "Service:")

local publicMethods = {
    "GetCounts",
    "Save",
    "Load",
    "ClearSavedReserves",
    "HasData",
    "IsLocalDataAvailable",
    "HasItemReserves",
    "GetNameAliases",
    "SetNameAlias",
    "RemoveNameAlias",
    "GetPlayerReserveEntries",
    "GetImportMode",
    "SetImportMode",
    "IsPlusSystem",
    "ParseImport",
    "ApplyImport",
    "RequestApplyImport",
    "QueryItemInfo",
    "QueryMissingItems",
    "GetReserveCountForItem",
    "GetPlusForItem",
    "HasCurrentRaidPlayersForItem",
    "GetItemReserveContext",
    "GetReadinessReport",
    "GetPlayersForItem",
    "FormatReservedPlayersLine",
    "GetDisplayList",
    "GetSyncMetadata",
    "GetSyncPayload",
    "SetSyncedData",
    "DeleteSyncedReservesCache",
    "IsSourceCollapsed",
    "ToggleSourceCollapsed",
    "RequestSyncMetadata",
    "HandleSyncMessage",
    "HasPendingItem",
}

for i = 1, #publicMethods do
    local methodName = publicMethods[i]
    assertContains(
        reserves,
        "function module:" .. methodName .. "(",
        "missing Reserves public method: " .. methodName
    )
end

assertContains(reserves, "function Sync:GetPayload()")
assertContains(reserves, "function Sync:SetSyncedData(sourceData, meta)")
assertContains(reserves, "function module:GetSyncPayload()")
assertContains(reserves, "function module:SetSyncedData(sourceData, meta)")

assertNotContains(reserves, "CreateFrame(")
assertNotContains(reserves, "GameTooltip")
assertNotContains(reserves, "addon.Widgets")
assertNotContains(reserves, "addon.Controllers")

assertContains(
    moduleRegistry,
    'name = "Services/Reserves",\n        path = "!KRT/Services/Reserves.lua",\n        owner = "module",'
)
assertContains(backlog, "Wave S3 completed: Reserves Service facade owner normalization")

print("audit cleanup wave s3 reserves source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails for the current source**

Run:

```powershell
lua tests\audit_cleanup_wave_s3_reserves_spec.lua
```

Expected:

```text
missing: Wave S3 completed: Reserves Service facade owner normalization
```

If the backlog assertion is reached first, the test is correctly failing. After
the backlog marker is added, the same test must also guard the removal of
`local Service = module`, `function Service:`, and `Service:` calls.

---

### Task 2: Update the Service Registry Source Contract

**Files:**
- Modify: `tests/module_registry_services_spec.lua`

- [ ] **Step 1: Change the expected Reserves owner**

In `tests/module_registry_services_spec.lua`, find the `expectedReservesServices`
entry for `Services/Reserves`:

```lua
    {
        name = "Services/Reserves",
        path = "!KRT/Services/Reserves.lua",
        owner = "Service",
        separator = ":",
```

Replace it with:

```lua
    {
        name = "Services/Reserves",
        path = "!KRT/Services/Reserves.lua",
        owner = "module",
        separator = ":",
```

- [ ] **Step 2: Run the registry test and verify it still fails before runtime
  source changes**

Run:

```powershell
lua tests\module_registry_services_spec.lua
```

Expected:

```text
Services/Reserves expected public API must appear before registry metadata
```

The exact Lua stack line may differ. The important point is that the registry
now expects `function module:*`, while `Reserves.lua` still defines
`function Service:*`.

---

### Task 3: Normalize the Reserves Facade Owner in Runtime Code

**Files:**
- Modify: `!KRT/Services/Reserves.lua`

- [ ] **Step 1: Remove the duplicate local owner alias**

At the top of `!KRT/Services/Reserves.lua`, replace:

```lua
    local Reserves = Services.Reserves
    local module = Reserves
    local Service = module
    module._Sync = module._Sync or {}
```

with:

```lua
    local Reserves = Services.Reserves
    local module = Reserves
    module._Sync = module._Sync or {}
```

- [ ] **Step 2: Convert public method definitions to the canonical owner**

In `!KRT/Services/Reserves.lua`, replace every public method definition that
starts with:

```lua
function Service:
```

with:

```lua
function module:
```

The resulting source must contain these public definitions:

```lua
function module:GetCounts(sourceData)
function module:Save(contextTag)
function module:Load()
function module:ClearSavedReserves()
function module:HasData()
function module:IsLocalDataAvailable()
function module:HasItemReserves(itemId)
function module:GetNameAliases()
function module:SetNameAlias(reserveName, raidName)
function module:RemoveNameAlias(reserveName)
function module:GetPlayerReserveEntries(playerName)
function module:GetImportMode()
function module:SetImportMode(mode, syncOptions)
function module:IsPlusSystem()
function module:ParseImport(text, mode, opts)
function module:ApplyImport(parsed, raidId, opts)
function module:RequestApplyImport(parsed, raidId, callback, opts)
function module:QueryItemInfo(itemId)
function module:QueryMissingItems(silent, primeFn)
function module:GetReserveCountForItem(itemId, playerName)
function module:GetPlusForItem(itemId, playerName)
function module:HasCurrentRaidPlayersForItem(itemId, raidNum)
function module:GetItemReserveContext(itemId, raidNum)
function module:GetReadinessReport(itemId, raidNum)
function module:GetPlayersForItem(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
function module:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers, raidNum)
function module:GetDisplayList()
function module:GetSyncMetadata()
function module:GetSyncPayload()
function module:SetSyncedData(sourceData, meta)
function module:DeleteSyncedReservesCache()
function module:IsSourceCollapsed(source)
function module:ToggleSourceCollapsed(source)
function module:RequestSyncMetadata()
function module:HandleSyncMessage(prefix, msg, channel, sender)
function module:HasPendingItem(itemId)
```

- [ ] **Step 3: Convert internal calls that used the alias**

Replace the remaining same-table calls:

```lua
Service:GetImportMode()
Service:GetPlusForItem(itemId, playerName)
Service:IsLocalDataAvailable()
```

with:

```lua
module:GetImportMode()
module:GetPlusForItem(itemId, playerName)
module:IsLocalDataAvailable()
```

The specific expected locations after editing are:

```lua
local mode = (parsed.mode == "plus" or parsed.mode == "multi") and parsed.mode or module:GetImportMode()
```

```lua
getPlusForItem = function(itemId, playerName)
    return module:GetPlusForItem(itemId, playerName)
end,
isPlusSystem = function()
    return module:GetImportMode() == "plus"
end,
isMultiReserve = function()
    return module:GetImportMode() == "multi"
end,
```

```lua
if module:IsLocalDataAvailable() then
    return false, "local_data_present"
end
```

- [ ] **Step 4: Verify the alias is gone**

Run:

```powershell
rg -n "\bService\b|Service:" "!KRT/Services/Reserves.lua"
```

Expected:

```text
```

An empty result means the local `Service` owner alias has been removed. Do not
remove `Services` dependency names; the command above matches the singular
word `Service`, not `Services`.

- [ ] **Step 5: Run focused source tests**

Run:

```powershell
lua tests\module_registry_services_spec.lua
lua tests\audit_cleanup_wave_s3_reserves_spec.lua
```

Expected:

```text
module registry services source contract passed
audit cleanup wave s3 reserves source contract passed
```

At this point `audit_cleanup_wave_s3_reserves_spec.lua` may still fail only on
the backlog completion marker. That marker is added in Task 4.

---

### Task 4: Update the Cleanup Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Mark Wave S3 complete**

In the `### Wave S3: Reserves Service` section, extend
`Current worktree progress` so it reads:

```markdown
Current worktree progress:
- reserve-index rebuild and change publication now share one helper path
- itemId-based entry scans now use one helper for item-data updates and multi-reserve checks
- `Services/Reserves.lua` now uses `module` as its only local public facade owner
- public `addon.Services.Reserves:*` method names and behavior are preserved
- `_Sync` remains package-internal behind the parent Reserves facade
- Wave S3 completed: Reserves Service facade owner normalization
```

- [ ] **Step 2: Advance the default next-step list**

Near the bottom, replace:

```markdown
If continuing the cleanup program immediately, start with:

1. `!KRT/Services/Reserves.lua` facade dedup (`Service:*` + `module:*`)
2. `!KRT/EntryPoints/SlashEvents.lua` boundary cleanup follow-up
3. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
```

with:

```markdown
If continuing the cleanup program immediately, start with:

1. `!KRT/EntryPoints/SlashEvents.lua` boundary cleanup follow-up
2. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
3. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
```

- [ ] **Step 3: Run the Wave S3 source-contract test**

Run:

```powershell
lua tests\audit_cleanup_wave_s3_reserves_spec.lua
```

Expected:

```text
audit cleanup wave s3 reserves source contract passed
```

---

### Task 5: Refresh Generated Catalogs and Run Gates

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
lua tests\audit_cleanup_wave_s3_reserves_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\release_stabilization_spec.lua
```

Expected:

```text
audit cleanup wave s3 reserves source contract passed
module registry services source contract passed
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
stylua --check !KRT\Services\Reserves.lua tests\audit_cleanup_wave_s3_reserves_spec.lua
git diff --check
git status --short
```

Expected:

```text
```

`git diff --check` must have no errors. `git status --short` must show only the
intended Wave S3 files and generated catalog files.

---

### Task 6: Parent Review, Commit, and Smoke Handoff

**Files:**
- Review all changed files.

- [ ] **Step 1: Inspect the final diff**

Run:

```powershell
git diff --stat
git diff -- !KRT/Services/Reserves.lua
git diff -- tests/module_registry_services_spec.lua
git diff -- tests/audit_cleanup_wave_s3_reserves_spec.lua
git diff -- docs/TECH_CLEANUP_BACKLOG.md
```

Expected:

```text
```

Review expectations:

- `Reserves.lua` no longer contains `local Service = module`.
- `Reserves.lua` no longer contains `function Service:`.
- Public method names are unchanged, only the local owner token changes.
- `_Sync` wire helpers remain package-internal.
- No import, alias, display, sync, whisper, or SavedVariables logic changes.

- [ ] **Step 2: Commit the Wave S3 patch**

Run:

```powershell
git add -- `
  "!KRT/Services/Reserves.lua" `
  "tests/module_registry_services_spec.lua" `
  "tests/audit_cleanup_wave_s3_reserves_spec.lua" `
  "docs/TECH_CLEANUP_BACKLOG.md" `
  "docs/FUNCTION_REGISTRY.csv" `
  "docs/FN_CLUSTERS.md" `
  "docs/TREE.md"

git commit -m "Normalize Reserves service facade owner"
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
```

`git status --short` must be empty.

## In-Client Smoke Checklist

Run this on WoW 3.3.5a after the commit:

- `/reload` with no Lua errors.
- `/krt` opens.
- Import reserves in multi mode from the import window.
- Import reserves in plus mode.
- Confirm display list rows and source collapse/expand still work.
- Query missing item info and confirm rows refresh when item data resolves.
- Add and remove a manual alias.
- `/reload` and confirm local reserves and aliases persist.
- If two clients are available, request reserve sync and confirm runtime synced
  reserves do not persist into `KRT_Reserves`.
- If whisper replies are enabled and authority is valid, whisper `!sr` and
  confirm the reply remains unchanged.

## Self-Review

- Spec coverage: the plan covers facade owner normalization, source contracts,
  backlog update, catalog refresh, repo gates, commit, and smoke handoff.
- Placeholder scan: no placeholder tasks are left; every edit step includes
  exact paths, concrete code, exact commands, and expected results.
- Type/name consistency: the public runtime contract remains
  `addon.Services.Reserves:*`; only the local source owner changes from
  `Service` to `module`.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-06-14-audit-cleanup-wave-s3-reserves-service.md`.

Two execution options:

1. Subagent-Driven (recommended) - dispatch a focused implementation subagent,
   then parent review and correction before commit.
2. Inline Execution - execute this plan in the current session with checkpoints.
