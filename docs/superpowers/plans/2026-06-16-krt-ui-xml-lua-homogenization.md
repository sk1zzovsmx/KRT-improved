# KRT UI XML Lua Homogenization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move fixed KRT UI visual structure into XML while keeping Lua responsible for runtime
behavior, state, data binding, dynamic row counts, tooltips, and fallbacks.

**Architecture:** Shared reusable visual skeletons load from `!KRT/UI/Templates/Common.xml` before
Lua. Concrete top-level frames stay included by `!KRT/KRT.xml`, while Lua lazily resolves named XML
children and keeps compatibility fallbacks until in-game validation proves each migration stable.
No XML `<Scripts>` are introduced.

**Tech Stack:** WoW 3.3.5a Interface 30300 XML, Lua 5.1, KRT UI helpers, repo `tools/krt.py`
quality gates, and existing Lua source-contract tests.

---

## Workflow Classification

Classification: `complex-orchestrated`.

## Parent Plan Summary

- Parent-approved goal: migrate fixed UI structure to XML while preserving Lua-owned runtime behavior, state, and bindings for Logger, LootCounter, Reserves, RaidGrid, ScreenNotice, and Master.
- Scope is limited to plan-defined files and checks; runtime behavior changes are deferred to explicit runtime-in-game validation and smoke tests.

Implementation must follow the repo 55to53 workflow:

- Parent analyzes and owns the final review.
- Use `code-mapper` before a task when ownership, load order, or call flow is unclear.
- Delegate each runtime-affecting task to `spark_implementer` with only the closed task steps.
- Parent reviews the diff after each task for scope, regressions, style, and check results.
- Keep fallbacks in the first pass; remove dead visual construction only after in-game smoke checks.

## File Structure

Create:

- `!KRT/UI/README.md`: UI ownership policy for XML versus Lua.
- `!KRT/UI/ScreenNotice.xml`: static screen notice frame and fontstrings.
- `!KRT/UI/RaidGrid.xml`: static RaidGrid top-level frame.
- `tests/ui_xml_homogenization_source_spec.lua`: source-contract checks for this migration.

Modify:

- `!KRT/!KRT.toc`: load-order comments only if template files are split; otherwise keep Common.xml.
- `!KRT/KRT.xml`: include `ScreenNotice.xml` and `RaidGrid.xml`.
- `!KRT/UI/Templates/Common.xml`: shared selectable row, raid grid button, and inspect icon templates.
- `!KRT/UI/Logger.xml`: logger header chrome, row backgrounds, row lines, spec icon XML children.
- `!KRT/UI/LootCounter.xml`: header, section, row templates, explicit scroll child and header.
- `!KRT/UI/ReservesTemplates.xml`: reserve row separators.
- `!KRT/Modules/UI/Frames.lua`: named-part helper if it reduces repeated `_G` lookups.
- `!KRT/Modules/UI/Visuals.lua`: resolve XML row/header/row-style parts before fallback creation.
- `!KRT/Modules/UI/ScreenNotice.lua`: resolve XML frame/fontstrings lazily before fallback creation.
- `!KRT/Widgets/RaidGrid.lua`: resolve XML frame parts and create dynamic buttons from XML template.
- `!KRT/Widgets/LootCounter.lua`: resolve XML header/row/section refs and keep runtime behavior.
- `!KRT/Widgets/ReservesUI.lua`: resolve XML row separators instead of creating them in Lua.
- `!KRT/Controllers/Logger.lua`: resolve XML spec/inspect icon parts where names are stable.
- `!KRT/Controllers/Master.lua`: instantiate the existing `KRTItemSelectionFrame` template.

Do not modify:

- `!KRT/Libs/*`.
- SavedVariables schemas.
- Service/controller public APIs.
- User-facing strings, unless a smoke test reveals a visible behavior change that needs
  `!KRT/CHANGELOG.md` under `## Unreleased`.

## Shared Test Harness

Use one source-contract test for migration ownership checks. Each task appends exact assertions
before changing production files, runs the test to confirm failure, then implements the slice.

The first version of `tests/ui_xml_homogenization_source_spec.lua` should start as:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function assertBefore(text, first, second, message)
    local firstIndex = text:find(first, 1, true)
    local secondIndex = text:find(second, 1, true)
    assert(firstIndex, "missing: " .. first)
    assert(secondIndex, "missing: " .. second)
    assert(firstIndex < secondIndex, message or (first .. " must appear before " .. second))
end

local uiReadme = read("!KRT/UI/README.md")
local commonXml = read("!KRT/UI/Templates/Common.xml")
local loggerXml = read("!KRT/UI/Logger.xml")
local lootCounterXml = read("!KRT/UI/LootCounter.xml")
local reservesXml = read("!KRT/UI/ReservesTemplates.xml")
local krtXml = read("!KRT/KRT.xml")
local visuals = read("!KRT/Modules/UI/Visuals.lua")
local frames = read("!KRT/Modules/UI/Frames.lua")
local screenNotice = read("!KRT/Modules/UI/ScreenNotice.lua")
local raidGrid = read("!KRT/Widgets/RaidGrid.lua")
local lootCounter = read("!KRT/Widgets/LootCounter.lua")
local reservesUi = read("!KRT/Widgets/ReservesUI.lua")
local logger = read("!KRT/Controllers/Logger.lua")
local master = read("!KRT/Controllers/Master.lua")

assertContains(uiReadme, "XML owns fixed visual structure", "UI README must document XML ownership")
assertContains(uiReadme, "Lua owns runtime behavior", "UI README must document Lua ownership")
assertContains(uiReadme, "Do not put addon behavior in XML", "UI README must forbid XML scripts")

print("ui xml homogenization source contract passed")
```

Run it with:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected first-run failure before Task 1 production edits:

```text
cannot open !KRT/UI/README.md
```

---

### Task 1: UI Ownership Policy And File Contracts

**Files:**

- Create: `!KRT/UI/README.md`
- Create: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/Modules/UI/Visuals.lua`
- Modify: `!KRT/Modules/UI/Frames.lua`
- Modify: `!KRT/Modules/UI/ListController.lua`
- Modify: `!KRT/Widgets/LootCounter.lua`
- Modify: `!KRT/Widgets/RaidGrid.lua`
- Modify: `!KRT/Modules/UI/ScreenNotice.lua`

- [ ] **Step 1: Add the failing source-contract test**

Create `tests/ui_xml_homogenization_source_spec.lua` with the exact harness from "Shared Test
Harness".

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL because `!KRT/UI/README.md` does not exist yet.

- [ ] **Step 3: Create the UI ownership policy**

Create `!KRT/UI/README.md`:

```md
# KRT UI Ownership Policy

XML owns fixed visual structure:
- top-level frames;
- reusable templates;
- static child widgets;
- fixed anchors, sizes, layers, backdrops, textures, and fontstrings;
- row and header skeletons.

Lua owns runtime behavior:
- controller logic;
- event handlers;
- data binding;
- list virtualization;
- dynamic row counts;
- scroll size calculation;
- conditional colors, textures, text, and visibility;
- tooltips;
- animation and effects;
- user-driven movement and positioning.

Do not put addon behavior in XML `<Scripts>`.
Use XML for layout and Lua for state.
```

- [ ] **Step 4: Add short ownership comments below existing Lua contract blocks**

Add these comments after the existing `-- events:` line in the named files.

In `!KRT/Modules/UI/Visuals.lua`:

```lua
-- ui ownership: Lua applies row/panel visual state and keeps XML-template fallbacks only.
```

In `!KRT/Modules/UI/Frames.lua`:

```lua
-- ui ownership: Lua owns frame binding, named-reference resolution, scripts, and refresh drivers.
```

In `!KRT/Modules/UI/ListController.lua`:

```lua
-- ui ownership: Lua owns list virtualization, row reuse, row placement, and scroll sizing.
```

In `!KRT/Widgets/LootCounter.lua`:

```lua
-- ui ownership: XML owns fixed counter skeletons; Lua owns counts, clicks, tooltips, and refresh.
```

In `!KRT/Widgets/RaidGrid.lua`:

