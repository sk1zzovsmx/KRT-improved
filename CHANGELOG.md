# Changelog

This project follows a simple rule: every user-visible or behavior change gets an entry here.
Dates are in YYYY-MM-DD.

## Unreleased
- **Refactor:** Continued modular architecture migration (wave 4d). UI legacy XML was decomposed into
  `UI/Minimap.xml`, `UI/ReservesTemplates.xml`, `UI/Master.xml`, and `UI/LootCounter.xml`; `KRT.xml`
  now includes these feature files directly, with no behavior changes.
- **Refactor:** Completed wave 4d cleanup by removing deprecated `UI/LegacyHead.xml`,
  `UI/LegacyMid.xml`, and `UI/LegacyTail.xml` placeholders from the repository.
- **Refactor:** Continued modular architecture migration (wave 4c.1). Core feature headers now consume
  shared context from `addon.Core.getFeatureShared()` in `KRT.lua`, reducing repeated local/bootstrap blocks
  in `Raid/Chat/Minimap/Rolls/Loot/Master/LootCounter` files without behavior changes.
- **Refactor:** Continued modular architecture migration (wave 4c). `Features/LootStack.lua` was split into
  `Features/Rolls.lua`, `Features/Loot.lua`, and `Features/Master.lua`; `LootStack.lua` remains as placeholder.
- **Refactor:** Continued modular architecture migration (wave 4b). Runtime core split further into
  `Features/Raid.lua`, `Features/Chat.lua`, `Features/Minimap.lua`, `Features/LootStack.lua`,
  and `Features/LootCounter.lua`; `Features/CoreGameplay.lua` is now a migration placeholder.
- **Refactor:** Continued modular architecture migration (wave 4). Core gameplay runtime modules
  (`Raid/Chat/Minimap/Rolls/Loot/Master/LootCounter`) moved to `Features/CoreGameplay.lua`,
  and slash/event wiring moved to `Features/SlashEvents.lua`, leaving `KRT.lua` as thin bootstrap/glue.
- **Refactor:** Continued modular architecture migration (wave 3). Logger runtime stack
  (Store/View/Actions/lists/popups) moved to `Features/Logger.lua`, and Logger UI moved to `UI/Logger.xml`,
  with `KRT.lua`/`KRT.xml` keeping only migration placeholders and include orchestration.
- **Refactor:** Continued modular architecture migration (wave 2). `Reserves` and `ReserveImport` were
  extracted into `Features/Reserves.lua` and `Features/ReserveImport.lua` with matching `UI/Reserves.xml`
  and `UI/ReserveImport.xml`, preserving existing behavior and public module APIs.
- **Refactor:** Started modular architecture migration (wave 1). `KRT.lua`/`KRT.xml` are now split with
  `Features/*.lua` and `UI/*.xml` include files, preserving existing runtime behavior and public module APIs.
- **Bugfix:** SoftRes import mode is now synchronized between runtime reserves state and
  `addon.options/KRT_Options`, so ReserveImport slider/parsing always matches the active mode after load/import.
- **Bugfix:** Reserve List window now relies on the inherited `KRTFrameTemplate` background to prevent
  background bleed outside the panel border.
- **UI:** Reserve List rows now use a stronger odd/even stripe contrast and a subtle horizontal delimiter line
  on each row for better readability.
- **UI:** Reserve List now also draws the delimiter on top of the first visible row of each
  collapsible group.
- **UI:** Reserve List item and player lines are vertically re-aligned to better center on the icon middle.
- **UI:** Reserve List now uses slightly more spacing between item and player lines while keeping icon-centered
  alignment.
- **UI:** Reserve List tooltips no longer show the boss/source line (keeps tooltip content minimal).
- **Packaging:** GitHub source archives now export only the `!KRT` addon folder by marking
  repository docs and dev files as `export-ignore`.
- **Refactor:** Renamed `Localization/ErrorLog.en.lua` to `Localization/DiagnoseLog.en.lua` and
  migrated diagnostic storage from `addon.E` to `addon.Diagnose`.
- **Refactor:** Added local `Diag` wrappers and switched diagnostic callsites from `Diagnose.*` to
  `Diag.*`; reorganized `DiagnoseLog.en.lua` by feature categories.
