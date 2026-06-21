# Spec Role Inspector Design

## Status

Revised design pending user review. No runtime code is implemented by this document.

## Goal

Add spec icons next to player names in the Master Loot roll list and Loot Counter rows.
Specs are read from `LibGroupTalents-1.0`, refreshed opportunistically on ready check, and
cached by KRT for the current addon session.

## Scope

- Show a spec icon beside each player name in the Master Loot roll list.
- Show a spec icon beside each player name in the Loot Counter.
- Refresh spec data for the current raid when a ready check starts, without requesting a library
  talent refresh for every cached player by default.
- Add a slash command to force a library talent refresh pass when the user explicitly wants one.
- Keep the feature compatible with WotLK 3.3.5a, Interface 30300, and Lua 5.1.

## Non-Goals

- Do not persist spec data in SavedVariables.
- Do not inspect continuously during UI refresh.
- Do not refresh every raid member through the talent library on every ready check unless
  explicitly forced.
- Do not call `NotifyInspect` directly from KRT for this feature; delegate talent refresh work to
  `LibGroupTalents-1.0`.
- Do not add Ace2 or Ace3 dependencies.
- Do not add spec icons to Logger, Reserves, Raid Grid, or other player lists in this change.
- Do not make loot decisions automatically from spec or role.

## User Experience

Before the first ready check, player rows may have no spec icon. When a ready check starts, KRT
refreshes the current raid from `LibGroupTalents` cache first, then asks the library to refresh only
players that need new talent data. Icons appear progressively as data becomes available.

If a player changes spec between ready checks and `LibGroupTalents` reports the change, KRT updates
the icon from the library callback. If the cache is stale or the user wants a fresh pass,
`/krt specinspect force` asks `LibGroupTalents` to refresh all inspectable raid members. If the
player cannot be inspected, the UI remains usable and keeps any previous runtime cache value until a
later refresh succeeds.

The icon should be compact and stable:

- Master Loot uses a small texture to the left of the player name.
- Loot Counter uses a matching texture to the left of the player name.
- Rows should reserve enough name-column space so text does not jump while icons appear.
- A tooltip may show the spec name and role when known.

## Architecture

Add a runtime service under `addon.Services.SpecInspect`.

Responsibilities:

- Listen for the WoW ready-check trigger.
- Build a refresh candidate list from the current raid roster.
- Resolve each player to a unit with `addon.Services.Raid:GetUnitID(name)`.
- Use `LibGroupTalents-1.0` as the primary source for spec, tree icon, and role.
- Ask `LibGroupTalents-1.0` to refresh talent data instead of owning a KRT inspect queue.
- Cache the latest runtime result by normalized player name and, where available, GUID.
- Emit an internal KRT event when a player's spec data changes.
- Expose a narrow API for slash commands to request a normal or forced refresh.

The service must stay UI-free. It returns display data such as:

- `specId`
- `specName`
- `icon`
- `role`
- `class`
- `updatedAt`
- `lastTalentRefreshAt`
- `refreshReason`

Controllers and widgets consume the service and render icons.

## Acquisition Method

KRT should use `LibGroupTalents-1.0` directly as the talent/spec source:

- `LGT:GetUnitTalentSpec(unit)` or `LGT:GetGUIDTalentSpec(guid)` returns the active dominant spec
  and the point totals for the three talent trees.
- `LGT:GetTalentTabInfo(unit, tab, group)` returns the tree name and tree icon for the selected
  dominant tab.
- `LGT:GetUnitRole(unit)` returns one of `tank`, `healer`, `melee`, or `caster`.
- `LGT:RefreshTalentsByUnit(unit)` requests a refresh through the library's own inspect queue.

KRT normalizes role values for display and future contracts:

- `tank` -> `TANK`
- `healer` -> `HEALER`
- `melee` -> `DAMAGER`
- `caster` -> `DAMAGER`

The dominant tab is derived from the point totals returned by `GetUnitTalentSpec`. The stable display
contract is `specName`, `icon`, and normalized `role`. `specId` is optional metadata only when KRT can
resolve it safely. When points tie or the spec is unknown, KRT should keep the previous cache entry if
present; otherwise it hides the icon.

KRT may use `LibCompat-1.0` only as an optional fallback for spec-id metadata. It should not use
`LibCompat.GetSpecializationInfoByID` as the authoritative role source because the vendored mapping
contains suspicious role entries for some specs. `LibGroupTalents:GetUnitRole` is the preferred role
source.

KRT listens to these library callbacks when available:

- `LibGroupTalents_Update`
- `LibGroupTalents_RoleChange`
- `LibGroupTalents_UpdateComplete`

Those callbacks update KRT's runtime cache and emit the KRT-level `SpecInspectUpdated` event for UI
refreshes.

## Data Flow

