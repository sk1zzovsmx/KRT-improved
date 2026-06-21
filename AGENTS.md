# KRT - AGENTS.md (WoW 3.3.5a / Lua 5.1)

Context file for AI coding agents. Keep lines <= 120 chars.

Default: guidelines are non-binding; when in doubt, follow existing KRT patterns.
Exception: sections marked **BINDING** must be followed for every change.

`!KRT/CHANGELOG.md` is the single source of truth for behavior/user-visible changes.

Developer docs package:
- `docs/ARCHITECTURE.md` - architecture/layering map and XML/UI policy
- `docs/OVERVIEW.md` - runtime ownership and module map
- `docs/LUA_WRITING_RULES.md` - Lua writing and naming rules
- `docs/UI_CODING_RULES.md` - reusable UI layout, template, list, and editbox rules
- `docs/DEV_CHECKS.md` - local checks and gates
- `docs/AGENT_SKILLS.md` - agent skills and companion tooling
- `docs/KRT_MCP.md` - repo-local MCP server usage
- `tools/krt.py` - cross-platform tooling entrypoint

---

## 1) Conversation Rules

- Before starting a task, scan the latest user message for new permanent rules/preferences.
- If a new durable rule is detected, update this file first, then do the task.
- Do not record one-off instructions, temporary exceptions, or task-local preferences.
- For large cleanup/refactor waves, start from a fresh inventory and proceed in stable load/layer order.

---

## Delegated Codex workflow: 55to53

In this project, the delegated `55to53` workflow is the default workflow for every
non-trivial code change. The user may also refer to it explicitly by name.

### Roles

- The parent agent uses the main project model, normally `gpt-5.5`.
- The parent agent owns analysis, reasoning, planning, review, and final correction.
- The workflow gate is the repo-local skill `55to53-orchestrator`.
- The exploration subagent is `code-mapper`.
- The implementation subagent is `spark_implementer`.
- The tooling/docs subagent is `tooling_worker`.
- `code-mapper` is read-only exploration and should map ownership, call paths, branch points,
  and unknowns before edits when uncertainty is material.
- `spark_implementer` is implementation-only and should use `gpt-5.3-codex-spark`.
- `tooling_worker` should use `gpt-5.5` with medium reasoning effort for scripts, tooling,
  transforms, reports, and
  documentation-oriented technical work around the addon.

Use `tooling_worker` when the task is primarily:

- `tools/*` work
- helper scripts or local automation
- report/export glue
- parsing or normalization utilities
- documentation-oriented technical notes or operational docs

### Model routing

Use models by task type:

- `gpt-5.5` is the default model for core addon reasoning: architecture, mapping, planning,
  debugging, review, final correction, and behavior-sensitive runtime work.
- `gpt-5.5` with medium reasoning effort is preferred for tooling, utility scripts, local
  automation, text/data transforms, reports, and documentation-oriented technical work around
  the addon when a dedicated tooling worker is used in this environment.
- `spark_implementer` on `gpt-5.3-codex-spark` is for micro-patches only. It should not own
  design, architecture, multi-file reasoning, or behavior-sensitive refactors.

Prefer `gpt-5.5` whenever the task touches:

- `!KRT/Controllers/*`
- `!KRT/Services/*`
- `!KRT/Database/*`
- `!KRT/!KRT.toc`
- SavedVariables shape, load order, service/controller boundaries, or public behavior

Prefer `tooling_worker` on `gpt-5.5` medium when the task is outside the runtime-critical addon
core and is primarily:

- `tools/*` work
- helper scripts
- reporting/export glue
- parsing or normalization utilities
- draft documentation or operational notes

### Escalation criteria

The parent may edit directly only for `trivial` or tightly `bounded` work.
If a task is `complex-orchestrated`, implementation must go through
`spark_implementer`.

Treat a task as `complex-orchestrated` when any point below is true:

- more than one file is likely to change
- a shared module, service contract, controller boundary, or public behavior is involved
- there is meaningful regression risk
- ownership, call flow, or branch behavior is not already clear
- the plan has three or more concrete implementation steps
- the task is expected to need a review/correction loop after the first patch

Use the repo-local skill `.agents/skills/55to53-orchestrator/SKILL.md` as the
operational classifier and routing layer for this workflow.

### Required workflow

1. The parent agent analyzes the task.
2. Before editing, the parent agent classifies the task through the `55to53-orchestrator`
   rules as `trivial`, `bounded`, or `complex-orchestrated`.
3. For non-trivial code changes, the parent agent should use `code-mapper` first when file
   ownership, execution flow, or branch behavior is not already clear.
4. If the task is `complex-orchestrated`, the parent agent must not implement it directly.
5. Before editing files, the parent agent creates a concise operational plan.
6. The plan must include:
   - goal of the change
   - files or functions likely involved
   - implementation strategy
   - risks or regressions to check
   - tests or checks to run
7. The parent agent delegates implementation to `spark_implementer`.
8. `spark_implementer` receives only closed, operational instructions, not the open-ended
   user request.
9. `spark_implementer` applies only the parent-approved plan.
10. `spark_implementer` must keep the diff minimal.
11. `spark_implementer` must avoid unrelated refactors, broad rewrites, speculative
    improvements, and architectural changes.
12. After implementation, the parent agent reviews the final diff.
13. The parent review must check:
    - whether the implementation matches the plan
    - unnecessary changes
    - regressions
    - style consistency
    - public behavior changes
    - test/check results
14. If Spark deviates from the plan, introduces regressions, modifies too much, or leaves
    incomplete work, the parent agent must correct the code directly or delegate a smaller
    corrective patch to `spark_implementer`.
15. The task is not complete until the parent agent has reviewed the final code.

### Final response requirements

The final response must include:

- mini plan followed
- files changed
- summary of changes
- tests/checks run
- remaining risks, if any

### Repo policy

- Keep project-specific Codex workflow files local under `.codex/`, not committed.
- Keep project-specific orchestrator skills local under `.agents/skills/`, not committed.
- Prefer the repo-local launcher `py -3 tools/krt.py codex-55to53 ...` when starting
  complex delegated Codex tasks from the command line.
- For `complex-orchestrated` tasks started through the repo-local launcher, use a
  dedicated task branch for the specific work item before implementation begins,
  even if the current checkout is already a `codex/*` branch.
- Treat `.codex/`, `.agents/`, `.vscode/`, `.venv/`, Python caches, and linter caches as
  local development state that must stay out of GitHub unless the user explicitly requests it.
- Do not move this workflow back to a global profile unless the user explicitly requests it.

### User reinforcement phrase

This rule is persistent in the project and should not need to be repeated in every prompt.
For large, delicate, risky, or multi-file tasks, the user may reinforce it with:
"Usa il workflow delegato del progetto: 5.5 pianifica, code-mapper mappa,
spark_implementer applica, 5.5 revisiona e corregge prima di chiudere."

---

## 2) Hard Constraints (**BINDING**)

- Client/API: Wrath of the Lich King 3.3.5a, Interface 30300, Lua 5.1.
- Addon folder name: `!KRT` with the leading `!`.
- Do not introduce Ace2/Ace3 dependencies.
- Do not modify vendored libraries under `!KRT/Libs/*`.
- Do not break SavedVariables shape without migration and changelog notes.
- Do not introduce new non-frame globals unless explicitly required and documented.
- Code, comments, UI labels, chat text, and docs should be English and ASCII-only unless required otherwise.
- User-facing strings go through `addon.L`; diagnostic templates go through `addon.Diagnose`.
- Do not cite or name other addons as implementation references in code, comments, UI text, or docs.

---

## 3) Runtime Architecture (**BINDING**)

KRT is modular. Keep ownership boundaries clear.