- **Behavior:** Diagnostic templates are now categorized by severity buckets:
  `Diagnose.I`, `Diagnose.W`, `Diagnose.E`, `Diagnose.D`, with matching callsites in `KRT.lua`.
- **Refactor:** Moved remaining hardcoded diagnostic strings in `KRT.lua`/`Modules/Utils.lua` into
  `Localization/DiagnoseLog.en.lua` (LoggerSelect, LoggerUI, callback execution, manual loot tag).
- **Bugfix:** Removed the `table: XXXXXXXX:` chat prefix from logger output by overriding
  `addon:Print` to forward through LibCompat without the addon self-label.
- **Bugfix:** Fixed nil getFrame error in UI module factories (Reserves, ReserveImport, Config, Warnings, Changes, Logger). Each module now properly initializes getFrame with `Utils.makeFrameGetter()` before using it in `makeUIFrameController()`.
- **Bugfix:** Logger module had getFrame redefined after factory initialization; removed duplicate definition to preserve correct execution order.
- **Bugfix:** Added missing `Diagnose.D.LogReservesImportWrongModePlus` log template used by Reserves CSV validation.
- **Localization:** Moved hardcoded Reserves tooltip/display strings (item/source labels and summary lines) into `addon.L`.
- **Behavior:** Reserved-roll announce text now hides `(P+N)` and `(xN)` suffixes and shows only the player list.
- **Bugfix:** Master Looter `Import SoftRes/Open SoftRes` button now updates immediately
  after SoftRes import and list clear operations.
- **Refactor:** Loot Counter and Reserve List windows now use only coalesced event-driven refresh
  (`RequestRefresh`) and no longer perform redundant immediate redraw calls.
- **Behavior:** Loot Counter refresh is now driven by `RaidRosterUpdate` and
  `PlayerCountChanged`; removed in-refresh `UpdateRaidRoster()` calls to prevent loop spam.
- **Behavior:** Removed standalone `/krtcounts`; Loot Counter is now toggled via `/krt counter`.

## 2026-02-08
**REFACTORING PROJECT COMPLETE** — Code consolidation initiative (3 phases) concluded.

### Consolidation Summary (Total: ~108-123 lines eliminated)
- **Phase 1 (High priority, Low risk):** 33 lines
  - Consolidated duplicated `GetPlus()` helper via `MakePlusGetter()` factory (8 lines)
  - Consolidated `GetMasterFrameName()` duplicate handling (10 lines)
  - Created `Utils.makeFrameGetter()` factory consolidating 3x identical frame getter patterns (15 lines)
  
- **Phase 2 (Medium risk, Significant impact):** 75-90 lines
  - Added `addon:makeUIFrameController()` factory consolidating Toggle/Hide/Show patterns across 9 UI modules
  - Applied to: Master Looter, LootCounter, Reserves, ReserveImport, Config, Warnings, Changes, Spammer, Logger
  
- **Phase 3 (Low priority, Optional):** Analysis completed; no additional consolidations identified
  - Verified CheckPlayer pattern already centralized in addon.Raid
  - Verified dropdown logic already parameterized via FindDropDownField
  - Verified all major consolidations already completed

### Changes
- Refactor: Moved `makeUIFrameController` factory from KRT.lua to Utils.lua (shared utility factory layer); added backwards-compatible alias in KRT.lua.
- Refactor: Master Looter dropdown handlers (holder/banker/disenchanter) consolidated to eliminate 3 identical branches via parameterized FindDropDownField.
- Refactor: Master Looter UpdateDropDowns consolidated from 3 repetitive if-elseif blocks to single loop via FindDropDownField (reduces code duplication).
- Master Looter: Hold/Bank/DE clears rolls only after completed assignment; inventory trade setup no longer wipes rolls early.
- Minimap: left-clicking the minimap icon now toggles the context menu open/closed.
- Docs: updated AGENTS.md with explicit `.luacheckrc` maintenance guidance for addon globals.
- Docs: fixed OVERVIEW.md repository links to use root-relative paths.
- Tooling: refreshed `.luacheckrc` with explicit KRT frame/global allowlist entries.

## 2026-02-05
- Docs: Split change log out of AGENTS.md into CHANGELOG.md (no runtime behavior change).

---