```lua
-- ui ownership: XML owns fixed picker skeletons; Lua owns dynamic buttons, data, and selection.
```

In `!KRT/Modules/UI/ScreenNotice.lua`:

```lua
-- ui ownership: XML owns static notice frame parts; Lua owns text, sizing, timing, and fade state.
```

- [ ] **Step 5: Run the task test**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: PASS and prints `ui xml homogenization source contract passed`.

- [ ] **Step 6: Run lightweight syntax and diff checks**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
git diff --check
```

Expected: both PASS.

- [ ] **Step 7: Commit**

```powershell
git add -- !KRT/UI/README.md tests/ui_xml_homogenization_source_spec.lua !KRT/Modules/UI/Visuals.lua !KRT/Modules/UI/Frames.lua !KRT/Modules/UI/ListController.lua !KRT/Widgets/LootCounter.lua !KRT/Widgets/RaidGrid.lua !KRT/Modules/UI/ScreenNotice.lua
git commit -m "docs: document KRT UI ownership policy"
```

### Task 2: Shared Named-Part Helper

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/Modules/UI/Frames.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append these assertions before the final `print(...)`:

```lua
assertContains(frames, "function Frames.ResolveNamedPartsBySuffix", "Frames must expose suffix ref resolver")
assertContains(frames, "cacheField = cacheField or \"_krtRefs\"", "resolver must use the existing cache default")
assertContains(frames, "_G[parentName .. suffix]", "resolver must resolve XML children by parent suffix")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL on missing `Frames.ResolveNamedPartsBySuffix`.

- [ ] **Step 3: Add the helper**

In `!KRT/Modules/UI/Frames.lua`, add this public method after `Frames.GetNamedParts`:

```lua
function Frames.ResolveNamedPartsBySuffix(parent, map, cacheField)
    if not parent or type(map) ~= "table" then
        return nil
    end

    cacheField = cacheField or "_krtRefs"
    if parent[cacheField] then
        return parent[cacheField]
    end

    local parentName = parent.GetName and parent:GetName() or nil
    local refs = {}

    if parentName then
        for key, suffix in pairs(map) do
            refs[key] = _G[parentName .. suffix]
        end
    end

    parent[cacheField] = refs
    return refs
end
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/module_registry_ui_spec.lua
```

Expected: both PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT/Modules/UI/Frames.lua
git commit -m "feat: add shared UI named-part resolver"
```

### Task 3: Selectable Row XML Template And Visual Fallbacks

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/UI/Templates/Common.xml`
- Modify: `!KRT/Modules/UI/Visuals.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append:

```lua
assertContains(commonXml, "KRTSelectableRowButtonTemplate", "Common XML must define selectable row template")
assertContains(commonXml, "$parentSelectedTexture", "selectable rows must expose selected texture")
assertContains(commonXml, "$parentFocusTexture", "selectable rows must expose focus texture")
assertContains(commonXml, "$parentPushedTexture", "selectable rows must expose pushed texture")
assertContains(commonXml, "KRTSelectPlayerTemplate\" inherits=\"KRTSelectableRowButtonTemplate", "player select rows must inherit selectable visuals")
assertContains(visuals, "_krtVisualsResolved", "row visuals must cache XML/fallback resolution")
assertContains(visuals, "SelectedTexture", "row visuals must resolve XML selected texture")
assertContains(visuals, "FocusTexture", "row visuals must resolve XML focus texture")
assertContains(visuals, "PushedTexture", "row visuals must resolve XML pushed texture")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL on missing `KRTSelectableRowButtonTemplate`.

- [ ] **Step 3: Add the selectable row XML template**

In `!KRT/UI/Templates/Common.xml`, insert this template after `KRTActionButtonTemplate`:

```xml
	<!-- Selectable list row visual skeleton -->
	<Button name="KRTSelectableRowButtonTemplate" virtual="true">
		<Layers>
			<Layer level="BACKGROUND">
				<Texture name="$parentSelectedTexture"
					file="Interface\QuestFrame\UI-QuestTitleHighlight"
					alphaMode="ADD"
					hidden="true">
					<Anchors>
						<Anchor point="TOPLEFT" />
						<Anchor point="BOTTOMRIGHT" />
					</Anchors>
					<Color r="0.20" g="0.60" b="1.00" a="0.52" />
				</Texture>
			</Layer>
			<Layer level="ARTWORK">
				<Texture name="$parentFocusTexture"
					file="Interface\QuestFrame\UI-QuestTitleHighlight"
					alphaMode="ADD"
					hidden="true">
					<Anchors>
						<Anchor point="TOPLEFT" />
						<Anchor point="BOTTOMRIGHT" />
					</Anchors>
					<Color r="0.20" g="0.60" b="1.00" a="0.72" />
				</Texture>
			</Layer>
		</Layers>
		<PushedTexture name="$parentPushedTexture" file="Interface\Buttons\WHITE8x8">
			<Anchors>
				<Anchor point="TOPLEFT" />
				<Anchor point="BOTTOMRIGHT" />
			</Anchors>
			<Color r="1" g="1" b="1" a="0.08" />
		</PushedTexture>
	</Button>
```

- [ ] **Step 4: Make player selection rows inherit the shared visuals**

Change:

```xml
	<Button name="KRTSelectPlayerTemplate" virtual="true">
```

to:

```xml
	<Button name="KRTSelectPlayerTemplate" inherits="KRTSelectableRowButtonTemplate" virtual="true">
```

- [ ] **Step 5: Refactor `ensureRowTextures` fallback-safe**

Replace `ensureRowTextures(row)` in `!KRT/Modules/UI/Visuals.lua` with:

```lua
local function ensureRowTextures(row)
    if not row or row._krtVisualsResolved then
        return
    end

    local rowName = row.GetName and row:GetName() or nil

    row._krtSelTex = row._krtSelTex or (rowName and _G[rowName .. "SelectedTexture"])
    row._krtFocusTex = row._krtFocusTex or (rowName and _G[rowName .. "FocusTexture"])

    local pushed = rowName and _G[rowName .. "PushedTexture"]
    if pushed and row.SetPushedTexture then
        row:SetPushedTexture(pushed)
    end

    if row._krtSelTex and row._krtSelTex.Hide then
        row._krtSelTex:Hide()
    end
    if row._krtFocusTex and row._krtFocusTex.Hide then
        row._krtFocusTex:Hide()
    end

    if not row._krtSelTex and row.CreateTexture then
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints(row)
        sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        sel:SetBlendMode("ADD")
        sel:SetVertexColor(0.20, 0.60, 1.00, 0.52)
        sel:Hide()
        row._krtSelTex = sel
    end

    if not row._krtFocusTex and row.CreateTexture then
        local focus = row:CreateTexture(nil, "ARTWORK")
        focus:SetAllPoints(row)
        focus:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        focus:SetBlendMode("ADD")
        focus:SetVertexColor(0.20, 0.60, 1.00, 0.72)
        focus:Hide()
        row._krtFocusTex = focus
    end

    if not pushed and row.CreateTexture and row.SetPushedTexture then
        pushed = row:CreateTexture(nil, "ARTWORK")
        pushed:SetAllPoints(row)
        pushed:SetTexture(1, 1, 1, 0.08)
        row:SetPushedTexture(pushed)
    end

    row._krtVisualsResolved = true
end
```

