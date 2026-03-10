# Dev Checks

Quick, copy-paste checks for layering and ownership rules.
If `rg` is missing on Windows, run `tools/check-layering.ps1` (it falls back to `Select-String`).
See `tools/README.md` for the current tool-family index.

## Lua syntax + uniformity (local gate)

These checks are local-only. No CI blocking gate is configured.

1. TOC naming and file-list check:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
```
Expected: `TOC file checks passed.`

2. Syntax check for all Lua files (including vendored libs):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```
Expected: `Lua syntax check passed.`

3. Lint check for KRT-owned Lua:
```powershell
luacheck --codes --no-color !KRT tools tests
```
Expected: `0 warnings / 0 errors`

4. Uniformity check for KRT-owned Lua (`!KRT`, `tools`, `tests`,
excluding `!KRT/Libs`):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1
```
Expected: `Lua uniformity checks passed.`
This includes canonical public naming and private helper naming checks.

5. Formatter check for KRT-owned Lua:
```powershell
stylua --check !KRT tools tests
```
Expected: no diff output

6. Install the repo-local hook once per clone:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/install-hooks.ps1
```
Expected: `Configured core.hooksPath=.githooks`

7. Targeted stabilization gate for `Services/Rolls.lua` and
`Controllers/Master.lua` changes:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```
Expected: tests pass, or an explicit runtime-missing skip message when
`lua`/`luajit` is not installed.

## WoW-specific audit greps (manual review)

1. Secure templates, `SetAttribute`, and combat guard coverage:
```powershell
rg ":SetAttribute\\(" -n !KRT -g "*.lua" -g "*.xml"
rg "Secure(Action|Handler|State)|SecureTemplates" -n !KRT -g "*.lua" -g "*.xml"
rg "\\bInCombatLockdown\\b|\\bPLAYER_REGEN_(DISABLED|ENABLED)\\b" -n !KRT -g "*.lua"
```
Expected: review manually; secure mutations should be guarded or deferred.

2. `OnUpdate` hotspots and high-frequency UI work:
```powershell
rg "SetScript\\(\"OnUpdate\"|\\bOnUpdate\\b" -n !KRT -g "*.lua" -g "*.xml"
```
Expected: review manually; recurring updates should be throttled or event-driven.

3. Hooking vs direct overrides:
```powershell
rg "hooksecurefunc|:HookScript\\(" -n !KRT -g "*.lua"
rg "^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*function\\s*\\(" -n !KRT -g "*.lua"
```
Expected: review manually; prefer safe hooks, scrutinize global direct overrides.

4. Global-env and named-frame scan:
```powershell
rg "CreateFrame\\([^,]+,\\s*\"[A-Za-z0-9_]+\"" -n !KRT -g "*.lua"
rg "\\b_G\\b|\\bgetglobal\\b|\\brawset\\(_G\\b" -n !KRT -g "*.lua"
```
Expected: review manually; named globals should stay addon-prefixed and intentional.

## Lua audit greps (manual review)

1. Private helper naming audit:
```powershell
rg "^\s*local\s+function\s+[A-Z]" -n !KRT tools tests -g "*.lua"
rg "^\s*function\s+[A-Z][A-Za-z0-9_]*\s*\(" -n !KRT tools tests -g "*.lua"
```
Expected: `0 match` outside allowed UI hook exceptions and vendored code.

2. Suspicious dot-call with explicit `self`:
```powershell
rg "\b[A-Za-z0-9_]+\.[A-Za-z0-9_]+\(\s*self\b" -n !KRT -g "*.lua"
```
Expected: review manually; often indicates a method still called with dot+self.

3. Suspicious colon-call on infra namespaces that should stay plain-function APIs:
```powershell
rg "\b(Core|Bus|Frames|UIScaffold|ListController|MultiSelect|UI|Strings|Time|Comms|Base64|Colors|Item|Sort):[A-Z][A-Za-z0-9_]*\(" -n !KRT -g "*.lua"
```
Expected: review manually; infra namespaces normally use `.` not `:`.

4. Bare function declarations:
```powershell
rg "^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\s*\(" -n !KRT -g "*.lua"
```
Expected: review manually; these should normally be local forward-declared helpers,
not accidental globals.

## Layering checks

1. Services must not reference Parents directly:
```powershell
rg "addon\.(Master|Logger|Warnings|Changes|Spammer)" -n !KRT/Services -g "*.lua"
```
Expected: `0 match`

2. Services must not touch parent frames or hook parent methods:
```powershell
rg "_G\\[\"KRT|addon\\.[A-Za-z]+\\.frame|hooksecurefunc\\(addon\\." -n !KRT/Services -g "*.lua"
```
Expected: `0 match`

3. Services should avoid direct UI frame APIs (allow tooltip probes in `Services/Loot.lua`):
```powershell
rg "CreateFrame|SetScript|:Show\\(|:Hide\\(" -n !KRT/Services -g "*.lua" -g "!Loot.lua"
```
Expected: `0 match`

4. Core must not reference Master frame ownership internals:
```powershell
rg "addon\\.Master\\.frame|_G\\[\"KRTMaster\"\\]" -n !KRT/Init.lua
```
Expected: `0 match`

5. Core must not touch any Parent frame internals:
```powershell
rg "_G\\[\"KRT(Master|Logger|Warnings|Changes|Spammer)\"\\]" -n !KRT/Init.lua
rg "addon\\.(Master|Logger|Warnings|Changes|Spammer)\\.frame" -n !KRT/Init.lua
```
Expected: `0 match`

6. No `hooksecurefunc(addon.Master, "OnLoad", ...)` anywhere:
```powershell
rg "hooksecurefunc\\(addon\\.Master\\s*,\\s*\"OnLoad\"" -n !KRT
```
Expected: `0 match`

7. No legacy Reserves Import module references:
```powershell
rg "addon\\.Reserves[I]mport" -n
```
Expected: `0 match`

8. No stale `Features/` paths inside addon runtime files:
```powershell
rg "Features/" -n !KRT
```
Expected: `0 match`

9. Parent exception check: only entrypoints may call `Parent:Toggle()`:
```powershell
rg ":Toggle\\(" -n !KRT/Services !KRT/Widgets !KRT/Controllers
```
Expected: review manually; parent toggles should not be introduced in Services.

## Function unification regression checks

10. `Core.GetFeatureShared` canonical owner is `Init.lua` only:
```powershell
rg "function\\s+Core\\.(GetFeatureShared|getFeatureShared)" -n !KRT -g "*.lua"
```
Expected: one hit in `!KRT/Init.lua`

11. `EnsureLootRuntimeState` canonical owner is `Init.lua` only:
```powershell
rg "function\\s+Core\\.(EnsureLootRuntimeState|ensureLootRuntimeState)" -n !KRT -g "*.lua"
```
Expected: one hit in `!KRT/Init.lua`

12. Reserves formatter helpers should not be duplicated in widget locals:
```powershell
rg "local\\s+function\\s+FormatReserve(ItemIdLabel|ItemFallback|DroppedBy)" -n !KRT/Widgets/ReservesUI.lua
```
Expected: `0 match`

13. EntryPoints should not re-introduce per-controller getter duplicates:
```powershell
rg "local\\s+function\\s+get(Master|Logger|Warnings|Changes|Spammer)Controller" -n !KRT/EntryPoints -g "*.lua"
```
Expected: `0 match`
