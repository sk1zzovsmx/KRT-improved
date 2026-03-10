# StdFacade Deprecation Map

This map tracks ownership for `addon.StdFacade.*` APIs during facade deconflict.

## Legend

- `compat-facade`: forwarding wrapper kept for backward compatibility.
- `still-owner`: utility still owned by `StdFacade.lua` (or mixed fallback logic).
- `deprecated`: compat API; new call-sites must use owner module directly.

## Deprecated Compat Facades

| StdFacade API | Class | Owner | Notes |
| --- | --- | --- | --- |
| `StdFacade.trimText` | compat-facade + deprecated | `addon.Strings.trimText` | Debug warning once/session. |
| `StdFacade.splitArgs` | compat-facade + deprecated | `addon.Strings.splitArgs` | Debug warning once/session. |
| `StdFacade.normalizeName` | compat-facade + deprecated | `addon.Strings.normalizeName` | Debug warning once/session. |
| `StdFacade.normalizeLower` | compat-facade + deprecated | `addon.Strings.normalizeLower` | Debug warning once/session. |

## Compat Facades (Keep)

| StdFacade API Group | Class | Owner |
| --- | --- | --- |
| `StdFacade.ucfirst`, `StdFacade.findAchievement`, `StdFacade.formatChatMessage`, `StdFacade.getItem*FromLink` | compat-facade | `addon.Strings.*` |
| `StdFacade.registerCallback`, `StdFacade.triggerEvent`, callback stats helpers | compat-facade | `addon.Bus.*` |
| `StdFacade.enableDrag`, frame helpers, `StdFacade.makeEventDrivenRefresher` | compat-facade | `addon.Frames.*` via `addon.StdFacade.UI.*` |
| `StdFacade.bootstrapModuleUi`, `StdFacade.makeUIFrameController`, `StdFacade.createListPanelScaffold` | compat-facade | `addon.UIScaffold.*` via `addon.StdFacade.UI.*` |
| `StdFacade.enableDisable`, `StdFacade.showHide`, `StdFacade.toggleHighlight`, named-part helpers | compat-facade | `addon.UIPrimitives.*` via `addon.StdFacade.UI.*` |
| `StdFacade.ensureRowVisuals`, `StdFacade.setRowSelected`, `StdFacade.setRowFocused` | compat-facade | `addon.UIRowVisuals.*` via `addon.StdFacade.UI.*` |
| `StdFacade.makeListController`, `StdFacade.createRowDrawer`, `StdFacade.bindListController` | compat-facade | `addon.ListController.*` via `addon.StdFacade.UI.*` |
| `StdFacade.warmItemCache`, `StdFacade.isBagItemSoulbound`, `addon:SetTooltip` | compat-facade | `addon.StdFacade.Tooltip.*` |
| `StdFacade.normalizeHexColor`, `StdFacade.getClassColor` | compat-facade | `addon.Colors.*` |
| `StdFacade.multiSelect*` + `StdFacade.MultiSelect_*` aliases | compat-facade | `addon.MultiSelect.*` |
| `StdFacade.sync`, `StdFacade.chat`, `StdFacade.whisper` | compat-facade | `addon.Comms.*` |
| `StdFacade.sec2clock`, `StdFacade.isRaidInstance`, `StdFacade.getDifficulty`, `StdFacade.getCurrentTime`, `StdFacade.getServerOffset` | compat-facade | `addon.Time.*` |
| `StdFacade.encode`, `StdFacade.decode` | compat-facade | `addon.Base64.*` |

## Still-Owner APIs

| StdFacade API | Class | Notes |
| --- | --- | --- |
| `StdFacade.isDebugEnabled`, `StdFacade.applyDebugSetting` | still-owner | Runtime debug state glue. |
| `StdFacade.setOption` | still-owner | Central option sync (`KRT_Options` + `addon.options`). |
| `StdFacade.getPlayerName`, `StdFacade.getRaid`, `StdFacade.GetRaid`, `StdFacade.getRealmName`, `StdFacade.getUnitRank` | still-owner | Raid/runtime fallbacks while facades migrate. |

## Policy

1. New code should call owner modules directly when available.
2. Keep compat facades until all critical call-sites migrate.
3. Deprecated facades are documented via `@deprecated` tags in compat wrappers.
