---
name: wow-addon-dev-wotlk-v335a
description: Develop, port, review, and debug World of Warcraft addons for the WotLK 3.3.5a client, Interface 30300, and Lua 5.1. Use when Codex works on WoW addon code, .toc files, FrameXML/UI, Lua errors from a 3.3.5 client, private-server addon ecosystems such as Project Epoch, Warmane, Ascension, or Atlantiss, or ports addons from Vanilla, TBC, Classic, Retail, Ace3, pfQuest-wotlk, ElvUI-WotLK, DBM, Recount, or similar WotLK addon codebases.
---

# WoW Addon Development - WotLK 3.3.5a

Use this skill for addon work targeting the 3.3.5a client, build 12340,
Interface 30300, and Lua 5.1.5.

## Priority

Obey project-local instructions first. In this KRT workspace, read and follow
`AGENTS.md` before changing addon code:

- Keep the addon folder name `!KRT`.
- Do not introduce Ace2 or Ace3 dependencies.
- Do not modify vendored libraries under `!KRT/Libs/*`.
- Keep XML layout-only; do not add XML scripts or `<On...>` handlers.
- Keep user-facing strings in `addon.L` and diagnostics in `addon.Diagnose`.
- Preserve SavedVariables shape unless adding migration and changelog notes.

When this skill conflicts with `AGENTS.md`, repo docs, or direct user
instructions, follow the higher-priority local instruction.

## Environment Facts

| Property | Value |
|---|---|
| Client patch | 3.3.5a |
| Build | 12340 |
| TOC Interface | `30300` |
| Runtime Lua | Lua 5.1.5 |
| FrameXML mirror | `wowgaming/3.3.5-interface-files` |
| Optional engine extensions | `FrostAtom/awesome_wotlk` |

Classic+ private servers can add content and globals, but the base client API
is still the 3.3.5a API unless a client-side DLL or launcher explicitly extends
it. Treat server-specific behavior as an extra constraint, not as proof that a
Retail API exists.

## Reference Loading

Keep context small. Read only the references needed for the task.

| User intent or signal | Read or run |
|---|---|
| New addon from scratch | `references/api-reference.md`, then `assets/MinimalAddon/` |
| Port Vanilla 1.12 code to WotLK | `references/porting-guide.md`, `references/lua-51-compatibility.md` |
| Port Retail, Classic, or TBC code to 3.3.5a | `references/porting-guide.md`, `references/api-reference.md` |
| Debug 3.3.5 Lua errors | `references/lua-51-compatibility.md`; use script checks below |
| TOC load failure | run `scripts/validate_toc.py`, then read `references/api-reference.md` TOC notes |
| Ace3 or AceGUI porting outside KRT | `references/ace3-on-335.md`, then scan for `xpcall` |
| FrameXML, secure templates, UI, or taint | `references/frame-xml-cookbook.md` |
| Missing APIs such as `C_Timer` or `C_NamePlate` | `references/porting-guide.md`, then `references/external-tools.md` |
| Project Epoch behavior | `references/server-specific/project-epoch.md` |
| MPQ, BLP, or external asset tooling | `references/external-tools.md` |

## Codex Workflow

1. Inspect the repo first with `rg` or `rg --files`.
2. For code edits, preserve the existing architecture and naming style.
3. Use Lua 5.1 syntax only; avoid Retail and Classic APIs unless guarded.
4. Prefer event-driven WoW UI patterns. Avoid polling `OnUpdate` unless the
   project already allows that pattern.
5. Run focused validators before claiming the addon loads.
6. For KRT, also run the repo gates documented in `tools/krt.py` and
   `docs/DEV_CHECKS.md` when relevant.

On Windows, prefer `py -3` for the bundled Python validators. On Unix-like
systems, use `python3`.

```powershell
py -3 .agents/skills/wow-addon-dev-wotlk-v335a/scripts/validate_toc.py path/to/Addon.toc
py -3 .agents/skills/wow-addon-dev-wotlk-v335a/scripts/lint_lua51.py path/to/Addon/
py -3 .agents/skills/wow-addon-dev-wotlk-v335a/scripts/scan_xpcall.py path/to/Addon/
```

