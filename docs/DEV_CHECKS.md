# Dev Checks

Quick copy-paste checks for layering, UI binding, Lua quality, and release hardening.

Primary entrypoint: `tools/krt.py`.
Use direct `*.ps1` scripts only when you need script-level control.

## 1) Fast Checks via `tools/krt.py`

Linux/macOS shell:

```bash
python3 tools/krt.py repo-quality-check --check toc_files
python3 tools/krt.py repo-quality-check --check lua_syntax
python3 tools/krt.py repo-quality-check --check lua_uniformity
python3 tools/krt.py repo-quality-check --check api_nomenclature
python3 tools/krt.py repo-quality-check --check layering
python3 tools/krt.py repo-quality-check --check ui_binding
python3 tools/krt.py repo-quality-check --check raid_hardening
```

Windows PowerShell:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_syntax
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check api_nomenclature
py -3 tools/krt.py repo-quality-check --check layering
py -3 tools/krt.py repo-quality-check --check ui_binding
py -3 tools/krt.py repo-quality-check --check raid_hardening
```

Expected: each command exits `0` and prints `... passed.` from the wrapped script.

## 2) Direct PowerShell Equivalents

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-api-nomenclature.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-layering.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-ui-binding.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-raid-hardening.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-release-targeted-tests.ps1
```

Extra gates:

```powershell
luacheck --codes --no-color !KRT tools tests
stylua --check !KRT tools tests
```

## 3) Layering and Ownership Spot Checks

`rg` version:

```powershell
rg "addon\.(Master|Logger|Warnings|Changes|Spammer)" -n !KRT/Services -g "*.lua"
rg "CreateFrame|SetScript|:Show\(|:Hide\(" -n !KRT/Services -g "*.lua" -g "!Loot.lua"
rg "<Scripts>|<On[A-Za-z]+>" -n !KRT/UI -g "*.xml"
```

Fallback when `rg` is unavailable:

```powershell
Get-ChildItem -Recurse !KRT/Services -Filter *.lua |
  Select-String -Pattern "addon\.(Master|Logger|Warnings|Changes|Spammer)"

Get-ChildItem -Recurse !KRT/Services -Filter *.lua |
  Where-Object { $_.Name -ne "Loot.lua" } |
  Select-String -Pattern "CreateFrame|SetScript|:Show\(|:Hide\("

Get-ChildItem -Recurse !KRT/UI -Filter *.xml |
  Select-String -Pattern "<Scripts>|<On[A-Za-z]+>"
```

## 4) Release-Path Checks

```powershell
py -3 tools/krt.py release-metadata --json
py -3 tools/krt.py release-publish-gate --previous-ref HEAD^ --json
py -3 tools/krt.py build-release-zip --output-dir dist --write-checksum
```

Expected:

- metadata resolves from `!KRT/CHANGELOG.md` + `!KRT/!KRT.toc`
- publish gate blocks suffix-only releases when numeric version is unchanged
- archive contains only `!KRT/`

## 5) Hook Setup

```powershell
py -3 tools/krt.py install-hooks
py -3 tools/krt.py pre-commit
```

Expected: `core.hooksPath=.githooks` and clean local pre-commit output.
