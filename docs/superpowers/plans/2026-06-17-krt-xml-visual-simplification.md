# KRT XML Visual Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Lua-created visual fallback objects where XML already owns the UI skeleton, while preserving dynamic runtime behavior and leaving LootCounter as its documented temporary exception.

**Architecture:** XML owns fixed frame, texture, fontstring, button, and hotspot skeletons. Lua resolves named XML children, applies runtime state, binds scripts, and may still create dynamic list rows from XML templates where the number of rows is data-driven. Fallback construction is removed from shared row visuals and Logger attendance icons after source-contract tests prove the XML path is authoritative.

**Tech Stack:** WoW WotLK 3.3.5a FrameXML, Interface 30300, Lua 5.1, KRT XML templates, repo-local Lua source-contract tests.

---

## Scope And Ownership Rules

This plan is a cleanup pass, not a redesign.

In scope:

- Remove XML-owned visual fallback creation from `!KRT/Modules/UI/Visuals.lua`.
- Remove Logger attendance spec icon fallback buttons/textures from `!KRT/Controllers/Logger.lua`.
- Move Logger inspect item icon instances into `!KRT/UI/Logger.xml` so Lua resolves them instead of creating them.
- Move Reserves row tooltip hotspots into `!KRT/UI/ReservesTemplates.xml` so Lua binds behavior only.
- Update source-contract tests so future regressions cannot reintroduce fallback visual construction.
- Update generated API docs if the public function inventory changes.

Out of scope:

- Do not migrate `!KRT/Widgets/LootCounter.lua`. It remains the documented temporary exception.
- Do not remove dynamic list row creation from `!KRT/Modules/UI/ListController.lua`.
- Do not remove dynamic row creation from `!KRT/Widgets/RaidGrid.lua`, `!KRT/Widgets/ReservesUI.lua`, or Master item selection when the row count is data-driven and the frame is created from an XML template.
- Do not remove runtime glow/effect construction from `!KRT/Modules/UI/Effects.lua`.
- Do not remove hidden driver frames or hidden tooltip frames such as `Modules/UI/Frames.lua` and `Modules/Item.lua`.

## Files

Modify:

- `!KRT/Modules/UI/Visuals.lua`
  - Resolve XML row/header/log row/master spec-icon parts only.
  - Remove `Rows._fallbackStats`, `Rows.GetFallbackStats`, and all `CreateTexture` fallback branches.
- `!KRT/Controllers/Logger.lua`
  - Resolve attendance inspect/spec icon XML children only.
  - Remove `CreateFrame` and `CreateTexture` fallback branches for attendance icons.
- `!KRT/UI/Logger.xml`
  - Add named inspect item icon child buttons to `KRTLoggerRaidAttendeeButton`.
- `!KRT/UI/ReservesTemplates.xml`
  - Add named tooltip hotspot child buttons to `KRTReserveRowTemplate`.
- `!KRT/Widgets/ReservesUI.lua`
  - Resolve XML hotspot children and bind scripts without creating hotspot buttons.
- `!KRT/UI/README.md`
  - Document the no-fallback policy and the allowed dynamic exceptions.
- `tests/ui_xml_homogenization_source_spec.lua`
  - Add source-contract assertions for removed fallbacks and XML-owned replacements.
- `tests/logger_visual_refresh_spec.lua`
  - Update visual ownership assertions to expect XML resolution rather than fallback creation.
- `tests/master_roll_row_visuals_spec.lua`
  - Make the master roll row spec icon test use the XML part and fail on runtime texture fallback creation.
- `docs/FUNCTION_REGISTRY.csv`
  - Refresh if `Rows.GetFallbackStats` removal changes generated inventory.
- `docs/FN_CLUSTERS.md`
  - Refresh if generated inventory changes.
- `docs/TREE.md`
  - Refresh if pre-commit updates it.

Do not modify:

- `!KRT/Widgets/LootCounter.lua`
- `!KRT/UI/LootCounter.xml`
- Vendored libraries under `!KRT/Libs/*`

---

### Task 1: Add Source-Contract Guards For XML-Only Visual Ownership

**Files:**
- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `tests/logger_visual_refresh_spec.lua`

- [ ] **Step 1: Add assertions that shared row visuals no longer create fallback textures**

In `tests/ui_xml_homogenization_source_spec.lua`, after the existing row visual XML assertions around `commonXml`, `visuals`, and `loggerXml`, add:

```lua
assertNotContains(visuals, "Rows._fallbackStats", "row visual fallback diagnostics must be removed after XML ownership is authoritative")
assertNotContains(visuals, "Rows.GetFallbackStats", "row visual fallback accessor must be removed with fallback construction")
assertNotContains(visuals, "row:CreateTexture", "shared row visuals must not create XML-owned row textures in Lua")
assertNotContains(visuals, "header:CreateTexture", "shared row visuals must not create XML-owned logger header textures in Lua")
assertNotContains(visuals, "row:SetPushedTexture", "selectable row pushed texture must be XML-owned")
assertNotContains(visuals, "row._krtSpecIcon", "master roll spec icon fallback cache must be removed")
assertContains(visuals, "resolveRowTextures", "row visuals must resolve XML row textures by name")
assertContains(visuals, "resolveLoggerHeaderTab", "logger header visuals must resolve XML header chrome by name")
assertContains(visuals, '_G[rowName .. "SpecIcon"]', "master roll rows must resolve XML spec icon by name")
```

- [ ] **Step 2: Add assertions that Logger attendance icons are XML-owned**

In `tests/ui_xml_homogenization_source_spec.lua`, near the existing Logger inspect/spec assertions, add:

```lua
assertContains(loggerXml, "$parentInspectItemIcon1", "raid attendance rows must expose inspect icon slot 1")
assertContains(loggerXml, "$parentInspectItemIcon17", "raid attendance rows must expose inspect icon slot 17")
assertNotContains(logger, 'CreateFrame("Button", iconName, row, "KRTLoggerInspectItemIconButtonTemplate")', "logger inspect icon slots must be XML-owned")
assertNotContains(logger, 'CreateFrame("Button", nil, row)', "logger attendance icon fallbacks must be removed")
assertNotContains(logger, 'icon:CreateTexture(nil, "ARTWORK")', "logger attendance icon textures must come from XML")
assertContains(logger, '_G[iconName .. "Texture"]', "logger attendance icons must resolve XML icon textures")
```

- [ ] **Step 3: Add assertions that Reserves hotspots are XML-owned**

In `tests/ui_xml_homogenization_source_spec.lua`, near the Reserves row separator assertions, add:

```lua
assertContains(reservesXml, "$parentNameHotspot", "reserve rows must expose a name tooltip hotspot")
assertContains(reservesXml, "$parentPlayersHotspot", "reserve rows must expose a players tooltip hotspot")
assertContains(reservesUi, "NameHotspot", "ReservesUI must resolve XML name hotspot")
assertContains(reservesUi, "PlayersHotspot", "ReservesUI must resolve XML players hotspot")
assertNotContains(reservesUi, 'CreateFrame("Button", nil, row.textBlock)', "ReservesUI must not create tooltip hotspot buttons in Lua")
```

- [ ] **Step 4: Update Logger visual source-contract names**

In `tests/logger_visual_refresh_spec.lua`, replace:

```lua
assert(visuals:find("ensureLoggerHeaderTab", 1, true), "Logger headers must render visible tab chrome through shared visuals")
```

with:

```lua
assert(visuals:find("resolveLoggerHeaderTab", 1, true), "Logger headers must resolve XML tab chrome through shared visuals")
```

Then add these assertions near the existing attendance icon checks:

```lua
assert(loggerXml:find("$parentInspectItemIcon1", 1, true), "Attendance XML must define the first inspect icon slot")
assert(loggerXml:find("$parentInspectItemIcon17", 1, true), "Attendance XML must define the final inspect icon slot")
assert(not logger:find('CreateFrame("Button", nil, row)', 1, true), "Logger attendance spec icons must not use unnamed Lua fallback buttons")
assert(not logger:find('icon:CreateTexture(nil, "ARTWORK")', 1, true), "Logger attendance icon textures must be XML-owned")
```

- [ ] **Step 5: Run the focused source tests and confirm they fail**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/logger_visual_refresh_spec.lua
```

Expected:

- `tests/ui_xml_homogenization_source_spec.lua` fails on current fallback creation strings.
- `tests/logger_visual_refresh_spec.lua` fails because `resolveLoggerHeaderTab` and XML inspect item slots do not exist yet.

---

### Task 2: Remove Visual Fallback Construction From Shared Row Visuals

**Files:**
- Modify: `!KRT/Modules/UI/Visuals.lua`
- Modify: `tests/master_roll_row_visuals_spec.lua`

- [ ] **Step 1: Update the Visuals ownership header**

In `!KRT/Modules/UI/Visuals.lua`, replace:

```lua
-- ui ownership: Lua applies row/panel visual state and keeps XML-template fallbacks only.
```

with:

```lua
-- ui ownership: XML owns row/header visual skeletons; Lua resolves named parts and applies runtime state.
```

- [ ] **Step 2: Remove fallback stats**

Delete this block from `!KRT/Modules/UI/Visuals.lua`:

```lua
Rows._fallbackStats = Rows._fallbackStats or {
    selectable = 0,
    loggerHeader = 0,
    loggerRow = 0,
    masterSpecIcon = 0,
}
```

Also delete this public method:

```lua
function Rows.GetFallbackStats()
    return Rows._fallbackStats
