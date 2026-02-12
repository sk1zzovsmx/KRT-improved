# KRT - AGENTS.md (WoW 3.3.5a / Lua 5.1)

Context file for AI coding agents. Lives at repo root as `AGENTS.md`.
Keep lines <= 120 chars. Keep this file current.

Default: guidelines are non-binding; when in doubt, follow existing KRT patterns.
Exception: sections marked **BINDING** must be followed for every change.

Changelog: **CHANGELOG.md** is the single source of truth for behavior/user-visible changes.

---

## Conversations (Self-Learning)

Update requirement:
- Before starting any task, scan the latest user message for new permanent rules/preferences.
- If a new durable rule is detected, update this file first, then do the task.

Do NOT record:
- one-off instructions for a single task,
- temporary exceptions.

Durable preferences learned from recent conversations:
- Prefer PascalCase for addon module table names.
- Prefer camelCase for utility functions and local variables; avoid snake_case for new naming.
- UI refactors: centralize shared UI glue/patterns in `KRT.lua`; keep feature-specific UI logic in each module.
- Move helpers to `Modules/Utils.lua` only when they are generic and reused, not for KRT-specific glue.
- Keep diagnostic templates in `addon.Diagnose`; use severity buckets `I/W/E/D` (`DiagnoseLog.en.lua`).
- Prefer local `Diag` wrapper aliases over direct `Diagnose.*` chains in implementation files.
- For XML and Lua analysis/reference, use Townlong-Yak FrameXML 3.3.5:
  `https://www.townlong-yak.com/framexml/3.3.5`.

---

## 1) Purpose

KRT (Kader Raid Tools) provides raid-lead QoL for WotLK 3.3.5a:
- loot handling (MS/OS/SR) + master-loot helpers,
- soft reserves (import/export, reserve list),
- loot history/logger,
- warnings/announces, LFM spammer,
- small utilities (export strings, helpers).

UI is XML + Lua (no Ace3 GUI). Libraries are vendored via LibStub.

---

## 2) Hard constraints (**BINDING**)

- Client/API: Wrath of the Lich King 3.3.5a (Interface 30300), Lua 5.1 runtime.
- Addon folder name: `!KRT` (leading `!` is intentional).
- No Ace3 dependencies (do not introduce Ace3).
- SavedVariables compatibility: do not break SV keys/shape without migration + CHANGELOG entry.

---

## 3) Modular feature policy (**BINDING**)

KRT is now modular by design:
- Core bootstrap, shared runtime state, and global event wiring live in `!KRT/KRT.lua`.
- Feature implementations can live in `!KRT/Features/*.lua`.
- `!KRT/Modules/` remains reserved for utilities/constants/static data (e.g., `Utils.lua`, `C.lua`,
  `ignoredItems.lua`) and must not become a feature folder.
- XML is split into feature-oriented files under `!KRT/UI/`, loaded via `!KRT/KRT.xml` include manifest.

Rules:
1) New feature modules SHOULD be placed in `!KRT/Features/` unless there is a strong reason to keep them in
   `KRT.lua`.
2) `KRT.lua` should stay focused on bootstrap/glue and shared infrastructure that must exist before features.
3) Prefer `addon.Core.getFeatureShared()` in feature file headers for shared locals/runtime state bootstrap.
4) Public exports go on `addon.*`; avoid extra globals.
5) Any user-visible behavior changes or migration notes MUST be documented in `CHANGELOG.md`.

---

## 4) Load order (**BINDING**)

WoW file load order matters. Keep (or restore) this order in `!KRT/!KRT.toc`:

1) LibStub
2) CallbackHandler-1.0
3) LibBossIDs-1.0
4) LibDeformat-3.0
5) LibCompat-1.0
6) LibLogger-1.0
7) Localization/localization.en.lua (defines `addon.L`)
8) Localization/DiagnoseLog.en.lua (defines `addon.Diagnose`)
9) Templates.xml
10) Modules/Utils.lua, Modules/C.lua
11) KRT.lua (core bootstrap + event wiring + shared runtime glue)
12) Features/Raid.lua
13) Features/Chat.lua
14) Features/Minimap.lua
15) Features/Rolls.lua
16) Features/Loot.lua
17) Features/Master.lua
18) Features/LootCounter.lua
19) Features/Reserves.lua
20) Features/ReserveImport.lua
21) Features/Logger.lua
22) Features/Config.lua
23) Features/Warnings.lua
24) Features/Changes.lua
25) Features/Spammer.lua
26) Features/SlashEvents.lua
27) KRT.xml (UI include manifest)
28) Modules/ignoredItems.lua (intentionally after runtime/UI definitions)

---

## 5) Repo layout (actual)

