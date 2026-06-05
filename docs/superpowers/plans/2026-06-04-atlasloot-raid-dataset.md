# AtlasLoot Raid Dataset Implementation Plan

**Status:** Implemented in this working tree.

**Goal:** Generate KRT-native raid and world-boss loot-source shards using AtlasLoot 3.3.5a
as the completeness reference, with no AtlasLoot runtime dependency.

**Architecture:** Keep the existing KRT runtime resolver and data shape. Add build-time tooling
that parses AtlasLoot source files through a declarative table-key map and regenerates the three
static KRT dataset shards.

**Tech Stack:** PowerShell for local commands, Python 3 for build-time generation, Lua 5.1
runtime-compatible generated data, existing KRT Lua test harness.

---

## File Structure

- Modified: `tests/release_stabilization_spec.lua`
  - Added real-dataset assertions for AtlasLoot-derived coverage and era separation.
- Created: `tools/atlasloot_raid_sources.py`
  - Build-time parser/generator. Reads AtlasLoot source files from a local checkout or downloads
    raw GitHub files. Applies the declarative raid table map and writes KRT Lua shard files.
- Created: `tools/atlasloot_raid_source_map.py`
  - Declarative AtlasLoot table-key mapping to expansion, raid, source, NPC ID, kind, and mode.
- Modified: `!KRT/Modules/Dataset/LootSources/Vanilla.lua`
  - Generated Vanilla raid and world-boss KRT data.
- Modified: `!KRT/Modules/Dataset/LootSources/BurningCrusade.lua`
  - Generated TBC raid and world-boss KRT data.
- Modified: `!KRT/Modules/Dataset/LootSources/Wrath.lua`
  - Generated Wrath raid KRT data.
- Modified: `docs/LOOT_SOURCES.md`
  - Documented AtlasLoot as the completeness reference and generated-data policy.
- Modified: `!KRT/CHANGELOG.md`
  - Added an Unreleased note for the expanded generated loot-source dataset.

## Completed Tasks

- [x] Added real dataset tests for representative AtlasLoot Vanilla, TBC, Wrath, and world-boss
  drops.
- [x] Added a Classic/Wrath Naxxramas separation test.
- [x] Added `tools/atlasloot_raid_source_map.py` with reviewed raid-instance table mappings.
- [x] Added `tools/atlasloot_raid_sources.py` for build-time KRT shard regeneration.
- [x] Regenerated Vanilla, TBC, and Wrath loot-source shards.
- [x] Updated `docs/LOOT_SOURCES.md`.
- [x] Updated `!KRT/CHANGELOG.md`.

## Representative Test Rows

- Vanilla: item `18832`, Molten Core, Garr, `normal40`.
- TBC: item `32351`, Black Temple, Essence of Anger, `normal25`.
- Wrath: item `44650`, The Eye of Eternity, Malygos, `normal10`.
- World boss: item `17070`, Azshara, Azuregos, `normal40`.
- World boss: item `30733`, Hellfire Peninsula, Doom Lord Kazzak, `normal40`.
- Era separation: Classic Naxxramas item `23054` stays `normal40`; Wrath Naxxramas item `39719`
  stays `normal25`.

## Verification

Run before final reporting:

```powershell
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```
