# Audit Cleanup Wave S2 Rolls Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the Rolls service facade by moving current-roll item resolution to the
Sessions helper owner and making roll intake/finalization/tie-reroll lifecycle helpers explicit,
without changing roll behavior or the public `addon.Services.Rolls` contract.

**Architecture:** `Services/Rolls/Service.lua` remains the public facade. `Sessions.lua` owns
session and current-roll context helpers; `Responses.lua`, `Resolution.lua`, and `Display.lua`
keep response-state, resolver, and display-model policy. This wave contracts private facade
glue only; public methods such as `GetDisplayModel()`, `SetPlayerResponse()`, and
`FinalizeRollSession()` stay intact.

**Tech Stack:** World of Warcraft 3.3.5a, Interface 30300, Lua 5.1, KRT 55to53 workflow,
PowerShell repo tooling, Lua source-contract specs.

---

## Classification

Use the project `55to53` workflow.

- Classification: `complex-orchestrated`
- Reason: the target is a behavior-sensitive public service facade consumed by Master, Loot,
  Debug, and tests; the change touches more than one file and has roll-resolution regression risk.
- Execution model: parent plans and reviews; `code-mapper` maps current contracts first;
  `spark_implementer` applies only the approved patch.
- Scope control: private helper ownership cleanup only. Do not remove public Rolls methods in
  this wave unless the mapper proves a method has no runtime or test consumers and the parent
  explicitly revises this plan.

## Branching

Start from the clean committed Wave 5 result.

```powershell
git checkout codex/audit-cleanup-wave-5-current
git status --short
git checkout -b codex/audit-cleanup-wave-s2-rolls-service
```

Expected:

- `git status --short` has no output.
- The new branch is `codex/audit-cleanup-wave-s2-rolls-service`.

If Wave 5 has already been merged into another integration branch before execution, stop and
update this Branching section with the exact base branch before editing.

Before editing:

```powershell
git status --short
lua tests\release_stabilization_spec.lua
```

Expected:

- `git status --short` has no output.
- `release_stabilization_spec.lua` exits `0`.

## Scope

Modify only:

- `tests/audit_cleanup_wave_s2_rolls_spec.lua`
- `!KRT/Services/Rolls/Sessions.lua`
- `!KRT/Services/Rolls/Service.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

Generated docs may change after catalog refresh or pre-commit hooks:

- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/API_NOMENCLATURE_CENSUS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_PUBLIC.csv`
- `docs/API_REGISTRY_INTERNAL.csv`
- `docs/TREE.md`

Do not modify in Wave S2:

- `!KRT/Libs/*`
- `!KRT/!KRT.toc`
- `!KRT/UI/*.xml`
- `!KRT/Controllers/Master.lua`
- `!KRT/Services/Rolls/Countdown.lua`
- `!KRT/Services/Rolls/History.lua`
- `!KRT/Services/Rolls/Responses.lua`
- `!KRT/Services/Rolls/Strategies.lua`
- `!KRT/Services/Rolls/Resolution.lua`
- `!KRT/Services/Rolls/Display.lua`
- `!KRT/Services/Loot/*`
- `!KRT/Services/Raid/*`
- `!KRT/CHANGELOG.md`, unless implementation changes user-visible behavior

## Non-Goals

- No winner policy changes.
- No response lifecycle changes.
- No `PASS`, `CANCELLED`, `TIMED_OUT`, or `INELIGIBLE` transition changes.
- No change to late-roll behavior with `countdownRollsBlock=false`.
- No changes to `Rolls:GetDisplayModel().resolution`.
- No SavedVariables shape changes.
- No controller/UI/XML changes.
- No broad rename of all Rolls local wrapper helpers.

---

### Task 1: Map Rolls Facade Ownership

**Files:** read-only

- `!KRT/Services/Rolls/Service.lua`
- `!KRT/Services/Rolls/Sessions.lua`
- `!KRT/Services/Rolls/History.lua`
- `!KRT/Services/Rolls/Responses.lua`
- `!KRT/Services/Rolls/Resolution.lua`
- `!KRT/Services/Rolls/Display.lua`
- `!KRT/Controllers/Master.lua`
- `!KRT/Services/Debug.lua`
- `!KRT/Services/Loot/Service.lua`
- `tests/release_stabilization_spec.lua`
- `tests/module_registry_services_spec.lua`
- `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Run the read-only mapper**

Use `code-mapper` with this prompt:

```text
Map Wave S2 Rolls Service cleanup. Do not edit files.

