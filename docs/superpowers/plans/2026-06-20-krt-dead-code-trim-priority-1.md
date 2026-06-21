# KRT Dead Code Trim Priority 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Priority 1 dead-code candidates from KRT with small, testable cuts:
private Logger/Master/SpecInspect helpers, unused event and constants, and the old Logger manual
boss/attendee Actions API plus its stale localization strings.

**Architecture:** This is a source-compatible cleanup pass with no runtime behavior change intended.
The patch is split into a private-helper wave and a Logger Actions API wave. A focused source-contract
test proves the targeted symbols are gone while active neighboring APIs remain. The parent agent uses
the 55to53 workflow: plan and review in the parent, implementation by `spark_implementer`.

**Tech Stack:** WoW 3.3.5a, Lua 5.1, KRT addon runtime, PowerShell checks, `tools/krt.py`.

---

## 55to53 Classification

Classification: `complex-orchestrated`.

Reasons:
- More than one runtime file changes.
- A shared service API surface changes in `!KRT/Services/Logger/Actions.lua`.
- Generated API catalogs may need refresh.
- Regression risk is low but cross-file, so the parent must review final diff and checks.

Implementation routing:
- Use `spark_implementer` for the code patch.
- Keep the Spark prompt closed and operational: do not ask it to rediscover the broad request.
- If any call-site uncertainty appears during implementation, run `code-mapper` before patching that
  part.
- Parent reviews the final diff, generated docs, and test output before closing.

Changelog:
- Do not update `!KRT/CHANGELOG.md` unless implementation discovers a user-visible behavior change.
- This plan expects no SavedVariables shape change and no migration.

## Files In Scope

Runtime files:
- `!KRT/Controllers/Logger.lua`
- `!KRT/Controllers/Master.lua`
- `!KRT/Services/SpecInspect.lua`
- `!KRT/Modules/Events.lua`
- `!KRT/Modules/C.lua`
- `!KRT/Services/Logger/Actions.lua`
- `!KRT/Localization/localization.en.lua`

Tests:
- `tests/dead_code_trim_spec.lua`

