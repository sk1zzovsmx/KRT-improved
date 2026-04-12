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
  `addon.Services.Raid` is split across `!KRT/Services/Raid/*.lua` and loaded by TOC order.
  `State.lua` is the state/compat anchor file; the other files extend the same service table by domain
  (`Capabilities`, `Changes`, `Counts`, `Roster`, `LootRecords`, `Session`, `Boss`).
  `Services/Raid/Capabilities.lua` owns capability queries and the shared master-only access guard.
  `Services/Chat.lua` owns announce/warn output contracts.
  `addon.Services.Reserves` owns the canonical public reserves contract; its `.Service`
  field is a compatibility alias to the same table, not a second owner.
- `!KRT/Core/DB.lua`
  Owns the canonical public accessor facade for DB-manager-backed services on
  `addon.Core.*`; `addon.DB` remains the concrete namespace for DB submodules and
  manager state, not a parallel getter surface.
- `!KRT/Core/DBSchema.lua`
  Owns schema-version state while exposing the canonical public accessor on
  `addon.Core.GetRaidSchemaVersion`; `addon.DBSchema` is not a second parallel getter facade.
- `!KRT/Widgets/*.lua`
  Own child UI controllers under `addon.Widgets.*`.
- `!KRT/EntryPoints/*.lua`
  Own slash/minimap entrypoints.
- `!KRT/Modules/*.lua`
  Own reusable infra only, not parent feature logic.

Compatibility aliases (`addon.Master`, `addon.Logger`, `addon.Raid`, ...) are legacy adapters.
New call sites should use namespaced owners (`addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`).
Avoid root addon method facades for chat/capability contracts; the only intentional root-method
compatibility exception is `addon:Print` for `LibLogger-1.0`.

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
- EntryPoints should prefer `addon.Core.RequestControllerMethod(...)` for parent routing instead
  of open-coded controller lookup helpers.
- Capability checks and announce/warn output should target `addon.Services.Raid` and
  `addon.Services.Chat` (or their top-level alias tables), not root addon methods.
- Controller-local UI glue should stay local: avoid exporting selection handlers, popup save/fill
  helpers, row-hover glue, and similar file-local mechanics on controller public surfaces.
- Cross-file helpers that are still package-internal should move to underscore internal surfaces
  on the owner table, not remain public `*Internal` methods.

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

Use `tools/krt.py` as the canonical entrypoint. For the full command matrix and PowerShell fallbacks,
see `docs/DEV_CHECKS.md`.

Common examples:

```bash
python3 tools/krt.py repo-quality-check --check all
python3 tools/krt.py repo-quality-check --check layering
```

Windows equivalent:

```powershell
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py repo-quality-check --check layering
```

Use `--check all` for a fast repo-wide preflight; keep the narrower commands when you only need to
verify architecture-specific constraints during refactors.

## Related Docs

- `AGENTS.md` - binding architecture and coding policy
- `docs/OVERVIEW.md` - runtime ownership and module map
- `docs/LUA_WRITING_RULES.md` - Lua style and naming rules
- `docs/DEV_CHECKS.md` - quick checks and audit commands
- `docs/KRT_MCP.md` - MCP tools for repo workflows
- `docs/AGENT_SKILLS.md` - skill sync and Mechanic companion workflow
