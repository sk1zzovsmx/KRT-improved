# Dev Checks

Quick copy-paste checks for layering, UI binding, Lua quality, and release hardening.

Primary entrypoint: `tools/krt.py`.
Use direct `*.ps1` scripts only when you need script-level control.
Examples below assume repo root. If you launch from inside `!KRT/` or another repo subfolder,
adjust the path to `tools/krt.py` relative to your current directory; `run-*` wrappers resolve their
input paths from the directory where you launch the command.

## 1) Fast Checks via `tools/krt.py`

Linux/macOS shell:

```bash
python3 tools/krt.py repo-quality-check --check all
python3 tools/krt.py repo-quality-check --check toc_files
python3 tools/krt.py repo-quality-check --check lua_syntax
python3 tools/krt.py repo-quality-check --check lua_uniformity
python3 tools/krt.py repo-quality-check --check api_nomenclature
python3 tools/krt.py repo-quality-check --check layering
python3 tools/krt.py repo-quality-check --check retired_aliases
python3 tools/krt.py repo-quality-check --check ui_binding
python3 tools/krt.py repo-quality-check --check raid_hardening
```

Windows PowerShell:

```powershell
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check api_nomenclature
py -3 tools/krt.py repo-quality-check --check layering
py -3 tools/krt.py repo-quality-check --check retired_aliases
py -3 tools/krt.py repo-quality-check --check ui_binding
py -3 tools/krt.py repo-quality-check --check raid_hardening
py -3 tools/krt.py api-catalog-check
```

Expected: each command exits `0` and prints `... passed.` from the wrapped script.
`lua_uniformity` now also verifies the full KRT Lua Contract on KRT-owned addon Lua,
the static-dataset `Public methods` exception, absence of `feature.* or addon.*`
fallbacks, `addon.options` confinement, allowed `OnUpdate` locations, and basic
WotLK/Lua 5.1 compatibility patterns.

## 2) Common Runs via `tools/krt.py`

```powershell
py -3 tools/krt.py run-release-targeted-tests
py -3 tools/krt.py run-sv-roundtrip --fixtures
py -3 tools/krt.py run-raid-validator --saved-variables-path "WTF\Account\<Account>\SavedVariables\!KRT.lua"
py -3 tools/krt.py run-sv-inspector --saved-variables-path "WTF\Account\<Account>\SavedVariables\!KRT.lua" --format table --section baseline
```

Use direct PowerShell only when you need to pass the native script parameters exactly as-is.

## 2.1 API Catalog Refresh

Use this sequence before and after API cleanup waves:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1 -MaxDepth 4
py -3 tools/krt.py repo-quality-check --check all
```

Preferred one-command refresh:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

CI drift check. It may regenerate identical catalog outputs before comparing, but should leave no
tracked diff when the repo is already up to date:

```powershell
py -3 tools/krt.py api-catalog-check
```

Run the `fnmap` steps sequentially in that order when using direct scripts.
`fnmap-classify.ps1` depends on the fresh CSV written by `fnmap-inventory.ps1`,
so parallel runs can produce stale catalogs.

Expected:

- `docs/FUNCTION_REGISTRY.csv` refreshed
- `docs/FN_CLUSTERS.md` refreshed
- `docs/API_REGISTRY*.csv` and `docs/API_NOMENCLATURE_CENSUS.md` refreshed
- `docs/TREE.md` refreshed
- repo-level static checks still pass after the contraction

## 3) Direct PowerShell Equivalents

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-api-nomenclature.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-layering.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-retired-aliases.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-ui-binding.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-raid-hardening.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-roundtrip.ps1 -Fixtures
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-raid-validator.ps1 "WTF\Account\<Account>\SavedVariables\!KRT.lua"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-sv-inspector.ps1 "WTF\Account\<Account>\SavedVariables\!KRT.lua" -Format table -Section baseline
```

Extra gates:

```powershell
luacheck --codes --no-color !KRT tools tests
stylua --check !KRT tools tests
```

## 4) Layering and Ownership Spot Checks

`rg` version:

```powershell
rg "addon\.(Master|Logger|Warnings|Changes|Spammer)" -n !KRT/Services -g "*.lua"
rg "addon\.(Raid|Chat|Master|Logger|LootCounter|ReservesUI|Config|Warnings|Changes|Spammer|Loot|Rolls)" `
  -n !KRT -g "*.lua" -g "!Libs/**"
rg "CreateFrame|SetScript|:Show\(|:Hide\(" -n !KRT/Services -g "*.lua" -g "!Loot.lua"
rg "feature\.[A-Za-z_][A-Za-z0-9_]*\s+or\s+addon\.|addon\.[A-Za-z_][A-Za-z0-9_]*\s+or\s+feature\." `
  -n !KRT -g "*.lua" -g "!Libs/**"
rg "addon\.options" -n !KRT -g "*.lua" -g "!Libs/**"
rg "OnUpdate" -n !KRT -g "*.lua" -g "!Libs/**"
rg "<Scripts>|<On[A-Za-z]+>" -n !KRT/UI -g "*.xml"
rg "PROTOCOL_VERSION|MSG_SNAPSHOT|MSG_ROLL_TICK|MSG_TIE_START|MSG_AWARDED" `
  -n !KRT/Services/Loot/DistributionSession.lua
```

Fallback when `rg` is unavailable:

```powershell
Get-ChildItem -Recurse !KRT/Services -Filter *.lua |
  Select-String -Pattern "addon\.(Master|Logger|Warnings|Changes|Spammer)"

Get-ChildItem -Recurse !KRT/Services -Filter *.lua |
  Where-Object { $_.Name -ne "Loot.lua" } |
  Select-String -Pattern "CreateFrame|SetScript|:Show\(|:Hide\("

Get-ChildItem -Recurse !KRT -Filter *.lua |
  Where-Object { $_.FullName -notmatch "\\!KRT\\Libs\\" } |
  Select-String -Pattern "feature\.[A-Za-z_][A-Za-z0-9_]*\s+or\s+addon\.|addon\.[A-Za-z_][A-Za-z0-9_]*\s+or\s+feature\."

Get-ChildItem -Recurse !KRT/UI -Filter *.xml |
  Select-String -Pattern "<Scripts>|<On[A-Za-z]+>"
```

## 5) Release-Path Checks

```powershell
py -3 tools/krt.py release-metadata --json
py -3 tools/krt.py release-publish-gate --previous-ref HEAD^ --json
py -3 tools/krt.py release-prepare --current-ref HEAD --output-dir dist --json
py -3 tools/krt.py release-notes --current-ref HEAD --output-file dist/release-notes.md
py -3 tools/krt.py build-release-zip --output-dir dist --write-checksum
```

Expected:

- metadata resolves from `!KRT/CHANGELOG.md` + `!KRT/!KRT.toc`
- publish gate accepts only strictly increasing publishable SemVer versions
- `release-prepare` emits the standard release bundle used by CI
- release notes render concise `Included Commits`, `New Functionality`,
  and `Enhancements/Improvement` sections, with commit short hashes included
- archive contains only `!KRT/`

## 6) Hook Setup

```powershell
py -3 tools/krt.py install-hooks
py -3 tools/krt.py pre-commit
```

Expected: `core.hooksPath=.githooks` and clean local pre-commit output.
