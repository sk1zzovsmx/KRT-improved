# Lua Writing Rules

Canonical writing rules for KRT-owned Lua code.

Scope:
- `!KRT/**/*.lua`, excluding vendored libraries under `!KRT/Libs/**`
- `tools/**/*.lua`
- `tests/**/*.lua`

Goal:
- unify syntax, naming, layout, and lint workflow for repo-owned Lua
- keep public APIs predictable across Controllers, Services, Widgets, Core, and Modules
- translate generic WoW addon guidance into KRT-specific rules without changing runtime behavior

## 1. KRT Overrides for Generic WoW Guidance

KRT uses generic WoW addon guidance as rationale, not as a literal project spec.

Adopted from generic WoW practice:
- zero accidental globals
- addon-prefixed frame and XML globals
- caching of frequently used globals in hot paths when it improves readability or cost
- formatter vs lint separation
- secure/UI review guidance around taint, hooks, and combat lockdown

Not adopted as KRT standard:
- `local ADDON_NAME, NS = ...`
- 2-space indentation
- new Ace2/Ace3 or AceLocale dependencies
- CI-first lint rollout
- generated `wow_read_globals.lua` as a required dependency
- Selene in phase 1

KRT-specific overrides:
- use `local addon = select(2, ...)` and `local feature = addon.Core.GetFeatureShared()`
- use 4 spaces
- keep `180` as the hard formatter limit and `120` as the editorial target
- use local gates and the repo-local pre-commit hook, not a CI blocking gate
- route user-facing strings through `addon.L` and diagnose templates through `addon.Diagnose`

## 2. File Contract

Use this header in KRT-owned addon files:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()
```

Feature files under `Controllers/`, `Services/`, `Widgets/`, and `EntryPoints/`
should keep this top-level section order:

1. `-- ----- Internal state ----- --`
2. `-- ----- Private helpers ----- --`
3. `-- ----- Public methods ----- --`

Prefer one local `UI` table for module-local UI state and hooks:

- `UI.AcquireRefs`
- `UI.BindHandlers`
- `UI.Localize`
- `UI.Refresh`

## 3. Naming

### 3.1 Public and cross-module APIs

Use `PascalCase` for:

- `module:*` methods exposed on Controllers, Services, Widgets, and EntryPoints
- infra namespaces such as `Core`, `Bus`, `Frames`, `UIScaffold`, `UI`,
  `ListController`, `MultiSelect`, `Strings`, `Time`, `Comms`, `Base64`,
  `Colors`, `Item`, and `Sort`
- structured sub-owners such as `Store:*`, `View:*`, `Actions:*`, and `Box:*`
- module-local UI contract tables such as `UI.AcquireRefs`

Examples:

- `module:GetDisplayModel()`
- `module:SetImportMode(mode, syncOptions)`
- `Core.GetRaidStoreOrNil(tag, requiredMethods)`
- `UI.Refresh()`

### 3.2 Private and file-local names

Use `camelCase` for:

- `local function ...`
- forward-declared local helpers
- closure-local callbacks
- temporary variables, caches, flags, and parser internals

Examples:

- `local function getRollSession()`
- `local function normalizeCandidateKey(name)`
- `local pendingDisplayRefreshHandle`

Do not introduce new snake_case helper names for local/private code.

### 3.3 Allowed exceptions

Keep WoW-required event handlers in WoW naming:

- `ADDON_LOADED`
- `RAID_ROSTER_UPDATE`
- `CHAT_MSG_SYSTEM`

Keep constants in `UPPER_SNAKE_CASE`:

- `RESPONSE_STATUS`
- `PENDING_AWARD_TTL_SECONDS`

Keep Lua metamethod names unchanged:

- `__index`
- `__call`

Keep canonical UI hook names when they implement the scaffold/UI contract:

- `AcquireRefs`
- `BindHandlers`
- `Localize`
- `OnLoadFrame`
- `RefreshUI`
- `Refresh`

### 3.4 Public API verb taxonomy (binding for new/renamed APIs)

To keep API names readable and consistent, new or renamed public methods on
`addon.*` should start with one of these verb groups.

Query verbs:

- `Get*`
- `Find*`
- `Is*`
- `Can*`

Mutation verbs:

- `Set*`
- `Add*`
- `Remove*`
- `Delete*`
- `Upsert*`

Lifecycle/UI verbs:

- `Ensure*`
- `Bind*`
- `Localize*`
- `Request*`
- `RequestRefresh*`
- `Refresh*`
- `Toggle*`
- `Show*`
- `Hide*`

Allowed exact lifecycle names:

- `OnLoad`
- `OnLoadFrame`
- `AcquireRefs`
- `BindHandlers`
- `RefreshUI`
- `Refresh`
- `RequestRefresh`
- `Toggle`
- `Show`
- `Hide`

UPPER WoW event handlers stay valid (`ADDON_LOADED`, `RAID_ROSTER_UPDATE`,
`CHAT_MSG_SYSTEM`, ...).

## 4. Function Declaration and Call Style

Use `:` only for true methods that expect `self`.

Examples:

- `function module:Refresh()`
- `function module:ValidateWinner(playerName, itemLink, rollType)`

Use `.` for plain functions that do not expect `self`.

Examples:

- `function Core.GetController(name)`
- `function UIScaffold.DefineModuleUi(cfg)`

Prefer `local function helperName(...)` for file-local helpers.

Only use forward declarations when recursion or ordering requires them:

```lua
local assignItem

