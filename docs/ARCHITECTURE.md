# KRT Architecture and Layering

This document defines runtime ownership, dependency directions, and UI/XML binding rules.
Use this as the architecture map; use `AGENTS.md` for binding policy.

## Canonical Layer Stack

The canonical layer order is declared in `!KRT/!KRT.toc`.

1. `Libs/*`
   Third-party runtime libraries loaded first.
   Vendored subtrees under `!KRT/Libs/**`, including nested compatibility dependencies,
   are third-party package content; do not edit or remove them as cleanup unless release
   packaging policy explicitly changes.
2. `Init.lua` + `Database/{DB,DBOptions,DBSchema,DBManager}.lua`
   Unified bootstrap, shared namespaces, controller dispatch, DB/options bootstrap.
3. `Localization/*`
   User strings (`addon.L`) and diagnose templates (`addon.Diagnose`).
4. `UI/Templates/Common.xml`
   Shared XML templates only.
5. `Modules/*`
   Shared infra (`Timer`, `Events`, `Bus`, `Item`, `Sort`, `UI.Scaffold`, `UI.Widgets`,
   `UI.Selection`, static datasets, ...).
6. `Database/DBRaid*.lua`, `Services/*`, `Controllers/*`, `Widgets/*`, `EntryPoints/*`
   Runtime feature implementation and entrypoints.
7. `KRT.xml` -> `UI/*.xml`
   UI include manifest and concrete frame layout files.

## Runtime Ownership Map

- `!KRT/Init.lua`
  Owns shared bootstrap namespaces (`addon.Database`, `addon.State`, `addon.Events`, ...)
  and global WoW event wiring. `Database.GetFeatureShared()` is the module-facing
  shared dependency contract, and `feature.EnsureServiceNamespace(...)` owns
  service namespace bootstrap for split service files.
  KRT-owned Lua binds shared dependencies from `feature.*`; do not use
  `feature.* or addon.*` double-binding fallbacks. When a root compatibility table
  remains public, modules bind from `feature.*` and export the same table back to
  `addon.*`.
- `!KRT/Controllers/*.lua`
  Own top-level parent feature modules under `addon.Controllers.*`.
- `!KRT/Services/*.lua`
  Own runtime model/service logic under `addon.Services.*`.
  `addon.Services.Raid` is split across `!KRT/Services/Raid/*.lua` and loaded by TOC order.
  `State.lua` is the state anchor file; the other files extend the same service table by domain
  (`Capabilities`, `LootMethod`, `Counts`, `Roster`, `Attendance`, `LootRecords`, `Session`).
  `addon.Services.Rolls` keeps its public roll/session contract in `!KRT/Services/Rolls/Service.lua` and owns
  internal runtime helpers in `!KRT/Services/Rolls/*.lua` for countdown/session lifecycle,
  raw history/tracker state, response intake/eligibility, strategy policy, resolver policy, and display assembly
  (`addon.Services.Rolls._Countdown`, `_Sessions`, `_History`, `_Responses`, `_Strategies`,
  `_Resolution`, `_Display`).
  `addon.Services.Loot` keeps its public ingestion/parsing API in `!KRT/Services/Loot/Service.lua` and owns
  internal loot-context/runtime rule helpers in `!KRT/Services/Loot/*.lua`
  (`Context`, `State`, `Snapshots`, `PendingAwards`, `PassiveGroupLoot`, `Tracking`, `Workflow`, `Receipts`,
  `Records`, `Reconcile`, `Rules`, `DistributionSession`) on underscore-prefixed internal surfaces.
  `Workflow` owns transient loot-flow diagnostics, `Receipts` classifies parsed loot events, `Records`
  materializes canonical loot rows, and `Reconcile` owns trade-only/passive duplicate reconciliation.
  `DistributionSession` owns the compact
  `KRTDist` session-sync protocol; protocol v2 adds snapshots, roll ticks, tie state, and awarded state while
  using versioned item, roll, done, clear, snapshot, tick, tie, and awarded messages.
  `addon.Services.Reserves` keeps its public reserves contract in `!KRT/Services/Reserves.lua` and owns
  internal import parsing, SoftRes name alias policy, grouped-display/player-format, runtime-only sync, and
  whisper-response helpers in `!KRT/Services/Reserves/{Import,Aliases,Display,Sync,Chat}.lua`
  (`addon.Services.Reserves._Import`, `_Aliases`, `_Display`, `_Sync`, `_Chat`).
  External call sites use the parent facade for sync operations (`RequestSyncMetadata`,
  `HandleSyncMessage`, `GetSyncPayload`, `SetSyncedData`, and cache APIs); `_Sync`
  remains package-internal.
  `Services/Raid/Capabilities.lua` owns capability queries and the shared master-only access guard.
  `Services/Raid/LootMethod.lua` owns opt-in Master Loot automation and Group Loot restore prompts.
  `Services/SpecInspect.lua` owns the UI-free runtime spec snapshot cache backed by LibGroupTalents.
  `Services/Spammer/Draft.lua` owns PUG spammer draft persistence helpers.
  `Services/Warnings/Store.lua` owns warning text storage.
  `Services/Chat.lua` owns announce/warn output contracts.
