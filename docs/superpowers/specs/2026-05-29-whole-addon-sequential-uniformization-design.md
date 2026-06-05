# Whole Addon Sequential Uniformization Design

## Goal

Uniform KRT-owned code and docs without a risky big-bang rewrite. The work proceeds file by file in a stable
sequence, records measurable before/after state, and keeps runtime behavior unchanged unless a concrete defect is found.

## Scope

Included:

- `AGENTS.md`, project docs, tools, tests, and KRT-owned addon files under `!KRT/`.
- Runtime addon files in `!KRT/!KRT.toc` order after vendored libraries.
- Test and tool Lua files after runtime files, because they validate the runtime contract.

Excluded by default:

- Vendored libraries under `!KRT/Libs/*`.
- Static dataset churn that only reformats data without reducing risk or improving ownership.
- Backward-compatibility shims unless explicitly requested for a concrete compatibility target.

## Sequence Policy

The primary runtime queue is the non-vendored load order from `!KRT/!KRT.toc`.
For each file, the worker must decide one of three outcomes:

- `No change`: file already matches current standards or a change would be churn.
- `Local cleanup`: private naming, section order, small helper collapse, comments, or dead local cleanup.
- `Contract wave needed`: public API ownership, load order, or cross-file behavior needs a dedicated plan.

Do not skip ahead to large hotspots unless the current file reveals a shared blocking contract.

## File Review Checklist

Each file review checks:

- WoW 3.3.5a and Lua 5.1 compatibility.
- No new globals, Ace dependencies, modern `C_*` APIs, or vendored library edits.
- Canonical owner namespace and no retired root aliases.
- Public API names and private helper names match `docs/LUA_WRITING_RULES.md`.
- Controllers/widgets keep UI lifecycle under `UIScaffold` where feasible.
- Services stay UI-free and communicate upward via `addon.Bus`.
- User-facing strings use `addon.L`; diagnostics use `addon.Diagnose`.
- Refactors reduce code surface, duplicate contracts, or real ambiguity.

## Verification

After each small tranche:

- Run `py -3 tools/krt.py repo-quality-check --check all`.
- Run targeted tests when touched files have a known regression gate.
- Refresh API catalogs only when public/internal API surfaces change.
- Update architecture docs only when ownership, load order, or contracts change.

## First Tranche

The first tranche establishes the process and starts at the top of the non-vendored runtime queue:

- `AGENTS.md`
- `!KRT/Init.lua`
- `!KRT/Core/DB.lua`
- `!KRT/Core/Options.lua`
- `!KRT/Core/DBSchema.lua`
- `!KRT/Core/DBManager.lua`

This tranche should prefer audit notes and small local cleanups. Any proposed split of `Init.lua` or public Core contract
change must become a separate contract wave before runtime edits.
