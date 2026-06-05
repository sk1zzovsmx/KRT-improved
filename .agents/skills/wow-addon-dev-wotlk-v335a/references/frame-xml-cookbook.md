# FrameXML Cookbook - WoW 3.3.5a UI Patterns

This doc covers the UI/frame patterns that come up repeatedly in 3.3.5 addon development and that are easy to get wrong. The ground truth for "how does Blizzard do it" is `wowgaming/3.3.5-interface-files` - clone it locally and grep before guessing.

## Table of contents

1. [Tooltip ownership - the GameTooltip steal problem](#tooltip-ownership--the-gametooltip-steal-problem)
2. [Taint avoidance - secure vs insecure code paths](#taint-avoidance--secure-vs-insecure-code-paths)
3. [Hooking Blizzard functions safely](#hooking-blizzard-functions-safely)
4. [SecureHandlers and combat-safe action bars](#securehandlers-and-combat-safe-action-bars)
5. [Frame strata, levels, and z-order debugging](#frame-strata-levels-and-z-order-debugging)
6. [OnUpdate throttling patterns](#onupdate-throttling-patterns)
7. [Event flood debouncing (BAG_UPDATE, UNIT_AURA)](#event-flood-debouncing-bag_update-unit_aura)
8. [Common templates reference](#common-templates-reference)

---

## Tooltip ownership - the GameTooltip steal problem

`GameTooltip` is a single shared global. Any addon can call `GameTooltip:SetOwner(otherFrame, "ANCHOR_RIGHT")` mid-frame and your tooltip handler now points at the wrong frame. Common offenders: pfQuest's scanner OnUpdate, Leatrix Plus, anything that calls `SetHyperlink` on hover.

**Symptoms:** tooltips show up on the wrong frame, show stale info from an item you hovered seconds ago, or just disappear.

**Fix:** always set ownership explicitly inside every tooltip handler. Never assume the tooltip is "still yours".

```lua
-- BROKEN: assumes GameTooltip is still pointed at our button
button:SetScript("OnEnter", function(self)
    GameTooltip:SetText("Hello")   -- might appear on someone else's frame!
    GameTooltip:Show()
end)

-- CORRECT: re-anchor every time
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Hello")
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
```

For item/spell/inspect tooltips, also guard against `nil` links:

```lua
-- The EpochFixes pattern: cache item links because they can expire mid-tooltip
local linkCache = {}

frame:RegisterEvent("INSPECT_READY")
frame:SetScript("OnEvent", function(self, event, guid)
    for slot = 1, 19 do
        linkCache[slot] = GetInventoryItemLink("target", slot)
    end
end)

slotButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local link = GetInventoryItemLink("target", self.slot)
                 or linkCache[self.slot]
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText("Item link expired")
    end
    GameTooltip:Show()
end)
```

---

## Taint avoidance - secure vs insecure code paths

WoW's "secure" system prevents addons from automating combat actions (CastSpellByName, UseAction, etc.) outside of hardware events. **Taint** is what happens when insecure (addon) code touches secure (Blizzard) state - that state becomes "tainted" and refuses to perform protected actions until reload.

**Symptoms:** "Action blocked" errors during combat, frames that won't accept clicks during raids, healers that can't cast on raid frames after a wipe.

**Rules:**

1. **Never overwrite Blizzard global functions.** This is the #1 source of taint:
   ```lua
   -- TAINTING: replaces the function reference
   local original = QuestLog_Update
   function QuestLog_Update() original() ; my_logic() end
   ```
   Use `hooksecurefunc` instead (next section).

2. **Never modify Blizzard frames' protected attributes.** Setting `:SetAttribute("type", ...)` or `:SetAttribute("spell", ...)` on Blizzard's UnitFrames during combat is forbidden. You can do it OUT of combat, but the moment combat starts, the frame is frozen.

3. **Watch out for taint-spreading via global functions.** If you call a Blizzard global (e.g. `ToggleCharacter("PaperDollFrame")`) from an addon-tainted code path, the global's results become tainted too. Use `InCombatLockdown()` to guard:
   ```lua
   if InCombatLockdown() then
       print("Can't change action bars in combat")
       return
   end
   ```

4. **`pcall`/`xpcall` taint everything they wrap.** Use them in clearly addon-only code paths, never around Blizzard secure calls.

---

## Hooking Blizzard functions safely

Use `hooksecurefunc(name, postHook)` to run code AFTER a Blizzard function without tainting it. The post-hook runs after the original returns. You CANNOT modify the original's return values this way (use case: observation only).

```lua
hooksecurefunc("QuestLog_Update", function()
    -- runs after Blizzard's QuestLog_Update completes; original's return value is unaffected
    UpdateMyQuestOverlay()
end)

hooksecurefunc(MerchantFrame, "Show", function(self)
    -- can hook frame methods too
    InjectMyMerchantButtons(self)
end)
```

For PRE-hooks where you need to alter inputs or short-circuit, you generally cannot do this safely on protected functions. For unprotected functions, you can do raw replacement at the cost of taking ownership of correctness.

---

## SecureHandlers and combat-safe action bars

If you're building action bars, custom keybinds, or anything that triggers spells, use `SecureActionButtonTemplate`:

```lua
local b = CreateFrame("Button", "MyCastButton", UIParent, "SecureActionButtonTemplate")
b:SetAttribute("type", "spell")
b:SetAttribute("spell", "Frostbolt")
b:SetAttribute("unit", "target")
b:RegisterForClicks("AnyDown", "AnyUp")
```

Setting attributes is allowed OUT of combat. To change a button's spell at runtime DURING combat, you need `SecureHandlerWrapScript` to register a snippet that runs inside the secure environment. That's beyond the scope of this cookbook - read `Blizzard_SecureHandlers/SecureHandlers.lua` in the FrameXML mirror.

---

## Frame strata, levels, and z-order debugging

Strata layers (back-to-front): `BACKGROUND`, `LOW`, `MEDIUM` (default), `HIGH`, `DIALOG`, `FULLSCREEN`, `FULLSCREEN_DIALOG`, `TOOLTIP`.

Within a strata, `frame:SetFrameLevel(n)` controls z-order (higher = in front).

To debug "why is my frame behind X":

```lua
/run print(MyFrame:GetFrameStrata(), MyFrame:GetFrameLevel())
/run print(SomeOtherFrame:GetFrameStrata(), SomeOtherFrame:GetFrameLevel())
```

To bring a frame fully forward:
```lua
MyFrame:SetFrameStrata("HIGH")
MyFrame:SetFrameLevel(MyFrame:GetParent():GetFrameLevel() + 10)
```

---

## OnUpdate throttling patterns

`OnUpdate` fires every frame (60+ times/sec). Doing real work every frame burns CPU. Throttle.

```lua
local THROTTLE = 0.1  -- 10 Hz
local elapsed = 0

frame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < THROTTLE then return end
    elapsed = 0

    -- expensive work here
end)
```

For "do once after a delay then stop":

```lua
local elapsed = 0
frame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= 1.5 then
        self:SetScript("OnUpdate", nil)
        do_the_thing()
    end
end)
```

For "do every N seconds forever, and let me cancel": see `references/porting-guide.md` section "C_Timer.NewTicker replacement".

---

## Event flood debouncing (BAG_UPDATE, UNIT_AURA)

Some events fire dozens of times for a single user action. `BAG_UPDATE` fires once per affected bag on every loot/sell/move. `UNIT_AURA` fires per aura change for every visible unit.

```lua
local pending = false
frame:RegisterEvent("BAG_UPDATE")
frame:SetScript("OnEvent", function(self, event)
    if pending then return end
    pending = true
    -- Coalesce all calls in the next 0.5s into one
    local t = CreateFrame("Frame")
    local elapsed = 0
    t:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            self:SetScript("OnUpdate", nil)
            pending = false
            scan_bags_once()
        end
    end)
end)
```

If you use Ace3, `AceTimer-3.0`'s `ScheduleTimer` + `CancelTimer` does this more cleanly.

---

## Common templates reference

`InterfaceOptionsCheckButtonTemplate`, `OptionsCheckButtonTemplate` - checkboxes
`UIPanelButtonTemplate`, `UIPanelButtonTemplate2` - standard buttons
`OptionsSliderTemplate`, `OptionsSliderTemplateLite` - sliders
`InputBoxTemplate`, `LargeInputBoxTemplate` - text input
`UIDropDownMenuTemplate` - dropdowns (use with `UIDropDownMenu_*` functions)
`UIPanelScrollFrameTemplate`, `FauxScrollFrameTemplate` - scrollable areas
`TooltipBorderedFrameTemplate` - frames with the tooltip border style
`SecureActionButtonTemplate` - combat-safe spell/macro buttons
`SecureUnitButtonTemplate` - combat-safe unit-targeting buttons
`SecureHandlerStateTemplate` - state-driven secure buttons (advanced)

For each: search `wowgaming/3.3.5-interface-files` for the template definition. Most are in `UIPanelTemplates.xml`, `OptionsPanelTemplates.xml`, or `Blizzard_SecureHandlers/`.
