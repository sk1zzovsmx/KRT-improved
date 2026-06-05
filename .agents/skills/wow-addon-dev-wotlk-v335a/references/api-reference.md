# API Reference - WoW 3.3.5a (Interface 30300)

This is a quick reference for the most frequently used 3.3.5a APIs. It is **not** exhaustive - the full surface is ~1500 functions and ~400 events. For comprehensive lookup:

- **Best**: install the **MilkyWay Codex MCP server** (see `external-tools.md`); it gives token-efficient queries against the full API
- **Authoritative**: clone `wowgaming/3.3.5-interface-files` locally and grep - Blizzard's own FrameXML is the ground truth
- **Browsable**: wowpedia.fandom.com - but always verify against the FrameXML mirror because wowpedia includes Retail-only APIs without flagging them

This doc covers what an addon dev reaches for daily.

---

## Table of contents

1. [TOC file format](#toc-file-format)
2. [Frame creation and templates](#frame-creation-and-templates)
3. [Event registration](#event-registration)
4. [Unit information](#unit-information)
5. [Auras (buffs/debuffs)](#auras-buffsdebuffs)
6. [Combat log (CLEU)](#combat-log-cleu)
7. [Spells and casting](#spells-and-casting)
8. [Items and inventory](#items-and-inventory)
9. [Chat and messages](#chat-and-messages)
10. [Saved variables](#saved-variables)
11. [Slash commands](#slash-commands)
12. [Tooltips](#tooltips)

---

## TOC file format

Required structure for an addon to load on 3.3.5. See `assets/MinimalAddon/MinimalAddon.toc` for a working template.

```
## Interface: 30300
## Title: My Addon
## Notes: Description
## Author: YourName
## Version: 1.0.0
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
## Dependencies: SomeOtherAddon
## OptionalDeps: AceAddon-3.0, AceEvent-3.0
## LoadOnDemand: 0

# Files load top-to-bottom in declaration order
embeds.xml
locales\enUS.lua
core.lua
ui.lua
```

`#` lines are comments. Files load in declaration order (matters for global definition order). `\` is the canonical path separator in TOC; `/` works on Windows but breaks on Mac/Linux clients.

Color codes work in `## Title:` and `## Notes:`:
```
## Title: |cff1784d1MyAddon|r
```

---

## Frame creation and templates

```lua
-- Basic frame
local f = CreateFrame("Frame", "MyAddonFrame", UIParent)
f:SetWidth(200)
f:SetHeight(100)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

-- Backdrop (3.3.5 inline; in Retail you need BackdropTemplateMixin)
f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
f:SetBackdropColor(0, 0, 0, 0.8)

-- Common templates
CreateFrame("Button", "B", parent, "UIPanelButtonTemplate")
CreateFrame("Button", "C", parent, "OptionsCheckButtonTemplate")
CreateFrame("Slider", "S", parent, "OptionsSliderTemplate")
CreateFrame("ScrollFrame", "SF", parent, "UIPanelScrollFrameTemplate")
CreateFrame("Frame", "T", parent, "TooltipBorderedFrameTemplate")
CreateFrame("EditBox", "E", parent, "InputBoxTemplate")
```

Frame strata (back-to-front): `BACKGROUND`, `LOW`, `MEDIUM`, `HIGH`, `DIALOG`, `FULLSCREEN`, `FULLSCREEN_DIALOG`, `TOOLTIP`. Default `MEDIUM`.

---

## Event registration

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- ...
    elseif event == "UNIT_AURA" then
        local unit = ...
        -- ...
    end
end)

-- Unregister specific or all
f:UnregisterEvent("PLAYER_LOGIN")
f:UnregisterAllEvents()
```

High-frequency events you'll use constantly:

| Event | Args (after self, event) |
|---|---|
| `PLAYER_LOGIN` | none - fires once after addons load |
| `PLAYER_ENTERING_WORLD` | none - fires on login + every zone change to a new instance/world |
| `ADDON_LOADED` | `addonName` - fires once per addon |
| `VARIABLES_LOADED` | none - SavedVariables now usable |
| `UNIT_AURA` | `unit` |
| `UNIT_HEALTH` | `unit` |
| `UNIT_SPELLCAST_START` | `unit, spellName, rank, lineId, spellId` |
| `COMBAT_LOG_EVENT_UNFILTERED` | see CLEU section |
| `BAG_UPDATE` | `bagID` (0..4 + bank) - fires in floods, debounce |
| `PLAYER_TARGET_CHANGED` | none |
| `PLAYER_FOCUS_CHANGED` | none |
| `QUEST_LOG_UPDATE` | none - fires on most quest state changes |

Wowpedia's "Events_A-M" / "Events_N-Z" lists all ~400 events for 3.3.5.

---

## Unit information

Unit IDs: `player`, `target`, `focus`, `pet`, `mouseover`, `party1..4`, `raid1..40`, `partypet1..4`, `raidpet1..40`, plus `targettarget`, `focustarget`, etc.

```lua
local name, realm = UnitName("target")
local class, classFile = UnitClass("target")          -- "Warrior", "WARRIOR"
local hp, maxhp = UnitHealth("target"), UnitHealthMax("target")
local power = UnitPower("target")                     -- mana/rage/energy
local powerType = UnitPowerType("target")             -- 0=mana, 1=rage, 2=focus, 3=energy, 6=runic
local level = UnitLevel("target")
local exists = UnitExists("target")
local isPlayer = UnitIsPlayer("target")
local isFriend = UnitIsFriend("player", "target")
local guid = UnitGUID("target")                       -- "0x" + 16 hex chars
local x, y = GetPlayerMapPosition("player")
```

---

## Auras (buffs/debuffs)

```lua
-- Iterate buffs/debuffs on a unit
for i = 1, 40 do
    local name, rank, icon, count, dispelType, duration, expirationTime,
          unitCaster, isStealable, shouldConsolidate, spellID = UnitBuff("target", i)
    if not name then break end
    -- ...
end

-- Same signature for UnitDebuff
-- Use UnitAura(unit, i, "HELPFUL"|"HARMFUL"|"PLAYER"|...) for filtered iteration

-- Time remaining
local remaining = expirationTime - GetTime()  -- seconds
```

`expirationTime` is in `GetTime()`-relative seconds. `duration == 0` means "permanent" (e.g. zone-wide buffs). `unitCaster` is the unit ID of the caster if visible (often nil for raid debuffs).

---

## Combat log (CLEU)

The structured combat log was introduced in WotLK and is fully available on 3.3.5.

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(self, event,
        timestamp, subevent, sourceGUID, sourceName, sourceFlags,
        destGUID, destName, destFlags, ...)
    -- The trailing ... varies per subevent. Common subevents:
    if subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
        local spellID, spellName, spellSchool,
              amount, overkill, school, resisted, blocked, absorbed,
              critical, glancing, crushing = ...
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local spellID, spellName, spellSchool,
              amount, overhealing, absorbed, critical = ...
    elseif subevent == "SPELL_AURA_APPLIED" then
        local spellID, spellName, spellSchool,
              auraType = ...   -- "BUFF" or "DEBUFF"
    end
end)
```

Full subevent argument layout: search `wowgaming/3.3.5-interface-files/Blizzard_CombatLog/` or wowpedia "COMBAT_LOG_EVENT".

Source/dest flags (`COMBATLOG_OBJECT_*` constants) encode reaction, controller type, etc. - bitmask via `bit.band`.

---

## Spells and casting

```lua
local name, rank, icon, castTime, minRange, maxRange = GetSpellInfo(spellID)
local start, duration, enabled = GetSpellCooldown(spellID)
local cost = GetSpellPowerCost(spellID)   -- only on retail; on 3.3.5 use UnitPowerType + tooltip parse

-- Trigger a cast (insecure - works in macros / hardware-event functions only)
CastSpellByName("Frostbolt")
CastSpellByID(spellID)                     -- 3.3.5 supports this
UseInventoryItem(slotID)

-- Spellbook iteration
local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
for i = offset + 1, offset + numSpells do
    local name = GetSpellName(i, BOOKTYPE_SPELL)
    -- ...
end
```

Many cast functions are *protected* - they only work when called from a hardware event (mouse click, key press) or a secure macro. Call them from a non-hardware OnUpdate and they silently no-op.

---

## Items and inventory

```lua
-- Item info
local name, link, quality, ilvl, reqLevel, type, subType, stackCount,
      equipLoc, texture, sellPrice = GetItemInfo(itemID or itemLink or itemName)

-- Tooltip-based lookup (slower but works for unknown items)
GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
GameTooltip:SetHyperlink(itemLink)
-- ... read GameTooltipTextLeft1, GameTooltipTextLeft2, etc.
GameTooltip:Hide()

-- Bag iteration
for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
        local icon, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
        if link then
            -- ...
        end
    end
end

-- Equipped items
local link = GetInventoryItemLink("player", slotID)   -- INVSLOT_HEAD = 1, etc.
local id = GetInventoryItemID("player", slotID)
```

---

## Chat and messages

```lua
DEFAULT_CHAT_FRAME:AddMessage("Hello", 1, 1, 0)   -- yellow

print("hello")   -- Blizzard's print, goes to ChatFrame1 (NOT standard Lua print)

SendChatMessage("hi", "PARTY")            -- channels: SAY, YELL, PARTY, RAID, GUILD, OFFICER, WHISPER, EMOTE
SendChatMessage("hi", "WHISPER", nil, "PlayerName-RealmName")
SendAddonMessage("MyAddonPrefix", "data", "PARTY")  -- inter-addon comms
```

Color codes: `|cAARRGGBB...|r`. Item links: `|Hitem:itemID:...|h[Item Name]|h`.

---

## Saved variables

Declare in TOC:
```
## SavedVariables: MyAddonDB                    -- account-wide
## SavedVariablesPerCharacter: MyAddonCharDB    -- per character
```

```lua
-- These are loaded BEFORE PLAYER_LOGIN fires
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addon)
    if addon == "MyAddon" then
        -- Initialize defaults if first run
        if not MyAddonDB then
            MyAddonDB = { setting = "default" }
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
```

Saved variables are written to disk only on `/reload`, logout, or game exit. Crashes lose unsaved state. Tell users to type `/reload` after changing settings if you can't programmatically force a save.

Format on disk: `WTF/Account/<account>/SavedVariables/MyAddon.lua` (account-wide) and `WTF/Account/<account>/<realm>/<char>/SavedVariables/MyAddon.lua` (per-character).

---

## Slash commands

```lua
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"
SlashCmdList["MYADDON"] = function(msg, editbox)
    if msg == "config" then
        -- ...
    end
end
```

The trailing number on `SLASH_MYADDON1`, `SLASH_MYADDON2` enables aliases. The dispatch key (`"MYADDON"`) is uppercase by convention and must match between the SLASH constants and the SlashCmdList key.

---

## Tooltips

```lua
-- Show a tooltip
GameTooltip:SetOwner(parentFrame, "ANCHOR_RIGHT")
GameTooltip:SetText("Title", 1, 1, 1)
GameTooltip:AddLine("Subtitle", 0.7, 0.7, 0.7, true)
GameTooltip:AddDoubleLine("Left", "Right", 1, 1, 1, 0, 1, 0)
GameTooltip:Show()

-- Show item / spell info
GameTooltip:SetHyperlink(itemLink)
GameTooltip:SetSpellByID(spellID)
GameTooltip:SetUnit("target")

-- Hide on leave
button:SetScript("OnLeave", function() GameTooltip:Hide() end)
```

**Critical caveat**: `GameTooltip` is a single shared global. Any addon (pfQuest, Leatrix, etc.) calling `GameTooltip:SetOwner()` mid-frame steals ownership from yours. Always call `SetOwner` explicitly before `Set*` calls in a tooltip handler - never assume the tooltip is "still yours" from one frame to the next. See `references/frame-xml-cookbook.md` section Tooltip ownership for the fix patterns used by EpochFixes and similar.
