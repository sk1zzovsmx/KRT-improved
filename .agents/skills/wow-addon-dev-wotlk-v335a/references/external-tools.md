# External Tools - Recommended Companions for WotLK 3.3.5 Addon Dev

This skill is self-contained, but four external resources dramatically improve productivity when working on 3.3.5 addons. None are bundled (license/practical reasons); install them separately as your workflow needs them.

## Table of contents

1. [MilkyWay Codex - MCP server for AI-assisted API lookup](#milkyway-codex--mcp-server-for-ai-assisted-api-lookup)
2. [wowgaming/3.3.5-interface-files - Blizzard FrameXML mirror](#wowgaming335-interface-files--blizzard-framexml-mirror)
3. [FrostAtom/awesome_wotlk - engine extensions for missing modern APIs](#frostatomawesome_wotlk--engine-extensions-for-missing-modern-apis)
4. [BLP / MPQ tools - asset extraction and conversion](#blp--mpq-tools--asset-extraction-and-conversion)
5. [Lua syntax tooling - Luanalysis, vscode-lua](#lua-syntax-tooling--luanalysis-vscode-lua)

---

## MilkyWay Codex - MCP server for AI-assisted API lookup

**Use when:** Codex needs to look up a 3.3.5a API function, event, widget method, CVar, or combat-log subevent and need ground-truth signatures.

**What it is:** an MCP (Model Context Protocol) server that wraps the full 3.3.5a reference data - ~1500 Lua API functions, ~400 events, every widget method, all CVars, and all CLEU subevents. Designed for token-efficient lookup so an AI assistant doesn't need to load big reference docs into context.

**Listing**: search for "MilkyWay Codex" on mcpmarket.com or pulsemcp.com. Provider id `suprsokr-milkyway-codex`.

**Install**: configure the MCP server in the active Codex MCP setup, or in any project/user MCP config supported by the current runtime:

```json
{
  "mcpServers": {
    "milkyway-codex": {
      "command": "npx",
      "args": ["-y", "@suprsokr/milkyway-codex"]
    }
  }
}
```

(Verify the actual command from the current MCP listing - install commands change.)

**When this skill should defer to MilkyWay Codex**: any time a question requires a specific API signature beyond what `references/api-reference.md` covers. Examples:

- "What are the args of `UnitClass`?" -> MilkyWay's `lookup_function` tool, no need to grep
- "Does `GetItemInfo` return spellID on 3.3.5?" -> MilkyWay's `lookup_function`, ground truth
- "List all `UNIT_*` events" -> MilkyWay's `search_events` with type filter
- "What CVars exist for nameplates?" -> MilkyWay's `search_cvars`

**Fallback if not installed**: grep the FrameXML mirror (next section).

---

## wowgaming/3.3.5-interface-files - Blizzard FrameXML mirror

**Use when:** you need to know "how does Blizzard implement X" - for any UI element, frame template, or event handler.

**Repo**: <https://github.com/wowgaming/3.3.5-interface-files>

**Contents**: every Lua and XML file from Blizzard's default UI for 3.3.5a. ~26 stars on GitHub but indispensable. Includes:

- Top-level FrameXML (`CharacterFrame.lua/xml`, `ContainerFrame.lua/xml`, `BuffFrame.lua/xml`, `CastingBarFrame.lua/xml`, `ChatFrame.lua/xml`, ...)
- All `Blizzard_*` modules (`Blizzard_AchievementUI`, `Blizzard_AuctionUI`, `Blizzard_CombatLog`, `Blizzard_GuildBankUI`, `Blizzard_InspectUI`, `Blizzard_RaidUI`, `Blizzard_TalentUI`, ...)
- `FrameXML.toc` declaring load order

**Recommended workflow**:

```bash
# Clone once
git clone https://github.com/wowgaming/3.3.5-interface-files.git ~/refs/wotlk-frame-xml

# When porting an addon, grep the mirror for any function/template you reference
rg "UIDropDownMenu_AddButton" ~/refs/wotlk-frame-xml/
rg "SecureActionButton" ~/refs/wotlk-frame-xml/
```

If a function appears in this repo, it exists on 3.3.5 and the implementation is the source of truth.

---

## FrostAtom/awesome_wotlk - engine extensions for missing modern APIs

**Use when:** building or porting an addon that needs APIs Blizzard never shipped on 3.3.5 - primarily `C_NamePlate`, the `NAME_PLATE_*` events, and a few QoL items.

**Repo**: <https://github.com/FrostAtom/awesome_wotlk>

**What it is**: a Detours-based DLL that injects new APIs into the 3.3.5 client at runtime. Adds:

| API / Event / CVar | Use case |
|---|---|
| `C_NamePlate.GetNamePlates()` | Iterate visible nameplate frames |
| `C_NamePlate.GetNamePlateForUnit(unit)` | Direct lookup |
| `NAME_PLATE_CREATED` event | First-time frame creation |
| `NAME_PLATE_UNIT_ADDED` event | Frame attached to unit |
| `NAME_PLATE_UNIT_REMOVED` event | Frame detached |
| `UnitIsControlled(unit)` | Mind control / fear detection |
| `UnitIsDisarmed(unit)` | Disarm detection |
| `UnitIsSilenced(unit)` | Silence detection |
| `GetInventoryItemTransmog(unit, slot)` | Transmog appearance ID |
| `FlashWindow()` / `IsWindowFocused()` / `FocusWindow()` | OS-level window state |
| `CopyToClipboard(text)` | Programmatic clipboard |
| CVar `nameplateDistance` | Configurable nameplate range |
| CVar `cameraFov` | FOV adjustment |

**Install**: download release, extract DLL into WoW root folder, run `AwesomeWotlkPatch.exe` once to patch the binary.

**Caveats**:

1. Patches the WoW.exe - some private servers consider this client modification and ban for it. **Check the server's ToS before recommending it to users.** For Project Epoch, see `references/server-specific/project-epoch.md` section "DLL injection policy".
2. Not maintained beyond v0.1.4 (Nov 2022) - no breakage so far on the 3.3.5a 12340 build.
3. Always feature-detect when using its APIs:
   ```lua
   if C_NamePlate and C_NamePlate.GetNamePlates then
       -- safe to use
   else
       -- fallback or warn user
   end
   ```

---

## BLP / MPQ tools - asset extraction and conversion

**Use when:** building UI textures, extracting Blizzard assets to derive icons/borders, or repackaging custom textures for the 3.3.5 client.

WoW's texture format is BLP (Blizzard's compressed texture). WoW's archive format is MPQ. To work with these:

| Tool | Purpose | Source |
|---|---|---|
| BLPNG-Converter | BLP <-> PNG conversion | <https://www.wowinterface.com/downloads/info23458-BLPNGConverterCommandlineUtilityVersion10.html> |
| BLPView | Inspect BLP files visually | community fork; search "BLPView" |
| MPQEditor (Ladik) | Open / extract MPQ archives | <http://www.zezula.net/en/mpq/download.html> |
| StormLib | C library for MPQ access (used by tools) | <https://github.com/ladislav-zezula/StormLib> |

**Workflow**:

1. Open `World of Warcraft\Data\patch.MPQ` or `expansion.MPQ` in MPQEditor
2. Navigate to `Interface\` or wherever the asset lives
3. Extract `.blp` file
4. Convert to PNG with BLPNG-Converter for editing
5. Re-export to BLP, drop in your addon's textures folder
6. Reference from Lua: `texture:SetTexture("Interface\\AddOns\\MyAddon\\textures\\myicon")` (no extension)

**License caution**: never redistribute extracted Blizzard assets in your addon. Use them for reference, then create your own derivatives or properly licensed alternatives.

---

## Lua syntax tooling - Luanalysis, vscode-lua

For type-checking and IDE support during development:

- **Luanalysis** (IntelliJ IDEA / WebStorm plugin) - set language level to **5.0** for Vanilla 1.12 work, **5.1** for WotLK 3.3.5
- **sumneko/lua-language-server** (VS Code, Neovim) - set `Lua.runtime.version = "Lua 5.1"` in settings; pair with type definitions:
  - <https://github.com/SabineWren/wow-api-type-definitions> - Vanilla 1.12 (Lua 5.1 mode in the LS even though the runtime is 5.0)
  - <https://github.com/refaim/Vanilla-WoW-Lua-Definitions> - alternative Vanilla 1.12 definitions
  - For WotLK 3.3.5: there is no widely-adopted typedef set; many devs use the Retail typedefs and accept the false positives, or roll their own from the FrameXML mirror

VS Code `.luarc.json` for 3.3.5 work:

```json
{
  "runtime.version": "Lua 5.1",
  "diagnostics.globals": [
    "ipairs", "pairs", "select", "unpack",
    "CreateFrame", "GetTime", "GetItemInfo", "UnitName", "UnitClass",
    "UnitHealth", "UnitHealthMax", "UnitGUID", "UnitExists",
    "UnitBuff", "UnitDebuff", "UnitAura", "UnitIsPlayer",
    "GetSpellInfo", "GetSpellCooldown", "CastSpellByName", "CastSpellByID",
    "SendChatMessage", "SendAddonMessage", "DEFAULT_CHAT_FRAME",
    "GetContainerNumSlots", "GetContainerItemInfo", "GetInventoryItemLink",
    "SLASH_MYADDON1", "SlashCmdList", "GetAddOnMetadata",
    "InCombatLockdown", "hooksecurefunc",
    "UIParent", "WorldFrame", "GameTooltip",
    "LibStub", "wipe", "strsplit", "strjoin", "strtrim",
    "geterrorhandler", "seterrorhandler",
    "bit"
  ],
  "diagnostics.disable": ["lowercase-global"]
}
```

Add the globals your addon actually uses; this is a starter set, not exhaustive.
