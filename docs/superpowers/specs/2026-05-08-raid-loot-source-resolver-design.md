# KRT Raid Loot Source Resolver - Design

**Date:** 2026-05-08
**Branch:** fix/runtime-master-local-limit
**Approach:** Add a KRT-owned static raid loot-source resolver for Vanilla through WotLK raid drops.

## Goals

1. Resolve passive Group Loot and Need Before Greed loot to the correct raid source by item ID before
   falling back to timing-based loot context.
2. Cover raid drops from Vanilla through WotLK, including boss drops and relevant raid trash drops.
3. Keep the runtime implementation independent from optional third-party addons.
4. Preserve current loot-window, recent-death, boss-event, and trash fallback behavior when the static
   database is missing or ambiguous.
5. Keep the resolver deterministic and testable with focused regression coverage.

## Non-Goals

1. Do not scrape in-game tooltips, chat, or UI data to discover sources.
2. Do not make DataStore, AtlasLoot, or any other addon a required runtime dependency.
3. Do not add SavedVariables for the source database or resolver cache.
4. Do not add UI controls in the first implementation wave.
5. Do not auto-award, auto-trade, or auto-assign loot based on the resolver.

## Source Addon Assessment

DataStore is not a good source for this feature. Its public description frames it as a set of scanning
and storage services for account and character data, with modules such as containers, auctions, crafts,
inventory, quests, reputations, stats, and talents. It is not a raid loot table database.

AtlasLoot is closer to the need because it is a loot-table browser for bosses, dungeons, raids,
collections, PvP, reputation rewards, and similar sources. However, KRT should not depend on AtlasLoot at
runtime because its table layout is not a stable public API across forks and versions. AtlasLoot-style
data can be used as an offline generation input only if the license and data shape are acceptable.

References:
- https://www.curseforge.com/wow/addons/datastore
- https://www.curseforge.com/wow/addons/atlasloot-enhanced

## New Module

Add `!KRT/Modules/LootSources.lua`.

Responsibilities:
- Own the static item-to-raid-source lookup.
- Expose pure lookup and resolution helpers.
- Avoid references to Controllers, Widgets, frames, or SavedVariables.
- Avoid runtime dependency on AtlasLoot or DataStore.
- Normalize item IDs, instance names, source kinds, and source candidates.

Initial public API:

```lua
addon.LootSources.GetCandidates(itemId)
addon.LootSources.FindSource(itemId, context)
```

`GetCandidates(itemId)` returns every known raid source for the item.

`FindSource(itemId, context)` returns either a single resolved source or an unresolved reason. The API should
avoid choosing randomly when multiple candidates remain plausible.

Candidate shape:

```lua
{
    npcId = 36612,
    npcName = "Lord Marrowgar",
    raid = "Icecrown Citadel",
    kind = "boss",
    modes = {
        normal10 = true,
        normal25 = true,
        heroic10 = true,
        heroic25 = true,
    },
}
```

Resolved source shape:

```lua
{
    npcId = 36612,
    npcName = "Lord Marrowgar",
    raid = "Icecrown Citadel",
    kind = "boss",
    confidence = "exact",
}
```

Unresolved shape:

```lua
{
    reason = "ambiguous",
    candidates = candidates,
}
```

## Dataset Scope

The first dataset should be raid-only and cover:

- Molten Core
- Onyxia's Lair
- Blackwing Lair
- Zul'Gurub
- Ruins of Ahn'Qiraj
- Temple of Ahn'Qiraj
- Naxxramas 40, when a reliable source is available
- Karazhan
- Gruul's Lair
- Magtheridon's Lair
- Serpentshrine Cavern
- The Eye
- Battle for Mount Hyjal
- Black Temple
- Sunwell Plateau
- Naxxramas 10/25
- The Obsidian Sanctum
- The Eye of Eternity
- Vault of Archavon
- Ulduar
- Trial of the Crusader
- Onyxia's Lair level 80
- Icecrown Citadel
- The Ruby Sanctum

The dataset should include boss drops and meaningful raid trash drops. Low-value passive Group Loot
filtering remains owned by the existing loot service policy.

## Integration Flow

Current passive loot flow:

1. `START_LOOT_ROLL` calls `Loot:AddPassiveLootRoll`.
2. `PassiveGroupLoot` creates or updates a `GL:*` roll session.
3. `CHAT_MSG_LOOT` calls `Loot:AddLoot`.
4. `Loot:AddLoot` resolves roll metadata and asks Raid service for a `bossNid`.
5. Raid service uses session context, loot-window context, recent death context, boss event context, and
   trash fallback.

