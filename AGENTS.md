# KRT - AGENTS.md (WoW 3.3.5a - Lua 5.1)

**Context file for AI coding agents.** Lives at repo root. Keep lines short (<= 120 chars). Keep this current.

**Default:** guidelines are non-binding; when in doubt, follow existing KRT patterns.
**Exception:** sections marked **BINDING** must be followed for every change.

---

## 1) Purpose
KRT (Kader Raid Tools) provides raid-lead QoL for WotLK 3.3.5a: loot handling (MS/OS/SR), soft reserves,
loot history/logger, master-loot helpers, LFM spammer, warnings/announces, and export/import utilities.

UI is **XML + Lua** (no Ace3 GUI). Libraries are vendored via **LibStub**.

---

## 2) Hard constraints
- **Client/API:** Wrath of the Lich King **3.3.5a** (Interface **30300**), **Lua 5.1** runtime.
- **Addon folder name:** `!KRT` (leading `!` is intentional).
- **Architecture:** **KRT.lua stays MONOLITHIC** for feature/core logic. (**BINDING**)
- **SV compatibility:** do not break SavedVariables keys without migration + change log note.
- **Dependencies:** do not introduce Ace3. Prefer existing vendored libs.

---

## 3) Monolithic KRT.lua policy (BINDING)
Monolithic means:
- Feature logic (Raid/Rolls/Reserves/Loot/Logger/Master/Warnings/Spammer/Changes/Config/Slash) lives in **KRT.lua**
  and is organized as `do ... end` module blocks.
- `Modules/` is reserved for existing **utility/const/data lists** (e.g., `Utils.lua`, `C.lua`, `ignoredItems.lua`).
  It must not become a feature plugin system.

Binding rules:
1) New features and major refactors MUST be implemented inside **KRT.lua**, not as new files.
2) A new file is allowed only if it is:
   - a static data list (IDs/lookup tables), or
   - a generic reusable utility, or
   - required by technical constraints/load order,
   and it MUST be documented in **17) Change log**.
3) Each in-file module block must be self-contained (private state local to the block; exports only on `addon.X`).

---

## 4) Load order (BINDING)
WoW file load order matters. Keep (or restore) this logical order in the `.toc`:

1) **LibStub**
2) **CallbackHandler-1.0**
3) **LibCompat-1.0** (includes internal libs)
4) **LibDeformat-3.0**
5) **LibLogger-1.0**
6) **LibBossIDs-1.0**
7) **Localization/localization.en.lua** (defines `addon.L`)
8) **Templates.xml**
9) **Modules/Utils.lua**, **Modules/C.lua**
10) **KRT.lua** (monolithic core + modules)
11) **KRT.xml** (main UI)
12) **Modules/ignoredItems.lua** (intentionally after KRT.lua)

---

## 5) Real repo layout
```
!KRT/
  !KRT.toc
  KRT.lua                  # MONOLITH: core + modules
  KRT.xml                  # main UI (keep frame scripts thin)
  Templates.xml            # reusable XML templates

  Localization/
    localization.en.lua    # canonical user strings (enUS)

  Modules/
    Utils.lua              # helpers (addon.Utils)
    C.lua                  # constants/enums/patterns (addon.C)
    ignoredItems.lua       # data lists / filters

  Libs/
    LibStub/
    CallbackHandler-1.0/
    LibCompat-1.0/
    LibDeformat-3.0/
    LibLogger-1.0/
    LibBossIDs-1.0/
```

---

## 6) Globals & SavedVariables (BINDING)

### 6.1 Intentional globals
- `_G["KRT"] = addon` is set by `KRT.lua` for debugging/interop and is intentional.
- Do not introduce additional globals.

### 6.2 SavedVariables (account)
These keys are used by the addon and must remain compatible:
- `KRT_Options`
- `KRT_Raids`
- `KRT_Players`
- `KRT_Warnings`
- `KRT_ExportString`
- `KRT_Spammer`
- `KRT_CurrentRaid`
- `KRT_LastBoss`
- `KRT_NextReset`
- `KRT_SavedReserves`
- `KRT_PlayerCounts`

Rules:
- Do not rename/re-structure SV without a migration.
- Any user-visible change MUST be documented in **17) Change log**.

---

## 7) Language policy (BINDING)
KRT is standardized on **English**.

Binding rules:
1) **All new or modified content must be English**:
   - code comments,
   - log/debug messages (LibLogger),
   - UI labels/help text,
   - chat/whisper text.
2) User-facing text MUST go through localization (`addon.L`):
   - `Localization/localization.en.lua` (enUS) is the canonical source of truth.
   - Do not add hardcoded user strings in code unless it is debug-only and clearly marked.