- `!KRT/Database/DB.lua`
  Owns the canonical public accessor facade for DB-manager-backed services on
  `addon.Database.*`; `addon.DB` remains the concrete namespace for DB submodules and
  manager state, not a parallel getter surface.
- `!KRT/Database/DBOptions.lua`
  Owns `addon.Options`, strict nested option namespaces, and the read-only `addon.options` proxy.
- `!KRT/Database/DBSchema.lua`
  Owns schema-version state while exposing the canonical public accessor on
  `addon.Database.GetRaidSchemaVersion`; `addon.DBSchema` is not a second parallel getter facade.
- `!KRT/Widgets/*.lua`
  Own child UI controllers under `addon.Widgets.*`. Controllers and entrypoints should
  dispatch optional widget behavior through `addon.UI.Widgets.Call(...)`; widget files
  register there while keeping owner exports available for widget-local ownership and tests.
- `!KRT/EntryPoints/*.lua`
  Own slash/minimap entrypoints.
- `!KRT/Modules/*.lua`
  Own reusable infra only, not parent feature logic.
  `Modules/Json.lua` owns the small native JSON decoder used by encoded SoftRes import parsing.
  `Modules/Dataset/LootSourcesData.lua` owns static raid item-source data and is the documented
  data-only exception to the otherwise required `Public methods` section.
  `Modules/LootSourceCandidates.lua` owns shared-source labels, mode signatures, candidate copying,
  and canonical loot-source display model construction helpers.
  `Modules/LootSources.lua` owns the itemId -> raid source resolver.
  `Modules/Dataset/IgnoredMobs.lua` owns raid add/phase-ignore lookup and the canonical generic trash-mob
  name helpers consumed by Raid state, Logger, and raid validation.
  `Modules/UI/Frames.lua` owns `addon.UI.Frames`, `addon.UI.Scaffold`, `addon.UI.ModuleState`,
  `addon.UI.EditBoxes`, `addon.UI.Popups`, and `addon.UI.Tooltips`.
  `Modules/UI/ListController.lua` owns `addon.UI.Lists`; `Modules/UI/MultiSelect.lua` owns
  `addon.UI.Selection`; `Modules/UI/Facade.lua` owns `addon.UI.Widgets`.
  `Modules/UI/ScreenNotice.lua` owns the shared transient screen-notice frame and delegates fade
  timing to `addon.UI.Effects`.

Retired root aliases (`addon.Master`, `addon.Logger`, `addon.Raid`, ...) are blocked for new code.
Call sites should use namespaced owners (`addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`).
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
- Services must not own frame lifecycle or UI setup (`OnLoad`, `Refresh`, `SetScript`,
  `Show`, `Hide`, `UI.Scaffold`, `InterfaceOptions`, panel APIs, or UI handler hooks).
- Controllers must not reference other parent owners directly.
- Upward communication should use `addon.Bus` and canonical event names from `Modules/Events.lua`.
- Prefer existing internal events (`SetItem`, `RaidRosterDelta`, etc.) over new micro-events.
- EntryPoints should prefer `addon.Database.RequestControllerMethod(...)` for parent routing instead
  of open-coded controller lookup helpers.
- Capability checks and announce/warn output should target `addon.Services.Raid` and
  `addon.Services.Chat` (or their top-level alias tables), not root addon methods.
- Controller-local UI glue should stay local: avoid exporting selection handlers, popup save/fill
  helpers, row-hover glue, and similar file-local mechanics on controller public surfaces.
- Cross-file helpers that are still package-internal should move to underscore internal surfaces
  on the owner table, not remain public `*Internal` methods.

