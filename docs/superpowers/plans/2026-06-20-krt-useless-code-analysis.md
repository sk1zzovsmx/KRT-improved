# KRT Useless Code Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run an analysis-first cleanup audit that identifies dead code, redundant functions,
rule violations, mixed flows, and excessive wrappers/failguards/shims before any code removal.

**Architecture:** This is an evidence-gathering pass, not a refactor wave. KRT's local function/API
catalogs, cleanup backlog, architecture docs, and source-contract specs are the primary evidence
sources. External Lua/code-review material informs the method, but KRT ownership boundaries decide
whether a candidate is kept, deleted, or moved into a later cleanup wave.

**Tech Stack:** WoW WotLK 3.3.5a, Interface 30300, Lua 5.1, PowerShell 5+, `rg`, KRT `tools/krt.py`,
KRT fnmap/API catalogs, Lua source-contract tests, and optional one-off external duplicate/complexity
checks.

---

## 55to53 Classification

Classification for this planning task: `complex-orchestrated`, docs-only artifact.

Classification for any future code removal/refactor wave produced by this analysis:
`complex-orchestrated`.

Reasoning:

- The future work can touch multiple owners and public contracts.
- The analysis must map call flow, public API exposure, generated catalogs, tests, and docs.
- Any actual removal needs parent planning, optional `code-mapper`, `spark_implementer` for bounded
  patches, and parent review before close-out.

No addon runtime edits are in scope for this plan file.

## External Method Inputs

- Google code review standard:
  https://google.github.io/eng-practices/review/reviewer/standard.html
- Google code-review checklist:
  https://google.github.io/eng-practices/review/reviewer/looking-for.html
- Luacheck warning list:
  https://luacheck.readthedocs.io/en/stable/warnings.html
- Lua 5.1 reference manual mirror for local/global lexical scope:
  https://gensoft.pasteur.fr/docs/lua/5.1.4/manual.html
- jscpd duplicate detector:
  https://github.com/kucherenko/jscpd
- lizard complexity analyzer:
  https://github.com/terryyin/lizard

Method adopted for KRT:

- Code health improvement is the bar, not maximal deletion.
- Every finding needs evidence from current code, not only a catalog label.
- Complexity findings should ask whether code can be understood quickly and changed safely.
- Luacheck-style unused/global/control-flow warnings are useful signals, but KRT's `.luacheckrc`
  intentionally ignores some WoW-compatible warning classes; warnings are triage inputs, not final
  verdicts.
- Lua 5.1 global/local scoping makes undeclared globals and accidental public surfaces important
  cleanup signals.
- jscpd/lizard can inspire optional one-off duplicate and complexity checks; they are not new
  mandatory repo dependencies.
- KRT fnmap/API catalogs remain the primary duplicate/API evidence source.

## File Structure

Read:

- `AGENTS.md`
- `docs/TECH_CLEANUP_WORKFLOW.md`
- `docs/TECH_CLEANUP_BACKLOG.md`
- `docs/ARCHITECTURE.md`
- `docs/LUA_WRITING_RULES.md`
- `docs/DEV_CHECKS.md`
- `docs/FUNCTION_REGISTRY.csv`
- `docs/FN_CLUSTERS.md`
- `docs/API_REGISTRY.csv`
- `docs/API_REGISTRY_PUBLIC.csv`
- `docs/API_REGISTRY_INTERNAL.csv`
- `docs/API_NOMENCLATURE_CENSUS.md`

Create during analysis execution, not during this plan-writing step:

- `docs/reports/krt-useless-code-analysis-2026-06-20.md`

Do not modify during analysis execution unless explicitly promoted into a later implementation wave:

- `!KRT/*`
- `tools/*`
- `tests/*`
- generated catalog files

If the analysis needs fresh generated evidence, run catalog refresh on a dedicated task branch and
stage generated evidence separately from any later code-removal patch.

## Decision Rules

Delete only when all of these are true:

- No production caller exists.
- No test/source-contract caller exists.
- No runtime event dispatch, string dispatch, slash command, popup callback, or XML frame-name path
  can reach it.
- No public facade, compatibility alias, SavedVariables/DB boundary, or library callback depends on
  it.
- No docs/backlog entry says the area is a hold or monitor-only surface.

Refactor only when all of these are true:

- One canonical owner is clear.
- Behavior can be locked with an existing or new source-contract test before the change.
- The refactor can be split into a single-owner patch.
- Public API and generated-catalog impact can be explained.

Keep when any of these are true:

