# UI Coding Rules

Reusable UI rules for KRT-owned XML and Lua code. These rules optimize for repeatable layout,
stable spacing, and fewer one-off border, scroll, table, and editbox fixes.

## Scope

Applies to:

- `!KRT/UI/**/*.xml`
- `!KRT/Controllers/**/*.lua`
- `!KRT/Widgets/**/*.lua`
- `!KRT/Modules/UI/**/*.lua`

Do not apply these rules to vendored libraries under `!KRT/Libs/**`.

Ground rules still come from `AGENTS.md`: WotLK 3.3.5a, Interface 30300, Lua 5.1,
XML layout-only, no Ace2/Ace3, no new non-frame globals unless explicitly required.

## 1) XML vs Lua Ownership

XML owns static layout:

- frame type, parent, inherited template, size, anchors, static layers, static textures
- named child widgets that Lua needs to acquire by `$parent` naming
- initial hidden state and base frame attributes such as `movable`, `enableMouse`, and `frameStrata`

Lua owns behavior and runtime layout:

- `SetScript`, `HookScript`, event binding, refresh, sorting, filtering, focus handling
- dynamic row creation, scroll-child sizing, scrollbar insets, row highlights, and button state
- localized text assignment, tooltips, editbox resets, and role-gated enable/disable state

The WoW XML schema supports `<Scripts>` and widget handler tags, but KRT does not use them.
Keep all widget handlers in Lua so ownership and review stay local to Controllers, Widgets, or
shared `Modules/UI/*` helpers.

## 2) Shared Template Policy

Shared XML templates should describe UI role, not historical implementation. Keep the `KRT` prefix
because WoW XML template names are global, but prefer semantic role names for new shared templates:

| Role | Preferred template name |
| --- | --- |
| Standard top-level window | `KRTWindowTemplate` |
| Compact popup/dialog | `KRTDialogTemplate` |
| Inner framed section | `KRTPanelTemplate` |
| Standard action button | `KRTActionButtonTemplate` |
| Item or icon button | `KRTIconButtonTemplate` or `KRTItemIconButtonTemplate` |
| Ordinary list scroll area | `KRTListScrollFrameTemplate` |
| Output/import text scroll area | `KRTTextScrollFrameTemplate` |
| Single-line text input | `KRTTextInputTemplate` |
| Numeric input | `KRTNumericInputTemplate` |
| Repeated table row | `KRTTableRowTemplate` |
| Table/list header row | `KRTHeaderRowTemplate` |

Current historical templates remain valid compatibility surfaces:

- `KRTFrameTemplate`
- `KRTSimpleFrameTemplate`
- `KRTButtonTemplate`
- `KRTItemButtonTemplate`
- `KRTScrollFrameTemplate`
- `KRTEditBoxTemplate`
- `KRTEditBoxSimpleTemplate`

Do not mass-rename existing XML templates in normal feature work. Introduce semantic templates as
compatibility-safe wrappers or replacements during a controlled UI migration, then update callers in
small batches with focused verification.

For example, a migration can keep old names alive while moving new code to semantic names:

```xml
<Frame name="KRTWindowTemplate" inherits="UIPanelDialogTemplate" virtual="true">
    ...
</Frame>

<Frame name="KRTFrameTemplate" inherits="KRTWindowTemplate" virtual="true" />
```

Add a new XML template only when at least two feature surfaces will reuse it, or when a single
surface has enough repeated child widgets that a template reduces real duplication. If a visual
choice is shared across features, put it in `!KRT/UI/Templates/Common.xml` or `!KRT/Modules/UI/*`,
not inside one feature controller.

## 3) Standard UI Contracts

These contracts are the default for KRT Controller and Widget UI work. Use them before writing
feature-local frame lifecycle, list refresh, row highlight, editbox, or visual helper code.

### Module UI Contract

Any Controller or Widget that owns a feature frame should use `UI.Scaffold.DefineModule(cfg)` unless
the file documents a specific exception.

Standard scaffold shape:

```lua
local UI = feature.UI
local Scaffold = UI.Scaffold

Scaffold.DefineModule({
    module = module,
    getFrame = getFrame,
    acquireRefs = acquireRefs,
    bind = bindHandlers,
    localize = localize,
    refresh = refreshUI,
    initFrameOpts = {
        enableDrag = true,
    },
})
```

Allowed owner hooks:

- `getFrame`
- `acquireRefs`
- `bindHandlers`
- `localize`
- `refreshUI`

Scaffold-owned methods:

- `BindUI`
- `EnsureUI`
- `Toggle`
- `Hide`
- `RequestRefresh`
- `MarkDirty`

Do not hand-roll these methods in feature code unless the module cannot fit the scaffold contract.
Keep lifecycle state in `addon.UI.ModuleState` with the canonical fields `Loaded`, `Bound`,
`Localized`, `Dirty`, `Reason`, and `FrameName`. Local references to that state should be named
`uiState`, so `UI` remains the `feature.UI` namespace.

### List and Table Contract

Repeated list/table UIs should use `addon.UI.Lists.CreateController(cfg)`.

Standard list shape:

```lua
local list = Lists.CreateController({
    keyName = "FeatureName",
    rowTmpl = "KRTTableRowTemplate",
    _rowParts = { "Name", "Value", "ActionBtn" },

    rowName = function(frameName, item, index)
        return frameName .. "Row" .. index
    end,

    getData = function(out)
        -- Fill out[] with display rows.
    end,

    drawRow = Lists.CreateRowRenderer(function(row, item, index)
        -- Assign texts, ids, icons, button state, and row-local display state.
    end),

    highlightId = function()
        return selectedId
    end,

    focusId = function()
        return focusedId
    end,

    sorters = sorters,
})
```

Required naming for standard list panels:

- `FrameNameScrollFrame`
- `FrameNameScrollFrameScrollChild`
- `FrameNameRow1`, `FrameNameRow2`, ...

Do not duplicate list-controller responsibilities in feature code:

- scroll-child width sync
- content-height calculation
- row reuse/hide behavior
- scrollbar right inset
- deferred refresh while width is unavailable
- selected/focused row visual refresh

### Row Visual Contract

Selectable rows use `addon.UI.Rows`.

Standard calls:

```lua
Rows.EnsureVisuals(row)
Rows.SetSelected(row, isSelected)
Rows.SetFocused(row, isFocused)
```

Feature code may set a semantic style flag, for example:

```lua
row._krtRowVisualStyle = "logger"
```

The texture creation, colors, blend modes, and pushed/selected/focused behavior stay in
`Modules/UI/Visuals.lua`. Do not create separate selected/focus textures in a Controller or Widget
when `UI.Rows` can represent the state.

### EditBox Contract

Editbox handlers should use `EditBoxes.BindHandlers(frameName, specs, requestRefreshFn)` when
the widget is named by the standard frame suffix pattern.

Standard editbox binding:

```lua
EditBoxes.BindHandlers(frameName, {
    {
        suffix = "Name",
        onEscape = function(editBox)
            EditBoxes.Reset(editBox)
        end,
        onEnter = function(editBox)
            saveName(editBox:GetText())
            editBox:ClearFocus()
        end,
        onFocusLost = function(editBox)
            validateName(editBox:GetText())
        end,
    },
}, function()
    module:RequestRefresh("editbox")
end)
```

Use shared editbox helpers:

- `EditBoxes.Reset(editBox)`
- `EditBoxes.Reset(editBox, true)`
- `EditBoxes.SetValue(editBox, value, focus)`

Validation belongs in the owning Controller or Widget. Persistence belongs in Database or Services.
Do not put validation or behavior in XML.

### Shared Visuals Contract

Shared UI behavior belongs in the existing `Modules/UI/*` owners:

| Owner | Responsibility |
| --- | --- |
| `Modules/UI/Frames.lua` | frame lifecycle, refs, editbox helpers, tooltips |
| `Modules/UI/Visuals.lua` | row visuals, primitives, pixel sizing |
| `Modules/UI/Effects.lua` | glow/effect internals |
| `Modules/UI/ListController.lua` | repeated scroll/list/table refresh |
| `Modules/UI/OptionsLayout.lua` | options panel row layout |
| `Modules/UI/Facade.lua` | widget routing |

