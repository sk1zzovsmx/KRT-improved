# KRT Error Patterns

Common KRT addon errors and fixes (WoW 3.3.5a / Lua 5.1).

## Lua Runtime Errors

### attempt to index nil value

```lua
-- Error: attempt to index nil value (local 'raid')
local raid = Store:GetRaid(selectedRaid)
print(raid.zone) -- raid is nil if selectedRaid is invalid

-- Fix: Guard with nil check
local raid = Store:GetRaid(selectedRaid)
if not raid then return end
print(raid.zone)
```

### attempt to call nil value

```lua
-- Error: attempt to call nil value (method 'Toggle')
module:Toggle() -- method doesn't exist on this table

-- Fix 1: Check : vs . call convention
-- If defined as: function module.Toggle() ... end
-- Call as: module.Toggle() not module:Toggle()

-- Fix 2: Check method exists
if module.Toggle then module:Toggle() end

-- Fix 3: Check load order in !KRT.toc
-- The module file may load after the caller
```

### bad argument #N

```lua
-- Error: bad argument #1 to 'format' (string expected, got nil)
format(L.SomeKey, nil)

-- Fix: Use tostring() for uncertain values
format(L.SomeKey, tostring(value))

-- Or provide fallback
format(L.SomeKey, value or "unknown")
```

### attempt to perform arithmetic on nil

```lua
-- Error: attempt to perform arithmetic on nil value
local remaining = total - count -- count might be nil

-- Fix: Default to 0
local remaining = (total or 0) - (count or 0)
```

## Load Order Errors

### Module not initialized

```lua
-- Error: attempt to index nil value (global 'addon')
-- This happens when a file loads before Init.lua

-- Fix: Check !KRT.toc order matches AGENTS.md section 4
-- Init.lua must load before any module files
```

### Circular dependency

```lua
-- Error: Service X calls Controller Y at load time
-- Services load before Controllers in the TOC

-- Fix: Use Bus event instead of direct call
addon.Bus.RegisterCallback(module, addon.Events.Internal.SomeEvent, handler)
```

## Combat Lockdown Errors

### Action blocked by Blizzard

```lua
-- Error: Action[SetPoint] blocked because of !KRT
frame:SetPoint("CENTER") -- during combat!

-- Fix: Guard with InCombatLockdown()
if InCombatLockdown() then return end
frame:SetPoint("CENTER")
```

## KRT-Specific Patterns

### Raid not detected

```lua
-- GetRaidStore returns nil when no current raid exists
local store = Core.GetRaidStoreOrNil("MyFeature", {"GetRaid"})
if not store then
    addon:debug(Diag.D.LogNoActiveRaid)
    return
end
```

### Master looter check

```lua
-- Master looter status checked via addon.State
if not addon.State.isMasterLooter then
    -- Non-ML clients should not run roll/award flows
    return
end
```

### SavedVariables not loaded

```lua
-- KRT_Raids etc. are nil before ADDON_LOADED fires
-- Never access SV tables at file load time
-- Always access them in event handlers or after Init
```

### Addon not loading

Checklist:
1. `!KRT.toc` filename matches folder name `!KRT` (case-sensitive)
2. `## Interface: 30300` in TOC
3. No Lua syntax errors (`py -3 tools/krt.py repo-quality-check --check lua_syntax`)
4. Dependencies listed in TOC exist under `Libs/`
5. File paths in `.toc` match actual filenames (case-sensitive on Linux)
