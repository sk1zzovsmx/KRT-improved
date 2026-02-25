# KRT Layer Map

Scope: all addon Lua files except `!KRT/Libs/**`.

Legend:
- Layers: `L1 Core`, `L2 Loc`, `L4 Modules`, `L5 Runtime`, `L6 Features`.
- Action values: `Keep`, `Merge`, `Move`, `Inline`, `Delete`, `Rename`.

| File | Layer attuale | Layer target | Owner | Azione | Note |
| --- | --- | --- | --- | --- | --- |
| Core/Init.lua | L1 Core | L1 Core | addon.Core | Keep | Bootstrap shared tables and contracts |
| Localization/localization.en.lua | L2 Loc | L2 Loc | addon.L | Keep | User-facing localization |
| Localization/DiagnoseLog.en.lua | L2 Loc | L2 Loc | addon.Diagnose | Keep | Diagnose templates |
| Modules/C.lua | L4 Modules | L4 Modules | addon.C | Keep | Constants and enums |
| Modules/Bus.lua | L4 Modules | L4 Modules | addon.Bus | Keep | Internal callback bus |
| Modules/Strings.lua | L4 Modules | L4 Modules | addon.Strings via Std | Merge | Merge into Modules/Std.lua |
| Modules/Colors.lua | L4 Modules | L4 Modules | addon.Colors via Std | Merge | Merge into Modules/Std.lua |
| Modules/Time.lua | L4 Modules | L4 Modules | addon.Time via Std | Merge | Merge into Modules/Std.lua |
| Modules/Base64.lua | L4 Modules | L4 Modules | addon.Base64 via Std | Merge | Merge into Modules/Std.lua |
| Modules/Comms.lua | L4 Modules | L4 Modules | addon.Comms via Std | Merge | Merge into Modules/Std.lua |
| Modules/Events.lua | L4 Modules | L1 Core | addon.Events | Inline | Inline in Core/Init.lua |
| Modules/Features.lua | L4 Modules | L1 Core | addon.Features | Inline | Inline in Core/Init.lua |
| Modules/ignoredItems.lua | L8 Late data | L6 Features | addon.Raid | Move | Move ignored list into Services/Raid.lua |
| Modules/StdFacade.RaidState.lua | L4 Modules | L1+L6 split | addon.Core + addon.Raid | Move | Split helpers between Core and Raid service |
| Modules/StdFacade.Tooltip.lua | L4 Modules | L4+L6 split | addon.Frames + addon.Loot | Move | Split tooltip UI and loot item probes |
| Modules/StdFacade.Options.lua | L4 Modules | L1 Core | addon.Options | Move | Replace with addon.Options owner |
| Modules/StdFacade.LegacyGlobals.lua | L4 Modules | L1 Core | addon.Core | Move | Install legacy globals from core init |
| Modules/Compat/StdFacade.UI.lua | L4 Modules | removed | compat facade | Delete | Remove compat UI facade |
| Modules/StdFacade.lua | L4 Modules | removed | addon.StdFacade facade | Delete | Remove mega-facade after migration |
| Modules/UI/Facade.lua | L4 Modules | L4 Modules | addon.UI | Keep | Widget facade/port |
| Modules/UI/Visuals.lua | L4 Modules | L4 Modules | addon.UIPrimitives + addon.UIRowVisuals | Keep | Shared row and visual helpers |
| Modules/UI/Frames.lua | L4 Modules | L4 Modules | addon.Frames + addon.UIScaffold | Keep | Frame scaffolding and tooltip helpers |
| Modules/UI/ListController.lua | L4 Modules | L4 Modules | addon.ListController | Keep | Reusable list controller |
| Modules/UI/MultiSelect.lua | L4 Modules | L4 Modules | addon.MultiSelect | Keep | Multi-select state helpers |
| Modules/UI/Binder/Map.lua | L4 Modules | L4 Modules | addon.UIBinder.Map | Keep | Binding datasets |
| Modules/UI/Binder/UIBinder.lua | L4 Modules | L4 Modules | addon.UIBinder | Keep | XML script binder |
| KRT.lua | L5 Runtime | L5 Runtime | addon | Keep | Runtime bootstrap and WoW event wiring |
| Services/Raid.lua | L6 Features | L6 Features | addon.Raid | Keep | Raid/session model and ignored item owner |
| Services/Chat.lua | L6 Features | L6 Features | addon.Chat | Keep | Chat output helpers |
| Services/Rolls.lua | L6 Features | L6 Features | addon.Rolls | Keep | Rolls tracking |
| Services/Loot.lua | L6 Features | L6 Features | addon.Loot | Keep | Loot parsing and cache probes |
| Services/Reserves.lua | L6 Features | L6 Features | addon.Reserves.Service | Keep | Reserve model/import |
| Services/Syncer.lua | L6 Features | L6 Features | addon.Syncer | Keep | Logger sync protocol |
| Controllers/Master.lua | L6 Features | L6 Features | addon.Master | Keep | Master-loot parent owner |
| Controllers/Logger.lua | L6 Features | L6 Features | addon.Logger | Keep | Logger parent owner |
| Controllers/Warnings.lua | L6 Features | L6 Features | addon.Warnings | Keep | Warnings parent owner |
| Controllers/Changes.lua | L6 Features | L6 Features | addon.Changes | Keep | Changes parent owner |
| Controllers/Spammer.lua | L6 Features | L6 Features | addon.Spammer | Keep | Spammer parent owner |
| Widgets/LootCounter.lua | L6 Features | L6 Features | addon.LootCounter | Keep | Loot counter widget owner |
| Widgets/ReservesUI.lua | L6 Features | L6 Features | addon.ReservesUI | Keep | Reserve list/import widgets |
| Widgets/Config.lua | L6 Features | L6 Features | addon.Config | Keep | Config widget owner |
| EntryPoints/Minimap.lua | L6 Features | L6 Features | addon.Minimap | Keep | Minimap button and menu entrypoint |
| EntryPoints/SlashEvents.lua | L6 Features | L6 Features | addon.Slash | Keep | Slash command router entrypoint |

Target end-state notes:
- Keep public `addon.*` APIs stable where practical.
- Remove `addon.StdFacade` facade only after all call-site migrations are complete.

Tag: LAYER_MAP
