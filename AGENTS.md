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
- Do not introduce Ace dependencies (Ace2/Ace3); prefer native KRT + LibCompat patterns.
- Avoid runtime backward-compat shims when refactoring; target the fresh-SV model directly.
- Prefer LuaRocks Lua Style Guide for formatting/layout when it does not conflict with KRT binding conventions.
- Prefer PascalCase for addon module table names.
- Prefer PascalCase for public exported methods on feature modules (`module:*`, `Store:*`, `View:*`, `Actions:*`,
  `Box:*`); keep WoW-required event names unchanged (UPPERCASE handlers).
- Prefer PascalCase for public/cross-module APIs in infrastructure namespaces too
  (`Core`, `Bus`, `Frames`, `UI*`, `Strings`, `Time`, `Comms`, `Base64`, `Colors`, `ItemProbe`).
- Prefer camelCase for utility functions and local variables; avoid snake_case for new naming.
- Keep file-local/private helpers in camelCase; keep Lua metamethods (`__index`, `__call`, etc.) unchanged.
- For naming migrations, use phased rollout: add PascalCase API + temporary alias, migrate call-sites
  (including XML/Binder/string references), then remove alias after zero legacy hits.
- In feature files under `Controllers/`, `Services/`, `Widgets/`, `EntryPoints/`, prefer canonical top-level
  section headers in order:
  `-- ----- Internal state ----- --`, `-- ----- Private helpers ----- --`,
  `-- ----- Public methods ----- --`.
- UI refactors: centralize shared UI glue/patterns in `KRT.lua`; keep feature-specific UI logic in each module.
- Move helpers to `Modules/Utils.lua` only when they are generic and reused, not for KRT-specific glue.
- Keep diagnostic templates in `addon.Diagnose`; use severity buckets `I/W/E/D` (`DiagnoseLog.en.lua`).
- Prefer local `Diag` wrapper aliases over direct `Diagnose.*` chains in implementation files.
- For naming/API uniformization, choose the most repeated in-repo pattern and apply it consistently and robustly.
- For XML and Lua analysis/reference, use Townlong-Yak FrameXML 3.3.5:
  `https://www.townlong-yak.com/framexml/3.3.5`.
- Treat raid `players[].count` (LootCounter) as canonical persisted raid data; restoring/selecting an old current raid
  must preserve and reuse historical counts.
- Prefer a clean persisted raid schema: keep `players[]` as the canonical persisted player store; treat
  `_playersByName` as a derived runtime index/cache.
- Treat fresh SavedVariables as strict mode: avoid legacy/migration cleanups and avoid fallback to
  volatile array indices when stable NIDs (`playerNid`, `bossNid`, `lootNid`) are available.
- Keep `EntryPoints/SlashEvents.lua` focused on `/cmd` handling only.
- Keep main WoW event handlers centralized in `KRT.lua`; modules should expose callable APIs used by those handlers.
- Prefer storing runtime-only addon state under `addon.State` (or feature state tables) over global runtime vars.
- Prefer deterministic sorting with explicit tie-breakers; when primary values are equal, use stable secondary keys
  (for Logger Loot, prefer loot name, then IDs) to avoid random reordering between sorts.
- Keep bootstrap ownership centralized in `Core/Init.lua` for `addon.Core`, `addon.L`, `addon.Diagnose`,
  `addon.State`, `addon.C`, and `addon.Events`; do not re-bootstrap them in feature files.
- Prefer a uniform Lua file contract header with:
  `local addon = select(2, ...)` and `local feature = addon.Core.GetFeatureShared()`.
- Prefer bus-only architecture from `KRT.lua`: no direct calls from Core to `addon.Master`/`addon.Logger`/other
  Parents; wire WoW events into `Bus.TriggerEvent("wow.EVENT", ...)` and let modules subscribe.
- Keep Logger-owned roster UI refresh logic inside `Controllers/Logger.lua` (subscribed via `RaidRosterDelta`),
  not in `KRT.lua`.
- Prefer a widget facade/port via `addon.UI` (`Modules/UI/Facade.lua`) for Controller/EntryPoint -> Widget calls.
- Avoid direct references to `addon.LootCounter`, `addon.ReservesUI`, and `addon.Config` in
  `Controllers/*.lua` and `EntryPoints/*.lua`; use `addon.UI:Call(...)` instead.
- Prefer optional widget architecture with `addon.Features` flags and profile-aware toggles (`core` vs `full`).
- Keep `Modules/UI/Binder/UIBinder.lua` resilient for optional widgets: skip bindings when a widget is disabled
  by feature flags or not registered in `addon.UI`.
