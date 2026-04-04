# SV Sanity Checklist

Single checklist for SavedVariables integrity and schema hygiene.
Use this before releases and before/after schema refactors.

## Required checks

1. Top-level SV keys are present and tables:
   `KRT_Raids`, `KRT_Players`, `KRT_Reserves`, `KRT_Warnings`, `KRT_Spammer`, `KRT_Options`.
2. Every raid has a valid `schemaVersion` (number, `>= 1`, `<= current schema`).
3. Every raid includes canonical keys:
   `raidNid`, `players`, `bossKills`, `loot`, `changes`,
   `nextPlayerNid`, `nextBossNid`, `nextLootNid`, `startTime`.
4. Legacy runtime keys are absent at raid root:
   `_playersByName`, `_playerIdxByNid`, `_bossIdxByNid`, `_lootIdxByNid`.
5. Legacy/transient payload keys are absent after save compaction:
   `loot[].looter`, `bossKills[].attendanceMask`, `KRT_Reserves[*].playerNameDisplay`,
   `KRT_Reserves[*].original`, and reserve rows `KRT_Reserves[*].reserves[*].player`.
6. Canonical ID counters are coherent:
   `nextPlayerNid >= max(players[].playerNid) + 1`,
   `nextBossNid >= max(bossKills[].bossNid) + 1`,
   `nextLootNid >= max(loot[].lootNid) + 1`.
7. Canonical references are coherent:
   `bossKills[].players[*]` points to existing `players[].playerNid`,
   `loot[].bossNid` points to existing `bossKills[].bossNid` (or unknown/trash policy),
   `loot[].looterNid` points to existing `players[].playerNid`.
8. Schema freeze gate:
   keep `schemaVersion = 3` unless there is a net structural simplification that requires `v4`.

## Tooling

Use the real SavedVariables file path, for example
`WTF\\Account\\<Account>\\SavedVariables\\!KRT.lua`.

When you use the `tools/krt.py run-*` wrappers, the SavedVariables path is resolved from your current
working directory. This means you can launch the wrapper from repo root or from inside `!KRT/`
subfolders as long as both the path to `tools/krt.py` and the `--saved-variables-path` argument are
written relative to the folder you are currently in.

- Validator:
   `py -3 tools/krt.py run-raid-validator --saved-variables-path "<path>\\!KRT.lua"`
- Validator (PowerShell wrapper on Windows):
  `powershell -ExecutionPolicy Bypass -File tools/run-raid-validator.ps1 "<path>\\!KRT.lua"`
- Inspector (table + baseline metrics):
  `lua tools/sv-inspector.lua "<path>\\!KRT.lua"`
- Inspector (PowerShell wrapper on Windows):
  `powershell -ExecutionPolicy Bypass -File tools/run-sv-inspector.ps1 "<path>\\!KRT.lua"`
- Inspector (cross-platform wrapper):
   `py -3 tools/krt.py run-sv-inspector --saved-variables-path "<path>\\!KRT.lua" --format table --section baseline`
- Inspector CSV export (per-raid):
  `lua tools/sv-inspector.lua "<path>\\!KRT.lua" --format csv --section raids`
- Round-trip no-drift validation (single SV file):
  `lua tools/sv-roundtrip.lua "<path>\\!KRT.lua"`
- Round-trip compatibility suite on legacy/mixed fixtures:
   `py -3 tools/krt.py run-sv-roundtrip --fixtures`
- Round-trip compatibility suite on legacy/mixed fixtures (PowerShell wrapper on Windows):
  `powershell -ExecutionPolicy Bypass -File tools/run-sv-roundtrip.ps1 -Fixtures`
- Note: the bundled `legacy-mixed-*` fixtures are compatibility inputs for round-trip checks; they are not expected to pass the canonical validator unchanged.
- Composite hardening check (DB boundary + XML layout + validator + fixtures):
  `powershell -ExecutionPolicy Bypass -File tools/check-raid-hardening.ps1`
