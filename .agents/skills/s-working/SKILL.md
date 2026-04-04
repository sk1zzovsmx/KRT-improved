---
name: s-working
description: >
  General-purpose skill for KRT addon development. Covers project architecture,
  module structure, development workflow, coding conventions, and tool reference.
  Use for everyday addon work, exploration, or when unsure which specialized skill to use.
  Triggers: work, build, develop, create, mechanic, addon, krt, module, feature.
---

# Working on KRT

Everyday development guidance for KRT addon (WotLK 3.3.5a, Lua 5.1).

## Quick Reference

| Task | How |
|------|-----|
| Run quality checks | `py -3 tools/krt.py repo-quality-check --check all` |
| Run pre-commit gate | `powershell -NoProfile -File tools/pre-commit.ps1` |
| Run regression tests | `powershell -NoProfile -File tools/run-release-targeted-tests.ps1` |
| Test in-game | `/reload` then `/krt` |
| Toggle debug mode | `/krt debug on` or `/krt debug off` |
| Open loot counter | `/krt counter` |
| MCP status | `dev_stack_status()` |

## Architecture Overview

### Layer Stack

```
EntryPoints/         SlashEvents, Minimap (user entry → module:Toggle)
     ↓
Controllers/         Master, Logger, Warnings, Changes, Spammer (parent owners)
     ↓
Widgets/             LootCounter, ReservesUI, Config (UI controllers)
     ↓
Services/            Raid, Rolls, Loot, Reserves, Chat, Debug (pure logic/data)
     ↓
Core/                DB, DBManager, DBSchema, DBRaidStore, DBRaidQueries
     ↓
Modules/             C, Events, Colors, Strings, Item, Bus, Sort, Time, Comms
     ↓
Init.lua             Bootstrap, shared runtime glue, main event wiring
```

### BINDING Rules

- Services MUST NOT call Controllers or touch Controller frames
- Services MUST NOT reference Widgets (`addon.*UI`)
- Upward communication uses Bus (`Bus.RegisterCallback` / `Bus.TriggerEvent`)
- EntryPoints may call `Controller:Toggle()`

### Module Ownership

| Module | File | Runtime |
|--------|------|---------|
| Raid service | `Services/Raid.lua` | `addon.Raid` |
| Roll tracking | `Services/Rolls.lua` | `addon.Rolls` |
| Loot parsing | `Services/Loot.lua` | `addon.Loot` |
| Reserves service | `Services/Reserves.lua` | `addon.Reserves` |
| Master controller | `Controllers/Master.lua` | `addon.Master` |
| Logger controller | `Controllers/Logger.lua` | `addon.Logger` |
| Logger data | `Services/Logger/*.lua` | `addon.Logger.Store/View/Helpers/Actions` |
| Config widget | `Widgets/Config.lua` | `addon.Config` |
| Loot counter | `Widgets/LootCounter.lua` | `addon.LootCounter` |

## Creating New Code

### New Module Checklist

1. Add file to correct folder (`Controllers/`, `Services/`, `Widgets/`, `Modules/`)
2. Add to `!KRT.toc` in correct load order position (see AGENTS.md section 4)
3. Start file with standard header:
   ```lua
   local addon = select(2, ...)
   local feature = addon.Core.GetFeatureShared()
   ```
4. Use canonical section headers:
   ```lua
   -- ----- Internal state ----- --
   -- ----- Private helpers ----- --
   -- ----- Public methods ----- --
   ```
5. Export on `addon.*`:
   ```lua
   addon.MyModule = module
   ```
6. Update `.luacheckrc` if adding named XML frames

### UI Module Contract (UIScaffold)

For modules with UI, use `UIScaffold.DefineModuleUi(cfg)`:

```lua
addon.UIScaffold.DefineModuleUi({
    module = module,
    frameName = "KRTMyFrame",
    -- Hooks implemented by the module:
    AcquireRefs = function(frame) end,
    BindHandlers = function(frame) end,
    Localize = function(frame) end,
    OnLoadFrame = function(frame) end,
    RefreshUI = function() end,
})
```

Scaffold provides: `BindUI`, `EnsureUI`, `Toggle`, `Show`, `Hide`, `RequestRefresh`, `MarkDirty`.

Module state: `module._ui = { Loaded, Bound, Localized, Dirty, Reason, FrameName }`.

### Bus Events

Use `addon.Bus` for cross-module communication:

```lua
-- Subscribe
addon.Bus.RegisterCallback("myKey", addon.Events.RAID_ROSTER_DELTA, function()
    module:RequestRefresh()
end)

-- Publish
addon.Bus.TriggerEvent(addon.Events.RAID_ROSTER_DELTA)
```

Event names live in `Modules/Events.lua` (`addon.Events`).

## Coding Conventions

### Naming

| Scope | Convention | Example |
|-------|-----------|---------|
| Public module method | PascalCase | `Store:GetRaid(id)` |
| Private helper | camelCase | `local function buildCache()` |
| Constants | UPPER_SNAKE | `addon.C.ROLL_TIMEOUT` |
| Local variable | camelCase | `local raidId = ...` |
| Lua metamethods | unchanged | `__index`, `__call` |

### Call Style

- `:` for methods (expects `self`): `module:Toggle()`, `addon:info(...)`
- `.` for plain functions (no `self`): `addon.NewTimer(...)`, `Utils.getRaid()`

### Strings

- User-facing text: `addon.L` (Localization/localization.en.lua)
- Diagnostic templates: `addon.Diagnose` (Localization/DiagnoseLog.en.lua)
- Use `format(L.Key, a, b)` over concatenation

### Logging (LibLogger-1.0)

```lua
addon:error("Critical failure: %s", msg)   -- Breaks functionality
addon:warn("Unexpected state: %s", state)   -- Abnormal but non-blocking
addon:info("Raid created: %s", raidId)      -- Major lifecycle events
addon:debug("Check: %s=%s", key, value)     -- Detailed flow (not in combat)
```

## Tool Reference

### Quality Check Scripts

| Script | Purpose |
|--------|---------|
| `check-layering.ps1` | Architecture layer violations |
| `check-api-nomenclature.ps1` | PascalCase/camelCase naming |
| `check-lua-syntax.ps1` | Lua 5.1 syntax validation |
| `check-lua-uniformity.ps1` | Section headers, naming |
| `check-toc-files.ps1` | TOC integrity |
| `check-ui-binding.ps1` | No inline XML scripts |
| `check-raid-hardening.ps1` | Raid store guard patterns |

### MCP Tools (KRT Server)

| Tool | Purpose |
|------|---------|
| `dev_stack_status()` | Environment and tool status |
| `repo_quality_check(check=...)` | Run quality checks |
| `skills_manifest()` | List pinned skills |
| `skills_verify()` | Verify skill integrity |

### Cross-Platform Entry Point

```powershell
# All checks
py -3 tools/krt.py repo-quality-check --check all

# Specific check
py -3 tools/krt.py repo-quality-check --check layering

# Release metadata
py -3 tools/krt.py release-metadata
```

## WoW 3.3.5a Reminders

- **No `C_*` APIs** — `C_Timer`, `C_Spell`, `C_Item` do not exist
- **No `io/os/debug`** — Not available in WoW runtime
- **LibCompat-1.0** provides: `tInvert`, `Round`, `tIndexOf`, `IsInGroup`, `IsInRaid`
- **Combat lockdown** — No secure frame changes during combat
- **Frame references** — Use `_G[frameName]` pattern, not `C_` lookups
- **Arrays are 1-indexed** — Standard Lua convention
- **No `#t` on sparse tables** — Use explicit length tracking