function assignItem(itemLink, playerName, rollType, rollValue)
    ...
end
```

Do not mechanically convert `.` and `:` call sites. Verify the declaration
signature first, then update call sites intentionally.

## 5. Formatting

Non-negotiables:

- Lua runtime: 5.1 / WoW 3.3.5a
- indentation: 4 spaces
- line endings: LF
- no trailing whitespace
- prefer ASCII in code, comments, and log text
- let Stylua own spacing, quotes, and comma layout

Line width policy:

- target: keep new and edited code near 120 columns
- hard formatter limit: 180 columns
- do not mass-reflow untouched legacy files just to hit 120

The repo prioritizes stable diffs over cosmetic rewrites.

## 6. WoW Compatibility Checklist

These rules come from WoW runtime constraints and are review expectations, not
phase-1 automatic lint gates.

- Keep accidental globals at zero. Only addon globals, XML frame globals, and
  declared SavedVariables may escape `local`.
- Prefer addon-prefixed frame names and XML IDs for anything that becomes global.
- Respect `.toc` load order, TOC file-list integrity, and existing SavedVariables
  contracts.
- Prefer `hooksecurefunc` or `HookScript` over direct overrides when a hook is
  sufficient.
- Avoid protected frame mutations in combat unless the code explicitly guards or
  defers with `InCombatLockdown()`.
- Prefer cached locals in hot paths when the code is event-heavy or called often.
- Keep Services free of Parent frame ownership and direct UI mutations.

## 7. Tooling

Use these local gates:

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1`
2. `luacheck --codes --no-color !KRT tools tests`
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1`
4. `stylua --check !KRT tools tests`

Local hook workflow:

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/install-hooks.ps1`
2. commit normally; the repo-local pre-commit hook runs staged Lua checks in
   check mode and keeps existing tree/layering checks

Tool ownership:

- `.stylua.toml`: formatter contract
- `.luacheckrc`: globals, WoW API allowances, and warning policy
- `tools/check-toc-files.ps1`: verify TOC naming and that listed files exist
- `tools/check-lua-syntax.ps1`: syntax-only validation for all Lua files
- `tools/check-lua-uniformity.ps1`: repo-specific structural and naming rules
- `tools/check-api-nomenclature.ps1`: staged public API case + verb-taxonomy check
- `docs/DEV_CHECKS.md`: copy-paste verification commands and audit greps

Do not add a style rule that cannot be explained by one of those sources.

## 8. Rollout Policy

Apply style unification incrementally, but keep the repo green after the sweep.

Rules:

1. New files should comply fully.
2. Touched files should move toward the canonical style in the touched area.
3. Do not mass-rename stable public APIs without a migration reason.
4. For public API renames, add a temporary alias, migrate call sites, then remove
   the alias after zero legacy hits.
5. Prefer deterministic renames over compatibility shims that keep two styles
   alive indefinitely.
6. Treat WoW compatibility items as review gates even when they are not yet
   automatic lint rules.

Practical sweep order:

1. make `stylua --check` green
2. align private helper naming
3. align file structure and UI lifecycle vocabulary
4. clean up only the most useful over-120 lines

This keeps behavior stable while reducing style drift where it hurts
maintainability the most.
