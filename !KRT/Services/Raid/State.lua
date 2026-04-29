-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Events = feature.Events or addon.Events
local C = feature.C
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Time = feature.Time or addon.Time
local Base64 = feature.Base64 or addon.Base64
local IgnoredMobs = feature.IgnoredMobs or addon.IgnoredMobs or {}

local InternalEvents = Events.Internal

local raidState = feature.raidState

local tinsert, twipe = table.insert, table.wipe
local ipairs, type, select = ipairs, type, select

local tostring, tonumber = tostring, tonumber
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitIsDead = UnitIsDead
local UnitName = UnitName
local UnitRace = UnitRace

local LEGACY_TRASH_MOB_NAME = "_TrashMob_"
local function resolveTrashMobName()
    local localizedName = L and L.StrTrashMobName
    if type(localizedName) ~= "string" or localizedName == "" then
        return LEGACY_TRASH_MOB_NAME
    end
    if localizedName == "StrTrashMobName" or localizedName == "L.StrTrashMobName" then
        return LEGACY_TRASH_MOB_NAME
    end
    return localizedName
end

local TRASH_MOB_NAME = resolveTrashMobName()

-- Raid helper module.
-- Manages raid state, roster, boss kills, and loot logging.
do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid
    -- ----- Internal state ----- --
    local getRaidRosterInfo = GetRaidRosterInfo
    local masterLootCandidateCache = {
        itemLink = nil,
        rosterVersion = nil,
        indexByName = {},
    }

    local function isTrashMobName(name)
        return name == TRASH_MOB_NAME or name == LEGACY_TRASH_MOB_NAME
    end

    local BOSS_KILL_DEDUPE_WINDOW_SECONDS = tonumber(C.BOSS_KILL_DEDUPE_WINDOW_SECONDS) or 30
    local BOSS_EVENT_CONTEXT_TTL_SECONDS = tonumber(C.BOSS_EVENT_CONTEXT_TTL_SECONDS) or BOSS_KILL_DEDUPE_WINDOW_SECONDS
    local GROUP_LOOT_PENDING_AWARD_TTL_SECONDS = tonumber(C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS) or 60
    local RECENT_TRASH_DEATH_CONTEXT_THROTTLE_SECONDS = tonumber(C.RECENT_TRASH_DEATH_CONTEXT_THROTTLE_SECONDS) or 1
    local LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS = math.max(BOSS_EVENT_CONTEXT_TTL_SECONDS, GROUP_LOOT_PENDING_AWARD_TTL_SECONDS)
    local LootService = addon.Services and addon.Services.Loot or {}
    local LootContextHelpers = assert(LootService._Context or Core._LootContext, "Loot context helpers are not initialized")
    local LootContextState = assert(LootService._State, "Loot state helpers are not initialized")
    local LootContextSessions = assert(LootService._Sessions, "Loot session helpers are not initialized")
    local LootContextSnapshots = assert(LootService._Snapshots, "Loot snapshot helpers are not initialized")
    local copyActiveLootSource = assert(LootContextHelpers.CopyLootSource, "Missing LootContext.CopyLootSource")
    local recentTrashDeathContextRaidNum = 0
    local recentTrashDeathContextSeenAt = 0

    -- ----- Private helpers ----- --
    local function isDebugEnabled()
        return addon.hasDebug ~= nil
    end

    local function isTraceEnabled()
        return addon.hasTrace ~= nil
    end

    local function invalidateMasterLootCandidateCache()
        masterLootCandidateCache.itemLink = nil
        masterLootCandidateCache.rosterVersion = nil
        twipe(masterLootCandidateCache.indexByName)
    end

    local function getRosterVersion()
        if type(module.GetRosterVersion) == "function" then
            return module:GetRosterVersion()
        end
        return 0
    end

    local function buildMasterLootCandidateCache(itemLink)
        local currentRosterVersion = getRosterVersion()
        masterLootCandidateCache.itemLink = itemLink
        masterLootCandidateCache.rosterVersion = currentRosterVersion
        twipe(masterLootCandidateCache.indexByName)

        for p = 1, addon.GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                masterLootCandidateCache.indexByName[candidate] = p
            end
        end

        if isDebugEnabled() then
            addon:debug(Diag.D.LogMLCandidateCacheBuilt:format(tostring(itemLink), addon.tLength(masterLootCandidateCache.indexByName)))
        end
        return masterLootCandidateCache
    end

    local function ensureMasterLootCandidateCache(itemLink)
        local currentRosterVersion = getRosterVersion()
        if masterLootCandidateCache.itemLink ~= itemLink or masterLootCandidateCache.rosterVersion ~= currentRosterVersion then
            return buildMasterLootCandidateCache(itemLink)
        end
        return masterLootCandidateCache
    end

    local function setLootContextField(slotKey, legacyKey, value)
        return LootContextState.SetField(raidState, slotKey, legacyKey, value)
    end

    local function setActiveLootContextState(activeLoot)
        return LootContextState.SetActive(raidState, activeLoot)
    end

    local function syncActiveLootContextState()
        return LootContextState.SyncActive(raidState)
    end

    local function findBossByNid(raid, bossNid)
        local resolvedBossNid = tonumber(bossNid) or 0
        if resolvedBossNid <= 0 then
            return nil
        end

        local bosses = raid and raid.bossKills or {}
        for i = 1, #bosses do
            local boss = bosses[i]
            if boss and tonumber(boss.bossNid) == resolvedBossNid then
                return boss
            end
        end

        return nil
    end

    local function findBossByName(raid, bossName)
        local resolvedBossName = Strings.NormalizeLower(bossName, true)
        if not resolvedBossName or resolvedBossName == "" then
            return nil
        end

        local bosses = raid and raid.bossKills or {}
        for i = #bosses, 1, -1 do
            local boss = bosses[i]
            if boss then
                local candidateName = Strings.NormalizeLower(boss.name, true)
                if candidateName == resolvedBossName then
                    return boss
                end
            end
        end

        return nil
    end

    local function findBossBySourceNpcId(raid, sourceNpcId)
        local resolvedNpcId = tonumber(sourceNpcId) or 0
        if resolvedNpcId <= 0 then
            return nil
        end

        local bosses = raid and raid.bossKills or {}
        for i = #bosses, 1, -1 do
            local boss = bosses[i]
            if boss and (tonumber(boss.sourceNpcId) or 0) == resolvedNpcId then
                return boss
            end
        end

        return nil
    end

    local function classifyNpcLootSource(npcId)
        local resolvedNpcId = tonumber(npcId) or 0
        if resolvedNpcId <= 0 then
            return "unknown", 0
        end

        if type(IgnoredMobs.Contains) == "function" and IgnoredMobs.Contains(resolvedNpcId) then
            return "ignored", resolvedNpcId
        end

        local bossLib = addon.BossIDs
        local bossIds = bossLib and bossLib.BossIDs
        if not bossIds then
            return "unknown", resolvedNpcId
        end
        if bossIds[resolvedNpcId] == true then
            local bossName = type(bossLib.GetBossName) == "function" and bossLib:GetBossName(resolvedNpcId) or nil
            return "boss", resolvedNpcId, bossName
        end

        return "trash", resolvedNpcId
    end

    local function getLootWindowBossContextState()
        return LootContextState.GetWindow(raidState)
    end

    local function clearLootWindowBossContext()
        LootContextState.ClearWindow(raidState)
    end

    local setActiveLootSource
    local setLootWindowBossContext

    local function resolveContextExpiry(now, ttlSeconds, defaultTtl, minTtl)
        return LootContextState.ResolveExpiry(now, ttlSeconds, defaultTtl, minTtl)
    end

    local function setBlockedLootWindowBossContext(raidNum, source, now, ttlSeconds, sourceMeta)
        local resolvedRaidNum = tonumber(raidNum) or 0
        if resolvedRaidNum <= 0 then
            clearLootWindowBossContext()
            return 0
        end

        local resolvedNow, _, expiresAt = resolveContextExpiry(now, ttlSeconds, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS)
        local activeLoot = syncActiveLootContextState() or {}
        activeLoot.raidNum = resolvedRaidNum
        activeLoot.kind = "trash"
        activeLoot.bossNid = 0
        activeLoot.blocked = true
        activeLoot.source = source or "lootWindowBlocked"
        activeLoot.sourceUnit = sourceMeta and sourceMeta.unit or nil
        activeLoot.sourceNpcId = tonumber(sourceMeta and sourceMeta.npcId) or 0
        activeLoot.sourceName = sourceMeta and sourceMeta.name or nil
        activeLoot.snapshotId = nil
        activeLoot.openedAt = resolvedNow
        activeLoot.expiresAt = expiresAt
        activeLoot.windowExpiresAt = expiresAt
        setActiveLootContextState(activeLoot)

        if isDebugEnabled() then
            addon:debug(
                Diag.D.LogBossLootWindowContextBlocked:format(
                    resolvedRaidNum,
                    tostring(sourceMeta and sourceMeta.unit or "?"),
                    tostring(sourceMeta and sourceMeta.name or "?"),
                    tonumber(sourceMeta and sourceMeta.npcId) or 0,
                    tostring(source or "lootWindowBlocked")
                )
            )
        end

        return 0
    end

    local function getLootSourceState()
        return LootContextState.GetSource(raidState)
    end

    local function clearLootSourceState()
        LootContextState.ClearSource(raidState)
    end

    local function getBossEventContextState()
        return LootContextState.GetBossEvent(raidState)
    end

    local function normalizeRecentLootDeathContext(context)
        if type(context) ~= "table" then
            return nil
        end

        context.raidNum = tonumber(context.raidNum) or 0
        context.kind = (context.kind == "boss" or context.kind == "trash") and context.kind or nil
        context.bossNid = tonumber(context.bossNid) or 0
        context.sourceNpcId = tonumber(context.sourceNpcId) or 0
        context.sourceName = context.sourceName or nil
        context.source = context.source or nil
        context.seenAt = tonumber(context.seenAt) or 0

        if context.raidNum <= 0 or not context.kind then
            return nil
        end
        if context.kind == "boss" and context.bossNid <= 0 and not context.sourceName then
            return nil
        end

        return context
    end

    local function getRecentLootDeathContextState()
        return LootContextState.SyncField(raidState, "recentDeath", "recentLootDeathContext", normalizeRecentLootDeathContext)
    end

    local function setRecentLootDeathContext(raidNum, kind, sourceName, sourceNpcId, bossNid, source, seenAt)
        local resolvedRaidNum = tonumber(raidNum) or 0
        if resolvedRaidNum <= 0 or (kind ~= "boss" and kind ~= "trash") then
            setLootContextField("recentDeath", "recentLootDeathContext", nil)
            recentTrashDeathContextRaidNum = 0
            recentTrashDeathContextSeenAt = 0
            return nil
        end

        if kind ~= "trash" then
            recentTrashDeathContextRaidNum = 0
            recentTrashDeathContextSeenAt = 0
        end

        return setLootContextField("recentDeath", "recentLootDeathContext", {
            raidNum = resolvedRaidNum,
            kind = kind,
            bossNid = tonumber(bossNid) or 0,
            sourceNpcId = tonumber(sourceNpcId) or 0,
            sourceName = sourceName,
            source = source or "UNIT_DIED",
            seenAt = tonumber(seenAt) or Time.GetCurrentTime(),
        })
    end

    local function rememberRecentTrashDeathContext(raidNum, sourceName, sourceNpcId, now)
        local resolvedRaidNum = tonumber(raidNum) or 0
        local currentTime = tonumber(now) or Time.GetCurrentTime()
        local elapsed = currentTime - (tonumber(recentTrashDeathContextSeenAt) or 0)
        if resolvedRaidNum == recentTrashDeathContextRaidNum and elapsed >= 0 and elapsed < RECENT_TRASH_DEATH_CONTEXT_THROTTLE_SECONDS then
            return nil
        end

        recentTrashDeathContextRaidNum = resolvedRaidNum
        recentTrashDeathContextSeenAt = currentTime
        return setRecentLootDeathContext(resolvedRaidNum, "trash", sourceName, sourceNpcId, 0, "UNIT_DIED", currentTime)
    end

    local function resetLootContextState()
        LootContextState.Reset(raidState)
        recentTrashDeathContextRaidNum = 0
        recentTrashDeathContextSeenAt = 0
    end

    local function clearActiveLootWindowItemSnapshot()
        LootContextSnapshots.ClearActive(raidState)
    end

    local function createLootWindowItemSnapshot(raidNum, bossNid, items, source, now, ttlSeconds)
        return LootContextSnapshots.Create(raidState, raidNum, bossNid, items, source, now, ttlSeconds, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS)
    end

    local function setActiveLootWindowItemSnapshot(raid, raidNum, snapshot, now, ttlSeconds)
        local bossNid = LootContextSnapshots.MarkActive(raidState, snapshot, now, ttlSeconds, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS)
        if bossNid <= 0 then
            return 0
        end
        setLootWindowBossContext(raid, raidNum, bossNid, snapshot.source or "lootWindow", now, ttlSeconds, nil, snapshot.id)
        return bossNid
    end

    local function findMatchingLootWindowItemSnapshot(raidNum, items)
        return LootContextSnapshots.FindMatching(raidState, raidNum, items)
    end

    local function consumeActiveLootWindowItemSnapshot(itemLink)
        return LootContextSnapshots.ConsumeActive(raidState, itemLink)
    end

    local function resolveLootWindowSourceUnitContext(raid)
        if type(UnitExists) ~= "function" or type(UnitGUID) ~= "function" then
            return nil
        end

        local function buildUnitContext(unit, options)
            if not UnitExists(unit) then
                return nil
            end
            options = options or {}

            local guid = UnitGUID(unit)
            local npcId = guid and addon.GetCreatureId and addon.GetCreatureId(guid) or 0
            if npcId <= 0 then
                return nil
            end

            local sourceKind, _, sourceBossName = classifyNpcLootSource(npcId)
            local name = type(UnitName) == "function" and UnitName(unit) or nil
            if sourceKind == "boss" then
                if not options.allowBossMatch then
                    return nil
                end

                local boss = findBossBySourceNpcId(raid, npcId)
                if not boss and name then
                    boss = findBossByName(raid, name)
                end
                if not boss and sourceBossName then
                    boss = findBossByName(raid, sourceBossName)
                end
                if not boss then
                    local canCreateFromDeadBoss = (not options.requireDeadBossForCreate) or (type(UnitIsDead) == "function" and UnitIsDead(unit))
                    if options.allowBossCreate and canCreateFromDeadBoss and (name or sourceBossName) then
                        return {
                            kind = "boss",
                            unit = unit,
                            npcId = npcId,
                            name = name or sourceBossName,
                            bossNid = 0,
                        }
                    end
                    return nil
                end

                return {
                    kind = "boss",
                    unit = unit,
                    npcId = npcId,
                    name = boss.name or name or sourceBossName,
                    bossNid = tonumber(boss.bossNid) or 0,
                }
            end

            if options.allowNonBoss and sourceKind == "trash" then
                return {
                    kind = "nonBoss",
                    unit = unit,
                    npcId = npcId,
                    name = name,
                    bossNid = 0,
                }
            end

            return nil
        end

        local function buildCorpseUnitContext(unit, allowNonBoss)
            return buildUnitContext(unit, {
                allowBossMatch = true,
                allowBossCreate = true,
                allowNonBoss = allowNonBoss == true,
                requireDeadBossForCreate = true,
            })
        end

        local targetContext = buildCorpseUnitContext("target", true)
        if targetContext then
            return targetContext
        end

        local mouseoverContext = buildCorpseUnitContext("mouseover", true)
        if mouseoverContext then
            return mouseoverContext
        end

        return nil
    end

    setActiveLootSource = function(raid, raidNum, kind, bossNid, sourceMeta, now, ttlSeconds, snapshotId)
        local resolvedRaidNum = tonumber(raidNum) or 0
        local resolvedKind = (kind == "boss" or kind == "trash" or kind == "object") and kind or nil
        if resolvedRaidNum <= 0 or not resolvedKind then
            clearLootSourceState()
            return nil
        end

        local resolvedNow, _, expiresAt = resolveContextExpiry(now, ttlSeconds, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS, 1)
        local resolvedBossNid = tonumber(bossNid) or 0
        local boss = (resolvedBossNid > 0) and findBossByNid(raid, resolvedBossNid) or nil
        local sourceName = sourceMeta and sourceMeta.name or nil
        if not sourceName and boss then
            sourceName = boss.name or boss.boss
        end

        local activeLoot = syncActiveLootContextState() or {}
        activeLoot.raidNum = resolvedRaidNum
        activeLoot.kind = resolvedKind
        activeLoot.bossNid = resolvedBossNid
        activeLoot.sourceNpcId = tonumber(sourceMeta and sourceMeta.npcId) or tonumber(sourceMeta and sourceMeta.sourceNpcId) or 0
        activeLoot.sourceName = sourceName
        activeLoot.snapshotId = tonumber(snapshotId) or nil
        activeLoot.openedAt = resolvedNow
        activeLoot.expiresAt = expiresAt
        return setActiveLootContextState(activeLoot)
    end

    setLootWindowBossContext = function(raid, raidNum, bossNid, source, now, ttlSeconds, sourceMeta, snapshotId, updateLootSource)
        local resolvedRaidNum = tonumber(raidNum) or 0
        local resolvedBossNid = tonumber(bossNid) or 0
        local boss = findBossByNid(raid, resolvedBossNid)
        if resolvedRaidNum <= 0 or resolvedBossNid <= 0 or not boss then
            clearLootWindowBossContext()
            return 0
        end

        local _, _, expiresAt = resolveContextExpiry(now, ttlSeconds, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS, LOOT_WINDOW_BOSS_CONTEXT_TTL_SECONDS)
        local activeLoot = syncActiveLootContextState() or {}
        activeLoot.raidNum = resolvedRaidNum
        activeLoot.bossNid = resolvedBossNid
        activeLoot.blocked = false
        activeLoot.source = source or "lootWindow"
        activeLoot.sourceUnit = sourceMeta and sourceMeta.unit or nil
        activeLoot.sourceNpcId = tonumber(sourceMeta and sourceMeta.npcId) or tonumber(activeLoot.sourceNpcId) or 0
        activeLoot.sourceName = sourceMeta and sourceMeta.name or tostring(boss.name)
        activeLoot.windowExpiresAt = expiresAt
        if updateLootSource ~= false then
            activeLoot.kind = isTrashMobName(boss.name) and "trash" or "boss"
            activeLoot.snapshotId = tonumber(snapshotId) or nil
            activeLoot.openedAt = tonumber(now) or Time.GetCurrentTime()
            activeLoot.expiresAt = expiresAt
        end
        setActiveLootContextState(activeLoot)

        if isDebugEnabled() then
            addon:debug(Diag.D.LogBossLootWindowContextSet:format(tostring(boss.name), resolvedBossNid, resolvedRaidNum, tostring(source or "lootWindow")))
        end

        return resolvedBossNid
    end

    local function resolveLootWindowContextState(raid, raidNum, now)
        local lootWindowBossContext = getLootWindowBossContextState()
        if type(lootWindowBossContext) ~= "table" then
            return nil
        end

        local currentTime = tonumber(now) or Time.GetCurrentTime()
        local contextRaidNum = tonumber(lootWindowBossContext.raidNum) or 0
        local contextBossNid = tonumber(lootWindowBossContext.bossNid) or 0
        local expiresAt = tonumber(lootWindowBossContext.expiresAt) or 0

        if contextRaidNum ~= (tonumber(raidNum) or 0) or contextBossNid <= 0 then
            if lootWindowBossContext.blocked ~= true then
                clearLootWindowBossContext()
                return nil
            end
            if contextRaidNum ~= (tonumber(raidNum) or 0) then
                clearLootWindowBossContext()
                return nil
            end
        end

        if expiresAt > 0 and currentTime > expiresAt then
            clearLootWindowBossContext()
            return nil
        end

        if lootWindowBossContext.blocked == true then
            return "blocked", lootWindowBossContext, nil
        end

        local boss = findBossByNid(raid, contextBossNid)
        if not boss then
            clearLootWindowBossContext()
            return nil
        end

        return "boss", lootWindowBossContext, boss
    end

    local function resolveLootWindowBossContext(raid, raidNum, now)
        local contextState, lootWindowBossContext, boss = resolveLootWindowContextState(raid, raidNum, now)
        if contextState ~= "boss" then
            return 0
        end

        if isDebugEnabled() then
            addon:debug(
                Diag.D.LogBossLootWindowContextRecovered:format(
                    tostring(boss.name),
                    tonumber(lootWindowBossContext.bossNid) or 0,
                    tonumber(lootWindowBossContext.raidNum) or 0,
                    tostring(lootWindowBossContext.source or "lootWindow")
                )
            )
        end

        return tonumber(lootWindowBossContext.bossNid) or 0
    end

    local function rememberLootBossSession(raidNum, rollSessionId, bossNid, ttlSeconds)
        LootContextSessions.Remember(raidState, raidNum, rollSessionId, bossNid, ttlSeconds, Time.GetCurrentTime())
    end

    local function resolveLootBossSession(raid, raidNum, rollSessionId, now)
        return LootContextSessions.Resolve(raidState, raid, raidNum, rollSessionId, now, findBossByNid)
    end

    local function isUnknownName(name)
        local resolver = module._IsUnknownNameInternal
        if type(resolver) == "function" then
            return resolver(name)
        end
        return (not name) or name == ""
    end

    local function invalidateRaidRuntime(raid)
        if Core and Core.StripRuntimeRaidCaches then
            Core.StripRuntimeRaidCaches(raid)
            return
        end
        if type(raid) == "table" then
            raid._runtime = nil
        end
    end
    module._InvalidateRaidRuntimeInternal = invalidateRaidRuntime

    local function buildDefaultRaidPlayer(name)
        return {
            name = name,
            rank = 0,
            subgroup = 1,
            class = "UNKNOWN",
            join = Time.GetCurrentTime(),
            leave = nil,
            count = 0,
        }
    end

    local function ensureRaidPlayerNid(name, raidNum)
        local resolvedName = Strings.NormalizeName(name, true) or name
        if not resolvedName or resolvedName == "" then
            return 0, resolvedName
        end

        local playerNid = module:GetPlayerID(resolvedName, raidNum)
        if playerNid > 0 then
            return playerNid, resolvedName
        end

        module:AddPlayer(buildDefaultRaidPlayer(resolvedName), raidNum)
        playerNid = module:GetPlayerID(resolvedName, raidNum)
        return playerNid, resolvedName
    end

    local function resolveRaidDifficulty(instanceDiff)
        local diff = tonumber(instanceDiff)
        if type(GetInstanceInfo) ~= "function" then
            return diff
        end
        local _, instanceType, liveDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if instanceType ~= "raid" then
            return diff
        end

        liveDiff = tonumber(liveDiff)
        if isDyn then
            local baseDiff = liveDiff or diff
            if baseDiff then
                return baseDiff + (2 * (tonumber(dynDiff) or 0))
            end
            return nil
        end

        -- Prefer live difficulty from GetInstanceInfo(): event payload can be stale during
        -- automatic fallback (for example 25H requested, 25N applied by the instance).
        return liveDiff or diff
    end

    local function getRaidSizeFromDifficulty(instanceDiff)
        local diff = tonumber(instanceDiff)
        if not diff then
            return nil
        end
        return (diff % 2 == 0) and 25 or 10
    end
    module._ResolveRaidDifficultyInternal = resolveRaidDifficulty
    module._GetRaidSizeFromDifficultyInternal = getRaidSizeFromDifficulty

    local function findRecentBossKillByName(raid, bossName, now)
        if not raid or not bossName then
            return nil, nil
        end

        local bossKills = raid.bossKills or {}
        for i = #bossKills, 1, -1 do
            local bossKill = bossKills[i]
            local killTime = tonumber(bossKill and bossKill.time) or 0
            local delta = now - killTime
            if delta > BOSS_KILL_DEDUPE_WINDOW_SECONDS then
                return nil, nil
            end
            if delta >= 0 and bossKill and bossKill.name == bossName then
                return bossKill, delta
            end
        end
        return nil, nil
    end

    local function clearBossEventContext()
        setLootContextField("eventBoss", "bossEventContext", nil)
    end

    local function setBossEventContext(raidNum, bossNid, bossName, source, seenAt)
        raidNum = tonumber(raidNum) or 0
        bossNid = tonumber(bossNid) or 0
        if raidNum <= 0 or bossNid <= 0 or not bossName then
            clearBossEventContext()
            return nil
        end

        local bossEventContext = setLootContextField("eventBoss", "bossEventContext", {
            raidNum = raidNum,
            bossNid = bossNid,
            name = bossName,
            source = source or "event",
            seenAt = tonumber(seenAt) or Time.GetCurrentTime(),
        })

        if isDebugEnabled() then
            addon:debug(Diag.D.LogBossEventContextSet:format(tostring(bossName), bossNid, raidNum, tostring(source or "event")))
        end

        return bossEventContext
    end

    local function resolveBossEventContext(raidNum, now, applyLastBoss)
        local bossEventContext = getBossEventContextState()
        if type(bossEventContext) ~= "table" then
            return 0
        end

        local contextRaidNum = tonumber(bossEventContext.raidNum) or 0
        local contextBossNid = tonumber(bossEventContext.bossNid) or 0
        local contextBossName = bossEventContext.name
        local delta = (tonumber(now) or 0) - (tonumber(bossEventContext.seenAt) or 0)

        if contextRaidNum ~= (tonumber(raidNum) or 0) or contextBossNid <= 0 or isTrashMobName(contextBossName) then
            clearBossEventContext()
            return 0
        end

        if delta < 0 or delta > BOSS_EVENT_CONTEXT_TTL_SECONDS then
            clearBossEventContext()
            return 0
        end

        if applyLastBoss then
            Core.SetLastBoss(contextBossNid)
            if isDebugEnabled() then
                addon:debug(
                    Diag.D.LogBossEventContextRecovered:format(tostring(contextBossName), contextBossNid, tonumber(delta) or -1, tostring(bossEventContext.source or "event"))
                )
            end
        end

        return contextBossNid
    end

    local function recoverBossEventContext(raidNum, now)
        return resolveBossEventContext(raidNum, now, true)
    end

    local function peekBossEventContext(raidNum, now)
        return resolveBossEventContext(raidNum, now, false)
    end

    local function resolveRecentLootDeathContext(raid, raidNum, now, ttlSeconds, source)
        local context = getRecentLootDeathContextState()
        if type(context) ~= "table" then
            return nil
        end

        local currentTime = tonumber(now) or Time.GetCurrentTime()
        local contextRaidNum = tonumber(context.raidNum) or 0
        local delta = currentTime - (tonumber(context.seenAt) or 0)
        if contextRaidNum ~= (tonumber(raidNum) or 0) or delta < 0 or delta > BOSS_EVENT_CONTEXT_TTL_SECONDS then
            setLootContextField("recentDeath", "recentLootDeathContext", nil)
            return nil
        end

        if context.kind == "trash" then
            setBlockedLootWindowBossContext(raidNum, source or "lootWindowRecentDeath", currentTime, ttlSeconds, {
                npcId = tonumber(context.sourceNpcId) or 0,
                name = context.sourceName,
            })
            return "blocked", 0
        end

        local bossNid = tonumber(context.bossNid) or 0
        local boss = findBossByNid(raid, bossNid)
        if not boss and context.sourceName then
            boss = findBossByName(raid, context.sourceName)
            bossNid = tonumber(boss and boss.bossNid) or bossNid
        end
        if not boss and context.sourceName then
            local sourceNpcId = tonumber(context.sourceNpcId) or 0
            local sourceNpcIdArg = sourceNpcId > 0 and sourceNpcId or nil
            bossNid = tonumber(module:AddBoss(context.sourceName, nil, raidNum, sourceNpcIdArg)) or 0
        end
        if bossNid <= 0 then
            return nil
        end

        local sourceMeta = {
            npcId = tonumber(context.sourceNpcId) or 0,
            name = context.sourceName,
        }
        return "boss", setLootWindowBossContext(raid, raidNum, bossNid, source or "lootWindowRecentDeath", currentTime, ttlSeconds, sourceMeta)
    end

    local function ensureLootWindowBossContext(raid, raidNum, now, ttlSeconds, source)
        local currentTime = tonumber(now) or Time.GetCurrentTime()
        local contextState = resolveLootWindowContextState(raid, raidNum, currentTime)
        if contextState == "blocked" then
            return 0
        end

        local bossNid = resolveLootWindowBossContext(raid, raidNum, currentTime)
        if bossNid > 0 then
            return bossNid
        end

        local sourceUnitContext = resolveLootWindowSourceUnitContext(raid)
        if type(sourceUnitContext) == "table" then
            if sourceUnitContext.kind == "boss" then
                local sourceBossNid = tonumber(sourceUnitContext.bossNid) or 0
                if sourceBossNid <= 0 and sourceUnitContext.name then
                    sourceBossNid = tonumber(module:AddBoss(sourceUnitContext.name, nil, raidNum, sourceUnitContext.npcId)) or 0
                    sourceUnitContext.bossNid = sourceBossNid
                end
                if sourceBossNid > 0 then
                    return setLootWindowBossContext(raid, raidNum, sourceBossNid, source or "lootWindowUnit", currentTime, ttlSeconds, sourceUnitContext)
                end
            elseif sourceUnitContext.kind == "nonBoss" then
                setBlockedLootWindowBossContext(raidNum, source or "lootWindowBlocked", currentTime, ttlSeconds, sourceUnitContext)
                return 0
            end
        end

        local recentState, recentBossNid = resolveRecentLootDeathContext(raid, raidNum, currentTime, ttlSeconds, source)
        if recentState == "blocked" then
            return 0
        end
        if recentState == "boss" and recentBossNid > 0 then
            return recentBossNid
        end

        bossNid = peekBossEventContext(raidNum, currentTime)
        if bossNid <= 0 then
            setActiveLootSource(raid, raidNum, "object", 0, nil, currentTime, ttlSeconds, nil)
            return 0
        end

        return setLootWindowBossContext(raid, raidNum, bossNid, source or "lootWindow", currentTime, ttlSeconds)
    end

    local function findAndRememberBossContextForLoot(raid, raidNum, rollSessionId, now, ttlSeconds, allowLootWindowContext, allowContextRecovery, applyLastBossOnRecovery)
        local currentTime = tonumber(now) or Time.GetCurrentTime()
        local bossNid = resolveLootBossSession(raid, raidNum, rollSessionId, currentTime)
        local contextBlocked = false

        if bossNid <= 0 and allowLootWindowContext then
            local contextState = resolveLootWindowContextState(raid, raidNum, currentTime)
            if contextState == "blocked" then
                contextBlocked = true
                allowContextRecovery = false
            else
                bossNid = resolveLootWindowBossContext(raid, raidNum, currentTime)
            end
        end
        if bossNid <= 0 and not contextBlocked then
            local recentState, recentBossNid = resolveRecentLootDeathContext(raid, raidNum, currentTime, ttlSeconds, "lootRecentDeath")
            if recentState == "blocked" then
                contextBlocked = true
                allowContextRecovery = false
            elseif recentState == "boss" and recentBossNid > 0 then
                bossNid = recentBossNid
            end
        end
        if bossNid <= 0 and not contextBlocked and allowContextRecovery then
            if applyLastBossOnRecovery then
                bossNid = recoverBossEventContext(raidNum, currentTime)
            else
                bossNid = peekBossEventContext(raidNum, currentTime)
            end
        end

        if bossNid > 0 and rollSessionId then
            rememberLootBossSession(raidNum, rollSessionId, bossNid, ttlSeconds)
        end

        return tonumber(bossNid) or 0
    end

    local function findOrCreateTrashBossNid(raidNum, raid)
        local bossKills = raid and raid.bossKills or {}
        for i = #bossKills, 1, -1 do
            local boss = bossKills[i]
            if boss and isTrashMobName(boss.name) then
                local existingBossNid = tonumber(boss.bossNid) or 0
                if existingBossNid > 0 then
                    return existingBossNid
                end
            end
        end

        local createdBossNid = tonumber(module:AddBoss(TRASH_MOB_NAME, nil, raidNum)) or 0
        return createdBossNid
    end

    -- ----- Public methods ----- --

    function module:RequestMasterLootCandidateRefresh()
        invalidateMasterLootCandidateCache()
    end

    function module:FindMasterLootCandidateIndex(itemLink, playerName)
        local cache = ensureMasterLootCandidateCache(itemLink)
        local candidateIndex = cache.indexByName[playerName]
        if not candidateIndex then
            if isDebugEnabled() then
                addon:debug(Diag.D.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            end
            cache = buildMasterLootCandidateCache(itemLink)
            candidateIndex = cache.indexByName[playerName]
        end
        return candidateIndex
    end

    function module:CanResolveMasterLootCandidates(itemLink)
        local cache = ensureMasterLootCandidateCache(itemLink)
        return next(cache.indexByName) ~= nil
    end

    function module:EnsureRaidPlayerNid(name, raidNum)
        return ensureRaidPlayerNid(name, raidNum)
    end

    function module:FindAndRememberBossContextForLootSession(raidNum, rollSessionId, options)
        options = options or {}
        local raid = type(Core.EnsureRaidById) == "function" and Core.EnsureRaidById(raidNum) or nil
        if not raid then
            return 0
        end
        return findAndRememberBossContextForLoot(
            raid,
            raidNum,
            rollSessionId,
            options.now,
            options.ttlSeconds,
            options.allowLootWindowContext == true,
            options.allowContextRecovery == true,
            false
        )
    end

    function module:SetBossContextForLootSession(raidNum, rollSessionId, bossNid, ttlSeconds)
        rememberLootBossSession(raidNum, rollSessionId, bossNid, ttlSeconds)
        return tonumber(bossNid) or 0
    end

    module._EnsureLootWindowItemContext = function(_, raidNum, items, options)
        options = options or {}
        local raid = type(Core.EnsureRaidById) == "function" and Core.EnsureRaidById(raidNum) or nil
        if not raid then
            return 0
        end

        local snapshot = findMatchingLootWindowItemSnapshot(raidNum, items)
        if snapshot then
            return setActiveLootWindowItemSnapshot(raid, raidNum, snapshot, options.now, options.ttlSeconds)
        end

        local bossNid = tonumber(options.bossNid) or 0
        if bossNid <= 0 then
            bossNid = ensureLootWindowBossContext(raid, raidNum, options.now, options.ttlSeconds, options.source)
        end
        if bossNid <= 0 then
            clearActiveLootWindowItemSnapshot()
            return 0
        end

        snapshot = createLootWindowItemSnapshot(raidNum, bossNid, items, options.source, options.now, options.ttlSeconds)
        if not snapshot then
            local boss = findBossByNid(raid, bossNid)
            setActiveLootSource(raid, raidNum, boss and isTrashMobName(boss.name) and "trash" or "boss", bossNid, nil, options.now, options.ttlSeconds, nil)
            return bossNid
        end

        return setActiveLootWindowItemSnapshot(raid, raidNum, snapshot, options.now, options.ttlSeconds)
    end

    module._ConsumeLootWindowItemContext = function(_, itemLink)
        return consumeActiveLootWindowItemSnapshot(itemLink)
    end

    function module:GetActiveLootSource(raidNum, bossNidOverride)
        local source = getLootSourceState()
        if type(source) ~= "table" then
            return nil
        end

        local expiresAt = tonumber(source.expiresAt) or 0
        if expiresAt > 0 and Time.GetCurrentTime() > expiresAt then
            clearLootSourceState()
            return nil
        end

        local queryRaidNum = tonumber(raidNum) or tonumber(Core.GetCurrentRaid and Core.GetCurrentRaid()) or 0
        local sourceRaidNum = tonumber(source.raidNum) or 0
        if queryRaidNum > 0 and sourceRaidNum > 0 and queryRaidNum ~= sourceRaidNum then
            return nil
        end

        return copyActiveLootSource(syncActiveLootContextState(), bossNidOverride)
    end

    function module:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, options)
        options = options or {}
        local currentTime = tonumber(options.now) or Time.GetCurrentTime()
        local allowContextRecovery = options.allowContextRecovery == true
        local allowLootWindowContext = options.allowLootWindowContext == true
        local allowTrashFallback = options.allowTrashFallback == true
        local ttlSeconds = options.ttlSeconds

        local bossNid = findAndRememberBossContextForLoot(raid, raidNum, rollSessionId, currentTime, ttlSeconds, allowLootWindowContext, allowContextRecovery, true)
        if bossNid <= 0 and allowTrashFallback then
            bossNid = findOrCreateTrashBossNid(raidNum, raid)
        end
        if bossNid > 0 then
            if allowLootWindowContext then
                setLootWindowBossContext(raid, raidNum, bossNid, "lootWindow", currentTime, ttlSeconds, nil, nil, false)
            end
        end
        return tonumber(bossNid) or 0
    end

    function module:ClearLootWindowBossContext()
        clearLootWindowBossContext()
        clearActiveLootWindowItemSnapshot()
    end

    -- Creates a new raid log entry.
    function module:Create(zoneName, raidSize, raidDiff)
        if not addon.IsInRaid() then
            return false
        end

        local num = GetNumRaidMembers()
        if num == 0 then
            return false
        end

        if Core.GetCurrentRaid() then
            self:End()
        end

        if type(module._SetNumRaidInternal) == "function" then
            module._SetNumRaidInternal(num)
        end

        local realm = Core.GetRealmName()
        local realmPlayers = (type(module._EnsureRealmPlayerMetaInternal) == "function" and module._EnsureRealmPlayerMetaInternal(realm)) or {}
        local currentTime = Time.GetCurrentTime()

        local instanceDiff = tonumber(raidDiff)
        if not instanceDiff then
            instanceDiff = resolveRaidDifficulty()
        end

        local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("Raid.Create", { "CreateRaidRecord", "InsertRaid" }) or nil
        if not raidStore then
            return false
        end

        local raidInfo = raidStore:CreateRaidRecord({
            realm = realm,
            zone = zoneName,
            size = raidSize,
            difficulty = tonumber(instanceDiff) or nil,
            startTime = currentTime,
        })

        for i = 1, num do
            local name, rank, subgroup, level, classL, class = getRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)

                local p = {
                    playerNid = raidInfo.nextPlayerNid,
                    name = name,
                    rank = rank or 0,
                    subgroup = subgroup or 1,
                    class = class or "UNKNOWN",
                    join = Time.GetCurrentTime(),
                    leave = nil,
                    count = 0,
                }
                raidInfo.nextPlayerNid = (tonumber(raidInfo.nextPlayerNid) or 1) + 1

                tinsert(raidInfo.players, p)

                if type(module._UpsertPlayerMetaInternal) == "function" then
                    module._UpsertPlayerMetaInternal(realmPlayers, name, unitID, level, race, raceL, class, classL)
                end
            end
        end

        local _, raidId = raidStore:InsertRaid(raidInfo)
        if not raidId then
            return false
        end
        Core.SetCurrentRaid(raidId)
        resetLootContextState()
        -- New session context: force version-gated roster consumers (e.g. Master dropdowns) to rebuild.
        if type(module._BumpRosterVersionInternal) == "function" then
            module._BumpRosterVersionInternal()
        end
        if type(module._ResetRosterTrackingInternal) == "function" then
            module._ResetRosterTrackingInternal()
        end

        addon:info(Diag.I.LogRaidCreated:format(Core.GetCurrentRaid() or -1, tostring(zoneName), tonumber(raidSize) or -1, #raidInfo.players))

        Bus.TriggerEvent(InternalEvents.RaidCreate, Core.GetCurrentRaid())

        -- Schedule one delayed roster refresh.
        if type(module._ScheduleRosterRefreshInternal) == "function" then
            module._ScheduleRosterRefreshInternal()
        end
        return true
    end

    -- Stable-ID helpers (bossNid / lootNid).
    -- Fresh SavedVariables only. Schema is normalized by Core.EnsureRaidSchema().

    function module:EnsureStableIds(raidNum)
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)
    end

    -- Ends the current raid log entry, marking end time.
    function module:End()
        if type(module.CancelInstanceChecks) == "function" then
            module:CancelInstanceChecks()
        end
        if type(module._ResetRosterTrackingInternal) == "function" then
            module._ResetRosterTrackingInternal()
        end
        if not Core.GetCurrentRaid() then
            return
        end
        -- Stop any pending roster update when ending the raid
        if type(module._CancelRosterRefreshInternal) == "function" then
            module._CancelRosterRefreshInternal()
        end
        local currentTime = Time.GetCurrentTime()
        local raid = Core.EnsureRaidById(Core.GetCurrentRaid())
        if raid then
            local duration = currentTime - (raid.startTime or currentTime)
            addon:info(
                Diag.I.LogRaidEnded:format(
                    Core.GetCurrentRaid() or -1,
                    tostring(raid.zone),
                    tonumber(raid.size) or -1,
                    raid.bossKills and #raid.bossKills or 0,
                    raid.loot and #raid.loot or 0,
                    duration
                )
            )

            for _, v in ipairs(raid.players) do
                if not v.leave then
                    v.leave = currentTime
                end
            end
            raid.endTime = currentTime
        end
        Core.SetCurrentRaid(nil)
        Core.SetLastBoss(nil)
        resetLootContextState()
    end

    -- Performs an initial raid check on player login.
    function module:FirstCheck()
        -- Cancel any pending first-check timer before starting a new one
        if module.firstCheckHandle then
            module:CancelTimer(module.firstCheckHandle)
            module.firstCheckHandle = nil
        end
        if not addon.IsInGroup() then
            return
        end

        if Core.GetCurrentRaid() and module:CheckPlayer(Core.GetPlayerName(), Core.GetCurrentRaid()) then
            -- Restart the roster update timer: cancel the old one and schedule a new one
            if type(module._ScheduleRosterRefreshInternal) == "function" then
                module._ScheduleRosterRefreshInternal()
            end
            return
        end

        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        if isDebugEnabled() then
            addon:debug(
                Diag.D.LogRaidFirstCheck:format(
                    tostring(addon.IsInGroup()),
                    tostring(Core.GetCurrentRaid() ~= nil),
                    tostring(instanceName),
                    tostring(instanceType),
                    tostring(instanceDiff)
                )
            )
        end
        if instanceType == "raid" then
            module:Check(instanceName, instanceDiff)
            return
        end
    end

    -- Adds a player to the raid log.
    function module:AddPlayer(t, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not t or not t.name then
            return
        end
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local players = module:GetPlayers(raidNum)
        local found = false
        local nextPlayerNid = tonumber(raid.nextPlayerNid) or 1

        for i, p in ipairs(players) do
            if t.name == p.name then
                -- Preserve countMS if present (falls back through legacy 'count' field).
                t.countMS = t.countMS or p.countMS or tonumber(p.count) or 0
                t.playerNid = tonumber(t.playerNid) or tonumber(p.playerNid) or nextPlayerNid
                if tonumber(t.playerNid) >= nextPlayerNid then
                    raid.nextPlayerNid = tonumber(t.playerNid) + 1
                end
                raid.players[i] = t
                found = true
                break
            end
        end

        if not found then
            t.countMS = t.countMS or 0
            t.playerNid = tonumber(t.playerNid) or nextPlayerNid
            raid.nextPlayerNid = tonumber(t.playerNid) + 1
            tinsert(raid.players, t)
            if isTraceEnabled() then
                addon:trace(Diag.D.LogRaidPlayerJoin:format(tostring(t.name), tonumber(raidNum) or -1))
            end
        else
            if isTraceEnabled() then
                addon:trace(Diag.D.LogRaidPlayerRefresh:format(tostring(t.name), tonumber(raidNum) or -1))
            end
        end
        invalidateRaidRuntime(raid)
    end

    -- Adds a boss kill to the active raid log.
    function module:AddBoss(bossName, manDiff, raidNum, sourceNpcId)
        sourceNpcId = tonumber(sourceNpcId)
        local sourceKind = sourceNpcId and classifyNpcLootSource(sourceNpcId) or nil
        if sourceKind == "ignored" then
            if isTraceEnabled() then
                addon:trace(Diag.D.LogBossUnitDiedIgnored:format(sourceNpcId, tostring(bossName)))
            end
            return 0
        end

        if isUnknownName(bossName) then
            bossName = nil
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not bossName then
            if isDebugEnabled() then
                addon:debug(Diag.D.LogBossAddSkipped:format(tostring(raidNum), tostring(bossName)))
            end
            return 0
        end
        local isTrashBoss = isTrashMobName(bossName)

        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end
        Core.EnsureRaidSchema(raid)

        local instanceDiff = resolveRaidDifficulty()
        if manDiff then
            instanceDiff = (raid.size == 10) and 1 or 2
            if Strings.NormalizeLower(manDiff, true) == "h" then
                instanceDiff = instanceDiff + 2
            end
        end

        local currentTime = Time.GetCurrentTime()
        local bossSource = sourceNpcId and "UNIT_DIED" or "YELL"
        local existingBoss, delta = findRecentBossKillByName(raid, bossName, currentTime)
        if existingBoss then
            local existingBossNid = tonumber(existingBoss.bossNid) or 0
            if existingBossNid > 0 then
                Core.SetLastBoss(existingBossNid)
                if not isTrashBoss then
                    setBossEventContext(raidNum, existingBossNid, bossName, bossSource, currentTime)
                else
                    clearBossEventContext()
                end
            end
            if isTraceEnabled() then
                addon:trace(Diag.D.LogBossDuplicateSuppressed:format(tostring(bossName), sourceNpcId or -1, existingBossNid, tonumber(delta) or -1))
            end
            return existingBossNid
        end

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

        local bossNid = tonumber(raid.nextBossNid) or 1
        raid.nextBossNid = bossNid + 1

        local killInfo = {
            bossNid = bossNid,
            name = bossName,
            sourceNpcId = sourceNpcId or nil,
            difficulty = instanceDiff,
            mode = (instanceDiff == 3 or instanceDiff == 4) and "h" or "n",
            players = players,
            time = currentTime,
            hash = Base64.Encode(raidNum .. "|" .. bossName .. "|" .. bossNid),
        }

        tinsert(raid.bossKills, killInfo)
        invalidateRaidRuntime(raid)
        Core.SetLastBoss(bossNid)
        if not isTrashBoss then
            setBossEventContext(raidNum, bossNid, bossName, bossSource, currentTime)
        else
            clearBossEventContext()
        end
        addon:info(Diag.I.LogBossLogged:format(tostring(bossName), tonumber(instanceDiff) or -1, tonumber(raidNum) or -1, #players))
        if isDebugEnabled() then
            addon:debug(Diag.D.LogBossLastBossHash:format(tonumber(Core.GetLastBoss()) or -1, tostring(killInfo.hash)))
        end
        return bossNid
    end

    -- Raid functions.

    function module:IsPlayerInRaid()
        if addon.IsInRaid() then
            return true
        end
        local groupType = addon.GetGroupTypeAndCount()
        if groupType == "raid" then
            return true
        end
        if UnitInRaid("player") then
            return true
        end
        return (GetNumRaidMembers() or 0) > 0
    end

    -- Returns raid size: 10 or 25.
    function module:GetRaidSize()
        local _, _, members = addon.GetGroupTypeAndCount()
        if members == 0 then
            return 0
        end

        local diff = Time.GetDifficulty()
        if diff then
            return (diff == 1 or diff == 3) and 10 or 25
        end

        return members > 20 and 25 or 10
    end

    -- Checks if a raid log is expired (older than the weekly reset).
    function module:Expired(rID)
        local raid = Core.EnsureRaidById(rID)
        if not raid then
            return true
        end

        local startTime = raid.startTime
        local currentTime = Time.GetCurrentTime()
        local week = 604800 -- 7 days in seconds

        if Core.GetNextReset() and Core.GetNextReset() > currentTime then
            return startTime < (Core.GetNextReset() - week)
        end

        return currentTime >= startTime + week
    end

    -- Retrieves all loot for a given raid and optional boss number.
    function module:GetLoot(raidNum, bossNid)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        bossNid = tonumber(bossNid) or 0
        if not raid then
            return {}
        end
        Core.EnsureRaidSchema(raid)

        local loot = raid.loot or {}
        if bossNid <= 0 then
            return loot
        end

        local items = {}
        for _, v in ipairs(loot) do
            if tonumber(v.bossNid) == bossNid then
                tinsert(items, v)
            end
        end
        return items
    end

    -- Processes COMBAT_LOG_EVENT_UNFILTERED for boss-kill detection.
    function module:COMBAT_LOG_EVENT_UNFILTERED(...)
        if not Core.GetCurrentRaid() then
            return
        end

        -- Hot-path fast check: inspect the event type before unpacking extra args.
        local subEvent = select(2, ...)
        if subEvent ~= "UNIT_DIED" then
            return
        end

        -- 3.3.5a base params (8):
        -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags
        local destGUID, destName, destFlags = select(6, ...)
        if bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then
            return
        end

        -- LibCompat embeds GetCreatureId with the 3.3.5a GUID parsing rules.
        local npcId = destGUID and addon.GetCreatureId(destGUID)
        local sourceKind, sourceNpcId, sourceBossName = classifyNpcLootSource(npcId)
        if sourceKind == "ignored" then
            if isTraceEnabled() then
                addon:trace(Diag.D.LogBossUnitDiedIgnored:format(tonumber(sourceNpcId) or -1, tostring(destName)))
            end
            return
        end
        if sourceKind ~= "boss" then
            if sourceKind == "trash" then
                rememberRecentTrashDeathContext(Core.GetCurrentRaid(), destName, sourceNpcId, Time.GetCurrentTime())
            end
            return
        end

        local boss = destName or sourceBossName
        if boss then
            if isTraceEnabled() then
                addon:trace(Diag.D.LogBossUnitDiedMatched:format(tonumber(sourceNpcId) or -1, tostring(boss)))
            end
            local bossNid = module:AddBoss(boss, nil, nil, sourceNpcId)
            setRecentLootDeathContext(Core.GetCurrentRaid(), "boss", boss, sourceNpcId, bossNid, "UNIT_DIED", Time.GetCurrentTime())
        end
    end
end
