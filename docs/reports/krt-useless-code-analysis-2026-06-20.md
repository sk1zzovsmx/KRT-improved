# KRT Useless Code Analysis Report

## Baseline
- Branch: `codex/krt-reserve-list-item-grouped`
- HEAD: `b4274a41` (`HEAD -> codex/krt-reserve-list-item-grouped`)
- Context: Runtime scope constrained to review findings, no runtime edits.
- Environment policy: WotLK 3.3.5a, Interface 30300, Lua 5.1.

## Method Used
- Collected evidence via existing project scans and checks already executed by parent analysis.
- Compared findings against current ownership boundaries and public contracts.
- Normalized evidence to two actionable lanes: `Keep` or `Refactor` only.
- No speculative deletion decisions were made.

## Triage Matrix
Test aliases: `quality` = full repo quality check, `syntax` = Lua syntax check, `catalog` = API catalog check.

| ID | Lane | Candidate | Owner | Evidence | Keep/Delete/Refactor | Risk | Required Test | Notes |
|---|---|---|---|---|---|---|---|
| R1 | Dead Code | None proven | n/a | Empty `merge-now`; no XML scripts | Keep | Low | quality, syntax | Monitor. |
| R2 | Facades | Pass-throughs | Service files | Delegation hits | Refactor | Med | quality | Owner split. |
| R3 | Rules | Modern API scan | Project | No owned violations | Keep | Low | catalog, quality | False positives only. |
| R4 | Flow | Entry helpers | Slash/Minimap | Approved path | Keep | Low | quality | No back-edge. |
| R5 | Guards | Stale guard | Loot service | Line 150 | Refactor | Med | quality | Prove load. |
| R6 | SV | Direct `KRT_*` | Store owners | Expected owners | Keep | Low | raid | Preserve shape. |

## Finding Details
- Baseline checks show layered integrity is healthy: no staged API_nomenclature issues and no stale syntax warnings.
- `docs/FN_CLUSTERS.md` indicates high structural-pattern volume (`2176`) and name-collision
  items (`451`).
- No single proven useless-code cluster was confirmed in scope.
- Catalog check reports `2745` fnmap entries; API census reports `44` unique APIs, `40` public,
  `4` internal, no public non-conformity.
- Facade-style methods in service modules are currently consistent with existing service ownership.
- They likely represent API stability choices until an owner-specific map proves otherwise.
- A retired-alias scan returned no hits for banned legacy owners, so mixed-flow cleanup is not actionable here.
- No service-to-controller/widget back-edge was found in owner reference scan.
- UI XML policy remains consistent: no inline scripts in UI layout files.

## Findings By Lane
### Dead Code
- No reliable dead code candidate with high confidence was identified from the provided evidence.
- No delete actions were taken due to lack of conclusive execution proof.

### Redundant Functions And Public Facades
- Service facade methods in:
  - `!KRT/Services/Master/Service.lua`
  - `!KRT/Services/Rolls/Service.lua`
  - `!KRT/Services/Loot/Service.lua`
- Classified as `Refactor` to preserve external/parent contracts while preparing future simplification.

### Rule Violations
- No confirmed rule violations from namespace, API naming, or UI-script structure checks.
- Modern API scan false positives identified, including constants like `SPEC_ICON`, `SYNC_OFFICER`,
  and vendored `LibCompat`.
- Keep current behavior to avoid introducing API contract risk.

### Mixed Flows
- EntryPoints correctly use controller/widget call helper paths where observed.
- No evidence of prohibited service-to-frame direct coupling in runtime service scan.

### Wrappers, Failguards, And Shims
- The load-order guard note in `!KRT/Services/Loot/Service.lua:150` is a valid stability concern.
- `Refactor` lane only, pending explicit load-order proof and no behavior contract regression.

## False Positives Kept
- `SPEC_ICON`, `SYNC_OFFICER`, and constants-like symbols in modern API scans.
- Vendored `LibCompat` references.
- Large name-collision cluster counts in `docs/FN_CLUSTERS.md` without immediate actionability.