```
!KRT/
  !KRT.toc
  KRT.lua                  # core bootstrap + shared runtime glue
  KRT.xml                  # UI include manifest/orchestrator
  Templates.xml            # reusable XML templates

  Features/
    Raid.lua               # raid/session, roster, instance detection
    Chat.lua               # output helpers (Print/Announce)
    Minimap.lua            # minimap button + context menu
    Rolls.lua              # roll tracking, sorting, winner logic
    Loot.lua               # loot parsing, item selection, export strings
    Master.lua             # master-loot helpers, award/trade tracking
    LootCounter.lua        # loot counter UI + data
    CoreGameplay.lua       # deprecated wave 4 compatibility placeholder (not loaded in TOC)
    LootStack.lua          # deprecated wave 4c compatibility placeholder (not loaded in TOC)
    Reserves.lua           # soft reserves model + list UI
    ReserveImport.lua      # SR import window glue + validation
    Logger.lua             # loot logger module stack (store/view/actions/ui)
    Config.lua             # options UI logic
    Warnings.lua           # warnings list + announce helpers
    Changes.lua            # MS changes list + announce
    Spammer.lua            # LFM spam helper
    SlashEvents.lua        # slash command router + addon event handlers

  UI/
    Minimap.xml            # minimap button frame
    ReservesTemplates.xml  # reserve list templates
    Reserves.xml           # reserve list UI
    ReserveImport.xml      # reserve import UI
    Logger.xml             # logger templates + frames
    Config.xml             # config UI
    Spammer.xml            # spammer UI
    Warnings.xml           # warnings UI
    Master.xml             # item selection + master looter UI
    LootCounter.xml        # loot counter UI
    Changes.xml            # changes UI

  Localization/
    localization.en.lua    # user-facing strings (enUS) -> addon.L
    DiagnoseLog.en.lua     # diagnostic templates (enUS) -> addon.Diagnose

  Modules/
    Utils.lua              # helpers + UI controllers (addon.Utils)
    C.lua                  # constants/enums/patterns (addon.C)
    ignoredItems.lua       # data lists / filters

  Libs/
    LibStub/
    CallbackHandler-1.0/
    LibBossIDs-1.0/
    LibDeformat-3.0/
    LibCompat-1.0/
    LibLogger-1.0/
```

---

## 6) Globals & SavedVariables (**BINDING**)

### 6.1 Intentional globals (allowed)

- `_G["KRT"] = addon` is set by `KRT.lua` for debugging/interop.
- Named XML frames become globals (normal WoW UI behavior). Examples:
  - `KRTConfig`, `KRTWarnings`, `KRTMaster`, `KRTLogger`, `KRTChanges`, `KRTSpammer`
  - `KRTLootCounterFrame`, `KRTReserveListFrame`, `KRTImportWindow`, `KRTItemSelectionFrame`
  - `KRTLoggerBossBox`, `KRT_MINIMAP_GUI`
- `Modules/Utils.lua` intentionally defines a few global convenience helpers:
  - `table.shuffle`, `table.reverse`, `string.trim`, `string.startsWith`, `string.endsWith`

Do not introduce additional non-frame globals (tables/vars/functions) unless explicitly required and documented.

### 6.2 SavedVariables (account)

These keys are persisted and must remain compatible:
- `KRT_Raids`
- `KRT_Players`
- `KRT_Reserves`
- `KRT_Warnings`
- `KRT_Spammer`
- `KRT_Options`

---

## 7) Language & strings (**BINDING**)

KRT is standardized on English.

Rules:
1) All new/modified content must be English (comments, logs, UI labels, chat text).
2) User-facing strings MUST go through `addon.L` (Localization/localization.en.lua).
3) Log/debug templates MUST go through `addon.Diagnose` (Localization/DiagnoseLog.en.lua).
4) Prefer format placeholders over sentence concatenation (use `format(L.Key, a, b)`).
5) Prefer ASCII-only in code/comments/logs (avoid typographic quotes/dashes and emojis).

---

## 8) Call style: `:` vs `.` (**BINDING**)

Lua method call depends on whether the function expects `self`:

- Use `:` for true methods (first parameter is `self`):
  - `addon:info(...)`, `addon:ADDON_LOADED(...)`, `module:Toggle()`, `Store:GetRaid(...)`
- Use `.` for plain functions (no `self`):
  - `Utils.getRaid(...)`, `addon.NewTimer(...)`, `addon.CancelTimer(...)`, `addon.After(...)`, `addon.LoadOptions()`

Rule: do not mechanically convert `.` <-> `:` unless you verified the function signature.

---

## 9) UI refresh policy: event-driven (**BINDING**)

KRT is actively refactoring away from polling-style UI updates.

Rules:
- Prefer on-demand UI redraws via `Utils.makeEventDrivenRefresher(getFrame, updateFn)`.
- Modules should expose:
  - `module:Refresh()` (pure redraw) and `module:RequestRefresh()` (throttled request).