- Keep XML layout-only: do not use `<Scripts>`/`<On...>` in `UI/*.xml` and `Templates.xml`.
- Prefer centralized UI script wiring in `Modules/UI/Binder/UIBinder.lua`
  (single binding table/source of truth).
- Prefer `Modules/UI/Binder/UIBinder.lua` bindings as direct Lua functions
  (`frameName + scriptType -> function`)
  and avoid `loadstring`-based script compilation.
- Keep Services pure: no frame lifecycle (`OnLoad`/`Refresh`) or UI delegation in `Services/*`;
  widgets consume `addon.<Feature>.Service` and refresh via bus events (e.g. `ReservesDataChanged`).
- Keep tooltip-based item metadata probes isolated in an infra adapter module (for example
  `Modules/ItemProbe.lua`); Services must consume only `feature.ItemProbe`/`addon.ItemProbe`.
- Prefer cross-code extraction from `Modules/Utils.lua` into dedicated reusable modules (`Bus`, `ListController`,
  `MultiSelect`, `Frames`, `Strings`, `Colors`, `Comms`, `Base64`, `Time`); keep `Utils.lua` as facade/re-export.
- Prefer incremental thematic split of `Modules/Utils.lua` into `Modules/Utils.*.lua` files
  (`UI`, `Tooltip`, `Options`, `RaidState`, `LegacyGlobals`), while keeping `Utils.lua`
  as compatibility facade/aggregator.
- Prefer centralized event-name registry in `Modules/Events.lua` for internal bus events and
  wow-forwarded events (avoid ad-hoc string literals in modules).
- Prefer namespaced module ownership under `addon.Controllers.*`, `addon.Services.*`, `addon.Widgets.*`;
  keep temporary legacy aliases (`addon.Master`, `addon.Raid`, etc.) during soft migrations.
- Alias lockdown: keep legacy aliases as compatibility only; in debug mode, warn on legacy alias reads
  (`addon.Raid`, `addon.Logger`, etc.) to prevent new call sites from regressing.
- Prefer fast architecture verification via focused `rg` checks (XML inline scripts, widget facade calls,
  namespacing coverage, and legacy top-level access scans) before closing refactor tasks.

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
- Early bootstrap for shared addon tables and header contract wiring lives in `!KRT/Core/Init.lua`.
- Core runtime bootstrap, shared runtime state, and global event wiring live in `!KRT/KRT.lua`.
- Feature implementations live in:
  - `!KRT/Controllers/*.lua` (top-level parent owners),
  - `!KRT/Services/*.lua` (runtime service/model modules),
  - `!KRT/Widgets/*.lua` (feature-specific UI controllers/widgets),
  - `!KRT/EntryPoints/*.lua` (slash/minimap entrypoints).
- `!KRT/Modules/` remains reserved for utilities/constants/static data (e.g., `Utils.lua`, `C.lua`,
  `ignoredItems.lua`) and must not become a feature folder.
- XML is split into feature-oriented files under `!KRT/UI/`, loaded via `!KRT/KRT.xml` include manifest.

Rules:
1) New feature modules SHOULD be placed in the appropriate folder among `Controllers/`, `Services/`,
   `Widgets/`,
   `EntryPoints/`, unless there is a strong reason to keep them in `KRT.lua`.
