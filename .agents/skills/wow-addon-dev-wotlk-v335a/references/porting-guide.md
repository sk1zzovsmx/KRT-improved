# Porting Guide - to WotLK 3.3.5a (Interface 30300)

This document covers two porting directions:

1. **Modern (Cataclysm/MoP/WoD/Legion+/Retail) -> 3.3.5** - the harder direction. Modern code uses APIs that don't exist in 3.3.5; you need replacements or capability guards.
2. **Vanilla 1.12 -> 3.3.5** - the easier direction. Most Vanilla idioms still work; the Lua version went 5.0 -> 5.1, the Interface went 11200 -> 30300, and a large CLEU/Aura/Talent API surface was added.

Always run `scripts/lint_lua51.py` and `scripts/scan_xpcall.py` before shipping a port.

---

## Table of contents

1. [Modern -> 3.3.5: Missing APIs and replacements](#modern--335-missing-apis-and-replacements)
2. [Modern -> 3.3.5: Snippets for the common cases](#modern--335-snippets-for-the-common-cases)
3. [Modern -> 3.3.5: TOC directives that don't exist](#modern--335-toc-directives-that-dont-exist)
4. [Vanilla 1.12 -> 3.3.5: What changed in your favor](#vanilla-112--335-what-changed-in-your-favor)
5. [Vanilla 1.12 -> 3.3.5: What still needs rewriting](#vanilla-112--335-what-still-needs-rewriting)
6. [When to use the awesome_wotlk DLL](#when-to-use-the-awesome_wotlk-dll)

---

## Modern -> 3.3.5: Missing APIs and replacements

The 3.3.5 client predates the entire `C_*` namespace reorganization that started in Cataclysm. Most of what looks like "modern API" needs replacement.

| Modern API (introduced) | 3.3.5 replacement |
|---|---|
| `C_Timer.After(delay, fn)` (Legion) | `CreateFrame("Frame")` + one-shot `OnUpdate` (snippet below) |
| `C_Timer.NewTicker(int, fn)` (Legion) | persistent `OnUpdate` with elapsed accumulator |
| `C_Timer.NewTimer(int, fn)` (Legion) | same as `NewTicker` plus a cancel flag |
| `C_AddOns.GetAddOnMetadata` (Dragonflight) | `GetAddOnMetadata` (no `C_` prefix; same args) |
| `C_AddOns.LoadAddOn` (DF) | `LoadAddOn` |
| `C_AddOns.GetNumAddOns` (DF) | `GetNumAddOns` |
| `C_NamePlate.GetNamePlateForUnit` (Legion) | not available; **use `awesome_wotlk` DLL** |
| `C_NamePlate.GetNamePlates` (Legion) | not available; **use `awesome_wotlk` DLL** |
| `Settings.RegisterCanvasLayoutCategory` (DF) | `InterfaceOptions_AddCategory(panel)` |
| `Settings.RegisterAddOnCategory` (DF) | `InterfaceOptions_AddCategory(panel)` |
| `Settings.RegisterVerticalLayoutCategory` (DF) | manual `CreateFrame` + `InterfaceOptions_AddCategory` |
| `MenuUtil` / `Menu` / `CreateAnchor` (DF) | `UIDropDownMenu` + `UIDropDownMenu_AddButton` |
| `texture:SetAtlas("name")` (Legion) | not available; guard with `if texture.SetAtlas then ... end` |
| `texture:SetColorTexture(r,g,b,a)` (Legion) | `texture:SetTexture(r, g, b, a)` |
| `frame:SetMask("path")` (Legion) | not available; capability guard |
| `frame:GetPortrait()` | not available; access `frame.portrait` directly |
| `slider:SetObeyStepOnDrag(b)` (MoP) | not available; guard with capability check |
| `WOW_PROJECT_ID`, `WOW_PROJECT_MAINLINE` (BfA) | not defined; nil-guard before comparing |
| `LE_EXPANSION_DRAGONFLIGHT` etc. (DF) | not defined; nil-guard |
| `LE_EXPANSION_LEVEL_CURRENT` (Legion) | not defined; nil-guard |
| `SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT` (DF) | may not exist; use `or 0` |
| `CreateFromMixins` (Legion) | not available; rewrite as plain table assignment |
| `EventRegistry` (BfA+) | not available; manual callback tables |
| `SetPortraitToTexture` is fine | works on 3.3.5 |
| `GameTooltip:SetUnit(unit, hideStatus)` second arg (BfA) | second arg ignored on 3.3.5 |

For combat-log events, 3.3.5 already has the full `COMBAT_LOG_EVENT_UNFILTERED` system introduced in WotLK proper. The CLEU subevent set is smaller than retail (no Legion+ subevents like `SPELL_EMPOWER_*`, no `RANGE_*` precision flags) but contains the core 60-odd subevents.

---

## Modern -> 3.3.5: Snippets for the common cases

### `C_Timer.After` replacement

```lua
-- Modern: C_Timer.After(2, function() print("delayed") end)

-- 3.3.5 equivalent
local function After(delay, fn)
    local f = CreateFrame("Frame")
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

After(2, function() print("delayed") end)
```

### `C_Timer.NewTicker` replacement

```lua
-- Modern: local t = C_Timer.NewTicker(1, function() print("tick") end)
-- Modern: t:Cancel()

-- 3.3.5 equivalent
local function NewTicker(interval, fn)
    local f = CreateFrame("Frame")
    local elapsed = 0
    local cancelled = false
    f:SetScript("OnUpdate", function(self, dt)
        if cancelled then
            self:SetScript("OnUpdate", nil)
            return
        end
        elapsed = elapsed + dt
        if elapsed >= interval then
            elapsed = 0
            fn()
        end
    end)
    return { Cancel = function() cancelled = true end }
end
```

### Settings panel pattern

```lua
local panel = CreateFrame("Frame", "MyAddonOptionsPanel", UIParent)
panel.name = GetAddOnMetadata("MyAddon", "Title")  -- shown in tree

-- ... add widgets to panel ...

InterfaceOptions_AddCategory(panel)

-- To open the panel programmatically (yes, you must call it twice - Blizzard
-- bug, the first call selects the wrong tab):
InterfaceOptionsFrame_OpenToCategory(panel)
InterfaceOptionsFrame_OpenToCategory(panel)
```

### UIDropDownMenu pattern (right-click context menus)

```lua
local dropdown = CreateFrame("Frame", "MyAddonContextMenu", UIParent, "UIDropDownMenuTemplate")

local function init(self, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Action 1"
    info.func = function() print("clicked 1") end
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Action 2"
    info.func = function() print("clicked 2") end
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
end

UIDropDownMenu_Initialize(dropdown, init, "MENU")

-- Show at cursor on right-click
ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0)
```

### Capability-guarded modern-API calls

If you want a single codebase to work on both 3.3.5 and Retail, guard modern calls:

```lua
if texture.SetAtlas then
    texture:SetAtlas("UI-HUD-MicroMenu-Achievements-Up")
else
    texture:SetTexture("Interface\\Icons\\Achievement_General")
end
```

### Replacing variadic `xpcall` (the Ace3 break)

See `references/lua-51-compatibility.md` section "The xpcall trap" for full explanation. Short version:

```lua
-- BROKEN on 3.3.5
local ok, result = xpcall(handler, geterrorhandler(), event, ...)

-- CORRECT
local ok, result = pcall(handler, event, ...)
if not ok then geterrorhandler()(result) end
```

---

## Modern -> 3.3.5: TOC directives that don't exist

Strip these from TOC files when porting; they cause the addon to silently fail to load on 3.3.5:

- `## AllowLoadGameType:` and the `[AllowLoadGameType xxx]` conditional - not parsed; addon just doesn't load
- `## DefaultState:` - not honored
- `## SecureHandlerVersion:` - not parsed
- `## LoadManagers:` - not honored on 3.3.5
- `## RequiredDeps:` (modern syntax) - use `## Dependencies:` (comma-separated, no version specifiers)
- Anything starting with `## X-Curse-` or `## X-Wago-` - harmless but noise; strip for cleanliness

What 3.3.5 DOES support (full list):

```
## Interface: 30300            (required, always 30300)
## Title: Addon Title          (required, supports |c color codes)
## Notes: Description          (optional, supports |c color codes)
## Author: Name                (optional)
## Version: 1.0.0              (optional)
## SavedVariables: VarName     (account-wide saved variables, comma-separated)
## SavedVariablesPerCharacter: VarName   (per-character)
## OptionalDeps: AddonA, AddonB           (load-after if present, no error if missing)
## Dependencies: AddonA, AddonB           (required; addon refuses to load without them)
## LoadOnDemand: 1              (don't auto-load; load via LoadAddOn())
## LoadWith: OtherAddon         (load when OtherAddon loads, only with LoadOnDemand: 1)
```

---

## Vanilla 1.12 -> 3.3.5: What changed in your favor

Going from 1.12 to 3.3.5 is mostly an *upgrade*. These APIs are available on 3.3.5 but not on 1.12 - you can throw away a lot of 1.12 workarounds.

| What you had to fake on 1.12 | Native API on 3.3.5 |
|---|---|
| Combat-log parsing via `CHAT_MSG_COMBAT_*` events + regex | `COMBAT_LOG_EVENT_UNFILTERED` - proper structured event with timestamp, GUID, subevent, source/dest unit + flags, spell ID + name + school, amount + crit + glancing + crushing |
| Buff/debuff scanning via `UnitBuff(unit, i)` returning only texture | `UnitBuff(unit, i)` returns `name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId` |
| No focus target | `/focus` and `focus`/`focustarget` unit IDs |
| No talent inspection | `NotifyInspect(unit)` + `INSPECT_READY` event + `GetTalentTabInfo(tabIndex, true, false, ...)` |
| Manual frame fading | Built-in `UIFrameFadeIn` / `UIFrameFadeOut` |
| Manual scrolling | `FauxScrollFrame_Update` and `ScrollFrameTemplate` |
| `arg1`, `arg2` in event handlers as implicit globals | `function(self, event, ...)` explicit signature |
| `this` for current frame | `self` parameter |
| `table.getn(t)` / `getn(t)` | `#t` |
| `string.gfind(s, pat)` | `string.gmatch(s, pat)` |
| `for k, v in pairs(t)` was OK; `for k, v in t do` was not | both `pairs` and `ipairs` work the same way |
| No `NotifyInspect` rate-limit handling | Same on 3.3.5 - still need to throttle to 1 inspect per 1.5s |

### CombatLog migration is the big win

If your Vanilla addon parses combat via `CHAT_MSG_COMBAT_HOSTILE_DEATH`, `CHAT_MSG_SPELL_PERIODIC_*`, etc. - throw all of that out and migrate to:

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(self, event, timestamp, subevent,
        sourceGUID, sourceName, sourceFlags,
        destGUID, destName, destFlags,
        spellID, spellName, spellSchool, ...)
    -- subevent is one of SWING_DAMAGE, SPELL_DAMAGE, SPELL_PERIODIC_DAMAGE,
    -- SPELL_HEAL, SPELL_AURA_APPLIED, SPELL_AURA_REMOVED, etc.
    -- Trailing ... varies by subevent - see Wowpedia COMBAT_LOG_EVENT for the table.
end)
```

This is the single biggest reason Cursive, BadBoy, Recount-style addons are dramatically simpler on 3.3.5 than on 1.12.

### Aura tracking is much better

```lua
-- Vanilla 1.12: scan textures, hope for the best, can't tell duration
for i = 1, 16 do
    local texture = UnitBuff("target", i)
    if texture and texture:find("Corruption") then
        -- got it, but no idea how much time is left
    end
end

-- 3.3.5: full data on every aura
for i = 1, 40 do
    local name, _, icon, count, debuffType, duration, expirationTime,
          unitCaster, _, _, spellId = UnitDebuff("target", i)
    if not name then break end
    if spellId == 11671 then  -- Corruption (Rank 4)
        local remaining = expirationTime - GetTime()
        -- ...
    end
end
```

For Affliction Warlock DoT tracking specifically, this changes the design space completely - you can build per-target timer bars with sub-second precision instead of texture-presence guessing.

---

## Vanilla 1.12 -> 3.3.5: What still needs rewriting

| 1.12 idiom | 3.3.5 equivalent |
|---|---|
| `function f(...)` with implicit `arg` table | `function f(...)` with explicit `select("#", ...)` and `select(i, ...)` |
| Implicit `event`, `arg1`, `arg2`, `this` in OnEvent | Explicit `function(self, event, ...)` |
| `string.gfind(s, pat)` | `string.gmatch(s, pat)` |
| `pcall` returning only the result | `pcall` returns `(ok, ...)` (same on both, but error formatting differs) |
| TOC `## Interface: 11200` | `## Interface: 30300` |
| `<Scripts>` tags with bare globals (`event`, `arg1`) | `<OnEvent>self, event, ...</OnEvent>` |
| `SecureHandlerWrapScript` did not exist | Available - use it for combat-aware action bars |
| Action bar slot 1-72 only | 1-120 (multi-spec bars) |

---

## When to use the awesome_wotlk DLL

`FrostAtom/awesome_wotlk` is a Detours-based DLL that injects retail-style APIs into the 3.3.5 client. Install it when you need:

| Feature | API added |
|---|---|
| Iterate visible nameplates | `C_NamePlate.GetNamePlates()` |
| Get the nameplate frame for a unit | `C_NamePlate.GetNamePlateForUnit(unit)` |
| Nameplate lifecycle events | `NAME_PLATE_CREATED`, `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED` |
| Detect controlled/disarmed/silenced state | `UnitIsControlled(unit)`, `UnitIsDisarmed(unit)`, `UnitIsSilenced(unit)` |
| Read transmog from inventory | `GetInventoryItemTransmog(unit, slot)` |
| Window-focus management | `IsWindowFocused()`, `FocusWindow()`, `FlashWindow()` |
| Clipboard access | `CopyToClipboard(text)` |
| Configurable nameplate distance | CVar `nameplateDistance` |
| Configurable camera FOV | CVar `cameraFov` |

**Tradeoff:** users must install a DLL, which violates many private servers' ToS for "client modification" even if cosmetic. Document this clearly. For Project Epoch specifically, see `references/server-specific/project-epoch.md` for current policy.

If your addon depends on `awesome_wotlk`, fail gracefully when the APIs aren't present:

```lua
if C_NamePlate and C_NamePlate.GetNamePlates then
    -- use the modern API
else
    -- fallback: scan frames for WorldFrame children with SetUnit()
    -- or warn the user that awesome_wotlk is required
end
```