end
```

- [ ] **Step 3: Replace row texture fallback resolution**

Replace the current `ensureRowTextures(row)` helper with:

```lua
local function resolveRowTextures(row)
    if not row or row._krtVisualsResolved then
        return
    end

    local rowName = row.GetName and row:GetName() or nil
    if rowName then
        row._krtSelTex = row._krtSelTex or _G[rowName .. "SelectedTexture"]
        row._krtFocusTex = row._krtFocusTex or _G[rowName .. "FocusTexture"]
    end

    if row._krtSelTex and row._krtSelTex.Hide then
        row._krtSelTex:Hide()
    end
    if row._krtFocusTex and row._krtFocusTex.Hide then
        row._krtFocusTex:Hide()
    end

    if row._krtSelTex and row._krtSelTex.SetDrawLayer then
        row._krtSelTex:SetDrawLayer("BORDER")
    end
    if row._krtFocusTex and row._krtFocusTex.SetDrawLayer then
        row._krtFocusTex:SetDrawLayer("BORDER")
    end

    row._krtVisualsResolved = true
end
```

Replace calls to `ensureRowTextures(row)` with `resolveRowTextures(row)` in:

```lua
function Rows.EnsureVisuals(row)
function Rows.SetSelected(row, cond)
function Rows.SetFocused(row, cond)
```

- [ ] **Step 4: Replace logger header fallback resolution**

Replace `ensureLoggerHeaderTab(header)` with:

```lua
local function resolveLoggerHeaderTab(header)
    if not header or header._krtHeaderTab then
        return
    end

    local headerName = header.GetName and header:GetName() or nil
    if headerName then
        header._krtHeaderFill = _G[headerName .. "Fill"]
        header._krtHeaderTop = _G[headerName .. "Top"]
        header._krtHeaderBottom = _G[headerName .. "Bottom"]
        header._krtHeaderLeft = _G[headerName .. "Left"]
        header._krtHeaderRight = _G[headerName .. "Right"]
    end

    if header._krtHeaderFill and header._krtHeaderFill.SetDrawLayer then
        header._krtHeaderFill:SetDrawLayer("BACKGROUND")
    end
    if header._krtHeaderTop and header._krtHeaderTop.SetDrawLayer then
        header._krtHeaderTop:SetDrawLayer("BORDER")
    end
    if header._krtHeaderBottom and header._krtHeaderBottom.SetDrawLayer then
        header._krtHeaderBottom:SetDrawLayer("BORDER")
    end
    if header._krtHeaderLeft and header._krtHeaderLeft.SetDrawLayer then
        header._krtHeaderLeft:SetDrawLayer("BORDER")
    end
    if header._krtHeaderRight and header._krtHeaderRight.SetDrawLayer then
        header._krtHeaderRight:SetDrawLayer("BORDER")
    end

    header._krtHeaderTab = true
end
```

In `styleLoggerHeader(header)`, replace:

```lua
ensureLoggerHeaderTab(header)
```

with:

```lua
resolveLoggerHeaderTab(header)
```

- [ ] **Step 5: Replace logger row fallback creation**

Replace the body of `Rows.StyleLoggerRow(row)` with:

```lua
function Rows.StyleLoggerRow(row)
    if not row then
        return
    end

    row._krtRowVisualStyle = "logger"
    local rowName = row.GetName and row:GetName() or nil
    if rowName then
        row._krtLoggerBg = row._krtLoggerBg or _G[rowName .. "LoggerBg"]
        row._krtLoggerLine = row._krtLoggerLine or _G[rowName .. "LoggerBottomLine"]
    end

    if row._krtLoggerBg and row._krtLoggerBg.SetDrawLayer then
        row._krtLoggerBg:SetDrawLayer("BACKGROUND")
    end
    if row._krtLoggerLine and row._krtLoggerLine.SetDrawLayer then
        row._krtLoggerLine:SetDrawLayer("BORDER")
        row._krtLoggerLine:SetTexture(0.32, 0.30, 0.25, 0.42)
    end
