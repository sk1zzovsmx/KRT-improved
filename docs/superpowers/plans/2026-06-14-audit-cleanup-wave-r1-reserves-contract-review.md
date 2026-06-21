# Wave R1 Reserves Contract Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit the deeper `!KRT/Services/Reserves.lua` facade lane and contract
only package-internal public methods that are proven by call-site evidence.

**Architecture:** This is an audit-first cleanup wave, not a mechanical removal wave.
Start with a read-only ownership map. Preserve the parent `addon.Services.Reserves`
facade for alias, collapse, readiness, display, import, sync, cache, and UI contracts
unless a specific method is proven package-internal by current source and tests.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT module registry,
PowerShell repo tooling, Lua source-contract tests.

---

## Classification

`complex-orchestrated`.

Reasons:

- The target is a shared service facade consumed by UI, Slash, Master, Rolls,
  LootHints, Init addon-message routing, and tests.
- The backlog explicitly says to continue only for proven package-internal contracts.
- A wrong contraction can break import, readiness, sync, whisper, or soft-res roll
  behavior without an obvious syntax failure.
- The first implementation decision depends on mapping results.

Workflow:

1. Parent reads backlog and current source.
2. `code-mapper` maps every public `addon.Services.Reserves:*` method and call site.
3. Parent chooses one of two paths:
   - no proven candidate: close Wave R1 as a documented no-op audit;
   - proven candidate exists: stop and create a narrower micro-plan for that method.
4. Documentation/test-only closure may use `tooling_worker`.
5. Any runtime contraction must use `spark_implementer` and a parent-approved
   candidate-specific plan.
6. Parent reviews final diff before completion.

## File Structure

Read-only mapping inputs:

- Read: `docs/TECH_CLEANUP_BACKLOG.md`
- Read: `docs/ARCHITECTURE.md`
- Read: `docs/OVERVIEW.md`
- Read: `docs/LUA_ALIGNMENT_MATRIX.md`
- Read: `!KRT/Services/Reserves.lua`
- Read: `!KRT/Services/Reserves/Aliases.lua`
- Read: `!KRT/Services/Reserves/Display.lua`
- Read: `!KRT/Services/Reserves/Import.lua`
- Read: `!KRT/Services/Reserves/Sync.lua`
- Read: `!KRT/Services/Reserves/Chat.lua`
- Read: `!KRT/Widgets/ReservesUI.lua`
- Read: `!KRT/Widgets/LootHints.lua`
- Read: `!KRT/EntryPoints/SlashEvents.lua`
- Read: `!KRT/Controllers/Master.lua`
- Read: `!KRT/Services/Rolls/Service.lua`
- Read: `!KRT/Services/Rolls/Responses.lua`
- Read: `!KRT/Init.lua`
- Read: `tests/audit_cleanup_wave_s3_reserves_spec.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `tests/module_registry_services_spec.lua`

Expected files if the audit finds no safe runtime contraction:

- Create: `tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua`
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
- Modify: `docs/TREE.md`
- Create: `docs/superpowers/plans/2026-06-14-audit-cleanup-wave-r1-reserves-contract-review.md`

Runtime files must remain unchanged on the no-candidate path:

- Do not modify: `!KRT/Services/Reserves.lua`
- Do not modify: `!KRT/Services/Reserves/*.lua`
- Do not modify: `!KRT/Widgets/ReservesUI.lua`
- Do not modify: `!KRT/EntryPoints/SlashEvents.lua`
- Do not modify: `!KRT/Controllers/Master.lua`
- Do not modify: `!KRT/Services/Rolls/*.lua`
- Do not modify: `!KRT/Init.lua`
- Do not modify: `!KRT/!KRT.toc`
- Do not modify: SavedVariables schema or migrations
- Do not modify: XML files

If a package-internal candidate is proven, stop this plan and write a narrower
micro-plan before changing runtime code.

## Current Evidence

Backlog constraints:

- `docs/TECH_CLEANUP_BACKLOG.md` says deeper Reserves work should continue only
  for proven package-internal contracts.
- It also says alias, collapse, readiness, and display methods are currently real
  slash/UI/controller contracts.

Current known external facade consumers:

- `!KRT/EntryPoints/SlashEvents.lua`
  - `GetCounts`
  - `GetReadinessReport`
  - `SetNameAlias`
  - `RemoveNameAlias`
  - `GetNameAliases`
  - `RequestSyncMetadata`
  - `GetSyncMetadata`
  - `DeleteSyncedReservesCache`
- `!KRT/Widgets/ReservesUI.lua`
  - `HasData`
  - `ToggleSourceCollapsed`
  - `IsSourceCollapsed`
  - `GetDisplayList`
  - `QueryItemInfo`
  - `QueryMissingItems`
  - `ClearSavedReserves`
  - `GetImportMode`
  - `RequestApplyImport`
  - `ApplyImport`
  - `ParseImport`
  - `SetImportMode`
  - `HasPendingItem`
- `!KRT/Controllers/Master.lua`
  - `HasData`
  - `FormatReservedPlayersLine`
  - `HasCurrentRaidPlayersForItem`
- `!KRT/Widgets/LootHints.lua`
  - `GetPlayersForItem`
- `!KRT/Services/Rolls/Service.lua`
  - `GetReserveCountForItem`
  - `GetPlusForItem`
  - `GetItemReserveContext`
  - `GetImportMode`
  - `IsPlusSystem`
- `!KRT/Services/Rolls/Responses.lua`
  - `GetPlayersForItem`
- `!KRT/Init.lua`
  - `HandleSyncMessage`

Current documented facade contracts:

- `docs/ARCHITECTURE.md` says external call sites use the parent Reserves facade
  for sync operations and `_Sync` remains package-internal.
- `docs/OVERVIEW.md` says `addon.Services.Reserves` is the canonical public
  surface and callers should not rely on nested `.Service` aliases.
- `docs/LUA_ALIGNMENT_MATRIX.md` says public Reserves APIs include load/save,
  parse/apply import, alias APIs, item/player query APIs, display/readiness APIs,
  sync/cache APIs, and source collapse APIs.

Initial review implication:

- Do not remove alias, collapse, readiness, display, import, sync, cache, or
  roll-facing methods merely because their implementation delegates to
  `_Aliases`, `_Display`, `_Import`, or `_Sync`.
- A method is a candidate only if current production call-site mapping proves it
  is not consumed outside the Reserves package and does not need to remain as a
  documented public compatibility facade.

## Task 0: Mapping Gate

**Files:**

- Read all files listed in "File Structure".

- [ ] **Step 1: Dispatch `code-mapper` read-only**

Use this exact prompt:

```text
Map the current `addon.Services.Reserves` public facade in
`!KRT/Services/Reserves.lua`.

Return a table with these columns:
- method name
- definition line
- production call sites outside `!KRT/Services/Reserves*`
- test-only call sites
- documentation that marks the method public or package-internal
- verdict: keep public, package-internal candidate, or unclear

Scope:
- Include every `function module:<Name>(...)` in `!KRT/Services/Reserves.lua`.
- Include `Sync:GetPayload` and `Sync:SetSyncedData` because the parent facade
  wraps them.
- Treat alias, collapse, readiness, display, import, sync, cache, and roll-facing
  behavior as public unless evidence proves otherwise.
- Treat `_Import`, `_Aliases`, `_Display`, `_Sync`, and `_Chat` as package-internal
  helper surfaces.
- Check `docs/TECH_CLEANUP_BACKLOG.md`, `docs/ARCHITECTURE.md`,
  `docs/OVERVIEW.md`, and `docs/LUA_ALIGNMENT_MATRIX.md`.

Stop conditions:
- If no package-internal candidate is proven, say `NO_RUNTIME_CANDIDATE`.
- If a candidate is proven, identify only that method and its exact replacement
  strategy. Do not propose broad refactors.
```

- [ ] **Step 2: Parent reviews mapper verdicts**

Accept a candidate only if all points are true:

- no production call site outside `!KRT/Services/Reserves*` uses it;
- docs do not describe it as a public parent-facade contract;
- tests using it are harness-only or can move to an internal surface without
  weakening behavior coverage;
- the replacement does not change SavedVariables, import formats, sync wire
  format, reserve matching, readiness output, display ordering, or whisper policy.

- [ ] **Step 3: Stop if the mapper returns `NO_RUNTIME_CANDIDATE`**

On this path, skip all runtime-edit tasks. Continue only with the no-candidate
audit contract, backlog update, tree update, and verification.

- [ ] **Step 4: Stop if the mapper returns a runtime candidate**

On this path, do not edit runtime code in Wave R1. Create a narrower follow-up
plan named after the exact method, such as:

```text
docs/superpowers/plans/2026-06-14-audit-cleanup-wave-r1a-reserves-<method>-contract.md
```

That follow-up plan must include the exact method, exact call-site migration,
candidate-specific RED test, minimal runtime patch, generated docs, and smoke
path. Do not continue with this generic review plan for runtime edits.

## Task 1: Add No-Candidate Audit Source Contract

**Files:**

- Create: `tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua`

- [ ] **Step 1: Create the source contract test**

Create this file:

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
local architecture = read("docs/ARCHITECTURE.md")
local overview = read("docs/OVERVIEW.md")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local slash = read("!KRT/EntryPoints/SlashEvents.lua")
local init = read("!KRT/Init.lua")
local master = read("!KRT/Controllers/Master.lua")
local reservesUi = read("!KRT/Widgets/ReservesUI.lua")
local lootHints = read("!KRT/Widgets/LootHints.lua")
local rollsService = read("!KRT/Services/Rolls/Service.lua")
local rollsResponses = read("!KRT/Services/Rolls/Responses.lua")

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
        "missing documented Reserves facade method: " .. methodName
    )
end

assertContains(reserves, "function Sync:GetPayload()")
assertContains(reserves, "function Sync:SetSyncedData(sourceData, meta)")
assertContains(reserves, "function module:GetSyncPayload()")
assertContains(reserves, "function module:SetSyncedData(sourceData, meta)")

assertContains(
    backlog,
    "deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts"
)
assertContains(
    backlog,
    "alias, collapse, readiness, and display methods are currently real slash/UI/controller contracts"
)
assertContains(overview, "For reserves, use `addon.Services.Reserves` as the canonical public surface.")
assertContains(architecture, "External call sites use the parent facade for sync operations")
assertContains(architecture, "`HandleSyncMessage`, `GetSyncPayload`, `SetSyncedData`, and cache APIs")

assertContains(slash, "reserves:GetCounts()")
assertContains(slash, "reserves:GetReadinessReport(itemId)")
assertContains(slash, "reserves:SetNameAlias(reserveName, raidName)")
assertContains(slash, "reserves:RemoveNameAlias(reserveName)")
assertContains(slash, "reserves:GetNameAliases()")
assertContains(slash, "reserves:RequestSyncMetadata()")
assertContains(slash, "reserves:GetSyncMetadata()")
assertContains(slash, "reserves:DeleteSyncedReservesCache()")

assertContains(init, "reservesService:HandleSyncMessage(prefix, msg, channel, sender)")

assertContains(master, "reserves:HasData()")
assertContains(master, "reserves:FormatReservedPlayersLine(")
assertContains(master, "reserves:HasCurrentRaidPlayersForItem(itemId)")

assertContains(reservesUi, "Reserves:ToggleSourceCollapsed(source)")
assertContains(reservesUi, "Reserves:IsSourceCollapsed(source)")
assertContains(reservesUi, "Reserves:GetDisplayList()")
assertContains(reservesUi, "Reserves:QueryItemInfo(itemId)")
assertContains(reservesUi, "Reserves:QueryMissingItems(silent")
assertContains(reservesUi, "Reserves:ClearSavedReserves()")
assertContains(reservesUi, "Reserves:GetImportMode()")
assertContains(reservesUi, "Reserves:RequestApplyImport(parsed")
assertContains(reservesUi, "Reserves:ApplyImport(parsed")
assertContains(reservesUi, "Reserves:ParseImport(")
assertContains(reservesUi, "Reserves:SetImportMode(mode, true)")
assertContains(reservesUi, "Reserves:HasPendingItem(itemId)")

assertContains(lootHints, "reserves:GetPlayersForItem(itemId")

assertContains(rollsService, "reserves:GetReserveCountForItem(itemId, name)")
assertContains(rollsService, "reserves:GetPlusForItem(itemId, name)")
assertContains(rollsService, "reserves:GetItemReserveContext(itemId)")
assertContains(rollsService, "reserves:IsPlusSystem()")
assertContains(rollsResponses, "reserves:GetPlayersForItem(itemId")

assertNotContains(slash, "._Sync")
assertNotContains(init, "._Sync")
assertNotContains(master, "._Display")
assertNotContains(reservesUi, "._Display")
assertNotContains(lootHints, "._Display")
assertNotContains(rollsService, "._Display")
assertNotContains(rollsResponses, "._Display")

print("audit cleanup wave R1 Reserves contract review source contract passed")
```

- [ ] **Step 2: Run the contract test**

Run:

```powershell
lua tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua
```

Expected output:

```text
audit cleanup wave R1 Reserves contract review source contract passed
```

This test is a no-candidate audit guard. It is allowed to pass before runtime
edits because Wave R1 starts from evidence preservation, not a predetermined
runtime deletion.

## Task 2A: No-Candidate Backlog Closure

Use this task only if `code-mapper` returns `NO_RUNTIME_CANDIDATE`.

**Files:**

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Add Wave R1 completion note after Wave S3**

Add this section after the Wave S3 section:

```markdown
### Wave R1: Reserves Contract Review

Wave R1 completed the deeper Reserves facade review:
- alias, collapse, readiness, display, import, sync, cache, and roll-facing
  methods remain parent-facade contracts with current production call sites or
  documented public compatibility.
- no package-internal-only public Reserves method was proven safe to contract
  in this pass.
- future Reserves contraction requires a fresh owner-specific micro-plan backed
  by a new call-site inventory.

Remaining Reserves contract review:
- None without new inventory evidence.
```

- [ ] **Step 2: Update Default Next Step**

Replace:

```markdown
1. deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts
2. bootstrap follow-up in `!KRT/Init.lua` only if a later inventory proves a residual owner
```

with:

```markdown
1. bootstrap follow-up in `!KRT/Init.lua` only if a later inventory proves a residual owner
2. hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method
```

- [ ] **Step 3: Keep runtime files unchanged**

Run:

```powershell
git diff --name-only -- "!KRT/*.lua" "!KRT/**/*.lua"
```

Expected output:

```text