Read only the files listed in the Wave S2 plan. Report:
1. every public addon.Services.Rolls method in Services/Rolls/Service.lua;
2. runtime call sites for those public methods in Master, Loot, Debug, and tests;
3. the current local helper wrappers around Sessions, History, Responses, Display, and Countdown;
4. whether getCurrentRollItemID belongs more cleanly in Sessions as current-roll context logic;
5. the exact behavior-sensitive tests covering PASS, CANCELLED, TIMED_OUT, OOT, tie reroll,
   duplicate rolls, display-model resolution, and award-time winner validation;
6. whether any public Rolls method can be removed safely in this wave.

Do not propose policy changes. Keep recommendations limited to helper ownership and facade cleanup.
```

Expected mapper result:

- Public `Rolls:*` methods are real public contracts and should stay in this wave.
- `getCurrentRollItemID` is current-roll context logic and can move into `Sessions`.
- `SetRollRecordingEnabled`, `BeginTieReroll`, and `FinalizeRollSession` can become thinner by
  using private lifecycle helpers inside `Service.lua`.
- `Responses`, `Resolution`, and `Display` policy should remain unchanged.

- [ ] **Step 2: Parent gate**

Parent checks the mapper result. If the mapper recommends changing resolver ordering, response
transition rules, Master controller code, or display-model shape, stop and revise the plan.

---

### Task 2: Add Wave S2 Source-Contract Harness

**Files:**

- Create: `tests/audit_cleanup_wave_s2_rolls_spec.lua`

- [ ] **Step 1: Create the initial failing source-contract test**

Create `tests/audit_cleanup_wave_s2_rolls_spec.lua` with this content:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing: " .. needle), 0)
    end
end

local function assertNotContains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected: " .. needle), 0)
    end
end

local service = read("!KRT/Services/Rolls/Service.lua")
local sessions = read("!KRT/Services/Rolls/Sessions.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

local publicMethods = {
    "Roll",
    "GetRollStatus",
    "SetRollRecordingEnabled",
    "CHAT_MSG_SYSTEM",
    "SubmitDebugRoll",
    "GetCandidateEligibility",
    "SetManualExclusion",
    "SetPlayerResponse",
    "GetRolls",
    "GetHighestRoll",
    "ClearRolls",
    "BeginTieReroll",
    "ValidateWinner",
    "GetDisplayModel",
    "GetRollSession",
    "SetExpectedWinners",
    "EnsureRollSession",
    "EnsureLootRollSession",
    "SyncSessionState",
    "GetResolvedWinner",
    "ShouldUseTieReroll",
    "StopCountdown",
    "StartCountdown",
    "IsCountdownRunning",
    "FinalizeRollSession",
}

for i = 1, #publicMethods do
    local methodName = publicMethods[i]
    assertContains(service, "function module:" .. methodName .. "(", "missing Rolls public method: " .. methodName)
end

assertContains(sessions, "function Sessions.GetCurrentRollItemId(ctx, onResolved)")
assertContains(service, "Sessions.GetCurrentRollItemId(getSessionsContext(), logCurrentRollItemId)")
assertNotContains(service, "local sessionItemId = session and tonumber(session.itemId) or nil")
assertNotContains(service, "Item.GetItemStringFromLink(itemLink) or itemLink")
assertContains(service, "local function beginRollIntake()")
assertContains(service, "local function finishRollIntake()")
assertContains(service, "local function resetForTieReroll(session, reroll, itemId, itemLink, currentRollType)")
assertContains(service, "local function finalizeRollSession()")
assertContains(service, "`resolution` table is a stable part of this API")
assertContains(backlog, "Wave S2 completed: Rolls Service facade helper cleanup")
assertNotContains(service, "addon.Services.Rolls", "Rolls service must keep Services.Rolls localization")
assertNotContains(service, "addon.Rolls", "Rolls service must not reintroduce root Rolls aliases")

print("audit cleanup wave s2 rolls source contract passed")
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

```powershell
lua tests\audit_cleanup_wave_s2_rolls_spec.lua
```

Expected failure before Task 3:

```text
missing: function Sessions.GetCurrentRollItemId(ctx, onResolved)
```

---

### Task 3: Move Current Item Resolution To Sessions

**Files:**

- Modify: `!KRT/Services/Rolls/Sessions.lua`
- Modify: `!KRT/Services/Rolls/Service.lua`

- [ ] **Step 1: Add the Sessions-owned current item helper**

In `!KRT/Services/Rolls/Sessions.lua`, add this public internal helper after the existing
`local function getRollSessionItemKey(itemLink)` helper:

```lua
function Sessions.GetCurrentRollItemId(ctx, onResolved)
    local session = Sessions.GetRollSession(ctx)
    local sessionItemId = session and tonumber(session.itemId) or nil

    if sessionItemId and sessionItemId > 0 then
        if onResolved then
            onResolved(sessionItemId)
        end
        return sessionItemId
    end

    local index = ctx.getItemIndex and ctx.getItemIndex() or nil
    local item = ctx.getItem and ctx.getItem(index) or nil
    local itemLink = item and item.itemLink
    if not itemLink then
        return nil
    end

    local itemId = Item.GetItemIdFromLink(itemLink)
    if itemId and session then
        session.itemId = itemId
        session.itemLink = itemLink
        session.itemKey = getRollSessionItemKey(itemLink) or itemLink
    end

    if onResolved then
        onResolved(itemId)
    end
    return itemId