2) `KRT.lua` should stay focused on bootstrap/glue and shared infrastructure that must exist before features.
3) Prefer `addon.Core.GetFeatureShared()` in feature file headers for shared locals/runtime state bootstrap.
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
7) Core/Init.lua (single bootstrap for `addon.Core/L/Diagnose/State/C/Events` + `Core.GetFeatureShared()`)
8) Localization/localization.en.lua (fills `addon.L`)
9) Localization/DiagnoseLog.en.lua (fills `addon.Diagnose`)
10) Templates.xml
11) Modules/C.lua
12) Modules/Events.lua
13) Modules/Colors.lua
14) Modules/Strings.lua
15) Modules/Comms.lua
16) Modules/Time.lua
17) Modules/Base64.lua
18) Modules/Features.lua
19) Modules/UI/Facade.lua
20) Modules/UI/Visuals.lua
21) Modules/UI/Frames.lua
22) Modules/UI/ListController.lua
23) Modules/UI/MultiSelect.lua
24) Modules/UI/Binder/Map.lua
25) Modules/UI/Binder/UIBinder.lua
26) Modules/Bus.lua
27) Modules/Utils.LegacyGlobals.lua
28) Modules/Utils.Options.lua
29) Modules/Utils.RaidState.lua
30) Modules/Utils.Tooltip.lua
31) Modules/Compat/Utils.UI.lua
32) Modules/Utils.lua
33) KRT.lua (runtime bootstrap + event wiring + shared runtime glue)
34) Services/Raid.lua
35) Services/Chat.lua
36) EntryPoints/Minimap.lua
37) Services/Rolls.lua
38) Services/Loot.lua
39) Controllers/Master.lua
40) Widgets/LootCounter.lua
41) Services/Reserves.lua
42) Widgets/ReservesUI.lua
43) Controllers/Logger.lua
44) Services/Syncer.lua
45) Widgets/Config.lua
46) Controllers/Warnings.lua
47) Controllers/Changes.lua
48) Controllers/Spammer.lua
49) EntryPoints/SlashEvents.lua
50) KRT.xml (UI include manifest; default profile forwards to `KRT.Full.xml`)
51) Modules/ignoredItems.lua (intentionally after runtime/UI definitions)

---

## 5) Repo layout (actual)