## Non-Negotiable Runtime Rules

The 3.3.5 client embeds Lua 5.1.5. These constructs do not parse:

- `goto label` and `::label::`
- `//` integer division
- Bitwise operators `&`, `|`, `~`, `<<`, `>>`
- `_ENV`
- `\z` string escape
- `table.pack`, `table.unpack`, and `bit32`

Use the global `unpack`, Blizzard's `bit.*` namespace, and regular control
flow. Read `references/lua-51-compatibility.md` for replacements.

## The `xpcall` Trap

Lua 5.1 `xpcall` accepts only `func` and `handler`. Extra arguments are silently
dropped, which breaks modern Ace3 and many Retail ports.

```lua
-- Broken on 3.3.5: arg1 and arg2 are dropped.
xpcall(func, handler, arg1, arg2)

-- Correct on 3.3.5.
local ok, err = pcall(func, arg1, arg2)
if not ok then
    handler(err)
end
```

Run `scripts/scan_xpcall.py` when porting Ace3-based or modern addon code.

## Common API Replacements

| Modern API | 3.3.5a replacement |
|---|---|
| `C_Timer.After(delay, fn)` | `CreateFrame("Frame")` with one-shot `OnUpdate` |
| `C_Timer.NewTicker(interval, fn)` | persistent `OnUpdate` with elapsed accumulator |
| `Settings.RegisterCanvasLayoutCategory` | `InterfaceOptions_AddCategory(panel)` |
| `Settings.RegisterAddOnCategory` | `InterfaceOptions_AddCategory(panel)` |
| `C_AddOns.GetAddOnMetadata` | `GetAddOnMetadata` |
| `MenuUtil`, `Menu`, `CreateAnchor` | `UIDropDownMenu_*` APIs |
| `texture:SetAtlas(name)` | unavailable; guard or replace with texture paths |
| `texture:SetColorTexture(r,g,b,a)` | `texture:SetTexture(r, g, b, a)` |
| `frame:SetMask(path)` | unavailable; guard with capability checks |
| `WOW_PROJECT_ID` and `WOW_PROJECT_MAINLINE` | absent; nil-guard use |
| `## AllowLoadGameType` | unsupported; remove |

## TOC Rules

Minimum 3.3.5 TOC:

```toc
## Interface: 30300
## Title: My Addon
## Notes: Description
## Author: YourName
## Version: 1.0.0
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB

main.lua
```

Run `scripts/validate_toc.py` to catch bad Interface versions, missing files,
unsupported directives, and malformed SavedVariables entries.

## Hooking And Taint

Use `hooksecurefunc` for Blizzard post-hooks. Do not raw-replace protected or
FrameXML functions unless the project has an established wrapper and the taint
risk is understood.

```lua
hooksecurefunc("QuestLog_Update", function()
    myLogic()
end)
```

Protected actions must run from hardware events or secure templates. Treat UI
automation, spell casts, item use, targeting, and macro mutation as combat-safe
design problems, not ordinary function calls.

## Validation

For a generic addon tree, run:

```powershell
py -3 .agents/skills/wow-addon-dev-wotlk-v335a/scripts/validate_toc.py path/to/Addon/Addon.toc
py -3 .agents/skills/wow-addon-dev-wotlk-v335a/scripts/lint_lua51.py path/to/Addon/
py -3 .agents/skills/wow-addon-dev-wotlk-v335a/scripts/scan_xpcall.py path/to/Addon/
```

For KRT changes, also run the relevant repo checks from `AGENTS.md`, for example:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Runtime behavior still needs an in-game smoke test on a 3.3.5a client.

## External Lookup

For API details beyond the bundled references:

1. Prefer an installed 3.3.5a API lookup MCP if available.
2. Otherwise grep a local clone of `wowgaming/3.3.5-interface-files`.
3. Use Wowpedia only after checking that an API exists in 3.3.5 FrameXML.

Never bundle copyrighted Blizzard books, PDFs, extracted MPQ assets, or client
data into generated addon repositories. Link to sources or require local user
assets instead.