Generated docs after runtime changes:
- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_CANONICAL.csv`
- `docs/API_NOMENCLATURE_CENSUS.md`
- `docs/TREE.md`, only if the new test file is tracked before tree refresh.

Files explicitly out of scope:
- `!KRT/Libs/*`
- `!KRT/!KRT.toc`
- SavedVariables schema files
- UI XML
- Any Logger UI redesign or behavior change

## Task 1: Add The Focused Source Contract Test

- [ ] Reconfirm baseline references before editing:

```powershell
rg -n "getBossEmptyStateText|getBossAttendeesEmptyStateText|_getSelectedRaidRecord|_deleteSelectedAttendees|_needBoss|_needLoot|CancelAward|GetLootSpamHeader|buildSpecIcon|RaidLeave|CHAT_PREFIX|GROUP_LOOT_CONTEXT_REUSE_SECONDS|RESERVES_ROW_HEIGHT|RESERVE_HEADER_HEIGHT|DeleteBoss\(|DeleteBossAttendee\(|UpsertBossKill\(|AddBossAttendee\(" !KRT tests -g "!KRT/Libs/**"
```

Expected before editing:
- Removed candidates show only definitions or definitions plus localization references tied to those
  definitions.
- Neighboring active APIs such as `DeleteLootMany`, `DeleteRaidAttendeeMany`, `SetLootEntry`,
  `ResolveLootEditWinner`, and `SetCurrentRaid` are not part of this removal.

- [ ] Add `tests/dead_code_trim_spec.lua` with this exact content:

```lua
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    if not string.find(text, needle, 1, true) then
        error(message .. " (missing " .. needle .. ")", 2)
    end
end

local function assertNotContains(text, needle, message)
    if string.find(text, needle, 1, true) then
        error(message .. " (found " .. needle .. ")", 2)
    end
end

local logger = read("!KRT/Controllers/Logger.lua")
assertNotContains(logger, "local function getBossEmptyStateText",
    "old Logger boss empty-state helper must stay removed")
assertNotContains(logger, "local function getBossAttendeesEmptyStateText",
    "old Logger boss-attendee empty-state helper must stay removed")
assertNotContains(logger, "module._getSelectedRaidRecord = function",
    "old Logger selected-raid getter must stay removed")
assertNotContains(logger, "module._deleteSelectedAttendees = function",
    "old Logger attendee-delete helper must stay removed")
assertNotContains(logger, "module._needBoss = function",
    "old Logger selected-boss guard must stay removed")
assertNotContains(logger, "module._needLoot = function",
    "old Logger selected-loot guard must stay removed")
assertContains(logger, "local function getRaidAttendeesEmptyStateText",
    "active Logger raid-attendee empty-state helper must remain")
assertContains(logger, "module._needRaid = function",
    "active Logger selected-raid guard must remain")
assertContains(logger, "module._runWithSelectedRaid = function",
    "active Logger selected-raid action wrapper must remain")

local master = read("!KRT/Controllers/Master.lua")
assertNotContains(master, "function module._PendingCounter:CancelAward",
    "old pending counter CancelAward helper must stay removed")
assertNotContains(master, "function Private.GetLootSpamHeader",
    "old private loot spam header helper must stay removed")
assertNotContains(master, "Private.GetLootSpamHeader = function",
    "old private loot spam header helper must stay removed")
assertContains(master, "function module._PendingCounter:Remove",
    "active pending counter Remove helper must remain")
assertContains(master, "Private.AnnounceLootLinks = function",
    "active loot announce helper must remain")

local specInspect = read("!KRT/Services/SpecInspect.lua")
assertNotContains(specInspect, "local function buildSpecIcon",
    "old single-spec icon builder must stay removed")
assertContains(specInspect, "local function buildGroupSpecIcon",
    "active grouped spec icon builder must remain")

local events = read("!KRT/Modules/Events.lua")
assertNotContains(events, "Internal.RaidLeave = \"RaidLeave\"",
    "unused RaidLeave internal event must stay removed")
assertContains(events, "Internal.RaidRosterDelta = \"RaidRosterDelta\"",
    "active raid roster delta event must remain")

local constants = read("!KRT/Modules/C.lua")
assertNotContains(constants, "C.CHAT_PREFIX = ",
    "unused long chat prefix constant must stay removed")
assertNotContains(constants, "C.GROUP_LOOT_CONTEXT_REUSE_SECONDS = ",
    "unused group-loot reuse constant must stay removed")
assertNotContains(constants, "C.RESERVES_ROW_HEIGHT = ",
    "unused reserves row height constant must stay removed")
assertNotContains(constants, "C.RESERVE_HEADER_HEIGHT = ",
    "unused reserve header height constant must stay removed")
assertContains(constants, "C.CHAT_PREFIX_SHORT = ",
    "active short chat prefix constant must remain")
assertContains(constants, "C.CHAT_PREFIX_HEX = ",
    "active chat prefix color constant must remain")
assertContains(constants, "C.RESERVES_QUERY_COOLDOWN_SECONDS = ",
    "active reserves query cooldown constant must remain")

local actions = read("!KRT/Services/Logger/Actions.lua")
assertNotContains(actions, "local function removeFromList(",
    "helper used only by removed boss attendee API must stay removed")
assertNotContains(actions, "function Actions:DeleteBoss(",
    "old manual boss delete API must stay removed")
assertNotContains(actions, "function Actions:DeleteBossAttendee(",
    "old manual boss attendee delete API must stay removed")
assertNotContains(actions, "function Actions:UpsertBossKill(",
    "old manual boss upsert API must stay removed")
assertNotContains(actions, "function Actions:AddBossAttendee(",
    "old manual boss attendee add API must stay removed")
assertContains(actions, "function Actions:DeleteLootMany(",
    "active loot-delete API must remain")
assertContains(actions, "function Actions:DeleteRaidAttendeeMany(",
    "active raid-attendee delete API must remain")
assertContains(actions, "function Actions:SetLootEntry(",
    "active loot edit API must remain")
assertContains(actions, "function Actions:ResolveLootEditWinner(",
    "active loot winner resolver API must remain")
assertContains(actions, "function Actions:SetCurrentRaid(",
    "active current-raid API must remain")
assertContains(actions, "function Actions:RemoveRaidHistoryEntries(",
    "active raid history removal API must remain")

local localization = read("!KRT/Localization/localization.en.lua")
local removedLocalizationKeys = {
    "StrBosses",
    "StrConfirmDeleteBoss",
    "StrConfirmDeleteAttendee",
    "StrBossAttendees",
    "StrBossParticipation",
    "StrAddBoss",
    "StrEditBoss",
    "StrBossNameHelp",
    "StrBossDifficultyHelp",
    "StrBossTimeHelp",
    "ErrBossDifficulty",
    "ErrBossTime",
    "StrAddPlayer",
    "ErrAttendeesInvalidName",
    "ErrAttendeesInvalidRaidBoss",
    "ErrAttendeesPlayerExists",
    "StrAttendeesAddSuccess",
}

for i = 1, #removedLocalizationKeys do
    local key = removedLocalizationKeys[i]
    assertNotContains(localization, "L." .. key .. " =",
        "localization key tied to removed Logger boss/attendee API must stay removed: " .. key)
end

assertContains(localization, "L.StrRaidAttendees = ",
    "active raid attendee label must remain")
assertContains(localization, "L.StrConfirmDeleteItem = ",
    "active loot delete confirmation must remain")
assertContains(localization, "L.StrLoggerSharedSource = ",
    "active logger shared-source label must remain")

print("dead code trim source contract passed")
```

- [ ] Run the new test before removals:

```powershell
lua tests/dead_code_trim_spec.lua
```

Expected before patching runtime:
- The test fails on the first still-present removed candidate.
- This proves the test can catch the cleanup target.

## Task 2: Remove Private Helpers, Event, And Constants

- [ ] In `!KRT/Controllers/Logger.lua`, remove only these definitions:
  - `local function getBossEmptyStateText()`
  - `local function getBossAttendeesEmptyStateText()`
  - `module._getSelectedRaidRecord = function()`
  - `module._deleteSelectedAttendees = function()`
  - `module._needBoss = function()`
  - `module._needLoot = function()`

- [ ] In the same file, preserve:
  - `local function getRaidAttendeesEmptyStateText()`
  - `module._needRaid = function()`
  - `module._runWithSelectedRaid = function(action, opts)`

- [ ] In `!KRT/Controllers/Master.lua`, remove only:
  - `function module._PendingCounter:CancelAward(award)`
  - `function Private.GetLootSpamHeader()`

- [ ] In the same file, preserve:
  - `function module._PendingCounter:Remove(award)`
  - `function module._PendingCounter:Clear()`
  - `function Private.AnnounceLootLinks(lootList)`

- [ ] In `!KRT/Services/SpecInspect.lua`, remove only:
  - `local function buildSpecIcon(specId)`

- [ ] In the same file, preserve:
  - `local function buildGroupSpecIcon(specId, groupIndex)`
  - `local function buildTalentGroupSnapshot(group, groupIndex)`

- [ ] In `!KRT/Modules/Events.lua`, remove only:
  - `Internal.RaidLeave = "RaidLeave"`

- [ ] In `!KRT/Modules/C.lua`, remove only:
  - `C.CHAT_PREFIX = "|cff33ff99KRT|r"`
  - `C.GROUP_LOOT_CONTEXT_REUSE_SECONDS = 8`
  - `C.RESERVES_ROW_HEIGHT = 24`
  - `C.RESERVE_HEADER_HEIGHT = 20`

- [ ] In the same file, preserve:
  - `C.CHAT_PREFIX_SHORT`
  - `C.CHAT_PREFIX_HEX`
  - `C.RESERVES_ITEM_FALLBACK_ICON`
  - `C.RESERVES_QUERY_COOLDOWN_SECONDS`

- [ ] Run focused checks:

```powershell
lua tests/dead_code_trim_spec.lua
lua tests/controllers_cleanup_spec.lua
lua tests/spec_inspect_service_spec.lua
lua tests/controller_chunk_budget_spec.lua
```

Expected after Task 2 and before Task 3:
- `tests/dead_code_trim_spec.lua` may still fail on Logger Actions or localization candidates.
- The other focused tests pass.

## Task 3: Remove Old Logger Manual Boss/Attendee Actions API

- [ ] In `!KRT/Services/Logger/Actions.lua`, remove only these public methods:
  - `function Actions:DeleteBoss(rID, bossNid, opts)`
  - `function Actions:DeleteBossAttendee(rID, bossNid, playerNid, opts)`
  - `function Actions:UpsertBossKill(input, opts)`
  - `function Actions:AddBossAttendee(input, opts)`

- [ ] In the same file, remove `local function removeFromList(list, value)` after confirming it has
  no references outside `DeleteBossAttendee`.

- [ ] Preserve these active methods and nearby behavior:
  - `function Actions:DeleteLootMany(rID, lootNids, opts)`
  - `function Actions:DeleteRaidAttendeeMany(rID, playerNids, opts)`
  - `function Actions:SetLootEntry(input, opts)`
  - `function Actions:ResolveLootEditWinner(input)`
  - `function Actions:SetCurrentRaid(raid, opts)`
  - `function Actions:RemoveRaidHistoryEntries(rID, opts)`
  - the Actions registry table at the end of the file

- [ ] In `!KRT/Localization/localization.en.lua`, remove only strings whose remaining references
  were inside the removed Logger boss/attendee API:
  - `L.StrBosses`
  - `L.StrConfirmDeleteBoss`
  - `L.StrConfirmDeleteAttendee`
  - `L.StrBossAttendees`
  - `L.StrBossParticipation`
  - `L.StrAddBoss`
  - `L.StrEditBoss`
  - `L.StrBossNameHelp`
  - `L.StrBossDifficultyHelp`
  - `L.StrBossTimeHelp`
  - `L.ErrBossDifficulty`
  - `L.ErrBossTime`
  - `L.StrAddPlayer`
  - `L.ErrAttendeesInvalidName`
  - `L.ErrAttendeesInvalidRaidBoss`
  - `L.ErrAttendeesPlayerExists`
  - `L.StrAttendeesAddSuccess`

- [ ] In the same localization file, preserve active Logger strings near the removed block:
  - `L.StrTrashMob`
  - `L.StrRaidAttendees`
  - `L.StrJoin`
  - `L.StrLeave`
  - `L.StrIlvl`
  - `L.StrSpec`
  - `L.StrInspect`
  - `L.StrInspectDone`
  - `L.StrInspectFail`
  - `L.BtnForceInspect`
  - `L.StrRaidLoot`
  - `L.StrUnknown`
  - `L.StrNone`
  - `L.StrConfirmDeleteItem`
  - `L.StrEditItem`
  - `L.StrLoggerSharedSource`

- [ ] Run focused checks:

```powershell
lua tests/dead_code_trim_spec.lua
lua tests/release_stabilization_spec.lua
lua tests/config_interface_options_spec.lua
```

Expected:
- `tests/dead_code_trim_spec.lua` passes.
- Existing behavior-sensitive tests pass.

## Task 4: Refresh Generated Catalogs And Run Gates

- [ ] Refresh generated function/API docs:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

- [ ] If `tests/dead_code_trim_spec.lua` is still untracked when refreshing `docs/TREE.md`, either:
  - stage the new test before the final tree refresh in the commit workflow, or
  - rerun tree refresh after the test file is tracked.

- [ ] Run required local gates:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
py -3 tools/krt.py repo-quality-check --check ui_binding
py -3 tools/krt.py repo-quality-check --check api_nomenclature
py -3 tools/krt.py api-catalog-check
git diff --check
```

Expected:
- Lua syntax passes.
- Repo quality checks pass.
- API catalog check passes after refresh.
- Diff whitespace check passes.

## Task 5: Parent Review Checklist

- [ ] Inspect changed files:

```powershell
git diff -- !KRT/Controllers/Logger.lua !KRT/Controllers/Master.lua !KRT/Services/SpecInspect.lua !KRT/Modules/Events.lua !KRT/Modules/C.lua !KRT/Services/Logger/Actions.lua !KRT/Localization/localization.en.lua tests/dead_code_trim_spec.lua docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/API_REGISTRY.csv docs/API_REGISTRY_CANONICAL.csv docs/API_NOMENCLATURE_CENSUS.md docs/TREE.md
```

- [ ] Confirm no unrelated runtime or vendored files changed:

```powershell
git diff --name-only
```

- [ ] Confirm removed symbols are absent from runtime and tests, while active neighbors remain:

```powershell
rg -n "getBossEmptyStateText|getBossAttendeesEmptyStateText|_getSelectedRaidRecord|_deleteSelectedAttendees|_needBoss|_needLoot|CancelAward|GetLootSpamHeader|local function buildSpecIcon|Internal\.RaidLeave|C\.CHAT_PREFIX =|GROUP_LOOT_CONTEXT_REUSE_SECONDS|RESERVES_ROW_HEIGHT|RESERVE_HEADER_HEIGHT|function Actions:DeleteBoss\(|function Actions:DeleteBossAttendee\(|function Actions:UpsertBossKill\(|function Actions:AddBossAttendee\(" !KRT tests -g "!KRT/Libs/**"
```

Expected:
- No matches for removed symbols.

```powershell
rg -n "DeleteLootMany|DeleteRaidAttendeeMany|SetLootEntry|ResolveLootEditWinner|SetCurrentRaid|RemoveRaidHistoryEntries|buildGroupSpecIcon|getRaidAttendeesEmptyStateText|CHAT_PREFIX_SHORT|CHAT_PREFIX_HEX" !KRT tests -g "!KRT/Libs/**"
```

Expected:
- Matches remain for active neighboring APIs.

- [ ] Review public behavior impact:
  - No SavedVariables schema change.
  - No `!KRT/!KRT.toc` load-order change.
  - No user-visible text change except removing unreachable localization keys.
  - No XML changes.
  - No Controller/Service boundary change beyond deleting unused Logger Actions methods.

## Spark Handoff Prompt

Use this prompt for `spark_implementer`:

```text
Implement docs/superpowers/plans/2026-06-20-krt-dead-code-trim-priority-1.md.

Scope is closed:
- Create tests/dead_code_trim_spec.lua exactly as specified.
- Remove only the listed dead helpers, constants, event, Logger Actions methods, and stale
  localization strings.
- Preserve all active neighboring APIs listed in the plan.
- Refresh generated API/function catalogs with the documented command.
- Keep the diff minimal and do not touch vendored libraries, SavedVariables schema, XML, or TOC.
- Run the focused tests and repo gates listed in the plan.

Return:
- files changed
- commands run and pass/fail output summary
- any deviations from the plan
```

## Follow-Up Task 6: Remove Public Utility Surfaces With No Internal Callers

Classification remains `complex-orchestrated` because this follow-up removes public table methods
across database, modules, UI primitives, and widgets. `code-mapper` confirmed there are no internal
KRT call sites; the only unresolved risk is external/addon-local direct calls to public tables.

- [ ] Extend `tests/dead_code_trim_spec.lua` with source-contract assertions for this wave:

```lua
local raidQueries = read("!KRT/Database/DBRaidQueries.lua")
assertNotContains(raidQueries, "function module:ResolveLootLooterNid",
    "unused public RaidQueries looter nid resolver must stay removed")
assertContains(raidQueries, "local function resolveLootLooterNid",
    "private RaidQueries looter nid helper must remain")
assertContains(raidQueries, "function module:ResolveLootLooterName",
    "active RaidQueries looter name resolver must remain")
assertContains(raidQueries, "function module:ResolveLootLooterNameFromMap",
    "active RaidQueries looter map resolver must remain")

local syncer = read("!KRT/Database/DBSyncer.lua")
assertNotContains(syncer, "function module:GetPrefix",
    "unused public sync prefix getter must stay removed")
assertContains(syncer, "local COMM_PREFIX = \"KRTLogSync\"",
    "active sync prefix constant must remain")
assertContains(syncer, "function module:GetProtocolVersion",
    "active sync protocol getter must remain")
assertContains(syncer, "function module:GetSyncMetrics",
    "active sync metrics getter must remain")
assertContains(syncer, "function module:ResetSyncMetrics",
    "active sync metrics reset must remain")
assertContains(syncer, "function module:OnAddonMessage",
    "active sync addon-message handler must remain")

local lootSourceCandidates = read("!KRT/Modules/LootSourceCandidates.lua")
assertNotContains(lootSourceCandidates, "function LootSourceCandidates.ParseLegacySharedText",
    "unused legacy shared-text parser wrapper must stay removed")
assertContains(lootSourceCandidates, "function LootSourceCandidates.IsLegacySharedText",
    "active legacy shared-text predicate must remain")
assertContains(lootSourceCandidates, "function LootSourceCandidates.ParseSharedText",
    "active shared-text parser must remain")
assertContains(lootSourceCandidates, "function LootSourceCandidates.Copy",
    "active loot source candidate copy helper must remain")
assertContains(lootSourceCandidates, "function LootSourceCandidates.BuildLootSourceModel",
    "active loot source model builder must remain")

local frames = read("!KRT/Modules/UI/Frames.lua")
assertNotContains(frames, "function ModuleState.ClearDirty",
    "unused ModuleState clear helper must stay removed")
assertContains(frames, "function ModuleState.Ensure",
    "active ModuleState Ensure helper must remain")
assertContains(frames, "function ModuleState.Get",
    "active ModuleState Get helper must remain")
assertContains(frames, "function ModuleState.Reset",
    "active ModuleState Reset helper must remain")
assertContains(frames, "function ModuleState.MarkDirty",
    "active ModuleState MarkDirty helper must remain")

local visuals = read("!KRT/Modules/UI/Visuals.lua")
assertNotContains(visuals, "function Primitives.SetNamedPartShown",
    "unused named-part show helper must stay removed")
assertContains(visuals, "function Primitives.SetShown",
    "active primitive show helper must remain")
assertContains(visuals, "function Primitives.SetEnabled",
    "active primitive enabled helper must remain")
assertContains(visuals, "function Primitives.SetNamedPartEnabled",
    "active named-part enabled helper must remain")
assertContains(visuals, "function Primitives.UpdateNamedPartModeText",
    "active named-part mode text helper must remain")

local lootHints = read("!KRT/Widgets/LootHints.lua")
assertNotContains(lootHints, "module.ApplyLootReserveUi = function",
    "unused LootHints reserve UI wrapper must stay removed")
assertContains(lootHints, "module.BuildLootReserveUiState = function",
    "active LootHints reserve state builder must remain")
assertContains(lootHints, "module.ApplyLootFrameReserveHints = function",
    "active LootFrame reserve hint applier must remain")
assertContains(lootHints, "module.ClearLootFrameReserveHints = function",
    "active LootFrame reserve hint clearer must remain")
assertContains(lootHints, "module.EnsureLootFrameHooks = function",
    "active LootFrame hook installer must remain")
```

- [ ] Remove only these public utilities:
  - `function module:ResolveLootLooterNid(loot)` from `!KRT/Database/DBRaidQueries.lua`
  - `function module:GetPrefix()` from `!KRT/Database/DBSyncer.lua`
  - `function LootSourceCandidates.ParseLegacySharedText(value)` from
    `!KRT/Modules/LootSourceCandidates.lua`
  - `function ModuleState.ClearDirty(module)` from `!KRT/Modules/UI/Frames.lua`
  - `function Primitives.SetNamedPartShown(frameName, suffix, cond)` from
    `!KRT/Modules/UI/Visuals.lua`
  - `module.ApplyLootReserveUi = function(frame, itemLink, icon, anchor)` from
    `!KRT/Widgets/LootHints.lua`

- [ ] Preserve the active neighboring APIs named in the source-contract assertions.

- [ ] Refresh generated function/API docs after the removals:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

- [ ] Run focused and repo checks:

```powershell
lua tests/dead_code_trim_spec.lua
lua tests/release_stabilization_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
py -3 tools/krt.py repo-quality-check --check ui_binding
py -3 tools/krt.py api-catalog-check
git diff --check
```

Expected:
- Removed symbols have no runtime matches.
- Active neighboring APIs remain.
- No SavedVariables, TOC, XML, or vendored-library changes.

## Completion Criteria

This cleanup is complete only when:
- The parent has reviewed the Spark diff.
- `tests/dead_code_trim_spec.lua` passes.
- The focused behavior tests pass.
- Lua syntax and repo quality gates pass.
- Generated API catalogs are refreshed and `api-catalog-check` passes.
- The final response reports the plan followed, files changed, summary, tests/checks, and remaining
  risks.

## Plan Self-Review

- Source-contract test includes both removal assertions and active-neighbor preservation assertions.
- The implementation tasks are ordered from smaller private cleanup to the public Logger Actions API.
- The plan avoids SavedVariables changes, XML changes, TOC changes, and vendored code.
- No open-ended implementation steps are required for execution.
