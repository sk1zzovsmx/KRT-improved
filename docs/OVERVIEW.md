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

- `addon.Database`
- `addon.L`
- `addon.Diagnose`
- `addon.State`
- `addon.C`
- `addon.Events` (`Internal` + forwarded `Wow` names)
- `addon.Controllers`, `addon.Services`, `addon.Widgets`

`Init.lua` also owns global WoW event wiring and bus forwarding.
Modules consume shared dependencies through `addon.Database.GetFeatureShared()`.
Service submodules bootstrap owner tables through `feature.EnsureServiceNamespace(...)`
so namespace creation stays centralized with the rest of bootstrap.
`Database/DBOptions.lua` owns `addon.Options`, namespaced defaults, and strict schema-2 storage.

## Runtime Module Map

### Controllers (`addon.Controllers.*`)

Top-level parent owners:

- `addon.Controllers.Master`
- `addon.Controllers.Logger`
- `addon.Controllers.Warnings`
- `addon.Controllers.Spammer`

### Services (`addon.Services.*`)

Runtime data/model/service modules:

- `addon.Services.Raid` (split owner across `Services/Raid/*.lua`)
- `addon.Services.Chat`
- `addon.Services.Rolls` (public facade in `Services/Rolls/Service.lua`; internal helpers in
  `Services/Rolls/Countdown.lua`, `Services/Rolls/Sessions.lua`, `Services/Rolls/History.lua`,
  `Services/Rolls/Responses.lua`, `Services/Rolls/Strategies.lua`, `Services/Rolls/Resolution.lua`,
  `Services/Rolls/Display.lua`)
- `addon.Services.Loot` (public API in `Services/Loot/Service.lua`; internal loot-context/rule helpers in
  `Services/Loot/*.lua`)
- `addon.Services.Debug`
- `addon.Services.Reserves` (public facade in `Services/Reserves.lua`; internal import, alias,
  grouped-display, runtime sync, and whisper-response helpers in
  `Services/Reserves/{Import,Aliases,Display,Sync,Chat}.lua`)
- `addon.Services.Logger` (Logger Store/View/Export/Helpers/Actions service tables consumed by
  `Controllers/Logger.lua`)

`addon.Services.Raid` is composed by:
- `Services/Raid/State.lua` (core raid state + raid-side loot/boss coordination contracts)
- `Services/Raid/Capabilities.lua` (role/capability policy + shared master-only guard)
- `Services/Raid/Counts.lua` (loot counter operations)
- `Services/Raid/Roster.lua` (live roster tracking and player lookups)
- `Services/Raid/Attendance.lua` (per-player attendance ledger from roster deltas)
- `Services/Raid/LootRecords.lua` (loot-record query helpers)
- `Services/Raid/Session.lua` (raid session checks/scheduling + boss query/icon helpers)

`addon.Services.Loot` internal runtime helpers are composed by:
- `Services/Loot/Context.lua` (`LootContext` normalization/projection helpers)
- `Services/Loot/State.lua` (`activeLoot` + `lootContext` session helpers + loot
  roll-session boss-context state)
- `Services/Loot/Snapshots.lua` (loot-window item snapshot state)
- `Services/Loot/PendingAwards.lua` (pending-award lifecycle and consume/refresh policy)
- `Services/Loot/PassiveGroupLoot.lua` (passive group-loot parser/state/winner helpers)
- `Services/Loot/Tracking.lua` (runtime tracking/debug snapshot builders)
- `Services/Loot/Workflow.lua` (transient loot-flow state and diagnostic snapshots)
- `Services/Loot/Receipts.lua` (parsed loot event classification)
- `Services/Loot/Records.lua` (canonical loot-record materialization)
- `Services/Loot/Reconcile.lua` (trade-only fallback merge and passive duplicate reconciliation)
- `Services/Loot/Rules.lua` (suggestion-only auto-loot rule classifier)
- `Services/Loot/DistributionSession.lua` (Master-owned compact `KRTDist` item/roll/done session sync;
  protocol v2 adds snapshots, ticks, tie state, and awarded state)

`addon.Services.Rolls` internal runtime helpers are composed by:
- `Services/Rolls/Countdown.lua` (countdown start/stop/tick runtime logic)
- `Services/Rolls/Sessions.lua` (roll-session lifecycle, tie-reroll state, and current-roll context helpers)
- `Services/Rolls/History.lua` (raw roll entries, per-item trackers, and local roll-state helpers)
- `Services/Rolls/Responses.lua` (response lifecycle, eligibility, and incoming-roll materialization)
- `Services/Rolls/Strategies.lua` (package-internal normal/SR/tie/raid-roll strategy policy)
- `Services/Rolls/Resolution.lua` (resolver ordering, tie-cutoff handling, and row-policy helpers)
- `Services/Rolls/Display.lua` (display-model assembly and winner/display contract helpers)

