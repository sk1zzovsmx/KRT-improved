# Modules UI Ownership Map

This map defines owner vs compat responsibilities for UI-related modules in `!KRT/Modules/UI`
and `!KRT/Modules/Compat`.

## Scope

- `!KRT/Modules/Compat/StdFacade.UI.lua`
- `!KRT/Modules/UI/Frames.lua`
- `!KRT/Modules/UI/ListController.lua`
- `!KRT/Modules/UI/Binder/UIBinder.lua`
- `!KRT/Modules/UI/Facade.lua`
- `!KRT/Modules/UI/MultiSelect.lua`

## Ownership Table

| Function | Current file | Category | Owner target | Action | Notes |
| --- | --- | --- | --- | --- | --- |
| `UI.enableDrag` | `StdFacade.UI.lua` | compat | `addon.Frames.enableDrag` | wrap | `StdFacade.UI` is compat-only. |
| `UI.createRowDrawer` | `StdFacade.UI.lua` | compat | `addon.ListController.createRowDrawer` | wrap | Direct forwarder. |
| `UI.makeListController` | `StdFacade.UI.lua` | compat | `addon.ListController.makeListController` | wrap | Direct forwarder. |
| `UI.bindListController` | `StdFacade.UI.lua` | compat | `addon.ListController.bindListController` | wrap | Direct forwarder. |
| `UI.makeConfirmPopup` | `StdFacade.UI.lua` | compat | `addon.Frames.makeConfirmPopup` | wrap | Direct forwarder. |
| `UI.makeEditBoxPopup` | `StdFacade.UI.lua` | compat | `addon.Frames.makeEditBoxPopup` | wrap | Direct forwarder. |
| `UI.setFrameTitle` | `StdFacade.UI.lua` | compat | `addon.Frames.setFrameTitle` | wrap | Direct forwarder. |
| `UI.resetEditBox` | `StdFacade.UI.lua` | compat | `addon.Frames.resetEditBox` | wrap | Direct forwarder. |
| `UI.setEditBoxValue` | `StdFacade.UI.lua` | compat | `addon.Frames.setEditBoxValue` | wrap | Direct forwarder. |
| `UI.setShown` | `StdFacade.UI.lua` | compat | `addon.Frames.setShown` | wrap | Direct forwarder. |
| `UI.makeEventDrivenRefresher` | `StdFacade.UI.lua` | compat | `addon.Frames.makeEventDrivenRefresher` | wrap | Direct forwarder. |
| `UI.makeFrameGetter` | `StdFacade.UI.lua` | compat | `addon.Frames.makeFrameGetter` | wrap | Direct forwarder. |
| `UI.initModuleFrame` | `StdFacade.UI.lua` | compat | `addon.Frames.initModuleFrame` | wrap | Direct forwarder. |
| `UI.bindEditBoxHandlers` | `StdFacade.UI.lua` | compat | `addon.Frames.bindEditBoxHandlers` | wrap | Direct forwarder. |
| `UI.bootstrapModuleUi` | `StdFacade.UI.lua` | compat | `addon.UIScaffold.bootstrapModuleUi` | wrap | Scaffold API implemented in `Frames.lua`. |
| `UI.makeUIFrameController` | `StdFacade.UI.lua` | compat | `addon.UIScaffold.makeUIFrameController` | wrap | Scaffold API implemented in `Frames.lua`. |
| `UI.createListPanelScaffold` | `StdFacade.UI.lua` | compat | `addon.UIScaffold.createListPanelScaffold` | wrap | Scaffold API implemented in `Frames.lua`. |
| `UI.enableDisable` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.enableDisable` | wrap | Primitive owner extracted. |
| `UI.toggle` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.toggle` | wrap | Primitive owner extracted. |
| `UI.hideFrame` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.hideFrame` | wrap | Primitive owner extracted. |
| `UI.showHide` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.showHide` | wrap | Primitive owner extracted. |
| `UI.toggleHighlight` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.toggleHighlight` | wrap | Primitive owner extracted. |
| `UI.setButtonCount` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.setButtonCount` | wrap | Primitive owner extracted. |
| `UI.setText` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.setText` | wrap | Primitive owner extracted. |
| `UI.getNamedFramePart` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.getNamedFramePart` | wrap | Primitive owner extracted. |
| `UI.enableDisableNamedPart` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.enableDisableNamedPart` | wrap | Primitive owner extracted. |
| `UI.showHideNamedPart` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.showHideNamedPart` | wrap | Primitive owner extracted. |
| `UI.setTextNamedPart` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.setTextNamedPart` | wrap | Primitive owner extracted. |
| `UI.updateModeTextNamedPart` | `StdFacade.UI.lua` | compat | `addon.UIPrimitives.updateModeTextNamedPart` | wrap | Primitive owner extracted. |
| `UI.ensureRowVisuals` | `StdFacade.UI.lua` | compat | `addon.UIRowVisuals.ensureRowVisuals` | wrap | Row visuals owner extracted. |
| `UI.setRowSelected` | `StdFacade.UI.lua` | compat | `addon.UIRowVisuals.setRowSelected` | wrap | Row visuals owner extracted. |
| `UI.setRowFocused` | `StdFacade.UI.lua` | compat | `addon.UIRowVisuals.setRowFocused` | wrap | Row visuals owner extracted. |
| `Frames.enableDrag` | `Frames.lua` | frame helper | `addon.Frames.enableDrag` | keep | Canonical drag owner. |
| `Frames.makeConfirmPopup` | `Frames.lua` | frame helper | `addon.Frames.makeConfirmPopup` | keep | Base helper. |
| `Frames.makeEditBoxPopup` | `Frames.lua` | frame helper | `addon.Frames.makeEditBoxPopup` | keep | Base helper. |
| `Frames.setFrameTitle` | `Frames.lua` | frame helper | `addon.Frames.setFrameTitle` | keep | Base helper. |
| `Frames.resetEditBox` | `Frames.lua` | frame helper | `addon.Frames.resetEditBox` | keep | Base helper. |
| `Frames.setEditBoxValue` | `Frames.lua` | frame helper | `addon.Frames.setEditBoxValue` | keep | Base helper. |
| `Frames.setShown` | `Frames.lua` | frame helper | `addon.Frames.setShown` | keep | Base helper. |
| `Frames.makeEventDrivenRefresher` | `Frames.lua` | frame helper | `addon.Frames.makeEventDrivenRefresher` | keep | Base helper. |
| `Frames.makeFrameGetter` | `Frames.lua` | frame helper | `addon.Frames.makeFrameGetter` | keep | Base helper. |
| `Frames.initModuleFrame` | `Frames.lua` | frame helper | `addon.Frames.initModuleFrame` | keep | Uses `Frames.enableDrag` directly. |
| `Frames.bindEditBoxHandlers` | `Frames.lua` | frame helper | `addon.Frames.bindEditBoxHandlers` | keep | Base helper. |
| `Frames.makeUIFrameController` | `Frames.lua` | compat | `addon.UIScaffold.makeUIFrameController` | wrap | Temporary compat wrapper. |
| `Frames.bootstrapModuleUi` | `Frames.lua` | compat | `addon.UIScaffold.bootstrapModuleUi` | wrap | Temporary compat wrapper. |
| `Frames.createListPanelScaffold` | `Frames.lua` | compat | `addon.UIScaffold.createListPanelScaffold` | wrap | Temporary compat wrapper. |
| `ListController.createRowDrawer` | `ListController.lua` | scaffold support | `addon.ListController.createRowDrawer` | keep | List module owner. |
| `ListController.makeListController` | `ListController.lua` | scaffold/list | `addon.ListController.makeListController` | keep | Uses `UIRowVisuals`/`UIPrimitives` owners. |
| `ListController.bindListController` | `ListController.lua` | scaffold/list | `addon.ListController.bindListController` | keep | List module owner. |
| `UIBinder:BindAll` | `UIBinder.lua` | binder runtime | `addon.UIBinder` | keep | Public API stable. |
| `UIBinder:BindCreatedFrame` | `UIBinder.lua` | binder runtime | `addon.UIBinder` | keep | Public API stable. |
| `UIBinder:PatchCreateFrame` | `UIBinder.lua` | binder runtime | `addon.UIBinder` | keep | Public API stable. |
| `trimBinderToken` | `UIBinder.lua` | binder compiler | `addon.UIBinder.Compiler` | keep | Compiler merged into runtime facade file. |
| `splitCommaArgs` | `UIBinder.lua` | binder compiler | `addon.UIBinder.Compiler` | keep | Compiler merged into runtime facade file. |
| `parseBodyToHandler` | `UIBinder.lua` | binder compiler | `addon.UIBinder.Compiler` | keep | Compiler merged into runtime facade file. |
| `compileHandler` | `UIBinder.lua` | binder compiler | `addon.UIBinder.Compiler` | keep | Compiler merged into runtime facade file. |
| `frameBindings` dataset | `UIBinder.Map.lua` | binder map | `addon.UIBinder.Map` | move | Moved out of runtime facade. |
| `frameTemplateMap` dataset | `UIBinder.Map.lua` | binder map | `addon.UIBinder.Map` | move | Moved out of runtime facade. |
| `templateInheritsMap` dataset | `UIBinder.Map.lua` | binder map | `addon.UIBinder.Map` | move | Moved out of runtime facade. |
| `templateBindings` dataset | `UIBinder.Map.lua` | binder map | `addon.UIBinder.Map` | move | Moved out of runtime facade. |
| `UI:IsEnabled` | `UIFacade.lua` | widget port | `addon.UI` | keep | Facade owner. |
| `UI:IsRegistered` | `UIFacade.lua` | widget port | `addon.UI` | keep | Facade owner. |
| `UI:Register` | `UIFacade.lua` | widget port | `addon.UI` | keep | Facade owner. |
| `UI:Call` | `UIFacade.lua` | widget port | `addon.UI` | keep | Facade owner. |
| `UI:Emit` | `UIFacade.lua` | widget port | `addon.UI` | keep | Facade owner. |
| `MultiSelect.multiSelect*` | `MultiSelect.lua` | utility | `addon.MultiSelect` | keep | No UI ownership change needed. |

## Backlog by milestone

### M15 checks

```powershell
rg -n 'function (UIPrimitives\.|UIRowVisuals\.)' !KRT/Modules/UI/Visuals.lua
rg -n '^function UI\.' !KRT/Modules/Compat/StdFacade.UI.lua
rg -n 'CreateTexture|RegisterForDrag|SetPushedTexture|StartMoving|StopMovingOrSizing' !KRT/Modules/Compat/StdFacade.UI.lua
```

### M16 checks

```powershell
rg -n 'function UIScaffold\.(makeUIFrameController|bootstrapModuleUi|createListPanelScaffold)' !KRT/Modules/UI/Frames.lua
rg -n 'function Frames\.(makeUIFrameController|bootstrapModuleUi|createListPanelScaffold)' !KRT/Modules/UI/Frames.lua
```

### M17 checks

```powershell
$files=Get-ChildItem !KRT/Modules/UI/Binder -Filter '*.lua'; $files|%{('{0}`t{1}' -f (Get-Content $_).Length,$_.Name)}
rg -n 'parseBodyToHandler|compileHandler|resolveArgToken|splitCommaArgs' !KRT/Modules/UI/Binder/*.lua
rg -n 'BindAll|BindCreatedFrame|PatchCreateFrame' !KRT/Modules/UI/Binder/*.lua
```

### M18 checks

```powershell
rg -n '\b(addon\.StdFacade|StdFacade\.)' !KRT/Modules/UI/Frames.lua !KRT/Modules/UI/ListController.lua !KRT/Modules/UI/Binder/UIBinder.lua
powershell -ExecutionPolicy Bypass -File tools/check-layering.ps1
```
