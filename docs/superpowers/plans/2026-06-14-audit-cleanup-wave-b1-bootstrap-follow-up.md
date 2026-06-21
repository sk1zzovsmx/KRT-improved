# Wave B1 Bootstrap Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit `!KRT/Init.lua` for proven residual feature-owner glue and either
close B1 as a no-candidate audit or stop for one owner-specific micro-plan.

**Architecture:** `Init.lua` owns bootstrap namespaces, SavedVariables bootstrap,
main WoW event registration, and Bus forwarding. Wave B1 must not split bootstrap
mechanically; it may only move feature-specific glue when current source proves a
clear owner and a narrow replacement contract.

**Tech Stack:** WoW 3.3.5a addon, Interface 30300, Lua 5.1, KRT module registry,
PowerShell repo tooling, Lua source-contract tests, delegated 55to53 workflow.

---

## Classification

`complex-orchestrated`.

Reasons:

- `!KRT/Init.lua` owns load order, SavedVariables preparation, main frame event
  routing, and compatibility bootstrap.
- A wrong cleanup can break addon loading, WoW event handling, raid detection,
  passive loot logging, sync routing, timer binding, or persistence.
- The backlog explicitly says to continue only if a later inventory proves a
  residual owner.
- The implementation path depends on mapping results.

Workflow:

1. Parent reviews backlog, architecture docs, and current `Init.lua`.
2. `code-mapper` maps every non-trivial bootstrap/event block in `Init.lua`.
3. Parent accepts a candidate only when ownership and replacement are proven.
4. If no candidate is proven, close B1 as a documented no-candidate audit.
5. If one candidate is proven, stop this generic plan and write a B1a micro-plan.
6. Any runtime `Init.lua` change must use `spark_implementer` with a parent-
   approved, candidate-specific plan.
7. Parent reviews final diff before completion.

## File Structure

Read-only mapping inputs:

- Read: `docs/TECH_CLEANUP_BACKLOG.md`
- Read: `docs/ARCHITECTURE.md`
- Read: `docs/OVERVIEW.md`
- Read: `docs/LUA_ALIGNMENT_MATRIX.md`
- Read: `docs/TECH_CLEANUP_WORKFLOW.md`
- Read: `!KRT/!KRT.toc`
- Read: `!KRT/Init.lua`
- Read: `!KRT/Modules/Events.lua`
- Read: `!KRT/Modules/Bus.lua`
- Read: `!KRT/Modules/Timer.lua`
- Read: `!KRT/Modules/UI/Frames.lua`
- Read: `!KRT/Modules/Comms.lua`
- Read: `!KRT/Database/DB.lua`
- Read: `!KRT/Database/DBManager.lua`
- Read: `!KRT/Database/DBRaidStore.lua`
- Read: `!KRT/Database/DBSyncer.lua`
- Read: `!KRT/Services/Raid/State.lua`
- Read: `!KRT/Services/Raid/Session.lua`
- Read: `!KRT/Services/Raid/Roster.lua`
- Read: `!KRT/Services/Raid/Capabilities.lua`
- Read: `!KRT/Services/Loot/Service.lua`
- Read: `!KRT/Services/Loot/PassiveGroupLoot.lua`
- Read: `!KRT/Services/Loot/DistributionSession.lua`
- Read: `!KRT/Services/Rolls/Service.lua`
- Read: `!KRT/Services/Reserves.lua`
- Read: `!KRT/EntryPoints/Minimap.lua`
- Read: `tests/release_stabilization_spec.lua`
- Read: `tests/module_registry_services_spec.lua`
- Read: `tests/module_registry_ui_entrypoints_spec.lua`

Expected files if no safe runtime candidate is proven:

- Create: `tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua`
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
- Modify: `docs/TREE.md`
- Create: `docs/superpowers/plans/2026-06-14-audit-cleanup-wave-b1-bootstrap-follow-up.md`

Runtime files must remain unchanged on the no-candidate path:

- Do not modify: `!KRT/Init.lua`
- Do not modify: `!KRT/!KRT.toc`
- Do not modify: `!KRT/Modules/*.lua`
- Do not modify: `!KRT/Database/*.lua`
- Do not modify: `!KRT/Services/**/*.lua`
- Do not modify: `!KRT/Controllers/*.lua`
- Do not modify: `!KRT/Widgets/*.lua`
- Do not modify: `!KRT/EntryPoints/*.lua`
- Do not modify: `!KRT/UI/*.xml`
- Do not modify: SavedVariables schema or migrations

If a candidate is proven, stop this plan and write a narrower B1a plan before
changing runtime code.