- [ ] **Step 6: Run focused tests and checks**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/logger_visual_refresh_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT/UI/Templates/Common.xml !KRT/Modules/UI/Visuals.lua
git commit -m "feat: move selectable row visuals into XML"
```

### Task 4: Logger Header, Row, Spec, And Inspect Visuals

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/UI/Logger.xml`
- Modify: `!KRT/Modules/UI/Visuals.lua`
- Modify: `!KRT/Controllers/Logger.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append:

```lua
assertContains(loggerXml, "$parentFill", "logger headers must expose fill texture")
assertContains(loggerXml, "$parentTop", "logger headers must expose top edge")
assertContains(loggerXml, "$parentBottom", "logger headers must expose bottom edge")
assertContains(loggerXml, "$parentLeft", "logger headers must expose left edge")
assertContains(loggerXml, "$parentRight", "logger headers must expose right edge")
assertContains(loggerXml, "$parentLoggerBg", "logger rows must expose background texture")
assertContains(loggerXml, "$parentLoggerBottomLine", "logger rows must expose bottom line texture")
assertContains(loggerXml, "$parentSpecIcon", "raid attendance rows must expose primary spec icon")
assertContains(loggerXml, "KRTLoggerInspectItemIconButtonTemplate", "logger must provide inspect icon button template")
assertContains(visuals, "LoggerBg", "logger row styling must resolve XML background")
assertContains(visuals, "LoggerBottomLine", "logger row styling must resolve XML bottom line")
assertContains(logger, "KRTLoggerInspectItemIconButtonTemplate", "logger inspect icons must use XML template")
assertContains(logger, "SpecIcon", "logger spec icons must resolve XML children")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL on missing logger XML textures.

- [ ] **Step 3: Add logger header textures**

In `KRTLoggerTableHeader`, keep `$parentBg` and add these textures inside the existing
`BACKGROUND` layer after `$parentBg`:

```xml
				<Texture name="$parentFill" file="Interface\Buttons\WHITE8x8">
					<Anchors>
						<Anchor point="TOPLEFT">
							<Offset><AbsDimension x="1" y="-1" /></Offset>
						</Anchor>
						<Anchor point="BOTTOMRIGHT">
							<Offset><AbsDimension x="-1" y="1" /></Offset>
						</Anchor>
					</Anchors>
				</Texture>
				<Texture name="$parentTop" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors>
						<Anchor point="TOPLEFT">
							<Offset><AbsDimension x="1" y="-1" /></Offset>
						</Anchor>
						<Anchor point="TOPRIGHT">
							<Offset><AbsDimension x="-1" y="-1" /></Offset>
						</Anchor>
					</Anchors>
				</Texture>
				<Texture name="$parentBottom" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors>
						<Anchor point="BOTTOMLEFT">
							<Offset><AbsDimension x="1" y="1" /></Offset>
						</Anchor>
						<Anchor point="BOTTOMRIGHT">
							<Offset><AbsDimension x="-1" y="1" /></Offset>
						</Anchor>
					</Anchors>
				</Texture>
				<Texture name="$parentLeft" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension x="1" /></Size>
					<Anchors>
						<Anchor point="TOPLEFT">
							<Offset><AbsDimension x="1" y="-1" /></Offset>
						</Anchor>
						<Anchor point="BOTTOMLEFT">
							<Offset><AbsDimension x="1" y="1" /></Offset>
						</Anchor>
					</Anchors>
				</Texture>
				<Texture name="$parentRight" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension x="1" /></Size>
					<Anchors>
						<Anchor point="TOPRIGHT">
							<Offset><AbsDimension x="-1" y="-1" /></Offset>
						</Anchor>
						<Anchor point="BOTTOMRIGHT">
							<Offset><AbsDimension x="-1" y="1" /></Offset>
						</Anchor>
					</Anchors>
				</Texture>
```

- [ ] **Step 4: Add logger row textures to each row template**

In each template named `KRTLoggerRaidButton`, `KRTLoggerBossButton`,
`KRTLoggerBossAttendeeButton`, `KRTLoggerRaidAttendeeButton`, and `KRTLoggerLootButton`, add:

```xml
				<Texture name="$parentLoggerBg" file="Interface\Buttons\WHITE8x8">
					<Anchors>
						<Anchor point="TOPLEFT" />
						<Anchor point="BOTTOMRIGHT" />
					</Anchors>
					<Color r="0.025" g="0.025" b="0.025" a="0.76" />
				</Texture>
				<Texture name="$parentLoggerBottomLine" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors>
						<Anchor point="BOTTOMLEFT">
							<Offset><AbsDimension x="2" y="0" /></Offset>
						</Anchor>
						<Anchor point="BOTTOMRIGHT">
							<Offset><AbsDimension x="-2" y="0" /></Offset>
						</Anchor>
					</Anchors>
					<Color r="0.32" g="0.30" b="0.25" a="0.42" />
				</Texture>
```

Place the new textures before the existing auction-frame background texture so Lua striping can
remain the visible base.

- [ ] **Step 5: Make logger row buttons inherit selectable row visuals**

Change each logger row template start tag from:

```xml
	<Button name="KRTLoggerRaidButton" virtual="true">
```

to this pattern, preserving the template name:

```xml
	<Button name="KRTLoggerRaidButton" inherits="KRTSelectableRowButtonTemplate" virtual="true">
```

Apply the same pattern to the other four logger row templates.

- [ ] **Step 6: Add attendance spec icon and inspect icon template**

Inside `KRTLoggerRaidAttendeeButton`, add this texture to the `ARTWORK` layer:

```xml
				<Texture name="$parentSpecIcon" hidden="true">
					<Size><AbsDimension x="17" y="17" /></Size>
					<Anchors>
						<Anchor point="TOPLEFT" relativeTo="$parentSpec" relativePoint="TOPLEFT">
							<Offset><AbsDimension x="1" y="-1" /></Offset>
						</Anchor>
					</Anchors>
					<TexCoords left="0.08" right="0.92" top="0.08" bottom="0.92" />
				</Texture>
```

Add this virtual template near the logger row templates:

```xml
	<Button name="KRTLoggerInspectItemIconButtonTemplate" virtual="true" enableMouse="true">
		<Size><AbsDimension x="18" y="18" /></Size>
		<Layers>
			<Layer level="ARTWORK">
				<Texture name="$parentTexture">
					<Anchors>
						<Anchor point="TOPLEFT" />
						<Anchor point="BOTTOMRIGHT" />
					</Anchors>
					<TexCoords left="0.08" right="0.92" top="0.08" bottom="0.92" />
				</Texture>
			</Layer>
		</Layers>
	</Button>
```

- [ ] **Step 7: Refactor logger header and row visual helpers**

In `!KRT/Modules/UI/Visuals.lua`, update `ensureLoggerHeaderTab(header)` to resolve named XML
children before fallback creation:

```lua
local function ensureLoggerHeaderTab(header)
    if not header or header._krtHeaderTab then
        return
    end

    local name = header.GetName and header:GetName() or nil
    if name then
        header._krtHeaderFill = _G[name .. "Fill"] or _G[name .. "Bg"]
        header._krtHeaderTop = _G[name .. "Top"]
        header._krtHeaderBottom = _G[name .. "Bottom"]
        header._krtHeaderLeft = _G[name .. "Left"]
        header._krtHeaderRight = _G[name .. "Right"]
    end

    if not header._krtHeaderFill and header.CreateTexture then
        local fill = header:CreateTexture(nil, "BACKGROUND")
        fill:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
        fill:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
        header._krtHeaderFill = fill
    end
    if not header._krtHeaderTop and header.CreateTexture then
        local top = header:CreateTexture(nil, "BORDER")
        top:SetHeight(1)
        top:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
        top:SetPoint("TOPRIGHT", header, "TOPRIGHT", -LOGGER_HEADER_TAB_INSET, -1)
        header._krtHeaderTop = top
    end
    if not header._krtHeaderBottom and header.CreateTexture then
        local bottom = header:CreateTexture(nil, "BORDER")
        bottom:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", LOGGER_HEADER_TAB_INSET, 1)
        bottom:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
        header._krtHeaderBottom = bottom
    end
    if not header._krtHeaderLeft and header.CreateTexture then
        local left = header:CreateTexture(nil, "BORDER")
        left:SetWidth(1)
        left:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
        left:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", LOGGER_HEADER_TAB_INSET, 1)
        header._krtHeaderLeft = left
    end
    if not header._krtHeaderRight and header.CreateTexture then
        local right = header:CreateTexture(nil, "BORDER")
        right:SetWidth(1)
        right:SetPoint("TOPRIGHT", header, "TOPRIGHT", -LOGGER_HEADER_TAB_INSET, -1)
        right:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
        header._krtHeaderRight = right
    end

    header._krtHeaderTab = true
end
```