New flow:

1. Keep the existing session and pending-award behavior unchanged.
2. When `Loot:AddLoot` has parsed `itemId`, call a loot-source resolver before timing-based fallback.
3. If a `GL:*` roll session already has a remembered `bossNid`, keep using it.
4. If `LootSources.FindSource(itemId, context)` returns one compatible source, create or reuse the matching
   boss/trash record and bind the roll session to that `bossNid`.
5. If the resolver returns `ambiguous` or `missing`, keep the current fallback path.

This makes item-based resolution an earlier evidence source, not a replacement for all existing context.

## Resolution Policy

Resolution must be deterministic:

1. Filter candidates by current raid or zone name when available.
2. Filter candidates by raid size and difficulty when the dataset has mode metadata.
3. If one candidate remains, resolve it.
4. If the recent or current boss is among the remaining candidates, resolve to that boss.
5. If all remaining candidates are trash in the current raid and a single NPC remains, resolve to that
   trash NPC.
6. If multiple boss candidates remain, return `ambiguous`.
7. If multiple trash candidates remain without a reliable context hint, return `ambiguous`.
8. If no candidate remains, return `missing`.

The resolver must never select the first table entry just because it is first.

## Boss And Trash Records

Boss source:
- Reuse an existing `raid.bossKills[]` record by `sourceNpcId` or normalized name when possible.
- If missing, create one through the Raid service with source metadata indicating item-source resolution.

Trash source:
- Prefer a named trash record when the database identifies a single trash NPC.
- Use the existing generic trash bucket only when the item maps to shared trash or remains ambiguous.
- Store `sourceNpcId` when known so future loot from the same NPC can reuse the same record.

Suggested diagnostic source labels:
- `LootSources`
- `LootSourcesAmbiguous`
- `LootSourcesMissing`

Diagnostics should use `addon.Diagnose` templates.

## Data Ownership And Generation

The runtime addon should ship with a compact static Lua table owned by KRT. The source dataset can be
generated offline from an external loot table source, but the generated output should be reviewed and
checked into the repo.

Suggested repository files:

- `!KRT/Modules/LootSources.lua` for runtime lookup.
- `tools/generate-loot-sources.*` only if generation is automated in a later step.
- `docs/LOOT_SOURCES.md` to document source coverage and known ambiguity policy if the generated data is
  large or non-obvious.

Generation should prefer stable item IDs and NPC IDs over localized names. Names are still useful for
logger display and human review.

## Load Order

Add the new module after `Modules/Item.lua` and before raid/loot services, for example:

1. `Modules/Item.lua`
2. `Modules/LootSources.lua`
3. `Modules/IgnoredItems.lua`
4. `Modules/IgnoredMobs.lua`

The exact position should be reflected in `!KRT/!KRT.toc`, `AGENTS.md`, and architecture docs if the
implementation adds the file.

## Tests

Add focused tests to `tests/release_stabilization_spec.lua`.

Required cases:

1. Passive Group Loot boss item with no loot-window context resolves to the expected boss.
2. Passive Group Loot trash item with no loot-window context resolves to a named trash source when unique.
3. Shared boss item resolves to the recent boss when the recent boss is one of the candidates.
4. Shared boss item without a compatible context remains ambiguous and uses the existing fallback.
5. Unknown item uses the existing fallback unchanged.
6. Existing passive filters still skip green-quality items, gems, and recipes.
7. Resolver does not create duplicate boss/trash records when the same source is reused.

Manual checks:

1. Raid logger still opens and filters loot by selected boss/trash source.
2. Group Loot in ICC, Ulduar, ToC, and older raids records the expected source.
3. Ambiguous items produce debug diagnostics instead of random attribution.
4. `/reload` keeps persisted raid schema valid.

Quality gates:

```powershell
py -3 tools/krt.py repo-quality-check --check all
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

## Risks

Dataset accuracy is the main risk. An incorrect source table can produce confident but wrong logs. This
is why ambiguous cases must fall back instead of forcing a match.

Private server loot changes are another risk. The resolver should target stock 3.3.5a data first. Server
customizations can be handled later through explicit override tables if needed.

The table size should be monitored. If the full raid dataset becomes too large, split the data by
expansion or raid while keeping one public `addon.LootSources` facade.
