# Raid Loot Source Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** Resolve passive Group Loot and Need Before Greed raid drops to deterministic boss or trash
sources by item ID before falling back to timing-based loot context.

**Architecture:** Add a pure `addon.LootSources` module backed by KRT-owned static raid-source data.
`Services/Loot/Service.lua` passes parsed `itemId` into Raid context resolution, and
`Services/Raid/State.lua` creates or reuses boss/trash records from resolved sources before current
fallbacks run.

**Tech Stack:** WoW 3.3.5a, Lua 5.1, KRT service modules, `tests/release_stabilization_spec.lua`,
PowerShell repo gates through `tools/krt.py`.

---

## File Structure

- Create `!KRT/Modules/LootSourcesData.lua`
  Static item-to-source data. It exports `addon.LootSourcesData` with a `ByItemId` field.

- Create `!KRT/Modules/LootSources.lua`
  Pure resolver facade. It exports `addon.LootSources.GetCandidates`,
  `addon.LootSources.Resolve`, and `_SetDataForTests`.

- Modify `!KRT/!KRT.toc`
  Load `Modules\LootSourcesData.lua` and `Modules\LootSources.lua` after `Modules\Item.lua`.

- Modify `tests/release_stabilization_spec.lua`
  Load the new modules in the harness and add resolver plus passive loot integration tests.

- Modify `!KRT/Services/Raid/State.lua`
  Add item-source resolution before timing fallback and add a private creator for loot-source records.

- Modify `!KRT/Services/Loot/Service.lua`
  Pass parsed `itemId` into Raid source resolution for normal loot and trade-only loot.

- Modify `!KRT/Localization/DiagnoseLog.en.lua`
  Add diagnostic templates for exact, missing, and ambiguous loot-source resolution.

- Modify `!KRT/CHANGELOG.md`
  Add an Unreleased behavior note because raid logger attribution changes.

- Modify docs as needed
  Update `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/OVERVIEW.md`, and generated `docs/TREE.md` when
  new runtime files are added.

---

### Task 1: Add Pure Resolver Tests

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add a pure resolver test block after `newHarness()` is available**

Add this test block near the other service-level tests, before passive Group Loot integration tests:

```lua
test("loot source resolver filters candidates by raid and mode", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91710] = {
            {
                npcId = 15953,
                npcName = "Grand Widow Faerlina",
                raid = "Naxxramas",
                kind = "boss",
                modes = { normal10 = true },
            },
            {
                npcId = 36612,
                npcName = "Lord Marrowgar",
                raid = "Icecrown Citadel",
                kind = "boss",
                modes = { normal10 = true },
            },
        },
    })

    local resolved = h.addon.LootSources.Resolve(91710, {
        raid = "Naxxramas",
        difficulty = 3,
        raidSize = 10,
    })

    assertEqual(resolved.reason, nil, "expected a resolved source")
    assertEqual(resolved.npcId, 15953, "expected the Naxxramas source to match")
    assertEqual(resolved.npcName, "Grand Widow Faerlina", "expected resolved boss name")
    assertEqual(resolved.kind, "boss", "expected boss source kind")
    assertEqual(resolved.confidence, "exact", "expected exact source confidence")
end)

test("loot source resolver refuses ambiguous candidates without context", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91712] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15954, npcName = "Noth the Plaguebringer", raid = "Naxxramas", kind = "boss" },
        },
    })

    local resolved = h.addon.LootSources.Resolve(91712, {
        raid = "Naxxramas",
        difficulty = 3,
        raidSize = 10,
    })

    assertEqual(resolved.reason, "ambiguous", "expected shared boss item to stay ambiguous")
    assertEqual(#resolved.candidates, 2, "expected both candidates to be reported")
end)
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: failure because `h:load("!KRT/Modules/LootSources.lua")` is not supported yet, or because
`addon.LootSources` is nil.

- [ ] **Step 3: Commit the failing tests only**

```powershell
git add tests/release_stabilization_spec.lua
git commit -m "test: cover loot source resolver matching"
```

---

### Task 2: Implement LootSources Modules

**Files:**
- Create: `!KRT/Modules/LootSourcesData.lua`
- Create: `!KRT/Modules/LootSources.lua`

- [ ] **Step 1: Add empty production data module**

Create `!KRT/Modules/LootSourcesData.lua`:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: static raid item source data for Vanilla through WotLK
-- exports: addon.LootSourcesData

local addon = select(2, ...)

-- ----- Internal state ----- --
addon.LootSourcesData = addon.LootSourcesData or {}
addon.LootSourcesData.ByItemId = addon.LootSourcesData.ByItemId or {}
```