```

No runtime Lua file should appear on the no-candidate path.

## Task 2B: Proven Candidate Stop Gate

Use this task only if `code-mapper` proves a package-internal candidate.

**Files:**

- No edits in this generic plan.

- [ ] **Step 1: Record candidate summary in the parent response**

Use this format:

```text
Candidate: addon.Services.Reserves:<MethodName>
Definition: !KRT/Services/Reserves.lua:<line>
External production call sites: none
Test-only call sites: <list>
Replacement surface: addon.Services.Reserves._<Owner>:<MethodName> or local helper
Risk class: <import|display|sync|alias|cache|lifecycle>
Required follow-up plan: wave-r1a-reserves-<method>-contract
```

- [ ] **Step 2: Stop before runtime edits**

Do not change `!KRT/Services/Reserves.lua` in Wave R1. The parent must write a
candidate-specific micro-plan before implementation.

## Task 3: Tree and Generated Docs

**Files:**

- Modify: `docs/TREE.md`

- [ ] **Step 1: Refresh tree docs**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

Expected output:

```text
Updated docs/TREE.md
```

- [ ] **Step 2: Do not regenerate function/API catalogs on the no-candidate path**

No runtime addon Lua changes are expected on the no-candidate path, and tests are
not part of `tools/fnmap-inventory.ps1` scan roots. Do not keep unrelated
catalog churn.

If a later candidate-specific micro-plan changes runtime Lua, that micro-plan
must regenerate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

## Task 4: Verification

**Files:**

- No edits.

- [ ] **Step 1: Run targeted source contracts**

Run:

```powershell
lua tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua
lua tests/audit_cleanup_wave_s3_reserves_spec.lua
lua tests/module_registry_services_spec.lua
```

Expected output includes:

```text
audit cleanup wave R1 Reserves contract review source contract passed
audit cleanup wave s3 reserves source contract passed
module registry services source contract passed
```

- [ ] **Step 2: Run reserve behavior coverage**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected output:

```text
targeted stabilization test(s) passed
```

- [ ] **Step 3: Run repo gates**

Run:

```powershell
git diff --check
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected output includes:

```text
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
Lua syntax check passed.
```

`git diff --check` must exit `0`. Generated CSV CRLF warnings are acceptable only
when no whitespace error is reported.

## Task 5: Parent Review

**Files:**

- Review every changed file.

- [ ] **Step 1: Confirm no-candidate path scope**

If `NO_RUNTIME_CANDIDATE` was returned, verify:

- no runtime Lua file under `!KRT` changed;
- no SavedVariables, TOC, XML, import format, sync wire format, readiness output,
  display output, whisper policy, or reserve matching rule changed;
- `docs/TECH_CLEANUP_BACKLOG.md` records Wave R1 as a completed audit;
- `docs/TREE.md` lists the new plan and audit spec;
- the new source contract preserves the current parent-facade public contract.

- [ ] **Step 2: Confirm proven-candidate path was not implemented here**

If a candidate was found, verify:

- no runtime edits were made in Wave R1;
- a follow-up micro-plan was created or requested;
- the parent response names the exact candidate and risk class.

- [ ] **Step 3: Decide commit gate**

If the no-candidate path changed only docs/tests, commit after local checks pass:

```powershell
git add docs/TECH_CLEANUP_BACKLOG.md docs/TREE.md `
  docs/superpowers/plans/2026-06-14-audit-cleanup-wave-r1-reserves-contract-review.md `
  tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua
git commit -m "Document Reserves contract review"
```

If any runtime Lua file changed in a follow-up micro-plan, require an in-client
WoW 3.3.5a smoke test before commit.

## Manual Smoke

No in-client smoke is required for the no-candidate path because runtime addon
Lua is unchanged.

If a follow-up runtime micro-plan is created later, smoke these paths:

- `/krt reserves` opens the Reserves UI.
- Import multi and plus reserves.
- `/krt res check` prints readiness.
- `/krt res alias`, `/krt res unalias`, and `/krt res aliases` work.
- Query missing items from the Reserves UI.
- Loot soft-res hints still render.
- Roll SR and plus flows still use reserve counts.
- Reserves sync metadata/data request still handles addon messages.
- Whisper SoftRes replies remain gated by config, reserve data, and authority.

## Self-Review

- Spec coverage: the plan addresses the default next step exactly: deeper
  `!KRT/Services/Reserves.lua` review only for proven package-internal contracts.
- Red-flag scan: no vague implementation task remains; runtime edits stop
  until a specific candidate is proven.
- Type consistency: all method names match current `function module:<Name>(...)`
  signatures in `!KRT/Services/Reserves.lua`.
