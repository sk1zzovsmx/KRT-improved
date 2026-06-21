# KRT Logger UI Semantic Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the mixed Logger XML surface into Loot History, Raid Attendance, and shared log UI files, then remove the remaining `KRTLogger...` UI global names from active XML and Lua references.

**Architecture:** Keep `Controllers/Logger.lua` as the runtime owner for both Loot History and Raid Attendance behavior. Move XML into feature-owned layout files while keeping shared row/header/panel templates in a small shared XML file loaded before both feature XML files. Preserve public controller methods such as `ToggleLootHistory` and `ToggleRaidAttendance`, and preserve existing root frame names `KRTLootHistory`, `KRTRaidAttendance`, and `KRTExportFrame`.

**Tech Stack:** WoW 3.3.5a FrameXML, Lua 5.1, KRT source-contract Lua specs, PowerShell repo checks, Python XML parsing checks.

---

## Current Constraints

- Worktree currently contains prior cleanup edits to `!KRT/!KRT.toc` and `!KRT/UI/Logger.xml`; start implementation only after those changes are intentionally included or committed.
- Do not reintroduce `!KRT/KRT.xml`.
- Do not add XML `<Scripts>` or `<On...>` handlers.
- Do not rename public Lua controller methods in this pass:
  - `module.ToggleLootHistory`
  - `module.ToggleRaidAttendance`
- Do not rename root frame globals in this pass:
  - `KRTLootHistory`
  - `KRTLootHistoryRaids`
  - `KRTLootHistoryLoot`
  - `KRTRaidAttendance`
  - `KRTRaidAttendanceRaids`
  - `KRTRaidAttendanceRaidAttendees`
  - `KRTExportFrame`
- This plan targets active code only. Historical references inside older files under `docs/superpowers/plans/` may remain.

## File Structure

- Create: `!KRT/UI/Logger.xml`
  - Owns shared log-style XML templates used by Loot History and Raid Attendance.
  - New names:
    - `KRTLogPanelTemplate`
    - `KRTLogTableHeaderTemplate`
    - `KRTLogRaidRowTemplate`
- Create: `!KRT/UI/LootHistory.xml`
  - Owns `KRTLootHistory`, `KRTExportFrame`, `KRTLootHistoryRollTypePickerFrame`, and the loot row template.
  - New names:
    - `KRTLootHistoryLootRowTemplate`
    - `KRTLootHistoryRollTypePickerFrame`
- Create: `!KRT/UI/RaidAttendance.xml`
  - Owns `KRTRaidAttendance`, the raid attendance player row template, and inspect icon slot template.
  - New names:
    - `KRTRaidAttendancePlayerRowTemplate`
    - `KRTRaidAttendanceInspectItemIconButtonTemplate`
- Delete: `!KRT/UI/Logger.xml`
  - Its content is split into the three files above.
- Modify: `!KRT/UI/Templates/Common.xml`
  - Remove `KRTLoggerInspectItemIconButtonTemplate` after moving/renaming it into `RaidAttendance.xml`.
- Modify: `!KRT/!KRT.toc`
  - Replace `UI\Logger.xml` with:
    - `UI\Logger.xml`
    - `UI\LootHistory.xml`
    - `UI\RaidAttendance.xml`
  - Load them before `Controllers\Logger.lua`.
- Modify: `!KRT/Controllers/Logger.lua`
  - Use the new row template and popup frame names.
- Modify: `.luacheckrc`
  - Remove stale `KRTLogger...` globals.
  - Add the new XML template/frame globals.
- Modify: `tests/logger_visual_refresh_spec.lua`
  - Read split XML files and assert the new semantic names.
- Modify: `tests/ui_xml_homogenization_source_spec.lua`
  - Read split XML files, update inspect icon template ownership assertions, and assert TOC order.
- Modify: `tests/equip_inspect_source_contract_spec.lua`
  - Read `RaidAttendance.xml` for attendance row/header assertions.
- Modify: `tests/release_stabilization_spec.lua`
  - Read `LootHistory.xml` for loot source hitbox XML assertions.
- Modify generated docs:
  - `docs/TREE.md` via `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1`.

## Rename Map