3) Localization keys SHOULD be English and stable. Do not rename keys without a migration plan.
4) Avoid string concatenation for sentences; prefer format placeholders (e.g., `format(L.X, a, b)`).
5) Existing non-English comments/strings SHOULD be migrated opportunistically when touched, but avoid mass rewrites that
6) Prefer ASCII-only text in code/comments/logs. Avoid typographic quotes/dashes and emojis.
   do not change behavior.

---

## 8) UI: main windows (KRT.xml)
Main frames (keep compatibility):
- `KRTConfig`
- `KRTWarnings`
- `KRTMaster`
- `KRTLogger`
- `KRTChanges`
- `KRTSpammer`
- `KRTLootCounterFrame`
- Common helpers: `KRTImportWindow`, `KRTItemSelectionFrame`, `KRTReserveListFrame`

Guidelines:
- XML stays thin: route logic into `KRT.lua` module methods.
- Reuse templates from `Templates.xml`.

---

## 9) Slash commands
- `/krt`, `/kraidtools` -> main dispatcher (handled by `addon.Slash`).
- `/krtcounts` -> toggles loot counter (`addon.Master:ToggleCountsFrame()`).

Rule:
- Do not break existing commands. Additions require help output + localization updates.

---

## 10) Module map (KRT.lua)
Modules are tables on `addon.*` inside `KRT.lua`:

- `addon.State`     - shared runtime state
- `addon.Chat`      - chat output helpers
- `addon.Slash`     - command parsing + help
- `addon.Config`    - options & SavedVariables
- `addon.Minimap`   - minimap button
- `addon.Raid`      - raid/session, roster, instance detection
- `addon.Rolls`     - roll tracking, sorting, winner logic (MS/OS/SR)
- `addon.Reserves`  - soft reserve model + import/export
- `addon.Loot`      - loot parsing, item selection, export strings
- `addon.Logger`    - loot history logging + UI refresh
- `addon.Master`    - master-loot helpers, award/trade tracking, loot counter frame
- `addon.Warnings`  - announce templates, throttling, channel selection
- `addon.Changes`   - MS change collection/announce
- `addon.Spammer`   - LFM spam helper

External modules:
- `addon.Utils` (Modules/Utils.lua)
- `addon.C`     (Modules/C.lua)

---

## 11) Canonical in-file module pattern (BINDING)
Every module block inside `KRT.lua` MUST follow this skeleton:

```lua
do
    addon.ModuleName = addon.ModuleName or {}
    local module = addon.ModuleName

    local L = addon.L
    local Utils = addon.Utils
    local C = addon.C

    -- Private state (local to this block)
    local state = {
        enabled = true,
    }

    -- Private helpers (local functions) above the public API

    -- Public API
    function module:Init()
    end
end
```

Rules:
- Working variables and state are `local` to the block.
- Public exports only via `addon.ModuleName`.
- Avoid circular dependencies. If needed, move shared helpers into `Utils` or implement a minimal bridge.

---

## 12) Lua 5.1 coding standard (BINDING)
This standard defines the repository-wide Lua 5.1 style. New code MUST follow it.

### 12.1 Non-negotiables
1) No accidental globals: everything is `local` unless exported via `addon` or documented as intentional global.
2) Prefer locals (performance + readability).
3) Do not use environment hacks in application logic (`getfenv/setfenv` only for tests/sandbox).

### 12.2 Formatting
- Indentation: **4 spaces** (no tabs).
- No trailing whitespace.
- No semicolons.
- Strings: prefer `"..."` in new code; `[[...]]` for multiline.

### 12.3 Naming
- Exported modules/tables: **PascalCase** (e.g., `Reserves`, `Loot`).
- Public functions: **lowerCamelCase** verbs (e.g., `getRaidSize`, `setEnabled`).
- Private helpers: `local function name()` (optional `_prefix`).
- Constants: **UPPER_SNAKE_CASE**.
- Booleans: `is/has/can/should` prefix.

### 12.4 Errors and returns
- Recoverable failures: `return nil, "reason"`.
- Success: return a non-nil primary value (`true`, result table, etc.).
- `assert()` only for invariants/programmer errors.
- `pcall/xpcall` only at untrusted boundaries (parsing external input, plugin hooks).

### 12.5 Tables and iteration
- Arrays are 1-indexed.
- If holes are possible, do not rely on `#t`.
- Use `for i = 1, #arr do ... end` for sequences; `pairs()` for maps.
- Avoid `ipairs()` if nil holes are possible.

### 12.6 Performance/GC
- Avoid allocations in tight loops (reuse tables).
- Avoid concatenation in loops; use `table.concat` where appropriate.
- Cache stdlib functions locally only in hot paths.

### 12.7 Optional dev-only global guard
```lua
-- DEV ONLY: fail on new globals
setmetatable(_G, {
    __newindex = function(_, k, _)
        error("Attempt to create global '" .. tostring(k) .. "'", 2)
    end
})
```

