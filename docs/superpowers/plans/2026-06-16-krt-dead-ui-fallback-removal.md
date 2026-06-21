# KRT Dead UI Fallback Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove old UI XML migration fallback code that has been validated in game and is no longer needed.

**Architecture:** Keep XML as the owner of fixed visual skeletons and keep Lua as the owner of runtime behavior, state, data binding, click handlers, tooltips, and refresh. Remove only the ScreenNotice and RaidGrid fallback construction paths that were intentionally kept during the first XML migration; keep generic fallback helpers that still serve unnamed rows, dynamic rows, tests, or non-XML callers.

**Tech Stack:** WoW 3.3.5a Interface 30300 XML, Lua 5.1, KRT UI source-contract tests, repo `tools/krt.py` quality gates, and in-game FrameXML smoke checks.

---

## Workflow Classification

Classification for execution: `complex-orchestrated`.

Use the repository 55to53 workflow during execution:

- Parent agent analyzes, narrows, reviews, and owns final correction.
- Use `code-mapper` before Task 2 or Task 4 if current source has drifted.
- Delegate implementation tasks to `spark_implementer` with closed operational instructions.
- Parent reviews every diff before continuing.

## Scope

Remove in this plan:

- `!KRT/Modules/UI/ScreenNotice.lua` fallback frame and font-string construction.
- `!KRT/Widgets/RaidGrid.lua` fallback frame, child-region, and button visual construction.
- Source-contract assertions that still require those fallback paths to remain.

Do not remove in this plan:

- `!KRT/Widgets/LootCounter.lua` Lua visual construction. LootCounter was deliberately restored to Lua-owned construction after in-game regressions.
- `!KRT/Modules/UI/Visuals.lua` generic row/header/logger fallback helpers. These still serve shared widgets, unnamed rows, and older internal callers.
- `!KRT/Controllers/Logger.lua` dynamic inspect/spec icon creation. It still creates variable item icons and secondary spec icons at runtime.
- `!KRT/Widgets/ReservesUI.lua` separator fallback removal already completed in Task 9; only keep its source-contract guard.
- `!KRT/Modules/UI/Effects.lua`, `!KRT/Modules/UI/ListController.lua`, and `!KRT/Modules/UI/Frames.lua` dynamic helper frames.

## File Structure

Modify:

- `tests/ui_xml_homogenization_source_spec.lua`: flip ScreenNotice and RaidGrid fallback assertions from "must keep" to "must not contain".
- `!KRT/Modules/UI/ScreenNotice.lua`: resolve only XML-created `KRTScreenNoticeFrame` and child fontstrings.
- `tests/raid_grid_spec_icon_spec.lua`: seed XML-like RaidGrid globals in the standalone Lua harness.
- `!KRT/Widgets/RaidGrid.lua`: remove fallback top-level frame, child-region, and button visual creation.

Generated only if pre-commit reports drift:

- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/TREE.md`

No changes expected:

- `!KRT/CHANGELOG.md`, unless in-game smoke identifies a user-visible behavior change.
- `!KRT/!KRT.toc`, because `ScreenNotice.xml` and `RaidGrid.xml` are already included through `!KRT/KRT.xml`.
- `!KRT/UI/ScreenNotice.xml` and `!KRT/UI/RaidGrid.xml`, unless a smoke test reveals a missing XML child required by Lua.

## Pre-Execution Inventory

Before Task 1, run:

```powershell
git status --short
rg -n "CreateFrame\(\"Frame\", FRAME_NAME|createButtonFallback|KRTRaidGridFrame or|fallback must remain|fallback creation" tests !KRT/Modules/UI/ScreenNotice.lua !KRT/Widgets/RaidGrid.lua
```

Expected current matches before implementation:

```text
tests/ui_xml_homogenization_source_spec.lua: ScreenNotice fallback assertions
tests/ui_xml_homogenization_source_spec.lua: RaidGrid fallback assertions
!KRT/Modules/UI/ScreenNotice.lua: frame = CreateFrame("Frame", FRAME_NAME, UIParent)
!KRT/Widgets/RaidGrid.lua: createButtonFallback
!KRT/Widgets/RaidGrid.lua: frame = _G.KRTRaidGridFrame or _G.CreateFrame(...)
```

If the matches are already gone, stop and ask the parent to remap the task instead of applying this plan.

---

### Task 1: Add ScreenNotice Dead-Fallback Source Contract

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`