- Avoid setting `OnUpdate` on feature frames to poll state.
- Allowed exceptions:
  - minimap drag movement,
  - LibCompat internal timers,
  - Utils internal driver frames used by `makeEventDrivenRefresher`.

For scroll lists:
- Prefer `Utils.makeListController({...})` + `controller:Dirty()` over manual row loops.
- For multi-selection, use `Utils.MultiSelect_*` with stable IDs.

---

## 10) Options access pattern

- SV table is `KRT_Options`.
- Runtime options are mirrored on `addon.options` by `addon.LoadOptions()` (called on ADDON_LOADED).
- When changing an option:
  - update `KRT_Options[key]`,
  - update `addon.options[key]` (if present),
  - request a refresh of the owning UI module.

---

## 11) Module map (runtime `addon.*`)

Top-level feature modules on `addon.*`:
- `addon.Raid`          - raid/session, roster, instance detection
- `addon.Chat`          - output helpers (Print/Announce)
- `addon.Minimap`       - minimap button + EasyMenu
- `addon.Rolls`         - roll tracking, sorting, winner logic
- `addon.Loot`          - loot parsing, item selection, export strings
- `addon.Master`        - master-loot helpers, award/trade tracking
- `addon.LootCounter`   - loot counter UI + data
- `addon.Reserves`      - soft reserves model + list UI
- `addon.ReserveImport` - SR import window glue + validation
- `addon.Config`        - options UI + defaults/load
- `addon.Warnings`      - warnings list + announce helpers
- `addon.Changes`       - MS changes list + announce
- `addon.Spammer`       - LFM spam helper
- `addon.Logger`        - loot logger UI + raid editor

`addon.Logger` internal structure (pattern for complex modules):
- `addon.Logger.Store`   - data access helpers + stable-ID indexing
- `addon.Logger.View`    - view-model row builders (UI-friendly data)
- `addon.Logger.Actions` - mutations + commit/refresh boundaries

Implementation placement (current wave):
- `KRT.lua`: core + most gameplay/logger logic
- `Features/*.lua`: Reserves, ReserveImport, Logger, Config, Warnings, Changes, Spammer

External modules:
- `addon.Utils` (Modules/Utils.lua)
- `addon.C`     (Modules/C.lua)

---

## 12) Lua 5.1 coding standard (**BINDING**)

Non-negotiables:
1) No accidental globals: everything is `local` unless intentionally exported.
2) Prefer locals for performance/readability.
3) Avoid environment hacks in addon logic (`getfenv/setfenv` only for niche debug tools).

Formatting:
- Indentation: 4 spaces (legacy code may contain tabs; do not mass-reformat).
- No trailing whitespace. No semicolons.

Errors/returns:
- Recoverable failure: `return nil, "reason"` or `return false` with a localized error message.
- Programmer errors/invariants: `assert()` or `error()`.

Iteration:
- Arrays are 1-indexed.
- If holes are possible, do not rely on `#t`.
- Prefer `for i = 1, #arr do ... end` for sequences; `pairs()` for maps.

---

## 13) Logging (LibLogger-1.0)

Use consistent levels:
- error: breaks functionality or corrupts state
- warn: abnormal but non-blocking behavior
- info: major lifecycle events (raid created, award, trade, boss kill)
- debug/trace: detailed flow (avoid spam, especially in combat)

Throttle high-frequency sources (roster bursts, combat log, UI refresh loops) with LibCompat timers.

---

## 14) WoW 3.3.5a compatibility

- Do not use modern APIs (`C_Timer`, `C_` namespaces, etc.).
- Avoid `io/os/debug` (not available in WoW runtime).
- Respect combat lockdown (avoid secure frame changes in combat).

---

## 15) Manual test checklist

- Login: no errors; `/krt` opens.
- Raid detection: instance/difficulty detected; current raid created; roster updates.
- Rolls: MS/OS/SR works; stable sorting; deterministic winner.
- Reserves: import/export; caps; roll gating consistent.
- Logger: loot entries append; filters; delete flows; selection highlight works.
- Master: award/trade tracking; multi-award; `/krt counter` toggles Loot Counter.
- Warnings/Changes/Spammer: correct channels + throttling; no UI spam.
- Persistency: `/reload` keeps SV and expected state.

---

## 16) Do / Don't

Do:
- small testable changes,
- reuse templates and Utils controllers,
- keep state local to module blocks,
- keep feature logic in `Features/*.lua` and shared infra in `KRT.lua`,
- document user-visible changes in CHANGELOG.md.

Don't:
- Ace3,
- long blocking loops,
- new SV keys without migration,
- new globals (beyond allowed ones).

---

## 17) Static analysis (`.luacheckrc`)

- Keep `.luacheckrc` aligned with current addon globals and frame names.
- When XML introduces/removes named frames, update `.luacheckrc` global allowlist in the same change.
- Prefer additive, explicit entries grouped under a `KRT addon globals` comment block.
