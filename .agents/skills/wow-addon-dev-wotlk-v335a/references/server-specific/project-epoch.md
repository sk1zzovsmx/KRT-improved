# Project Epoch - Server-Specific Notes

[Project Epoch](https://www.project-epoch.net/) is a Classic+ private server built on the WoW 3.3.5a (Interface 30300) client. Vanilla content + TBC-style talent trees + custom items, dungeons, and encounters.

This doc covers behaviors that are specific to Project Epoch and don't apply to other 3.3.5 servers (Warmane, Ascension, Atlantiss, etc.).

## Table of contents

1. [Client distribution and addon path](#client-distribution-and-addon-path)
2. [Server-modified client features](#server-modified-client-features)
3. [Custom seals, items, and content gaps](#custom-seals-items-and-content-gaps)
4. [Known client bugs that addons can patch](#known-client-bugs-that-addons-can-patch)
5. [DLL injection policy](#dll-injection-policy)
6. [Recommended Project Epoch addon ecosystem](#recommended-project-epoch-addon-ecosystem)

---

## Client distribution and addon path

Project Epoch is distributed via the **Ascension Launcher** (Project Epoch runs on Ascension's infrastructure). The launcher downloads a 3.3.5a client into:

```
<launcher install>/Ascension Launcher/resources/epoch_live/
```

Addons go in:

```
<launcher install>/Ascension Launcher/resources/epoch_live/Interface/AddOns/
```

SavedVariables in:

```
<launcher install>/Ascension Launcher/resources/epoch_live/WTF/Account/<account>/SavedVariables/
```

**Critical**: do NOT use the Ascension Launcher's built-in addon manager for Project Epoch - it pulls addons curated for Ascension's other realms (Classless, BronzeBeard) which use different APIs and frequently crash on Epoch. Install addons manually or use a third-party addon manager pointed at the Epoch live folder.

---

## Server-modified client features

Project Epoch ships a **modified client** (Blizzard 3.3.5a binary with custom patches). These changes affect addon behavior:

| Modification | Effect on addons |
|---|---|
| Login & character-creation screens replaced with Vanilla visuals | Cosmetic only |
| Loading screens restored to Classic | Cosmetic only |
| Blood Elf / Draenei references scrubbed from interface | Don't reference these races in addon code; UI strings are gone |
| **Character pane rewritten** for TBC-appropriate stats | **Older UI addons that hook the character pane (`PaperDollFrame`) often break** - test inspect, gear scoring, and stat display addons specifically |
| Hit and Crit tooltip text standardized | Items like Devilsaur Eye and Elixir of the Mongoose now read uniformly; addons that parse these tooltips may need to update regex |
| Spellbook gains a new "Racials" tab | Don't iterate spellbook tabs without bounds-checking - Project Epoch has +1 tab vs vanilla 3.3.5 |

If your addon hooks the character pane, the spellbook, or parses Hit/Crit tooltip strings, regression-test against a current Project Epoch client.

---

## Custom seals, items, and content gaps

Project Epoch adds custom Paladin seals, custom item rewards, custom dungeons (Baradin Hold at level 60, reworked Scarlet Monastery, etc.). Implications for addons:

- **PallyPower-style addons** must be backported to know about Project Epoch's seal IDs. The official backport is `yeagerca/PallyPower-TBC-Backport-for-Epoch`.
- **Quest databases** (pfQuest-wotlk, Questie) need an Epoch overlay - `Bennylavaa/pfQuest-epoch` or the maintained fork in `Defcons/epoch-addons/pfQuest-epoch/` is the standard. The overlay also REMOVES content not on the server (Silithus NPCs, TBC-only quest NPCs, PvP quests not yet implemented):
  ```lua
  pfDB["units"]["data-epoch"][15174] = {}   -- removes NPC
  pfDB["quests"]["data-epoch"][8369] = {}   -- removes quest
  ```
- **Loot tables**: AtlasLoot and similar reference loot from raids that exist on retail WotLK but not on Epoch. Use `Rofos2011/AtlasQuest` (Epoch-specific) or expect mismatches.
- **Item-level squish**: raid gear caps at iLvl 63-67 on Epoch. Don't hardcode iLvl thresholds calibrated against retail-WotLK gear (200+).

---

## Known client bugs that addons can patch

The Defcons addon `EpochFixes` patches four known client bugs. If you ship an addon that touches these areas, replicate the patches or depend on EpochFixes.

### 1. Spellbook crash on hover

`SpellBookFrameTabButton2:GetScript("OnEnter")` can throw on certain spec layouts. Wrap any tab-button OnEnter calls in `pcall()`.

### 2. Quest abandon abandons the wrong quest

`QUEST_LOG_UPDATE` can fire and change `GetQuestLogSelection()` between the user clicking "Abandon" and confirming the popup. The popup then calls `AbandonQuest()` against whatever quest is currently selected - not what the user clicked.

**Fix pattern**: capture the quest title and index at click time, then re-search by title before calling AbandonQuest:

```lua
local savedAbandonTitle, savedAbandonIndex
hooksecurefunc("QuestLog_UpdateSelectedAbandonable", function() end)  -- placeholder hook
-- On QuestLog abandon button click:
QuestLogAbandonButton:HookScript("OnClick", function()
    savedAbandonIndex = GetQuestLogSelection()
    savedAbandonTitle = GetQuestLogTitle(savedAbandonIndex)
end)
-- On the popup OnAccept:
StaticPopupDialogs["ABANDON_QUEST"].OnAccept = function()
    -- re-search by title in case the index drifted
    for i = 1, GetNumQuestLogEntries() do
        local title = GetQuestLogTitle(i)
        if title == savedAbandonTitle then
            SelectQuestLogEntry(i)
            break
        end
    end
    AbandonQuest()
end
```

### 3. Quest reward tooltips show wrong item

Quest reward item tooltips can show the wrong item if pfQuest's scanner or Leatrix Plus has stolen GameTooltip ownership. Force re-anchor every quest reward `OnEnter`:

```lua
for i = 1, 6 do
    local btn = _G["QuestInfoItem"..i]
    if btn then
        btn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            QuestInfo_OnHyperlinkEnter(self)  -- or call SetQuestItem directly
        end)
    end
end
```

### 4. Inspect tooltip cache expiry

Item links from `INSPECT_READY` expire ~10-15s after the inspect. If a user hovers a slot after the cache expires, `GetInventoryItemLink("target", slot)` returns nil and the tooltip is empty.

**Fix pattern**: cache all 19 slot links at INSPECT_READY time, fall back to cache when live link is nil:

```lua
local linkCache = {}
local f = CreateFrame("Frame")
f:RegisterEvent("INSPECT_READY")
f:SetScript("OnEvent", function(self, event, guid)
    for slot = 1, 19 do
        linkCache[guid] = linkCache[guid] or {}
        linkCache[guid][slot] = GetInventoryItemLink("target", slot)
    end
end)
-- In tooltip OnEnter:
local link = GetInventoryItemLink("target", slot) or
             (linkCache[UnitGUID("target")] and linkCache[UnitGUID("target")][slot])
```

---

## DLL injection policy

Project Epoch's general policy (per the official wiki, as of mid-2026): **even purely cosmetic third-party client modifications may violate the rules, as they alter game files**. This includes:

- `FrostAtom/awesome_wotlk` (Detours-based DLL adding C_NamePlate)
- `suprepupre/wow-optimize` and `suprepupre/LuaBoost` (Lua VM optimization DLLs)
- HD-client packs / texture mods
- Any DLL injector

**Recommendation**: do not require DLL-based libraries in addons targeting Project Epoch. If your addon would benefit from awesome_wotlk's `C_NamePlate.*`, gate it as optional with a fallback message:

```lua
if not (C_NamePlate and C_NamePlate.GetNamePlates) then
    print("MyAddon: nameplate features require awesome_wotlk DLL " ..
          "(NOTE: may violate Project Epoch ToS - check before installing)")
    return
end
```

Verify the current ToS at <https://project-epoch-wow.fandom.com/wiki/Project_Epoch_Wiki> before assuming this policy hasn't changed.

---

## Recommended Project Epoch addon ecosystem

For a baseline UI on Project Epoch, the widely-installed stack is:

| Category | Recommended addon | Source |
|---|---|---|
| Quest tracking | `pfQuest-wotlk` + `pfQuest-epoch` | Defcons/epoch-addons or Bennylavaa/pfQuest-epoch |
| Custom Atlas data | `AtlasQuest` | Rofos2011/AtlasQuest |
| LFG / dungeon finder | `LFG` (Bennylavaa) | Bennylavaa/LFG (note: maintenance status varies) |
| Auction house | `Aux-addon` (Defcons fork) | Defcons/epoch-addons |
| Inventory | `ArkInventory` (Defcons fork with Lua 5.1 xpcall fix) | Defcons/epoch-addons |
| Nameplates | `NotPlater-3.3.5` (Defcons fork) | Defcons/epoch-addons |
| Bug fixes | `EpochFixes` | Defcons/epoch-addons |
| Item drop database | `Epoch_Drops` | sebastianpiresmolin/epoch-drops |
| TSM bridge | `AuxTSMBridge` | Defcons/epoch-addons |

For new addon development, study the project-local agent instructions and the individual addons' source - they encode hard-won knowledge about Project Epoch quirks that aren't documented anywhere else.
