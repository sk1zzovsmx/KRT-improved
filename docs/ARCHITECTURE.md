# KRT Architecture and Layering

This document defines runtime ownership, dependency directions, and UI/XML binding rules.
Use this as the architecture map; use `AGENTS.md` for binding policy.

## Canonical Layer Stack

The canonical layer order is declared in `!KRT/!KRT.toc`.

1. `Libs/*`
   Third-party runtime libraries loaded first.
2. `Init.lua` + `Core/DB*.lua`
   Unified bootstrap, shared namespaces, legacy alias proxy, DB bootstrap.
3. `Localization/*`
   User strings (`addon.L`) and diagnose templates (`addon.Diagnose`).
4. `UI/Templates/Common.xml`
   Shared XML templates only.
5. `Modules/*`
   Shared infra (`Events`, `Bus`, `Item`, `Sort`, `Frames`, `UIScaffold`, `UI` facade, ...).
6. `Core/DBRaid*.lua`, `Services/*`, `Controllers/*`, `Widgets/*`, `EntryPoints/*`
   Runtime feature implementation and entrypoints.
7. `KRT.xml` -> `UI/*.xml`
   UI include manifest and concrete frame layout files.

## Runtime Ownership Map

- `!KRT/Init.lua`
  Owns shared bootstrap namespaces (`addon.Core`, `addon.State`, `addon.Events`, ...)
  and global WoW event wiring.
- `!KRT/Controllers/*.lua`
  Own top-level parent feature modules under `addon.Controllers.*`.
- `!KRT/Services/*.lua`
  Own runtime model/service logic under `addon.Services.*`.
- `!KRT/Widgets/*.lua`
  Own child UI controllers under `addon.Widgets.*`.
- `!KRT/EntryPoints/*.lua`
  Own slash/minimap entrypoints.
- `!KRT/Modules/*.lua`
  Own reusable infra only, not parent feature logic.

Compatibility aliases (`addon.Master`, `addon.Logger`, `addon.Raid`, ...) are legacy adapters.
New call sites should use namespaced owners (`addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`).

## Dependency Rules

`Y` = allowed direct call/reference, `Bus` = event-based only, `Toggle` = explicit exception.

| From \ To | Modules/Loc | Init.lua | Services | Controllers | Widgets | EntryPoints | UI/XML |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Modules/Loc | Y | N | N | N | N | N | N |
| Init.lua | Y | Y | Y | Y | N | N | N |
| Services | Y | N | Y | N | N | N | N |
| Controllers | Y | Y | Y | Bus | Y (owned) | N | Y |
| Widgets | Y | N | Y | Y (owner only) | Y | N | Y |
| EntryPoints | Y | N | N | Toggle (`Parent:Toggle`) | N | Y | N |

### Guardrails

- Services must not reference parent owners or parent frames.
- Services must not own frame lifecycle (`OnLoad`, `Refresh`, `SetScript`, `Show`, `Hide`).
- Controllers must not reference other parent owners directly.
- Upward communication should use `addon.Bus` and canonical event names from `Modules/Events.lua`.
- Prefer existing internal events (`SetItem`, `RaidRosterDelta`, etc.) over new micro-events.

## UI/XML Binding and Template Policy

- XML is layout-only:
  no `<Scripts>` and no `<On...>` blocks in `!KRT/UI/*.xml` or `!KRT/UI/Templates/*.xml`.
- Do not reintroduce `Modules/UI/Binder/*` or binder-style mapping registries.
- UI script wiring belongs in Lua via explicit `SetScript`/handler binding in owning modules.
- For Controllers/Widgets, prefer `UIScaffold.DefineModuleUi(cfg)` as the canonical lifecycle contract.
- Modules should implement UI hooks only:
  `AcquireRefs`, `BindHandlers`, `Localize`, `OnLoadFrame`, `RefreshUI`/`Refresh`.
- Scaffold-generated methods own shared lifecycle methods:
  `BindUI`, `EnsureUI`, `Toggle`, `Show`, `Hide`, `RequestRefresh`, `MarkDirty`.
- Keep UI cache/state schema uniform under `module._ui`.
- Optional widget routing goes through `addon.UI` (`Modules/UI/Facade.lua`) + `addon.Features`.

## Quick Layering Verification

Cross-platform entrypoint (`tools/krt.py`):

```bash
python3 tools/krt.py repo-quality-check --check layering
python3 tools/krt.py repo-quality-check --check ui_binding
python3 tools/krt.py repo-quality-check --check lua_uniformity
```

Windows equivalents:

```powershell
py -3 tools/krt.py repo-quality-check --check layering
py -3 tools/krt.py repo-quality-check --check ui_binding
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Direct PowerShell fallback (when needed):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-layering.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-ui-binding.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1
```

## Related Docs

- `AGENTS.md` - binding architecture and coding policy
- `docs/OVERVIEW.md` - runtime ownership and module map
- `docs/LUA_WRITING_RULES.md` - Lua style and naming rules
- `docs/DEV_CHECKS.md` - quick checks and audit commands
- `docs/KRT_MCP.md` - MCP tools for repo workflows
- `docs/AGENT_SKILLS.md` - skill sync and Mechanic companion workflow
