# Audit Cleanup Micro-Wave Documentation/Test Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the R1 Reserves no-candidate guard and the generated function-cluster catalog
so the cleanup program can be closed with passing docs/test evidence.

**Architecture:** This is a documentation, test, and tooling-catalog micro-wave only. It restores
the explicit R1 hold contract in `TECH_CLEANUP_BACKLOG.md`, teaches the function classifier that
entrypoint-local `callControllerMethod(...)` helpers are intentional routing patterns, regenerates
the generated catalog files, and adds a small source-contract spec to prevent drift.

**Tech Stack:** PowerShell 5+, Lua/LuaJIT 5.1-compatible tests, KRT repo tooling under `tools/`,
generated docs under `docs/`.

---

## 55to53 Classification

Classification: `bounded`.

Reasoning:
- No addon runtime file under `!KRT/` is in scope.
- No SavedVariables, load order, service contract, controller behavior, or public UI behavior changes.
- The work touches docs, tests, and one catalog tooling rule.
- Parent direct implementation is allowed, but Subagent-Driven execution is still recommended for review.

Preferred project worker if using delegated execution: `tooling_worker`, because the task is primarily
tooling, generated documentation, and operational docs/test alignment.

## File Structure

- Create: `tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua`
  - Guards the R1 backlog contract and the `FN_CLUSTERS`/classifier alignment.
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`
  - Restore the explicit R1 hold phrase expected by the R1 no-candidate spec.
  - Record that `callControllerMethod(...)` is an intentional entrypoint-local routing pattern,
    not a high-confidence merge-now cleanup candidate.
- Modify: `tools/fnmap-classify.ps1`
  - Classify `callControllerMethod` under `!KRT/EntryPoints/*` as
    `structural-pattern` + `keep` with a stable cluster name.
- Generated: `docs/FUNCTION_REGISTRY.csv`
  - The two `callControllerMethod` rows should move from `clone-exact`/`merge` to
    `structural-pattern`/`keep`.
- Generated: `docs/FN_CLUSTERS.md`
  - The `merge-now` section should no longer list `callControllerMethod`.
  - The class summary should no longer report `clone-exact | 2`.
- Generated: `docs/TREE.md`
  - Update if catalog refresh or tree generation detects the new test/plan file.
- Do not modify: `!KRT/*`, `!KRT/CHANGELOG.md`, vendored libs.
  - There is no addon behavior or user-visible change.

## Task 1: Capture Baseline Failures

**Files:**
- Read: `tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua`
- Read: `docs/TECH_CLEANUP_BACKLOG.md`
- Read: `docs/FN_CLUSTERS.md`
- Read: `docs/FUNCTION_REGISTRY.csv`

- [ ] **Step 1: Confirm the R1 guard currently fails**

Run:

```powershell
lua tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua
```

Expected: FAIL with this missing phrase:

```text
hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method
```

- [ ] **Step 2: Confirm the catalog/backlog mismatch**

Run:

```powershell
rg -n 'callControllerMethod.*clone-exact|clone-exact \| 2|No high-confidence `merge-now`' docs/FN_CLUSTERS.md docs/TECH_CLEANUP_BACKLOG.md docs/FUNCTION_REGISTRY.csv
```

Expected:

```text
docs/FN_CLUSTERS.md:10:| clone-exact | 2 |
docs/FN_CLUSTERS.md:19:| - | callControllerMethod | clone-exact | merge | !KRT/EntryPoints/Minimap.lua | 46 |
docs/FN_CLUSTERS.md:20:| - | callControllerMethod | clone-exact | merge | !KRT/EntryPoints/SlashEvents.lua | 353 |
docs/TECH_CLEANUP_BACKLOG.md:907:1. No high-confidence `merge-now` duplicates remain after the stage-2 recatalog.
```

- [ ] **Step 3: Confirm the duplicate helpers are runtime-intentional**

Run:

```powershell
lua tests/audit_cleanup_wave_e1_slash_routing_spec.lua
lua tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
```

Expected:

```text
audit cleanup wave E1 slash routing source contract passed
audit cleanup wave E2 minimap entrypoint source contract passed
```

## Task 2: Add the Alignment Guard Spec

**Files:**
- Create: `tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua`

- [ ] **Step 1: Create the failing source-contract spec**

Create `tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua` with this content:

```lua
local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function getSection(text, title)
    local marker = "## " .. title
    local startPos = text:find(marker, 1, true)
    assert(startPos, "missing section: " .. title)

    local nextPos = text:find("\n## ", startPos + #marker, true)
    if nextPos then
        return text:sub(startPos, nextPos - 1)
    end
    return text:sub(startPos)
end

local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local clusters = read("docs/FN_CLUSTERS.md")
local classifier = read("tools/fnmap-classify.ps1")

assertContains(
    backlog,
    "hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method",
    "R1 backlog must keep the explicit Reserves hold contract"
)
assertContains(
    backlog,
    "keep `!KRT/Init.lua` and `!KRT/Services/Reserves.lua` in hold without new call-site evidence",
    "default next step must keep the combined Init/Reserves hold"
)
assertContains(
    backlog,
    "No high-confidence `merge-now` duplicates remain after the stage-2 recatalog",
    "backlog must keep the high-confidence merge-now closure statement"
)
assertContains(
    backlog,
    "Exact clone count reduced from `10` to `0`",
    "backlog must keep the exact-clone closure statement"
)

local mergeNow = getSection(clusters, "merge-now")
assertNotContains(
    mergeNow,
    "| - | callControllerMethod | clone-exact | merge |",
    "entrypoint controller dispatch helpers must not be merge-now candidates"
)
assertNotContains(
    clusters,
    "| clone-exact | 2 |",
    "FN_CLUSTERS must not report the stale callControllerMethod exact-clone count"
)
assertNotContains(
    clusters,
    "| callControllerMethod | clone-exact | merge |",
    "callControllerMethod must not be classified as clone-exact merge"
)
assertContains(
    classifier,
    '$functionKey -eq "callControllerMethod"',
    "fnmap classifier must own the callControllerMethod exception"
)
assertContains(
    classifier,
    '$row.File -match "^!KRT/EntryPoints/"',
    "fnmap classifier must scope the callControllerMethod exception to EntryPoints"
)

print("audit cleanup micro-wave docs/test alignment contract passed")
```

- [ ] **Step 2: Run the new spec and confirm it fails before implementation**

Run:

```powershell
lua tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua
```

Expected: FAIL on the missing R1 hold contract or the stale `callControllerMethod` clone.

## Task 3: Restore the R1 Hold Contract in the Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Add the explicit R1 hold line**

In `docs/TECH_CLEANUP_BACKLOG.md`, update the R1 section to contain this exact bullet:

```markdown
- hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method.
```

The resulting R1 section should include all of these lines:

```markdown
### Wave R1: Reserves Contract Review

Wave R1 completed the deeper Reserves facade review:
- alias, collapse, readiness, display, import, sync, cache, and roll-facing
  methods remain parent-facade contracts with current production call sites or
  documented public compatibility.
- no package-internal-only public Reserves method was proven safe to contract
  in this pass.
- future Reserves contraction requires a fresh owner-specific micro-plan backed
  by a new call-site inventory.
- hold further `!KRT/Services/Reserves.lua` contraction unless a fresh inventory proves a package-internal-only method.
- deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts is closed.
- alias, collapse, readiness, and display methods are currently real slash/UI/controller contracts.

Remaining Reserves contract review:
- None without new inventory evidence.
```

- [ ] **Step 2: Run the original R1 spec**

Run:

```powershell
lua tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua
```

Expected:

```text
audit cleanup wave R1 reserves contract review source contract passed
```

- [ ] **Step 3: Run the new alignment spec**

Run:

```powershell
lua tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua
```

Expected: still FAIL until the classifier and generated catalogs are aligned.

## Task 4: Classify Entrypoint Controller Dispatch Helpers as Intentional

**Files:**
- Modify: `tools/fnmap-classify.ps1`
- Generated: `docs/FUNCTION_REGISTRY.csv`
- Generated: `docs/FN_CLUSTERS.md`

- [ ] **Step 1: Add the classifier exception**

In `tools/fnmap-classify.ps1`, add this branch after the existing structural keep exceptions for
`Database.GetFeatureShared`, `Database.EnsureLootRuntimeState`, and `Database.GetController`,
and before the field/local closure and exact-clone branches:

```powershell
        if (
            $functionKey -eq "callControllerMethod" -and
            $row.File -match "^!KRT/EntryPoints/"
        ) {
            $row.Class = "structural-pattern"
            $row.Action = "keep"
            $row.Cluster = "entrypoint.controller-dispatch"
            continue
        }
```

This makes the classification durable. Do not hand-edit `docs/FN_CLUSTERS.md` to hide the
rows without changing the classifier.

- [ ] **Step 2: Regenerate the function catalog**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
```

Expected:

```text
Function classification complete.
```

- [ ] **Step 3: Verify the stale clone rows are gone**

Run:

```powershell
rg -n "callControllerMethod.*clone-exact|clone-exact \| 2" docs/FN_CLUSTERS.md docs/FUNCTION_REGISTRY.csv
```

Expected: no output and exit code `1`.

- [ ] **Step 4: Verify the intentional keep classification is present**

Run:

```powershell
rg -n "entrypoint.controller-dispatch.*callControllerMethod|callControllerMethod.*entrypoint.controller-dispatch" docs/FN_CLUSTERS.md docs/FUNCTION_REGISTRY.csv
```

Expected: hits for both `!KRT/EntryPoints/Minimap.lua` and `!KRT/EntryPoints/SlashEvents.lua`.

## Task 5: Record the Micro-Wave Outcome in the Backlog

**Files:**
- Modify: `docs/TECH_CLEANUP_BACKLOG.md`

- [ ] **Step 1: Add a short documentation/test alignment note**

In `docs/TECH_CLEANUP_BACKLOG.md`, under `### 8.2 Remaining high-confidence redundancies`,
keep the existing closure statement and add this note after the evidence line:

```markdown
   Micro-wave documentation/test alignment classifies the duplicated
   `callControllerMethod(...)` entrypoint helpers as intentional local routing
   patterns, not merge-now candidates.
```

The section should read:

```markdown
### 8.2 Remaining high-confidence redundancies

1. No high-confidence `merge-now` duplicates remain after the stage-2 recatalog.
   Evidence: `docs/FN_CLUSTERS.md` merge-now table is empty.
   Micro-wave documentation/test alignment classifies the duplicated
   `callControllerMethod(...)` entrypoint helpers as intentional local routing
   patterns, not merge-now candidates.

2. Remaining follow-up is contract review only:
   - `name-collision` entries that represent different owners with similar names
   - intentional bridge APIs such as the lean `Raid <-> Loot` boundary
```

- [ ] **Step 2: Run the new alignment spec**

Run:

```powershell
lua tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua
```

Expected:

```text
audit cleanup micro-wave docs/test alignment contract passed
```

## Task 6: Refresh Broad Catalogs and Tree

**Files:**
- Generated: `docs/FUNCTION_REGISTRY.csv`
- Generated: `docs/FN_CLUSTERS.md`
- Generated: `docs/API_REGISTRY.csv`
- Generated: `docs/API_REGISTRY_PUBLIC.csv`
- Generated: `docs/API_REGISTRY_INTERNAL.csv`
- Generated: `docs/API_NOMENCLATURE_CENSUS.md`
- Generated: `docs/TREE.md`

- [ ] **Step 1: Run the canonical catalog refresh**

Run:

```powershell
py -3 tools/krt.py api-catalog-refresh
```

Expected:

```text
Function inventory complete.
Function classification complete.
```

The exact command output can include API census and tree update lines.

- [ ] **Step 2: Run the catalog drift check**

Run:

```powershell
py -3 tools/krt.py api-catalog-check
```

Expected: PASS with no catalog drift.

- [ ] **Step 3: Inspect generated-file scope**

Run:

```powershell
git diff --name-only
```

Expected changed files are limited to:

```text
docs/TECH_CLEANUP_BACKLOG.md
tools/fnmap-classify.ps1
docs/FUNCTION_REGISTRY.csv
docs/FN_CLUSTERS.md
docs/TREE.md
tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua
docs/superpowers/plans/2026-06-14-audit-cleanup-micro-wave-doc-test-alignment.md
```

If API registry files change because `api-catalog-refresh` regenerates them with real drift,
review the diff and keep only generated changes explained by the classifier or new test/plan files.

## Task 7: Final Verification

**Files:**
- Test: `tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua`
- Test: `tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua`
- Test: `tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua`
- Test: `tests/audit_cleanup_wave_e1_slash_routing_spec.lua`
- Test: `tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua`
- Test: `tests/module_registry_ui_entrypoints_spec.lua`
- Tooling: `tools/fnmap-classify.ps1`

- [ ] **Step 1: Run focused cleanup specs**

Run:

```powershell
lua tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua
lua tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua
lua tests/audit_cleanup_wave_b1_bootstrap_follow_up_spec.lua
lua tests/audit_cleanup_wave_e1_slash_routing_spec.lua
lua tests/audit_cleanup_wave_e2_minimap_entrypoint_spec.lua
lua tests/module_registry_ui_entrypoints_spec.lua
```

Expected:

```text
audit cleanup micro-wave docs/test alignment contract passed
audit cleanup wave R1 reserves contract review source contract passed
audit cleanup wave B1 bootstrap follow-up source contract passed
audit cleanup wave E1 slash routing source contract passed
audit cleanup wave E2 minimap entrypoint source contract passed
module registry UI entrypoints source contract passed
```

- [ ] **Step 2: Run broad local gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
git diff --check
```

Expected:

```text
TOC file checks passed.
Lua uniformity checks passed.
Raid hardening checks passed.
Lua syntax check passed.
```

`git diff --check` should produce no output and exit `0`.

- [ ] **Step 3: Confirm no runtime files changed**

Run:

```powershell
git diff --name-only -- '!KRT'
```

Expected: no output.

No in-client smoke test is required for this micro-wave because it does not touch addon runtime
files, TOC load order, XML, SavedVariables, controllers, services, widgets, or entrypoints.

## Task 8: Commit

**Files:**
- Commit all changed files from this micro-wave.

- [ ] **Step 1: Review the final diff**

Run:

```powershell
git diff -- docs/TECH_CLEANUP_BACKLOG.md tools/fnmap-classify.ps1 docs/FUNCTION_REGISTRY.csv docs/FN_CLUSTERS.md docs/TREE.md tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua docs/superpowers/plans/2026-06-14-audit-cleanup-micro-wave-doc-test-alignment.md
```

Expected:
- No `!KRT/*` runtime diff.
- R1 backlog contains the explicit Reserves hold phrase.
- `tools/fnmap-classify.ps1` contains only the scoped `callControllerMethod` classifier exception.
- `docs/FN_CLUSTERS.md` no longer lists `callControllerMethod` in `merge-now`.
- New test is focused on docs/tooling alignment only.

- [ ] **Step 2: Stage the micro-wave files**

Run:

```powershell
git add -- docs/TECH_CLEANUP_BACKLOG.md `
  tools/fnmap-classify.ps1 `
  docs/FUNCTION_REGISTRY.csv `
  docs/FN_CLUSTERS.md `
  docs/TREE.md `
  tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua `
  docs/superpowers/plans/2026-06-14-audit-cleanup-micro-wave-doc-test-alignment.md
```

- [ ] **Step 3: Commit**

Run:

```powershell
git commit -m "docs: align cleanup catalog guards"
```

Expected: commit succeeds after hooks.

## Final Acceptance Criteria

- `lua tests/audit_cleanup_wave_r1_reserves_contract_review_spec.lua` passes.
- `lua tests/audit_cleanup_micro_wave_doc_test_alignment_spec.lua` passes.
- `docs/FN_CLUSTERS.md` `merge-now` section has no `callControllerMethod` rows.
- `docs/FN_CLUSTERS.md` class summary has no stale `clone-exact | 2` row.
- `docs/FUNCTION_REGISTRY.csv` marks both entrypoint `callControllerMethod` helpers as
  `entrypoint.controller-dispatch`, `structural-pattern`, `keep`.
- `docs/TECH_CLEANUP_BACKLOG.md` is internally consistent with `docs/FN_CLUSTERS.md`.
- No `!KRT/*` runtime files changed.
- Broad local gates pass.
