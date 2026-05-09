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

Current generated coverage includes: Vanilla, The Burning Crusade, Wrath of the Lich King.

The table is intentionally conservative for trash. Boss and encounter loot is generated from
static guide tables, while generic trash sections without a unique NPC are omitted unless a
specific NPC mapping has been reviewed. This avoids replacing timing ambiguity with false NPC
attribution.

- Molten Core: 138 item IDs, 220 source edges, 11 NPC/encounter sources
- Onyxia's Lair: 86 item IDs, 86 source edges, 1 NPC/encounter sources
- Blackwing Lair: 78 item IDs, 92 source edges, 8 NPC/encounter sources
- Zul'Gurub: 105 item IDs, 107 source edges, 13 NPC/encounter sources
- Ruins of Ahn'Qiraj: 64 item IDs, 66 source edges, 7 NPC/encounter sources
- Temple of Ahn'Qiraj: 121 item IDs, 123 source edges, 12 NPC/encounter sources
- Naxxramas: 492 item IDs, 630 source edges, 18 NPC/encounter sources
- Karazhan: 146 item IDs, 200 source edges, 16 NPC/encounter sources
- Gruul's Lair: 25 item IDs, 25 source edges, 2 NPC/encounter sources
- Magtheridon's Lair: 18 item IDs, 18 source edges, 1 NPC/encounter sources
- Serpentshrine Cavern: 70 item IDs, 71 source edges, 6 NPC/encounter sources
- The Eye: 54 item IDs, 54 source edges, 4 NPC/encounter sources
- Hyjal Summit: 69 item IDs, 101 source edges, 5 NPC/encounter sources
- Black Temple: 110 item IDs, 128 source edges, 11 NPC/encounter sources
- Zul'Aman: 56 item IDs, 61 source edges, 6 NPC/encounter sources
- Sunwell Plateau: 92 item IDs, 131 source edges, 7 NPC/encounter sources
- The Obsidian Sanctum: 44 item IDs, 44 source edges, 1 NPC/encounter sources
- The Eye of Eternity: 32 item IDs, 32 source edges, 1 NPC/encounter sources
- Vault of Archavon: 701 item IDs, 797 source edges, 4 NPC/encounter sources
- Ulduar: 421 item IDs, 545 source edges, 16 NPC/encounter sources
- Trial of the Crusader: 561 item IDs, 3676 source edges, 36 NPC/encounter sources
- Icecrown Citadel: 501 item IDs, 609 source edges, 14 NPC/encounter sources
- The Ruby Sanctum: 56 item IDs, 56 source edges, 1 NPC/encounter sources

## Reference Sources

- https://www.wowhead.com/classic/guide/blackwing-lair-loot-classic-wow
- https://www.wowhead.com/classic/guide/molten-core-loot-wow-classic
- https://www.wowhead.com/classic/guide/onyxia-onyxias-lair-strategy-wow-classic
- https://www.wowhead.com/classic/guide/ruins-ahnqiraj-aq20-loot-classic-wow
- https://www.wowhead.com/classic/guide/temple-ahnqiraj-aq40-loot-classic-wow
- https://www.wowhead.com/classic/guide/wow-classic-naxxramas-raid-loot-bosses-atiesh-frozen-runes
- https://www.wowhead.com/classic/guide/wow-classic-zulgurub-loot-guide
- https://www.wowhead.com/tbc/guide/black-temple-loot-gear-guide-burning-crusade-classic
- https://www.wowhead.com/tbc/guide/gruuls-lair-and-magtheridons-lair-loot-guide-for-world-of-warcraft-burning-13462
- https://www.wowhead.com/tbc/guide/hyjal-summit-loot-gear-guide-burning-crusade-classic
- https://www.wowhead.com/tbc/guide/karazhan-raid-loot-gear-tier-tokens-burning-crusade-classic
- https://www.wowhead.com/tbc/guide/serpentshrine-cavern-ssc-loot-gear-guide-burning-crusade-classic
- https://www.wowhead.com/tbc/guide/sunwell-plateau-raid-gear-loot-burning-crusade-classic
- https://www.wowhead.com/tbc/guide/the-eye-raid-gear-loot-burning-crusade-classic-wow
- https://www.wowhead.com/tbc/guide/zulaman-za-loot-gear-guide-burning-crusade-classic
- https://www.wowhead.com/wotlk/guide/raids/eye-of-eternity-loot
- https://www.wowhead.com/wotlk/guide/raids/icecrown-citadel/loot
- https://www.wowhead.com/wotlk/guide/raids/naxxramas/loot
- https://www.wowhead.com/wotlk/guide/raids/obsidian-sanctum/loot
- https://www.wowhead.com/wotlk/guide/raids/onyxias-lair-80/loot
- https://www.wowhead.com/wotlk/guide/raids/ruby-sanctum/loot
- https://www.wowhead.com/wotlk/guide/raids/trial-of-the-crusader/loot
- https://www.wowhead.com/wotlk/guide/raids/trial-of-the-grand-crusader/loot
- https://www.wowhead.com/wotlk/guide/raids/ulduar/loot
- https://www.wowhead.com/wotlk/guide/raids/vault-of-archavon/loot
- https://www.wowhead.com/wotlk/npc=38433/toravon-the-ice-watcher