| Old active UI global | New UI global |
| --- | --- |
| `KRTLoggerFrameTemplate` | `KRTLogPanelTemplate` |
| `KRTLoggerTableHeader` | `KRTLogTableHeaderTemplate` |
| `KRTLoggerRaidButton` | `KRTLogRaidRowTemplate` |
| `KRTLoggerLootButton` | `KRTLootHistoryLootRowTemplate` |
| `KRTLoggerRaidAttendeeButton` | `KRTRaidAttendancePlayerRowTemplate` |
| `KRTLoggerInspectItemIconButtonTemplate` | `KRTRaidAttendanceInspectItemIconButtonTemplate` |
| `KRTLoggerRollTypePickerFrame` | `KRTLootHistoryRollTypePickerFrame` |
| `KRTLoggerRollTypePickerFrameMS` | `KRTLootHistoryRollTypePickerFrameMS` |
| `KRTLoggerRollTypePickerFrameOS` | `KRTLootHistoryRollTypePickerFrameOS` |
| `KRTLoggerRollTypePickerFrameSR` | `KRTLootHistoryRollTypePickerFrameSR` |
| `KRTLoggerRollTypePickerFrameFree` | `KRTLootHistoryRollTypePickerFrameFree` |
| `KRTLoggerRollTypePickerFrameBank` | `KRTLootHistoryRollTypePickerFrameBank` |
| `KRTLoggerRollTypePickerFrameDE` | `KRTLootHistoryRollTypePickerFrameDE` |
| `KRTLoggerRollTypePickerFrameHold` | `KRTLootHistoryRollTypePickerFrameHold` |
| `KRTLoggerItemMenuFrame` | `KRTLootHistoryItemMenuFrame` |

---

### Task 1: Add Failing Source-Contract Coverage