1. A ready check starts.
2. `SpecInspect` clears any stale pending work and scans the current raid roster.
3. For each player, the service first reads known data from `LibGroupTalents`.
4. If the known data is enough, the runtime cache is updated without requesting a refresh.
5. Players still missing usable data, or whose KRT cache is stale, are passed to
   `LGT:RefreshTalentsByUnit(unit)`.
6. `LibGroupTalents` owns the actual inspect queue, throttling, and opportunistic inspect handling.
7. When library callbacks arrive, KRT recomputes the active spec snapshot and icon.
8. `SpecInspectUpdated` is emitted when a player's visible spec snapshot changes.
9. Master Loot and Loot Counter request refresh and redraw the affected rows.

## Refresh Policy

Ready-check refresh is intentionally conservative. It should request a library talent refresh only
when one of these conditions is true:

- the player has no runtime cache entry
- the cached entry has no usable `specName` or `icon`
- the player's GUID changed for the cached name
- the entry is older than the configured stale threshold
- the previous talent refresh failed and its retry cooldown has expired

The stale threshold should be long enough to avoid refreshing the full raid repeatedly during a loot
session. A reasonable initial value is 30 minutes. This means ready checks keep icons current for
missing or stale players, while avoiding a full talent refresh pass every time.

Forced refresh ignores the stale threshold and calls `LGT:RefreshTalentsByUnit(unit)` for all
inspectable raid members.

## Slash Command

Add a local command owned by `EntryPoints/SlashEvents.lua`:

- `/krt specinspect`: request a normal refresh using the ready-check policy.
- `/krt inspectspec`: alias for the same normal refresh.
- `/krt specinspect force`: force a full talent refresh of inspectable raid members.

The command should print a concise localized summary, for example queued count and skipped count.
It should not spam per-player messages.

## UI Integration

### Master Loot

`KRTSelectPlayerTemplate` should gain a named texture part for the spec icon. The existing winner
star remains visible, but its position must be coordinated with the new icon. The preferred layout is
spec icon at the far left and winner star just to its right, followed by the player name.

The row renderer in `Modules/UI/Visuals.lua` reads `data.specIcon` or equivalent display fields and
shows or hides the icon.

### Loot Counter

`Widgets/LootCounter.lua` creates rows in Lua. Each row should create one `specIcon` texture during
row setup, reserve a fixed left slot, and anchor the name after that slot.

The refresh path reads the cached spec data for `data.name` and updates `row.specIcon`.

## Error Handling

- Missing unit: skip the player for the current pass and keep old runtime cache if present.
- Missing talent library: disable icon refresh gracefully and leave icons hidden.
- Talent refresh failure or timeout: keep old runtime cache if present and retry later.
- Offline or out-of-range player: skip until a later ready check.
- Unknown spec: hide the icon and avoid fallback-icon noise.
- Repeated force command: submit the latest forced request through `LibGroupTalents` and avoid
  separate KRT queue stacking.

All failures are recoverable. No user-facing warning should appear for ordinary inspect misses.
Diagnostics, if added, should use `addon.Diagnose`.

## Testing And Checks

Implementation should include source-level or Lua harness coverage for:

- `SpecInspect` service registration and public cache/query API.
- Ready-check refresh policy for missing, cached, stale, failed, and forced entries.
- `LibGroupTalents_Update` and `LibGroupTalents_RoleChange` cache update behavior.
- Slash command routing for normal and forced refresh requests.
- Master row rendering with known and unknown spec icons.
- Loot Counter row rendering with known and unknown spec icons.

Focused checks:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Because `Controllers/Master.lua` is likely to be touched, also run:

```powershell
lua tests/release_stabilization_spec.lua
```

Manual smoke:

- Join a raid on WotLK 3.3.5a.
- Open `/krt` and Loot Counter before a ready check; rows remain stable.
- Start a ready check; icons populate progressively.
- Change a player's spec and run `/krt specinspect force`; that player's icon updates.
- Confirm Master Loot winner star and spec icon do not overlap.

## Files Likely Involved

- `!KRT/Modules/Events.lua`
- `!KRT/Init.lua`
- `!KRT/Services/SpecInspect.lua`
- `!KRT/EntryPoints/SlashEvents.lua`
- `!KRT/!KRT.toc`
- `!KRT/UI/Templates/Common.xml`
- `!KRT/Modules/UI/Visuals.lua`
- `!KRT/Widgets/LootCounter.lua`
- `!KRT/CHANGELOG.md`
- focused tests under `tests/`

## Risks

- Inspect/talent APIs are asynchronous and may conflict with other addons using inspect.
- Some players may be unavailable during the ready check pass.
- A conservative stale threshold may not catch every spec change immediately.
- The Master Loot row is narrow, so icon and star spacing must be verified in-game.
- Private-server talent behavior may differ from stock WotLK, so failures must remain non-fatal.
