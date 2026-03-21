# KRT MCP Server

This repository now ships a repo-local MCP server for addon development and skill maintenance.

The server is intentionally thin: it wraps the existing PowerShell tooling already used in this repo,
so there is a single execution path for humans and agents.

## What it exposes

- `dev_stack_status`
  - Read unified readiness for vendored skills, local Codex installs, Mechanic,
    and the repo-local MCP server.
- `skills_manifest`
  - Read the pinned manifest behind `.agents/skills`.
- `skills_verify`
  - Verify vendored skills against the pinned upstream commits.
- `skills_sync`
  - Sync vendored skills and optionally install them into a local Codex skills folder.
- `repo_quality_check`
  - Run repo-local checks such as `toc_files`, `lua_syntax`, `ui_binding`, `layering`,
    `raid_hardening`, and `lua_uniformity`.
- `mechanic_call`
  - Call the existing `tools/mech-krt.ps1` wrapper for `env.status`, addon validation,
    dead-code scans, lint, formatting, output, and similar Mechanic-backed flows.
- `mechanic_bootstrap`
  - Bootstrap or update the external Mechanic checkout used by repo-local wrappers.

## Start command

Use the PowerShell wrapper so the client does not need to know the Python path in advance:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-krt-mcp.ps1
```

The Python server lives at `tools/krt_mcp_server.py`.

## Optional environment overrides

- `KRT_LOCAL_SKILLS_ROOT`
  - Overrides the default local install target for `skills_sync installLocal=true`.
  - Default: `%USERPROFILE%\.codex\skills`
- `KRT_MECHANIC_ROOT`
  - Overrides the default bootstrap location used by `tools/mech-bootstrap.ps1`.
  - Default: `C:\dev\Mechanic`
- `KRT_MECHANIC_EXE`
  - Overrides the `mech.exe` path used by `tools/mech-krt.ps1` and `mechanic_call`.
  - Default: `C:\dev\Mechanic\desktop\.venv\Scripts\mech.exe`
- `KRT_POWERSHELL_EXE`
  - Overrides the PowerShell executable used by the Python MCP server.
  - Default: `powershell`

## Suggested workflow

1. Call `dev_stack_status` first.
2. Call `skills_manifest` to inspect the pinned skill sources.
3. Call `skills_verify` before editing repo docs or local tooling.
4. If vendored skills drift, call `skills_sync`.
5. If Mechanic is missing, call `mechanic_bootstrap`.
6. Run `repo_quality_check` for fast local checks that do not need Mechanic.
7. If Mechanic is ready, use `mechanic_call` for addon-aware validation and output.

## Notes

- The MCP server does not patch vendored skill content. It only reads the manifest or runs the existing sync
  script.
- `mechanic_call` depends on a local Mechanic install. Bootstrap it first with
  `mechanic_bootstrap` or `tools/mech-bootstrap.ps1` if needed.
- The server auto-detects current newline-delimited stdio framing and legacy `Content-Length` framing,
  which keeps it usable across older and newer MCP clients.
