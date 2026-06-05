# Logger List Visual Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh Logger list rows, headers, scroll gutters, and loot column rhythm while preserving the current runtime tab layout and behavior.

**Architecture:** Keep ownership in `!KRT/Controllers/Logger.lua` for Logger-specific visual/layout code and use
`!KRT/Modules/UI/Visuals.lua` only for shared selected/focused row textures. Do not change Services, SavedVariables,
XML scripts, list controller semantics, or the runtime panel layout in `refreshLoggerTabLayout()`.

**Tech Stack:** WoW 3.3.5a XML/Lua 5.1, KRT `ListController`, KRT `UIRowVisuals`, PowerShell repo checks through `tools/krt.py`.

---

## File Structure

- Modify `!KRT/Controllers/Logger.lua`
  - Tune Logger panel/header/row styling.
  - Add Logger-local loot column width helpers.
  - Apply loot widths to headers and row parts.
  - Adjust row heights through list drawer return values.
- Modify `!KRT/Modules/UI/Visuals.lua`
  - Tune Logger-only selected/focused visual colors while preserving non-Logger visuals.
- No XML changes are planned.
- No Service changes are planned.
- No SavedVariables or localization changes are planned.

---

### Task 1: Add Lua Visual Contract Test

**Files:**
- Create: `tests/logger_visual_refresh_spec.lua`
- Modify: none
- Test: `tests/logger_visual_refresh_spec.lua`

- [ ] **Step 1: Write the failing test**

Create `tests/logger_visual_refresh_spec.lua` with assertions against the Lua source. This is a source-level regression
test because WoW frame rendering is not available in the local test runner.

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local logger = read("!KRT/Controllers/Logger.lua")
local visuals = read("!KRT/Modules/UI/Visuals.lua")

assert(logger:find("LOGGER_LOOT_COLUMN_WIDTHS", 1, true), "Logger loot column widths must be centralized")
assert(logger:find("applyLootListColumnWidths", 1, true), "Logger loot header widths must be applied centrally")
assert(logger:find("applyLootRowColumnWidths", 1, true), "Logger loot row widths must be applied centrally")
assert(logger:find("LOGGER_LOOT_ROW_HEIGHT", 1, true), "Logger loot row height must be explicit")
assert(logger:find("LOGGER_COMPACT_ROW_HEIGHT", 1, true), "Logger compact row height must be explicit")
assert(logger:find("setLoggerRowIndex", 1, true), "Logger row striping must reset on row reuse")
assert(logger:find("rightInset = 0", 1, true), "Logger lists must keep the existing scrollbar inset policy")
assert(not logger:find("KRTLoggerBossAttendees.+Show%("), "Logger refresh must not restore hidden boss attendee panel")

assert(visuals:find("isLoggerRow%(row%)", 1, false), "Logger row visuals must stay scoped to Logger rows")
assert(visuals:find("0%.08, 0%.52, 0%.10", 1, false), "Logger selected rows must remain green")

print("logger visual refresh source contract passed")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
```

Expected: FAIL because the centralized loot width helpers and explicit row height constants do not exist yet. If `lua`
is not available, run the repo's Lua test wrapper if present, otherwise record the missing local Lua runtime and rely on
the static repo gates in Task 4.

- [ ] **Step 3: Commit the failing test**

```powershell
git add tests/logger_visual_refresh_spec.lua
git commit -m "test: capture logger visual refresh contract"
```

---

### Task 2: Implement Logger Row, Header, And Column Polish

**Files:**
- Modify: `!KRT/Controllers/Logger.lua`
- Test: `tests/logger_visual_refresh_spec.lua`

- [ ] **Step 1: Add Logger-local constants near the existing Logger style helpers**

Add constants after `loggerHeaderSuffixes`:

```lua
local LOGGER_COMPACT_ROW_HEIGHT = 22
local LOGGER_LOOT_ROW_HEIGHT = 32

local LOGGER_LOOT_COLUMN_WIDTHS = {
    icon = 30,
    item = 185,
    source = 126,
    winner = 92,
    type = 42,
    roll = 35,
    time = 32,
}
```

- [ ] **Step 2: Add width helpers near `applyRaidRowColumnWidths()`**

Add:

```lua
local function applyLootListColumnWidths(frameName)
    if not frameName then
        return
    end
    setWidgetWidth(_G[frameName .. "HeaderItem"], LOGGER_LOOT_COLUMN_WIDTHS.icon + LOGGER_LOOT_COLUMN_WIDTHS.item)
    setWidgetWidth(_G[frameName .. "HeaderSource"], LOGGER_LOOT_COLUMN_WIDTHS.source)
    setWidgetWidth(_G[frameName .. "HeaderWinner"], LOGGER_LOOT_COLUMN_WIDTHS.winner)
    setWidgetWidth(_G[frameName .. "HeaderType"], LOGGER_LOOT_COLUMN_WIDTHS.type)
    setWidgetWidth(_G[frameName .. "HeaderRoll"], LOGGER_LOOT_COLUMN_WIDTHS.roll)
    setWidgetWidth(_G[frameName .. "HeaderTime"], LOGGER_LOOT_COLUMN_WIDTHS.time)
end

