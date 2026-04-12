# Technical Cleanup Workflow

Deterministic workflow for cleanup and normalization passes across KRT modules.

Use this document when the goal is technical cleanup, not behavior changes.

## 1. Goal

Keep cleanup work predictable, low-risk, and easy to verify.

This workflow is for:
- UI normalization
- API deduplication
- naming unification
- ownership cleanup
- XML structure cleanup
- stale helper removal

This workflow is not for:
- new user-facing features
- SavedVariables schema changes
- large behavior rewrites
- vendored library edits under `!KRT/Libs`

## 2. Core Policy

1. Lock behavior first, then clean structure.
2. Work one owner at a time.
3. Keep diffs local to the owning module and its directly owned XML.
4. Prefer canonical in-repo patterns over inventing new ones.
5. Split Lua cleanup and XML cleanup when mixing them would raise risk.
6. Run static gates before asking for in-game verification.
7. Ask for `/reload` after addon changes and wait for confirmation.

## 3. Cleanup Unit

The default cleanup unit is one owner module plus its directly owned files.

Examples:
- `Controllers/Master.lua` + `UI/Master.xml`
- `Controllers/Logger.lua` + `UI/Logger.xml`
- `Widgets/ReservesUI.lua` + `UI/Reserves.xml` + `UI/ReservesTemplates.xml`
- `Services/Reserves.lua` without unrelated UI work

Avoid mixed waves such as:
- multiple parent owners in one pass
- Services plus unrelated Controller rewrites
- runtime logic changes combined with large XML rewrites

## 4. Preflight

Before editing:

1. Read `AGENTS.md`.
2. Check module ownership in `docs/ARCHITECTURE.md`.
3. Check function ownership rules in `docs/REFACTOR_RULES.md`.
4. Inspect current worktree and avoid touching unrelated user changes.
5. Define the cleanup scope in one sentence:
   `Normalize UI lifecycle for Logger without behavior changes.`
6. Define non-goals in one sentence:
   `Do not change sorting, selection semantics, or layout.`

## 5. Discovery Pass

For the selected cleanup unit, map these first:

1. Owned Lua files.
2. Owned XML files.
3. Public APIs exported on `addon.*`.
4. Bus events consumed or triggered.
5. Frame names and named child access patterns.
6. SavedVariables touched by the module.
7. Existing tests or targeted gates for the area.

Useful repo checks:

```powershell
git status --short
rg "UIScaffold|MakeModuleFrameGetter|FrameName|RefreshUI|_ui" !KRT -g "*.lua"
rg "addon\\.(Master|Logger|Warnings|Changes|Spammer)" !KRT -g "*.lua"
rg "<Scripts>|<OnLoad>|<OnShow>|<OnClick>" !KRT/UI -g "*.xml"
```

### 5.1 API-Reduction Loop

When the goal is API deduplication or owner contraction, use this loop before
editing code:

1. Regenerate `docs/FUNCTION_REGISTRY.csv`.
2. Regenerate `docs/FN_CLUSTERS.md`.
3. Regenerate `docs/API_REGISTRY*.csv` and
   `docs/API_NOMENCLATURE_CENSUS.md`.
4. Regenerate `docs/TREE.md` if file ownership or structure may matter.
5. Split findings into:
   - exact or near clones that can merge now
   - duplicated public facades or pass-through APIs
   - simple name collisions with different responsibilities
6. Pick one canonical owner per behavior and migrate call sites there before
   deleting wrappers.

Run the catalog scripts sequentially: `fnmap-inventory` -> `fnmap-classify` ->
`fnmap-api-census` -> `update-tree`. Do not parallelize `inventory` and `classify`.

Do not treat raw `name-collision` counts as removal candidates without owner and
behavior review.

## 6. Module-Type Workflow

### 6.1 Controllers and Widgets

Target outcome:
- canonical `module._ui` state
- canonical `UIScaffold.DefineModuleUi(...)` contract
- clear frame ownership
- event-driven refresh flow

Preferred contract:
- `OnLoad`
- `AcquireRefs`
- `BindHandlers`
- `Localize`
- `OnLoadFrame`
- `RefreshUI` or `Refresh`

Checklist:

1. Centralize frame lookup with `feature.MakeModuleFrameGetter(...)`.
2. Keep UI state under:
   `module._ui = { Loaded, Bound, Localized, Dirty, Reason, FrameName }`
3. Move idempotent bindings into scaffold hooks instead of ad-hoc `OnLoad` branches.
4. Use named-part helpers instead of repeating `_G[frameName .. suffix]` everywhere.
5. Keep refresh entrypoints explicit:
   `RefreshUI`, `Refresh`, `RequestRefresh`, `MarkDirty`
6. Remove duplicate local flags when `_ui` or scaffold state already owns them.
7. Keep XML layout-only and bind scripts in Lua.

### 6.2 Services

Target outcome:
- pure runtime/data ownership
- no parent frame reach-through
- deterministic data helpers

Checklist:

1. Remove direct parent references and frame access.
2. Use `Core.GetRaidStoreOrNil(...)` instead of ad-hoc nil guards when applicable.
3. Deduplicate helper functions and keep one canonical owner.
4. Keep sorting deterministic with explicit tie-breakers.
5. Avoid UI delegation and `addon.*UI` calls.
6. Keep runtime caches derived and rebuildable.

### 6.3 EntryPoints

Target outcome:
- routing only
- no feature ownership drift

Checklist:

1. Keep slash handling in `EntryPoints/SlashEvents.lua`.
2. Keep minimap behavior in `EntryPoints/Minimap.lua`.
3. Only call parent toggle or public routing APIs.
4. Do not duplicate controller lookup helpers.

### 6.4 Infrastructure Modules

Target outcome:
- one canonical owner per generic helper
- no feature-specific leakage into `Modules/`

Checklist:

1. Keep helpers generic and reusable.
2. Extract only after repeated usage proves it is shared.
3. Do not revive catch-all utility files.
4. Preserve plain-function style on infra namespaces.

### 6.5 XML Files

Target outcome:
- layout-only XML
- readable structure
- no hidden behavior in markup

Checklist:

1. No inline `<Scripts>` or `<On...>` handlers.
2. Keep frame names unchanged unless there is a strong reason.
3. Remove empty wrappers and stale comments when safe.
4. Normalize indentation and closing-tag alignment.
5. Do not change anchors, sizes, or inherits during cleanup-only passes.
6. Keep templates generic and feature files feature-local.

## 7. Execution Order

Use this order unless the module clearly requires a different one:

1. Normalize Lua ownership and lifecycle.
2. Run local static gates.
3. If stable, do XML cleanup in a separate pass.
4. Re-run XML validation and UI-binding checks.
5. Ask for `/reload`.
6. Do in-game smoke verification with the user.

Rationale:
- behavior risk is easier to isolate in Lua-only waves
- XML-only waves are easier to review once runtime ownership is already stable

For API-reduction passes, insert this mandatory checkpoint after each stage:

1. update the affected narrative docs under `docs/`
2. regenerate `fnmap`/API catalogs
3. rerun the relevant repo checks
4. only then continue to the next stage

## 8. Validation Matrix

Run the minimum matching set for the files you touched.

### 8.1 Always Relevant

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-layering.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-ui-binding.ps1
```

### 8.2 If Lua Changed

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
luacheck --codes --no-color !KRT tools tests
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1
stylua --check !KRT tools tests
```

For small waves, targeted `luacheck` on touched files is acceptable during iteration.
Run the broader local gates before closing a larger cleanup batch.

### 8.3 If `Controllers/Master.lua` or `Services/Rolls.lua` Changed

```powershell
py -3 tools/krt.py run-release-targeted-tests
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```

Prefer the `tools/krt.py` wrapper for the default path; keep the PowerShell command for script-level control.

### 8.4 If XML Changed

```powershell
rg "<Scripts>|<OnLoad>|<OnShow>|<OnClick>" !KRT/UI -g "*.xml"
```

Also validate that edited XML still parses cleanly.

### 8.5 If TOC or File Inventory Changed

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
```

## 9. In-Game Verification

After addon changes:

1. Ask the user to run `/reload`.
2. Wait for confirmation.
3. Smoke-test only the touched owner flow first.
4. Expand to neighboring flows only if the owner flow is stable.

Recommended smoke scope by module type:

- `Master`: select item, roll state, countdown, assign buttons, reroll, dropdowns
- `Logger`: tab switch, list selection, popup add/edit, export
- `Warnings` and `Changes`: message edit, announce path, list refresh
- `Spammer`: preview, start, stop, pause, channels, duration
- `ReservesUI`: list render, import, filters, reserve rows
- `Config`: option toggles, localization, open-close persistence
- `LootCounter`: toggle, count update, restore from persisted raid

## 10. Done Definition

A cleanup wave is done only when all of these are true:

1. Scope stayed inside the selected cleanup unit.
2. No intentional behavior changes slipped in undocumented.
3. Static gates relevant to the touched files passed.
4. XML stayed layout-only.
5. In-game reload completed without new errors.
6. The user confirmed the touched flow is stable.

## 11. Suggested Work Order for KRT

Use this default order for future cleanup programs:

1. Controllers and Widgets with the heaviest UI ownership.
2. Their directly owned XML files.
3. Services that still contain UI leakage or duplicate helpers.
4. EntryPoints with routing drift.
5. Shared Modules with duplicate or unclear ownership.
6. Tree-wide naming and dedup follow-up only after owner cleanup is stable.

## 12. Cleanup Ticket Template

Use this template before each cleanup wave:

```text
Scope:
Non-goals:
Owner files:
Owned XML:
Public APIs to preserve:
SavedVariables to preserve:
Static checks:
In-game smoke path:
```

## Related Docs

- `docs/ARCHITECTURE.md`
- `docs/TECH_CLEANUP_BACKLOG.md`
- `docs/REFACTOR_RULES.md`
- `docs/LUA_WRITING_RULES.md`
- `docs/DEV_CHECKS.md`
