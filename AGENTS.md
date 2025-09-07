# **KRT – AGENTS.md** (WoW 3.3.5a · Lua 5.1)

**Context file for AI coding agents.** Lives at repo root. Short lines (≤ 120 chars). Keep this current.
Guidelines are **non‑binding**; prefer existing code patterns when in doubt.

---

## 1) Purpose
Provide raid‑lead QoL tools for WotLK 3.3.5a: loot rolls (MS/OS/SR), reserve tracking (SR), loot history/log,
master‑loot helpers, LFM spammer, warnings/announcements, and export/import utilities.
No Ace3 GUI; UI is XML + Lua only. Vendored libs via **LibStub**.

---

## 2) Hard constraints (please keep stable unless explicitly changed)
- **Client/API:** Wrath of the Lich King **3.3.5a** (Interface **30300**), **Lua 5.1** runtime.
- **Addon folder name:** `!KRT` (the leading `!` is intentional).
- **SavedVariables (account):**
  `KRT_Options, KRT_Raids, KRT_Players, KRT_Warnings, KRT_ExportString, KRT_Spammer, KRT_CurrentRaid,`
  `KRT_LastBoss, KRT_NextReset, KRT_SavedReserves, KRT_PlayerCounts, KRT_Debug`.
- **Branching model:** work **only** on `dev`. `main` is release‑only. Maintainers handle merges/bumping.
- **Backward compatibility:** avoid breaking SV keys and existing CLI without a note in **18) Change log**.
- **Structure:** keep addon monolithic; integrate features within `!KRT/` instead of split addons.

> If you need to change a hard constraint, edit this section and add a note in **18) Change log**.

---

## 3) Soft preferences (revisitable)
- **UI style:** XML + Lua frames; avoid new UI frameworks (e.g., Ace3) unless discussed first.
- **Code style:** single namespace table `addon`, localize aggressively, small functions, ≤120‑char lines.
- **Perf:** event‑driven over `OnUpdate`; reuse tables; throttle chat/log spam; avoid allocations in hot paths.
- **I18n:** all user text via `L[...]` from `Localization/`.

These are guidelines, not rules. Prefer existing patterns in the codebase when unsure.

---

## 4) Repo layout (monolithic)
```
!KRT/
  !KRT.toc                 # metadata (Interface 30300, SavedVariables, links)
  KRT.lua                  # main addon (core logic, modules & slash handlers)
  KRT.xml                  # frames & UI logic (main, logger, reserves, master, warnings, spammer, etc.)
  Templates.xml            # shared XML templates
  Localization/
    localization.en.lua    # enUS strings (L)
    # localization.it.lua  # optional future mirror
  Modules/                 # NOTE: directory name is Uppercase
    Utils.lua              # utility functions (table ops, color, formatting, etc.)
    bossList.lua           # boss id/name lists
    ignoredItems.lua       # item filter list
  Libs/                    # vendored libraries (LibStub–based)
    libs.xml
    CallbackHandler-1.0/
    LibBossIDs-1.0/
    LibCompat-1.0/
    LibDeformat-3.0/
    LibLogger-1.0/
    LibMath/
    LibStub/
    LibXML-1.0/
```

---

## 5) External libraries
- **LibStub** loader (lib registry)
- **CallbackHandler‑1.0** events/callbacks
- **LibCompat‑1.0** shims & safe WoW API helpers
- **LibLogger‑1.0** lightweight logger (can embed onto addon)
- **LibDeformat‑3.0** pattern‑based deformatting (parsing chat/loot lines)
- **LibBossIDs‑1.0** boss id/name lookup
- **LibXML‑1.0** optional runtime XML helpers
- **LibMath** tiny math helpers

*Guideline:* Embed via `LibStub("Name", true)`; treat missing libs gracefully; never hard‑require Ace3.

---

## 6) User‑visible commands
- **`/krt`**, **`/kraidtools`** — main entry. Subcommands (see localized help):
  - `config` (options), `warnings`, `log`, `reserves`, `changes`, `ach`, `lfm start|stop`

*Guideline:* Keep CLI surface stable; document new subcommands via help output and localization.

---

## 7) Module map (in `KRT.lua` unless stated)
- `addon.Raid`          — raid state, roster helpers
- `addon.Loot`          — loot events, history, export string
- `addon.Rolls`         — roll tracking (MS/OS/SR/Free/Bank/DE/Hold), sorting, winner logic
- `addon.Reserves`      — SR model (per‑item reserve counts), CSV import/export
- `addon.Warnings`      — announcements (RW/RAID/PARTY), templates & throttling
- `addon.Changes`       — main‑spec change collection/announce utilities
- `addon.Spammer`       — LFM spam helper (start/stop)
- `addon.UIMaster`      — frames for Master, Logger, Reserves, Changes, Warnings, Loot Counter (see `KRT.xml`)
- `addon.Config`        — options window & persisted settings
- `addon.Minimap`       — minimap button (toggle)
- `Modules/Utils.lua`   — helpers (tables/strings/colors, `WrapTextInColorCode`, etc.)
- `Localization/*.lua`  — strings table `addon.L`

