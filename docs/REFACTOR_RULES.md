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
3. New code should target owner modules directly, not deprecated `Utils.*` facades.

## PR Checklist

1. Run `tools/check-layering.ps1`.
2. Run quick duplicate checks from `DEV_CHECKS.md` (function unification section).
3. If function ownership changed, regenerate:
   - `docs/FUNCTION_REGISTRY.csv`
   - `docs/FUNCTION_REGISTRY.md`
   - `docs/FN_CLUSTERS.md`
4. Update this policy and deprecation map when introducing new compat wrappers.

## Canonical Ownership (Quick Wins)

- `Core.getFeatureShared`: `!KRT/Core/Init.lua`
- `Core.ensureLootRuntimeState`: `!KRT/Core/Init.lua`
- `Core.getController`: `!KRT/Core/Init.lua`
- Reserves formatters: `!KRT/Services/Reserves.lua`
- EntryPoint controller lookup: `Core.getController(name)`
- UI primitives: `!KRT/Modules/UI/Visuals.lua`
- UI row visuals: `!KRT/Modules/UI/Visuals.lua`
- UI scaffold orchestration: `!KRT/Modules/UI/Frames.lua` (`addon.UIScaffold.*`)
- Binder map datasets: `!KRT/Modules/UI/Binder/Map.lua`
- Binder arg-token helpers: `trimBinderToken` / `splitCommaArgs` in `!KRT/Modules/UI/Binder/UIBinder.lua`