**Files:**
- Modify: `tests/logger_visual_refresh_spec.lua`
- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `tests/equip_inspect_source_contract_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Update `tests/logger_visual_refresh_spec.lua` to read split XML**

Replace:

```lua
local loggerXml = read("!KRT/UI/Logger.xml")
```

with:

```lua
local LoggerXml = read("!KRT/UI/Logger.xml")
local lootHistoryXml = read("!KRT/UI/LootHistory.xml")
local raidAttendanceXml = read("!KRT/UI/RaidAttendance.xml")
local loggerXml = LoggerXml .. "\n" .. lootHistoryXml .. "\n" .. raidAttendanceXml
```

Add these assertions after the existing `ToggleRaidAttendance` assertion:

```lua
assert(LoggerXml:find('Frame name="KRTLogPanelTemplate"', 1, true), "Shared log XML must define KRTLogPanelTemplate")
assert(LoggerXml:find('Button name="KRTLogTableHeaderTemplate"', 1, true), "Shared log XML must define KRTLogTableHeaderTemplate")
assert(LoggerXml:find('Button name="KRTLogRaidRowTemplate"', 1, true), "Shared log XML must define KRTLogRaidRowTemplate")
assert(lootHistoryXml:find('Button name="KRTLootHistoryLootRowTemplate"', 1, true), "Loot History XML must define KRTLootHistoryLootRowTemplate")
assert(raidAttendanceXml:find('Button name="KRTRaidAttendancePlayerRowTemplate"', 1, true), "Raid Attendance XML must define KRTRaidAttendancePlayerRowTemplate")
assert(raidAttendanceXml:find('Button name="KRTRaidAttendanceInspectItemIconButtonTemplate"', 1, true), "Raid Attendance XML must define KRTRaidAttendanceInspectItemIconButtonTemplate")
assert(logger:find('rowTmpl = "KRTLogRaidRowTemplate"', 1, true), "Logger raid lists must use the shared log raid row template")
assert(logger:find('rowTmpl = "KRTLootHistoryLootRowTemplate"', 1, true), "Loot History loot list must use the Loot History row template")
assert(logger:find('rowTmpl = "KRTRaidAttendancePlayerRowTemplate"', 1, true), "Raid Attendance players list must use the Raid Attendance row template")
assert(logger:find('ROLLTYPE_PICKER_FRAME = "KRTLootHistoryRollTypePickerFrame"', 1, true), "Loot History roll type picker must use the semantic frame name")
assert(logger:find('"KRTLootHistoryItemMenuFrame"', 1, true), "Loot History item menu must use the semantic frame name")
assert(not loggerXml:find("KRTLoggerFrameTemplate", 1, true), "Split XML must not keep KRTLoggerFrameTemplate")
assert(not loggerXml:find("KRTLoggerTableHeader", 1, true), "Split XML must not keep KRTLoggerTableHeader")
assert(not loggerXml:find("KRTLoggerRaidButton", 1, true), "Split XML must not keep KRTLoggerRaidButton")
assert(not loggerXml:find("KRTLoggerLootButton", 1, true), "Split XML must not keep KRTLoggerLootButton")
assert(not loggerXml:find("KRTLoggerRaidAttendeeButton", 1, true), "Split XML must not keep KRTLoggerRaidAttendeeButton")
assert(not loggerXml:find("KRTLoggerInspectItemIconButtonTemplate", 1, true), "Split XML must not keep KRTLoggerInspectItemIconButtonTemplate")
assert(not loggerXml:find("KRTLoggerRollTypePickerFrame", 1, true), "Split XML must not keep KRTLoggerRollTypePickerFrame")
assert(not logger:find("KRTLoggerItemMenuFrame", 1, true), "Logger Lua must not keep KRTLoggerItemMenuFrame")
```

- [ ] **Step 2: Update inspect icon assertions in `tests/logger_visual_refresh_spec.lua`**

Replace:

```lua
assert(loggerXml:find("$parentInspectItemIcon1", 1, true), "Logger XML must define inspect item icon 1")
assert(loggerXml:find("$parentInspectItemIcon17", 1, true), "Logger XML must define inspect item icon 17")
```

with:

```lua
assert(raidAttendanceXml:find("$parentInspectItemIcon1", 1, true), "Raid Attendance XML must define inspect item icon 1")
assert(raidAttendanceXml:find("$parentInspectItemIcon17", 1, true), "Raid Attendance XML must define inspect item icon 17")
```

- [ ] **Step 3: Update `tests/ui_xml_homogenization_source_spec.lua` to read split XML**

Replace:

```lua
local loggerXml = read("!KRT/UI/Logger.xml")
```

with:

```lua
local LoggerXml = read("!KRT/UI/Logger.xml")
local lootHistoryXml = read("!KRT/UI/LootHistory.xml")
local raidAttendanceXml = read("!KRT/UI/RaidAttendance.xml")
local loggerXml = LoggerXml .. "\n" .. lootHistoryXml .. "\n" .. raidAttendanceXml
```

Replace:

```lua
assertContains(commonXml, "KRTLoggerInspectItemIconButtonTemplate", "common templates must provide inspect icon button template")
assertNotContains(loggerXml, 'name="KRTLoggerInspectItemIconButtonTemplate"', "logger xml must not duplicate runtime icon template")
```

with:

```lua
assertNotContains(commonXml, "KRTLoggerInspectItemIconButtonTemplate", "common templates must not keep logger-prefixed inspect icon template")
assertContains(raidAttendanceXml, "KRTRaidAttendanceInspectItemIconButtonTemplate", "raid attendance xml must provide inspect icon button template")
assertNotContains(loggerXml, 'name="KRTLoggerInspectItemIconButtonTemplate"', "split logger xml must not keep logger-prefixed inspect icon template")
```

Add these TOC order assertions after the existing `assertNotContains(toc, "KRT.xml", ...)` line:

```lua
assertContains(toc, "UI\\Logger.xml", "TOC must load shared Logger UI templates")
assertContains(toc, "UI\\LootHistory.xml", "TOC must load Loot History XML")
assertContains(toc, "UI\\RaidAttendance.xml", "TOC must load Raid Attendance XML")
assertNotContains(toc, "UI\\Logger.xml", "TOC must not load the retired mixed Logger XML file")
assertBefore(toc, "UI\\Logger.xml", "UI\\LootHistory.xml", "shared Logger templates must load before Loot History XML")
assertBefore(toc, "UI\\Logger.xml", "UI\\RaidAttendance.xml", "shared Logger templates must load before Raid Attendance XML")
assertBefore(toc, "UI\\LootHistory.xml", "Controllers\\Logger.lua", "Loot History XML must load before Logger controller")
assertBefore(toc, "UI\\RaidAttendance.xml", "Controllers\\Logger.lua", "Raid Attendance XML must load before Logger controller")
```

Replace:

```lua
assertContains(logger, '_G[iconName .. "Texture"]', "logger must resolve icon textures through XML globals")
```

with:

```lua
assertContains(logger, '_G[iconName .. "Texture"]', "logger must resolve icon textures through XML globals")
assertContains(raidAttendanceXml, 'inherits="KRTRaidAttendanceInspectItemIconButtonTemplate"', "raid attendance inspect icon slots must inherit the semantic inspect icon template")
```

- [ ] **Step 4: Update `tests/equip_inspect_source_contract_spec.lua` to read Raid Attendance XML**

Replace:

```lua
local xml = read("!KRT/UI/Logger.xml")
```

with:

```lua
local xml = read("!KRT/UI/RaidAttendance.xml")
```

- [ ] **Step 5: Update `tests/release_stabilization_spec.lua` XML path for the loot source hitbox test**

In the test named `logger loot XML exposes layout-only source column hitbox`, replace:

```lua
local xml = readText("!KRT/UI/Logger.xml")
```

with:

```lua
local xml = readText("!KRT/UI/LootHistory.xml")
```

- [ ] **Step 6: Run the source-contract tests and confirm they fail for missing split files**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/equip_inspect_source_contract_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected:

```text
cannot open !KRT/UI/Logger.xml
```

or:

```text
cannot open !KRT/UI/RaidAttendance.xml
```

Do not continue if the tests pass before implementation.

---

### Task 2: Split Logger XML And Rename XML Globals

**Files:**
- Create: `!KRT/UI/Logger.xml`
- Create: `!KRT/UI/LootHistory.xml`
- Create: `!KRT/UI/RaidAttendance.xml`
- Delete: `!KRT/UI/Logger.xml`
- Modify: `!KRT/UI/Templates/Common.xml`

- [ ] **Step 1: Run this split script from the repo root**

Run:

```powershell
@'
from pathlib import Path

