---
name: s-lint
description: >
  Ensure code quality for KRT addon using Luacheck linting and StyLua formatting.
  Covers KRT-specific warnings, naming rules, and pre-commit gates.
  Triggers: lint, format, style, luacheck, stylua, code quality, warnings.
---

# Linting KRT

Code quality and formatting for KRT addon (WotLK 3.3.5a, Lua 5.1).

## MCP Tools (KRT Server)

| Task | MCP Tool |
|------|----------|
| Syntax check | `repo_quality_check(check="lua_syntax")` |
| Full uniformity | `repo_quality_check(check="lua_uniformity")` |

## Capabilities

1. **Luacheck Linting** — Syntax errors, undefined globals, unused variables (Lua 5.1)
2. **StyLua Formatting** — Consistent code style, 4-space indent, Unix line endings
3. **Naming Compliance** — PascalCase public, camelCase private, canonical section headers
4. **Pre-Commit Gate** — All checks chained in `tools/pre-commit.ps1`

## Common Luacheck Warnings

| Code | Meaning | Fix |
|------|---------|-----|
| W111 | Setting undefined global | Add to `.luacheckrc` globals or fix typo |
| W112 | Mutating undefined global | Same as W111 |
| W113 | Accessing undefined global | Check if WoW API exists in 3.3.5a |
| W211 | Unused local variable | Remove or prefix with `_` |
| W212 | Unused argument | Prefix with `_` (e.g., `_event`) |
| W213 | Unused loop variable | Prefix with `_` |
| W311 | Value assigned but never used | Remove assignment or use the value |
| W431 | Shadowing upvalue | Rename the local variable |

## KRT .luacheckrc Configuration

The actual configuration:

```lua
std = "lua51c"               -- Lua 5.1 compat variant
codes = true                 -- Show error codes
ranges = true                -- Show location ranges
quiet = 1                    -- Suppress header
cache = false                -- Disable cache
allow_defined = true         -- Allow globals (WoW APIs)
max_line_length = false      -- No line-length limits
```

**Ignored patterns**:
- `11./SLASH_.*` — Slash command globals
- `11./BINDING_.*` — Keybinding globals
- `111/[A-Z][A-Z0-9_]+` — Global constants
- `113/LE_.*` — Lua enum globals
- `211/L` — Unused localization table
- `231/_.*` — Unused `_`-prefixed vars
- `42.` — Shadowing (allowed except upvalues)

**Global allowlist includes**:
- LibCompat functions: `tInvert`, `Round`, `tIndexOf`, `IsInGroup`, `IsInRaid`
- KRT runtime: `KRT`
- Named XML frames: `KRTConfig`, `KRTMaster`, `KRTLogger`, `KRTLootCounterFrame`, etc.
- SavedVariables: `KRT_Raids`, `KRT_Players`, `KRT_Reserves`, etc.

**When adding new named frames in XML**: update `.luacheckrc` global allowlist in the same change.

## KRT .stylua.toml Configuration

The actual configuration:

```toml
syntax = "Lua51"
column_width = 180
line_endings = "Unix"
indent_type = "Spaces"       # 4 spaces, NOT tabs
indent_width = 4
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
collapse_simple_statement = "Never"
sort_requires = { enabled = false }
space_after_function_names = "Never"
```

## KRT Naming Rules

### Public Functions (PascalCase)

```lua
-- Exported methods on feature modules
function module:Toggle() end
function Store:GetRaid(raidId) end
function View:GetBossModeLabel(boss) end
function Actions:CommitLootEdit(lootNid, changes) end
```

### Private Functions (camelCase)

```lua
-- File-local helpers
local function buildRosterCache() end
local function validatePlayerNid(nid) end
```

### UI Hooks (canonical names)

```lua
-- These exact names are called by UIScaffold
function module.AcquireRefs(frame) end
function module.BindHandlers(frame) end
function module.Localize(frame) end
function module.OnLoadFrame(frame) end
function module.RefreshUI() end
function module.Refresh() end
```

### Section Headers (required in Controllers/Services/Widgets)

```lua
-- ----- Internal state ----- --
-- ----- Private helpers ----- --
-- ----- Public methods ----- --
```

## Quick Reference

### Run All Lint Checks

```powershell
# Via MCP
repo_quality_check(check="lua_uniformity")

# Via shell
py -3 tools/krt.py repo-quality-check --check lua_uniformity

# Direct
luacheck --codes --no-color !KRT tools tests
stylua --check !KRT tools tests
```

### Fix Formatting

```powershell
stylua !KRT tools tests
```

### Pre-Commit Gate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/pre-commit.ps1
```

Gate order:
1. TOC files check
2. Layering check
3. UI binding check
4. Lua syntax (if .lua staged)
5. Luacheck full
6. Lua uniformity (naming + headers)
7. API nomenclature (staged additions)
8. StyLua format check
9. Tree update

## Best Practices

1. **Run pre-commit before pushing** — Catches all issues in order
2. **Update .luacheckrc with XML changes** — New frames need global entries
3. **Prefix unused with `_`** — `_event`, `_self`, `_unused`
4. **Use 4 spaces** — Never tabs (StyLua enforces this)
5. **No C_ namespace APIs** — 3.3.5a doesn't have `C_Timer`, `C_Spell`, etc.
6. **Keep section headers** — Required in Controllers/Services/Widgets files