Update `Rows.StyleLoggerRow(row)` so it resolves `LoggerBg` and `LoggerBottomLine` before
fallback creation.

- [ ] **Step 8: Refactor logger spec and inspect icon creation**

In `!KRT/Controllers/Logger.lua`, change `ensureAttendanceSpecIcon(row)` to first resolve:

```lua
local rowName = row.GetName and row:GetName() or nil
local icon = rowName and _G[rowName .. "SpecIcon"] or nil
```

If the XML texture exists, cache it as `row._krtAttendanceSpecIcon`, assign `icon.texture = icon`,
bind the existing tooltip behavior, and keep the current `CreateFrame("Button", nil, row)` fallback
for unnamed or old rows.

Change `ensureAttendanceInspectIcon(row, index, ui)` so named icons use:

```lua
local rowName = row.GetName and row:GetName() or nil
local iconName = rowName and (rowName .. "InspectIcon" .. tostring(index)) or nil
icon = iconName and _G[iconName] or nil
if not icon and iconName then
    icon = CreateFrame("Button", iconName, row, "KRTLoggerInspectItemIconButtonTemplate")
end
```

Then set:

```lua
icon.texture = icon.texture or (iconName and _G[iconName .. "Texture"])
```

Keep the tooltip scripts in Lua.

- [ ] **Step 9: Run focused tests and checks**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/logger_visual_refresh_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected: all PASS.

- [ ] **Step 10: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT/UI/Logger.xml !KRT/Modules/UI/Visuals.lua !KRT/Controllers/Logger.lua
git commit -m "feat: move logger fixed visuals into XML"
```

### Task 5: ScreenNotice XML Frame

**Files:**

- Create: `!KRT/UI/ScreenNotice.xml`
- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/KRT.xml`
- Modify: `!KRT/Modules/UI/ScreenNotice.lua`
- Modify: `tests/screen_notice_runtime_spec.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append:

```lua
assertContains(krtXml, "<Include file=\"UI\\ScreenNotice.xml\" />", "KRT.xml must include ScreenNotice XML")
assertContains(screenNotice, "_G[FRAME_NAME]", "ScreenNotice must resolve XML frame by name")
assertContains(screenNotice, "FRAME_NAME .. \"TitleText\"", "ScreenNotice must resolve XML title text")
assertContains(screenNotice, "FRAME_NAME .. \"DetailText\"", "ScreenNotice must resolve XML detail text")
assertContains(screenNotice, "CreateFrame(\"Frame\", FRAME_NAME, UIParent)", "ScreenNotice must keep fallback creation")
```

- [ ] **Step 2: Update the runtime spec to exercise XML resolution**

In `tests/screen_notice_runtime_spec.lua`, pre-register named XML-like parts before loading
`ScreenNotice.lua`:

```lua
frames.KRTScreenNoticeFrame = makeFrame("KRTScreenNoticeFrame")
_G.KRTScreenNoticeFrame = frames.KRTScreenNoticeFrame
_G.KRTScreenNoticeFrameTitleText = makeFrame("KRTScreenNoticeFrameTitleText")
_G.KRTScreenNoticeFrameDetailText = makeFrame("KRTScreenNoticeFrameDetailText")
```

Change the assertion for fontstrings to assert the named title text:

```lua
assert(_G.KRTScreenNoticeFrameTitleText._text == "Boss targeted, auto switch to |cffff2020Master Loot|r.", "screen notice text must be applied")
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/screen_notice_runtime_spec.lua
```

Expected: source test FAIL on missing XML include; runtime spec FAIL until Lua resolves named parts.

- [ ] **Step 4: Create `!KRT/UI/ScreenNotice.xml`**

Use this file:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
	xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">
	<Frame name="KRTScreenNoticeFrame" parent="UIParent" frameStrata="TOOLTIP" hidden="true">
		<Size><AbsDimension x="1" y="1" /></Size>
		<Anchors>
			<Anchor point="CENTER" relativeTo="UIParent" relativePoint="CENTER">
				<Offset><AbsDimension x="0" y="140" /></Offset>
			</Anchor>
		</Anchors>
		<Layers>
			<Layer level="OVERLAY">
				<FontString name="$parentTitleText" justifyH="CENTER" justifyV="MIDDLE">
					<Anchors>
						<Anchor point="CENTER"><Offset><AbsDimension x="0" y="0" /></Offset></Anchor>
					</Anchors>
					<Font font="Fonts\FRIZQT__.TTF" height="24" flags="OUTLINE" />
					<Color r="1" g="1" b="1" a="1" />
					<Shadow>
						<Color r="0" g="0" b="0" a="1" />
						<Offset><AbsDimension x="2" y="-2" /></Offset>
					</Shadow>
				</FontString>
				<FontString name="$parentDetailText" justifyH="CENTER" justifyV="MIDDLE" hidden="true">
					<Anchors>
						<Anchor point="CENTER"><Offset><AbsDimension x="0" y="-22" /></Offset></Anchor>
					</Anchors>
					<Font font="Fonts\FRIZQT__.TTF" height="16" flags="OUTLINE" />
					<Color r="0.78" g="0.78" b="0.78" a="1" />
					<Shadow>
						<Color r="0" g="0" b="0" a="1" />
						<Offset><AbsDimension x="1" y="-1" /></Offset>
					</Shadow>
				</FontString>
			</Layer>
		</Layers>
	</Frame>
</Ui>
```

- [ ] **Step 5: Include ScreenNotice XML**

In `!KRT/KRT.xml`, add near the top of the include manifest:

```xml
    <Include file="UI\ScreenNotice.xml" />
```

- [ ] **Step 6: Refactor `ensureFrame()`**

In `!KRT/Modules/UI/ScreenNotice.lua`, make `ensureFrame()` resolve XML first:

```lua
frame = _G[FRAME_NAME]
if frame then
    titleText = _G[FRAME_NAME .. "TitleText"]
    detailText = _G[FRAME_NAME .. "DetailText"]
    if frame.SetFrameLevel then
        frame:SetFrameLevel(1000)
    end
    return frame
end
```

Keep the current `CreateFrame("Frame", FRAME_NAME, UIParent)` block as the fallback path.

- [ ] **Step 7: Run focused tests and checks**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/screen_notice_runtime_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```powershell
git add -- !KRT/UI/ScreenNotice.xml !KRT/KRT.xml !KRT/Modules/UI/ScreenNotice.lua tests/ui_xml_homogenization_source_spec.lua tests/screen_notice_runtime_spec.lua
git commit -m "feat: move screen notice frame into XML"
```

### Task 6: RaidGrid XML Frame And Button Template

**Files:**

- Create: `!KRT/UI/RaidGrid.xml`
- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `tests/raid_grid_spec_icon_spec.lua`
- Modify: `!KRT/UI/Templates/Common.xml`
- Modify: `!KRT/KRT.xml`
- Modify: `!KRT/Widgets/RaidGrid.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append:

```lua
assertContains(commonXml, "KRTRaidGridButtonTemplate", "Common XML must define raid grid button template")
assertContains(krtXml, "<Include file=\"UI\\RaidGrid.xml\" />", "KRT.xml must include RaidGrid XML")
assertContains(raidGrid, "KRTRaidGridButtonTemplate", "RaidGrid buttons must use XML template")
assertContains(raidGrid, "KRTRaidGridFrameIcon", "RaidGrid must resolve XML icon")
assertContains(raidGrid, "KRTRaidGridFrameCloseButton", "RaidGrid must resolve XML close button")
assertContains(raidGrid, "createButtonFallback", "RaidGrid must keep fallback creation while migrating")
```

- [ ] **Step 2: Update the runtime spec for templated button creation**

In `tests/raid_grid_spec_icon_spec.lua`, update fake `CreateFrame` to accept and store the template:

```lua
function fakeG.CreateFrame(_, name, parent, template)
    local frame = makeFrame(name)
    frame.parent = parent
    frame.template = template
    if name then
        frames[name] = frame
        fakeG[name] = frame
        fakeG[name .. "Bg"] = makeFrame(name .. "Bg")
        fakeG[name .. "TopLine"] = makeFrame(name .. "TopLine")
        fakeG[name .. "BottomLine"] = makeFrame(name .. "BottomLine")
        fakeG[name .. "Highlight"] = makeFrame(name .. "Highlight")
        fakeG[name .. "Text"] = makeFrame(name .. "Text")
        fakeG[name .. "SpecIcon"] = makeFrame(name .. "SpecIcon")
    end
    return frame