- [ ] **Step 1: Replace ScreenNotice keep-fallback assertions**

In `tests/ui_xml_homogenization_source_spec.lua`, replace the existing ScreenNotice fallback assertions:

```lua
assertContains(screenNotice, 'CreateFrame("Frame", FRAME_NAME, UIParent)', "ScreenNotice must keep fallback creation")
assertContains(screenNotice, 'CreateFrame("Frame", FRAME_NAME, UIParent)', "ScreenNotice fallback must remain until in-game XML validation")
```

with this XML-only contract:

```lua
assertContains(screenNotice, "_G[FRAME_NAME]", "ScreenNotice must resolve XML frame by name")
assertContains(screenNotice, 'FRAME_NAME .. "TitleText"', "ScreenNotice must resolve XML title text")
assertContains(screenNotice, 'FRAME_NAME .. "DetailText"', "ScreenNotice must resolve XML detail text")
assertNotContains(screenNotice, 'CreateFrame("Frame", FRAME_NAME, UIParent)', "ScreenNotice must rely on XML frame after in-game validation")
assertNotContains(screenNotice, "frame:CreateFontString(nil, \"OVERLAY\")", "ScreenNotice must rely on XML fontstrings after in-game validation")
```

Keep the existing `assertContains` checks for XML frame and child resolution if they are already present; do not duplicate identical assertions.

- [ ] **Step 2: Run the source-contract test and verify failure**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL with a message containing:

```text
ScreenNotice must rely on XML frame after in-game validation
```

- [ ] **Step 3: Commit the failing contract**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua
git commit -m "test: guard screen notice xml-only fallback removal"
```

Expected: commit succeeds only if the project allows a failing source-contract commit in the current workflow branch. If the pre-commit hook blocks failing tests, keep the test staged locally and continue directly to Task 2 without committing.

### Task 2: Remove ScreenNotice Fallback Construction

**Files:**

- Modify: `!KRT/Modules/UI/ScreenNotice.lua`

- [ ] **Step 1: Remove fallback-only locals**

In `!KRT/Modules/UI/ScreenNotice.lua`, remove these local bindings:

```lua
local CreateFrame = CreateFrame
local UIParent = UIParent
```

Also remove this fallback-only constant:

```lua
local FONT_PATH = "FONTS\\FRIZQT__.TTF"
```

- [ ] **Step 2: Replace `ensureFrame()` with XML-only resolution**

Replace the full `ensureFrame()` function with:

```lua
local function ensureFrame()
    if frame then
        return frame
    end

    frame = _G[FRAME_NAME]
    if not frame then
        return nil
    end

    titleText = _G[FRAME_NAME .. "TitleText"]
    detailText = _G[FRAME_NAME .. "DetailText"]
    if not titleText or not detailText then
        frame = nil
        titleText = nil
        detailText = nil
        return nil
    end

    if frame.SetFrameLevel then
        frame:SetFrameLevel(1000)
    end

    return frame
end
```

Do not move fade logic, sizing logic, text colorization, event registration, or `Effects.SetTimedFade`.

- [ ] **Step 3: Run focused tests**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/screen_notice_runtime_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
git diff --check
```

Expected:

```text
ui xml homogenization source contract passed
screen notice runtime contract passed
Lua syntax check passed.
```

`git diff --check` should print no output and exit 0.

