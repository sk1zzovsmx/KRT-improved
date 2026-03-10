# KRT Architecture Layering

This document defines folder responsibilities and allowed dependencies.

## Layer map

1. `Modules/`, `Localization/`, `UI/Templates/*.xml`: shared primitives.
2. `Init.lua`: bootstrap and global WoW event wiring.
3. `Services/`: runtime data/model modules, no parent-frame ownership.
4. `Controllers/`: parent owners (`Master`, `Logger`, `Warnings`, `Changes`, `Spammer`).
5. `Widgets/`: optional child frame controllers owned by a parent/feature.
6. `EntryPoints/`: slash/minimap routing only.
7. `UI/*.xml`, `KRT.xml`: frame definitions and include manifest.

## Dependency matrix

`Y` = allowed, `N` = disallowed, `Bus` = via `Bus.RegisterCallback` / `Bus.TriggerEvent`,
`Toggle` = explicit entrypoint exception.

| From \ To | Modules/Loc | Init.lua | Services | Controllers | Widgets | EntryPoints | UI/XML |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Modules/Loc | Y | N | N | N | N | N | N |
| Init.lua | Y | Y | Y | Y | N | N | N |
| Services | Y | N | Y | N | N | N | N |
| Controllers | Y | Y | Y | Bus | Y | N | Y |
| Widgets | Y | N | Y | Y (owner only) | Y | N | Y |
| EntryPoints | Y | N | N | Toggle | N | Y | N |

## Guardrails

- Services must not call parent controllers or touch parent frames.
- Services may use non-owning UI APIs only when needed (for example tooltip probes in item helpers).
- Controllers must not reference other parent owners or other parent frames.
- Upward communication should use the internal bus.
- Prefer existing events (`SetItem`, `RaidRosterDelta`, `AddRoll`, `LoggerSelectRaid`).
- Do not introduce new UI micro-events when existing events already model the flow.
- XML stays layout-only: no inline `<Scripts>`/`<On...>` handlers.

## UI Binding

- Do not reintroduce `Modules/UI/Binder/*` or binder-like mapping tables.
- Do not introduce binder registries, parser layers, or `CreateFrame` patching
  as a generic wiring mechanism.
- Bind scripts in module code with explicit `SetScript` calls.
- Prefer `UIScaffold.BootstrapModuleUi(...)` and
  `Frames.MakeFrameGetter(...)` for frame lifecycle wiring.
- Keep optional widgets behind `addon.UI:IsEnabled(widgetId)` and register
  exports with `addon.UI:Register`.
- Keep UI wiring local to the owning module and make it idempotent.
- `tools/check-ui-binding.ps1` enforces binder absence and blocks inline XML
  script handlers.

## Template Alignment

KRT follows the common WoW addon split, with repo-specific ownership choices:

- generic addon templates often use `Core/Init.lua`, but KRT keeps bootstrap
  ownership in root `Init.lua`
- `EntryPoints/Minimap.lua` owns minimap interactions
- `EntryPoints/SlashEvents.lua` owns slash command routing
- `!KRT/!KRT.toc` declares load order and SavedVariables, and `!KRT/KRT.xml`
  remains the UI include manifest

This keeps module ownership explicit without splitting bootstrap logic across
multiple entry files.

## Automation

- Install repository hooks with `tools/install-hooks.ps1`.
- Pre-commit runs `tools/check-toc-files.ps1`, `tools/check-layering.ps1`,
  `tools/check-ui-binding.ps1`, and `tools/update-tree.ps1`.
- When staged `.lua` files exist, pre-commit also runs the local Lua gates in
  check mode:
  - `tools/check-lua-syntax.ps1`
  - `luacheck --codes --no-color !KRT tools tests`
  - `tools/check-lua-uniformity.ps1`
  - `stylua --check !KRT tools tests`

## Related Docs

- `docs/LUA_WRITING_RULES.md`: canonical Lua syntax, naming, formatting, and
  local gate policy
- `docs/SV_SCHEMA.md`: SavedVariables inventory and ownership notes
- `docs/RAID_SCHEMA.md`: canonical persisted raid schema
- `docs/REFACTOR_RULES.md`: function ownership and deduplication workflow
- `docs/AGENT_SKILLS.md`: repo-local skill sync and Mechanic workflow
- `docs/KRT_MCP.md`: repo-local MCP server and tool inventory