## Current Evidence

Backlog constraints:

- `docs/TECH_CLEANUP_BACKLOG.md` says `!KRT/Init.lua` should stay a follow-up
  lane and should not be reopened early unless a cleanup wave proves a residual
  owner clearly belongs elsewhere.
- Wave B1 scope is to move residual feature-specific glue only when ownership is
  clear and to keep bootstrap ownership centralized.
- The current default next step says to start with bootstrap follow-up only if a
  later inventory proves a residual owner.

Current architecture constraints:

- `Init.lua` owns shared bootstrap namespaces, `addon.State`, `addon.Events`,
  main WoW event wiring, and Bus forwarding.
- `Init.lua` may call Services and Controllers where bootstrap or event routing
  requires it, but Services must not call Controllers or own frame lifecycle.
- EntryPoints own slash/minimap routing, but bootstrap may call minimap lifecycle
  endpoints such as `Minimap:EnsureUI()`.
- SavedVariables shape must not change without migration and changelog notes.

Initial candidate lanes to map:

- SavedVariables/bootstrap helpers:
  `Database.NormalizeSavedVariablesAfterLoad`,
  `Database.PrepareSavedVariablesForSave`, `Database.StripRuntimeRaidCaches`,
  and raid-store fallback paths.
- WoW event dispatcher:
  `addon:RegisterEvent`, `addon:UnregisterEvent`, `mainFrame:SetScript`, and
  the `wowBusEvents` forwarding table.
- Raid-session events:
  `RAID_INSTANCE_WELCOME`, `PLAYER_DIFFICULTY_CHANGED`,
  `UPDATE_INSTANCE_INFO`, `PLAYER_ENTERING_WORLD`, and
  `COMBAT_LOG_EVENT_UNFILTERED`.
- Roster events:
  `RAID_ROSTER_UPDATE`, `processRaidRosterUpdate`, and
  `InternalEvents.RaidRosterDelta`.
- Passive loot and roll-routing events:
  `CHAT_MSG_LOOT`, `CHAT_MSG_SYSTEM`, `START_LOOT_ROLL`, and
  `observePassiveLootMessage`.
- Addon-message fan-out:
  `CHAT_MSG_ADDON` routing through Comms, Reserves, Loot distribution, and
  DBSyncer.
- Bootstrap side effects:
  `ADDON_LOADED`, Timer mixin binding, options load, minimap ensure, reserves
  load, comm prefix registration, and event registration.

Initial review implication:

- Do not move event registration itself out of `Init.lua`; it is bootstrap-owned.
- Do not move Bus forwarding table entries unless `Modules/Events` or `Bus`
  already owns an equivalent contract and load order proves it is safe.
- Do not move SavedVariables preparation unless the Database owner already has
  the complete public contract and the fallback behavior remains identical.
- Do not move passive loot or addon-message fan-out unless the replacement keeps
  ordering, capability gates, and fallbacks exactly unchanged.

## Task 0: Mapping Gate

**Files:**

- Read every file listed in "File Structure".

- [ ] **Step 1: Dispatch `code-mapper` read-only**

Use this exact prompt:

```text
Map Wave B1 for `!KRT/Init.lua`.

The backlog says bootstrap follow-up may proceed only if a fresh inventory
proves a residual owner that clearly belongs elsewhere. Do not assume a runtime
candidate exists.

Return a table with these columns:
- block or function name
- definition line range in `!KRT/Init.lua`
- current responsibility
- candidate owner, if any
- production callers or event sources
- tests or docs that describe the contract
- risk class
- verdict: keep in Init, candidate for B1a micro-plan, or unclear

Scope every non-trivial block:
- bootstrap namespace seeding and `Database.GetFeatureShared`
- performance helpers
- event name seeding
- `Database.RequestControllerMethod`
- `Database.EnsureServiceNamespace`
- `Database.EnsureLootRuntimeState`
- SavedVariables bootstrap and library bootstrap
- frame event dispatcher and `RegisterEvent` wrappers
- `Database.MakeModuleFrameGetter`
- `Database.RequireServiceMethod`
- raid-store fallback wrappers
- `Database.NormalizeSavedVariablesAfterLoad`
- `Database.PrepareSavedVariablesForSave`
- `ADDON_LOADED`
- `wowBusEvents` forwarding
- raid instance and roster handlers
- passive loot and roll handlers
- `CHAT_MSG_ADDON` fan-out
- boss-yell and combat-log forwarding
- `PLAYER_LOGOUT`

Candidate acceptance rules:
- A candidate must have a single clear owner outside `Init.lua`.
- The replacement owner must already be loaded early enough by `!KRT/!KRT.toc`
  or the mapper must identify the exact load-order change required.
- Event registration must remain in `Init.lua`.
- SavedVariables shape, sync wire format, passive loot behavior, roll routing,
  raid detection, roster delta events, and minimap/bootstrap side effects must
  remain behaviorally unchanged.

Stop conditions:
- If no candidate is proven, say `NO_RUNTIME_CANDIDATE`.
- If a candidate is proven, identify only the smallest candidate block and its
  exact replacement owner. Do not propose broad Init splitting.
```