- Framework hook or config callback.
- WoW event handler.
- EntryPoint routing helper.
- Vendored library or compatibility shim.
- XML named-frame contract.
- Public SavedVariables/DB boundary.
- Documented hold area such as `Services/Reserves.lua` or `Init.lua` without fresh owner proof.

## False-Positive Exemptions

- `UI.Scaffold`, `ListController`, popup, EasyMenu, and XML frame-name hooks.
- EntryPoint-local `callControllerMethod(...)` and `callWidgetMethod(...)` routing helpers.
- WoW event handlers and method-name dispatch endpoints.
- Vendored libraries under `!KRT/Libs/*`.
- Allowed `OnUpdate` paths: minimap drag, LibCompat internals, and shared UI drivers/effects.
- `addon:Print`, the retained root-method compatibility exception.
- Reserves and bootstrap hold areas unless a fresh inventory proves a package-internal-only method.

---

### Task 1: Preflight and Evidence Snapshot

**Files:**

- Read: `AGENTS.md`
- Read: `docs/TECH_CLEANUP_WORKFLOW.md`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`
- Read: `docs/DEV_CHECKS.md`

- [ ] **Step 1: Capture branch and HEAD**

Run:

```powershell
git status --short --branch
git log -1 --oneline --decorate
```

Expected:

- Branch name and HEAD commit are recorded in the analysis report.
- Any dirty files are listed before running catalog or test commands.

- [ ] **Step 2: Record the baseline health gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```

Expected:

- Exit `0` for both commands.
- If a command fails, record the failure as baseline evidence and stop before candidate scoring.

### Task 2: Rebuild or Verify Function/API Catalog Evidence

**Files:**

- Read: `docs/FUNCTION_REGISTRY.csv`
- Read: `docs/FN_CLUSTERS.md`
- Read: `docs/API_REGISTRY.csv`
- Read: `docs/API_REGISTRY_PUBLIC.csv`
- Read: `docs/API_REGISTRY_INTERNAL.csv`
- Read: `docs/API_NOMENCLATURE_CENSUS.md`

- [ ] **Step 1: Check current catalog drift**

Run:

```powershell
py -3 tools/krt.py api-catalog-check
```

Expected:

- Exit `0` and no tracked diff.
- If generated files change, record the diff as catalog drift and stop before triage decisions.

- [ ] **Step 2: Refresh catalogs only on an approved evidence branch**

Run the canonical wrapper:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

Fallback only if the wrapper is unavailable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
```

Expected:

- Exit `0`.
- Catalog generation runs in inventory -> classify -> API census -> tree order.
- Generated deltas are evidence for the report, not automatic cleanup authorization.

### Task 3: Dead Code Candidate Inventory

**Files:**

- Read: `docs/FUNCTION_REGISTRY.csv`
- Read: `docs/API_REGISTRY_PUBLIC.csv`
- Read: `tests/*.lua`
- Read: `!KRT/**/*.lua`

- [ ] **Step 1: Extract functions with weak or missing call evidence**

Run:

```powershell
Import-Csv docs/FUNCTION_REGISTRY.csv |
  Where-Object { $_.File -like '!KRT/*' } |
  Select-Object Function,File,Line,Class,Action |
  Sort-Object File,Line |
  Format-Table -AutoSize
```

Expected:

- Candidate list is available for manual owner/caller review.
- No function is marked delete from registry data alone.

- [ ] **Step 2: Check exact-name call sites for each candidate**

For each candidate function name from Step 1, run:

```powershell
rg -n --fixed-strings "CandidateFunctionName" !KRT tests docs -g "*.lua" -g "*.md" -g "*.csv"
```

Expected:

- Report records production callers, test callers, docs references, and generated-catalog references.
- Candidates with only their definition still require dynamic-dispatch and public-contract checks.

### Task 4: Redundant Function and Public Facade Inventory

**Files:**

- Read: `docs/FN_CLUSTERS.md`
- Read: `docs/API_REGISTRY_PUBLIC.csv`
- Read: `docs/API_NOMENCLATURE_CENSUS.md`
- Read: `!KRT/Services/**/*.lua`
- Read: `!KRT/Controllers/**/*.lua`
- Read: `!KRT/EntryPoints/**/*.lua`

- [ ] **Step 1: Capture duplicate and facade signals**

Run:

```powershell
$catalogSignals = "merge-now|clone-exact|clone-near|name-collision|public-unclassified"
rg -n $catalogSignals docs/FN_CLUSTERS.md docs/API_NOMENCLATURE_CENSUS.md
```

Expected:

- Current duplicate and API-shape signals are copied into the report.
- `name-collision` rows are not treated as removal candidates without owner review.

- [ ] **Step 2: Locate pass-through and public facade patterns**

Run:

```powershell
$passThrough = "return [A-Za-z0-9_\\.]+:[A-Za-z0-9_]+\\(|" +
  "return [A-Za-z0-9_\\.]+\\.[A-Za-z0-9_]+\\("
