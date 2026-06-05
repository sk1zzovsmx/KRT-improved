# Whole Addon Sequential Uniformization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uniform every KRT-owned file through a stable sequential review queue without changing behavior accidentally.

**Architecture:** The TOC remains the runtime source of truth. Each tranche audits files in load order, applies only
local low-risk cleanups, and escalates public-contract or ownership changes into dedicated waves.

**Tech Stack:** WoW 3.3.5a, Lua 5.1, XML layout files, PowerShell tooling, `tools/krt.py` quality gates.

---

## File Structure

- Modify: `AGENTS.md`
  Records durable process rules for sequential whole-addon uniformization.
- Modify only when justified: `!KRT/Init.lua`
  Bootstrap and event wiring; no split or public contract change in this tranche.
- Modify only when justified: `!KRT/Core/DB.lua`
  Canonical DB accessor facade on `addon.Core`.
- Modify only when justified: `!KRT/Core/Options.lua`
  Strict nested options namespace and `addon.options` read-only proxy.
- Modify only when justified: `!KRT/Core/DBSchema.lua`
  Raid schema version contract.
- Modify only when justified: `!KRT/Core/DBManager.lua`
  SavedVariables manager factory.
- Reference: `docs/LUA_WRITING_RULES.md`
- Reference: `docs/DEV_CHECKS.md`
- Reference: `docs/API_NOMENCLATURE_CENSUS.md`

## Task 1: Lock The Sequential Process

**Files:**
- Modify: `AGENTS.md`

- [x] **Step 1: Add the audit-before-runtime rule**

Add a durable preference requiring measurable audit before whole-addon code changes.

- [x] **Step 2: Add the stable file-order rule**

Add a durable preference requiring KRT-owned files to be processed sequentially in stable load/layer order.

- [ ] **Step 3: Verify `AGENTS.md` line length**

Run:

```powershell
$bad = Get-Content AGENTS.md | ForEach-Object -Begin {$i=0} -Process {$i++; if ($_.Length -gt 120) { "$i" }}
if ($bad) { $bad } else { "OK" }
```

Expected: `OK`.

## Task 2: Build The Runtime Queue

**Files:**
- Read: `!KRT/!KRT.toc`
- Read: `docs/LUA_WRITING_RULES.md`

- [ ] **Step 1: Generate non-vendored TOC order**

Run:

```powershell
$toc='!KRT\!KRT.toc'
Get-Content $toc |
  Where-Object { $_ -and $_ -notmatch '^\s*#' -and $_ -match '\.(lua|xml)$' } |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -notmatch '^Libs\\' }
```

Expected: list begins with `Init.lua` and ends with `KRT.xml`.

- [ ] **Step 2: Treat vendored libraries as excluded**

Confirm there are no planned edits under `!KRT/Libs`.

## Task 3: Review `!KRT/Init.lua`

**Files:**
- Read: `!KRT/Init.lua`
- Test: `tools/krt.py`

- [ ] **Step 1: Inspect exports and bootstrap ownership**

Check that `addon.Core`, `addon.L`, `addon.Diagnose`, `addon.State`, `addon.C`, and `addon.Events` remain centralized.

- [ ] **Step 2: Inspect event forwarding**

Check that WoW events are wired through `Bus.TriggerEvent("wow.EVENT", ...)` or intentional controller dispatch.

- [ ] **Step 3: Apply only local cleanup**

Allowed edits: comments, private helper simplification, duplicate local removal, debug guard simplification.
Disallowed edits: splitting `Init.lua`, changing SavedVariables bootstrap, changing event dispatch contracts.

- [ ] **Step 4: Verify**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all checks pass.

## Task 4: Review Core Facade Files

**Files:**
- Read/modify if justified: `!KRT/Core/DB.lua`
- Read/modify if justified: `!KRT/Core/Options.lua`
- Read/modify if justified: `!KRT/Core/DBSchema.lua`
- Read/modify if justified: `!KRT/Core/DBManager.lua`
- Test: `tools/krt.py`

- [ ] **Step 1: Review canonical public surfaces**

Confirm DB-backed public access remains on `addon.Core.*` and concrete module state remains under `addon.DB`.

- [ ] **Step 2: Review options access**

Confirm writes go through namespace setters or `addon.Options.Set`, not direct `addon.options` mutation.

- [ ] **Step 3: Apply only local cleanup**

Allowed edits: private helper cleanup, comments that clarify invariants, redundant local removal.
Disallowed edits: new migration behavior, new public aliases, SavedVariables shape changes.

- [ ] **Step 4: Verify**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all checks pass.

## Task 5: Tranche Report

**Files:**
- Modify if useful: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Record outcomes**

For each reviewed file, record `No change`, `Local cleanup`, or `Contract wave needed`.

- [ ] **Step 2: Check git diff**

Run:

```powershell
git diff --stat
git status --short
```

Expected: only intentional files changed.

- [ ] **Step 3: Decide next tranche**

Continue with `Localization/localization.en.lua`, `Localization/DiagnoseLog.en.lua`, `UI/Templates/Common.xml`,
and the first `Modules/*` files in TOC order.