- [ ] **Step 2: Parent reviews mapper verdicts**

Accept a candidate only if all points are true:

- current source proves the block is feature-specific rather than bootstrap or
  event wiring;
- the candidate owner already has the right namespace and load-order position,
  or a single minimal TOC move is proven safe;
- the replacement keeps the same event registration timing and dispatch order;
- the replacement keeps all nil-guard and fallback behavior;
- the replacement does not alter SavedVariables, sync wire format, passive loot
  attribution, roll routing, raid detection, roster deltas, or UI lifecycle.

- [ ] **Step 3: Stop if mapper returns `NO_RUNTIME_CANDIDATE`**

On this path, skip runtime-edit tasks. Continue only with the no-candidate audit
contract, backlog update, tree update, and verification.

- [ ] **Step 4: Stop if mapper returns a runtime candidate**

On this path, do not edit runtime code in Wave B1. Create a narrower follow-up
plan named after the owner and block, for example:

```text
docs/superpowers/plans/2026-06-14-audit-cleanup-wave-b1a-bootstrap-chat-addon-routing.md
```

That follow-up plan must include the exact block, exact replacement owner,
candidate-specific RED test, minimal runtime patch, generated docs, and full
smoke path. Do not continue with this generic B1 plan for runtime edits.

## Task 1A: Add No-Candidate Audit Source Contract

Use this task only if `code-mapper` returns `NO_RUNTIME_CANDIDATE`.

**Files:**

- Create: `tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua`

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