## Legacy entries (moved from the old AGENTS.md)

- 2026-03-15: Skip raid target icon on the master looter when they win their own trade.
- 2026-03-14: Master Loot roll button now respects multi-reserve roll counts for the local player.
- 2026-03-13: Converted Config/Warnings/Changes/Reserves/BossBox UI refresh to on-demand updates.
- 2026-03-12: Fixed Master Looter inventory insert to match cursor items by itemId fallback.
- 2026-03-12: Simplified Master Looter bag item selection (click drop, tradeable gate, bag scan).
- 2026-03-12: Localized XML UI strings from KRT.xml/Templates.xml via Lua.
- 2026-03-12: Loot Counter keeps scroll position and relies on localization strings.
- 2026-03-12: Loot Counter player names now use class colors.
- 2026-03-12: Loot Counter headers use the same grey styling as Master Looter.
- 2026-03-11: Deterministic changes list ordering and refresh after deletions.
- 2026-03-11: Improved list controller sorting, row sizing, and scroll inset safety.
- 2026-03-10: Localized Reserve List window buttons (clear, query item, close).
- 2026-03-10: Master Loot reserve list button toggles insert/open; Loot Counter uses former Raid List button.
- 2026-03-09: Master Looter uses GetContainerItemLink for inventory item links in 3.3.5a.
- 2026-03-08: Split log localization strings into Localization/ErrorLog.en.lua.
- 2026-03-07: Clear rolls when self-awarding stacked inventory items (multi-count trade keep path).
- 2026-03-06: Master Looter buttons: countdown gates item selection, roll start, SR gated by reserved item,
  roll/award gating, reset rolls on awards; selection now enables Hold/Bank/DE buttons.
- 2026-03-05: Removed Docs/KRT_STANDARD.md and Docs/WoW_Addons.pdf references and files.
- 2026-03-05: Removed TemplatesLua directory references from AGENTS and deleted TemplatesLua.
- 2026-03-02: Removed `/krt lfm period` command and default LFM period SV entry.
- 2026-03-01: Renamed History module to Logger (UI, strings, and references).
- 2026-02-21: Removed KRT_Debug SavedVariable (log levels are runtime-only).
- 2026-02-15: Parse pushed loot messages and refresh Loot Logger on new loot.
- 2026-02-01: Fixed CallbackHandler OnUsed/OnUnused wiring in event dispatcher and templates.
- 2026-01-13: Standardized repository language to English (AGENTS + codebase rules).
- 2026-01-13: Reaffirmed KRT.lua monolithic policy and in-file module skeleton.
- 2026-01-13: Codified Lua 5.1 style rules (globals, formatting, naming, errors/returns, iteration).
- 2026-01-07: Simplified SavedVariables: removed unused versioning/audit keys.
- 2026-01-02: Standardized module skeleton, updated templates/docs, and introduced addon.LootCounter (kept aliases).
- 2025-12-27: Hardened debug logger guard, trimmed slash args, removed unused CHAT_MSG_ADDON entry.
- 2025-12-24: Added BINDING docs/templates as canonical patterns for all work.
- 2025-09-27: SR roll button allows non-reserved players to roll once (SR priority remains).
- 2025-09-26: Load saved SR reserves during addon initialization.
- 2025-09-25: Reserve list rows place text to the right of icons; hide icons until item data loads.
- 2025-09-24: Reserve list row alignment + auto-query missing item icons on open.
- 2025-09-23: Reset Master Loot ItemCount on item change/award; refresh counts for loot sources.
- 2025-09-22: Expanded vendored library guidance into explicit bullet rules.
- 2025-09-21: Prefer vendored libs; avoid Utils/KRT duplicates; skip fallbacks when libs are vendored.
- 2025-09-20: Enlarged Loot Counter window, centered title, and enabled dragging.
- 2025-09-13: Updated nil-check and API fallback guidelines.
- 2025-09-10: Clarified proprietary WoW API requirement.
- 2025-09-09: Integrated new template; removed unused libs.
- 2025-09-08: Renamed Logger module to History to avoid conflict with debugging logger.
- 2025-09-07: Clarified monolithic structure and updated CLI command list.
- 2025-09-05: Initial lightweight version; removed binding “recipes”. Added dev-only branching policy.