- [ ] **Step 2: Add resolver facade implementation**

Create `!KRT/Modules/LootSources.lua` with this implementation:

```lua
-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.LootSources

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Strings = feature.Strings

-- ----- Internal state ----- --
addon.LootSources = addon.LootSources or {}
local LootSources = addon.LootSources

local Data = addon.LootSourcesData or { ByItemId = {} }

local tonumber, tostring = tonumber, tostring
local type = type

-- ----- Private helpers ----- --
local function normalizeText(value)
    if Strings and Strings.NormalizeLower then
        return Strings.NormalizeLower(value, true)
    end
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return string.lower(value)
end

local function normalizeKind(kind)
    if kind == "boss" or kind == "trash" then
        return kind
    end
    return nil
end

local function normalizeModeKey(context)
    local raidSize = tonumber(context and context.raidSize) or 0
    local difficulty = tonumber(context and context.difficulty) or 0
    if raidSize == 10 then
        if difficulty == 5 then
            return "heroic10"
        end
        return "normal10"
    end
    if raidSize == 25 then
        if difficulty == 6 then
            return "heroic25"
        end
        return "normal25"
    end
    if difficulty == 3 then
        return "normal10"
    end
    if difficulty == 4 then
        return "normal25"
    end
    if difficulty == 5 then
        return "heroic10"
    end
    if difficulty == 6 then
        return "heroic25"
    end
    return nil
end

local function copyCandidate(candidate)
    if type(candidate) ~= "table" then
        return nil
    end
    local npcId = tonumber(candidate.npcId) or 0
    local npcName = candidate.npcName
    local raid = candidate.raid
    local kind = normalizeKind(candidate.kind)
    if npcId <= 0 or not npcName or not raid or not kind then
        return nil
    end
    return {
        npcId = npcId,
        npcName = npcName,
        raid = raid,
        kind = kind,
        modes = candidate.modes,
    }
end

local function appendCandidate(out, candidate)
    local copy = copyCandidate(candidate)
    if copy then
        out[#out + 1] = copy
    end
end

local function candidateMatchesRaid(candidate, context)
    local queryRaid = normalizeText((context and (context.raid or context.zoneName or context.instanceName)) or nil)
    if not queryRaid then
        return true
    end
    local candidateRaid = normalizeText(candidate and candidate.raid)
    return candidateRaid == queryRaid
end

local function candidateMatchesMode(candidate, context)
    local modeKey = normalizeModeKey(context)
    local modes = candidate and candidate.modes
    if not modeKey or type(modes) ~= "table" then
        return true
    end
    return modes[modeKey] == true
end

local function filterCandidates(candidates, context)
    local out = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidateMatchesRaid(candidate, context) and candidateMatchesMode(candidate, context) then
            out[#out + 1] = candidate
        end
    end
    return out
end

local function resolveRecentCandidate(candidates, context)
    local recentNpcId = tonumber(context and context.recentSourceNpcId) or 0
    local recentName = normalizeText(context and context.recentSourceName)
    if recentNpcId <= 0 and not recentName then
        return nil
    end
    local matched = nil
    for i = 1, #candidates do
        local candidate = candidates[i]
        local npcMatches = recentNpcId > 0 and (tonumber(candidate.npcId) or 0) == recentNpcId
        local nameMatches = recentName and normalizeText(candidate.npcName) == recentName
        if npcMatches or nameMatches then
            if matched then
                return nil
            end
            matched = candidate
        end
    end
    return matched
end

local function resolveSingleTrashCandidate(candidates)
    local matched = nil
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.kind ~= "trash" then
            return nil
        end
        if matched and (matched.npcId ~= candidate.npcId) then
            return nil
        end
        matched = matched or candidate
    end
    return matched
end

local function resolved(candidate, confidence)
    return {
        npcId = candidate.npcId,
        npcName = candidate.npcName,
        raid = candidate.raid,
        kind = candidate.kind,
        confidence = confidence or "exact",
    }
end

-- ----- Public methods ----- --
function LootSources.GetCandidates(itemId)
    local resolvedItemId = tonumber(itemId) or 0
    local candidates = {}
    local source = Data.ByItemId and Data.ByItemId[resolvedItemId] or nil
    if type(source) ~= "table" then
        return candidates
    end
    for i = 1, #source do
        appendCandidate(candidates, source[i])
    end
    return candidates
end

function LootSources.Resolve(itemId, context)
    local candidates = filterCandidates(LootSources.GetCandidates(itemId), context or {})
    if #candidates == 0 then
        return { reason = "missing", candidates = candidates }
    end
    if #candidates == 1 then
        return resolved(candidates[1], "exact")
    end

    local recent = resolveRecentCandidate(candidates, context or {})
    if recent then
        return resolved(recent, "context")
    end

    local trash = resolveSingleTrashCandidate(candidates)
    if trash then
        return resolved(trash, "shared-trash")
    end

    return { reason = "ambiguous", candidates = candidates }
end

function LootSources._SetDataForTests(byItemId)
    Data = { ByItemId = byItemId or {} }
end
```

