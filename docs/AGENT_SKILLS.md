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

Start with a single readiness check before switching between vendored skills,
local Codex installs, Mechanic, and MCP:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev-stack-status.ps1
```

Machine-readable status for agents and wrappers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev-stack-status.ps1 -Json
```

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

## Canonical AFD Workflow

Treat the repo-local scripts as the CLI truth and use them in this order:

1. `tools/dev-stack-status.ps1`
   - Confirms whether vendored skills, local installs, Mechanic, and MCP are ready.
2. `tools/sync-agent-skills.ps1`
   - Restores vendored skills or installs them locally with `-InstallLocal`.
3. `tools/mech-bootstrap.ps1`
   - Bootstraps Mechanic on the current device when `mech.exe` is missing.
4. `tools/mech-krt.ps1`
   - Validates the addon and docs through Mechanic-backed commands.
5. `tools/run-krt-mcp.ps1`
   - Exposes the same stack through one MCP endpoint for agents.

This keeps the local workflow aligned with AFD's CLI-first rule: if a tool
chain is not ready or testable from the shell, do not assume an agent or UI
surface will be reliable.

## Repo-Local MCP Server

Use the repo-local MCP server when you want agents to access the existing skill sync and addon tooling
through one stdio endpoint instead of shelling each script manually.

Start command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-krt-mcp.ps1
```

See `docs/KRT_MCP.md` for tool inventory, readiness checks, environment
overrides, and the recommended workflow.

## Safety Boundaries

- Cleanup removes stale files only inside managed destinations from the manifest.
- The script never touches `.system` skills.
- Local install overwrites only the managed skill names listed in the manifest.
