# Ace3 on WoW 3.3.5a

Ace3 is the dominant addon framework on WotLK private servers - most ported addons (ElvUI-WotLK, ArkInventory, DBM, Recount, Skada) use it. But modern Ace3 releases (v36+) target Lua 5.2+ and break in subtle ways on 3.3.5's Lua 5.1.5.

This doc covers the Ace3-specific compatibility issues. For general Lua 5.1 gotchas, see `lua-51-compatibility.md`.

## Table of contents

1. [Which Ace3 version to use on 3.3.5](#which-ace3-version-to-use-on-335)
2. [The xpcall break in AceGUI/AceConfig v36+](#the-xpcall-break-in-acegui-aceconfig-v36)
3. [AceDB and SavedVariables](#acedb-and-savedvariables)
4. [AceTimer for event coalescing](#acetimer-for-event-coalescing)
5. [AceComm for inter-addon comms](#acecomm-for-inter-addon-comms)
6. [Embedding vs LibStub-shared libraries](#embedding-vs-libstub-shared-libraries)
7. [Common library version recommendations](#common-library-version-recommendations)

---

## Which Ace3 version to use on 3.3.5

**Use Ace3 r1198 or earlier**, or one of the WotLK-curated forks (e.g. the version embedded in ElvUI-WotLK). These predate the variadic-xpcall break.

If you must use a newer Ace3 release for some reason, apply the xpcall patch (next section) to AceGUI-3.0, AceConfig-3.0, and any other library that uses variadic xpcall internally.

To check a library's version, look at the LibStub registration line:

```lua
local MAJOR, MINOR = "AceGUI-3.0", 36
local AceGUI = LibStub:NewLibrary(MAJOR, MINOR)
```

Anything `>= 36` for AceGUI-3.0 is post-break.

---

## The xpcall break in AceGUI/AceConfig v36+

Modern Ace3 dispatches event/widget callbacks via:

```lua
xpcall(callback, errorhandler, arg1, arg2, arg3)
```

On Lua 5.2+ this forwards `arg1, arg2, arg3` to the callback. On Lua 5.1 (3.3.5), the trailing args are silently dropped - the callback runs with no arguments and `self = nil`. No error fires, the addon "loads" but every widget is non-functional.

**The fix** (apply to every variadic xpcall in the offending library):

```lua
-- BROKEN
local ok, err = xpcall(callback, errorhandler, arg1, arg2, arg3)

-- FIXED
local ok, err = pcall(callback, arg1, arg2, arg3)
if not ok then errorhandler(err) end
```

Or build a `safecall` wrapper once and use it everywhere:

```lua
local function safecall(fn, ...)
    local n = select("#", ...)
    local args = {...}
    local results = {pcall(fn, unpack(args, 1, n))}
    if results[1] then
        return select(2, unpack(results))
    end
    geterrorhandler()(results[2])
end
```

Use `scripts/scan_xpcall.py` to find every offending call site automatically.

---

## AceDB and SavedVariables

AceDB-3.0 wraps SavedVariables with profile/character/realm/global scopes. Works fine on 3.3.5.

```lua
-- In your addon
local defaults = {
    profile = {
        showFrame = true,
        scale = 1.0,
    },
    char = {
        firstRun = true,
    },
}

local AceDB = LibStub("AceDB-3.0")
self.db = AceDB:New("MyAddonDB", defaults, true)  -- third arg: use UnitName as default profile

-- Access
self.db.profile.scale = 1.5
local first = self.db.char.firstRun
```

Don't forget to declare `## SavedVariables: MyAddonDB` in your TOC.

---

## AceTimer for event coalescing

Use AceTimer-3.0 instead of writing your own OnUpdate-based debouncer. Tightly integrated with AceEvent.

```lua
self:RegisterEvent("BAG_UPDATE", "OnBagUpdate")

function MyAddon:OnBagUpdate()
    if self.bagTimer then self:CancelTimer(self.bagTimer) end
    self.bagTimer = self:ScheduleTimer("DoBagScan", 0.5)
end

function MyAddon:DoBagScan()
    self.bagTimer = nil
    -- expensive scan
end
```

This collapses BAG_UPDATE floods (which can fire 10+ times per second during loot) into one scan per quiet period.

---

## AceComm for inter-addon comms

`AceComm-3.0` wraps `SendAddonMessage` / `CHAT_MSG_ADDON` with chunking, serialization, and per-prefix dispatch.

```lua
self:RegisterComm("MyAddonPrefix")

function MyAddon:OnCommReceived(prefix, msg, channel, sender)
    -- ...
end

self:SendCommMessage("MyAddonPrefix", "hello", "PARTY")
```

Note: `SendAddonMessage` on 3.3.5 has a per-tick byte budget. AceComm handles throttling. Without it, you'll silently drop messages under load.

---

## Embedding vs LibStub-shared libraries

Two ways to ship Ace3 with your addon:

**Embedded (recommended for distribution)**: copy the library into your addon's folder and load it from your TOC. Each addon ships its own copy. LibStub deduplicates by version (highest version wins). Pros: no missing-dependency installs. Cons: bloat.

**Standalone (Ace3 as a separate addon)**: list `## OptionalDeps: Ace3` in TOC and load the standalone Ace3 addon separately. Pros: no duplication. Cons: users must install Ace3 separately, version mismatches possible.

For a port targeting Project Epoch / Warmane, embed everything. Users on these servers don't typically install the standalone Ace3 package and you don't want surprise nil errors.

Embedding pattern in TOC:

```
embeds.xml
core.lua
```

`embeds.xml`:
```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
    <Include file="Libs\LibStub\LibStub.lua"/>
    <Include file="Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
    <Include file="Libs\AceAddon-3.0\AceAddon-3.0.xml"/>
    <Include file="Libs\AceEvent-3.0\AceEvent-3.0.xml"/>
    <Include file="Libs\AceDB-3.0\AceDB-3.0.xml"/>
    <Include file="Libs\AceTimer-3.0\AceTimer-3.0.xml"/>
    <!-- etc. -->
</Ui>
```

Get the library zip from the WoWAce/Curse archive for r1198 or from the ElvUI-WotLK repo's Libs folder.

---

## Common library version recommendations

Last-known-good versions for 3.3.5 (verified against Defcons/epoch-addons and ElvUI-WotLK):

| Library | Recommended version |
|---|---|
| LibStub | 2 (any) |
| CallbackHandler-1.0 | r24 |
| AceAddon-3.0 | r1238 (early) - avoid post-r1300 |
| AceEvent-3.0 | r1119 |
| AceTimer-3.0 | r1119 |
| AceConsole-3.0 | r1241 |
| AceDB-3.0 | r1241 |
| AceDBOptions-3.0 | r1241 |
| AceConfig-3.0 | r1183 (pre-xpcall-break) |
| AceGUI-3.0 | r1184 (pre-xpcall-break, v35) |
| AceComm-3.0 | r1241 |
| AceLocale-3.0 | r1119 |
| AceSerializer-3.0 | r1241 |
| LibSharedMedia-3.0 | r127 |
| LibDataBroker-1.1 | latest, version-stable |

If you grab newer versions from the curse/wowace archive, scan them with `scripts/scan_xpcall.py` first.
