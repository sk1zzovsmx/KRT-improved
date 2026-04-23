---
name: k-docs
description: >
  Index of KRT documentation with summaries and links. Load this to understand
  what documentation exists and where to find detailed information on specific topics.
  Triggers: docs, documentation, reference, guide, help.
---

# KRT Documentation Index

Quick reference to all KRT project documentation.

## Primary Documents

| Document | Path | Summary |
|----------|------|---------|
| **AGENTS.md** | `AGENTS.md` | Master agent guidance, load order, repo layout, module map, binding rules |
| **CHANGELOG.md** | `!KRT/CHANGELOG.md` | User-visible changes, version history, release metadata |
| **README.md** | `README.md` | Project overview |
| **TOC File** | `!KRT/!KRT.toc` | Load order manifest, version, SavedVariables declarations |

## Architecture & Design

Located in `docs/`:

| Document | Summary |
|----------|---------|
| **ARCHITECTURE.md** | Architecture/layering map, UI/XML binding policy, template policy |
| **OVERVIEW.md** | Runtime ownership and module map |
| **RAID_SCHEMA.md** | Canonical raid data schema (players, bosses, loot, rolls) |
| **SV_SCHEMA.md** | SavedVariables schema documentation |
| **SV_SANITY_CHECKLIST.md** | SavedVariables consistency checks |

## Development Rules & Standards

| Document | Summary |
|----------|---------|
| **LUA_WRITING_RULES.md** | Lua coding rules, naming policy, style conventions |
| **API_NOMENCLATURE_CENSUS.md** | PascalCase/camelCase compliance tracking |
| **REFACTOR_RULES.md** | Migration and refactoring guidelines |

## API Reference

| Document | Summary |
|----------|---------|
| **API_REGISTRY.csv** | Complete public + internal API surface |
| **API_REGISTRY_PUBLIC.csv** | Public API methods only |
| **API_REGISTRY_INTERNAL.csv** | Internal/private API methods |
| **FUNCTION_REGISTRY.csv** | Function inventory with classifications |
| **FN_CLUSTERS.md** | Function groupings and cluster analysis |

## Tooling & Workflow

| Document | Summary |
|----------|---------|
| **KRT_MCP.md** | KRT MCP server usage and tool inventory |
| **AGENT_SKILLS.md** | Agent skills, vendoring policy, Mechanic companion workflow |
| **DEV_CHECKS.md** | Quick layering/tooling checks reference |
| **TECH_CLEANUP_BACKLOG.md** | Technical debt tracking |
| **TECH_CLEANUP_WORKFLOW.md** | Cleanup process documentation |
| **RELEASE_DOWNLOAD.md** | Release asset download/checksum instructions |
| **TREE.md** | Auto-generated directory tree |

## Tool Scripts

Located in `tools/`:

| Script | Purpose |
|--------|---------|
| `krt.py` | Cross-platform tooling entrypoint |
| `krt_mcp_server.py` | KRT MCP server (7 tools) |
| `pre-commit.ps1` | Full pre-commit gate chain |
| `build-release-zip.ps1` | Package addon for release |
| `check-layering.ps1` | Architecture layer violations |
| `check-api-nomenclature.ps1` | Naming compliance |
| `check-lua-syntax.ps1` | Lua 5.1 syntax validation |
| `check-lua-uniformity.ps1` | Section headers / naming patterns |
| `check-toc-files.ps1` | TOC file integrity |
| `check-ui-binding.ps1` | No inline XML scripts |
| `check-raid-hardening.ps1` | Raid store guard patterns |
| `run-release-targeted-tests.ps1` | Busted regression tests |
| `run-sv-roundtrip.ps1` | SavedVariables round-trip test |
| `run-sv-inspector.ps1` | SV structure inspection |
| `run-raid-validator.ps1` | Raid schema validation |
| `fnmap-inventory.ps1` | Function inventory generation |
| `fnmap-classify.ps1` | Function classification |
| `fnmap-api-census.ps1` | API naming census |

## Skill References

Each skill in `.agents/skills/` has detailed domain guidance:

| Skill | Purpose |
|-------|---------|
| **s-audit** | Quality analysis (layering, naming, raid hardening) |
| **s-clean** | Dead code and stale doc cleanup |
| **s-debug** | Debugging methodology + reference files |
| **s-lint** | Luacheck + StyLua code quality |
| **s-release** | Version bumping, changelog, packaging |
| **s-working** | General KRT development guidance |
| **k-docs** | This documentation index |

## External References

| Resource | URL |
|----------|-----|
| WoW 3.3.5a FrameXML | `https://www.townlong-yak.com/framexml/3.3.5` |

## Quick Links by Topic

| Topic | Where to Look |
|-------|---------------|
| Getting started | `README.md`, `docs/OVERVIEW.md` |
| Load order | `AGENTS.md` section 4, `!KRT/!KRT.toc` |
| Module map | `AGENTS.md` section 11, `docs/OVERVIEW.md` |
| Debugging | `s-debug` skill, `/krt debug on` |
| Code style | `docs/LUA_WRITING_RULES.md`, `s-lint` skill |
| Architecture | `docs/ARCHITECTURE.md`, `AGENTS.md` sections 3+18 |
| Releasing | `s-release` skill, `docs/RELEASE_DOWNLOAD.md` |
| SavedVariables | `docs/SV_SCHEMA.md`, `docs/SV_SANITY_CHECKLIST.md` |
| Raid schema | `docs/RAID_SCHEMA.md`, `Core/DBSchema.lua` |
| Quality checks | `docs/DEV_CHECKS.md`, `tools/pre-commit.ps1` |