end
```

Add after `button` is acquired:

```lua
assertEquals(button.template, "KRTRaidGridButtonTemplate", "RaidGrid dynamic buttons must use XML template")
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/raid_grid_spec_icon_spec.lua
```

Expected: FAIL on missing `KRTRaidGridButtonTemplate`.

- [ ] **Step 4: Add `KRTRaidGridButtonTemplate` to Common.xml**

Insert after `KRTSelectableRowButtonTemplate`:

```xml
	<Button name="KRTRaidGridButtonTemplate" virtual="true">
		<Size><AbsDimension x="150" y="28" /></Size>
		<Layers>
			<Layer level="BACKGROUND">
				<Texture name="$parentBg" file="Interface\Buttons\WHITE8x8">
					<Anchors><Anchor point="TOPLEFT" /><Anchor point="BOTTOMRIGHT" /></Anchors>
				</Texture>
			</Layer>
			<Layer level="BORDER">
				<Texture name="$parentTopLine" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors><Anchor point="TOPLEFT" /><Anchor point="TOPRIGHT" /></Anchors>
					<Color r="1" g="1" b="1" a="0.08" />
				</Texture>
				<Texture name="$parentBottomLine" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors><Anchor point="BOTTOMLEFT" /><Anchor point="BOTTOMRIGHT" /></Anchors>
					<Color r="0" g="0" b="0" a="0.90" />
				</Texture>
			</Layer>
			<Layer level="ARTWORK">
				<Texture name="$parentSpecIcon" hidden="true">
					<Size><AbsDimension x="16" y="16" /></Size>
					<Anchors>
						<Anchor point="LEFT"><Offset><AbsDimension x="12" y="0" /></Offset></Anchor>
					</Anchors>
					<TexCoords left="0.08" right="0.92" top="0.08" bottom="0.92" />
				</Texture>
				<FontString name="$parentText" inherits="GameFontNormalLarge" justifyH="CENTER">
					<Anchors>
						<Anchor point="LEFT"><Offset><AbsDimension x="4" y="0" /></Offset></Anchor>
						<Anchor point="RIGHT"><Offset><AbsDimension x="-4" y="0" /></Offset></Anchor>
					</Anchors>
				</FontString>
			</Layer>
			<Layer level="HIGHLIGHT">
				<Texture name="$parentHighlight"
					file="Interface\QuestFrame\UI-QuestTitleHighlight"
					alphaMode="ADD">
					<Anchors><Anchor point="TOPLEFT" /><Anchor point="BOTTOMRIGHT" /></Anchors>
				</Texture>
			</Layer>
		</Layers>
	</Button>
```

- [ ] **Step 5: Create `!KRT/UI/RaidGrid.xml`**

Use this file:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
	xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">
	<Frame name="KRTRaidGridFrame"
		inherits="KRTDialogTemplate"
		parent="UIParent"
		frameStrata="FULLSCREEN_DIALOG"
		toplevel="true"
		hidden="true"
		clampedToScreen="true"
		movable="true"
		enableMouse="true"
		registerForDrag="LeftButton">
		<Size><AbsDimension x="250" y="160" /></Size>
		<Anchors><Anchor point="CENTER" /></Anchors>
		<Layers>
			<Layer level="ARTWORK">
				<Texture name="$parentIcon">
					<Size><AbsDimension x="30" y="30" /></Size>
					<Anchors>
						<Anchor point="TOPLEFT">
							<Offset><AbsDimension x="22" y="-18" /></Offset>
						</Anchor>
					</Anchors>
				</Texture>
				<FontString name="$parentTitle" inherits="GameFontNormalLarge" justifyH="LEFT">
					<Anchors>
						<Anchor point="LEFT" relativeTo="$parentIcon" relativePoint="RIGHT">
							<Offset><AbsDimension x="8" y="0" /></Offset>
						</Anchor>
					</Anchors>
				</FontString>
				<FontString name="$parentCount" inherits="GameFontNormal" hidden="true">
					<Anchors>
						<Anchor point="LEFT" relativeTo="$parentTitle" relativePoint="RIGHT">
							<Offset><AbsDimension x="8" y="0" /></Offset>
						</Anchor>
					</Anchors>
					<Color r="1" g="1" b="1" a="1" />
				</FontString>
				<Texture name="$parentDivider" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors>
						<Anchor point="TOPLEFT"><Offset><AbsDimension x="22" y="-56" /></Offset></Anchor>
						<Anchor point="TOPRIGHT"><Offset><AbsDimension x="-22" y="-56" /></Offset></Anchor>
					</Anchors>
					<Color r="1" g="0.82" b="0" a="0.35" />
				</Texture>
				<FontString name="$parentEmpty" inherits="GameFontHighlight" justifyH="LEFT">
					<Anchors>
						<Anchor point="TOPLEFT"><Offset><AbsDimension x="24" y="-62" /></Offset></Anchor>
					</Anchors>
					<Color r="1" g="0.2" b="0.2" a="1" />
				</FontString>
			</Layer>
		</Layers>
		<Frames>
			<Button name="$parentCloseButton" inherits="UIPanelCloseButton">
				<Anchors>
					<Anchor point="TOPRIGHT">
						<Offset><AbsDimension x="-5" y="-5" /></Offset>
					</Anchor>
				</Anchors>
			</Button>
		</Frames>
	</Frame>
</Ui>
```

- [ ] **Step 6: Include RaidGrid XML**

In `!KRT/KRT.xml`, add:

```xml
    <Include file="UI\RaidGrid.xml" />
```

- [ ] **Step 7: Refactor `Widgets/RaidGrid.lua`**

Add a `createButtonFallback(index)` containing the old Lua visual construction.

Change `createButton(index)` to:

```lua
local buttonName = "KRTRaidGridButton" .. tostring(index)
local button = _G[buttonName]
if not button and _G.CreateFrame then
    button = _G.CreateFrame("Button", buttonName, frame, "KRTRaidGridButtonTemplate")
end
if not button then
    return createButtonFallback(index)
end

setSize(button, CFG.buttonWidth, CFG.buttonHeight)
button.bg = _G[buttonName .. "Bg"] or button.bg
button.topLine = _G[buttonName .. "TopLine"] or button.topLine
button.bottomLine = _G[buttonName .. "BottomLine"] or button.bottomLine
button.highlight = _G[buttonName .. "Highlight"] or button.highlight
button.text = _G[buttonName .. "Text"] or button.text
button.specIcon = _G[buttonName .. "SpecIcon"] or button.specIcon
```

Update `ensureFrame()` to first resolve `_G.KRTRaidGridFrame` and its named children:

```lua
frame = _G.KRTRaidGridFrame or _G.CreateFrame("Frame", "KRTRaidGridFrame", _G.UIParent, "KRTDialogTemplate")
frame.icon = _G.KRTRaidGridFrameIcon or frame.icon
frame.title = _G.KRTRaidGridFrameTitle or frame.title
frame.count = _G.KRTRaidGridFrameCount or frame.count
frame.divider = _G.KRTRaidGridFrameDivider or frame.divider
frame.empty = _G.KRTRaidGridFrameEmpty or frame.empty
frame.close = _G.KRTRaidGridFrameCloseButton or frame.close
```

Bind close and drag scripts in Lua as they are behavior.

- [ ] **Step 8: Run focused tests and checks**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/raid_grid_spec_icon_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected: all PASS.

- [ ] **Step 9: Commit**

```powershell
git add -- !KRT/UI/RaidGrid.xml !KRT/UI/Templates/Common.xml !KRT/KRT.xml !KRT/Widgets/RaidGrid.lua tests/ui_xml_homogenization_source_spec.lua tests/raid_grid_spec_icon_spec.lua
git commit -m "feat: move raid grid skeleton into XML"
```

