# Git Hooks

KRT uses a repository-local pre-commit hook for layering hygiene, UI binding checks,
Lua gates, and generated tree docs.

Enable once per clone:

```powershell
py -3 tools/krt.py install-hooks
```

Linux:

```bash
python3 tools/krt.py install-hooks
```

The hook runs:
- `tools/check-toc-files.ps1`
- `tools/check-layering.ps1`
- `tools/check-ui-binding.ps1`
- staged Lua gates in check-only mode, when staged `.lua` files exist:
  - `tools/check-lua-syntax.ps1`
  - `luacheck --codes --no-color !KRT tools tests`
  - `tools/check-lua-uniformity.ps1`
  - `stylua --check !KRT tools tests`
- `tools/update-tree.ps1`

`docs/TREE.md` is auto-staged by the hook.

`tools/check-layering.ps1` prefers `rg` when available and falls back to `Select-String` if `rg` is missing.

The hook now enters through `tools/krt.py pre-commit`, which keeps the hook bootstrap consistent across
Windows and Linux. The underlying validation flow still uses the existing PowerShell gate scripts.
