# KRT Debugging Strategies

Systematic approaches to KRT addon investigation (WoW 3.3.5a / Lua 5.1).

## The Scientific Method

1. **Observe**: What exactly is happening? Get the error message and stack trace.
2. **Hypothesize**: Why might this happen? (3-5 hypotheses)
3. **Test**: Can user reproduce? Add instrumentation to narrow down.
4. **Conclude**: Root cause identified from log evidence.
5. **Fix**: Apply minimal change, verify with `/reload`.

## Information Gathering

### Check Syntax First

```powershell
py -3 tools/krt.py repo-quality-check --check lua_syntax
```

### Check Architecture

```powershell
py -3 tools/krt.py repo-quality-check --check layering
```

### In-Game Debug Mode

```
/krt debug on       -- Enable DEBUG log level
/krt debug off      -- Back to INFO level
/krt                -- Open main UI
/krt counter        -- Toggle loot counter
```

### Stack Trace Reading

```
1x [ADDON]!KRT\Services\Rolls\Service.lua:123: attempt to index nil value
[string "@!KRT\Services\Rolls\Service.lua"]:123: in function 'SubmitRoll'
[string "@!KRT\Controllers\Master.lua"]:45: in function 'HandleRoll'
```

Read bottom-up: HandleRoll called SubmitRoll which crashed at line 123.

## Isolation Techniques

### Binary Search via TOC

1. Comment out half the files in `!KRT.toc` (keep Init.lua and dependencies)
2. Bug still occurs?
   - Yes: Bug in remaining files
   - No: Bug in removed files
3. Repeat until isolated

### Check Load Order

Compare `!KRT.toc` against AGENTS.md section 4. Wrong order causes nil errors.

### Disable Other Addons

```
/console scriptErrors 1
```

Disable all addons except KRT. If error goes away, another addon interferes.

## KRT Debug Instrumentation

### Adding Debug Logs

```lua
-- Step 1: Add template to Localization/DiagnoseLog.en.lua
Diag.D.LogMyCheck = "[Debug] feature=%s state=%s value=%s"

-- Step 2: Use in code
addon:debug(Diag.D.LogMyCheck:format(
    tostring(featureName), tostring(state), tostring(value)))
```

### Checking State at Runtime

```lua
-- Add temporary check (remove after debugging)
addon:debug(("Master state: isMl=%s raidId=%s"):format(
    tostring(addon.State.isMasterLooter),
    tostring(addon.State.currentRaidId)))
```

## SavedVariables Debugging

```powershell
# Validate raid schema integrity
py -3 tools/krt.py repo-quality-check --check raid_hardening

# SV round-trip stability check
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-roundtrip.ps1

# Inspect SV structure
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-inspector.ps1

# Validate raid schema definitions
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-raid-validator.ps1
```

## Regression Tests

Run after changing `Services/Rolls/Service.lua` or `Controllers/Master.lua`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```

Uses **Busted** test framework. Test file: `tests/release_stabilization_spec.lua`.

## Performance Debugging

```lua
-- WoW 3.3.5a profiling
local start = debugprofilestop()
ExpensiveFunction()
addon:debug(("Took %.2f ms"):format(debugprofilestop() - start))
```

## Event Debugging

```lua
-- Temporary event sniffer (remove after debugging)
local spy = CreateFrame("Frame")
spy:RegisterAllEvents()
spy:SetScript("OnEvent", function(self, event, ...)
    addon:debug(("Event: %s args=%s"):format(event, strjoin(", ", tostringall(...))))
end)
```
lua.results()
```

## Common Investigation Paths

| Symptom | Investigate |
|---------|-------------|
| Nothing loads | .toc, Interface version, syntax |
| Nil error | API return, missing check |
| Works sometimes | Race condition, timing |
| Blocked action | Combat lockdown, taint |
| Wrong data | Event args changed, API changed |