```
!KRT/
  !KRT.toc
  Core/
    Init.lua               # single bootstrap for addon root tables + shared contract helper
  KRT.lua                  # runtime bootstrap + shared runtime glue + main event wiring
  KRT.xml                  # UI include manifest/orchestrator
  KRT.Core.xml             # core UI include manifest (without optional widgets)
  KRT.Full.xml             # full UI include manifest (core + optional widgets)
  Templates.xml            # reusable XML templates

  Controllers/
    Master.lua             # master-loot parent owner
    Logger.lua             # logger parent owner + submodules
    Warnings.lua           # warnings parent owner
    Changes.lua            # changes parent owner
    Spammer.lua            # spammer parent owner

  Services/
    Raid.lua               # raid/session, roster, instance detection
    Chat.lua               # output helpers (Print/Announce)
    Rolls.lua              # roll tracking, sorting, winner logic
    Loot.lua               # loot parsing, item selection, export strings
    Reserves.lua           # soft reserves service/model + import parsing + reserve lookups
    Syncer.lua             # logger synchronization (addon comms)

  Widgets/
    LootCounter.lua        # loot counter UI + data
    ReservesUI.lua         # reserve list + import frame controller + row/header rendering
    Config.lua             # options UI logic

  EntryPoints/
    Minimap.lua            # minimap button + context menu
    SlashEvents.lua        # slash command router

  UI/
    Minimap.xml            # minimap button frame
    ReservesTemplates.xml  # reserve list templates
    Reserves.xml           # reserve list UI + reserve import window UI
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
    C.lua                  # constants/enums/patterns (addon.C)
    Events.lua             # centralized event-name registry (addon.Events)
    Colors.lua             # color normalization/class-color helpers (addon.Colors)
    Strings.lua            # text/item-link normalization and parsing (addon.Strings)
    Comms.lua              # addon chat/whisper/sync helpers (addon.Comms)
    Time.lua               # time/difficulty helpers (addon.Time)
    Base64.lua             # base64 codec helpers (addon.Base64)
    Features.lua           # feature flags/profile toggles (addon.Features)
    UI/
      Facade.lua           # widget facade (addon.UI) with Register/Call no-op routing
      Visuals.lua          # UI primitives + row visuals (addon.UIPrimitives/addon.UIRowVisuals)
      Frames.lua           # frame helpers + UI scaffold/orchestration (addon.Frames/addon.UIScaffold)
      ListController.lua   # reusable scroll-list controller (addon.ListController)
      MultiSelect.lua      # reusable multiselect state helpers (addon.MultiSelect)
      Binder/
        Map.lua            # XML binding datasets/maps (addon.UIBinder.Map)
        UIBinder.lua       # XML binder runtime/facade + compiler (addon.UIBinder/addon.UIBinder.Compiler)
    Bus.lua                # internal callback bus + metrics (addon.Bus)
    Utils.LegacyGlobals.lua # legacy global monkeypatches (`table.*` / `string.*`)
    Utils.Options.lua      # debug/options helpers (addon.Utils.Options)
    Utils.RaidState.lua    # raid/player state helpers (addon.Utils.RaidState)
    Utils.Tooltip.lua      # tooltip/soulbound helpers (addon.Utils.Tooltip)
    Compat/
      Utils.UI.lua         # UI compat facade wrappers (addon.Utils.UI)
    Utils.lua              # compatibility facade/re-exports (addon.Utils)
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
- `Modules/Utils.LegacyGlobals.lua` intentionally defines a few global convenience helpers:
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
- Exception: `debug` is runtime-only state and must not be persisted in `KRT_Options`.

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
- `addon.Reserves`      - soft reserves service facade (data/model APIs)
- `addon.Reserves.Service` - soft reserves store/index/import implementation
- `addon.ReservesUI`    - reserve list UI widget owner
- `addon.ReservesUI.Import` - reserve import UI widget owner
- `addon.Config`        - options UI + defaults/load
- `addon.Warnings`      - warnings list + announce helpers
- `addon.Changes`       - MS changes list + announce
- `addon.Spammer`       - LFM spam helper
- `addon.Logger`        - loot logger UI + raid editor
- `addon.Syncer`        - logger synchronization protocol (request/push + merge)

`addon.Logger` internal structure (pattern for complex modules):
- `addon.Logger.Store`   - data access helpers + stable-ID indexing
- `addon.Logger.View`    - view-model row builders (UI-friendly data)
- `addon.Logger.Actions` - mutations + commit/refresh boundaries

Implementation placement (current wave):
- `Core/Init.lua`: single bootstrap for shared addon tables + `Core.GetFeatureShared()`
- `KRT.lua`: runtime core + main gameplay/logger logic
- `Controllers/*.lua`, `Services/*.lua`, `Widgets/*.lua`, `EntryPoints/*.lua`

External modules:
- `addon.Utils` (Modules/Utils.lua)
  - `addon.Utils.LegacyGlobals` (Modules/Utils.LegacyGlobals.lua)
  - `addon.Utils.Options` (Modules/Utils.Options.lua)
  - `addon.Utils.RaidState` (Modules/Utils.RaidState.lua)
  - `addon.Utils.Tooltip` (Modules/Utils.Tooltip.lua)
  - `addon.Utils.UI` (Modules/Compat/Utils.UI.lua)
- `addon.C`     (Modules/C.lua)
- `addon.Events` (Modules/Events.lua)
- `addon.Colors` (Modules/Colors.lua)
- `addon.Strings` (Modules/Strings.lua)
- `addon.Comms` (Modules/Comms.lua)
- `addon.Time` (Modules/Time.lua)
- `addon.Base64` (Modules/Base64.lua)
- `addon.UIPrimitives` (Modules/UI/Visuals.lua)
- `addon.UIRowVisuals` (Modules/UI/Visuals.lua)
- `addon.Frames` (Modules/UI/Frames.lua)
- `addon.UIScaffold` (Modules/UI/Frames.lua)
- `addon.MultiSelect` (Modules/UI/MultiSelect.lua)
- `addon.ListController` (Modules/UI/ListController.lua)
- `addon.Bus` (Modules/Bus.lua)
- `addon.Features` (Modules/Features.lua)
- `addon.UI`    (Modules/UI/Facade.lua)
- `addon.UIBinder.Map` (Modules/UI/Binder/Map.lua)
- `addon.UIBinder.Compiler` (Modules/UI/Binder/UIBinder.lua)
- `addon.UIBinder` (Modules/UI/Binder/UIBinder.lua)

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
- keep feature logic in `Controllers/*.lua` / `Services/*.lua` / `Widgets/*.lua` / `EntryPoints/*.lua`,
  and shared infra in `KRT.lua`,
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

---

## 18) Architecture layering (Parents/Services + Bus) (**BINDING**)

- 5 top-level Parents: `Changes`, `MasterLoot` (`addon.Master`), `Warnings`, `Logger`, `Spammer`.
- Parent owner files live under `!KRT/Controllers/` (folder naming), while "Parent" remains the architecture term.
- Services MUST NOT call Parents or touch Parent frames.
- Services MUST NOT reference Widgets or delegate UI (`addon.*UI`, `module.UI`, `Get*UI` patterns).
- Upward communication uses internal bus (`Bus.RegisterCallback` / `Bus.TriggerEvent`).
- EntryPoint toggle exception: `EntryPoints/SlashEvents.lua` and `EntryPoints/Minimap.lua` may call
  `Parent:Toggle()`.
- Prefer existing events (`SetItem`, `RaidRosterDelta`) over new UI micro-events.
- UI ownership: Master frame UI code lives in `Master` (or Master View helpers).
- Child widgets attach Parent->Child only.
