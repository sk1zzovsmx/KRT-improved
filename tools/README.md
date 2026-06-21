# Tools

Stable index for repository tooling.

`tools/krt.py` is the canonical cross-platform entrypoint. Direct `*.ps1`
and Lua helper scripts remain available when a lower-level script contract is
needed by hooks, CI, MCP, or manual debugging. Paths stay flat under `tools/`
because AGENTS, hooks, docs, and MCP registrations reference them directly.

## `tools/krt.py` Command Index

Run these as `py -3 tools/krt.py <command>` on Windows or
`python3 tools/krt.py <command>` on Linux/macOS.

| Command | Purpose |
|---|---|
| `build-release-zip` | Build addon ZIPs containing only `!KRT/`. |
| `install-hooks` | Set `git core.hooksPath=.githooks`. |
| `repo-quality-check --check <name>` | Run one repo-local quality check. |
| `api-catalog-refresh` | Regenerate function/API catalogs and `docs/TREE.md`. |
| `api-catalog-check` | Regenerate catalogs and fail on drift. |
| `run-release-targeted-tests` | Run the release stabilization Lua spec. |
| `run-raid-validator` | Validate one SavedVariables file. |
| `run-sv-inspector` | Inspect one SavedVariables file. |
| `run-sv-roundtrip` | Validate SavedVariables serialization stability. |
| `skills-manifest` | Print the managed skill manifest. |
| `skills-sync` | Sync or verify vendored skill snapshots. |
| `run-krt-mcp` | Start the repo-local MCP server. |
| `codex-55to53` | Classify and wrap a delegated Codex workflow prompt. |
| `dev-stack-status` | Inspect repo tooling readiness. |
| `install-python-dev-deps` | Install repo-local Python developer dependencies. |
| `python-quality-check` | Run Python quality checks for tools and tests. |
| `release-metadata` | Resolve SemVer metadata from changelog and TOC. |
| `release-notes` | Build GitHub release notes from changelog and commits. |
| `release-prepare` | Generate release notes, ZIP, and checksum artifacts. |
| `release-publish-gate` | Decide whether release publication should run. |
| `pre-commit` | Run the canonical local pre-commit entrypoint. |

`repo-quality-check --check` accepts `all`, `api_nomenclature`, `layering`,
`lua_syntax`, `lua_uniformity`, `raid_hardening`, `retired_aliases`,
`toc_files`, and `ui_binding`.

## Daily Checks

Windows:

```powershell
py -3 tools/krt.py dev-stack-status --json
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
py -3 tools/krt.py pre-commit
```

Linux:

```bash
python3 tools/krt.py dev-stack-status --json
python3 tools/krt.py repo-quality-check --check all
python3 tools/krt.py api-catalog-check
```

Quality check wrappers:

- `tools/krt.py repo-quality-check --check all`: canonical full quality sweep
  in repo order.
- `check-toc-files.ps1`: validates TOC naming, file entries, and
  SavedVariables declarations.
- `check-layering.ps1`: validates repo architecture and ownership guardrails.
- `check-retired-aliases.ps1`: rejects retired top-level `addon.*` aliases in
  KRT-owned Lua.
- `check-ui-binding.ps1`: checks binder absence and XML layout-only policy.
- `check-lua-syntax.ps1`: syntax-only validation for all Lua files.
- `check-lua-uniformity.ps1`: checks Lua headers, naming, whitespace,
  line endings, option access, `OnUpdate`, and WotLK/Lua 5.1 compatibility.
- `check-api-nomenclature.ps1`: checks staged/new public API naming and
  verb-taxonomy rules.
- `check-raid-hardening.ps1`: audits DB/SV/UI boundaries and fixture
  round-trip behavior.

## SavedVariables Helpers

- `tools/krt.py run-raid-validator`: validates one SavedVariables file through
  `run-raid-validator.ps1` and `validate-raid-schema.lua`.
- `tools/krt.py run-sv-inspector`: inspects SavedVariables through
  `run-sv-inspector.ps1` and `sv-inspector.lua`.
- `tools/krt.py run-sv-roundtrip`: validates serialization stability through
  `run-sv-roundtrip.ps1` and `sv-roundtrip.lua`.

Common examples:

```powershell
py -3 tools/krt.py run-sv-roundtrip --fixtures
py -3 tools/krt.py run-raid-validator --saved-variables-path "<path>/!KRT.lua"
py -3 tools/krt.py run-sv-inspector --saved-variables-path "<path>/!KRT.lua" --format table
```

