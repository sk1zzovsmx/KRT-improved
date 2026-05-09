# Loot Sources

KRT uses `!KRT/Modules/LootSourcesData.lua` as a static raid-only item source table.
The resolver targets stock WoW 3.3.5a raid data from Vanilla through WotLK.

Loot source data is used for passive Group Loot and Need Before Greed attribution before
timing-based fallbacks are considered. AtlasLoot and DataStore are not required at runtime.

## Runtime Rules

- Exact source matches create or reuse boss and trash records.
- Ambiguous or missing static data falls back to the existing context resolver.
- AtlasLoot and DataStore are not runtime dependencies for source resolution.

## Data Rules

- Prefer item IDs and NPC IDs over names.
- Use `kind = "trash"` for trash sources.
- Use `kind = "boss"` for boss sources.
- Add mode metadata when 10/25-player or normal/heroic availability differs.
- Exclude non-raid, vendor, crafted, PvP, reputation, and quest-only sources.

## Current Coverage

This commit seeds a small reviewed Icecrown Citadel smoke slice. The initial trash row for
Wodin's Lucky Necklace is curated against Deathbound Ward as an ICC trash source, not a claim
that the item is exclusive to that NPC. Full Vanilla, The Burning Crusade, and Wrath of the
Lich King raid coverage will be added and refined in later batches.

## Reference Sources

- Wowhead WotLK item 50761, Citadel Enforcer's Claymore:
  https://www.wowhead.com/wotlk/item=50761/citadel-enforcers-claymore
- Wowhead Icecrown Citadel WotLK loot guide:
  https://www.wowhead.com/wotlk/guide/raids/icecrown-citadel/loot
- Wowhead WotLK NPC 37007, Deathbound Ward:
  https://www.wowhead.com/wotlk/npc=37007/deathbound-ward
