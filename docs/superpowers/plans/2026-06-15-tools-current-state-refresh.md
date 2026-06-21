# Tools Current State Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh repo tooling files so `tools/` documents and reports the current
KRT workflow after the Mechanic removal and recent release/tooling consolidation.

**Architecture:** Keep `tools/krt.py` as the canonical cross-platform entrypoint,
with PowerShell scripts as lower-level wrappers. Keep `tools/krt_mcp_server.py`
exposing only repo-local skill/readiness/quality tools, and keep
`tools/dev-stack-status.ps1` focused on vendored skills, optional local installs,
and MCP readiness.

**Tech Stack:** Python 3, PowerShell, JSON-RPC MCP stdio, Lua 5.1 helper scripts,
existing `tools/krt.py` command wrappers.

---

### Task 1: Refresh Tools README Inventory

**Files:**
- Modify: `tools/README.md`

- [x] **Step 1: Replace the flat index intro with current ownership text**

Use this opening:

```markdown
# Tools

Stable index for repository tooling.

`tools/krt.py` is the canonical cross-platform entrypoint. Direct `*.ps1`
and Lua helper scripts remain available when a lower-level script contract is
needed by hooks, CI, MCP, or manual debugging. Paths stay flat under `tools/`
because AGENTS, hooks, docs, and MCP registrations reference them directly.
```

- [x] **Step 2: Group commands by current workflow**

Keep these groups in this order: `Daily Checks`, `SavedVariables Helpers`,
`Release Flow`, `Agent And MCP Tooling`, `Catalogs And Tree`, `Compatibility
Wrappers`, `Lua Helpers`.

- [x] **Step 3: Add the current command examples**

Use these exact commands:

```powershell
py -3 tools/krt.py dev-stack-status --json
py -3 tools/krt.py repo-quality-check --check all
py -3 tools/krt.py api-catalog-check
py -3 tools/krt.py pre-commit
```

```bash
python3 tools/krt.py dev-stack-status --json
python3 tools/krt.py repo-quality-check --check all
python3 tools/krt.py api-catalog-check
```

- [x] **Step 4: Run a spelling/obsolete reference scan**

Run:

```powershell
rg -n -i "mechanic|\bmech\b|legacy Mechanic|external addon analyzer" tools/README.md
```

Expected: no output.

### Task 2: Tighten Dev Stack Status Wording

**Files:**
- Modify: `tools/dev-stack-status.ps1`

- [x] **Step 1: Rename AFD-facing labels to repo workflow labels**

Change the human heading from:

```powershell
Write-Host "KRT AFD Stack Status"
```

to:

```powershell
Write-Host "KRT Repo Tooling Status"
```

- [x] **Step 2: Update readiness reasoning**

Change the JSON `reasoning` text to:

```powershell
"KRT repo tooling readiness depends on required commands, vendored skills, " +
"optional local skill installs, and MCP files agreeing."
```

- [x] **Step 3: Keep JSON shape stable**

Do not rename existing JSON fields such as `repoReady`, `localSkillsReady`,
`mcpReady`, `fullReady`, `commands`, `paths`, `vendoredSkills`, or
`localSkills`.

- [x] **Step 4: Verify both output modes**

Run:

```powershell
py -3 tools/krt.py dev-stack-status --json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev-stack-status.ps1
```

Expected: both commands exit 0 and no output mentions Mechanic/Mech.

### Task 3: Refresh MCP Tool Descriptions

**Files:**
- Modify: `tools/krt_mcp_server.py`

- [x] **Step 1: Align MCP server docstring with current scope**

Use:

```python
"""Repo-local MCP server for KRT repo tooling, skills, and addon checks."""
```

- [x] **Step 2: Update `dev_stack_status` tool description**

Use:

```python
"Inspect repo-local tooling, skill sync, and MCP readiness. "
"Use this first to understand what is missing on the current machine."
```

- [x] **Step 3: Update initialize instructions**

Use:

```python
"Use dev_stack_status first, use skills_* only for skill manifest or sync work, "
"and finish addon/tooling changes with repo_quality_check."
```

- [x] **Step 4: Smoke test MCP tools/list**

Run a Python JSON-RPC smoke test against `tools/krt_mcp_server.py` and confirm
the tool names are exactly:

```text
skills_manifest,skills_verify,skills_sync,dev_stack_status,repo_quality_check
```

### Task 4: Refresh Cleanup Wave Prompt

**Files:**
- Modify: `tools/api-contract-cleanup-wave.md`

- [x] **Step 1: Add current workflow constraints**

Add baseline bullets requiring the repo-local 55to53 workflow for complex
multi-file cleanup and confirming external Mechanic/Mech tooling is not part
of the active workflow.

- [x] **Step 2: Replace raw catalog command list with canonical CLI**

Use:

```text
py -3 tools/krt.py api-catalog-refresh
```

and keep the raw `fnmap-*` sequence only as an expanded fallback note.

- [x] **Step 3: Update final deliverables**

Keep the existing metrics delta deliverables and add:

```text
- parent plan, delegation notes if 55to53 was used, checks run, and risks left
```

### Task 5: Record And Verify

**Files:**
- Modify: `!KRT/CHANGELOG.md`
- Generated check only: `docs/TREE.md`

- [x] **Step 1: Add a tooling changelog note**

Add under `## Unreleased`:

```markdown
- **Repo tooling docs** - Refreshed `tools/` guidance and readiness/MCP wording
  to match the current non-Mechanic workflow.
```

- [x] **Step 2: Run final checks**

Run:

```powershell
git diff --check
py -3 tools/krt.py api-catalog-check
py -3 tools/krt.py repo-quality-check --check all
```

Expected: all exit 0.

- [x] **Step 3: Inspect final diff**

Run:

```powershell
git diff --stat
git status --short
```

Expected: only the planned files are modified.

## Self-Review

Spec coverage: the plan updates current `tools/` documentation, readiness text,
MCP wording, and the reusable cleanup prompt while preserving existing command
contracts.

Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps remain.

Type consistency: JSON field names and MCP tool names are unchanged except for
descriptive strings.