### Task 7: LootCounter XML Header, Sections, And Rows

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/UI/LootCounter.xml`
- Modify: `!KRT/Widgets/LootCounter.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append:

```lua
assertContains(lootCounterXml, "KRTLootCounterHeaderTemplate", "LootCounter XML must define header template")
assertContains(lootCounterXml, "KRTLootCounterSectionTemplate", "LootCounter XML must define section template")
assertContains(lootCounterXml, "KRTLootCounterRowTemplate", "LootCounter XML must define row template")
assertContains(lootCounterXml, "$parentHeader", "LootCounter scroll child must define header")
assertContains(lootCounter, "ensureHeaderFallback", "LootCounter must keep header fallback during migration")
assertContains(lootCounter, "ensureRowFallback", "LootCounter must keep row fallback during migration")
assertContains(lootCounter, "KRTLootCounterRow", "LootCounter rows must be named XML-template rows")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL on missing `KRTLootCounterHeaderTemplate`.

- [ ] **Step 3: Add LootCounter XML templates**

In `!KRT/UI/LootCounter.xml`, before `KRTLootCounterFrame`, add:

```xml
    <Frame name="KRTLootCounterHeaderTemplate" virtual="true">
        <Size><AbsDimension y="20" /></Size>
        <Layers>
            <Layer level="BORDER">
                <Texture name="$parentSeparator" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension y="1" /></Size>
                    <Anchors><Anchor point="BOTTOMLEFT" /><Anchor point="BOTTOMRIGHT" /></Anchors>
                    <Color r="1" g="1" b="1" a="0.06" />
                </Texture>
            </Layer>
            <Layer level="ARTWORK">
                <FontString name="$parentResetPlaceholder" inherits="GameFontNormalSmall" justifyH="CENTER">
                    <Size><AbsDimension x="18" /></Size>
                    <Anchors>
                        <Anchor point="RIGHT"><Offset><AbsDimension x="-2" y="0" /></Offset></Anchor>
                    </Anchors>
                </FontString>
                <FontString name="$parentFreeLabel" inherits="GameFontNormalSmall" justifyH="CENTER">
                    <Size><AbsDimension x="62" /></Size>
                    <Anchors>
                        <Anchor point="RIGHT" relativeTo="$parentResetPlaceholder" relativePoint="LEFT">
                            <Offset><AbsDimension x="-16" y="0" /></Offset>
                        </Anchor>
                    </Anchors>
                </FontString>
                <FontString name="$parentOSLabel" inherits="GameFontNormalSmall" justifyH="CENTER">
                    <Size><AbsDimension x="62" /></Size>
                    <Anchors>
                        <Anchor point="RIGHT" relativeTo="$parentFreeLabel" relativePoint="LEFT">
                            <Offset><AbsDimension x="-8" y="0" /></Offset>
                        </Anchor>
                    </Anchors>
                </FontString>
                <FontString name="$parentMSLabel" inherits="GameFontNormalSmall" justifyH="CENTER">
                    <Size><AbsDimension x="62" /></Size>
                    <Anchors>
                        <Anchor point="RIGHT" relativeTo="$parentOSLabel" relativePoint="LEFT">
                            <Offset><AbsDimension x="-8" y="0" /></Offset>
                        </Anchor>
                    </Anchors>
                </FontString>
                <FontString name="$parentName" inherits="GameFontNormalSmall" justifyH="LEFT">
                    <Anchors>
                        <Anchor point="LEFT" />
                        <Anchor point="RIGHT" relativeTo="$parentMSLabel" relativePoint="LEFT">
                            <Offset><AbsDimension x="-6" y="0" /></Offset>
                        </Anchor>
                    </Anchors>
                </FontString>
                <Texture name="$parentSepOS" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension x="1" /></Size>
                    <Anchors>
                        <Anchor point="TOP" relativeTo="$parentOSLabel" relativePoint="TOPLEFT">
                            <Offset><AbsDimension x="-4" y="-3" /></Offset>
                        </Anchor>
                        <Anchor point="BOTTOM" relativeTo="$parentOSLabel" relativePoint="BOTTOMLEFT">
                            <Offset><AbsDimension x="-4" y="3" /></Offset>
                        </Anchor>
                    </Anchors>
                </Texture>
                <Texture name="$parentSepFree" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension x="1" /></Size>
                    <Anchors>
                        <Anchor point="TOP" relativeTo="$parentFreeLabel" relativePoint="TOPLEFT">
                            <Offset><AbsDimension x="-4" y="-3" /></Offset>
                        </Anchor>
                        <Anchor point="BOTTOM" relativeTo="$parentFreeLabel" relativePoint="BOTTOMLEFT">
                            <Offset><AbsDimension x="-4" y="3" /></Offset>
                        </Anchor>
                    </Anchors>
                </Texture>
                <Texture name="$parentSepReset" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension x="1" /></Size>
                    <Anchors>
                        <Anchor point="TOP" relativeTo="$parentResetPlaceholder" relativePoint="TOPLEFT">
                            <Offset><AbsDimension x="-8" y="-3" /></Offset>
                        </Anchor>
                        <Anchor point="BOTTOM" relativeTo="$parentResetPlaceholder" relativePoint="BOTTOMLEFT">
                            <Offset><AbsDimension x="-8" y="3" /></Offset>
                        </Anchor>
                    </Anchors>
                </Texture>
            </Layer>
        </Layers>
    </Frame>
