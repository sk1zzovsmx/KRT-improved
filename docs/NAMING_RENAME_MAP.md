# Naming Rename Map

Tracking table for naming normalization. Status legend:

- `done-m56`: implemented, legacy aliases removed
- `compliant`: already in target naming style

## Core (M56 done)

| OldName | NewName | File | Public? | Alias temp? | Status |
| --- | --- | --- | --- | --- | --- |
| `Core.registerLegacyAlias` | `Core.RegisterLegacyAlias` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.registerLegacyAliasPath` | `Core.RegisterLegacyAliasPath` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getController` | `Core.GetController` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getPlayerName` | `Core.GetPlayerName` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getRealmName` | `Core.GetRealmName` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getUnitRank` | `Core.GetUnitRank` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.ensureLootRuntimeState` | `Core.EnsureLootRuntimeState` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getFeatureShared` | `Core.GetFeatureShared` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getCurrentRaid` | `Core.GetCurrentRaid` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.setCurrentRaid` | `Core.SetCurrentRaid` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getLastBoss` | `Core.GetLastBoss` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.setLastBoss` | `Core.SetLastBoss` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getNextReset` | `Core.GetNextReset` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.setNextReset` | `Core.SetNextReset` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getRaidSchemaVersion` | `Core.GetRaidSchemaVersion` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.ensureRaidSchema` | `Core.EnsureRaidSchema` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.ensureRaidById` | `Core.EnsureRaidById` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.ensureRaidByNid` | `Core.EnsureRaidByNid` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getRaidNidById` | `Core.GetRaidNidById` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.getRaidIdByNid` | `Core.GetRaidIdByNid` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.createRaidRecord` | `Core.CreateRaidRecord` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.stripRuntimeRaidCaches` | `Core.StripRuntimeRaidCaches` | `!KRT/Init.lua` | yes | no | done-m56 |

## Bus (M56 done)

| OldName | NewName | File | Public? | Alias temp? | Status |
| --- | --- | --- | --- | --- | --- |
| `Bus.registerCallback` | `Bus.RegisterCallback` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |
| `Bus.unregisterCallback` | `Bus.UnregisterCallback` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |
| `Bus.triggerEvent` | `Bus.TriggerEvent` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |
| `Bus.registerCallbacks` | `Bus.RegisterCallbacks` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |
| `Bus.getInternalCallbackStats` | `Bus.GetInternalCallbackStats` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |
| `Bus.resetInternalCallbackStats` | `Bus.ResetInternalCallbackStats` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |
| `Bus.dumpInternalCallbackStats` | `Bus.DumpInternalCallbackStats` | `!KRT/Modules/Bus.lua` | yes | no | done-m56 |

## Std Namespaces (M56 done)

| OldName | NewName | File | Public? | Alias temp? | Status |
| --- | --- | --- | --- | --- | --- |
| `Colors.normalizeHexColor` | `Colors.NormalizeHexColor` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Colors.getClassColor` | `Colors.GetClassColor` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.ucfirst` | `Strings.UpperFirst` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.trimText` | `Strings.TrimText` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.normalizeName` | `Strings.NormalizeName` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.normalizeLower` | `Strings.NormalizeLower` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.findAchievement` | `Strings.FindAchievement` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.formatChatMessage` | `Strings.FormatChatMessage` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.splitArgs` | `Strings.SplitArgs` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.getItemIdFromLink` | `Strings.GetItemIdFromLink` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Strings.getItemStringFromLink` | `Strings.GetItemStringFromLink` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Time.sec2clock` | `Time.SecondsToClock` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Time.isRaidInstance` | `Time.IsRaidInstance` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Time.getDifficulty` | `Time.GetDifficulty` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Time.getCurrentTime` | `Time.GetCurrentTime` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Time.getServerOffset` | `Time.GetServerOffset` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Base64.encode` | `Base64.Encode` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Base64.decode` | `Base64.Decode` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Comms.sync` | `Comms.Sync` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Comms.chat` | `Comms.Chat` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |
| `Comms.whisper` | `Comms.Whisper` | `!KRT/Modules/Std.lua` | yes | no | done-m56 |

## UI Namespaces (M56 done)

