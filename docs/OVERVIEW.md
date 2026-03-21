# KRT Runtime Overview

Purpose: quick orientation for contributors who need current runtime ownership without scanning
all binding details first.

For binding rules and invariants, see `AGENTS.md`.
For architecture guardrails, see `docs/ARCHITECTURE.md`.

## At a Glance

- Runtime target: WoW 3.3.5a (`Interface: 30300`), Lua 5.1.
- Addon folder: `!KRT/` (leading `!` is intentional).
- Unified bootstrap ownership is in `!KRT/Init.lua`.
- Runtime modules are split into `Controllers/`, `Services/`, `Widgets/`, and `EntryPoints/`.
- Shared infra is in `!KRT/Modules/`.
- XML is layout-only under `!KRT/UI/`, included through `!KRT/KRT.xml`.

## Bootstrap Ownership (`Init.lua`)

`Init.lua` owns initialization of shared namespaces and runtime state roots:

- `addon.Core`
- `addon.L`
- `addon.Diagnose`
- `addon.State`
- `addon.C`
- `addon.Events` (`Internal` + forwarded `Wow` names)
- `addon.Controllers`, `addon.Services`, `addon.Widgets`
- compatibility alias proxy (`addon.Master`, `addon.Logger`, `addon.Raid`, ...)

`Init.lua` also owns global WoW event wiring and bus forwarding.

## Runtime Module Map

### Controllers (`addon.Controllers.*`)

Top-level parent owners:

- `addon.Controllers.Master`
- `addon.Controllers.Logger`
- `addon.Controllers.Warnings`
- `addon.Controllers.Changes`
- `addon.Controllers.Spammer`

### Services (`addon.Services.*`)

Runtime data/model/service modules:

- `addon.Services.Raid`
- `addon.Services.Chat`
- `addon.Services.Rolls`
- `addon.Services.Loot`
- `addon.Services.Debug`
- `addon.Services.Reserves` (`.Service` sub-owner for reserves store/index/import)

### Widgets (`addon.Widgets.*`)

Feature UI controllers:

- `addon.Widgets.LootCounter`
- `addon.Widgets.ReservesUI`
- `addon.Widgets.Config`

### EntryPoints

Entrypoints stay narrow:

- `addon.Minimap` (`EntryPoints/Minimap.lua`)
- slash command routing (`EntryPoints/SlashEvents.lua`)

### Shared Modules

Common infra under `!KRT/Modules/`:

- Data/utility: `Events`, `Strings`, `Item`, `Time`, `Sort`, `Comms`, `Base64`, `Colors`
- UI infra: `Frames`, `UIScaffold`, `ListController`, `MultiSelect`, `UI` facade, `UIEffects`
- Messaging: `Bus`
- Feature toggles: `Features`

## Public API Notes

- Canonical owners are namespaced (`addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`).
- Legacy top-level aliases (`addon.Master`, `addon.Logger`, ...) are compatibility shims.
- In debug mode, alias reads are intentionally warned to prevent new alias call sites.

## Event and Refresh Flow

- WoW events are received in `Init.lua`.
- `Init.lua` forwards domain events through `addon.Bus`.
- Services process model/runtime state.
- Controllers and Widgets refresh UI on demand (`RequestRefresh`/`Refresh`), not by polling.

## SavedVariables (Account Scope)

Declared in `!KRT/!KRT.toc`:

- `KRT_Raids`
- `KRT_Players`
- `KRT_Reserves`
- `KRT_Warnings`
- `KRT_Spammer`
- `KRT_Options`

Avoid key/shape breaks without migration and changelog notes.

## Placement Guide for New Code

- Parent feature logic -> `Controllers/`
- Runtime model/state logic -> `Services/`
- Feature UI controllers -> `Widgets/`
- Slash/minimap routing -> `EntryPoints/`
- Generic reusable helpers/constants -> `Modules/`

When in doubt, keep behavior ownership explicit and route cross-layer notifications through `addon.Bus`.