- `!KRT/Init.lua` owns bootstrap, shared runtime tables, and main WoW event wiring.
- `!KRT/Database/*` owns DB/options/schema/persistence contracts.
- `!KRT/Modules/*` owns reusable infra/static data only, not feature implementations.
- `!KRT/Services/*` owns runtime service/model logic.
- `!KRT/Controllers/*` owns top-level feature Parents and their frames.
- `!KRT/Widgets/*` owns feature-specific child widgets.
- `!KRT/EntryPoints/*` owns slash/minimap entrypoints.
- XML stays layout-only under `!KRT/UI/*`; do not add XML `<Scripts>` or `<On...>` handlers.
- `!KRT/!KRT.toc` is the authoritative load order. Keep it aligned with `docs/TREE.md`.

Top-level Parents:
- `addon.Controllers.Master`
- `addon.Controllers.Logger`
- `addon.Controllers.Warnings`
- `addon.Controllers.Spammer`

Rules:
- Services must not call Parents, touch Parent frames, reference Widgets, or delegate UI.
- Upward communication uses `addon.Bus`.
- EntryPoints may call Parent `:Toggle()` methods.
- Child widgets attach Parent -> Child only.
- Use `addon.UI.Widgets.Call(...)` for Controller/EntryPoint -> Widget calls.
- Do not reintroduce retired root aliases such as `addon.Master`, `addon.Raid`, or `addon.Config`.
- Do not reintroduce legacy UI root aliases such as `addon.Frames`, `addon.UIScaffold`,
  `addon.ListController`, `addon.UIPrimitives`, `addon.UIRowVisuals`, or `addon.MultiSelect`.
- `addon:Print` remains the only root-method compatibility exception for LibLogger.

---

## 4) File Header And Namespaces

Preferred Lua file header:

```lua
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()
```

Use the canonical namespaces:
- `addon.Database`
- `addon.Controllers.*`
- `addon.Services.*`
- `addon.Widgets.*`
- `addon.UI.*`
- `addon.Modules` are exposed by concrete names such as `addon.Item`, `addon.Sort`, `addon.Bus`.

Keep bootstrap ownership centralized in `Init.lua` for:
- `addon.Database`
- `addon.L`
- `addon.Diagnose`
- `addon.State`
- `addon.C`
- `addon.Events`

---

## 5) Lua 5.1 Rules (**BINDING**)

- Everything is `local` unless intentionally exported.
- Prefer locals for readability and runtime cost.
- Do not use modern APIs such as `C_Timer` or `C_*` namespaces.
- Avoid `io`, `os`, and `debug` in addon runtime.
- Respect combat lockdown.
- Arrays are 1-indexed.
- If holes are possible, do not rely on `#t`.
- Use `for i = 1, #arr do ... end` for sequences and `pairs()` for maps.
- Recoverable failure returns `nil, "reason"` or `false` with a localized message.
- Programmer errors use `assert()` or `error()`.

Call style:
- Use `:` only when the function expects `self`.
- Use `.` for plain functions.
- Never mechanically convert `.` and `:` without checking the function signature.

Naming:
- Public module tables and public exported methods use PascalCase.
- WoW event handler names stay uppercase.
- Local helpers and local variables use camelCase.
- Private cross-file package helpers use underscore-prefixed owner fields when needed.
- Avoid snake_case for new Lua names.

Canonical public API verbs:
- Queries: `Get`, `Find`, `Is`, `Can`
- Mutations: `Set`, `Add`, `Remove`, `Delete`, `Upsert`
- Lifecycle/UI: `Ensure`, `Bind`, `Localize`, `Request`, `RequestRefresh`, `Refresh`, `Toggle`, `Show`, `Hide`
- Exact hooks: `OnLoad`, `OnLoadFrame`, `AcquireRefs`, `BindHandlers`, `RefreshUI`

---

## 6) SavedVariables And Persistence (**BINDING**)

Persisted account keys:
- `KRT_Raids`
- `KRT_Players`
- `KRT_Reserves`
- `KRT_Warnings`
- `KRT_Spammer`
- `KRT_Options`

