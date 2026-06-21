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

The workflow base depends on `AGENTS.md`, `.codex/*`, and the KRT MCP registration.
MarkItDown MCP is also registered as an auxiliary local server for attachment and
document conversion.

## Start Command

Use the cross-platform Python entrypoint:

```text
Windows: py -3 tools/krt.py run-krt-mcp
Linux:   python3 tools/krt.py run-krt-mcp
```

Server implementation: `tools/krt_mcp_server.py`.

### Installation for MCP Python dependencies

Windows:

```powershell
py -3 -m venv .venv
.venv\Scripts\python.exe -m pip install -r tools/requirements-mcp.txt
```

This virtualenv is used by both `run-markitdown-mcp.py` and related attachment
conversion tooling.

### MarkItDown MCP Start Command

```text
py -3 tools/run-markitdown-mcp.py
```

## Exposed MCP Tools

- `dev_stack_status`
  Unified readiness across commands, manifests, local skills, and MCP dependencies.
- `skills_manifest`
  Read `tools/agent-skills.manifest.json` with resolved destination paths.
- `skills_verify`
  Verify vendored `.agents/skills` content against pinned manifest snapshots.
- `skills_sync`
  Sync vendored skills and optionally install them into local Codex skill paths.
- `repo_quality_check`
  Run one MCP-exposed repo check: `toc_files`, `lua_syntax`, `ui_binding`, `layering`,
  `retired_aliases`, `raid_hardening`, or `lua_uniformity`.
## Suggested Workflow

1. Run `dev_stack_status` first.
2. Inspect `skills_manifest`.
3. Run `skills_verify` before doc/tooling updates.
4. Run `skills_sync` when vendored snapshots drift.
5. Run `repo_quality_check` for fast local guardrails.

## Shell Equivalents

The MCP server delegates to these repo scripts:

- `tools/dev-stack-status.ps1`
- `tools/sync-agent-skills.ps1`
- `tools/check-*.ps1` (`toc`, `lua`, `layering`, `ui_binding`, ...)

Equivalent direct CLI path:

```bash
python3 tools/krt.py dev-stack-status
python3 tools/krt.py repo-quality-check --check layering
python3 tools/krt.py api-catalog-check
python3 tools/krt.py skills-sync --verify-only
```

## Optional Environment Overrides

- `KRT_LOCAL_SKILLS_ROOT`
  Overrides local Codex skills destination.
  Default: `%USERPROFILE%\.codex\skills` (Windows), `~/.codex/skills` (Linux).
- `KRT_POWERSHELL_EXE`
  Overrides PowerShell executable used by the MCP server.

## Notes

- MCP tool operations do not patch vendored skill content directly.
- `skills_sync` is intentionally marked as a destructive operation.
- The server supports both newline-delimited JSON-RPC framing and `Content-Length` framing.
- MarkItDown MCP is for local trusted usage only. It can read files and URIs with
  current-user privileges; keep stdio transport local (no HTTP/SSE exposure).