```

Also add `KRTLootCounterSectionTemplate` and `KRTLootCounterRowTemplate` with named parts:

```xml
    <Frame name="KRTLootCounterSectionTemplate" virtual="true">
        <Size><AbsDimension x="62" y="25" /></Size>
        <Frames>
            <Button name="$parentPlus" inherits="KRTActionButtonTemplate">
                <Size><AbsDimension x="18" y="18" /></Size>
                <Anchors><Anchor point="RIGHT" /></Anchors>
            </Button>
            <Button name="$parentMinus" inherits="KRTActionButtonTemplate">
                <Size><AbsDimension x="18" y="18" /></Size>
                <Anchors>
                    <Anchor point="RIGHT" relativeTo="$parentPlus" relativePoint="LEFT">
                        <Offset><AbsDimension x="-2" y="0" /></Offset>
                    </Anchor>
                </Anchors>
            </Button>
        </Frames>
        <Layers>
            <Layer level="ARTWORK">
                <FontString name="$parentCount" inherits="GameFontNormalSmall" justifyH="CENTER">
                    <Size><AbsDimension x="22" /></Size>
                    <Anchors>
                        <Anchor point="RIGHT" relativeTo="$parentMinus" relativePoint="LEFT">
                            <Offset><AbsDimension x="-2" y="0" /></Offset>
                        </Anchor>
                    </Anchors>
                </FontString>
            </Layer>
        </Layers>
    </Frame>

    <Frame name="KRTLootCounterRowTemplate" virtual="true">
        <Size><AbsDimension y="25" /></Size>
        <Layers>
            <Layer level="BACKGROUND">
                <Texture name="$parentBackground" file="Interface\Buttons\WHITE8x8">
                    <Anchors><Anchor point="TOPLEFT" /><Anchor point="BOTTOMRIGHT" /></Anchors>
                    <Color r="1" g="1" b="1" a="0.06" />
                </Texture>
            </Layer>
            <Layer level="BORDER">
                <Texture name="$parentSeparator" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension y="1" /></Size>
                    <Anchors><Anchor point="BOTTOMLEFT" /><Anchor point="BOTTOMRIGHT" /></Anchors>
                    <Color r="1" g="1" b="1" a="0.06" />
                </Texture>
            </Layer>
            <Layer level="ARTWORK">
                <Texture name="$parentSpecIcon" hidden="true">
                    <Size><AbsDimension x="14" y="14" /></Size>
                    <Anchors><Anchor point="LEFT" /></Anchors>
                    <TexCoords left="0.08" right="0.92" top="0.08" bottom="0.92" />
                </Texture>
                <FontString name="$parentName" inherits="GameFontNormalSmall" justifyH="LEFT">
                    <Anchors>
                        <Anchor point="LEFT" relativeTo="$parentSpecIcon" relativePoint="RIGHT">
                            <Offset><AbsDimension x="4" y="0" /></Offset>
                        </Anchor>
                        <Anchor point="RIGHT" relativeTo="$parentMSSection" relativePoint="LEFT">
                            <Offset><AbsDimension x="-6" y="0" /></Offset>
                        </Anchor>
                    </Anchors>
                </FontString>
                <Texture name="$parentSepOS" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension x="1" /></Size>
                    <Anchors>
                        <Anchor point="TOP" relativeTo="$parentOSSection" relativePoint="TOPLEFT">
                            <Offset><AbsDimension x="-4" y="-2" /></Offset>
                        </Anchor>
                        <Anchor point="BOTTOM" relativeTo="$parentOSSection" relativePoint="BOTTOMLEFT">
                            <Offset><AbsDimension x="-4" y="2" /></Offset>
                        </Anchor>
                    </Anchors>
                </Texture>
                <Texture name="$parentSepFree" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension x="1" /></Size>
                    <Anchors>
                        <Anchor point="TOP" relativeTo="$parentFreeSection" relativePoint="TOPLEFT">
                            <Offset><AbsDimension x="-4" y="-2" /></Offset>
                        </Anchor>
                        <Anchor point="BOTTOM" relativeTo="$parentFreeSection" relativePoint="BOTTOMLEFT">
                            <Offset><AbsDimension x="-4" y="2" /></Offset>
                        </Anchor>
                    </Anchors>
                </Texture>
                <Texture name="$parentSepReset" file="Interface\Buttons\WHITE8x8">
                    <Size><AbsDimension x="1" /></Size>
                    <Anchors>
                        <Anchor point="TOP" relativeTo="$parentReset" relativePoint="TOPLEFT">
                            <Offset><AbsDimension x="-8" y="-2" /></Offset>
                        </Anchor>
                        <Anchor point="BOTTOM" relativeTo="$parentReset" relativePoint="BOTTOMLEFT">
                            <Offset><AbsDimension x="-8" y="2" /></Offset>
                        </Anchor>
                    </Anchors>
                </Texture>
            </Layer>
        </Layers>
        <Frames>
            <Button name="$parentReset" inherits="KRTActionButtonTemplate">
                <Size><AbsDimension x="18" y="18" /></Size>
                <Anchors>
                    <Anchor point="RIGHT"><Offset><AbsDimension x="-2" y="0" /></Offset></Anchor>
                </Anchors>
            </Button>
            <Frame name="$parentFreeSection" inherits="KRTLootCounterSectionTemplate">
                <Anchors>
                    <Anchor point="RIGHT" relativeTo="$parentReset" relativePoint="LEFT">
                        <Offset><AbsDimension x="-16" y="0" /></Offset>
                    </Anchor>
                </Anchors>
            </Frame>
            <Frame name="$parentOSSection" inherits="KRTLootCounterSectionTemplate">
                <Anchors>
                    <Anchor point="RIGHT" relativeTo="$parentFreeSection" relativePoint="LEFT">
                        <Offset><AbsDimension x="-8" y="0" /></Offset>
                    </Anchor>
                </Anchors>
            </Frame>
            <Frame name="$parentMSSection" inherits="KRTLootCounterSectionTemplate">
                <Anchors>
                    <Anchor point="RIGHT" relativeTo="$parentOSSection" relativePoint="LEFT">
                        <Offset><AbsDimension x="-8" y="0" /></Offset>
                    </Anchor>
                </Anchors>
            </Frame>
        </Frames>
    </Frame>
```

- [ ] **Step 4: Define explicit scroll child and XML header**

Replace the current `KRTLootCounterFrame` scroll frame body with an explicit scroll child:

```xml
            <ScrollFrame name="$parentScrollFrame" inherits="KRTListScrollFrameTemplate">
                <Anchors>
					<Anchor point="TOPLEFT"><Offset><AbsDimension x="15" y="-32" /></Offset></Anchor>
					<Anchor point="BOTTOMRIGHT"><Offset><AbsDimension x="-30" y="44" /></Offset></Anchor>
                </Anchors>
                <ScrollChild>
                    <Frame name="$parentScrollChild">
                        <Size><AbsDimension x="1" y="1" /></Size>
                        <Frames>
                            <Frame name="$parentHeader" inherits="KRTLootCounterHeaderTemplate">
                                <Anchors>
                                    <Anchor point="TOPLEFT" />
                                    <Anchor point="TOPRIGHT" />
                                </Anchors>
                            </Frame>
                        </Frames>
                    </Frame>
                </ScrollChild>
            </ScrollFrame>
```

- [ ] **Step 5: Refactor LootCounter Lua with fallback helpers**

Rename the old `ensureHeader()` body to `ensureHeaderFallback()`.
Rename the old row-construction body inside `ensureRow(i, rowHeight)` to `ensureRowFallback(i, rowHeight)`.

Implement XML-first `ensureHeader()`:

```lua
local function ensureHeader()
    if header or not scrollChild then
        return
    end

    local childName = scrollChild.GetName and scrollChild:GetName() or nil
    header = childName and _G[childName .. "Header"] or nil
    if not header then
        return ensureHeaderFallback()
    end

    header.separator = _G[childName .. "HeaderSeparator"]
    header.resetPlaceholder = _G[childName .. "HeaderResetPlaceholder"]
    header.freeLabel = _G[childName .. "HeaderFreeLabel"]
    header.osLabel = _G[childName .. "HeaderOSLabel"]
    header.msLabel = _G[childName .. "HeaderMSLabel"]
    header.name = _G[childName .. "HeaderName"]

    header.resetPlaceholder:SetText("R")
    header.freeLabel:SetText(L.StrFREE)
    header.osLabel:SetText(L.StrOS)
    header.msLabel:SetText(L.StrMS)
    header.name:SetText(L.StrPlayer)

    setFontColor(header.resetPlaceholder, COLOR_HEADER_TEXT)
    setFontColor(header.freeLabel, COLOR_COUNT_FREE)
    setFontColor(header.osLabel, COLOR_COUNT_OS)
    setFontColor(header.msLabel, COLOR_COUNT_MS)
    setFontColor(header.name, COLOR_HEADER_TEXT)
end
```

Implement XML-first row creation with named rows:

```lua
local rowName = "KRTLootCounterFrameRow" .. tostring(i)
row = _G[rowName] or CreateFrame("Frame", rowName, scrollChild, "KRTLootCounterRowTemplate")
row:SetHeight(rowHeight)
row.background = _G[rowName .. "Background"]
row.separator = _G[rowName .. "Separator"]
row.reset = _G[rowName .. "Reset"]
row.freeSection = _G[rowName .. "FreeSection"]
row.osSection = _G[rowName .. "OSSection"]
row.msSection = _G[rowName .. "MSSection"]
row.specIcon = _G[rowName .. "SpecIcon"]
row.name = _G[rowName .. "Name"]
row.freeSection.plus = _G[rowName .. "FreeSectionPlus"]
row.freeSection.minus = _G[rowName .. "FreeSectionMinus"]
row.freeSection.count = _G[rowName .. "FreeSectionCount"]
row.osSection.plus = _G[rowName .. "OSSectionPlus"]
row.osSection.minus = _G[rowName .. "OSSectionMinus"]
row.osSection.count = _G[rowName .. "OSSectionCount"]
row.msSection.plus = _G[rowName .. "MSSectionPlus"]
row.msSection.minus = _G[rowName .. "MSSectionMinus"]
row.msSection.count = _G[rowName .. "MSSectionCount"]
```

Keep all button text, tooltips, click handlers, count refresh, row positioning, scroll sizing,
alternating row colors, class colors, and spec icon state in Lua.

- [ ] **Step 6: Run focused tests and checks**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT/UI/LootCounter.xml !KRT/Widgets/LootCounter.lua
git commit -m "feat: move loot counter skeleton into XML"
```

### Task 8: Reserves Separators And Master Selection Template

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `!KRT/UI/ReservesTemplates.xml`
- Modify: `!KRT/Widgets/ReservesUI.lua`
- Modify: `!KRT/Controllers/Master.lua`