## Release Flow

- `tools/krt.py release-metadata`: resolves SemVer release metadata from
  `!KRT/CHANGELOG.md` and `!KRT/!KRT.toc`.
- `tools/krt.py release-publish-gate`: decides whether publication is allowed
  by comparing the current version against a previous ref.
- `tools/krt.py release-notes`: builds GitHub release notes from changelog
  entries and previous-tag-to-current-tag commits.
- `tools/krt.py release-prepare`: builds release notes, addon ZIP, and checksum
  artifacts in one canonical flow.
- `tools/krt.py build-release-zip`: builds an addon ZIP containing only
  `!KRT/` and omits standalone embedded-library metadata files that KRT does
  not load at runtime.
- `tools/krt.py run-release-targeted-tests`: runs
  `tests/release_stabilization_spec.lua`.

Common examples:

```powershell
py -3 tools/krt.py release-metadata --json
py -3 tools/krt.py release-publish-gate --previous-ref HEAD^ --json
py -3 tools/krt.py release-prepare --current-tag v<version> --output-dir dist --json
py -3 tools/krt.py release-notes --current-tag v<version> --output-file dist/release-notes.md
py -3 tools/krt.py build-release-zip --output-dir dist --write-checksum
```

## Agent And MCP Tooling

- `dev-stack-status.ps1`: readiness check for required commands, vendored
  skills, optional local Codex skill installs, and the repo-local MCP server.
- `sync-agent-skills.ps1`: syncs repo-managed Codex skills from
  `agent-skills.manifest.json`.
- `agent-skills.manifest.json`: source of truth for repo-managed skill sync and
  archived skill metadata.
- `tools/krt.py skills-manifest`: prints the resolved skill manifest.
- `tools/krt.py skills-sync --verify-only`: verifies vendored skill snapshots.
- `tools/krt.py skills-sync --install-local`: intentionally copies managed
  skills into a local Codex skills root.
- `tools/krt.py run-krt-mcp`: starts `krt_mcp_server.py` for repo-local MCP
  tools.
- `run-krt-mcp.ps1`: PowerShell wrapper used by MCP registration.
- `krt_mcp_server.py`: JSON-RPC stdio MCP server exposing skill, readiness, and
  quality-check tools.
- `tools/krt.py codex-55to53`: repo-local launcher for the delegated 55to53
  workflow. It classifies tasks and emits, runs, or writes a wrapped Codex
  prompt; for complex orchestrated tasks it creates a dedicated
  `codex/55to53-*` branch unless the worktree is dirty.

## Python Dev Tooling

- `tools/requirements-dev.txt`: repo-local developer dependencies for Python tooling:
  `ruff`, `pytest`, `jsonschema`, and `Pillow`.
- `.venv\Scripts\python.exe -m pip install -r tools\requirements-dev.txt`
- `.venv\Scripts\python.exe tools\krt.py install-python-dev-deps`
- `.venv\Scripts\python.exe tools\krt.py python-quality-check`
- `python-quality-check` target defaults are `tools` and `tests/python` and supports:
  `--skip-ruff`, `--skip-pytest`.

## Catalogs And Tree

- `fnmap-inventory.ps1`: inventories Lua functions into
  `docs/FUNCTION_REGISTRY.csv`.
- `fnmap-classify.ps1`: classifies inventory rows and writes
  `docs/FN_CLUSTERS.md`.
- `fnmap-api-census.ps1`: inventories callable `addon.*` APIs and writes full,
  public, and internal nomenclature reports.
- `update-tree.ps1`: regenerates `docs/TREE.md` with default `-MaxDepth 4`.
- `tools/krt.py api-catalog-refresh`: runs inventory, classify, API census, and
  tree refresh in canonical order.
- `tools/krt.py api-catalog-check`: runs the same sequence and fails if
  catalog files drift.

## Compatibility Wrappers

- `pre-commit.ps1`: canonical local pre-commit entrypoint used by Git hooks and
  `tools/krt.py pre-commit`.
- `tooling-common.ps1`: shared PowerShell helpers for repo root, Lua runtime,
  ripgrep, and path handling.

## Lua Helpers

- `sv-inspector.lua`: SavedVariables inspection utility.
- `sv-roundtrip.lua`: round-trip serializer validation utility.
- `validate-raid-schema.lua`: schema validation utility for raid
  SavedVariables.