*Guideline:* Keep globals scoped to `addon` (or `_G[...] = addon` where needed). Avoid introducing new globals.

---

## 8) Development setup (local)
- No build step. Copy `!KRT/` into `<WoW>/Interface/AddOns/` and `/reload`.
- Use a 3.3.5a client. Verify **Interface** matches 30300.
- Developer helpers:
  - Logging window **KRTLogger** (`KRT.xml`); LibLogger API is embedded onto `addon`.
  - Event hooks live in `KRT.lua` (search `RegisterEvents(...)`).
  - Useful in‑game tools: `/etrace`, `/dump`, and `/krt log`.

---

## 9) Coding & UI conventions
- Lua 5.1 only (no bit32, no `goto`, no `table.new`). Prefer `local` and single table namespace `addon.*`.
- Favor event‑driven code; avoid heavy `OnUpdate`. Throttle chat/announces.
- Reuse tables; prefer `table.wipe` over re‑alloc in hot paths (see `Utils`).
- XML: build widgets from `Templates.xml` and named frames in `KRT.xml`.
- UI text via `L[...]` only; avoid hardcoded strings.
- Do not add Ace3. Keep vendored libs minimal and updated.
- Lines ≤ 120 chars; keep functions short; group related private helpers in local blocks.
- Commit style: `feat(rolls): ...`, `fix(reserves): ...`, `ref(ui): ...`, `perf: ...`, `chore: ...`.

---

## 10) Testing checklist (manual)
- **Load:** no errors on login; `/krt` opens.
- **Raid events:** roll tracking works for MS/OS/SR; winners resolved deterministically.
- **Reserves:** CSV import/export round‑trips; per‑item caps apply; SR logic respected on roll gating.
- **Logger:** entries append correctly; filtering maintains order.
- **Warnings/Spammer:** throttle behavior; correct channels (RW/RAID/PARTY/WHISPER) and locale.
- **Persistency:** SavedVariables update; reload preserves settings/state.
- **Performance:** no GC spikes in combat; no taint; zero spam in chat/combatlog.

---

## 11) Security & compat
- No external I/O or networking beyond WoW API.
- Avoid taint: no secure frame manipulation in combat; defer via out‑of‑combat handlers.
- Guard locale and nils; never trust `Unit*` calls to succeed; use `LibCompat-1.0` iterators.
- Respect 3.3.5 API (no modern `C_Timer`, etc.). If you need timers, use `OnUpdate` with conservative throttle.

---

## 12) Localization
- Source of truth: `Localization/localization.en.lua`.
- New strings: add to `L[...]`; keep keys stable; avoid string concatenation in code paths.
- Future: optional `Localization/localization.it.lua` (mirror keyset).

---

## 13) Release & packaging
- Ship the folder **named exactly** `!KRT` with `!KRT.toc` at root.
- Keep `.toc` metadata updated (`Version`, `X-Date`, links).
- Exclude debug logs from releases.

---

## 14) Backlog (non‑binding, safe tasks)
- Reduce UI churn in Loot Logger/Counter via row pools and batched updates.
- Encapsulate recurring UI elements into small Lua factories (dropdowns, button rows, tooltips).
- Declarative builders for options to cut XML duplication.
- Improve SR CSV UX (empty‑state, error surfaces, success toast).
- Add `localization.it.lua`; extract remaining hardcoded help strings.

---

## 15) Do / Don’t
**Do:** keep changes small & testable; prefer composition over globals; log via `LibLogger`.
**Don’t:** introduce Ace3, block UI with long loops, or break `/krt` CLI stability.

---

## 16) Maintainers & links
- Upstream inspiration: https://github.com/bkader/KRT (MIT/X)
- In‑addon About page has contact links (Discord/Website).

---

## 17) Reference templates (optional)

Lua code skeletons in‑repo: If a templates folder exists (e.g., `TemplatesLua/`), treat it as optional, non‑binding
starting points (module skeleton, event listener, CLI sub‑command, logger usage). Prefer existing KRT patterns.

External guide: Lua Programming Development Guide — Agents.md examples collection.
https://github.com/gakeez/agents_md_collection/blob/main/examples/lua-programming-development.md

- Report issues with exact client build, steps, and SavedVariables snapshots.

---

## 18) Change log (edit by hand)
- _2025‑09‑05_: Initial lightweight version; removed binding “recipes”. Added `dev`‑only branching policy.
- _2025-09-07_: Clarified monolithic structure and updated CLI command list.