## Intentional Controller/EntryPoint Public Contracts

After the API/lifecycle cleanup, the remaining public Controller/EntryPoint surface is intentional.
Do not internalize these methods without changing the caller architecture and updating the matching
tests. They are public because the current runtime dispatch uses method-name lookup, slash/minimap
entrypoints, or scaffold/minimap ownership.

| Contract | Type | Current reason |
| --- | --- | --- |
| `Master:LOOT_OPENED` | WoW-forwarded event handler | Called by Master event forwarding through method-name dispatch. |
| `Master:LOOT_CLOSED` | WoW-forwarded event handler | Called by Master event forwarding through method-name dispatch. |
| `Master:LOOT_SLOT_CLEARED` | WoW-forwarded event handler | Called by Master event forwarding through method-name dispatch. |
| `Master:UI_ERROR_MESSAGE` | WoW-forwarded event handler | Called by Master event forwarding through method-name dispatch. |
| `Master:TRADE_ACCEPT_UPDATE` | WoW-forwarded event handler | Called by Master trade forwarding through method-name dispatch. |
| `Master:TRADE_CLOSED` | WoW-forwarded event handler | Called by Master trade forwarding through method-name dispatch. |
| `Master:TRADE_REQUEST_CANCEL` | WoW-forwarded event handler | Called by Master trade forwarding through method-name dispatch. |
| `Warnings:RequestAnnounce` | Slash command endpoint | Used by `/krt rw ...` through `Database.RequestControllerMethod`. |
| `Spammer:RequestStart` | Slash command endpoint | Used by `/krt pug start` through `Database.RequestControllerMethod`. |
| `Spammer:RequestStop` | Slash command endpoint | Used by `/krt pug stop` through `Database.RequestControllerMethod`. |
| `Minimap:SetPos` | Slash/minimap state endpoint | Used by `/krt minimap pos` and minimap drag/load positioning. |
| `Minimap:BindUI` | Minimap lifecycle endpoint | Owned by `EntryPoints/Minimap.lua` for minimap frame binding. |
| `Minimap:EnsureUI` | Minimap lifecycle endpoint | Used by bootstrap/config paths to ensure minimap state. |
| `Minimap:ToggleMinimapButton` | Config/minimap endpoint | Used by config and minimap visibility flows. |

The registry may classify some `Request*` or minimap methods as `Lifecycle` because of their verb.
Semantically, `Warnings:RequestAnnounce` and `Spammer:RequestStart/RequestStop` are command
endpoints, while `Minimap:*` methods are entrypoint-owned minimap lifecycle/state endpoints.

## UI/XML Binding and Template Policy

- XML is layout-only:
  no `<Scripts>` and no `<On...>` blocks in `!KRT/UI/*.xml` or `!KRT/UI/Templates/*.xml`.
- Do not reintroduce `Modules/UI/Binder/*` or binder-style mapping registries.
- UI script wiring belongs in Lua via explicit `SetScript`/handler binding in owning modules.
- For Controllers/Widgets, prefer `UI.Scaffold.DefineModule(cfg)` as the canonical lifecycle contract.
- Modules should implement UI hooks only:
  `AcquireRefs`, `BindHandlers`, `Localize`, `OnLoadFrame`, `RefreshUI`/`Refresh`.
- Scaffold-generated methods own shared lifecycle methods:
  `BindUI`, `EnsureUI`, `Toggle`, `Show`, `Hide`, `RequestRefresh`, `MarkDirty`.
- Keep UI cache/state schema uniform in `addon.UI.ModuleState`; use `uiState` for local references.
- Optional widget routing goes through `addon.UI` (`Modules/UI/Facade.lua`) + `addon.Features`.
- `OnUpdate` is allowed only for minimap drag and shared UI driver/effect modules.
- Option access uses namespace configs (`cfg:Get`, `cfg:Set`); `addon.options` remains a
  read-only compatibility proxy owned by `Database/DBOptions.lua`.
- Reusable layout, scrollframe, table, row, editbox, border, and spacing rules live in
  `docs/UI_CODING_RULES.md`. Follow that guide before adding new feature-local UI styling.

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
- `docs/UI_CODING_RULES.md` - reusable UI layout and template rules
- `docs/DEV_CHECKS.md` - quick checks and audit commands
- `docs/KRT_MCP.md` - MCP tools for repo workflows
- `docs/AGENT_SKILLS.md` - skill sync and Mechanic companion workflow