end
```

- [ ] **Step 6: Remove Master roll spec icon fallback creation**

In `Rows.DrawMasterRollRow(row, data, onClick)`, replace:

```lua
local specIcon = ui and (ui.specIcon or ui.SpecIcon) or row._krtSpecIcon
if hasSpecIcon and not specIcon and row.CreateTexture then
    specIcon = row:CreateTexture(nil, "ARTWORK")
    row._krtSpecIcon = specIcon
    Rows._fallbackStats.masterSpecIcon = Rows._fallbackStats.masterSpecIcon + 1
end
```

with:

```lua
local specIcon = ui and (ui.specIcon or ui.SpecIcon) or nil
```

Keep the existing `if specIcon then` block. Lua still applies dynamic texture, visibility, and anchoring state to the XML-owned spec icon.

- [ ] **Step 7: Update the Master roll row test to require XML spec icon parts**

In `tests/master_roll_row_visuals_spec.lua`, replace `makeRow(name)` with:

```lua
local function makeRow(name)
    local row = {
        name = name,
    }

    function row:GetName()
        return self.name
    end

    function row:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end

    function row:CreateTexture()
        error("Rows.DrawMasterRollRow must use XML-owned spec icon parts", 2)
    end

    return row
end
```

Add the XML spec icon part to the first `parts` table:

```lua
local parts = {
    name = makeRegion(),
    roll = makeRegion(),
    counter = makeRegion(),
    info = makeRegion(),
    star = makeRegion(),
    specIcon = makeRegion(),
}
```

Replace the fallback assertions:

```lua
assert(row._krtSpecIcon, "spec icon should be created at runtime when template part is absent")
assertEquals(row._krtSpecIcon:GetTexture(), "Interface\\Icons\\Spell_Holy_HolyBolt", "spec texture should be assigned")
assertEquals(row._krtSpecIcon.shown, true, "spec icon should be visible")
assertEquals(row._krtSpecIcon.width, 12, "spec icon width should be stable")
assertEquals(row._krtSpecIcon.height, 12, "spec icon height should be stable")
assertEquals(#row._krtSpecIcon.points, 1, "spec icon should not accumulate anchors")
assertEquals(row._krtSpecIcon.points[1].x, 16, "spec icon should sit between star and name")
```

with:

```lua
assertEquals(parts.specIcon:GetTexture(), "Interface\\Icons\\Spell_Holy_HolyBolt", "xml spec texture should be assigned")
assertEquals(parts.specIcon.shown, true, "xml spec icon should be visible")
assertEquals(parts.specIcon.width, 12, "xml spec icon width should be stable")
assertEquals(parts.specIcon.height, 12, "xml spec icon height should be stable")
assertEquals(#parts.specIcon.points, 1, "xml spec icon should not accumulate anchors")
assertEquals(parts.specIcon.points[1].x, 16, "xml spec icon should sit between star and name")
```

Replace the second draw fallback assertions:

```lua
assertEquals(row._krtSpecIcon.shown, false, "spec icon should hide when spec data is absent")
assertEquals(#row._krtSpecIcon.points, 1, "spec icon anchors should remain stable across redraws")
```

with:

```lua
assertEquals(parts.specIcon.shown, false, "xml spec icon should hide when spec data is absent")
assertEquals(#parts.specIcon.points, 1, "xml spec icon anchors should remain stable across redraws")
```

- [ ] **Step 8: Run focused tests**

Run:

```powershell
lua tests/master_roll_row_visuals_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected:

- `master_roll_row_visuals_spec.lua` passes after `Rows.DrawMasterRollRow` stops creating fallback textures.
- `logger_visual_refresh_spec.lua` still fails until Logger inspect icon XML slots are added in Task 3.
- `ui_xml_homogenization_source_spec.lua` still fails until Logger and Reserves XML ownership updates are complete.

---

### Task 3: Make Logger Attendance Icons XML-Owned

**Files:**
- Modify: `!KRT/UI/Logger.xml`
- Modify: `!KRT/Controllers/Logger.lua`

- [ ] **Step 1: Add static inspect icon slots to `KRTLoggerRaidAttendeeButton`**

In `!KRT/UI/Logger.xml`, inside `KRTLoggerRaidAttendeeButton` `<Frames>`, after `$parentSecondarySpecIcon`, add the 17 inspect item icon buttons:

```xml
			<Button name="$parentInspectItemIcon1" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon2" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon3" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon4" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon5" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon6" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon7" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon8" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon9" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon10" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon11" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon12" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon13" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon14" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon15" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon16" inherits="KRTLoggerInspectItemIconButtonTemplate" />
			<Button name="$parentInspectItemIcon17" inherits="KRTLoggerInspectItemIconButtonTemplate" />
```

No anchors are needed here because Lua positions visible inspect icons dynamically relative to `InspectStatus`.

- [ ] **Step 2: Replace `ensureAttendanceInspectIcon` with XML resolution**

In `!KRT/Controllers/Logger.lua`, replace `ensureAttendanceInspectIcon(row, index, ui)` with:

```lua
local function getAttendanceInspectIcon(row, index, ui)
    if not row or not ui then
        return nil
    end
    row._krtAttendanceInspectIcons = row._krtAttendanceInspectIcons or {}
    local list = row._krtAttendanceInspectIcons
    local icon = list[index]
    if icon then
        return icon
    end

    local rowName = row.GetName and row:GetName() or nil
    local iconName = rowName and (rowName .. "InspectItemIcon" .. tostring(index)) or nil
    icon = iconName and _G[iconName] or nil
    if not icon then
        return nil
    end

    icon:EnableMouse(true)
    icon:SetSize(RAID_INSPECT_ICON_SIZE, RAID_INSPECT_ICON_SIZE)
    icon:SetID(index)
    icon.texture = iconName and _G[iconName .. "Texture"] or nil
    if not icon.texture then
        return nil
    end
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not icon:GetScript("OnEnter") then
        icon:SetScript("OnEnter", function(self)
            local link = self._krtItemLink
            if not link then
                return
            end
            if GameTooltip and GameTooltip.SetOwner and GameTooltip.SetHyperlink then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end
        end)
    end
    if not icon:GetScript("OnLeave") then
        icon:SetScript("OnLeave", function()
            if GameTooltip and GameTooltip.Hide then
                GameTooltip:Hide()
            end
        end)
    end
    list[index] = icon
    return icon
end
```

In `renderAttendanceInspectIcons(row, ui, playerNid, snapshot)`, replace:

```lua
local icon = ensureAttendanceInspectIcon(row, count, ui)
```

with:

```lua
local icon = getAttendanceInspectIcon(row, count, ui)
```

- [ ] **Step 3: Replace primary spec icon fallback resolution**

Replace `ensureAttendanceSpecIcon(row)` with:

```lua
local function getAttendanceSpecIcon(row)
    if not row then
        return nil
    end
    if row._krtAttendanceSpecIcon then
        return row._krtAttendanceSpecIcon
    end

    local rowName = row.GetName and row:GetName() or nil
    local iconName = rowName and (rowName .. "SpecIcon") or nil
    local icon = iconName and _G[iconName] or nil
    if not icon then
        return nil
    end

    icon:EnableMouse(true)
    icon:SetSize(RAID_SPEC_ICON_SIZE, RAID_SPEC_ICON_SIZE)
    icon.texture = iconName and _G[iconName .. "Texture"] or nil
    if not icon.texture then
        return nil
    end
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bindAttendanceSpecIconTooltip(icon)
    row._krtAttendanceSpecIcon = icon
    return icon
end
```

- [ ] **Step 4: Replace secondary spec icon fallback resolution**

Replace `ensureAttendanceSecondarySpecIcon(row)` with:

```lua
local function getAttendanceSecondarySpecIcon(row)
    if not row then
        return nil
    end
    if row._krtAttendanceSecondarySpecIcon then
        return row._krtAttendanceSecondarySpecIcon
    end

    local rowName = row.GetName and row:GetName() or nil
    local iconName = rowName and (rowName .. "SecondarySpecIcon") or nil
    local icon = iconName and _G[iconName] or nil
    if not icon then
        return nil
    end

    icon:EnableMouse(true)
    icon:SetSize(RAID_SPEC_ICON_SIZE, RAID_SPEC_ICON_SIZE)
    icon.texture = iconName and _G[iconName .. "Texture"] or nil
    if not icon.texture then
        return nil
    end
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bindAttendanceSpecIconTooltip(icon)
    row._krtAttendanceSecondarySpecIcon = icon
    return icon
end
```

In `setAttendanceSpecIcon(row, primarySpecIcon, secondarySpecIcon, primarySpecName, secondarySpecName)`, replace:

```lua
local primaryIcon = ensureAttendanceSpecIcon(row)
local secondaryIcon = ensureAttendanceSecondarySpecIcon(row)
```

with:

```lua
local primaryIcon = getAttendanceSpecIcon(row)
local secondaryIcon = getAttendanceSecondarySpecIcon(row)
```

- [ ] **Step 5: Run focused Logger tests**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected:

- Logger visual source contract passes.
- UI XML homogenization may still fail on Reserves hotspot assertions until Task 4 is complete.

---

### Task 4: Move Reserves Tooltip Hotspots Into XML

**Files:**
- Modify: `!KRT/UI/ReservesTemplates.xml`
- Modify: `!KRT/Widgets/ReservesUI.lua`

- [ ] **Step 1: Add XML hotspot buttons to reserve rows**

In `!KRT/UI/ReservesTemplates.xml`, inside `KRTReserveRowTemplate` `<Frames>`, after the `$parentTextBlock` frame, add:

```xml
			<Button name="$parentNameHotspot" enableMouse="true">
				<Size>
					<AbsDimension x="200" y="16" />
				</Size>
				<Anchors>
					<Anchor point="TOPLEFT" relativeTo="$parentTextBlock" relativePoint="TOPLEFT">
						<Offset>
							<AbsDimension x="0" y="0" />
						</Offset>
					</Anchor>
				</Anchors>
			</Button>
			<Button name="$parentPlayersHotspot" enableMouse="true">
				<Size>
					<AbsDimension x="200" y="16" />
				</Size>
				<Anchors>
					<Anchor point="BOTTOMLEFT" relativeTo="$parentTextBlock" relativePoint="BOTTOMLEFT">
						<Offset>
							<AbsDimension x="0" y="0" />
						</Offset>
					</Anchor>
				</Anchors>
			</Button>
```

- [ ] **Step 2: Resolve hotspot children during row initialization**

In `createReserveRow(parent, info, yOffset, index, isFirstInGroup)`, inside the `if not row._initialized then` block, after:

```lua
row.textBlock = _G[rowName .. "TextBlock"]
```

add:

```lua
row._nameHotspot = _G[rowName .. "NameHotspot"]
row._playersHotspot = _G[rowName .. "PlayersHotspot"]
```

- [ ] **Step 3: Remove Lua hotspot button creation**

In `setupReserveRowTooltip(row)`, replace the `if row.textBlock then ... end` block that creates `CreateFrame("Button", nil, row.textBlock)` with:

```lua
        if row.textBlock then
            row.textBlock:EnableMouse(false)
        end

        if row._nameHotspot then
            row._nameHotspot:SetFrameLevel(row.textBlock:GetFrameLevel() + 2)
            row._nameHotspot:EnableMouse(true)
            row._nameHotspot:SetScript("OnEnter", showItemTooltip)
            row._nameHotspot:SetScript("OnLeave", Tooltips.Hide)
        end

        if row._playersHotspot then
            row._playersHotspot:SetFrameLevel(row.textBlock:GetFrameLevel() + 2)
            row._playersHotspot:EnableMouse(true)
            row._playersHotspot:SetScript("OnEnter", showPlayersTooltip)
            row._playersHotspot:SetScript("OnLeave", Tooltips.Hide)
        end
```

Keep `updateReserveRowHotspots(row)` unchanged unless variable names are deliberately normalized. It already updates `_nameHotspot` and `_playersHotspot` widths and mouse state dynamically.

- [ ] **Step 4: Guard against missing textBlock before using frame level**

In the replacement block from Step 3, if `row.textBlock` can be nil, use this exact guarded variant instead:

```lua
        if row.textBlock then
            row.textBlock:EnableMouse(false)
        end

        local hotspotFrameLevel = row.textBlock and (row.textBlock:GetFrameLevel() + 2) or nil
        if row._nameHotspot then
            if hotspotFrameLevel then
                row._nameHotspot:SetFrameLevel(hotspotFrameLevel)
            end
            row._nameHotspot:EnableMouse(true)
            row._nameHotspot:SetScript("OnEnter", showItemTooltip)
            row._nameHotspot:SetScript("OnLeave", Tooltips.Hide)
        end

        if row._playersHotspot then
            if hotspotFrameLevel then
                row._playersHotspot:SetFrameLevel(hotspotFrameLevel)
            end
            row._playersHotspot:EnableMouse(true)
            row._playersHotspot:SetScript("OnEnter", showPlayersTooltip)
            row._playersHotspot:SetScript("OnLeave", Tooltips.Hide)
        end
```

Use the guarded variant if there is any uncertainty during implementation.

- [ ] **Step 5: Run focused Reserves/UI XML tests**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected:

- Passes after Visuals, Logger, and Reserves XML ownership updates are complete.

---

### Task 5: Document The Post-Fallback XML Ownership Policy

**Files:**
- Modify: `!KRT/UI/README.md`

- [ ] **Step 1: Add a no-fallback policy section**

In `!KRT/UI/README.md`, after the existing ownership description and before `## Temporary exceptions`, add:

```md
## Lua fallback policy

For XML-owned visual skeletons, Lua should resolve named XML children and apply runtime state only.

Do not add Lua fallbacks that recreate XML-owned textures, fontstrings, buttons, or static child frames.

Allowed Lua-created UI remains limited to:
- data-driven repeated rows created from XML templates;
- runtime-only effect frames under `Modules/UI/Effects.lua`;
- hidden driver or tooltip frames required by the WotLK 3.3.5a API;
- LootCounter internals while the temporary exception remains active.
```

- [ ] **Step 2: Keep LootCounter exception unchanged**

Confirm the existing `## Temporary exceptions` section still includes:

```md
### LootCounter
```

and still states that Lua owns dynamic header, row, section, button, count, spec-icon, and name skeletons.

---

### Task 6: Static Audit And Generated Docs Refresh

**Files:**
- Modify if generated: `docs/FUNCTION_REGISTRY.csv`
- Modify if generated: `docs/FN_CLUSTERS.md`
- Modify if generated: `docs/TREE.md`

- [ ] **Step 1: Check XML syntax**

Run:

```powershell
@'
import os
import xml.etree.ElementTree as ET

root = "!KRT"
for dirpath, _, files in os.walk(root):
    for name in files:
        if name.endswith(".xml"):
            path = os.path.join(dirpath, name)
            ET.parse(path)
            print("OK", path)
'@ | py -3 -
```

Expected:

- Every XML file prints `OK`.
- No parse errors.

- [ ] **Step 2: Check remaining Lua visual creation**

Run:

```powershell
rg -n "CreateFrame\(|CreateTexture\(|CreateFontString\(|SetPushedTexture\(|SetHighlightTexture\(|SetNormalTexture\(" !KRT/Modules !KRT/Widgets !KRT/Controllers !KRT/EntryPoints --glob "!**/Libs/**"
```

Expected allowed hits:

- `!KRT/Modules/UI/ListController.lua`: data-driven row creation and hidden defer frame.
- `!KRT/Modules/UI/Frames.lua`: hidden driver frame.
- `!KRT/Modules/UI/Effects.lua`: runtime effects.
- `!KRT/Modules/Item.lua`: hidden tooltip probe.
- `!KRT/EntryPoints/Minimap.lua`: dropdown menu frame.
- `!KRT/Widgets/RaidGrid.lua`: data-driven player buttons from `KRTRaidGridButtonTemplate`.
- `!KRT/Widgets/ReservesUI.lua`: data-driven reserve headers and rows from XML templates only.
- `!KRT/Widgets/LootCounter.lua`: documented temporary exception.
- `!KRT/Controllers/Master.lua`: dynamic item texture updates and data-driven item selection frames/buttons from XML templates.
- `!KRT/Controllers/Logger.lua`: dropdown menu frame only.

Unexpected hits after this plan:

- Any `CreateTexture` in `!KRT/Modules/UI/Visuals.lua`.
- Any `CreateFrame("Button", nil, row)` in `!KRT/Controllers/Logger.lua`.
- Any `icon:CreateTexture(nil, "ARTWORK")` in `!KRT/Controllers/Logger.lua`.
- Any `CreateFrame("Button", nil, row.textBlock)` in `!KRT/Widgets/ReservesUI.lua`.
- Any `SetPushedTexture` in `!KRT/Modules/UI/Visuals.lua`.

- [ ] **Step 3: Run focused Lua tests**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/master_roll_row_visuals_spec.lua
lua tests/screen_notice_runtime_spec.lua
lua tests/raid_grid_spec_icon_spec.lua
```

Expected:

- All listed tests pass.

- [ ] **Step 4: Run repo quality checks**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

- All checks pass with zero errors.

- [ ] **Step 5: Refresh generated docs if API catalog drift appears**

Run:

```powershell
py -3 tools/krt.py api-catalog-check
```

If this reports stale generated docs, keep the regenerated files and rerun:

```powershell
py -3 tools/krt.py api-catalog-check
```

Expected after refresh:

- `API catalogs are up to date.`

Do not hand-edit generated catalog files.

---

### Task 7: In-Game Smoke Checklist

**Files:**
- No code files.

- [ ] **Step 1: Enable script errors and reload**

Run in game:

```lua
/console scriptErrors 1
/reload
```

Expected:

- No Lua errors at login or reload.
- No XML load errors in `FrameXML.log` for `!KRT`.

- [ ] **Step 2: Test Logger History**

Check:

- Raid row selected and focused visuals are visible.
- Boss row selected and focused visuals are visible.
- Boss attendee row selected and focused visuals are visible.
- Loot row selected and focused visuals are visible.
- Header fill and borders are visible.
- Alternating row background is visible.
- Loot item menu still opens.

- [ ] **Step 3: Test Raid Attendance**

Check:

- Primary spec icon is visible and saturated.
- Secondary spec icon is visible and desaturated.
- Spec icon tooltip text still appears on hover.
- Inspect item icons are visible for ready snapshots.
- Inspect item icon tooltip still shows the item link.
- Force inspect button still works.

- [ ] **Step 4: Test Master Loot**

Check:

- Roll rows still render player name, roll, counter, and info.
- XML-owned spec icon beside the player name is visible when spec data exists.
- Spec icon hides when spec data is absent.
- Star plus spec icon layout is correct.
- Selected and focused row highlight remains visible.

- [ ] **Step 5: Test Reserves**

Check:

- Reserve rows render item icon, item name, source text, players text, quantity, and separators.
- Item-name tooltip hotspot still shows item tooltip.
- Players hotspot still shows player list tooltip.
- Collapsing and expanding reserve source headers still works.

- [ ] **Step 6: Confirm LootCounter was not migrated**

Check:

- LootCounter opens.
- Lua-created row/header/section internals still render.
- Plus/minus buttons still work.
- Announce/reset buttons still work.

---

### Task 8: Commit

**Files:**
- Stage only files changed by the implementation and generated docs refreshed by the repo tools.

- [ ] **Step 1: Review the diff**

Run:

```powershell
git diff --stat
git diff -- !KRT/Modules/UI/Visuals.lua !KRT/Controllers/Logger.lua !KRT/UI/Logger.xml !KRT/UI/ReservesTemplates.xml !KRT/Widgets/ReservesUI.lua tests/ui_xml_homogenization_source_spec.lua tests/logger_visual_refresh_spec.lua tests/master_roll_row_visuals_spec.lua !KRT/UI/README.md
```

Expected:

- No LootCounter migration.
- No XML `<Scripts>` or `<On...>` handlers.
- No Lua fallback texture/fontstring/button creation for XML-owned skeletons.
- No unrelated refactors.

- [ ] **Step 2: Stage files**

Run:

```powershell
git add -- !KRT/Modules/UI/Visuals.lua !KRT/Controllers/Logger.lua !KRT/UI/Logger.xml !KRT/UI/ReservesTemplates.xml !KRT/Widgets/ReservesUI.lua !KRT/UI/README.md tests/ui_xml_homogenization_source_spec.lua tests/logger_visual_refresh_spec.lua tests/master_roll_row_visuals_spec.lua docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/TREE.md
```

If any generated doc file was not modified, Git leaves it unchanged.

- [ ] **Step 3: Commit**

Run:

```powershell
git commit -m "refactor: remove XML visual Lua fallbacks"
```

Expected:

- Pre-commit passes.
- Commit is created.

---

## Execution Routing

Classifier for implementation: `complex-orchestrated`.

Reason:

- More than one file changes.
- Shared UI helpers, Logger controller, Reserves widget, XML templates, and source-contract tests are involved.
- The change removes compatibility fallback paths and therefore needs parent review plus in-game smoke.
- The implementation has more than three concrete steps.

Use this flow:

1. Parent reviews current inventory and this plan.
2. Parent delegates implementation to `spark_implementer` with one task at a time or a tightly bounded task batch.
3. Spark applies only the task instructions.
4. Parent reviews the diff after each task batch.
5. Parent runs the focused tests and repo checks.
6. Parent performs or requests in-game smoke confirmation before final commit.

## Self-Review

Spec coverage:

- Lua fallback removal is covered by Tasks 1, 2, 3, and 4.
- XML preference is covered by Tasks 2, 3, 4, and 5.
- Remaining dynamic creation is classified and audited in Task 6.
- LootCounter remains excluded in Scope and Task 7.

Placeholder scan:

- The plan contains no deferred implementation placeholders.

Type/name consistency:

- `resolveRowTextures`, `resolveLoggerHeaderTab`, `getAttendanceInspectIcon`, `getAttendanceSpecIcon`, and `getAttendanceSecondarySpecIcon` are named consistently where referenced.