---

## 13) Logging (LibLogger-1.0) guidelines
Use consistent levels:
- `error`: breaks functionality or corrupts state
- `warn`: abnormal but non-blocking behavior
- `info`: major lifecycle events (raid created, boss kill, award, trade)
- `debug/trace`: detailed flow (avoid spam, especially in combat)

Throttle high-frequency sources (roster updates, combat log, UI refresh loops).

---

## 14) WoW 3.3.5a compatibility
- Do not use modern APIs (`C_Timer`, `C_` namespaces, etc.).
- Avoid `io/os/debug` (not available in WoW).
- Respect combat lockdown (do not manipulate secure frames in combat).

---

## 15) Manual test checklist
- Login: no errors; `/krt` opens.
- Raid detection: instance/difficulty detected; `KRT_CurrentRaid` created.
- Rolls: MS/OS/SR works; stable sorting; deterministic winner.
- Reserves: import/export; caps; roll gating consistent.
- Logger: records append; UI refresh; filters keep order.
- Master: award/trade tracking; `/krtcounts` toggles `KRTLootCounterFrame`.
- Warnings/Spammer: correct channels + throttling.
- Persistency: `/reload` keeps SV and expected state.

---

## 16) Do / Don't
**Do:** small testable changes; reuse templates; local scope; logs that help without spamming.
**Don't:** Ace3, long blocking loops, new SV without migration, undocumented globals, moving features into new files.

---

## 17) Change log (edit manually)
- 2026-03-09: Logger "Set Current" now allows switching raids while not in a raid group.
- 2026-03-08_: Split KRT.lua into module files and added Modules/Core.lua with updated toc load order.
- 2026-01-13: Standardized repository language to English (AGENTS + codebase rules).
- 2026-01-13: Reaffirmed **KRT.lua monolithic** policy and in-file module skeleton.
- 2026-01-13: Codified Lua 5.1 style rules (globals, formatting, naming, errors/returns, iteration).
- 2026-03-07_: Clear rolls when self-awarding stacked inventory items (multi-count trade keep path).
- 2026-03-06_: Master Looter buttons: countdown gates item selection, roll start, SR gated by reserved item, roll/award gating, reset rolls on awards; selection now enables Hold/Bank/DE buttons.
- 2026-03-05_: Removed Docs/KRT_STANDARD.md and Docs/WoW_Addons.pdf references and files.
- 2026-03-05_: Removed TemplatesLua directory references from AGENTS and deleted TemplatesLua.
- 2026-03-02_: Removed `/krt lfm period` command and default LFM period SV entry.
- 2026-01-02_: Standardized module skeleton (use `local module`), updated TemplatesLua + Docs, and introduced `addon.LootCounter` module (kept Master aliases).
- 2025-09-05_: Initial lightweight version; removed binding “recipes”. Added `dev`-only branching policy.
- 2025-09-07_: Clarified monolithic structure and updated CLI command list.
- 2025-09-08_: Renamed Logger module to History to avoid conflict with debugging logger.
- 2025-09-09_: Integrate new template. Removed unused Libs.
- 2025-09-10_: Clarified proprietary WoW API requirement.
- 2025-09-13_: Updated nil-check and API fallback guidelines.
- 2025-12-24_: Added BINDING `Docs/KRT_STANDARD.md` and `TemplatesLua/` as canonical patterns for all work.
- 2026-01-07_: Simplified SavedVariables: removed unused versioning/audit keys.
- 2025-12-27_: Hardened debug logger guard, trimmed slash args, removed unused CHAT_MSG_ADDON entry.
- 2025-09-20_: Enlarged Loot Counter window, centered title, and enabled dragging.
- 2025-09-21_: Prefer vendored libs, avoid Utils/KRT duplicates, and skip fallbacks when libs are vendored.
- 2025-09-22_: Expanded vendored library guidance into explicit bullet rules.
- 2025-09-23_: Reset Master Loot ItemCount on item change/award and refresh counts for loot sources.
- 2025-09-24_: Centered reserve list row alignment and auto-queried missing item icons on open.
- 2025-09-25_: Reserve list rows now place text to the right of icons and hide icons until item data loads.
- 2025-09-26_: Load saved SR reserves during addon initialization.
- 2025-09-27_: SR roll button allows non-reserved players to roll once (SR priority remains).
- 2026-02-01_: Fixed CallbackHandler OnUsed/OnUnused wiring in event dispatcher and templates.
- 2026-02-15_: Parse pushed loot messages and refresh Loot Logger on new loot.
- 2026-02-21_: Removed KRT_Debug SavedVariable (log levels are runtime-only).
- 2026-03-01_: Renamed History module to Logger (UI, strings, and references).