`addon.Services.Reserves` internal runtime helpers are composed by:
- `Services/Reserves/Import.lua` (CSV and encoded SoftRes JSON parsing plus/multi strategies)
- `Services/Reserves/Aliases.lua` (package-internal SoftRes name alias resolution policy)
- `Services/Reserves/Display.lua` (grouped display rows, player formatting, and reserve-list projections)
- `Services/Reserves/Sync.lua` (runtime-only SoftRes metadata/data sync and chunked addon-message handling)
- `Services/Reserves/Chat.lua` (opt-in `!sr`/`!softres` whisper request parsing and chat-safe replies)

### Widgets (`addon.Widgets.*`)

Feature UI controllers:

- `addon.Widgets.LootCounter`
- `addon.Widgets.ReservesUI`
- `addon.Widgets.Config`

### EntryPoints

Entrypoints stay narrow:

- `addon.Minimap` (`EntryPoints/Minimap.lua`)
- slash command routing (`EntryPoints/SlashEvents.lua`)
- parent routing should prefer `addon.Database.RequestControllerMethod(...)`

### Shared Modules

Common infra under `!KRT/Modules/`:

- Data/utility: `Timer`, `Events`, `Strings`, `Item`, `LootSourcesData`, `LootSources`, `Time`,
  `Sort`, `Comms`, `Base64`, `Json`, `Colors`, `IgnoredItems`, `IgnoredMobs`
- `Modules/LootSourcesData.lua` - static raid item-source data
- `Modules/LootSources.lua` - itemId -> raid source resolver
- `Modules/Dataset/IgnoredMobs.lua` - raid add/phase-ignore lookup plus canonical trash-mob name helpers
- UI infra: `Frames`, `UIScaffold`, `ListController`, `MultiSelect`, `UI` facade, `UIEffects`
- Messaging: `Bus`
- Feature toggles: `Features`

## Public API Notes

- Canonical owners are namespaced (`addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`).
- Retired top-level aliases (`addon.Master`, `addon.Logger`, ...) must not be reintroduced.
- For announce and shared warning output, use `addon.Services.Chat`.
  For capability queries and shared master-only access guards, use
  `addon.Services.Raid`.
  Root addon method facades such as `addon:Announce`,
  `addon:GetRaidCapabilityState`, and `addon:EnsureMasterOnlyAccess`
  are intentionally absent.
- `addon:Print` remains a compatibility hook for `LibLogger-1.0`.
- For reserves, use `addon.Services.Reserves` as the canonical public surface.
  Do not rely on nested `.Service` alias surfaces.
- For DB-manager-backed accessors, use `addon.Database.GetRaidStore`,
  `addon.Database.GetRaidStoreOrNil`, `addon.Database.GetRaidQueries`,
  `addon.Database.GetRaidMigrations`, `addon.Database.GetRaidValidator`, and
  `addon.Database.GetSyncer` as the canonical public surface.
  Use `addon.Database.GetRaidSchemaVersion` as the canonical schema-version accessor.
  `addon.DB` remains the concrete DB namespace (`RaidStore`, `RaidQueries`,
  `RaidMigrations`, `RaidValidator`, `Syncer`) plus manager state, and
  `addon.DBSchema` remains the concrete schema namespace.
- For `Logger`, controller UI-local lifecycle/state glue stays private inside
  `Controllers/Logger.lua`. External runtime behavior should go through `Services/Logger/*`,
  bus events, and action contracts.
- Package-internal cross-file helpers should live on underscore-prefixed owner-table fields
  (`addon.Services.Raid._...`, `addon.Services.Logger.Store._...`,
  `addon.Services.Reserves._...`) instead of public `*Internal` methods.
- For `Master`, keep only explicitly consumed button handlers public. Dropdown, cursor,
  and other frame-local glue should stay private inside `Controllers/Master.lua`.
- Retired alias usage is blocked by local gates to prevent new root call sites.

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

Avoid key/shape breaks without explicit release notes and a deliberate schema-version decision.

## Placement Guide for New Code

- Parent feature logic -> `Controllers/`
- Runtime model/state logic -> `Services/`
- Feature UI controllers -> `Widgets/`
- Slash/minimap routing -> `EntryPoints/`
- Generic reusable helpers/constants -> `Modules/`

When in doubt, keep behavior ownership explicit and route cross-layer notifications through `addon.Bus`.