| OldName | NewName | File | Public? | Alias temp? | Status |
| --- | --- | --- | --- | --- | --- |
| `Frames.enableDrag` | `Frames.EnableDrag` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.makeConfirmPopup` | `Frames.MakeConfirmPopup` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.makeEditBoxPopup` | `Frames.MakeEditBoxPopup` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.setFrameTitle` | `Frames.SetFrameTitle` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.resetEditBox` | `Frames.ResetEditBox` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.setEditBoxValue` | `Frames.SetEditBoxValue` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.setShown` | `Frames.SetShown` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.setTooltip` | `Frames.SetTooltip` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.makeEventDrivenRefresher` | `Frames.MakeEventDrivenRefresher` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.makeFrameGetter` | `Frames.MakeFrameGetter` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.initModuleFrame` | `Frames.InitModuleFrame` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.makeUIFrameController` | `Frames.MakeUIFrameController` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.bootstrapModuleUi` | `Frames.BootstrapModuleUi` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.createListPanelScaffold` | `Frames.CreateListPanelScaffold` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `Frames.bindEditBoxHandlers` | `Frames.BindEditBoxHandlers` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `UIScaffold.makeUIFrameController` | `UIScaffold.MakeUIFrameController` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `UIScaffold.bootstrapModuleUi` | `UIScaffold.BootstrapModuleUi` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `UIScaffold.createListPanelScaffold` | `UIScaffold.CreateListPanelScaffold` | `!KRT/Modules/UI/Frames.lua` | yes | no | done-m56 |
| `UIPrimitives.enableDisable` | `UIPrimitives.EnableDisable` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.toggle` | `UIPrimitives.Toggle` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.hideFrame` | `UIPrimitives.HideFrame` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.showHide` | `UIPrimitives.ShowHide` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.toggleHighlight` | `UIPrimitives.ToggleHighlight` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.setButtonCount` | `UIPrimitives.SetButtonCount` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.setText` | `UIPrimitives.SetText` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.getNamedFramePart` | `UIPrimitives.GetNamedFramePart` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.enableDisableNamedPart` | `UIPrimitives.EnableDisableNamedPart` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.showHideNamedPart` | `UIPrimitives.ShowHideNamedPart` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.setTextNamedPart` | `UIPrimitives.SetTextNamedPart` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIPrimitives.updateModeTextNamedPart` | `UIPrimitives.UpdateModeTextNamedPart` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIRowVisuals.ensureRowVisuals` | `UIRowVisuals.EnsureRowVisuals` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIRowVisuals.setRowSelected` | `UIRowVisuals.SetRowSelected` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `UIRowVisuals.setRowFocused` | `UIRowVisuals.SetRowFocused` | `!KRT/Modules/UI/Visuals.lua` | yes | no | done-m56 |
| `ListController.createRowDrawer` | `ListController.CreateRowDrawer` | `!KRT/Modules/UI/ListController.lua` | yes | no | done-m56 |
| `ListController.makeListController` | `ListController.MakeListController` | `!KRT/Modules/UI/ListController.lua` | yes | no | done-m56 |
| `ListController.bindListController` | `ListController.BindListController` | `!KRT/Modules/UI/ListController.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectInit` | `MultiSelect.MultiSelectInit` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectClear` | `MultiSelect.MultiSelectClear` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectToggle` | `MultiSelect.MultiSelectToggle` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectSetAnchor` | `MultiSelect.MultiSelectSetAnchor` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectGetAnchor` | `MultiSelect.MultiSelectGetAnchor` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectRange` | `MultiSelect.MultiSelectRange` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectIsSelected` | `MultiSelect.MultiSelectIsSelected` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectCount` | `MultiSelect.MultiSelectCount` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectGetVersion` | `MultiSelect.MultiSelectGetVersion` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `MultiSelect.multiSelectGetSelected` | `MultiSelect.MultiSelectGetSelected` | `!KRT/Modules/UI/MultiSelect.lua` | yes | no | done-m56 |
| `Map.getFrameWidgetId` | `Map.GetFrameWidgetId` | `!KRT/Modules/UI/Binder/Map.lua` | yes | no | done-m56 |
| `Compiler.trimBinderToken` | `Compiler.TrimBinderToken` | `!KRT/Modules/UI/Binder/UIBinder.lua` | yes | no | done-m56 |
| `Compiler.splitCommaArgs` | `Compiler.SplitCommaArgs` | `!KRT/Modules/UI/Binder/UIBinder.lua` | yes | no | done-m56 |
| `Compiler.parseBodyToHandler` | `Compiler.ParseBodyToHandler` | `!KRT/Modules/UI/Binder/UIBinder.lua` | yes | no | done-m56 |
| `Compiler.compileHandler` | `Compiler.CompileHandler` | `!KRT/Modules/UI/Binder/UIBinder.lua` | yes | no | done-m56 |
| `Compiler.resolveArgToken` | `Compiler.ResolveArgToken` | `!KRT/Modules/UI/Binder/UIBinder.lua` | yes | no | done-m56 |

## Infra Adapters (M56 done)

| OldName | NewName | File | Public? | Alias temp? | Status |
| --- | --- | --- | --- | --- | --- |
| `Options.newOptions` | `Options.NewOptions` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Options.isDebugEnabled` | `Options.IsDebugEnabled` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Options.applyDebugSetting` | `Options.ApplyDebugSetting` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Options.setOption` | `Options.SetOption` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Options.loadOptions` | `Options.LoadOptions` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Options.restoreDefaults` | `Options.RestoreDefaults` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Events.configOptionChanged` | `Events.ConfigOptionChanged` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Events.wowForwarded` | `Events.WowForwarded` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.bindModuleRequestRefresh` | `Core.BindModuleRequestRefresh` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.bindModuleToggleHide` | `Core.BindModuleToggleHide` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Core.makeModuleFrameGetter` | `Core.MakeModuleFrameGetter` | `!KRT/Init.lua` | yes | no | done-m56 |
| `Loot.warmItemCache` | `Loot.WarmItemCache` | `!KRT/Services/Loot.lua` | yes | no | done-m56 |
| `Loot.isBagItemSoulbound` | `Loot.IsBagItemSoulbound` | `!KRT/Services/Loot.lua` | yes | no | done-m56 |

## ItemProbe (M56)

| Name | File | Status |
| --- | --- | --- |
| `ItemProbe.WarmItemCache` | `!KRT/Modules/ItemProbe.lua` | compliant |
| `ItemProbe.IsBagItemSoulbound` | `!KRT/Modules/ItemProbe.lua` | compliant |

