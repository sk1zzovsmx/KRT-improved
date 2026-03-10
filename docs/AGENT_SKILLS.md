# Agent Skills Sync

This repository vendors selected AI skills under `.agents/skills` using an upstream-pure policy.

## Policy

- Keep imported skills identical to upstream source files.
- Do not patch or rewrite imported content, even when some relative links do not resolve in this repo.
- Pin every imported skill to an explicit commit SHA for deterministic sync.

## Source Of Truth

- Manifest: `tools/agent-skills.manifest.json`
- Script: `tools/sync-agent-skills.ps1`

The manifest defines:

- `version`
- `sources[]` entries with `skill`, `repo`, `commit`, `sourceBasePath`, `destinationPath`

## Pinned Sources

- `Falkicon/Mechanic` @ `41ef25dcfcd7c1450577b5826fbba9c571c7c75d`
- `lushly-dev/afd` @ `53084d96b61edc515cd85f64eec4aa514c68548d`

Managed skills:

- `s-clean`
- `s-audit`
- `s-debug`
- `s-working`
- `s-lint`
- `s-release`
- `k-docs`
- `afd`

## Commands

Sync skills into `.agents/skills` from pinned sources:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-agent-skills.ps1
```

Verify drift only (read-only check, no file writes):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-agent-skills.ps1 -VerifyOnly
```

Sync and install managed skills to local Codex profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync-agent-skills.ps1 -InstallLocal
```

Default local install target:

- `%USERPROFILE%\.codex\skills\<skill>`

## Multi-Device Mechanic Companion

When working on multiple devices, keep Mechanic outside this repo and bootstrap per machine.

Bootstrap or update local Mechanic companion:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-bootstrap.ps1
```

Bootstrap and pull latest `main` first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-bootstrap.ps1 -Pull
```

Optional tool setup step (non-interactive config skip):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-bootstrap.ps1 -RunSetupTools
```

Run Mechanic commands for KRT with explicit addon path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-krt.ps1 -Action AddonValidate -Json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-krt.ps1 -Action DocsStale -Json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mech-krt.ps1 -Action AddonDeadcode -Json
```

Available wrapper actions:

- `EnvStatus`
- `ToolsStatus`
- `AddonValidate`
- `DocsStale`
- `AddonDeadcode`
- `AddonLint`
- `AddonFormat`
- `AddonSecurity`
- `AddonComplexity`
- `AddonDeprecations`
- `AddonOutput`

## Repo-Local MCP Server

Use the repo-local MCP server when you want agents to access the existing skill sync and addon tooling
through one stdio endpoint instead of shelling each script manually.

Start command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-krt-mcp.ps1
```

See `docs/KRT_MCP.md` for tool inventory, environment overrides, and the recommended workflow.

## Safety Boundaries

- Cleanup removes stale files only inside managed destinations from the manifest.
- The script never touches `.system` skills.
- Local install overwrites only the managed skill names listed in the manifest.
