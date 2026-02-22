# Git Hooks

KRT uses a repository-local pre-commit hook for layering hygiene and generated tree docs.

Enable once per clone:

```powershell
powershell -ExecutionPolicy Bypass -File tools/install-hooks.ps1
```

The hook runs:
- `tools/check-layering.ps1`
- `tools/update-tree.ps1`

`docs/TREE.md` is auto-staged by the hook.

`tools/check-layering.ps1` prefers `rg` when available and falls back to `Select-String` if `rg` is missing.
