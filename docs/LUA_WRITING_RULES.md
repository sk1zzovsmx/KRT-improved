# Lua Writing Rules

Canonical writing rules for KRT-owned Lua code.

## Scope

Applies to:

- `!KRT/**/*.lua` (excluding vendored libs in `!KRT/Libs/**`)
- `tools/**/*.lua`
- `tests/**/*.lua`

Goals:

- predictable API naming across Controllers/Services/Widgets/Core/Modules
- consistent file structure for easier review and refactor safety
- WoW 3.3.5a compatibility without behavior regressions

## 1) File Contract

Use this header in KRT addon files:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()
```

Feature files under `Controllers/`, `Services/`, `Widgets/`, `EntryPoints/` should keep this section order:

1. `-- ----- Internal state ----- --`
2. `-- ----- Private helpers ----- --`
3. `-- ----- Public methods ----- --`

## 2) Naming Policy

### Public and cross-module APIs

Use `PascalCase` for exported/public APIs:

- `module:*` on Controllers/Services/Widgets/EntryPoints
- infra namespaces (`Core`, `Bus`, `Frames`, `UIScaffold`, `UI`, `ListController`, ...)
- structured owners (`Store:*`, `View:*`, `Actions:*`, `Box:*`)

Examples:

- `module:GetDisplayModel()`
- `Core.GetRaidStoreOrNil(tag, requiredMethods)`
- `UI.Refresh()`

### Private helpers and locals

Use `camelCase` for file-local/private helpers, callbacks, and temporary variables.
Do not introduce new snake_case private names.

### Allowed exceptions

- WoW event handlers stay UPPER (`ADDON_LOADED`, `RAID_ROSTER_UPDATE`, ...)
- constants stay `UPPER_SNAKE_CASE`
- Lua metamethods stay unchanged (`__index`, `__call`, ...)
- canonical UI hook names remain valid (`AcquireRefs`, `BindHandlers`, `Localize`, `OnLoadFrame`, `RefreshUI`)

### Public API verb taxonomy (new/renamed APIs)

- Queries: `Get*`, `Find*`, `Is*`, `Can*`
- Mutations: `Set*`, `Add*`, `Remove*`, `Delete*`, `Upsert*`
- Lifecycle/UI: `Ensure*`, `Bind*`, `Localize*`, `Request*`, `RequestRefresh*`, `Refresh*`,
  `Toggle*`, `Show*`, `Hide*`
- Exact lifecycle hooks: `OnLoad`, `OnLoadFrame`, `AcquireRefs`, `BindHandlers`, `RefreshUI`, `Refresh`

## 3) `:` vs `.` Call Style

- Use `:` only for true methods that expect `self`.
- Use `.` for plain functions.
- Never bulk-convert call style without checking function signatures.

Examples:

```lua
function module:Refresh() ... end
function UIScaffold.DefineModuleUi(cfg) ... end
```

## 4) Formatting and Layout

- Lua runtime target: 5.1
- indentation: 4 spaces
- no trailing whitespace
- prefer ASCII in comments/logs/code
- line width: keep edited lines around 120 when practical
- formatter hard limit remains 180 (see `.stylua.toml`)

Prefer stable, scoped diffs over mass reformatting untouched legacy code.

## 5) UI and Layering Expectations

- Services remain UI-free: no parent frame ownership, no direct UI lifecycle control.
- XML is layout-only: no inline `<Scripts>` / `<On...>` handlers.
- For Controllers/Widgets, prefer `UIScaffold.DefineModuleUi(cfg)` as canonical UI contract.
- Keep module-local UI state under `module._ui` with uniform fields.
- Prefer event-driven redraw (`RequestRefresh`/`Refresh`) over polling `OnUpdate` loops.

## 6) Local Quality Gates

Canonical cross-platform entrypoint:

```bash
python3 tools/krt.py repo-quality-check --check all
```

Windows equivalent:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

For the expanded per-check command list and direct PowerShell fallbacks, see `docs/DEV_CHECKS.md`.

Direct tool commands still supported:

- `luacheck --codes --no-color !KRT tools tests`
- `stylua --check !KRT tools tests`
- `py -3 tools/krt.py install-hooks`

## 7) Incremental Rollout Rules

1. New files should comply fully.
2. Touched code should move toward canonical style in touched areas.
3. Avoid mass public API renames without migration intent.
4. Prefer deterministic refactors over compatibility shims that keep duplicate naming alive.
5. Keep behavior and SavedVariables compatibility intact.