Policies:
- Treat fresh SavedVariables as strict mode.
- Keep `players[]` as the canonical persisted player store.
- Treat `_playersByName` as a derived runtime index/cache.
- Store only canonical restore-critical data.
- Avoid persisting duplicated, derived, or runtime-only fields.
- Use stable NIDs (`playerNid`, `bossNid`, `lootNid`) instead of volatile array indices.
- Use `Database.GetRaidStoreOrNil(contextTag, requiredMethods)` for optional raid-store access.

Options:
- `KRT_Options` uses strict nested schema 2 storage.
- Modules register defaults with `addon.Options.AddNamespace(...)`.
- Read via namespace `cfg:Get(...)`.
- Write via `cfg:Set(...)` or `addon.Options.Set(...)`.
- Do not write through `addon.options`.
- `debug` is runtime-only state under `addon.State.debugEnabled`.

---

## 7) UI Policy (**BINDING**)

- Prefer event-driven redraws. Avoid feature-frame polling with `OnUpdate`.
- Allowed `OnUpdate` exceptions: minimap drag, LibCompat internals, and shared refresher drivers.
- Use `addon.UI.Scaffold.DefineModule(cfg)` where feasible.
- Keep UI lifecycle state in `addon.UI.ModuleState`; local lifecycle variables use `uiState`.
- Modules implement hooks such as `AcquireRefs`, `BindHandlers`, `Localize`, `OnLoadFrame`, `RefreshUI`.
- Scaffold-generated methods own `BindUI`, `EnsureUI`, `Toggle`, `Show`, `Hide`, `RequestRefresh`, `MarkDirty`.
- Prefer the dominant `_G[frameName .. suffix]` named-frame access pattern.
- Prefer simple role-gated UI without extra disabled-action tooltips unless requested.
- Keep shared UI glue in `Init.lua` or `Modules/UI/*`; keep feature-specific UI in feature modules.
- In options panels, rows with action buttons must reserve a fixed-width right command column.
- Do not anchor button columns to variable-width or wrapped description text.
- Controller/Widget frame lifecycle should use `addon.UI.Scaffold.DefineModule(cfg)` or document why not.
- `addon.UI.ModuleState` uses canonical `Loaded`, `Bound`, `Localized`, `Dirty`, `Reason`, `FrameName`.
- `BindUI`, `EnsureUI`, `Toggle`, `Hide`, `RequestRefresh`, and `MarkDirty` are scaffold-owned.
- Use shared KRT semantic XML templates and `Modules/UI/*` helpers before feature-local UI styling.
- New shared XML templates keep the `KRT` prefix and use role names such as `Window`, `Panel`,
  `Dialog`, `ActionButton`, `ListScrollFrame`, `TextInput`, `TableRow`, or `HeaderRow`.
- Historical template names are retired; use semantic KRT templates in KRT-owned XML and Lua.
- New repeated list/table UIs should prefer `addon.UI.Lists`.
- Selectable row selected/focused visuals should use `addon.UI.Rows`.
- ScrollFrame tables use stable names: `FrameNameScrollFrame` and `FrameNameScrollFrameScrollChild`.
- Scroll children must have explicit synced width and calculated content height before refresh completes.
- Table rows use fixed row heights, fixed command columns, and scrollbar-aware right inset handling.
- EditBox widgets use KRT editbox templates, `autoFocus=false`, and shared `addon.UI.EditBoxes` helpers.
- Shared borders, spacing, row visuals, glow effects, and reusable primitives stay under `Modules/UI/*`.
- Feature files may compose UI pieces, but must not copy divergent border, spacing, or highlight systems.
- Services must not reference frames, Widgets, Controllers, `addon.UI.Scaffold`, or shared UI helper modules.

Logger visual direction:
- Wrath raid-log look with compact dark tables, yellow section titles, and green selected rows.
- Blizzard dialog frame, compact dark tables, yellow section titles, green selected rows.
- Default KRT buttons outside list panels.
- Loot item icons keep about `28x28` click target, centered `26x26` icon, and `32x32` quickslot border.