## Recommended Follow-Up Wave
### Scope
- Services/Master facade and pass-through review for behavior-preserving simplification.
### Non-goals
- No public behavior change, no API shape change, no SavedVariables migration in this wave.
- No changes to `!KRT/Services/Rolls/Service.lua` or `!KRT/Services/Loot/Service.lua` in this wave.
### Owner files
- `!KRT/Services/Master/Service.lua`
### Owned XML
- None.
### Public APIs to preserve
- All existing service facade signatures and external call contracts.
### SavedVariables to preserve
- `KRT_Raids`, `KRT_Players`, `KRT_Reserves`, `KRT_Warnings`, `KRT_Spammer`, `KRT_Options`.
### Static checks
- `py -3 tools/krt.py repo-quality-check --check all`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1`
- `api-catalog-check`
### In-game smoke path
- `/reload`, `/krt`, reserve interaction quick path, and loot warning/spam flow.

## Checks Run
- `git status --short` (exit 0; only untracked plan/report docs)
- `git diff --check` (exit 0)
- `py -3 tools/krt.py repo-quality-check --check all` (exit 0)
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1`
  (exit 0, 170 files, 0 warnings/errors)
- `lua tests/release_stabilization_spec.lua` (exit 0, 308 targeted stabilization tests passed)
- `py -3 tools/krt.py api-catalog-check` (exit 0; `fnmap` entries 2745, API census 44,
  catalogs up to date)
- Commit hook reran `api-catalog-check`; staging the new docs made `docs/TREE.md` refresh its
  tracked file listing for this report and plan.
- `rg -nP "[^\x00-\x7F]" docs/reports/krt-useless-code-analysis-2026-06-20.md`
  (exit 0 after no-match normalization; ASCII clean)
- `rg` mapping notes from parent/code-mapper pass:
  `Master.BuildSessionWinnersModel`, `Master.BuildSrSummaryText`, `Services/Master/FlowState.lua`,
  `Controllers/Master.lua`.
- TOC load-order evidence: `!KRT/!KRT.toc` loads `Services\Loot\DistributionSession.lua` at
  line 90 before `Services\Loot\Service.lua` at line 112.
- Fallback guard test evidence: `lua tests/release_stabilization_spec.lua` covers
  missing `DistributionSession` helper package loading path.

## Follow-Up Wave Result: Services/Master Facade
- Status: No code patch under current API-preservation rule.
- `!KRT/Services/Master/Service.lua` is the public `addon.Services.Master` facade.
- Removing facade wrappers would delete public signatures, and converting wrappers to direct aliases
  would change late-binding behavior.
- Direct-facade test-only methods:
  - `Master.BuildSessionWinnersModel` -> underlying `SessionWinners.BuildModel` runtime-used by
    `!KRT/Services/Master/FlowState.lua`.
  - `Master.BuildSrSummaryText` -> underlying `SoftRes.BuildSummaryText` runtime-used by
    `!KRT/Services/Master/FlowState.lua`.
- All other facade methods have runtime use from `!KRT/Controllers/Master.lua`.
- Next candidate after this no-op result: `!KRT/Services/Loot/Service.lua:150` stale-install/load-order
  guard; map before editing.

## Follow-Up Wave Result: Loot DistributionSession Guard
- Status: No code patch under current stability contract.
- `!KRT/!KRT.toc` loads `Services\Loot\DistributionSession.lua` before
  `Services\Loot\Service.lua`, so the fallback is not reached in a healthy packaged install.
- The guard in `!KRT/Services/Loot/Service.lua:getDistributionSession()` is still intentional:
  it preserves public Loot facade boot behavior for stale or incomplete packages where the
  helper file is missing or loaded late.
- `tests/release_stabilization_spec.lua` explicitly covers this path with
  `loot service keeps booting when the distribution helper file is missing`.
- Do not remove this guard unless the stale-package compatibility contract and its release
  stabilization test are intentionally retired.

## Remaining Risks
- Service facades may be intentional API preservation points.
- Refactor can be delayed if cross-team contracts are strict.
- Failguard/comment cleanup in `!KRT/Services/Loot/Service.lua` requires load-order proof before any structural change.
- Large cluster counts in `docs/FN_CLUSTERS.md` may contain future cleanup opportunities not actionable now.
