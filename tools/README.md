# Tools

Stable index for repository tooling.

Paths remain flat under `tools/` on purpose: the repo already references these scripts in hooks,
docs, AGENTS, and MCP wiring. Grouping is documented here first to keep cleanup safe and churn low.

## Cross-Platform Entrypoint

Use `tools/krt.py` as the canonical repo tooling entrypoint when you want the same command shape on
Windows and Linux.

Examples:

- Windows PowerShell: `py -3 tools/krt.py dev-stack-status --json`
- Linux shell: `python3 tools/krt.py dev-stack-status --json`
- Repository quality sweep: `python3 tools/krt.py repo-quality-check --check all`
- Stabilization tests: `python3 tools/krt.py run-release-targeted-tests`
- SV fixture round-trip: `python3 tools/krt.py run-sv-roundtrip --fixtures`
- SV validator: `python3 tools/krt.py run-raid-validator --saved-variables-path "<path>/!KRT.lua"`
- Release metadata from `!KRT/CHANGELOG.md`: `python3 tools/krt.py release-metadata --json`
- Publish gate by SemVer progression: `python3 tools/krt.py release-publish-gate --previous-ref HEAD^ --json`
- Release packaging: `python3 tools/krt.py build-release-zip --output-dir dist --write-checksum`
- Hook install: `python3 tools/krt.py install-hooks`
- Mechanic wrapper: `python3 tools/krt.py mech AddonValidate --json`

The legacy `*.ps1` scripts remain available for compatibility and for lower-level/script-specific
control.

## Checks

- `tools/krt.py repo-quality-check --check all`: runs the canonical full quality sweep in repo order
- `check-toc-files.ps1`: validates TOC naming, file entries, and SavedVariables declarations
- `check-layering.ps1`: repo architecture and ownership guardrails
- `check-ui-binding.ps1`: binder absence and XML layout-only policy
- `check-lua-syntax.ps1`: syntax-only validation for all Lua files
- `check-lua-uniformity.ps1`: repo-specific naming, headers, whitespace, and line-ending checks
- `check-api-nomenclature.ps1`: staged/new public API naming and verb-taxonomy guard
- `check-raid-hardening.ps1`: DB/SV/UI hardening audits and fixture round-trip gate

## Runs

- `tools/krt.py run-raid-validator`: wraps `run-raid-validator.ps1`
- `tools/krt.py run-sv-inspector`: wraps `run-sv-inspector.ps1`
- `tools/krt.py run-sv-roundtrip`: wraps `run-sv-roundtrip.ps1`
- `tools/krt.py run-release-targeted-tests`: wraps `run-release-targeted-tests.ps1`
- `tools/krt.py run-krt-mcp`: starts the local KRT MCP server wrapper
- `run-raid-validator.ps1`: runs `validate-raid-schema.lua` against a SavedVariables file
- `run-sv-inspector.ps1`: runs `sv-inspector.lua` with table or CSV output
- `run-sv-roundtrip.ps1`: runs `sv-roundtrip.lua` on one file or a fixture directory
- `run-release-targeted-tests.ps1`: runs `tests/release_stabilization_spec.lua`
- `run-krt-mcp.ps1`: starts the local KRT MCP server wrapper
- `build-release-zip.ps1`: compatibility shim around `tools/krt.py build-release-zip`
  for existing PowerShell workflows

## Fnmap

- `fnmap-inventory.ps1`: inventories Lua functions into `docs/FUNCTION_REGISTRY.csv`
- `fnmap-classify.ps1`: classifies inventory rows and writes `docs/FN_CLUSTERS.md`
- `fnmap-api-census.ps1`: inventories callable `addon.*` APIs and writes full/public/internal nomenclature reports

## Mechanic

- `mech-bootstrap.ps1`: installs or updates the external Mechanic companion tool
- `mech-krt.ps1`: repo wrapper for common Mechanic addon/documentation commands

## Agent Tooling

- `dev-stack-status.ps1`: unified readiness check for vendored skills, local
  Codex installs, Mechanic, and the repo-local MCP server
- `sync-agent-skills.ps1`: syncs local Codex skills from the repo manifest
- `agent-skills.manifest.json`: source of truth for repo-managed skill sync

## Infrastructure

- `tooling-common.ps1`: shared PowerShell helpers for repo root, Lua runtime, `rg`, and path handling
- `pre-commit.ps1`: canonical local pre-commit entrypoint
- `install-hooks.ps1`: compatibility shim around `tools/krt.py install-hooks`
- `update-tree.ps1`: regenerates `docs/TREE.md`
- `krt_mcp_server.py`: MCP server implementation used by `run-krt-mcp.ps1`

## Lua Helpers

- `sv-inspector.lua`: SavedVariables inspection utility
- `sv-roundtrip.lua`: round-trip serializer validation utility
- `validate-raid-schema.lua`: schema validation utility for raid SavedVariables