local init = read("!KRT/Init.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local architecture = read("docs/ARCHITECTURE.md")
local overview = read("docs/OVERVIEW.md")

local initOwnedContracts = {
    "addon.Database = addon.Database or {}",
    "addon.State = addon.State or {}",
    "addon.Events = addon.Events or {}",
    "addon.Controllers = addon.Controllers or {}",
    "addon.Services = addon.Services or {}",
    "addon.Widgets = addon.Widgets or {}",
    "addon.Bus = addon.Bus or {}",
    "function Database.GetFeatureShared()",
    "function Database.EnsureBootstrapEvents()",
    "function Database.RequestControllerMethod(name, methodName, ...)",
    "function Database.EnsureServiceNamespace(...)",
    "function Database.EnsureLootRuntimeState()",
    "function Database.NormalizeSavedVariablesAfterLoad()",
    "function Database.PrepareSavedVariablesForSave(contextTag)",
    "function addon:RegisterEvent(eventName)",
    "function addon:UnregisterEvent(eventName)",
    "mainFrame:SetScript(\"OnEvent\", handleEvent)",
    "addon:RegisterEvent(\"ADDON_LOADED\")",
    "function addon:ADDON_LOADED(name)",
    "function addon:PLAYER_LOGOUT()",
}

for i = 1, #initOwnedContracts do
    assertContains(init, initOwnedContracts[i])
end

local eventForwardingContracts = {
    "WowEvents.LootOpened",
    "WowEvents.LootClosed",
    "WowEvents.OpenMasterLootList",
    "WowEvents.UpdateMasterLootList",
    "WowEvents.ChatMsgWhisper",
    "WowEvents.ReadyCheck",
    "Bus.TriggerEvent(eventKey, ...)",
}

for i = 1, #eventForwardingContracts do
    assertContains(init, eventForwardingContracts[i])
end

local bootstrapSideEffects = {
    "addon.Options.EnsureLoaded()",
    "addon.Options.SetDebugEnabled(false)",
    "addon.Timer.BindMixin(addon, \"Database\")",
    "minimap:EnsureUI()",
    "reservesService:Load()",
    "addon.Comms:EnsureVersionPrefix()",
    "Database.NormalizeSavedVariablesAfterLoad()",
    "self:RAID_ROSTER_UPDATE(true)",
}

for i = 1, #bootstrapSideEffects do
    assertContains(init, bootstrapSideEffects[i])
end

local eventHandlerContracts = {
    "function addon:RAID_ROSTER_UPDATE(forceImmediate)",
    "function addon:RAID_INSTANCE_WELCOME(...)",
    "function addon:PLAYER_DIFFICULTY_CHANGED()",
    "function addon:UPDATE_INSTANCE_INFO()",
    "function addon:PLAYER_ENTERING_WORLD()",
    "function addon:CHAT_MSG_LOOT(msg)",
    "function addon:CHAT_MSG_SYSTEM(msg)",
    "function addon:START_LOOT_ROLL(rollId, rollTime)",
    "function addon:CHAT_MSG_ADDON(prefix, msg, channel, sender)",
    "function addon:CHAT_MSG_MONSTER_YELL(...)",
    "function addon:COMBAT_LOG_EVENT_UNFILTERED(...)",
}

for i = 1, #eventHandlerContracts do
    assertContains(init, eventHandlerContracts[i])
end

local addonMessageHandlers = {
    "addon.Comms:HandleVersionMessage(prefix, msg, channel, sender)",
    "reservesService:HandleSyncMessage(prefix, msg, channel, sender)",
    "lootService:HandleDistributionMessage(prefix, msg, channel, sender)",
    "syncer:OnAddonMessage(prefix, msg, channel, sender)",
}

for i = 1, #addonMessageHandlers do
    assertContains(init, addonMessageHandlers[i])
end

assertContains(init, "lootService:ObservePassiveLootMessage(msg, winnerOnly)")
assertContains(init, "lootService:AddGroupLootMessage(msg)")
assertContains(init, "lootService:AddLoot(msg, nil, nil, parsedLoot)")
assertContains(init, "rollsService:CHAT_MSG_SYSTEM(msg)")
assertContains(init, "lootService:AddPassiveLootRoll(rollId, rollTime)")
assertContains(init, "raidService:AddBoss(L.BossYells[text])")
assertContains(init, "raidService:COMBAT_LOG_EVENT_UNFILTERED(...)")
assertContains(init, "Bus.TriggerEvent(InternalEvents.RaidRosterDelta")

assertContains(
    backlog,
    "Wave B1 completed the bootstrap residual-owner inventory."
)
assertContains(
    backlog,
    "no bootstrap block was proven safe to move out of `!KRT/Init.lua` in this pass."
)
assertContains(
    backlog,
    "open a fresh inventory item only when a new owner-specific candidate is proven"
)
assertContains(
    backlog,
    "keep `!KRT/Init.lua` and `!KRT/Services/Reserves.lua` in hold without new call-site evidence"
)
assertContains(backlog, "no speculative splitting")
assertContains(backlog, "no event-wiring rewrite without evidence")
assertContains(backlog, "`!KRT/Modules/UI/Frames.lua`: cleanup wave U1 completed, monitor only")
assertContains(architecture, "`!KRT/Init.lua`")
assertContains(architecture, "Owns shared bootstrap namespaces")
assertContains(overview, "`Init.lua` also owns global WoW event wiring and bus forwarding.")

assertNotContains(init, "self.Raid")
assertNotContains(init, "addon.Master")
assertNotContains(init, "addon.Raid")
assertNotContains(init, "addon.Config")
assertNotContains(init, "addon.Frames")

print("audit cleanup wave B1 bootstrap follow-up source contract passed")
```

- [ ] **Step 2: Run the contract test and verify the backlog assertions fail**

Run:

```powershell
lua tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua
```

Expected failure before Task 2:

```text
missing: Wave B1 completed the bootstrap residual-owner inventory.
```

This is the RED check for the no-candidate audit closure. The Init ownership
assertions should already match current source; the backlog closure assertions
should fail until Task 2 updates the backlog.

## Task 1B: Proven Candidate Stop Gate

Use this task only if `code-mapper` proves one residual owner candidate.

**Files:**

- No edits in this generic plan.

- [ ] **Step 1: Record the candidate summary in the parent response**

Write the candidate summary in plain text with these facts:

- the exact `!KRT/Init.lua` line range;
- the current block or function name;
- the exact replacement owner file;
- the event names or call sites involved;
- the behavior contracts that must not change;
- the required follow-up plan filename.

- [ ] **Step 2: Stop before runtime edits**

Do not change `!KRT/Init.lua` in Wave B1. The parent must write a candidate-
specific B1a micro-plan before implementation.

## Task 2: No-Candidate Backlog Closure

Use this task only if `code-mapper` returns `NO_RUNTIME_CANDIDATE`.

**Files:**

- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Add Wave B1 completion note in the Wave B1 section**

In the existing `### Wave B1: Bootstrap Follow-up` section, append these bullets
under `Current worktree progress`:

```markdown
- Wave B1 completed the bootstrap residual-owner inventory.
- no bootstrap block was proven safe to move out of `!KRT/Init.lua` in this pass.
- future bootstrap contraction requires a fresh owner-specific micro-plan backed
  by a new line-range inventory.
```

- [ ] **Step 2: Update Default Next Step**

Replace:

```markdown
1. bootstrap follow-up in `!KRT/Init.lua` only if a later inventory proves a residual owner
2. hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method
```

with:

```markdown
1. open a fresh inventory item only when a new owner-specific candidate is proven
2. keep `!KRT/Init.lua` and `!KRT/Services/Reserves.lua` in hold without new call-site evidence
```

- [ ] **Step 3: Align stale UI scaffold status**

In `## 2. Status by Module`, replace:

```markdown
- `!KRT/Modules/UI/Frames.lua`: cleanup wave U1 in progress
```

with:

```markdown
- `!KRT/Modules/UI/Frames.lua`: cleanup wave U1 completed, monitor only
```

This is documentation alignment only. It records the already-completed Wave U1
section and must not introduce a new UI task.

- [ ] **Step 4: Keep runtime files unchanged**

Run:

```powershell
git diff --name-only -- "!KRT/*.lua" "!KRT/**/*.lua" "!KRT/*.toc" "!KRT/**/*.xml"
```

Expected output:

```text

```

No runtime addon file should appear on the no-candidate path.

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

If a later B1a micro-plan changes runtime Lua, that micro-plan must regenerate:

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
lua tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua
lua tests/module_registry_services_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected output includes:

```text
audit cleanup wave B1 bootstrap follow-up source contract passed
module registry services source contract passed
module registry ui entrypoints source contract passed
targeted stabilization test(s) passed
```

- [ ] **Step 2: Run repo gates**

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

`git diff --check` must exit `0`.

## Task 5: Parent Review

**Files:**

- Review every changed file.

- [ ] **Step 1: Confirm no-candidate path scope**

If `NO_RUNTIME_CANDIDATE` was returned, verify:

- no runtime addon file under `!KRT` changed;
- no SavedVariables, TOC, XML, import format, sync wire format, raid detection,
  passive loot logging, roll routing, roster delta, minimap lifecycle, or event
  registration behavior changed;
- `docs/TECH_CLEANUP_BACKLOG.md` records Wave B1 as a completed audit;
- `docs/TECH_CLEANUP_BACKLOG.md` aligns the stale Wave U1 status line;
- `docs/TREE.md` lists the new B1 plan and audit spec;
- the new source contract preserves current bootstrap/event ownership.

- [ ] **Step 2: Confirm proven-candidate path was not implemented here**

If a candidate was found, verify:

- no runtime edits were made in Wave B1;
- a B1a follow-up micro-plan was created or requested;
- the parent response names the exact candidate, owner, line range, and risk.

- [ ] **Step 3: Decide commit gate**

If the no-candidate path changed only docs/tests, commit after local checks pass:

```powershell
git add docs/TECH_CLEANUP_BACKLOG.md docs/TREE.md `
  docs/superpowers/plans/2026-06-14-audit-cleanup-wave-b1-bootstrap-follow-up.md `
  tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua
git commit -m "Document bootstrap follow-up review"
```

If any runtime addon file changes in a B1a micro-plan, require an in-client
WoW 3.3.5a smoke test before commit.

## Manual Smoke

No in-client smoke is required for the no-candidate path because runtime addon
files are unchanged.

If a follow-up B1a runtime micro-plan is created later, smoke these paths:

- Login with no Lua errors.
- `/reload` with no Lua errors.
- `/krt` opens.
- Raid detection creates or restores the current raid.
- Roster updates publish join/update/leave deltas.
- Passive Group Loot and Master Loot event paths still log expected loot.
- Rolls still receive `CHAT_MSG_SYSTEM` roll lines.
- Reserves sync and distribution sync addon-message routing still work.
- Minimap icon initializes and menu actions still route.
- `PLAYER_LOGOUT` preserves SavedVariables and strips runtime-only raid caches.

## Self-Review

- Spec coverage: the plan addresses Wave B1 exactly: bootstrap follow-up only if
  a later inventory proves a residual owner.
- Placeholder scan: no runtime candidate is assumed; mapper-dependent runtime
  work stops and requires a B1a micro-plan.
- Type consistency: all method and event names match current `!KRT/Init.lua`
  source as of this plan.