- [ ] **Step 3: Run resolver tests and verify they pass**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: the resolver tests pass. Other tests may still fail if the harness does not load new modules
for service paths; fix that in Task 3.

- [ ] **Step 4: Commit resolver modules**

```powershell
git add !KRT/Modules/LootSourcesData.lua !KRT/Modules/LootSources.lua
git commit -m "feat: add raid loot source resolver"
```

---

### Task 3: Wire Load Order And Harness

**Files:**
- Modify: `!KRT/!KRT.toc`
- Modify: `tests/release_stabilization_spec.lua`
- Modify: `AGENTS.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/OVERVIEW.md`

- [ ] **Step 1: Add TOC entries**

In `!KRT/!KRT.toc`, insert these lines immediately after `Modules\Item.lua`:

```text
Modules\LootSourcesData.lua
Modules\LootSources.lua
```

- [ ] **Step 2: Add harness loading support**

In `tests/release_stabilization_spec.lua`, inside `harness.load`, define module files before service files:

```lua
local lootSourceFiles = {
    "!KRT/Modules/LootSourcesData.lua",
    "!KRT/Modules/LootSources.lua",
}
```

Then load them before `lootServiceFiles` and `raidServiceFiles` when service aliases are requested:

```lua
if path == "!KRT/Modules/LootSources.lua" then
    loadFiles(lootSourceFiles)
    feature.LootSources = addon.LootSources
    return addon.LootSources
end

if path == "!KRT/Services/Loot.lua" then
    loadFiles(lootSourceFiles)
    feature.LootSources = addon.LootSources
    loadFiles(lootServiceFiles)
    return addon.Services.Loot
end

if path == "!KRT/Services/Raid.lua" then
    loadFiles(lootSourceFiles)
    feature.LootSources = addon.LootSources
    loadFiles(lootServiceFiles)
    loadFiles(raidServiceFiles)
    local raid = addon.Services.Raid
    local loot = addon.Services.Loot
    if raid and loot then
        raid.AddLoot = raid.AddLoot or function(_, ...)
            return loot:AddLoot(...)
        end
        raid.AddPassiveLootRoll = raid.AddPassiveLootRoll or function(_, ...)
            return loot:AddPassiveLootRoll(...)
        end
        raid.AddGroupLootMessage = raid.AddGroupLootMessage or function(_, ...)
            return loot:AddGroupLootMessage(...)
        end
        raid.LogTradeOnlyLoot = raid.LogTradeOnlyLoot or function(_, ...)
            return loot:LogTradeOnlyLoot(...)
        end
    end
    return addon.Services.Raid
end
```

