# KRT Architecture (Light Guide)

This document summarizes the folder layout and layering rules used by KRT.
Scope is documentation only; runtime behavior is defined by code and `AGENTS.md` binding sections.

## Repo Tree (`!KRT/`)

```text
!KRT/
  Controllers/   # Parent/top-level controllers and orchestration
  Services/      # Data/model/business logic (no Parent UI ownership)
  Widgets/       # UI controllers and child widgets
  EntryPoints/   # Slash/minimap entrypoints and command routing
  UI/            # XML frames/templates
  Modules/       # Shared utilities/constants/static helpers
  Localization/  # addon.L and addon.Diagnose strings/templates
  Libs/          # Vendored libs (LibStub, LibCompat, etc.)
```

## Folder Responsibilities

| Folder | Responsibility | Allowed dependencies |
| --- | --- | --- |
| `Controllers/` | Parent logic, orchestration, UI ownership for parent frames | `Services`, `Widgets`, `Modules`, bus |
| `Services/` | Domain data/model logic and mutations | `Modules`, `Localization`, other services |
| `Widgets/` | Frame controllers, row rendering, child widget behavior | Owner parent, `Modules`, bus |
| `EntryPoints/` | User entrypoints (`/krt`, minimap clicks) | Parent `:Toggle()`, `Modules` |
| `UI/` | XML manifests/templates only | XML include graph only |
| `Modules/` | Shared helpers/constants/events/list controllers | No feature ownership |
| `Localization/` | User and diagnose strings | Referenced by all runtime layers |
| `Libs/` | Third-party libs | Loaded by `.toc` order |

## Layering Rules (Binding Recap)

- Parent controllers are: `MasterLoot` (`addon.Master`), `Logger`, `Warnings`, `Changes`, `Spammer`.
- Services must not reference Parents and must not touch Parent frames.
- Widgets attach only Parent -> Child. Child code must not `hooksecurefunc` parent lifecycle.
- EntryPoints may call `Parent:Toggle()` directly (`SlashEvents`, `Minimap` exception).
- Upward communication goes through internal bus:
  `Utils.registerCallback(...)` and `Utils.triggerEvent(...)`.
- Do not add new globals beyond intentional addon globals and XML frame globals.

## Core Event Contracts (Reused Events)

- `SetItem(itemLink, itemData?)`
- `RaidRosterDelta(delta, rosterVersion, raidId)`
- `AddRoll(name, roll, ...)`
- `LoggerSelectRaid(raidId, reason?)` where `reason` can be `"ui"` or `"sync"`
- `ReservesDataChanged(reason?, raidId?)`

Payload details can be extended compatibly with optional trailing args.
Do not introduce new nominal events when an existing event already models the flow.

## Dev Checks

See `DEV_CHECKS.md` for copy/paste layering checks and quick validation commands.
