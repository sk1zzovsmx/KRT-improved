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

- Validator:
  `powershell -ExecutionPolicy Bypass -File tools/run-raid-validator.ps1 "<path>\\!KRT.lua"`
- Inspector (table + baseline metrics):
  `lua tools/sv-inspector.lua "<path>\\!KRT.lua"`
- Inspector (PowerShell wrapper on Windows):
  `powershell -ExecutionPolicy Bypass -File tools/run-sv-inspector.ps1 "<path>\\!KRT.lua"`
- Inspector CSV export (per-raid):
  `lua tools/sv-inspector.lua "<path>\\!KRT.lua" --format csv --section raids`
- Round-trip no-drift validation (single SV file):
  `lua tools/sv-roundtrip.lua "<path>\\!KRT.lua"`
- Round-trip compatibility suite on legacy/mixed fixtures:
  `powershell -ExecutionPolicy Bypass -File tools/run-sv-roundtrip.ps1 -Fixtures`