Glow effects:
- Keep implementation details in `Modules/UI/Effects.lua`.
- Keep `Modules/UI/Visuals.lua` focused on generic primitives and row visuals.
- Prefer clean border pulses tightly aligned to button borders.

---

## 8) Service And Feature Policies

Raid/capabilities:
- `addon.Services.Raid` owns capability queries and master-only guards.
- Looting flows require current Master Looter ownership.
- Leadership features may use raid leader/assistant authority where appropriate.
- LootCounter grouped announce/spam actions require raid leader/assistant permission in raid.

Chat/output:
- `addon.Services.Chat` owns announce/warn/chat-safe output.
- Prefer localized format strings over sentence concatenation.

Rolls:
- Roll-response lifecycle: `PASS` reversible, `CANCELLED` reversible, `TIMED_OUT` terminal.
- `INELIGIBLE` is recoverable only through eligibility refresh.
- Only eligible `ROLL` responses may enter the resolver.
- With `countdownRollsBlock=false`, late rolls stay visible with `OOT` but are excluded from resolution.
- `Rolls:GetDisplayModel().resolution` is a public service contract.

Loot:
- Auto-loot rules are suggestions only. Do not auto-award, auto-trade, or auto-assign unless requested.
- Passive Group Loot logging filters low-value DE/Greed drops such as greens, gems, and recipes by default.
- Keep loot-context internals under `Services/Loot/*`.
- Keep `Services/Loot/Service.lua` as the public facade.

Reserves:
- Keep Whisper SoftRes player handling out of `EntryPoints/SlashEvents.lua`.
- Put whisper parsing and response policy under Reserves/Chat service ownership.
- Gate replies behind config, valid reserve data, and ML/leader/assistant authority.

Logger:
- Logger UI-local selection/edit/popup glue stays private to `Controllers/Logger.lua`.
- Logger store/view/export/helpers/actions live under `Services/Logger/*`.
- Keep Logger-owned roster UI refresh logic in `Controllers/Logger.lua` via `RaidRosterDelta`.

---

## 9) Tooling And Checks

Prefer `rg`/`rg --files` for repository search.

Common gates:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Generated docs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

When editing `Services/Rolls/Service.lua` or `Controllers/Master.lua`, run:

```powershell
lua tests/release_stabilization_spec.lua
```

If XML frame names change, update `.luacheckrc` globals in the same change.

---

## 10) Release Policy

- Release metadata lives under `## Unreleased` in `!KRT/CHANGELOG.md`.
- Use `Release-Version: <version>`.
- Stable: `x.y.z`; internal/no publication: `x.y.z-alpha.N`; GitHub prerelease: `x.y.z-beta.N`.
- Publish only when the full SemVer increases.
- Patch for compatible fixes/polish.
- Minor for compatible features or meaningful UI/workflow additions.
- Major for breaking API/SavedVariables changes or required user migrations.
- Package only the addon folder `!KRT/`.
- Do not include repo-level docs/tooling files in release ZIPs.
- Keep release asset download/checksum instructions out of root `README.md`.
- Published `Included Commits` must always be computed from previous release tag to current release tag.
- Do not list release commits from branch tips, arbitrary SHAs, partial ranges, or non-tag refs.

---

## 11) Manual Smoke Checklist

- Login: no errors; `/krt` opens.
- Raid detection: instance/difficulty detected; current raid created; roster updates.
- Rolls: MS/OS/SR works; stable sorting; deterministic winner.
- Reserves: import/export; caps; roll gating consistent.
- Logger: loot entries append; filters/delete/selection highlight work.
- Master: award/trade tracking and multi-award work; `/krt counter` toggles Loot Counter.
- Warnings/Changes/Spammer: correct channels and throttling.
- Persistency: `/reload` keeps SavedVariables and expected state.