root = Path("!KRT/UI")
logger_path = root / "Logger.xml"
common_path = root / "Templates" / "Common.xml"

logger = logger_path.read_text(encoding="utf-8")
common = common_path.read_text(encoding="utf-8")

header = '<Ui xmlns="http://www.blizzard.com/wow/ui/"\n\txmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\\FrameXML\\UI.xsd">'

def extract_block(text, tag, name):
    start_token = f'<{tag} name="{name}"'
    start = text.find(start_token)
    if start < 0:
        raise SystemExit(f"missing block: {tag} {name}")
    depth = 0
    pos = start
    while True:
        next_open = text.find(f"<{tag}", pos)
        next_close = text.find(f"</{tag}>", pos)
        if next_close < 0:
            raise SystemExit(f"unterminated block: {tag} {name}")
        if next_open >= 0 and next_open < next_close:
            open_end = text.find(">", next_open)
            token = text[next_open:open_end + 1]
            if not token.rstrip().endswith("/>"):
                depth += 1
            pos = open_end + 1
            continue
        depth -= 1
        close_end = next_close + len(f"</{tag}>")
        if depth == 0:
            block = text[start:close_end]
            remainder = text[:start] + text[close_end:]
            return block.strip(), remainder
        pos = close_end

def rename(text):
    replacements = {
        "KRTLoggerFrameTemplate": "KRTLogPanelTemplate",
        "KRTLoggerTableHeader": "KRTLogTableHeaderTemplate",
        "KRTLoggerRaidButton": "KRTLogRaidRowTemplate",
        "KRTLoggerLootButton": "KRTLootHistoryLootRowTemplate",
        "KRTLoggerRaidAttendeeButton": "KRTRaidAttendancePlayerRowTemplate",
        "KRTLoggerInspectItemIconButtonTemplate": "KRTRaidAttendanceInspectItemIconButtonTemplate",
        "KRTLoggerRollTypePickerFrame": "KRTLootHistoryRollTypePickerFrame",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text

def wrap(blocks):
    body = "\n\n".join(blocks)
    return header + "\n\t" + body.replace("\n", "\n\t") + "\n</Ui>\n"

shared_blocks = []
loot_blocks = []
attendance_blocks = []

for tag, name, target in [
    ("Frame", "KRTLoggerFrameTemplate", shared_blocks),
    ("Button", "KRTLoggerTableHeader", shared_blocks),
    ("Button", "KRTLoggerRaidButton", shared_blocks),
    ("Button", "KRTLoggerLootButton", loot_blocks),
    ("Frame", "KRTLootHistory", loot_blocks),
    ("Frame", "KRTExportFrame", loot_blocks),
    ("Frame", "KRTLoggerRollTypePickerFrame", loot_blocks),
    ("Button", "KRTLoggerRaidAttendeeButton", attendance_blocks),
    ("Frame", "KRTRaidAttendance", attendance_blocks),
]:
    block, logger = extract_block(logger, tag, name)
    target.append(rename(block))

inspect_block, common = extract_block(common, "Button", "KRTLoggerInspectItemIconButtonTemplate")
attendance_blocks.insert(0, rename(inspect_block))

(root / "Logger.xml").write_text(wrap(shared_blocks), encoding="utf-8", newline="\n")
(root / "LootHistory.xml").write_text(wrap(loot_blocks), encoding="utf-8", newline="\n")
(root / "RaidAttendance.xml").write_text(wrap(attendance_blocks), encoding="utf-8", newline="\n")
common_path.write_text(common, encoding="utf-8", newline="\n")
logger_path.unlink()
'@ | python -
```

- [ ] **Step 2: Parse the new XML files**

Run:

```powershell
@'
import xml.etree.ElementTree as ET
for path in [
    r"!KRT/UI/Logger.xml",
    r"!KRT/UI/LootHistory.xml",
    r"!KRT/UI/RaidAttendance.xml",
    r"!KRT/UI/Templates/Common.xml",
]:
    ET.parse(path)
    print("OK", path)
'@ | python -
```

Expected:

```text
OK !KRT/UI/Logger.xml
OK !KRT/UI/LootHistory.xml
OK !KRT/UI/RaidAttendance.xml
OK !KRT/UI/Templates/Common.xml
```

- [ ] **Step 3: Confirm `KRTLogger...` XML globals are gone from active UI XML**

Run:

```powershell
rg -n "KRTLogger" !KRT/UI --glob "*.xml"
```

Expected:

```text
```

No output.

---

### Task 3: Update TOC Load Order

**Files:**
- Modify: `!KRT/!KRT.toc`

- [ ] **Step 1: Replace the old mixed XML entry**

Replace this line under `# Layer 6 - Concrete UI frames`:

```toc
UI\Logger.xml
```

with no line.

Insert these lines after `Services\Warnings\Store.lua` and before `Controllers\Logger.lua`:

```toc
UI\Logger.xml
UI\LootHistory.xml
UI\RaidAttendance.xml
```

The target section should read:

```toc
Services\Logger\Store.lua
Services\Logger\Helpers.lua
Services\Logger\View.lua
Services\Logger\Export.lua
Services\Logger\Actions.lua
Services\Spammer\Draft.lua
Services\Warnings\Store.lua
UI\Logger.xml
UI\LootHistory.xml
UI\RaidAttendance.xml
Controllers\Logger.lua
Widgets\Config.lua
Controllers\Warnings.lua
Controllers\Spammer.lua
```

- [ ] **Step 2: Run TOC validation**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
```

Expected:

```text
TOC file checks passed.
```

---

### Task 4: Update Logger Lua References

**Files:**
- Modify: `!KRT/Controllers/Logger.lua`

- [ ] **Step 1: Replace active template and popup globals**

Run:

```powershell
@'
from pathlib import Path
path = Path("!KRT/Controllers/Logger.lua")
text = path.read_text(encoding="utf-8")
replacements = {
    '"KRTLoggerRollTypePickerFrame"': '"KRTLootHistoryRollTypePickerFrame"',
    "_G.KRTLoggerItemMenuFrame": "_G.KRTLootHistoryItemMenuFrame",
    '"KRTLoggerItemMenuFrame"': '"KRTLootHistoryItemMenuFrame"',
    '"KRTLoggerRaidButton"': '"KRTLogRaidRowTemplate"',
    '"KRTLoggerLootButton"': '"KRTLootHistoryLootRowTemplate"',
    '"KRTLoggerRaidAttendeeButton"': '"KRTRaidAttendancePlayerRowTemplate"',
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"missing expected token: {old}")
    text = text.replace(old, new)
path.write_text(text, encoding="utf-8", newline="\n")
'@ | python -
```

- [ ] **Step 2: Confirm active Logger Lua no longer references `KRTLogger...` UI globals**

Run:

```powershell
rg -n "KRTLogger(ItemMenuFrame|RollTypePickerFrame|RaidButton|LootButton|RaidAttendeeButton)" !KRT/Controllers/Logger.lua
```

Expected:

```text
```

No output.

- [ ] **Step 3: Run Logger source-contract test**

Run:

```powershell
lua tests/logger_visual_refresh_spec.lua
```

Expected:

```text
logger visual refresh source contract passed
```

---

### Task 5: Update Luacheck Globals And Remaining Source Contracts

**Files:**
- Modify: `.luacheckrc`
- Modify: `tests/ui_xml_homogenization_source_spec.lua`
- Modify: `tests/equip_inspect_source_contract_spec.lua`
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Update `.luacheckrc` Logger UI globals**

In `.luacheckrc`, replace:

```lua
	"KRTLoggerItemMenuFrame",
	"KRTLoggerRollTypePickerFrame",
	"KRTLoggerRollTypePickerFrameMS",
	"KRTLoggerRollTypePickerFrameOS",
	"KRTLoggerRollTypePickerFrameSR",
	"KRTLoggerRollTypePickerFrameFree",
	"KRTLoggerRollTypePickerFrameBank",
	"KRTLoggerRollTypePickerFrameDE",
	"KRTLoggerRollTypePickerFrameHold",
```

with:

```lua
	"KRTLootHistoryItemMenuFrame",
	"KRTLootHistoryRollTypePickerFrame",
	"KRTLootHistoryRollTypePickerFrameMS",
	"KRTLootHistoryRollTypePickerFrameOS",
	"KRTLootHistoryRollTypePickerFrameSR",
	"KRTLootHistoryRollTypePickerFrameFree",
	"KRTLootHistoryRollTypePickerFrameBank",
	"KRTLootHistoryRollTypePickerFrameDE",
	"KRTLootHistoryRollTypePickerFrameHold",
```

Replace:

```lua
	"KRTLoggerFrameTemplate",
	"KRTLoggerTableHeader",
```

with:

```lua
	"KRTLogPanelTemplate",
	"KRTLogTableHeaderTemplate",
```

Replace:

```lua
	"KRTLoggerBossAttendeeButton",
	"KRTLoggerBossButton",
	"KRTLoggerLootButton",
	"KRTLoggerRaidAttendeeButton",
	"KRTLoggerRaidButton",
```

with:

```lua
	"KRTLogRaidRowTemplate",
	"KRTLootHistoryLootRowTemplate",
	"KRTRaidAttendancePlayerRowTemplate",
	"KRTRaidAttendanceInspectItemIconButtonTemplate",
```

Remove stale globals if still present:

```lua
	"KRTLoggerExport",
	"KRTLoggerExportRaids",
	"KRTLoggerExportCsv",
	"KRTLoggerExportCsvScrollFrame",
	"KRTLoggerExportCsvText",
```

- [ ] **Step 2: Run all updated source-contract tests**

Run:

```powershell
lua tests/ui_xml_homogenization_source_spec.lua
lua tests/equip_inspect_source_contract_spec.lua
lua tests/release_stabilization_spec.lua
```

Expected:

```text
ui xml homogenization source contract passed
equip inspect source contract passed
```

For `release_stabilization_spec.lua`, expected output is the existing full pass output for that suite.

- [ ] **Step 3: Audit remaining active `KRTLogger...` references**

Run:

```powershell
rg -n "KRTLogger" !KRT tests .luacheckrc --glob "!Libs/**"
```

Expected:

```text
```

No output.

---

### Task 6: Full Validation And Generated Docs

**Files:**
- Modify: `docs/TREE.md`

- [ ] **Step 1: Parse every addon XML file**

Run:

```powershell
@'
import os
import xml.etree.ElementTree as ET
root = "!KRT"
count = 0
for dirpath, _, files in os.walk(root):
    if "Libs" in os.path.relpath(dirpath, root).split(os.sep):
        continue
    for name in files:
        if name.endswith(".xml"):
            path = os.path.join(dirpath, name)
            ET.parse(path)
            count += 1
print("OK addon XML parsed:", count)
'@ | python -
```

Expected:

```text
OK addon XML parsed: 13
```

- [ ] **Step 2: Run repo checks**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check raid_hardening
py -3 tools/krt.py repo-quality-check --check lua_uniformity
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

```text
TOC file checks passed.
Raid hardening checks passed.
Lua uniformity checks passed.
Lua syntax check passed.
```

- [ ] **Step 3: Refresh tree docs after file add/delete**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

Expected:

```text
Updated docs/TREE.md
```

- [ ] **Step 4: Check whitespace and final diff**

Run:

```powershell
git diff --check
git status --short --branch
git diff --stat
```

Expected:

```text
```

`git diff --check` should produce no errors. `git status --short --branch` should show only the planned files.

---

### Task 7: Parent Review And Commit

**Files:**
- Review all modified files from `git status --short`.

- [ ] **Step 1: Review split boundaries**

Run:

```powershell
rg -n "KRTLogPanelTemplate|KRTLogTableHeaderTemplate|KRTLogRaidRowTemplate|KRTLootHistoryLootRowTemplate|KRTRaidAttendancePlayerRowTemplate|KRTRaidAttendanceInspectItemIconButtonTemplate|KRTLootHistoryRollTypePickerFrame|KRTLootHistoryItemMenuFrame" !KRT tests .luacheckrc
```

Expected:

```text
!KRT/UI/Logger.xml
!KRT/UI/LootHistory.xml
!KRT/UI/RaidAttendance.xml
!KRT/Controllers/Logger.lua
.luacheckrc
tests/logger_visual_refresh_spec.lua
tests/ui_xml_homogenization_source_spec.lua
```

The exact line numbers may differ. The paths above must appear.

- [ ] **Step 2: Review that deleted mixed XML is not loaded**

Run:

```powershell
rg -n "UI\\Logger.xml|!KRT/UI/Logger.xml" !KRT tests .luacheckrc docs/TREE.md
```

Expected:

```text
```

No output for active files. If `docs/TREE.md` still contains `Logger.xml`, rerun `tools/update-tree.ps1`.

- [ ] **Step 3: Commit**

Run:

```powershell
git add -- !KRT/!KRT.toc !KRT/UI/Templates/Common.xml !KRT/UI/Logger.xml !KRT/UI/LootHistory.xml !KRT/UI/RaidAttendance.xml !KRT/UI/Logger.xml !KRT/Controllers/Logger.lua .luacheckrc tests/logger_visual_refresh_spec.lua tests/ui_xml_homogenization_source_spec.lua tests/equip_inspect_source_contract_spec.lua tests/release_stabilization_spec.lua docs/TREE.md
git commit -m "Split Logger UI XML and rename log templates"
```

Expected:

```text
[codex/krt-xml-visual-simplification <sha>] Split Logger UI XML and rename log templates
```

---

## Manual In-Game Smoke

Run in the 3.3.5a client:

```lua
/console scriptErrors 1
/reload
```

Check:

- Loot History opens from minimap/slash.
- Loot History raid list renders and selection highlight works.
- Loot History loot list renders item icons, source column tooltip, and roll type picker.
- Export frame opens and both CSV buttons work.
- Raid Attendance opens from minimap/slash.
- Raid Attendance raid list renders and selection highlight works.
- Raid Attendance player rows render iLvl, primary spec, secondary spec, inspect icons, and inspect status.
- Force Inspect button still works.
- No `FrameXML.log` `!KRT` errors for missing templates, missing inherited nodes, or missing relative frames.

## Self-Review

- Spec coverage:
  - Split `Logger.xml`: Task 2 and Task 3.
  - Rename remaining `KRTLogger...` active UI globals: Task 2, Task 4, Task 5.
  - Preserve behavior and public toggles: Current Constraints and validation tests.
  - Update tests/docs/tooling: Task 1, Task 5, Task 6.
- Placeholder scan:
  - No `TODO`, `TBD`, or unspecified implementation steps remain.
- Type/name consistency:
  - `KRTLogRaidRowTemplate` is shared by both Loot History raids and Raid Attendance raids.
  - `KRTLootHistoryLootRowTemplate` is used only by the Loot History loot list.
  - `KRTRaidAttendancePlayerRowTemplate` is used only by Raid Attendance player rows.
  - `KRTLootHistoryRollTypePickerFrame` and `KRTLootHistoryItemMenuFrame` are Loot History-only popup globals.
