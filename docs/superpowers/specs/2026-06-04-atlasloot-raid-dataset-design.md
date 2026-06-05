# AtlasLoot Raid Dataset Design

## Goal

Use AtlasLoot 3.3.5a modules as the completeness reference for KRT loot-source data while
shipping a KRT-native raid and world-boss static dataset with no AtlasLoot runtime dependency
and no verbatim AtlasLoot table copy.

## Scope

KRT will import raid-instance and outdoor world-boss loot source coverage from these AtlasLoot
modules:

- `AtlasLoot_OriginalWoW/originalwow.lua`
- `AtlasLoot_BurningCrusade/burningcrusade.lua`
- `AtlasLoot_WrathoftheLichKing/wrathofthelichking.lua`

The import excludes dungeon, key, set collection, PvP, faction, vendor, emblem, badge, crafting
pattern-only, reputation, and quest-reward tables. Reviewed outdoor world-boss tables are mapped
as zone-backed raid records. Once a reviewed raid-instance or world-boss table is mapped, positive
item IDs inside that table are kept even if the item is a token, emblem, badge, quest starter,
recipe, mount, or legendary component.

## Architecture

The runtime contract remains unchanged:

- `!KRT/Modules/Dataset/LootSources/Vanilla.lua`
- `!KRT/Modules/Dataset/LootSources/BurningCrusade.lua`
- `!KRT/Modules/Dataset/LootSources/Wrath.lua`
- `!KRT/Modules/Dataset/LootSourcesData.lua`
- `!KRT/Modules/LootSources.lua`

AtlasLoot parsing is build-time tooling only. The generated Lua shard files append KRT-native
records to `LootSourcesData.Raw` using the current item/source shape:

```lua
{
    name = "Raid Name",
    sources = {
        {
            name = "Boss Name",
            npcId = 12345,
            kind = "boss",
            items = {
                { 12345, N25 },
            },
        },
    },
}
```

The generator owns source parsing and filtering. A declarative map owns semantics that
AtlasLoot does not expose as structured fields:

- AtlasLoot table key
- KRT raid or outdoor zone name
- KRT source name
- NPC ID
- source kind (`boss` or reviewed `trash`)
- mode (`normal10`, `normal20`, `normal25`, `normal40`, `heroic10`, `heroic25`)
- expansion shard

## Distinct Raid Eras

Raid names that exist in more than one era are separated by mode metadata and source shard.
The resolver already filters by raid size and difficulty, so the dataset must preserve these
boundaries:

- Classic `Naxxramas` uses `normal40`.
- Wrath `Naxxramas` uses `normal10` and `normal25`.
- Classic `Onyxia's Lair` uses `normal40`.
- Wrath `Onyxia's Lair` uses `normal10` and `normal25`.

Items shared across multiple bosses in the same mode remain shared. The resolver can later
disambiguate them from recent boss context; the generated data must not force a false source.

## Source Policy

AtlasLoot is GPL v2 and is used as a reference input for generated data, not bundled as a
runtime addon dependency. KRT must document the source URL, AtlasLoot version, and the fact
that generated records are normalized KRT item/source facts.

The release package still includes only `!KRT/`. Tooling and repo docs stay outside the addon
ZIP unless project release policy changes.

## Testing

The implementation must add or preserve tests that prove:

- Real generated data loads under the existing isolated harness.
- Known AtlasLoot-only gaps resolve, including representative Vanilla, TBC, Wrath, and world-boss
  drops.
- Classic and Wrath `Naxxramas` do not merge modes.
- Classic and Wrath `Onyxia's Lair` do not merge modes.
- Shared drops remain ambiguous without recent boss context.
- Generated Lua parses under Lua 5.1 syntax checks.

## Verification

Before completion, run:

```powershell
lua tests/release_stabilization_spec.lua
py -3 tools/krt.py repo-quality-check --check toc_files
py -3 tools/krt.py repo-quality-check --check lua_uniformity
py -3 tools/krt.py repo-quality-check --check raid_hardening
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-lua-syntax.ps1
```
