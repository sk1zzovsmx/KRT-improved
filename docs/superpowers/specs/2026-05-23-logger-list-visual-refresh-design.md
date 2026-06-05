# KRT Logger List Visual Refresh Design

Date: 2026-05-23
Status: Approved for implementation planning

## Goal

Refresh the Logger list graphics while preserving the current runtime layout and behavior.

The visual direction is the approved "Polish + row rhythm" option from the current-state mockup. The Logger should
continue to feel like a Wrath-era raid log: Blizzard dialog frame, dark compact tables, yellow section titles, default
KRT buttons outside list panels, and green selected rows.

## Current Runtime Layout

The implementation must follow `Controllers/Logger.lua`, not the raw five-panel XML arrangement.

`refreshLoggerTabLayout()` currently defines two runtime layouts:

- Loot tab:
  - `KRTLoggerRaids`: `335x430`, anchored at the left of `KRTLoggerHistory`.
  - `KRTLoggerLoot`: `600x430`, anchored to the right of `KRTLoggerRaids`.
- Attendance tab:
  - `KRTLoggerRaids`: `335x430`.
  - `KRTLoggerRaidAttendees`: `265x430`.
  - `KRTLoggerBosses`: `335x430`.

`KRTLoggerBossAttendees` remains hidden in the current tab layout. This refresh must not reintroduce the old
simultaneous five-panel arrangement.

## Scope

In scope:

- Improve Logger row backgrounds, separators, selected state, and focus state.
- Make table headers visually clearer without changing XML script policy.
- Improve scrollbar/list gutter treatment inside Logger panels.
- Slightly increase row rhythm where useful, especially loot rows.
- Redistribute Logger loot column widths so item and winner text have more usable room.
- Preserve the existing loot item icon contract: approximately `28x28` click target, centered `26x26` texture, and
  a quickslot-like border outside the icon.

Out of scope:

- Changing Logger data flow, services, actions, sort behavior, selection behavior, or multi-select behavior.
- Introducing Ace dependencies or new vendored UI libraries.
- Adding XML `<Scripts>` blocks.
- Replacing the current tab layout.
- Adding new SavedVariables.
- Changing user-facing Logger strings except if a label is already wrong or clipped because of the visual refresh.

## Implementation Shape

Most work should stay in `!KRT/Controllers/Logger.lua` and shared UI primitives:

- `styleLoggerPanel(frameName)`:
  - Keep dark compact panel treatment.
  - Ensure title/header colors are consistent across runtime tabs.
  - Optionally tune panel backdrop and border colors.

- `styleLoggerHeader(header)`:
  - Improve header text contrast and alignment.
  - Avoid per-header one-off behavior unless required by existing column widths.

- `styleLoggerRow(row)`:
  - Own Logger-specific base row textures.
  - Add or tune alternating row background support if it can be done without fighting row reuse.
  - Keep row visual work idempotent because list rows are pooled/reused.

- `UIRowVisuals.SetRowSelected(row, cond)` and `UIRowVisuals.SetRowFocused(row, cond)`:
  - Preserve existing non-Logger behavior.
  - Keep Logger selection green.
  - Make Logger focus/hover readable but secondary to selected state.

- Logger list drawers:
  - Keep existing list controller contracts and row templates.
  - Adjust row height return values only where needed.
  - Avoid changing `ListController` globally unless the change is truly generic and harmless for other lists.

- Loot column widths:
  - Prefer a small Logger-local width helper, matching the existing `applyRaidRowColumnWidths()` pattern.
  - Apply widths to both loot headers and loot row parts.
  - Give more room to `Item` and `Winner`; keep `Type`, `Roll`, and `Time` compact.

## Behavior And Data Flow

Behavior must remain unchanged:

- Clicking rows still selects the same raid, boss, player, or loot item.
- Right-click/context behavior on loot rows remains unchanged.
- Multi-select scope keys remain unchanged.
- Sort headers continue to work for the raid list.
- `ListController` still owns row acquisition, scroll child sizing, and deferred refresh.
- Logger UI refresh stays event-driven through existing controller/list mechanisms.

## Testing And Verification

Run focused static checks after implementation:

- `py -3 tools/krt.py repo-quality-check --check ui-binding`
- `py -3 tools/krt.py repo-quality-check --check lua-syntax`
- `py -3 tools/krt.py repo-quality-check --check lua-uniformity`

Run targeted architecture scans:

- Confirm no Logger XML inline scripts were introduced.
- Confirm no service-to-controller/widget references were introduced.
- Confirm no direct changes under `!KRT/Libs/*`.

Manual in-game checklist:

- Open `/krt`, switch between Loot and Attendance tabs.
- Verify Logger rows render with stable heights and no overlapping text.
- Verify scrollbars still scroll full lists.
- Verify selected rows remain visible and green.
- Verify loot icons retain the intended click target and visual border.
- Verify row clicks, loot right-click actions, and raid deletion/edit controls still work.

## Risks

- WoW 3.3.5 frame texture layering can differ from browser mockups. Keep textures simple and verify in game.
- Row pooling can retain stale visual state. Styling must be idempotent and reset per draw when row state varies.
- Changing row heights can affect scroll child height. Use `ListController.CreateRowDrawer()` return values deliberately.
- Column width changes can expose truncation in localized or long item/source names. Prefer truncation over overlap.
