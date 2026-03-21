# KRT Overview

Purpose: quick navigation for contributors who need the current addon shape
without reading full binding policy first.

For binding rules and architectural constraints, use:
- `AGENTS.md`
- `docs/ARCHITECTURE.md`

## At A Glance

- Runtime target: WoW 3.3.5a, Lua 5.1.
- Addon root: `!KRT/`.
- Unified bootstrap and shared runtime ownership live in `!KRT/Init.lua`.
- Runtime code is split into `Controllers/`, `Services/`, `Widgets/`, and
  `EntryPoints/`.
- Shared infrastructure lives in `!KRT/Modules/`.
- XML stays layout-only under `!KRT/UI/` and is loaded via `!KRT/KRT.xml`.
- Persisted state is declared in `!KRT/!KRT.toc` through `KRT_*`
  SavedVariables.

## Current Module Layout

- `!KRT/Controllers/*.lua`
  Parent owners such as `Master`, `Logger`, `Warnings`, `Changes`, `Spammer`.
- `!KRT/Services/*.lua`
  Runtime data/model logic such as `Raid`, `Chat`, `Rolls`, `Loot`,
  `Reserves`.
- `!KRT/Widgets/*.lua`
  Feature UI controllers such as `LootCounter`, `ReservesUI`, `Config`.
- `!KRT/EntryPoints/*.lua`
  User entrypoints such as slash routing and minimap behavior.
- `!KRT/Modules/*.lua`
  Shared infra modules such as `Bus`, `Strings`, `Item`, `Time`, `Sort`,
  `Base64`, `Colors`, `Frames`, `UIScaffold`, `ListController`, and
  `MultiSelect`.

## Runtime Rules That Matter Most

- Services stay UI-free and do not touch Parent frames.
- Upward communication goes through `addon.Bus`.
- EntryPoints may call `Parent:Toggle()` directly.
- Public APIs use `PascalCase`; private helpers use `camelCase`.
- XML does not own logic through inline `<Scripts>` or `<On...>` handlers.

## Fast References

- Lua rules and local gates: `docs/LUA_WRITING_RULES.md`
- Layering map and repo-local automation: `docs/ARCHITECTURE.md`
- Copy-paste checks: `docs/DEV_CHECKS.md`
- SavedVariables inventory: `docs/SV_SCHEMA.md`
- Raid schema contract: `docs/RAID_SCHEMA.md`