- [ ] **Step 4: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua !KRT/Modules/UI/ScreenNotice.lua
git commit -m "fix: remove screen notice xml fallback"
```

### Task 3: Add RaidGrid Dead-Fallback Source Contract

**Files:**

- Modify: `tests/ui_xml_homogenization_source_spec.lua`

- [ ] **Step 1: Replace RaidGrid keep-fallback assertions**

In `tests/ui_xml_homogenization_source_spec.lua`, remove these assertions if present:

```lua
assertContains(raidGrid, "createButtonFallback", "RaidGrid lua should still fallback construct buttons")
assertContains(raidGrid, "_G.KRTRaidGridFrame or", "raidgrid lua should resolve frame from global or fallback")
assertContains(raidGrid, "createButtonFallback", "RaidGrid fallback must remain until in-game XML validation")
```

Add these assertions near the existing RaidGrid source-contract block:

```lua
assertContains(raidGrid, "KRTRaidGridButtonTemplate", "RaidGrid lua should use button template")
assertContains(raidGrid, "KRTRaidGridFrameIcon", "RaidGrid lua should resolve xml icon")
assertContains(raidGrid, "KRTRaidGridFrameCloseButton", "RaidGrid lua should resolve xml close button")
assertNotContains(raidGrid, "createButtonFallback", "RaidGrid buttons must rely on XML templates after in-game validation")
assertNotContains(raidGrid, "_G.KRTRaidGridFrame or", "RaidGrid frame must rely on XML top-level frame after in-game validation")
assertNotContains(raidGrid, "local function ensureRegion()", "RaidGrid must not keep fake visual-region fallback helpers")
assertNotContains(raidGrid, "local function createTexture(parent, layer)", "RaidGrid must not create XML-owned textures in Lua")
assertNotContains(raidGrid, "local function createFontString(parent, template)", "RaidGrid must not create XML-owned fontstrings in Lua")
```

Keep existing assertions for scripts being bound in Lua:

```lua
assertContains(raidGrid, 'SetScript", "OnEnter"', "raidgrid button should bind OnEnter in Lua")
assertContains(raidGrid, 'SetScript", "OnLeave"', "raidgrid button should bind OnLeave in Lua")
assertContains(raidGrid, 'SetScript", "OnClick"', "raidgrid button should bind OnClick in Lua")
assertContains(raidGrid, 'SetScript", "OnDragStart"', "raidgrid frame should bind drag start script")
assertContains(raidGrid, 'SetScript", "OnDragStop"', "raidgrid frame should bind drag stop script")
```

- [ ] **Step 2: Run the source-contract test and verify failure**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
```

Expected: FAIL with a message containing:

```text
RaidGrid buttons must rely on XML templates after in-game validation
```

- [ ] **Step 3: Commit the failing contract**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua
git commit -m "test: guard raid grid xml-only fallback removal"
```

Expected: commit succeeds only if the project allows a failing source-contract commit in the current workflow branch. If the pre-commit hook blocks failing tests, keep the test staged locally and continue directly to Task 4 without committing.

### Task 4: Remove RaidGrid Fallback Construction

**Files:**

- Modify: `!KRT/Widgets/RaidGrid.lua`
- Modify: `tests/raid_grid_spec_icon_spec.lua`

- [ ] **Step 1: Seed XML-like RaidGrid globals in the standalone test**

In `tests/raid_grid_spec_icon_spec.lua`, after `fakeG.CreateFrame` is defined and before loading `!KRT/Widgets/RaidGrid.lua`, add this harness setup:

```lua
fakeG.CreateFrame("Frame", "KRTRaidGridFrame", fakeG.UIParent, "KRTDialogTemplate")

local raidGridFrameChildren = {
    "Icon",
    "Title",
    "Count",
    "Divider",
    "Empty",
    "CloseButton",
}
for i = 1, #raidGridFrameChildren do
    local childName = "KRTRaidGridFrame" .. raidGridFrameChildren[i]
    local child = makeFrame(childName)
    frames[childName] = child
    fakeG[childName] = child
end
```

This mirrors the XML top-level frame and children that the real client creates from `!KRT/UI/RaidGrid.xml`.

- [ ] **Step 2: Remove visual fallback helper functions from RaidGrid**

In `!KRT/Widgets/RaidGrid.lua`, delete these helper functions completely:

```lua
local function ensureRegion()
    return {
        Show = noop,
        Hide = noop,
        SetAllPoints = noop,
        SetBlendMode = noop,
        SetFontObject = noop,
        SetHeight = noop,
        SetJustifyH = noop,
        SetPoint = noop,
        SetText = noop,
        SetTextColor = noop,
        SetTexture = noop,
        SetVertexColor = noop,
        SetWidth = noop,
    }