rg -n $passThrough !KRT/Services !KRT/Controllers !KRT/EntryPoints

$retiredAliases = "addon\\.(Master|Raid|Config|Frames|UIScaffold|" +
  "ListController|UIPrimitives|UIRowVisuals|MultiSelect)"
rg -n $retiredAliases !KRT -g "*.lua" -g "!Libs/**"
```

Expected:

- Pass-through wrappers are grouped by canonical owner.
- Retired root alias hits are either absent or become rule-violation candidates.

### Task 5: Rule-Violation and Architecture Drift Audit

**Files:**

- Read: `docs/ARCHITECTURE.md`
- Read: `docs/LUA_WRITING_RULES.md`
- Read: `docs/UI_CODING_RULES.md`
- Read: `!KRT/**/*.lua`
- Read: `!KRT/UI/**/*.xml`

- [ ] **Step 1: Run service/UI and XML ownership scans**

Run:

```powershell
rg -n "CreateFrame|SetScript|:Show\\(|:Hide\\(|addon\\.UI|GameTooltip" !KRT/Services -g "*.lua" -g "!Libs/**"
rg -n "<Scripts>|<On[A-Za-z]+>" !KRT/UI -g "*.xml"
```

Expected:

- Services remain UI-free.
- XML remains layout-only.
- Any hit is classified with owner, risk, and existing exception status.

- [ ] **Step 2: Run Lua contract and options scans**

Run:

```powershell
$doubleBinding = "feature\\.[A-Za-z_][A-Za-z0-9_]*\\s+or\\s+addon\\.|" +
  "addon\\.[A-Za-z_][A-Za-z0-9_]*\\s+or\\s+feature\\."
rg -n $doubleBinding !KRT -g "*.lua" -g "!Libs/**"

$savedVariables = "addon\\.options|KRT_Options|KRT_Raids|KRT_Players|" +
  "KRT_Reserves|KRT_Warnings|KRT_Spammer"
rg -n $savedVariables !KRT -g "*.lua" -g "!Libs/**"

$modernApi = "C_Timer|C_[A-Za-z0-9_]+|table\\.pack|table\\.unpack|bit32|" +
  "SetAtlas|SetColorTexture|SetMask|xpcall\\s*\\([^,]+,[^,]+,"
rg -n $modernApi !KRT -g "*.lua" -g "!Libs/**"
```

Expected:

- Double-binding fallbacks are absent.
- Direct SavedVariables access is owned or explicitly reviewed.
- WotLK/Lua 5.1 incompatibility hits are absent or documented compatibility code.

### Task 6: Mixed-Flow and Wrapper/Shim Audit

**Files:**

- Read: `!KRT/Services/**/*.lua`
- Read: `!KRT/Controllers/**/*.lua`
- Read: `!KRT/Modules/**/*.lua`
- Read: `!KRT/EntryPoints/**/*.lua`

- [ ] **Step 1: Locate guard, fallback, compat, and shim clusters**

Run:

```powershell
$guardSignals = "fallback|compat|shim|wrapper|guard|fail|pcall\\(|xpcall\\(|" +
  "type\\([^\\)]*\\) == ""function""|if not [A-Za-z0-9_\\.]+ then return"
rg -n $guardSignals `
  !KRT/Services !KRT/Controllers !KRT/Modules !KRT/EntryPoints `
  -g "*.lua" -g "!Libs/**"
```

Expected:

- Findings are categorized as real guard, compatibility shim, defensive drift, or removable wrapper.
- No guard is removed unless the load-order or owner contract proves it cannot fail.

- [ ] **Step 2: Identify mixed owner flows**

Run:

```powershell
$ownerRefs = "addon\\.Services\\.|addon\\.Controllers\\.|addon\\.Widgets\\.|" +
  "addon\\.Database\\.|addon\\.UI\\."
rg -n $ownerRefs `
  !KRT/Services !KRT/Controllers !KRT/Widgets !KRT/EntryPoints `
  -g "*.lua" -g "!Libs/**"
