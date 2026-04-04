---
name: s-debug
description: >
  Diagnose and fix bugs in KRT addon (WoW 3.3.5a / Lua 5.1) using evidence-based
  investigation. Requires runtime evidence before fixes. Covers hypothesis-driven
  debugging, LibLogger instrumentation, Lua errors, taint, and combat lockdown.
  Triggers: error, bug, debug, fix, crash, taint, nil value, diagnose, hypothesis.
---

# Debugging KRT

Systematic debugging and error recovery for KRT addon (WotLK 3.3.5a, Interface 30300).

## MCP Tools (KRT Server)

| Task | MCP Tool |
|------|----------|
| Lua syntax check | `repo_quality_check(check="lua_syntax")` |
| Layering check | `repo_quality_check(check="layering")` |
| Raid hardening | `repo_quality_check(check="raid_hardening")` |

## KRT Logging System

KRT uses **LibLogger-1.0** embedded on the addon table:

```lua
-- Setup (Init.lua)
addon.Debugger = LibStub("LibLogger-1.0")
addon.Debugger:Embed(addon)

-- Usage anywhere
addon:info(Diag.I.LogCoreLoaded:format(version, logLevel, perfMode))
addon:warn(Diag.W.LogRaidUnmappedZone:format(zoneName, difficulty))
addon:debug(Diag.D.LogDebugRaidRoll:format(raidId, name, roll, ok, reason))
addon:error(Diag.E.LogSomeError:format(details))
```

**Log levels**: DEBUG < INFO < WARN < ERROR
**Toggle**: `/krt debug on` enables DEBUG level (runtime-only, not persisted)

### Diagnostic Templates

All log messages use `addon.Diagnose` templates from `Localization/DiagnoseLog.en.lua`:

```lua
local Diag = feature.Diag
Diag.I = {}  -- INFO templates
Diag.W = {}  -- WARN templates
Diag.E = {}  -- ERROR templates
Diag.D = {}  -- DEBUG templates

-- Naming: {Severity}.Log{Module}{Event}
Diag.I.LogCoreLoaded = "[Core] Loaded version=%s logLevel=%s perfMode=%s"
Diag.D.LogDebugRaidRoll = "[Debug] Raid roll raidId=%s name=%s roll=%d ok=%s reason=%s"
```

## Routing Logic

| Error type | Reference |
|------------|-----------|
| Common Lua errors, nil values | [references/error-patterns.md](references/error-patterns.md) |
| Evidence-based methodology | [references/evidence-based-debugging.md](references/evidence-based-debugging.md) |
| Isolation and strategies | [references/debugging-strategies.md](references/debugging-strategies.md) |

## Quick Reference

### Common KRT Error Patterns

- `attempt to index nil value`: Data not loaded yet, or module not initialized. Check load order in `!KRT.toc`.
- `attempt to call nil value (method 'X')`: Method doesn't exist on table. Check `:` vs `.` call convention.
- `Action blocked by Blizzard`: Secure frame modification in combat. Guard with `InCombatLockdown()`.
- Roll/award not working: Check `addon.State` for master looter status and raid detection.

### Systematic Workflow

1. **Gather Evidence**: Ask user to reproduce the error, get the exact Lua error message and stack trace
2. **Check Syntax**: `repo_quality_check(check="lua_syntax")` to rule out parse errors
3. **Hypothesize**: Generate 3-5 hypotheses about root cause
4. **Instrument**: Add `addon:debug()` calls with `Diag.D.*` templates at suspected locations
5. **Ask user to `/reload`** and reproduce, then check debug output
6. **Fix**: Apply minimal fix based on evidence

### Adding Debug Instrumentation

```lua
-- 1. Add template to Localization/DiagnoseLog.en.lua
Diag.D.LogMyFeatureState = "[MyFeature] state=%s value=%s expected=%s"

-- 2. Add logging call at suspected location
addon:debug(Diag.D.LogMyFeatureState:format(
    tostring(state), tostring(value), tostring(expected)))

-- 3. Enable debug: /krt debug on
-- 4. Remove instrumentation after fix confirmed
```

### WoW 3.3.5a API Gotchas

- No `C_Timer`, `C_` namespaces, `C_Spell`, `C_Item` — these are modern API
- Use `LibCompat-1.0` timers: `addon.NewTimer()`, `addon.CancelTimer()`, `addon.After()`
- No `io/os/debug` standard libraries in WoW runtime
- `GetLootSlotLink()` may return nil before loot window is fully loaded
- `UnitName("player")` always works, but `GetRaidRosterInfo(i)` can return nil for empty slots

### SavedVariables Debugging

```powershell
# Validate raid schema
py -3 tools/krt.py repo-quality-check --check raid_hardening

# SV round-trip stability
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-roundtrip.ps1

# Inspect SV structure
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-inspector.ps1
```

### Test Infrastructure

KRT uses **Busted** for regression tests:

```powershell
# Run release stabilization tests (Rolls + Master)
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```

Test file: `tests/release_stabilization_spec.lua`
Covers: `Services/Rolls.lua` and `Controllers/Master.lua`

## Best Practices

1. **Never guess** — Always get the actual error message before proposing fixes
2. **Check load order** — Many nil errors come from wrong file order in `.toc`
3. **Use Diag templates** — Never use raw `print()` for debug output
4. **Guard combat** — Any frame manipulation needs `InCombatLockdown()` check
5. **Run tests after Rolls/Master changes** — `tools/run-release-targeted-tests.ps1`
6. **Check `:` vs `.`** — Most KRT "nil method" errors are call convention mismatches
