# KRT Architecture Layering

This document defines folder responsibilities and allowed dependencies.

## Layer map

1. `Modules/`, `Localization/`, `Templates.xml`: shared primitives.
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

## Automation

- Install repository hooks with `tools/install-hooks.ps1`.
- Pre-commit runs `tools/check-layering.ps1`, `tools/check-ui-binding.ps1`, and `tools/update-tree.ps1`.