end
```

```lua
local function createTexture(parent, layer)
    if parent and parent.CreateTexture then
        return parent:CreateTexture(nil, layer)
    end
    return ensureRegion()
end
```

```lua
local function createFontString(parent, template)
    if parent and parent.CreateFontString then
        return parent:CreateFontString(nil, "OVERLAY", template)
    end
    return ensureRegion()
end
```

Also delete the full `createButtonFallback(index, button)` function.
Also delete this now-unused helper:

```lua
local function noop() end
```

- [ ] **Step 3: Make `createButton(index)` XML-template-only**

Replace `createButton(index)` with:

```lua
local function createButton(index)
    local buttonName = "KRTRaidGridButton" .. tostring(index)
    local button = _G[buttonName]
    if not button and _G.CreateFrame then
        button = _G.CreateFrame("Button", buttonName, frame, "KRTRaidGridButtonTemplate")
    end
    assert(button, "KRTRaidGridButtonTemplate frame is required")

    setSize(button, CFG.buttonWidth, CFG.buttonHeight)
    safeCall(button, "RegisterForClicks", "LeftButtonUp")

    button.bg = _G[buttonName .. "Bg"]
    button.topLine = _G[buttonName .. "TopLine"]
    button.bottomLine = _G[buttonName .. "BottomLine"]
    button.highlight = _G[buttonName .. "Highlight"]
    button.text = _G[buttonName .. "Text"]
    button.specIcon = _G[buttonName .. "SpecIcon"]
    assert(button.bg and button.text and button.specIcon, "KRTRaidGridButtonTemplate children are required")

    setSize(button.specIcon, CFG.specIconSize, CFG.specIconSize)
    safeCall(button.specIcon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
    safeCall(button.specIcon, "Hide")
    buttons[index] = button
    updateButtonColor(button, false)

    safeCall(button, "SetScript", "OnEnter", function(self)
        updateButtonColor(self, true)
        if _G.GameTooltip and _G.GameTooltip.SetOwner then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if _G.GameTooltip.AddLine then
                _G.GameTooltip:AddLine(self.fullName or "Unknown", 1, 1, 1)
                _G.GameTooltip:AddLine(getTooltipLine(), 0.75, 0.75, 0.75)
            end
            if _G.GameTooltip.Show then
                _G.GameTooltip:Show()
            end
        end
    end)
    safeCall(button, "SetScript", "OnLeave", function(self)
        updateButtonColor(self, false)
        if _G.GameTooltip and _G.GameTooltip.Hide then
            _G.GameTooltip:Hide()
        end
    end)
    safeCall(button, "SetScript", "OnClick", function(self)
        selectEntry(self.entry)
    end)

    return button
end
```

- [ ] **Step 4: Make `ensureFrame()` XML-top-level-only**

In `ensureFrame()`, replace:

```lua
frame = _G.KRTRaidGridFrame or _G.CreateFrame("Frame", "KRTRaidGridFrame", _G.UIParent, "KRTDialogTemplate")
```

with:

```lua
frame = _G.KRTRaidGridFrame
if not frame then
    return nil
end
```

Then replace the fallback child creation blocks with strict XML resolution:

```lua
frame.icon = _G.KRTRaidGridFrameIcon
frame.title = _G.KRTRaidGridFrameTitle
frame.count = _G.KRTRaidGridFrameCount
frame.divider = _G.KRTRaidGridFrameDivider
frame.empty = _G.KRTRaidGridFrameEmpty
frame.closeButton = _G.KRTRaidGridFrameCloseButton
if not (frame.icon and frame.title and frame.count and frame.divider and frame.empty and frame.closeButton) then
    frame = nil
    return nil
end

setTextureColor(frame.divider, 1, 0.82, 0, 0.35)
safeCall(frame.closeButton, "SetScript", "OnClick", function()
    module.Hide()
end)
```

Keep these frame behavior bindings in Lua:

```lua
safeCall(frame, "Hide")
safeCall(frame, "SetFrameStrata", "FULLSCREEN_DIALOG")
safeCall(frame, "SetToplevel", true)
safeCall(frame, "SetClampedToScreen", true)
safeCall(frame, "SetMovable", true)
safeCall(frame, "EnableMouse", true)
safeCall(frame, "RegisterForDrag", "LeftButton")
safeCall(frame, "SetScript", "OnDragStart", function(self)
    if self.StartMoving then
        self:StartMoving()
    end
end)
safeCall(frame, "SetScript", "OnDragStop", function(self)
    if self.StopMovingOrSizing then
        self:StopMovingOrSizing()
    end
end)
```

- [ ] **Step 5: Guard public methods against missing XML**

In `module.ShowPicker`, replace:

```lua
ensureFrame()
```

with:

```lua
if not ensureFrame() then
    return false
end
```

In `module.Refresh`, replace:

```lua
ensureFrame()
```

with:

```lua
if not ensureFrame() then
    return false
end
```
No additional loop guard is required because `createButton(index)` asserts the XML button template
and its required children. A missing template child is a programming/load-order error after this
cleanup, not a recoverable runtime branch.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/raid_grid_spec_icon_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
git diff --check
```

Expected:

```text
ui xml homogenization source contract passed
raid grid spec icon spec passed
Lua syntax check passed.
```

`git diff --check` should print no output and exit 0.

- [ ] **Step 7: Commit**

```powershell
git add -- tests/ui_xml_homogenization_source_spec.lua tests/raid_grid_spec_icon_spec.lua !KRT/Widgets/RaidGrid.lua
git commit -m "fix: remove raid grid xml fallbacks"
```

### Task 5: Final Audit, In-Game Gate, And Generated Docs

**Files:**

- Modify only if generated by checks: `docs/FUNCTION_REGISTRY.csv`
- Modify only if generated by checks: `docs/FN_CLUSTERS.md`
- Modify only if generated by checks: `docs/TREE.md`

- [ ] **Step 1: Run fallback inventory**

Run:

```powershell
rg -n "CreateFrame\(\"Frame\", FRAME_NAME|createButtonFallback|KRTRaidGridFrame or|fallback must remain|fallback creation" tests !KRT/Modules/UI/ScreenNotice.lua !KRT/Widgets/RaidGrid.lua
```

Expected: no matches.

- [ ] **Step 2: Confirm intentional fallback areas still remain**

Run:

```powershell
rg -n "CreateTexture\(|CreateFontString\(|CreateFrame\(" !KRT/Modules/UI/Visuals.lua !KRT/Controllers/Logger.lua !KRT/Widgets/LootCounter.lua !KRT/Modules/UI/Effects.lua !KRT/Modules/UI/ListController.lua !KRT/Modules/UI/Frames.lua
```

Expected remaining categories:

```text
!KRT/Modules/UI/Visuals.lua: generic row/header/logger visual fallbacks
!KRT/Controllers/Logger.lua: dynamic inspect/spec icon creation
!KRT/Widgets/LootCounter.lua: intentional Lua-owned LootCounter construction
!KRT/Modules/UI/Effects.lua: runtime effects construction
!KRT/Modules/UI/ListController.lua: dynamic row creation
!KRT/Modules/UI/Frames.lua: shared refresh/defer driver
```

Do not remove these in this plan.

- [ ] **Step 3: Run full local gates**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/raid_grid_spec_icon_spec.lua
lua tests/screen_notice_runtime_spec.lua
lua tests/logger_visual_refresh_spec.lua
lua tests/release_stabilization_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
git diff --check
```

Expected:

```text
ui xml homogenization source contract passed
raid grid spec icon spec passed
screen notice runtime contract passed
logger visual refresh source contract passed
295 targeted stabilization test(s) passed.
Lua syntax check passed.
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
```

- [ ] **Step 4: Run generated catalog refresh if pre-commit reports drift**

If `git commit` or `tools/krt.py api-catalog-check` reports stale generated docs, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

Then stage only generated docs that changed:

```powershell
git add -- docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/API_REGISTRY.csv docs/API_REGISTRY_PUBLIC.csv docs/API_REGISTRY_INTERNAL.csv docs/API_NOMENCLATURE_CENSUS.md docs/TREE.md
```

- [ ] **Step 5: In-game smoke checklist**

Use a WoW 3.3.5a client with script errors enabled:

```text
/console scriptErrors 1
/reload
```

Verify:

```text
FrameXML.log has no Error loading Interface\AddOns\!KRT
FrameXML.log has no Couldn't find inherited node from !KRT
FrameXML.log has no Couldn't find relative frame from !KRT
/krt opens without Lua errors
ScreenNotice is hidden at login
ScreenNotice appears and fades when triggered by the existing Master Loot notice path
RaidGrid opens from Master target/award flows
RaidGrid drag, close button, empty state, spec icons, tooltip, and selection still work
LootCounter remains unchanged from the restored Lua-owned version
Logger row/header visuals still render
Reserves row separators still render
```

- [ ] **Step 6: Commit final generated docs and audit note**

If Task 5 changed only generated docs, commit them:

```powershell
git add -- docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/API_REGISTRY.csv docs/API_REGISTRY_PUBLIC.csv docs/API_REGISTRY_INTERNAL.csv docs/API_NOMENCLATURE_CENSUS.md docs/TREE.md
git commit -m "docs: refresh fallback removal catalogs"
```

If Task 5 changed no files, do not create an empty commit.

#### Execution audit note - 2026-06-17

Task 5 completed after the final in-game gate.

- ScreenNotice fallback removal commit: `139b6ae9 fix: remove screen notice xml fallback`.
- RaidGrid fallback removal commit: `6f8143c2 fix: remove raid grid xml fallbacks`.
- Final FrameXML review found no `!KRT` load errors, missing inherited nodes, or missing relative frames.
- User-reported in-game smoke passed with correct ScreenNotice, RaidGrid, LootCounter, Master Loot, and
  Logger/Reserves behavior and no Lua errors.
- Final source audit found no removed ScreenNotice or RaidGrid fallback strings in the target files.
- Final generated catalog refresh had already been included in the implementation commits; no extra generated-doc
  only commit was required after the in-game gate.

## Parent Final Review Checklist

Before closing execution, parent must verify:

- `ScreenNotice.lua` no longer calls `CreateFrame("Frame", FRAME_NAME, UIParent)`.
- `ScreenNotice.lua` no longer creates title/detail fontstrings in Lua.
- `RaidGrid.lua` no longer contains `createButtonFallback`.
- `RaidGrid.lua` no longer uses `_G.KRTRaidGridFrame or _G.CreateFrame(...)`.
- `RaidGrid.lua` still binds drag, close, button enter/leave/click scripts in Lua.
- `RaidGrid.lua` still creates dynamic player buttons through `KRTRaidGridButtonTemplate`.
- `tests/raid_grid_spec_icon_spec.lua` seeds XML-like top-level frame children, not fallback-created children.
- `tests/ui_xml_homogenization_source_spec.lua` preserves intentional fallback guards for Reserves and excludes LootCounter XML fallback assertions.
- No XML `<Scripts>` or `<On...>` handlers were added.
- No SavedVariables shape changed.
- No vendored library changed.
- In-game smoke has been reported before final closeout.

## Self-Review

Spec coverage:

- The plan removes the two old fallback areas that are both still explicitly marked as temporary in the current source-contract test: ScreenNotice and RaidGrid.
- The plan excludes LootCounter because the user chose to keep it Lua-owned after runtime regressions.
- The plan excludes generic shared visual fallbacks because current evidence does not prove they are dead for all unnamed/internal callers.

Placeholder scan:

- No forbidden placeholder terms or unspecified test steps are present.
- Each code-changing step includes exact files, exact snippets, and exact commands.

Type and naming consistency:

- Existing KRT names are preserved: `FRAME_NAME`, `KRTRaidGridFrame`, `KRTRaidGridButtonTemplate`, `KRTScreenNoticeFrameTitleText`, and `KRTScreenNoticeFrameDetailText`.
- Lua 5.1 syntax is used throughout.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-16-krt-dead-ui-fallback-removal.md`. Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
