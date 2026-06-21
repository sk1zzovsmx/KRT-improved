# Docs Current Addon State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the repository documentation so `/docs` describes the current KRT addon layout,
runtime ownership, coding rules, and local development checks.

**Architecture:** This is a documentation-only update. Runtime code, SavedVariables schema, TOC
load order, and vendored libraries stay unchanged. The docs should describe the current source tree
as loaded by `!KRT/!KRT.toc`, then generated inventory files are refreshed from tooling.

**Tech Stack:** World of Warcraft WotLK 3.3.5a, Interface 30300, Lua 5.1, KRT docs, PowerShell
tooling, `tools/krt.py`.

---

## Files

- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/OVERVIEW.md`
- Modify: `docs/LUA_WRITING_RULES.md`
- Modify: `docs/UI_CODING_RULES.md`
- Review: `docs/DEV_CHECKS.md` (already current; no content patch needed)
- Modify: `docs/AGENT_SKILLS.md`
- Modify: `docs/KRT_MCP.md`
- Modify: `docs/LOOT_SOURCES.md`
- Modify: `docs/REFACTOR_RULES.md`
- Modify or regenerate: `docs/TREE.md`
- Modify or regenerate: `docs/FUNCTION_REGISTRY.csv`
- Modify or regenerate: `docs/FN_CLUSTERS.md`
- Modify or regenerate: `docs/API_REGISTRY.csv`
- Modify or regenerate: `docs/API_REGISTRY_PUBLIC.csv`
- Modify or regenerate: `docs/API_REGISTRY_INTERNAL.csv`
- Modify or regenerate: `docs/API_NOMENCLATURE_CENSUS.md`
- Create: `docs/superpowers/plans/2026-06-14-docs-current-addon-state.md`

## Task 1: Inventory Current Runtime Shape

- [x] **Step 1: Read the current load order**

Run:

```powershell
Get-Content -Raw '!KRT\!KRT.toc'
```

Expected: the TOC shows Layer 0 libraries, Layer 1 bootstrap/database, Layer 4 shared modules,
Layer 5 runtime modules, and Layer 6 `KRT.xml`.

- [x] **Step 2: List repository docs and addon files**

Run:

```powershell
rg --files
Get-ChildItem -Force docs | Select-Object Name,Length,LastWriteTime
```

Expected: all docs, source files, tests, and tools are visible; no generated or runtime code is
changed by this step.

- [x] **Step 3: Search for stale doc references**

Run:

```powershell
rg -n "Modules/LootSourcesData|Selection|SpecInspect|ScreenNotice|Warnings\\Store|Spammer\\Draft" docs
```

Expected: stale or imprecise references are found in docs that need direct edits.

## Task 2: Patch Narrative Docs

- [x] **Step 1: Update architecture and overview module maps**

Patch `docs/ARCHITECTURE.md` and `docs/OVERVIEW.md` so they state:

```markdown
`Modules/Dataset/LootSourcesData.lua` owns static raid item-source data.
`Modules/LootSourceCandidates.lua` owns shared-source labels, mode signatures, and candidate copies.
`Modules/UI/MultiSelect.lua` exports `addon.UI.Selection`.
`Modules/UI/ScreenNotice.lua` owns the shared transient screen-notice frame/effect.
`Services/SpecInspect.lua` owns UI-free cached raid spec snapshots.
```

- [x] **Step 2: Update coding and UI rules**

Patch `docs/LUA_WRITING_RULES.md` and `docs/UI_CODING_RULES.md` so they name the current shared UI
owners exactly:

```markdown
`Modules/UI/Frames.lua` owns `addon.UI.Scaffold`, frame refs, editbox helpers, and tooltip helpers.
`Modules/UI/MultiSelect.lua` owns `addon.UI.Selection`.
`Modules/UI/ScreenNotice.lua` owns shared screen notices.
`Modules/UI/Facade.lua` owns `addon.UI.Widgets`.
```

- [x] **Step 3: Review local checks and update refactor rules**

Review `docs/DEV_CHECKS.md` and patch `docs/REFACTOR_RULES.md` so examples use the current owner
names, current `tools/krt.py` commands, and current docs refresh path:

```powershell
py -3 tools/krt.py api-catalog-refresh
py -3 tools/krt.py api-catalog-check
py -3 tools/krt.py repo-quality-check --check all
```

- [x] **Step 4: Update loot source docs**

Patch `docs/LOOT_SOURCES.md` so it references:

```markdown
`!KRT/Modules/Dataset/LootSourcesData.lua`
`!KRT/Modules/Dataset/LootSources/`
`!KRT/Modules/LootSources.lua`
`!KRT/Modules/LootSourceCandidates.lua`
```

## Task 3: Refresh Generated Docs

- [x] **Step 1: Regenerate API catalogs and tree**

Run:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

Expected: generated docs are either unchanged or refreshed to match the current source tree.

- [x] **Step 2: Inspect the resulting diff**

Run:

```powershell
git diff -- docs
```

Expected: only documentation and generated inventory files changed.

## Task 4: Verify

- [x] **Step 1: Run documentation-relevant quality gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected: every command exits `0`.

- [x] **Step 2: Confirm working tree scope**

Run:

```powershell
git status --short
```

Expected: changes are limited to `docs/*` files unless a generated check reports otherwise.