end
```

- [ ] **Step 2: Replace the Service-local resolver body**

In `!KRT/Services/Rolls/Service.lua`, replace the current long `getCurrentRollItemID = function()`
body with this shorter wrapper. Keep assignment to the existing forward-declared local; do not use
`local function getCurrentRollItemID()` here because `getSessionsContext()` already captures the
forward declaration.

```lua
local function logCurrentRollItemId(itemId)
    if IsDebugEnabled() then
        addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(itemId)))
    end
end

getCurrentRollItemID = function()
    return Sessions.GetCurrentRollItemId(getSessionsContext(), logCurrentRollItemId)
end
```

Do not change the `getSessionsContext()` callback shape:

```lua
getCurrentRollItemID = function()
    return getCurrentRollItemID()
end,
```

- [ ] **Step 3: Run the source-contract test**

```powershell
lua tests\audit_cleanup_wave_s2_rolls_spec.lua
```

Expected: still fails because lifecycle helpers and backlog update are not implemented yet.

---

### Task 4: Make Roll Intake Lifecycle Helpers Explicit

**Files:**

- Modify: `!KRT/Services/Rolls/Service.lua`

- [ ] **Step 1: Add lifecycle helpers before public methods**

Add this block after `resetRolls()` and before `-- ----- Public methods ----- --`:

```lua
local function beginRollIntake()
    state.canRoll = true
    state.record = true
    lootState.rollStarted = true
    ensureAdHocRollSession()
    ensureResponseSession()
    state.warned = false
    state.countdownExpired = false

    if state.count == 0 then
        lootState.winner = nil
        lootState.rollWinner = nil
    end

    updateSessionRollWindow(true)
end

local function finishRollIntake()
    state.canRoll = false
    state.record = false

    local context = getCurrentRollContext()
    prepareResponseState(context)
    finalizeMaterializedResponses(context.itemId, context.itemLink, context.rollType)
    updateSessionRollWindow(false)
end
```

- [ ] **Step 2: Replace `SetRollRecordingEnabled` internals**

Replace the body of `function module:SetRollRecordingEnabled(bool)` with:

```lua
local on = bool == true

if on then
    beginRollIntake()
else
    finishRollIntake()
end

if IsDebugEnabled() then
    addon:debug(Diag.D.LogRollsRecordState:format(tostring(bool)))
end
```

This preserves the existing debug line and the same start/stop side effects.

- [ ] **Step 3: Run targeted roll behavior tests**

```powershell
lua tests\release_stabilization_spec.lua
```

Expected:

- All targeted stabilization tests pass.

---

### Task 5: Extract Tie-Reroll Reset Glue

**Files:**

- Modify: `!KRT/Services/Rolls/Service.lua`

- [ ] **Step 1: Add a private tie-reroll reset helper**

Add this helper after `finishRollIntake()`:

```lua
local function resetForTieReroll(session, reroll, itemId, itemLink, currentRollType)
    clearRollEntries()
    clearResponseState({
        preserveManualExclusions = true,
        preserveTieReroll = true,
    })
    state.sessionId = tostring(session.id)
    state.rolled = false
    state.warned = false
    state.record = true
    state.canRoll = true
    state.countdownExpired = false

    lootState.winner = nil
    lootState.rollWinner = nil
    lootState.rollsCount = 0
    lootState.itemTraded = 0
    lootState.rollStarted = true

    session.active = true
    session.endsAt = nil
    updateSessionRollWindow(true)
    prepareResponseState({
        itemId = itemId,
        itemLink = itemLink,
        rollType = currentRollType,
    }, {
        seedReserved = false,
        seedTieReroll = true,
    })
