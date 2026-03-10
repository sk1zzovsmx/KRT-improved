# UI Binding Rules

Status: active (binder removed).

Purpose:
- Keep XML as layout/template source.
- Keep wiring explicit in Lua modules.
- Remove the transitional binder stack (`Modules/UI/Binder/*`).

Rules:
1. Do not reintroduce `Modules/UI/Binder/*` or binder-like mapping tables.
2. Do not introduce new binder-like registries, parsers, or `CreateFrame` patching.
3. Keep XML layout-only: no `<Scripts>` or `<On...>` handler logic in UI XML files.
4. Bind scripts in module code with explicit `SetScript` calls.
5. Prefer `UIScaffold.BootstrapModuleUi(...)` + `Frames.MakeFrameGetter(...)` for frame lifecycle wiring.
6. Keep optional widgets behind `addon.UI:IsEnabled(widgetId)` and register exports with `addon.UI:Register`.
7. Keep services UI-free; only controllers/widgets should own frame script binding.

Notes:
- Binder files were removed from TOC/runtime.
- Keep UI wiring local to each module and idempotent.
