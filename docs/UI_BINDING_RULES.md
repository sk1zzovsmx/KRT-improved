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
5. Use this per-window pattern:
   - `AcquireRefs(frame) -> refs`
   - `BindUI()` (idempotent; stores `self.frame/self.refs`)
   - `EnsureUI()` (bind once)
   - `Open/Toggle` must call `EnsureUI()` before `Show()`

Notes:
- Binder files were removed from TOC/runtime.
- Keep UI wiring local to each module via `BindUI/EnsureUI`.
