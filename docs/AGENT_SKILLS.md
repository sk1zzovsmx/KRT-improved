# Agent Skills and Mechanic Workflow

This repository maintains AI skills under `.agents/skills`, customized for KRT addon development.

## Policy

- Skills are KRT-native: content is tailored for KRT addon architecture, WoW 3.3.5a, and Lua 5.1.
- Upstream Mechanic skill snapshots serve as structural templates; content is overridden locally.
- Pin every imported skill to an explicit commit SHA for structural reference.
- Do not introduce Mechanic/Fen/AFD-specific guidance in skills; keep all references KRT-relevant.

## Source of Truth

- Manifest: `tools/agent-skills.manifest.json`
- Sync script: `tools/sync-agent-skills.ps1`
- Cross-platform entrypoint: `tools/krt.py`

## Pinned Skill Sources

- `Falkicon/Mechanic` @ `41ef25dcfcd7c1450577b5826fbba9c571c7c75d`

Managed skills from the manifest:

- `s-clean`
- `s-audit`
- `s-debug`
- `s-working`
- `s-lint`
- `s-release`
- `k-docs`

## Recommended Command Flow

1. Inspect local readiness.
2. Verify or sync vendored skills.
3. Install skills locally if needed.
4. Bootstrap Mechanic (once per machine).
5. Run Mechanic-backed addon checks.
6. Start MCP when agent workflows need a tool endpoint.

## Cross-Platform Commands (`tools/krt.py`)

Windows:

```powershell
py -3 tools/krt.py dev-stack-status
py -3 tools/krt.py skills-manifest
py -3 tools/krt.py skills-sync --verify-only
py -3 tools/krt.py skills-sync
py -3 tools/krt.py skills-sync --install-local
py -3 tools/krt.py mechanic-bootstrap --pull
py -3 tools/krt.py mech AddonValidate --json
py -3 tools/krt.py run-krt-mcp
```

Linux:

```bash
python3 tools/krt.py dev-stack-status
python3 tools/krt.py skills-manifest
python3 tools/krt.py skills-sync --verify-only
python3 tools/krt.py skills-sync
python3 tools/krt.py skills-sync --install-local
python3 tools/krt.py mechanic-bootstrap --pull
python3 tools/krt.py mech AddonValidate --json
python3 tools/krt.py run-krt-mcp
```

## Legacy Script Equivalents

These remain valid and are what `krt.py` wraps:

- `tools/sync-agent-skills.ps1`
- `tools/mech-bootstrap.ps1`
- `tools/mech-krt.ps1`
- `tools/dev-stack-status.ps1`
- `tools/run-krt-mcp.ps1`

## Multi-Device Mechanic Companion

Keep Mechanic external to this repo, bootstrap per device.

Default roots:

- Windows: `C:\dev\Mechanic`
- Linux: `~/dev/Mechanic`

Environment overrides:

- `KRT_MECHANIC_ROOT`
- `KRT_MECHANIC_EXE`
- `KRT_LOCAL_SKILLS_ROOT`
- `KRT_POWERSHELL_EXE`

## Safety Boundaries

- Sync cleanup is limited to managed destination paths from the manifest.
- `.system` skills are never touched by repo sync.
- Local install overwrites only managed skill names listed in the manifest.

## Related Docs

- `docs/KRT_MCP.md` - MCP tool inventory and workflow
- `docs/DEV_CHECKS.md` - fast local checks
- `tools/README.md` - tool index and command families
