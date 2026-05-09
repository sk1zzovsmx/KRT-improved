# Loot Sources

KRT uses `!KRT/Modules/LootSourcesData.lua` as a static raid-only item source table.
The resolver targets stock WoW 3.3.5a raid data from Vanilla through WotLK.

Loot source data is used for passive Group Loot and Need Before Greed attribution before
timing-based fallbacks are considered. AtlasLoot and DataStore are not required at runtime.

## Runtime Rules

- Exact source matches create or reuse boss and trash records.
- Ambiguous or missing static data falls back to the existing context resolver.
- AtlasLoot and DataStore are not runtime dependencies for source resolution.
- Legacy raid sizes use `normal20` and `normal40`; Wrath raids use `normal10`, `normal25`,
  `heroic10`, and `heroic25` when mode-specific data differs.

## Data Rules

- Prefer item IDs and NPC IDs over names.
- Use `kind = "trash"` for trash sources.
- Use `kind = "boss"` for boss and encounter sources backed by raid boss NPC IDs.
- Add mode metadata when raid size, normal/heroic, or legacy raid availability differs.
- Exclude non-raid, vendor, crafted, PvP-only, reputation, and quest-only reward sources.
- Do not bulk-map generic trash tables that do not identify a specific NPC source.

## Current Coverage

Current generated coverage includes: Vanilla.

The table is intentionally conservative for trash. Boss and encounter loot is generated from
static guide tables, while generic trash sections without a unique NPC are omitted unless a
specific NPC mapping has been reviewed. This avoids replacing timing ambiguity with false NPC
attribution.

- Molten Core: 138 item IDs, 220 source edges, 11 NPC/encounter sources
- Onyxia's Lair: 16 item IDs, 16 source edges, 1 NPC/encounter sources
- Blackwing Lair: 78 item IDs, 92 source edges, 8 NPC/encounter sources
- Zul'Gurub: 105 item IDs, 107 source edges, 13 NPC/encounter sources
- Ruins of Ahn'Qiraj: 64 item IDs, 66 source edges, 7 NPC/encounter sources
- Temple of Ahn'Qiraj: 121 item IDs, 123 source edges, 12 NPC/encounter sources
- Naxxramas: 136 item IDs, 166 source edges, 14 NPC/encounter sources

## Reference Sources

- https://www.wowhead.com/classic/guide/blackwing-lair-loot-classic-wow
- https://www.wowhead.com/classic/guide/molten-core-loot-wow-classic
- https://www.wowhead.com/classic/guide/onyxia-onyxias-lair-strategy-wow-classic
- https://www.wowhead.com/classic/guide/ruins-ahnqiraj-aq20-loot-classic-wow
- https://www.wowhead.com/classic/guide/temple-ahnqiraj-aq40-loot-classic-wow
- https://www.wowhead.com/classic/guide/wow-classic-naxxramas-raid-loot-bosses-atiesh-frozen-runes
- https://www.wowhead.com/classic/guide/wow-classic-zulgurub-loot-guide
