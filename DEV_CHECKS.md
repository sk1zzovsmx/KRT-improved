# Dev Checks

Quick, copy-paste checks for layering and ownership rules.
If `rg` is missing on Windows, run `tools/check-layering.ps1` (it falls back to `Select-String`).

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
rg "addon\\.Master\\.frame|_G\\[\"KRTMaster\"\\]" -n !KRT/KRT.lua
```
Expected: `0 match`

5. Core must not touch any Parent frame internals:
```powershell
rg "_G\\[\"KRT(Master|Logger|Warnings|Changes|Spammer)\"\\]" -n !KRT/KRT.lua
rg "addon\\.(Master|Logger|Warnings|Changes|Spammer)\\.frame" -n !KRT/KRT.lua
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

10. `Core.getFeatureShared` must not be redefined in `KRT.lua`:
```powershell
rg "function\\s+Core\\.getFeatureShared" -n !KRT/KRT.lua
```
Expected: `0 match`

11. `ensureLootRuntimeState` canonical owner is `Core/Init.lua` only:
```powershell
rg "local\\s+function\\s+ensureLootRuntimeState|function\\s+Core\\.ensureLootRuntimeState" -n !KRT/KRT.lua
```
Expected: `0 match`

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

14. UIBinder should not reintroduce `splitArgs` local helper naming collision:
```powershell
rg "local\\s+function\\s+splitArgs\\s*\\(" -n !KRT/Modules/UIBinder.lua
```
Expected: `0 match`
