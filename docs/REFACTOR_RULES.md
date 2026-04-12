# Refactor Rules

Permanent guardrails for function mapping and unification work.

## Duplicate Prevention

1. Before adding a helper/function, search existing code with `rg`.
2. Same name in different modules is allowed only for standard UI APIs:
   `OnLoad`, `Refresh`, `Toggle`, `Hide`, `Show`, `Select`, `Edit`, `Delete`, `Clear`, `Announce`.
3. If a generic helper is duplicated twice, extract it on the third usage.
4. Keep a single owner per shared function; compat aliases must be explicit.

## Compat and Deprecation

1. Compat wrappers must be marked `@compat`.
2. Deprecated compat wrappers must be marked `@deprecated use addon.<Owner>.X`.
3. New code should target owner modules directly, not legacy aliases/facades.
4. `addon:Print` is the only accepted root-method compatibility hook; do not reintroduce
   root addon method facades for chat/capability contracts.
5. Keep Logger UI-local selection/edit/popup glue private; do not expose it as public
   controller API unless another module genuinely depends on that contract.
6. If a helper crosses files but stays package-internal, expose it as an
   underscore-prefixed owner-table field or keep it local; do not publish
   `*Internal` methods as public API.

## PR Checklist

1. Run `tools/check-layering.ps1`.
2. When touching Lua, run the canonical local Lua gates:
   - `tools/check-lua-syntax.ps1`
   - `luacheck --codes --no-color !KRT tools tests`
   - `tools/check-lua-uniformity.ps1`
   - `stylua --check !KRT tools tests`
3. Run quick duplicate checks from `docs/DEV_CHECKS.md` (function unification section).
4. If function ownership changed, regenerate:
   - `docs/FUNCTION_REGISTRY.csv`
   - `docs/FN_CLUSTERS.md`
   Commands:
   - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1`
   - `powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1`
5. Update this policy when introducing new compat wrappers.

## Canonical Ownership (Quick Wins)

- `Core.GetFeatureShared`: `!KRT/Init.lua`
- `Core.EnsureLootRuntimeState`: `!KRT/Init.lua`
- `Core.GetController`: `!KRT/Init.lua`
- DB manager-backed accessors: `!KRT/Core/DB.lua` via `addon.Core.*`
- Raid schema version accessor: `!KRT/Core/DBSchema.lua` via `addon.Core.GetRaidSchemaVersion`
- Chat announce/warn output: `!KRT/Services/Chat.lua` via `addon.Services.Chat.*`
- Raid capability queries and ML guard: `!KRT/Services/Raid/Capabilities.lua` via
  `addon.Services.Raid.*`
- Logger controller public surface: lifecycle/state + cross-module actions only;
  keep file-local UI glue private inside `!KRT/Controllers/Logger.lua`
- Package-internal Logger store resolve helpers: internal underscore surface only
- Package-internal Raid roster/runtime helpers: internal underscore surface only
- Package-internal Reserves pending/import-cache helpers: internal underscore surface only
- Master button/dropdown/cursor glue: private unless explicitly consumed by tests or
  another owner
- Reserves formatters: `!KRT/Services/Reserves.lua`
- EntryPoint controller lookup: `Core.GetController(name)`
- UI primitives: `!KRT/Modules/UI/Visuals.lua`
- UI row visuals: `!KRT/Modules/UI/Visuals.lua`
- UI scaffold orchestration: `!KRT/Modules/UI/Frames.lua` (`addon.UIScaffold.*`)
- Widget facade ownership: `!KRT/Modules/UI/Facade.lua` (`addon.UI.*`)
- Item link/tooltip helpers: `!KRT/Modules/Item.lua` (`addon.Item.*`)
