# Total Rework Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the first safe foundation for a future KRT total rework: explicit module dependency
metadata and verification, without moving feature logic or changing gameplay behavior.

**Architecture:** Keep WoW's static TOC loading, but add a Lua 5.1 registry that records module names,
declared dependencies, and TOC load order. The first stage is observational and validation-only: it gives
future rework waves a stable dependency graph before large files are split or moved.

**Tech Stack:** WoW 3.3.5a, Lua 5.1, PowerShell repo gates, existing `tools/krt.py` quality wrapper.

---

### Task 1: Module Registry Core

**Files:**
- Create: `!KRT/Modules/ModuleRegistry.lua`
- Modify: `!KRT/!KRT.toc`
- Create: `tests/module_registry_spec.lua`

- [ ] **Step 1: Write a failing source-contract test**

Create `tests/module_registry_spec.lua` that:
- reads `!KRT/Modules/ModuleRegistry.lua`,
- requires public APIs `AddModule`, `SetLoaded`, `GetLoadOrderStatus`, `GetStatus`, and `GetModules`,
- verifies the TOC loads `Modules\ModuleRegistry.lua` after `Modules\Features.lua` and before
  `Modules\UI\Facade.lua`.

Run:

```powershell
lua tests/module_registry_spec.lua
```

Expected before implementation: failure because `ModuleRegistry.lua` does not exist.

- [ ] **Step 2: Implement minimal registry**

Create `!KRT/Modules/ModuleRegistry.lua` with:
- standard KRT module header,
- `addon.ModuleRegistry`,
- internal module list and by-name map,
- `AddModule(name, cfg)`,
- `SetLoaded(name)`,
- `GetModules(out)`,
- `GetStatus(name)`,
- `GetLoadOrderStatus()`.

The registry must not initialize feature modules or change runtime flow yet.

- [ ] **Step 3: Add TOC entry**

Add `Modules\ModuleRegistry.lua` after `Modules\Features.lua` and before `Modules\UI\Facade.lua` in
`!KRT/!KRT.toc`.

- [ ] **Step 4: Run focused verification**

Run:

```powershell
lua tests/module_registry_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
```

Expected: all pass.

### Task 2: Bootstrap Registry Metadata

**Files:**
- Modify: `!KRT/Init.lua`
- Modify: `!KRT/Modules/ModuleRegistry.lua`
- Modify: `tests/module_registry_spec.lua`

- [ ] **Step 1: Add failing source-contract coverage**

Extend `tests/module_registry_spec.lua` to verify:
- `Init.lua` calls `ModuleRegistry.SetLoaded("Init")`,
- `ModuleRegistry.lua` can record dependency lists,
- `GetLoadOrderStatus()` reports missing dependencies and out-of-order dependencies.

Run:

```powershell
lua tests/module_registry_spec.lua
```

Expected before implementation: failure because `Init` is not marked and validation does not yet return the
required diagnostics.

- [ ] **Step 2: Extend registry diagnostics**

Make `GetLoadOrderStatus()` return:
- `true, nil` when all declared dependencies are loaded earlier,
- `false, issues` when a dependency is missing or appears after the dependent module.

Each issue should be a table with `module`, `dependency`, and `reason`.

- [ ] **Step 3: Mark `Init` loaded**

In `!KRT/Init.lua`, after core bootstrap tables exist, call:

```lua
if addon.ModuleRegistry and addon.ModuleRegistry.SetLoaded then
    addon.ModuleRegistry.SetLoaded("Init")
end
```

This is metadata only and must not affect gameplay event registration.

- [ ] **Step 4: Run focused verification**

Run:

```powershell
lua tests/module_registry_spec.lua
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-toc-files.ps1
```

Expected: all pass.

### Task 3: Final Local Gates And Catalog Snapshot

**Files:**
- Generated/checked: `docs/API_REGISTRY*.csv`, `docs/FUNCTION_REGISTRY.csv`, `docs/FN_CLUSTERS.md`

- [ ] **Step 1: Run full repo gate**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all checks pass.

- [ ] **Step 2: Regenerate catalogs**

Run in sequence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
```

Expected: catalogs regenerate without errors.

- [ ] **Step 3: Summarize branch delta**

Record:
- changed files,
- new registry APIs,
- tests run,
- remaining next stage: dependency registration for first real package (`Modules/UI` or `Services/Rolls`).