end
```

- [ ] **Step 2: Replace the duplicated block in `BeginTieReroll`**

In `module:BeginTieReroll(names)`, keep validation, item context lookup, debug logging, and return
shape. Replace the state-reset block from `clearRollEntries()` through `prepareResponseState(...)`
with:

```lua
resetForTieReroll(session, reroll, itemId, itemLink, currentRollType)
```

Expected `BeginTieReroll` shape after replacement:

```lua
function module:BeginTieReroll(names)
    local session = getRollSession() or ensureAdHocRollSession()
    local reroll
    local itemId
    local itemLink
    local currentRollType

    if not session then
        return false
    end
    ensureResponseSession()

    reroll = setTieRerollFilter(names)
    if not (reroll and reroll.ordered and #reroll.ordered > 1) then
        return false
    end

    itemId = getCurrentRollItemID()
    itemLink = getCurrentItemLink()
    currentRollType = getActiveRollType()
    reroll.sourceRollType = currentRollType

    resetForTieReroll(session, reroll, itemId, itemLink, currentRollType)

    if IsDebugEnabled() then
        addon:debug(Diag.D.LogRollsTieReroll:format(tostring(itemLink), tconcat(reroll.ordered, ",")))
    end
    module:GetDisplayModel()
    return true, reroll.ordered
end
```

- [ ] **Step 3: Run the source-contract test**

```powershell
lua tests\audit_cleanup_wave_s2_rolls_spec.lua
```

Expected: still fails only on missing `finalizeRollSession` helper or backlog text.

---

### Task 6: Extract Finalize Helper Without Changing Public Facade

**Files:**

- Modify: `!KRT/Services/Rolls/Service.lua`

- [ ] **Step 1: Add a private finalize helper**

Add this helper after `resetForTieReroll(...)`:

```lua
local function finalizeRollSession()
    finishRollIntake()
    Countdown.Stop(state)
    Display.BuildModel(getDisplayContext())
end
```

- [ ] **Step 2: Replace `FinalizeRollSession` body**

Replace:

```lua
function module:FinalizeRollSession()
    module:SetRollRecordingEnabled(false)
    module:StopCountdown()
    module:GetDisplayModel()
end
```

with:

```lua
function module:FinalizeRollSession()
    finalizeRollSession()
end
```

Do not remove `module:SetRollRecordingEnabled`, `module:StopCountdown`, or
`module:GetDisplayModel`; Master and tests consume those public methods.

- [ ] **Step 3: Run focused roll behavior tests**

```powershell
lua tests\release_stabilization_spec.lua
```

Expected:

- All targeted stabilization tests pass.
- Tests covering explicit pass, cancel, timeout, late OOT rolls, tie reroll, duplicate attempts,
  display model resolution, and Master award validation still pass.

---

### Task 7: Update Cleanup Backlog

**Files:**

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Update the Wave S2 section**

In the `### Wave S2: Rolls Service` section, replace the current worktree progress bullets with:

```markdown
Current worktree progress:
- current-roll item resolution now lives under `Services/Rolls/Sessions.lua`
  with the other session/context helpers
- `Services/Rolls/Service.lua` keeps the public facade while using private
  helpers for roll intake start, roll intake finish, tie-reroll reset, and
  finalization
- public response lifecycle and display-model contracts are preserved:
  `PASS`, `CANCELLED`, `TIMED_OUT`, `INELIGIBLE`, late `OOT` rolls, and
  `Rolls:GetDisplayModel().resolution`
- Wave S2 completed: Rolls Service facade helper cleanup
```

- [ ] **Step 2: Keep priority/default-next-step coherent**

If the backlog default next step still lists Rolls first, move it behind the next unresolved owners:

```markdown
If continuing the cleanup program immediately, start with:

1. `!KRT/Services/Reserves.lua` facade dedup (`Service:*` + `module:*`)
2. `!KRT/EntryPoints/SlashEvents.lua` boundary cleanup follow-up
3. one remaining `getRaidQueries` owner group, starting with `!KRT/Database/DBSyncer.lua`
```

Do not mark S3, E1, or the post-Wave5 `getRaidQueries` owners as completed.

- [ ] **Step 3: Run the source-contract test**

```powershell
lua tests\audit_cleanup_wave_s2_rolls_spec.lua
```

Expected:

```text
audit cleanup wave s2 rolls source contract passed
```

---

### Task 8: Verification Gates

**Files:** no edits unless a gate exposes a defect

- [ ] **Step 1: Run focused source and behavior checks**

```powershell
lua tests\audit_cleanup_wave_s2_rolls_spec.lua
lua tests\module_registry_services_spec.lua
lua tests\release_stabilization_spec.lua
py -3 tools/krt.py run-release-targeted-tests
```

Expected:

- All commands exit `0`.
- Release stabilization reports all targeted stabilization tests passed.

- [ ] **Step 2: Run standard repo gates**

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

- All commands exit `0`.

- [ ] **Step 3: Run formatting and whitespace checks**

```powershell
stylua --check !KRT\Services\Rolls\Service.lua !KRT\Services\Rolls\Sessions.lua
stylua --check tests\audit_cleanup_wave_s2_rolls_spec.lua
git diff --check
```

Expected:

- Both commands exit `0`.
- `git diff --check` has no output.

- [ ] **Step 4: Refresh API catalogs**

Because `Sessions.GetCurrentRollItemId` adds an internal helper surface, refresh catalogs:

```powershell
py -3 tools/krt.py api-catalog-refresh
py -3 tools/krt.py api-catalog-check
```

Expected:

- Catalog files are refreshed.
- `api-catalog-check` exits `0`.

If the refresh changes generated docs, stage only generated catalog files listed in this plan.

- [ ] **Step 5: Inspect final diff**

```powershell
git diff --stat
git diff -- !KRT\Services\Rolls\Service.lua !KRT\Services\Rolls\Sessions.lua tests docs
```

Review checklist:

- `Services/Rolls/Service.lua` remains the public facade.
- Public `module:*` methods listed in Task 2 remain present.
- `Sessions.GetCurrentRollItemId` owns current item ID resolution.
- Response lifecycle states are not changed.
- `GetDisplayModel().resolution` remains public and documented in source.
- No Controller, Loot, Raid, XML, TOC, SavedVariables, or vendored files changed.

---

### Task 9: Parent Review And Closeout

**Files:** review only

- [ ] **Step 1: Parent review**

Parent reviews the final diff against this plan.

Reject the patch if it:

- removes or renames a public `Rolls:*` method;
- changes response transition policy in `Responses.lua`;
- changes resolver ordering or tie cutoff policy;
- changes Master controller behavior;
- changes display-model row or `resolution` shape;
- edits files outside the scope list except generated catalogs.

- [ ] **Step 2: Commit**

```powershell
git status --short
git add -- tests\audit_cleanup_wave_s2_rolls_spec.lua
git add -- !KRT\Services\Rolls\Sessions.lua !KRT\Services\Rolls\Service.lua
git add -- docs\TECH_CLEANUP_BACKLOG.md
git add -- docs\FUNCTION_REGISTRY.csv docs\FN_CLUSTERS.md
git add -- docs\API_NOMENCLATURE_CENSUS.md docs\API_REGISTRY.csv
git add -- docs\API_REGISTRY_PUBLIC.csv docs\API_REGISTRY_INTERNAL.csv docs\TREE.md
git commit -m "Clean up Rolls service facade helpers"
```

If a generated file did not change, `git add` may report nothing for it; that is fine. Do not stage
unrelated files.

- [ ] **Step 3: In-client smoke request**

Ask the user to run a WoW 3.3.5a smoke test:

```text
Please smoke test:
- /reload with no Lua errors
- start MS, OS, SR, and Free rolls
- submit valid rolls
- pass, cancel, timeout, and reroll a tie
- verify late OOT rolls stay visible but cannot win
- award through Master
```

The wave is not fully accepted until the user confirms the in-client smoke path.

## Remaining Risks

- `Rolls/Service.lua` stays behavior-sensitive even when the diff is private-helper cleanup.
- Public API surface is intentionally preserved; deeper public contraction needs a separate mapper
  pass and stronger evidence.
- Any future response-state cleanup must be isolated to `Responses.lua` with dedicated tests.
- Any future resolver cleanup must be isolated to `Resolution.lua`/`Strategies.lua` with no
  display-model shape changes.
