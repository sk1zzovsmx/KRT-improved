---
name: s-audit
description: >
  Comprehensive quality analysis for KRT addon (WoW 3.3.5a / Lua 5.1).
  Combines layering, naming, raid hardening, TOC, UI binding, and dead code
  checks into a single audit workflow.
  Triggers: audit, quality, analysis, review, check, scan.
---

# Auditing KRT

Quality analysis workflow for KRT addon codebase (WotLK 3.3.5a, Interface 30300).

## MCP Tools (KRT Server)

| Task | MCP Tool |
|------|----------|
| Layering check | `repo_quality_check(check="layering")` |
| TOC validation | `repo_quality_check(check="toc_files")` |
| UI binding check | `repo_quality_check(check="ui_binding")` |
| Lua syntax | `repo_quality_check(check="lua_syntax")` |
| Naming/uniformity | `repo_quality_check(check="lua_uniformity")` |
| Raid hardening | `repo_quality_check(check="raid_hardening")` |
| Dev stack status | `dev_stack_status(verifySkills=true)` |

If Mechanic is bootstrapped, additional checks are available via `mechanic_call`:

| Task | Action |
|------|--------|
| Dead code detection | `mechanic_call(action="AddonDeadcode")` |
| Security analysis | `mechanic_call(action="AddonSecurity")` |
| Complexity analysis | `mechanic_call(action="AddonComplexity")` |

## Capabilities

1. **Layering Verification** — Services must not call Controllers/Widgets or own frames
2. **Naming Compliance** — PascalCase public, camelCase private, canonical section headers
3. **Raid Hardening** — DB facade encapsulation, legacy key cleanup, SV round-trip stability
4. **TOC Integrity** — File existence, naming conventions, SavedVariables declarations
5. **UI Binding** — XML layout-only policy (no inline scripts), no Binder files
6. **Dead Code** — Function registry via `fnmap-inventory.ps1`, orphaned file detection

## Analysis Categories

### Layering (`check-layering.ps1`)

| Check | Description | Severity |
|-------|-------------|----------|
| Service→Parent refs | Services referencing Controllers directly | Error |
| Service→Parent frames | Services accessing Controller frame objects | Error |
| Service hooksecurefunc | Services hooking Controller code | Error |
| Service UI frame APIs | Services creating/showing/hiding frames | Error |
| Item tooltip leak | Item helpers leaking outside `Modules/Item.lua` | Warning |
| Core parent frame leak | Init.lua accessing Master.frame | Warning |

### Naming (`check-lua-uniformity.ps1`)

| Check | Expected Pattern | Description |
|-------|-----------------|-------------|
| Public functions | PascalCase or UPPER_SNAKE | Exported methods on modules |
| Private functions | camelCase | File-local helpers |
| UI hooks | `AcquireRefs`, `BindHandlers`, `Localize`, `OnLoadFrame`, `RefreshUI` | Canonical names |
| Section headers | `-- ----- Internal state ----- --` etc. | Required in Controllers/Services/Widgets |

### Raid Hardening (`check-raid-hardening.ps1`)

| Check | Description |
|-------|-------------|
| KRT_Raids access confinement | Only Init.lua + DBRaidStore.lua may touch `KRT_Raids` |
| Legacy runtime key cleanup | `_playersByName` etc. only in DBRaidStore.lua |
| XML layout-only | No inline scripts in UI XML |
| DB facade access | Raid store accessed only through DB facade |
| Schema validation | `validate-raid-schema.lua` passes luacheck |
| SV round-trip | Fixture stability via `sv-roundtrip.lua` |

### Dead Code (`fnmap-inventory.ps1`)

| Category | Description |
|----------|-------------|
| Function registry | Scans all KRT-owned Lua for function definitions |
| Layer classification | Maps functions to Core/Modules/Services/Controllers/Widgets |
| Owner extraction | Identifies `addon.*`, `module.*` ownership |
| API census | `fnmap-api-census.ps1` enumerates public API surface |

## Workflow

### Quick Audit

```
1. repo_quality_check(check="layering")      → Architecture violations
2. repo_quality_check(check="lua_syntax")     → Syntax errors
3. repo_quality_check(check="toc_files")      → Missing files / broken TOC
4. Report critical findings
```

### Full Audit

```
1. repo_quality_check(check="layering")       → Architecture
2. repo_quality_check(check="ui_binding")     → XML policy
3. repo_quality_check(check="raid_hardening") → DB encapsulation + SV stability
4. repo_quality_check(check="lua_syntax")     → Syntax
5. repo_quality_check(check="lua_uniformity") → Naming + luacheck
6. repo_quality_check(check="toc_files")      → TOC integrity
7. Report with priority order
```

### Shell Fallback

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-layering.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-raid-hardening.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-uniformity.ps1
```

Or via cross-platform entrypoint:

```powershell
py -3 tools/krt.py repo-quality-check --check layering
py -3 tools/krt.py repo-quality-check --check raid_hardening
```

## Priority Order

1. **Critical** (Fix immediately):
   - Layering violations (Services calling Controllers/Widgets)
   - Raid hardening failures (DB facade bypass, SV corruption risk)
   - Missing TOC entries (addon files won't load)

2. **High** (Fix before release):
   - Lua syntax errors
   - UI binding violations (inline XML scripts)
   - Naming regressions

3. **Medium** (Fix when convenient):
   - Long functions (>100 lines)
   - Missing section headers in feature modules
   - Dead code / unused exports

4. **Low** (Monitor):
   - Code duplicates
   - Function registry drift

## Best Practices

1. **Run pre-commit gate** — `tools/pre-commit.ps1` chains all checks
2. **Start with layering** — Architecture violations block everything else
3. **Check raid hardening after DB changes** — SV round-trip must stay stable
4. **Use MCP tools when available** — Faster than shell for iterative checks
5. **Target 3.3.5a only** — Do not flag modern API deprecations (C_Timer, C_Spell, etc.)
