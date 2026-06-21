# KRT MCP Server

KRT ships a repo-local MCP server for addon and skill workflows.

The server is intentionally thin: it wraps existing repo scripts so humans and agents
share one execution path.

## Project Registration

The repo registers this server in both:

- `.codex/config.toml`
  Project-local Codex config used by the structured `55to53` workflow.
- `.mcp.json`
  Project MCP manifest alongside other repo-local MCP servers such as `lua-lsp`.

Keep these registrations project-local so agents can use the same repo-specific tooling
without relying on personal global Codex config.

Mechanic integration remains optional. The structured `55to53` workflow base depends on
`AGENTS.md`, `.codex/*`, and the KRT MCP registration, not on a local Mechanic install.

## Start Command

Use the cross-platform Python entrypoint:

```text
Windows: py -3 tools/krt.py run-krt-mcp
Linux:   python3 tools/krt.py run-krt-mcp
```

Server implementation: `tools/krt_mcp_server.py`.

## Exposed MCP Tools

- `dev_stack_status`
  Unified readiness across commands, manifests, local skills, Mechanic, and MCP dependencies.
- `skills_manifest`
  Read `tools/agent-skills.manifest.json` with resolved destination paths.
- `skills_verify`
  Verify vendored `.agents/skills` content against pinned manifest snapshots.
- `skills_sync`
  Sync vendored skills and optionally install them into local Codex skill paths.
- `repo_quality_check`
  Run one repo check: `toc_files`, `lua_syntax`, `ui_binding`, `layering`, `raid_hardening`,
  or `lua_uniformity`.
- `mechanic_call`
  Execute existing Mechanic wrapper flows (`env.status`, addon validate/lint/deadcode, etc.).
- `mechanic_bootstrap`
  Bootstrap/update external Mechanic checkout used by wrappers.

## Suggested Workflow

1. Run `dev_stack_status` first.
2. Inspect `skills_manifest`.
3. Run `skills_verify` before doc/tooling updates.
4. Run `skills_sync` when vendored snapshots drift.
5. Run `repo_quality_check` for fast local guardrails.
6. If addon-aware Mechanic flows are needed and Mechanic is missing, run `mechanic_bootstrap`.
7. Use `mechanic_call` only for checks that specifically need the external Mechanic companion.

## Shell Equivalents

The MCP server delegates to these repo scripts:

- `tools/dev-stack-status.ps1`
- `tools/sync-agent-skills.ps1`
- `tools/check-*.ps1` (`toc`, `lua`, `layering`, `ui_binding`, ...)
- `tools/mech-krt.ps1`
- `tools/mech-bootstrap.ps1`

Equivalent direct CLI path:

```bash
python3 tools/krt.py dev-stack-status
python3 tools/krt.py repo-quality-check --check layering
python3 tools/krt.py skills-sync --verify-only
python3 tools/krt.py mech AddonValidate --json
```

## Optional Environment Overrides

- `KRT_LOCAL_SKILLS_ROOT`
  Overrides local Codex skills destination.
  Default: `%USERPROFILE%\.codex\skills` (Windows), `~/.codex/skills` (Linux).
- `KRT_MECHANIC_ROOT`
  Overrides Mechanic checkout root.
  Default: `C:\dev\Mechanic` (Windows), `~/dev/Mechanic` (Linux).
- `KRT_MECHANIC_EXE`
  Overrides executable used by Mechanic wrapper calls.
- `KRT_POWERSHELL_EXE`
  Overrides PowerShell executable used by the MCP server.

## Notes

- MCP tool operations do not patch vendored skill content directly.
- `skills_sync` and `mechanic_bootstrap` are intentionally marked as destructive operations.
- The server supports both newline-delimited JSON-RPC framing and `Content-Length` framing.
