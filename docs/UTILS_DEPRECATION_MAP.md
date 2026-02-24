# Utils Deprecation Map

This map tracks ownership for `addon.Utils.*` APIs during facade deconflict.

## Legend

- `compat-facade`: forwarding wrapper kept for backward compatibility.
- `still-owner`: utility still owned by `Utils.lua` (or mixed fallback logic).
- `deprecated`: compat API; new call-sites must use owner module directly.

## Deprecated Compat Facades

| Utils API | Class | Owner | Notes |
| --- | --- | --- | --- |
| `Utils.trimText` | compat-facade + deprecated | `addon.Strings.trimText` | Debug warning once/session. |
| `Utils.splitArgs` | compat-facade + deprecated | `addon.Strings.splitArgs` | Debug warning once/session. |
| `Utils.normalizeName` | compat-facade + deprecated | `addon.Strings.normalizeName` | Debug warning once/session. |
| `Utils.normalizeLower` | compat-facade + deprecated | `addon.Strings.normalizeLower` | Debug warning once/session. |

## Compat Facades (Keep)

| Utils API Group | Class | Owner |
| --- | --- | --- |
| `Utils.ucfirst`, `Utils.findAchievement`, `Utils.formatChatMessage`, `Utils.getItem*FromLink` | compat-facade | `addon.Strings.*` |
| `Utils.registerCallback`, `Utils.triggerEvent`, callback stats helpers | compat-facade | `addon.Bus.*` |
| `Utils.enableDrag`, frame helpers, `Utils.makeEventDrivenRefresher` | compat-facade | `addon.Frames.*` via `addon.Utils.UI.*` |
| `Utils.bootstrapModuleUi`, `Utils.makeUIFrameController`, `Utils.createListPanelScaffold` | compat-facade | `addon.UIScaffold.*` via `addon.Utils.UI.*` |
| `Utils.enableDisable`, `Utils.showHide`, `Utils.toggleHighlight`, named-part helpers | compat-facade | `addon.UIPrimitives.*` via `addon.Utils.UI.*` |
| `Utils.ensureRowVisuals`, `Utils.setRowSelected`, `Utils.setRowFocused` | compat-facade | `addon.UIRowVisuals.*` via `addon.Utils.UI.*` |
| `Utils.makeListController`, `Utils.createRowDrawer`, `Utils.bindListController` | compat-facade | `addon.ListController.*` via `addon.Utils.UI.*` |
| `Utils.warmItemCache`, `Utils.isBagItemSoulbound`, `addon:SetTooltip` | compat-facade | `addon.Utils.Tooltip.*` |
| `Utils.normalizeHexColor`, `Utils.getClassColor` | compat-facade | `addon.Colors.*` |
| `Utils.multiSelect*` + `Utils.MultiSelect_*` aliases | compat-facade | `addon.MultiSelect.*` |
| `Utils.sync`, `Utils.chat`, `Utils.whisper` | compat-facade | `addon.Comms.*` |
| `Utils.sec2clock`, `Utils.isRaidInstance`, `Utils.getDifficulty`, `Utils.getCurrentTime`, `Utils.getServerOffset` | compat-facade | `addon.Time.*` |
| `Utils.encode`, `Utils.decode` | compat-facade | `addon.Base64.*` |

## Still-Owner APIs

| Utils API | Class | Notes |
| --- | --- | --- |
| `Utils.isDebugEnabled`, `Utils.applyDebugSetting` | still-owner | Runtime debug state glue. |
| `Utils.setOption` | still-owner | Central option sync (`KRT_Options` + `addon.options`). |
| `Utils.getPlayerName`, `Utils.getRaid`, `Utils.GetRaid`, `Utils.getRealmName`, `Utils.getUnitRank` | still-owner | Raid/runtime fallbacks while facades migrate. |

## Policy

1. New code should call owner modules directly when available.
2. Keep compat facades until all critical call-sites migrate.
3. Deprecated facades are documented via `@deprecated` tags in compat wrappers.
