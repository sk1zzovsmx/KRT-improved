# KRT Architecture Layering

This document defines folder responsibilities and allowed dependencies.

## Layer map

1. `Modules/`, `Localization/`, `Templates.xml`: shared primitives.
2. `KRT.lua`: bootstrap and global event wiring.
3. `Services/`: runtime data/model modules, no parent-frame ownership.
4. `Controllers/`: parent owners (`Master`, `Logger`, `Warnings`, `Changes`, `Spammer`).
5. `Widgets/`: child frame controllers owned by a parent/feature.
6. `EntryPoints/`: slash/minimap routing only.
7. `UI/*.xml`, `KRT.xml`: frame definitions and include manifest.

## Dependency matrix

`Y` = allowed, `N` = disallowed, `Bus` = via `StdFacade.triggerEvent/registerCallback`, `Toggle` = exception.

| From \ To | Modules/Loc | KRT.lua | Services | Controllers | Widgets | EntryPoints | UI/XML |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Modules/Loc | Y | N | N | N | N | N | N |
| KRT.lua | Y | Y | Y | Y | N | N | N |
| Services | Y | N | Y | N | N | N | N |
| Controllers | Y | Y | Y | Bus | Y | N | Y |
| Widgets | Y | N | Y | Y (owner only) | Y | N | Y |
| EntryPoints | Y | N | N | Toggle | N | Y | N |

## Guardrails

- Services must not call parents or touch parent frames.
- Services may use local non-owning UI APIs when needed (for example tooltip probes).
- Controllers must not reference other parent owners or other parent frames.
- Upward communication should use the internal bus.
- Prefer existing events (`SetItem`, `RaidRosterDelta`, `AddRoll`, `LoggerSelectRaid`).
- No new UI micro-events when an existing event already models the refresh.
- `tools/check-layering.ps1` enforces service and controller ownership checks.

## Automation

- Install repository hooks with `tools/install-hooks.ps1`.
- Pre-commit runs `tools/check-layering.ps1` and `tools/update-tree.ps1`.