Feature code may request visual state, but should not duplicate reusable border, spacing, highlight,
glow, pixel-sizing, scrollbar, or options-row placement logic.

### Service Boundary Contract

Services are UI-free. Code under `!KRT/Services/*` must not reference frames, widgets, parent
controllers, or shared UI helper modules.

Services may return:

- state
- display models
- validation results
- capability decisions
- events through `addon.Bus`

Controllers and Widgets consume those contracts and render the UI.

Correct pattern:

```lua
local model = Rolls:GetDisplayModel()
renderRollRows(model.rows)
```

Incorrect pattern inside Services:

```lua
_G.KRTMaster:Show()
```

## 4) Layout Tokens

Prefer these baseline dimensions unless an existing feature has a stronger local pattern:

| Purpose | Size |
| --- | ---: |
| Window inner padding | 12-16 px |
| Section gap | 12-16 px |
| Row gap | 4-8 px |
| Compact table row height | 18-22 px |
| Dense table header height | 18-22 px |
| Standard button height | 25 px |
| Compact icon button target | 28-32 px |
| EditBox height | 20-22 px |
| EditBox horizontal text inset | 4-6 px |
| Scrollbar right reserve | measured by helper, otherwise about 22-28 px |

Rules:

- Do not anchor command buttons to variable-width or wrapped description text.
- Give action columns fixed widths before laying out descriptive text.
- Use fixed row heights for tables and scroll lists unless the row is deliberately multiline.
- If rows can be multiline, calculate and set the row height in one Lua owner, then set the scroll
  child height from the same calculation.
- Avoid per-feature magic spacing when a value can become an option in `UI.Layout`, a template
  dimension, or a local constant block.

## 5) ScrollFrame Rules

Standard scrollframe naming:

```xml
<ScrollFrame name="$parentScrollFrame" inherits="KRTListScrollFrameTemplate">
    ...
</ScrollFrame>
```

Use `KRTScrollFrameTemplate` only as the current compatibility fallback until semantic scrollframe
templates exist in the addon.

Expected runtime names:

- `FrameNameScrollFrame`
- `FrameNameScrollFrameScrollChild`

Rules:

- The scroll child must have an explicit width before rows are positioned.
- The scroll child height must be `max(contentHeight, scrollFrame:GetHeight())`.
- Call `UpdateScrollChildRect()` when available after width/height changes.
- Account for the visible scrollbar when anchoring row right edges.
- Do not rely on `UIPanelScrollFrameTemplate` to infer content size from hidden or zero-width rows.
- Defer list refresh if the scrollframe width is not available yet.

For repeated rows, prefer `addon.UI.Lists.CreateController(cfg)`. It already handles
deferred refresh, scroll-child width sync, row reuse, right inset, content height, and selection
visual refresh.

## 6) Table and Row Rules

Tables should be built from predictable columns:

- define local constants for row height, header height, icon width, command width, and column gaps
- anchor from right to left for fixed command/count columns
- let the primary text column fill the remaining middle width
- keep row child names consistent with the row template suffixes
- reuse row frames instead of destroying and recreating them during normal refresh
- hide unused rows after each refresh

Selection and focus visuals:

- use `addon.UI.Rows.EnsureVisuals(row)` for selectable rows
- use `addon.UI.Rows.SetSelected(row, selected)` for selected state
- use `addon.UI.Rows.SetFocused(row, focused)` when focus differs from selection
- keep custom row highlight colors in `Modules/UI/Visuals.lua`, not in feature code

Sorting:

- keep sort state in the controller/list owner
- expose sort through public UI verbs such as `Sort`
- do not make services know about table columns or selected row frames

## 7) EditBox Rules

XML:

- use `KRTTextInputTemplate` or `KRTNumericInputTemplate` when available
- use `KRTEditBoxTemplate` or `KRTEditBoxSimpleTemplate` only as compatibility fallbacks
- set `autoFocus="false"` unless the field is an intentional popup primary input
- set `letters` or `numeric` when the input contract is known
- for multiline output/import boxes, make the scrollframe and editbox dimensions explicit

Lua:

- bind handlers with `EditBoxes.BindHandlers(frameName, specs, requestRefreshFn)` when possible
- reset with `EditBoxes.Reset(editBox, hide)`
- set and focus with `EditBoxes.SetValue(editBox, value, focus)`
- trim and validate before persisting or sending chat output
- clear focus on escape and after accepted popup input

Do not put editbox validation in XML. Validation belongs in the owning Controller or Widget, while
data rules belong in Services or Database code.

## 8) Borders, Highlights, and Effects

Shared visual rules:

- common frame borders belong in XML templates
- reusable primitive sizing, show/hide, and text helpers belong in `Modules/UI/Visuals.lua`
- glow effects belong in `Modules/UI/Effects.lua`
- feature code may request a visual state, but should not duplicate glow or border internals

When a new border or highlight is needed, first decide whether it is:

- a frame template concern: add or reuse XML template structure
- a row visual concern: update `UI.Rows`
- a button/effect concern: update `UI.Effects`
- a one-off feature concern: keep it local only if it truly will not be reused

## 9) Options Panel Layout

Use `addon.UI.Layout.ApplyRows(frameOrName, rows, cfg)` for option panels where feasible.

Rows with action buttons must reserve a fixed-width command column. The description text column
must never control the command button position. This avoids layout drift when localization, wrapping,
or future labels change.

Preferred row types:

- `section` for group labels
- `body` or `text` for explanatory rows
- `check` for boolean options
- `command` for title/description plus one action button
- `editCommand` for title/description plus editbox and button
- `dropdown` for title/description plus dropdown
- `buttonRow` for compact command groups

## 10) FrameXML and WotLK Compatibility

The Warcraft Wiki and Wowpedia pages are useful for XML element names, widget hierarchy, and
FrameXML helper categories, but KRT targets the 3.3.5a client. Before using a FrameXML helper from
modern docs, verify it exists in a 3.3.5a FrameXML mirror or in the local client.

Do not use modern-only systems such as:

- `C_Timer`
- `C_*` namespaces
- `CreateFramePool`
- mixin-heavy SharedXML helpers from modern Retail
- atlas APIs such as `SetAtlas`
- modern NineSlice utilities

Use the local KRT helpers and 3.3.5-compatible Widget API instead.

## 11) UI Change Review Checklist

Before finishing a UI change, check:

- XML has no `<Scripts>` and no `<On...>` handlers.
- New frames inherit a semantic shared KRT template when one exists.
- Historical templates are kept as compatibility surfaces until a planned migration replaces them.
- Controller/Widget frame lifecycle uses `UI.Scaffold.DefineModule(cfg)` or documents an exception.
- ScrollFrame child width and height are explicitly set before refresh ends.
- Repeated tables/lists use `UI.Lists` unless the UI is static or documents an exception.
- Table rows have fixed heights or one owner that calculates dynamic heights.
- Selectable rows use `UI.Rows` for selected/focused visuals.
- Buttons sit in fixed command columns, not after wrapped text.
- EditBoxes use KRT templates, `autoFocus=false`, and shared `Frames` editbox helpers.
- User-facing strings are assigned from `addon.L`.
- Services do not reference frames, widgets, parent controllers, or UI lifecycle methods.
- New reusable borders, highlights, spacing, or effects live in `Modules/UI/*` or shared XML templates.
- WotLK/Lua 5.1 compatibility is preserved.

## References

- Warcraft Wiki: <https://warcraft.wiki.gg/wiki/XML_schema>
- Warcraft Wiki: <https://warcraft.wiki.gg/wiki/FrameXML_functions>
- Wowpedia: <https://wowpedia.fandom.com/wiki/XML_schema>
- Wowpedia: <https://wowpedia.fandom.com/wiki/FrameXML_functions>