- [ ] **Step 1: Extend the failing source-contract test**

Append:

```lua
assertContains(reservesXml, "$parentTopSeparator", "reserve rows must expose top separator")
assertContains(reservesXml, "$parentBottomSeparator", "reserve rows must expose bottom separator")
assertContains(reservesUi, "TopSeparator", "ReservesUI must resolve XML top separator")
assertContains(reservesUi, "BottomSeparator", "ReservesUI must resolve XML bottom separator")
assertContains(master, "KRTItemSelectionFrame", "Master must instantiate the dedicated item selection template")
assertNotContains(master, "CreateFrame(\"Frame\", nil, frame, \"KRTDialogTemplate\")", "Master must stop bypassing KRTItemSelectionFrame")
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL on missing reserve separators or Master template use.

- [ ] **Step 3: Add reserve row separators to XML**

In `KRTReserveRowTemplate`, add these textures in a `BACKGROUND` or `BORDER` layer:

```xml
				<Texture name="$parentTopSeparator" file="Interface\Buttons\WHITE8x8" hidden="true">
					<Size><AbsDimension y="1" /></Size>
					<Anchors>
						<Anchor point="TOPLEFT" />
						<Anchor point="TOPRIGHT"><Offset><AbsDimension x="-4" y="0" /></Offset></Anchor>
					</Anchors>
					<Color r="1" g="1" b="1" a="0.10" />
				</Texture>
				<Texture name="$parentBottomSeparator" file="Interface\Buttons\WHITE8x8">
					<Size><AbsDimension y="1" /></Size>
					<Anchors>
						<Anchor point="BOTTOMLEFT" />
						<Anchor point="BOTTOMRIGHT"><Offset><AbsDimension x="-4" y="0" /></Offset></Anchor>
					</Anchors>
					<Color r="1" g="1" b="1" a="0.08" />
				</Texture>
```

- [ ] **Step 4: Refactor reserve row decor**

Replace `setupReserveRowDecor(row)` with XML-first resolution:

```lua
local function setupReserveRowDecor(row)
    if not row or row._decorInitialized then
        return
    end

    local rowName = row.GetName and row:GetName() or nil
    row.topSeparator = rowName and _G[rowName .. "TopSeparator"] or nil
    row.separator = rowName and _G[rowName .. "BottomSeparator"] or nil

    if row.topSeparator and row.topSeparator.Hide then
        row.topSeparator:Hide()
    end

    if not row.topSeparator and row.CreateTexture then
        local topSeparator = row:CreateTexture(nil, "BORDER")
        topSeparator:SetTexture("Interface\\Buttons\\WHITE8x8")
        topSeparator:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        topSeparator:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, 0)
        topSeparator:SetHeight(1)
        topSeparator:Hide()
        row.topSeparator = topSeparator
    end

    if not row.separator and row.CreateTexture then
        local separator = row:CreateTexture(nil, "BORDER")
        separator:SetTexture("Interface\\Buttons\\WHITE8x8")
        separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
        separator:SetHeight(1)
        row.separator = separator
    end

    row._decorInitialized = true
end
```

- [ ] **Step 5: Use the Master item selection XML template**

In `!KRT/Controllers/Master.lua`, replace:

```lua
module._selectionFrame = CreateFrame("Frame", nil, frame, "KRTDialogTemplate")
```

with:

```lua
local frameName = getFrameName()
local selectionName = frameName and (frameName .. "ItemSelectionFrame") or nil
module._selectionFrame = CreateFrame("Frame", selectionName, frame, "KRTItemSelectionFrame")
```

Keep `module._selectionFrame:Hide()` and all button creation/update logic unchanged.

- [ ] **Step 6: Run focused tests and checks**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check raid_hardening
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT/UI/ReservesTemplates.xml !KRT/Widgets/ReservesUI.lua !KRT/Controllers/Master.lua
git commit -m "feat: use XML templates for reserves and master selection"
```

### Task 9: Cleanup Audit And Fallback Removal Gate

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify only files whose fallback paths are verified in-game as dead.

- [ ] **Step 1: Search remaining Lua visual creation**

Run:

```powershell
rg -n "CreateTexture\\(|CreateFontString\\(|SetBackdrop\\(|SetNormalTexture\\(|SetHighlightTexture\\(|SetPushedTexture\\(" !KRT/Modules !KRT/Widgets !KRT/Controllers !KRT/EntryPoints
```

Expected remaining allowed areas:

```text
!KRT/Modules/UI/Effects.lua
fallback paths added by this plan
dynamic list row creation
tooltip and hitbox code
dropdown and menu code
runtime state styling
```

- [ ] **Step 2: Classify remaining hits in the final review notes**

For each hit, record one of:

```text
allowed dynamic
compatibility fallback
still needs XML migration
```

Do not remove fallback paths unless an in-game smoke pass has verified the XML path.

- [ ] **Step 3: Add source-contract assertions for intentional fallbacks**

Append assertions that preserve intentional dynamic areas:

```lua
assertContains(screenNotice, "CreateFrame(\"Frame\", FRAME_NAME, UIParent)", "ScreenNotice fallback must remain until in-game XML validation")
assertContains(raidGrid, "createButtonFallback", "RaidGrid fallback must remain until in-game XML validation")
assertContains(lootCounter, "ensureHeaderFallback", "LootCounter fallback must remain until in-game XML validation")
assertContains(lootCounter, "ensureRowFallback", "LootCounter row fallback must remain until in-game XML validation")
```

- [ ] **Step 4: Run full local gates**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/raid_grid_spec_icon_spec.lua
lua tests/screen_notice_runtime_spec.lua
lua tests/release_stabilization_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
git diff --check
```

Expected: all PASS.

- [ ] **Step 5: In-game smoke checklist**

Use a WoW 3.3.5a client with script errors enabled:

```text
/console scriptErrors 1
/reload
```

Check `World of Warcraft\Logs\FrameXML.log` for no XML parse errors.

Manually verify:

```text
/krt opens without errors
Master item selection frame opens and sizes correctly
Logger tabs, headers, row selection, row focus, attendance spec, and inspect icons render correctly
LootCounter rows, scroll, plus, minus, reset, reset all, announce, class colors, and spec icons work
Reserves rows, separators, collapse/expand, item tooltip, and player tooltip work
RaidGrid opens, drags, closes, shows empty state, renders spec icons, and selects a player
ScreenNotice is hidden at login and fades when triggered
Repeated open/close/refresh does not create duplicate overlays
```

- [ ] **Step 6: Remove verified-dead fallback code in a separate micro-patch**

Only after Step 5 passes, remove fallback helpers that are no longer reachable. Keep generic helper
fallbacks that may serve unnamed rows or old internal callers.

- [ ] **Step 7: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT
git commit -m "chore: audit migrated UI visual construction"
```

## Parent Final Review Policy

Parent final review policy: validate the implemented plan before closure, including scope adherence, diff sanity, and evidence from runs.

## Final Review Checklist

Parent review must verify:

- No XML `<Scripts>` or `<On...>` handlers were added.
- `!KRT/!KRT.toc` still loads reusable templates before Lua modules.
- `!KRT/KRT.xml` concrete frame includes do not require code to resolve them at module load time.
- Services do not reference frames, widgets, controllers, or UI helper modules.
- Logger, LootCounter, RaidGrid, Reserves, ScreenNotice, and Master public APIs are unchanged.
- SavedVariables shape is unchanged.
- `!KRT/CHANGELOG.md` is updated only if a user-visible behavior or appearance change is accepted.
- All static checks pass.
- In-game smoke confirms no XML errors, no Lua errors, and no duplicate overlays after refresh/toggle.
- Remaining-risk reporting: include explicit residual risks, unresolved follow-ups, and rationale for any deferred cleanup.

## Execution Handoff

Use `superpowers:subagent-driven-development` for implementation. Dispatch one fresh
`spark_implementer` per task with the exact task steps and file list, then review the diff before
starting the next task. Use `code-mapper` before Task 4, Task 6, or Task 7 if the current code has
changed since this plan was written.
