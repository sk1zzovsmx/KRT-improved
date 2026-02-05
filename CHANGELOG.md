# Changelog

This project follows a simple rule: every user-visible or behavior change gets an entry here.
Dates are in YYYY-MM-DD.

## Unreleased
- (add entries here)

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