```

Expected:

- Service-to-UI or Service-to-Controller back-edges are treated as high-priority findings.
- Controller/Widget/EntryPoint calls are reviewed against `docs/ARCHITECTURE.md`.

### Task 7: Triage Matrix and Report Draft

**Files:**

- Create: `docs/reports/krt-useless-code-analysis-2026-06-20.md`

- [ ] **Step 1: Create the report with the required evidence sections**

Run:

```powershell
$report = @'
# KRT Useless Code Analysis Report

## Baseline

- Branch:
- HEAD:
- Catalog status:
- Gate status:

## Triage Matrix

| ID | Lane | Candidate | Owner | Evidence | Keep/Delete/Refactor | Risk | Required Test | Notes |
|----|------|-----------|-------|----------|----------------------|------|---------------|-------|

## Findings By Lane

### Dead Code

### Redundant Functions And Public Facades

### Rule Violations

### Mixed Flows

### Wrappers, Failguards, And Shims

## False Positives Kept

## Recommended Follow-Up Waves

## Checks Run

## Remaining Risks
'@
New-Item -ItemType Directory -Force docs/reports | Out-Null
Set-Content -LiteralPath docs/reports/krt-useless-code-analysis-2026-06-20.md -Value $report -Encoding ASCII
```

Expected:

- Report file exists.
- It contains the triage matrix and all lane sections.
- Empty sections are filled during analysis before the report is considered complete.

- [ ] **Step 2: Fill the triage matrix from evidence only**

Required table schema:

| ID | Lane | Candidate | Owner | Evidence | Keep/Delete/Refactor | Risk | Required Test | Notes |
|----|------|-----------|-------|----------|----------------------|------|---------------|-------|

Expected:

- Each row has a concrete file/function candidate and evidence path.
- Decision values are exactly `Keep`, `Delete`, or `Refactor`.
- `Delete` rows satisfy every delete rule in this plan.

### Task 8: Parent Review Gate and Follow-Up Wave Selection

**Files:**

- Read: `docs/reports/krt-useless-code-analysis-2026-06-20.md`
- Read: `git diff --stat`

- [ ] **Step 1: Run final analysis gates**

Run:

```powershell
git status --short
git diff --check
py -3 tools/krt.py repo-quality-check --check all
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
lua tests/release_stabilization_spec.lua
```

Expected:

- Exit `0`.
- Only the report and explicitly approved generated evidence files are changed.
- Runtime addon files remain untouched during analysis-only execution.

- [ ] **Step 2: Select one follow-up implementation wave**

Parent review must classify the top candidate wave before any code edit:

```text
Scope:
Non-goals:
Owner files:
Owned XML:
Public APIs to preserve:
SavedVariables to preserve:
Static checks:
In-game smoke path:
```

Expected:

- Exactly one owner-centered follow-up wave is selected.
- The wave is small enough for `spark_implementer` to receive closed operational instructions.
- Lower-confidence findings remain in the report as holds, not speculative edits.

## Validation Gates

For this analysis-only pass:

```powershell
git diff --check
py -3 tools/krt.py repo-quality-check --check all
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
lua tests/release_stabilization_spec.lua
```

For later code removal/refactor waves, add owner-specific source-contract tests and, when runtime
behavior changes are possible, in-game WotLK 3.3.5a smoke:

- `/reload` without new errors.
- `/krt` opens.
- Raid detection and roster update.
- Rolls flow.
- Reserves import/list/whisper path.
- Logger list, filters, export, and selection.
- Master award/trade/counter path.
- Warnings and Spammer channels.

## Remaining Risks

- Static analysis can miss string dispatch, XML named-frame lookup, and WoW event dispatch.
- `.luacheckrc` intentionally suppresses some warnings for WoW/Lua compatibility, so Luacheck-style
  findings need manual triage.
- Catalog `name-collision` rows are often owner taxonomy noise, not cleanup candidates.
- Removing guards without load-order proof can turn harmless defensive code into startup errors.
- Any future code deletion still needs client smoke because static tests cannot fully prove FrameXML,
  taint/combat lockdown, addon-message timing, or private-server runtime behavior.

## Execution Options

1. Subagent-Driven (recommended): use project 55to53 orchestration. Parent writes the owner plan,
   `code-mapper` maps uncertain ownership, `spark_implementer` applies only the approved patch, and
   parent reviews/corrects before close-out.
2. Inline Execution for analysis-only steps: run Tasks 1-8 in this session, produce only the report
   and explicitly approved generated evidence, then stop before any code removal.