- [ ] **Step 3: Update docs load-order references**

Update `AGENTS.md` section 4 so `Modules/LootSourcesData.lua` and `Modules/LootSources.lua` appear
after `Modules/Item.lua`. Renumber following entries.

Update `docs/ARCHITECTURE.md` and `docs/OVERVIEW.md` module maps with:

```text
Modules/LootSourcesData.lua - static raid item-source data
Modules/LootSources.lua - itemId -> raid source resolver
```

- [ ] **Step 4: Run TOC and resolver tests**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check toc
lua tests/release_stabilization_spec.lua
```

Expected: TOC passes. Resolver tests pass.

- [ ] **Step 5: Commit load-order wiring**

```powershell
git add !KRT/!KRT.toc tests/release_stabilization_spec.lua AGENTS.md docs/ARCHITECTURE.md docs/OVERVIEW.md
git commit -m "chore: wire loot source modules"
```

---

### Task 4: Add Passive Loot Integration Tests

**Files:**
- Modify: `tests/release_stabilization_spec.lua`

- [ ] **Step 1: Add boss resolution integration test**

Add this test near existing Group Loot tests:

```lua
test("group loot source resolver assigns boss item without timing context", function()
    local h = newHarness()
    local link = h.registerItem(91730, "Resolver Boss Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            zone = "Naxxramas",
            size = 10,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil

    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetLootRollItemLink = function(rollId)
        return (rollId == 301) and link or nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "resolver-boss-win" then
            return 301, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.addon.LootSources._SetDataForTests({
        [91730] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
        },
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(301, 45000)
    assertEqual(Raid:AddGroupLootMessage("resolver-boss-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-boss-win")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected source resolver to create one boss record")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected resolved boss name")
    assertEqual(raid.bossKills[1].sourceNpcId, 15953, "expected resolved boss npc id")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected loot to bind to resolved boss")
end)
```

- [ ] **Step 2: Add named trash resolution integration test**

Add this test immediately after the boss test:

```lua
test("group loot source resolver assigns named trash without timing context", function()
    local h = newHarness()
    local link = h.registerItem(91731, "Resolver Trash Cloak")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            zone = "Naxxramas",
            size = 10,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil

    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetLootRollItemLink = function(rollId)
        return (rollId == 302) and link or nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "resolver-trash-win" then
            return 302, 77, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.addon.LootSources._SetDataForTests({
        [91731] = {
            { npcId = 15989, npcName = "Naxxramas Cultist", raid = "Naxxramas", kind = "trash" },
        },
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(302, 45000)
    assertEqual(Raid:AddGroupLootMessage("resolver-trash-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-trash-win")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected source resolver to create one trash record")
    assertEqual(raid.bossKills[1].name, "Naxxramas Cultist", "expected named trash source")
    assertEqual(raid.bossKills[1].sourceNpcId, 15989, "expected trash npc id")
    assertEqual(raid.bossKills[1].sourceKind, "trash", "expected trash source kind")
    assertEqual(h.Core.GetLastBoss(), nil, "expected named trash to avoid becoming lastBoss")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected loot to bind to trash source")
end)
```

- [ ] **Step 3: Add ambiguous fallback integration test**

Add this test after the named trash test:

```lua
test("group loot source resolver falls back when item source is ambiguous", function()
    local h = newHarness()
    local link = h.registerItem(91732, "Ambiguous Resolver Token")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            zone = "Naxxramas",
            size = 10,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil

    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetLootRollItemLink = function(rollId)
        return (rollId == 303) and link or nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "resolver-ambiguous-win" then
            return 303, 99, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.addon.LootSources._SetDataForTests({
        [91732] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15954, npcName = "Noth the Plaguebringer", raid = "Naxxramas", kind = "boss" },
        },
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(303, 45000)
    assertEqual(Raid:AddGroupLootMessage("resolver-ambiguous-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-ambiguous-win")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected ambiguous item to use current trash fallback")
    assertEqual(raid.bossKills[1].name, "_TrashMob_", "expected ambiguous item to avoid random boss choice")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected fallback loot binding")
end)
```

- [ ] **Step 4: Run tests and verify they fail**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: new integration tests fail because Raid service does not consume `LootSources` yet.

- [ ] **Step 5: Commit failing integration tests**

```powershell
git add tests/release_stabilization_spec.lua
git commit -m "test: cover item source loot attribution"
```

---

### Task 5: Implement Raid Source Resolution

**Files:**
- Modify: `!KRT/Services/Raid/State.lua`
- Modify: `!KRT/Localization/DiagnoseLog.en.lua`

- [ ] **Step 1: Add diagnostics**

Add these templates in `!KRT/Localization/DiagnoseLog.en.lua` near the boss/loot diagnostics:

```lua
Diag.D.LogLootSourceResolved = "[LootSource] Resolved itemId=%s raid=%s source=%s npcId=%d kind=%s confidence=%s"
Diag.D.LogLootSourceMissing = "[LootSource] Missing itemId=%s raid=%s"
Diag.D.LogLootSourceAmbiguous = "[LootSource] Ambiguous itemId=%s raid=%s candidates=%d"
```

- [ ] **Step 2: Add LootSources local and context helper**

In `!KRT/Services/Raid/State.lua`, near existing module locals, add:

```lua
local LootSources = addon.LootSources or feature.LootSources
```

Inside the `do` block private helpers, add:

```lua
local function getRaidSourceContext(raid, raidNum, now)
    local instanceName, _, difficultyIndex, _, maxPlayers = nil, nil, nil, nil, nil
    if type(GetInstanceInfo) == "function" then
        instanceName, _, difficultyIndex, _, maxPlayers = GetInstanceInfo()
    end

    local recent = getRecentLootDeathContextState()
    return {
        raid = instanceName or (raid and raid.zone),
        zoneName = instanceName or (raid and raid.zone),
        difficulty = tonumber(difficultyIndex) or tonumber(raid and raid.difficulty) or 0,
        raidSize = tonumber(maxPlayers) or tonumber(raid and raid.size) or 0,
        recentSourceNpcId = tonumber(recent and recent.sourceNpcId) or 0,
        recentSourceName = recent and recent.sourceName or nil,
        now = tonumber(now) or Time.GetCurrentTime(),
        raidNum = tonumber(raidNum) or 0,
    }
end
```

- [ ] **Step 3: Add source record creator that does not promote trash to lastBoss**

Add this helper near `findOrCreateTrashBossNid`:

```lua
local function findOrCreateLootSourceBossNid(raid, raidNum, source, now)
    if type(raid) ~= "table" or type(source) ~= "table" then
        return 0
    end

    local sourceNpcId = tonumber(source.npcId) or 0
    local sourceName = source.npcName
    if sourceNpcId <= 0 or not sourceName or sourceName == "" then
        return 0
    end

    local existing = findBossBySourceNpcId(raid, sourceNpcId) or findBossByName(raid, sourceName)
    if existing and (tonumber(existing.bossNid) or 0) > 0 then
        return tonumber(existing.bossNid) or 0
    end

    Core.EnsureRaidSchema(raid)
    local bossNid = tonumber(raid.nextBossNid) or 1
    raid.nextBossNid = bossNid + 1

    local instanceDiff = resolveRaidDifficulty()
    local players = {}
    local seenPlayers = {}
    for unit in addon.UnitIterator(true) do
        if UnitIsConnected(unit) then
            local name = UnitName(unit)
            if name then
                local resolvedName = Strings.NormalizeName(name, true) or name
                local playerNid = ensureRaidPlayerNid(resolvedName, raidNum)
                if playerNid > 0 and not seenPlayers[playerNid] then
                    seenPlayers[playerNid] = true
                    tinsert(players, playerNid)
                end
            end
        end
    end

    local killInfo = {
        bossNid = bossNid,
        name = sourceName,
        sourceNpcId = sourceNpcId,
        sourceKind = source.kind,
        source = "LootSources",
        difficulty = instanceDiff,
        mode = (instanceDiff == 3 or instanceDiff == 4) and "h" or "n",
        players = players,
        time = tonumber(now) or Time.GetCurrentTime(),
        hash = Base64.Encode(raidNum .. "|" .. sourceName .. "|" .. bossNid),
    }

    tinsert(raid.bossKills, killInfo)
    invalidateRaidRuntime(raid)
    if source.kind == "boss" then
        Core.SetLastBoss(bossNid)
        setBossEventContext(raidNum, bossNid, sourceName, "LootSources", killInfo.time)
    end

    return bossNid
end
```

- [ ] **Step 4: Add resolver helper**

Add this helper near `findAndRememberBossContextForLoot`:

```lua
local function findOrCreateBossNidFromLootSource(raid, raidNum, itemId, rollSessionId, now, ttlSeconds)
    if not (LootSources and LootSources.Resolve) then
        return 0
    end

    local resolvedItemId = tonumber(itemId) or 0
    if resolvedItemId <= 0 then
        return 0
    end

    local context = getRaidSourceContext(raid, raidNum, now)
    local source = LootSources.Resolve(resolvedItemId, context)
    if type(source) ~= "table" then
        return 0
    end

    if source.reason == "missing" then
        if isDebugEnabled() then
            addon:debug(Diag.D.LogLootSourceMissing:format(tostring(resolvedItemId), tostring(context.raid)))
        end
        return 0
    end

    if source.reason == "ambiguous" then
        if isDebugEnabled() then
            addon:debug(
                Diag.D.LogLootSourceAmbiguous:format(
                    tostring(resolvedItemId),
                    tostring(context.raid),
                    #(source.candidates or {})
                )
            )
        end
        return 0
    end

    local bossNid = findOrCreateLootSourceBossNid(raid, raidNum, source, now)
    if bossNid > 0 and rollSessionId then
        rememberLootBossSession(raidNum, rollSessionId, bossNid, ttlSeconds)
    end
    if bossNid > 0 and isDebugEnabled() then
        addon:debug(
            Diag.D.LogLootSourceResolved:format(
                tostring(resolvedItemId),
                tostring(context.raid),
                tostring(source.npcName),
                tonumber(source.npcId) or 0,
                tostring(source.kind),
                tostring(source.confidence)
            )
        )
    end
    return bossNid
end
```

- [ ] **Step 5: Call item-source resolver before timing fallback**

In `module:FindOrCreateBossNidForLoot`, after the initial `findAndRememberBossContextForLoot` call and
before `allowTrashFallback`, insert:

```lua
if bossNid <= 0 then
    bossNid = findOrCreateBossNidFromLootSource(
        raid,
        raidNum,
        options.itemId,
        rollSessionId,
        currentTime,
        ttlSeconds
    )
end
```

- [ ] **Step 6: Run integration tests and verify they still fail until Loot passes itemId**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: pure resolver tests pass. Integration tests still fail because `options.itemId` is not passed
from Loot service yet.

- [ ] **Step 7: Commit Raid implementation**

```powershell
git add !KRT/Services/Raid/State.lua !KRT/Localization/DiagnoseLog.en.lua
git commit -m "feat: resolve loot sources in raid context"
```

---

### Task 6: Pass Item IDs From Loot Service

**Files:**
- Modify: `!KRT/Services/Loot/Service.lua`

- [ ] **Step 1: Pass itemId in normal loot resolution**

In `resolveBossNidForLoot`, add an `itemId` parameter:

```lua
local function resolveBossNidForLoot(raid, raidNum, rollSessionId, passiveGroupLoot, now, itemId)
```

Inside the `FindOrCreateBossNidForLoot` options table, add:

```lua
itemId = itemId,
```

Update the call in `module:AddLoot`:

```lua
local bossNid = resolveBossNidForLoot(raid, currentRaidId, rollSessionId, passiveGroupLoot, currentTime, itemId)
```

- [ ] **Step 2: Pass itemId in trade-only loot resolution**

In `module:LogTradeOnlyLoot`, add `itemId = itemId` to the `FindOrCreateBossNidForLoot` options table:

```lua
resolvedBossNid = raidService:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, {
    now = currentTime,
    allowContextRecovery = false,
    allowTrashFallback = true,
    ttlSeconds = GROUP_LOOT_PENDING_AWARD_TTL_SECONDS,
    itemId = itemId,
})
```

- [ ] **Step 3: Run integration tests**

Run:

```powershell
lua tests/release_stabilization_spec.lua
```

Expected: new resolver and integration tests pass, along with existing release stabilization tests.

- [ ] **Step 4: Commit Loot integration**

```powershell
git add !KRT/Services/Loot/Service.lua
git commit -m "feat: pass item ids to loot source resolution"
```

---

### Task 7: Add Production Data Skeleton And First Real Coverage

**Files:**
- Modify: `!KRT/Modules/LootSourcesData.lua`
- Create: `docs/LOOT_SOURCES.md`

- [ ] **Step 1: Add real seed rows for smoke coverage**

Add a small reviewed stock 3.3.5a data slice to `LootSourcesData.ByItemId`. Use real item IDs only.
Start with rows that cover one boss and one trash source from commonly tested raids:

```lua
addon.LootSourcesData.ByItemId = {
    -- Icecrown Citadel - Lord Marrowgar
    [50761] = {
        {
            npcId = 36612,
            npcName = "Lord Marrowgar",
            raid = "Icecrown Citadel",
            kind = "boss",
            modes = { normal10 = true },
        },
    },

    -- Icecrown Citadel - Deathbound Ward trash
    [50452] = {
        {
            npcId = 37007,
            npcName = "Deathbound Ward",
            raid = "Icecrown Citadel",
            kind = "trash",
            modes = { normal10 = true, normal25 = true, heroic10 = true, heroic25 = true },
        },
    },
}
```

If either item-source pairing is not verified against the selected data source during implementation,
replace it with a verified boss row and a verified trash row before committing.

- [ ] **Step 2: Document dataset policy**

Create `docs/LOOT_SOURCES.md`:

```markdown
# Loot Sources

KRT uses `!KRT/Modules/LootSourcesData.lua` as a static raid-only item source table.

The resolver targets stock WoW 3.3.5a raid data from Vanilla through WotLK. It is used as an evidence
source for passive Group Loot and Need Before Greed attribution before timing-based fallbacks.

Runtime rules:
- Exact item-source matches can create or reuse boss/trash records.
- Ambiguous items fall back to the existing context resolver.
- Missing items fall back to the existing context resolver.
- AtlasLoot or DataStore are not required at runtime.

Data rules:
- Prefer item IDs and NPC IDs over names.
- Mark trash sources as `kind = "trash"`.
- Mark boss sources as `kind = "boss"`.
- Add mode metadata when the source differs by 10/25 or normal/heroic.
- Do not include non-raid, vendor, crafted, PvP, reputation, or quest-only sources.
```

- [ ] **Step 3: Commit seed data and policy docs**

```powershell
git add !KRT/Modules/LootSourcesData.lua docs/LOOT_SOURCES.md
git commit -m "data: seed raid loot source table"
```

---

### Task 8: Expand Full Raid Dataset In Batches

**Files:**
- Modify: `!KRT/Modules/LootSourcesData.lua`
- Modify: `docs/LOOT_SOURCES.md`

- [ ] **Step 1: Add Vanilla raid data batch**

Add reviewed boss and relevant trash rows for:

```text
Molten Core
Onyxia's Lair
Blackwing Lair
Zul'Gurub
Ruins of Ahn'Qiraj
Temple of Ahn'Qiraj
Naxxramas 40
```

Each row must use this exact shape:

```lua
[itemId] = {
    {
        npcId = sourceNpcId,
        npcName = "Source Name",
        raid = "Raid Name",
        kind = "boss",
        modes = { normal40 = true },
    },
}
```

For shared trash drops, use `kind = "trash"` and include all plausible NPCs. The resolver will keep
ambiguous shared trash unresolved unless one NPC remains after context filtering.

- [ ] **Step 2: Run checks and commit Vanilla batch**

```powershell
lua tests/release_stabilization_spec.lua
git add !KRT/Modules/LootSourcesData.lua docs/LOOT_SOURCES.md
git commit -m "data: add vanilla raid loot sources"
```

- [ ] **Step 3: Add TBC raid data batch**

Add reviewed boss and relevant trash rows for:

```text
Karazhan
Gruul's Lair
Magtheridon's Lair
Serpentshrine Cavern
The Eye
Battle for Mount Hyjal
Black Temple
Sunwell Plateau
```

Use mode keys only when useful for disambiguation. For TBC raids, omit `modes` when the same source table
applies to the raid mode.

- [ ] **Step 4: Run checks and commit TBC batch**

```powershell
lua tests/release_stabilization_spec.lua
git add !KRT/Modules/LootSourcesData.lua docs/LOOT_SOURCES.md
git commit -m "data: add burning crusade raid loot sources"
```

- [ ] **Step 5: Add WotLK raid data batch**

Add reviewed boss and relevant trash rows for:

```text
Naxxramas 10/25
The Obsidian Sanctum
The Eye of Eternity
Vault of Archavon
Ulduar
Trial of the Crusader
Onyxia's Lair level 80
Icecrown Citadel
The Ruby Sanctum
```

Use mode keys for WotLK raid entries when source availability differs:

```lua
modes = {
    normal10 = true,
    normal25 = true,
    heroic10 = true,
    heroic25 = true,
}
```

- [ ] **Step 6: Run checks and commit WotLK batch**

```powershell
lua tests/release_stabilization_spec.lua
git add !KRT/Modules/LootSourcesData.lua docs/LOOT_SOURCES.md
git commit -m "data: add wrath raid loot sources"
```

---

### Task 9: Add Changelog And Final Gates

**Files:**
- Modify: `!KRT/CHANGELOG.md`
- Regenerate: `docs/TREE.md`

- [ ] **Step 1: Add changelog entry**

Under `## Unreleased` in `!KRT/CHANGELOG.md`, add:

```markdown
- Added raid loot source resolution for passive Group Loot and Need Before Greed logging. KRT can now
  match known Vanilla through WotLK raid item drops to boss or named trash sources before falling back to
  timing-based loot context.
```

- [ ] **Step 2: Run full gates**

Run:

```powershell
py -3 tools/krt.py repo-quality-check --check all
powershell -NoProfile -File tools/run-release-targeted-tests.ps1
```

Expected:
- TOC checks pass.
- Layering checks pass.
- UI binding checks pass.
- Lua syntax/uniformity checks pass.
- API catalog check passes or updates only generated docs that must be staged.
- Release targeted tests pass.

- [ ] **Step 3: Stage generated docs if required**

If the quality gate updates `docs/TREE.md`, stage it:

```powershell
git add docs/TREE.md
```

Do not stage API registry files unless `git diff --quiet` shows real content changes beyond timestamp or
line-ending metadata.

- [ ] **Step 4: Commit final docs**

```powershell
git add !KRT/CHANGELOG.md docs/TREE.md
git commit -m "docs: record raid loot source resolver"
```

- [ ] **Step 5: Final status check**

Run:

```powershell
git status --short
```

Expected: no unstaged or uncommitted changes.

---

## Self-Review Checklist

- Spec coverage:
  - Static resolver module: Tasks 1-3.
  - Runtime independence from DataStore/AtlasLoot: Tasks 2 and 7.
  - Boss and named trash attribution: Tasks 4-6.
  - Ambiguous and missing fallback: Tasks 1, 4, and 5.
  - Vanilla through WotLK data expansion: Task 8.
  - Diagnostics, changelog, docs, and gates: Tasks 5 and 9.

- Type consistency:
  - Candidate fields are `npcId`, `npcName`, `raid`, `kind`, `modes`.
  - Resolver return uses either source fields or `reason = "missing"|"ambiguous"`.
  - Raid integration passes `options.itemId`.
  - Persisted source records use `sourceKind` and `source = "LootSources"`.

- Test sequence:
  - Pure resolver tests fail before module implementation.
  - Integration tests fail before Raid/Loot wiring.
  - Full release stabilization passes after Task 6.
  - Repo quality and targeted release tests pass after Task 9.
