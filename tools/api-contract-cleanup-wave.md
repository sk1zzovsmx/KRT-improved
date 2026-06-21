# Addon Cleanup Wave Prompt

Copy/paste this prompt to run a future staged cleanup wave across the whole addon.

```text
Run a new staged cleanup wave for this addon.

Baseline:
- Use docs/TECH_CLEANUP_BACKLOG.md and repo docs as the planning baseline.
- Re-catalog the repo before changing code.
- Use the repo-local delegated 55to53 workflow for complex multi-file cleanup:
  parent plans, code-mapper maps when ownership is unclear, spark_implementer
  applies bounded patches, and parent reviews/corrects before closing.
- External addon analyzer companions are not part of the active workflow.
- Cover the whole addon surface: Database, Controllers, Services, Widgets,
  EntryPoints, Modules, UI/XML, docs, and touched tooling.

Process requirements:
1. Rebuild inventories with the canonical CLI:
   - py -3 tools/krt.py api-catalog-refresh
   Expanded fallback sequence, only when the CLI wrapper is unavailable:
   - powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-inventory.ps1
   - powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-classify.ps1
   - powershell -NoProfile -ExecutionPolicy Bypass -File tools/fnmap-api-census.ps1
   - powershell -NoProfile -ExecutionPolicy Bypass -File tools/update-tree.ps1
2. Review each candidate module, function, exported API, UI binding, and doc
   reference and classify it:
   - canonical public contract
   - package-internal helper
   - retired alias or redundant facade
   - dead or redundant surface
   - stale documentation or generated-catalog drift
3. Only land high-confidence changes:
   - remove pass-through wrappers when a canonical owner already exists
   - collapse duplicate helpers under canonical ownership
   - keep service/UI layering intact
   - fix stale docs and catalog drift created by the cleanup
   - keep behavior unchanged unless it is explicitly planned and documented
   - do not add new compatibility shims unless explicitly required
4. Execute the work in explicit stages.
5. After every stage:
   - update docs/*
   - regenerate inventories/catalogs
   - rerun the relevant checks/tests
   - continue only if the stage is clean

Scope priorities:
1. redundant public facades and duplicated contracts
2. UI-local helpers exposed as public controller/service APIs
3. dead or stale docs, catalogs, and tree entries
4. naming, ownership, or layering drift with a clear canonical owner
5. feature-local cleanup that reduces surface area without changing behavior

Guardrails:
- Preserve module ownership boundaries.
- Keep Services UI-free and preserve event-driven refresh boundaries.
- Do not touch vendored libraries.
- Do not change SavedVariables shape without an explicit migration and
  CHANGELOG entry.
- If a stage touches rollout-sensitive modules, run the targeted regression
  tests for that area.
- Always run:
  - py -3 tools/krt.py repo-quality-check --check all

Deliverables:
- updated docs/* and tooling docs touched by the cleanup
- refreshed FUNCTION_REGISTRY / FN_CLUSTERS / API_REGISTRY / TREE
- a short stage-by-stage summary
- parent plan, delegation notes if 55to53 was used, checks run, and risks left
- final metrics delta:
  - function inventory
  - total API surface
  - public API surface
  - public unclassified
  - name collisions
  - merge-now candidates
- explicit note on what was intentionally left unchanged
```