local function applyLootRowColumnWidths(ui)
    if not ui then
        return
    end
    setWidgetWidth(ui.Name, LOGGER_LOOT_COLUMN_WIDTHS.item)
    setWidgetWidth(ui.Source, LOGGER_LOOT_COLUMN_WIDTHS.source)
    setWidgetWidth(ui.Winner, LOGGER_LOOT_COLUMN_WIDTHS.winner)
    setWidgetWidth(ui.Type, LOGGER_LOOT_COLUMN_WIDTHS.type)
    setWidgetWidth(ui.Roll, LOGGER_LOOT_COLUMN_WIDTHS.roll)
    setWidgetWidth(ui.Time, LOGGER_LOOT_COLUMN_WIDTHS.time)
end
```

- [ ] **Step 3: Make row styling reset safely on row reuse**

Change `styleLoggerRow(row)` to create base, alternate, and separator textures once, and add a private local helper:

```lua
local function setLoggerRowIndex(row, index)
    if not row then
        return
    end
    styleLoggerRow(row)
    local isAlt = index and (index % 2 == 0)
    if row._krtLoggerBg then
        if isAlt then
            row._krtLoggerBg:SetTexture(0.07, 0.07, 0.07, 0.74)
        else
            row._krtLoggerBg:SetTexture(0.025, 0.025, 0.025, 0.76)
        end
    end
end
```

Keep the helper local to `Controllers/Logger.lua`; use camelCase because this is a private helper.

- [ ] **Step 4: Apply striping and row heights in `makeLoggerList()`**

In the `cfg.drawRow` wrapper, call `setLoggerRowIndex(row, it and it._rowIndex)` before the original drawer. If data
items do not have `_rowIndex`, set it in `ListController`-fed data after `refreshData()` by assigning `self.data[i]._rowIndex = i`
inside `ListController` only if needed. Prefer doing it in `makeLoggerList()` by wrapping `cfg.getData`:

```lua
if cfg.getData then
    local getData = cfg.getData
    cfg.getData = function(out)
        getData(out)
        for i = 1, #out do
            out[i]._rowIndex = i
        end
    end
end
```

- [ ] **Step 5: Apply loot header and row widths**

Call `applyLootListColumnWidths("KRTLoggerLoot")` in `refreshLoggerTabLayout()` after `applyRaidListColumnWidths()`.
In the loot list drawer, call `applyLootRowColumnWidths(ui)` before setting loot text.

- [ ] **Step 6: Return explicit row heights**

For non-loot Logger drawers, return `LOGGER_COMPACT_ROW_HEIGHT` from the draw wrapper or set row height before returning.
For the loot drawer, return `LOGGER_LOOT_ROW_HEIGHT`.

- [ ] **Step 7: Run the source contract test**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
```

Expected: PASS with `logger visual refresh source contract passed`, unless local Lua is unavailable.

---

### Task 3: Tune Shared Logger Selected/Focused Visuals

**Files:**
- Modify: `!KRT/Modules/UI/Visuals.lua`
- Test: `tests/logger_visual_refresh_spec.lua`

- [ ] **Step 1: Tune Logger selected state**

In `UIRowVisuals.SetRowSelected`, keep non-Logger behavior unchanged and keep Logger rows green:

```lua
if isLoggerRow(row) then
    row._krtSelTex:SetVertexColor(0.08, 0.52, 0.10, 0.76)
else
    row._krtSelTex:SetVertexColor(0.20, 0.60, 1.00, 0.52)
end
```

- [ ] **Step 2: Tune Logger focused state**

In `UIRowVisuals.SetRowFocused`, make Logger focus secondary to selected:

```lua
if isLoggerRow(row) then
    texture:SetVertexColor(0.95, 0.72, 0.20, 0.26)
else
    texture:SetVertexColor(0.20, 0.60, 1.00, 0.72)
end
```

- [ ] **Step 3: Run the source contract test**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
```

Expected: PASS with `logger visual refresh source contract passed`, unless local Lua is unavailable.

---

### Task 4: Run Repo Verification

**Files:**
- No edits expected.

- [ ] **Step 1: Run UI binding check**

```powershell
py -3 tools/krt.py repo-quality-check --check ui_binding
```

Expected: PASS, with no XML inline scripts reported.

- [ ] **Step 2: Run Lua syntax check**

```powershell
py -3 tools/krt.py repo-quality-check --check lua_syntax
```

Expected: PASS.

- [ ] **Step 3: Run Lua uniformity check**

```powershell
py -3 tools/krt.py repo-quality-check --check lua_uniformity
```

Expected: PASS or only pre-existing unrelated findings. New Logger changes must not introduce naming or section-header
regressions.

- [ ] **Step 4: Run focused architecture scans**

```powershell
rg -n "<Scripts>|<On[A-Za-z]+" "!KRT/UI"
rg -n "addon\\.(LootCounter|ReservesUI|Config)" "!KRT/Controllers" "!KRT/EntryPoints"
rg -n "KRTLoggerBossAttendees.*Show|BossAttendees.*Show" "!KRT/Controllers/Logger.lua"
```

Expected:

- First command: no inline XML script matches.
- Second command: no new direct widget facade regressions.
- Third command: no match that restores the hidden boss-attendee panel in the runtime tab layout.

- [ ] **Step 5: Commit implementation**

```powershell
git add tests/logger_visual_refresh_spec.lua !KRT/Controllers/Logger.lua !KRT/Modules/UI/Visuals.lua
git commit -m "ui: polish logger list visuals"
```

Expected: commit succeeds after pre-commit checks.
