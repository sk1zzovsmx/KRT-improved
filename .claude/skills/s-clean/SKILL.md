---
name: s-clean
description: >
  Find and remove dead code and stale documentation in KRT (WoW 3.3.5a / Lua 5.1).
  Covers unused functions, orphaned files, dead links, and outdated references.
  Triggers: clean, dead code, unused, orphan, stale, cruft, maintenance.
---

# Cleaning KRT

Find and remove cruft in the KRT addon codebase.

## MCP Tools (KRT Server)

| Task | MCP Tool |
|------|----------|
| TOC integrity | `repo_quality_check(check="toc_files")` |
| Naming/dead patterns | `repo_quality_check(check="lua_uniformity")` |

If Mechanic is bootstrapped:

| Task | Action |
|------|--------|
| Dead code detection | `mechanic_call(action="AddonDeadcode")` |
| Stale docs | `mechanic_call(action="DocsStale")` |

## Capabilities

1. **Dead Code Detection** — Unused functions, orphaned files, dead exports
2. **Stale Docs Detection** — Broken links, outdated references, missing files
3. **Function Registry** — Generate full function inventory for analysis
4. **TOC Orphan Check** — Files not listed in `!KRT.toc` won't load

## Detection Categories

### Orphaned Files

Files under `!KRT/` that exist on disk but are not referenced in `!KRT/!KRT.toc`.

```powershell
# TOC check covers this:
py -3 tools/krt.py repo-quality-check --check toc_files
```

### Function Registry

Generate a full function inventory for dead code analysis:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
```

Outputs: `docs/FUNCTION_REGISTRY.csv`

Related tools:
- `tools/fnmap-classify.ps1` — classify by layer/owner
- `tools/fnmap-api-census.ps1` — enumerate public vs. internal API surface

Outputs: `docs/API_REGISTRY.csv`, `docs/API_REGISTRY_PUBLIC.csv`, `docs/API_REGISTRY_INTERNAL.csv`

### Stale Documentation

Check docs/ files against actual codebase:

| What to check | How |
|---|---|
| AGENTS.md load order (section 4) | Compare against `!KRT/!KRT.toc` entries |
| AGENTS.md repo layout (section 5) | Compare against actual file tree |
| AGENTS.md module map (section 11) | Compare against `addon.*` assignments in code |
| docs/TREE.md | Regenerate with `tools/update-tree.ps1` |
| docs/*.csv registries | Regenerate with `tools/fnmap-inventory.ps1` |
| .luacheckrc globals | Compare against named XML frames in `!KRT/UI/*.xml` |

### Dead SavedVariables Keys

Check for SV keys that are written but never read, or read but never written:

```powershell
py -3 tools/krt.py repo-quality-check --check raid_hardening
```

This validates SV round-trip stability via `tools/sv-roundtrip.lua`.

## Workflow

### Quick Cleanup

1. `repo_quality_check(check="toc_files")` — find orphaned/missing files
2. Scan `docs/FUNCTION_REGISTRY.csv` for functions with 0 call sites
3. Check `docs/TREE.md` freshness: `tools/update-tree.ps1`
4. Fix broken links in docs/ files

### Deep Cleanup

1. Regenerate function registry: `tools/fnmap-inventory.ps1`
2. Regenerate API census: `tools/fnmap-api-census.ps1`
3. Cross-reference public API against actual call sites
4. Check AGENTS.md sections 4, 5, 11 against codebase
5. If Mechanic available: `mechanic_call(action="AddonDeadcode")`

## Confidence Interpretation

| Level | Meaning | Action |
|-------|---------|--------|
| **Definite** | File not in TOC, function never called | Safe to remove |
| **Likely** | Function defined but no call site found by grep | Review for dynamic dispatch |
| **Suspicious** | Used via `_G[]`, `rawget`, `addon[methodName]` patterns | Manual verification required |

## KRT-Specific Patterns to Preserve

These patterns look like dead code but are intentional:

- `SLASH_KRT1` — WoW slash command registration (global)
- `addon:ADDON_LOADED()` — WoW event handler called by OnEvent dispatch
- `module.OnLoadFrame()` — UIScaffold lifecycle callback
- `module.AcquireRefs()` — UIScaffold lifecycle callback
- `module.BindHandlers()` — UIScaffold lifecycle callback
- `module.RefreshUI()` — UIScaffold lifecycle callback
- `Diag.I.*`, `Diag.W.*` etc. — diagnostic templates (may appear unused if only used at runtime)

## Best Practices

1. **Start with TOC check** — Orphaned files are definite dead code
2. **Regenerate registries before analysis** — CSVs may be stale
3. **Check dynamic dispatch** — `_G[frameName .. suffix]` pattern hides real usage
4. **Preserve UIScaffold hooks** — They're called dynamically by the scaffold
5. **Update docs after code removal** — Run `tools/update-tree.ps1`
