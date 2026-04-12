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
local pairs, ipairs, type, select = pairs, ipairs, type, select

local tostring, tonumber = tostring, tonumber
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

    -- ----- Private helpers ----- --
    local function invalidateMasterLootCandidateCache()
        masterLootCandidateCache.itemLink = nil
        masterLootCandidateCache.rosterVersion = nil
        twipe(masterLootCandidateCache.indexByName)
    end

    local function buildMasterLootCandidateCache(itemLink)
        local currentRosterVersion = (type(module.GetRosterVersion) == "function" and module:GetRosterVersion()) or 0
        masterLootCandidateCache.itemLink = itemLink
        masterLootCandidateCache.rosterVersion = currentRosterVersion
        twipe(masterLootCandidateCache.indexByName)

        for p = 1, addon.GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                masterLootCandidateCache.indexByName[candidate] = p
            end
        end

        addon:debug(Diag.D.LogMLCandidateCacheBuilt:format(tostring(itemLink), addon.tLength(masterLootCandidateCache.indexByName)))
        return masterLootCandidateCache
    end

    local function ensureMasterLootCandidateCache(itemLink)
        local currentRosterVersion = (type(module.GetRosterVersion) == "function" and module:GetRosterVersion()) or 0
        if masterLootCandidateCache.itemLink ~= itemLink or masterLootCandidateCache.rosterVersion ~= currentRosterVersion then
            return buildMasterLootCandidateCache(itemLink)
        end
        return masterLootCandidateCache
    end

    local function getLootBossSessionState()
        raidState.lootBossSessions = raidState.lootBossSessions or {}
        local state = raidState.lootBossSessions
        state.bySessionId = state.bySessionId or {}
        return state
    end

    local function clearLootBossSessionState()
        raidState.lootBossSessions = nil
    end

    local function purgeExpiredLootBossSessions(now)
        local state = getLootBossSessionState()
        local currentTime = tonumber(now) or Time.GetCurrentTime()

        for sessionId, entry in pairs(state.bySessionId) do
            local expiresAt = tonumber(entry and entry.expiresAt) or 0
            local entryRaidNum = tonumber(entry and entry.raidNum) or 0
            local entryBossNid = tonumber(entry and entry.bossNid) or 0
            if type(sessionId) ~= "string" or sessionId == "" or entryRaidNum <= 0 or entryBossNid <= 0 or (expiresAt > 0 and expiresAt <= currentTime) then
                state.bySessionId[sessionId] = nil
            end
        end
    end

    local function rememberLootBossSession(raidNum, rollSessionId, bossNid, ttlSeconds)
        local sessionId = rollSessionId and tostring(rollSessionId) or nil
        local resolvedRaidNum = tonumber(raidNum) or 0
        local resolvedBossNid = tonumber(bossNid) or 0
        if not sessionId or sessionId == "" or resolvedRaidNum <= 0 or resolvedBossNid <= 0 then
            return
        end

        local ttl = tonumber(ttlSeconds) or GROUP_LOOT_PENDING_AWARD_TTL_SECONDS
        if ttl < 1 then
            ttl = GROUP_LOOT_PENDING_AWARD_TTL_SECONDS
        end

        local state = getLootBossSessionState()
        local now = Time.GetCurrentTime()
        state.bySessionId[sessionId] = {
            raidNum = resolvedRaidNum,
            bossNid = resolvedBossNid,
            expiresAt = now + ttl,
        }
    end

    local function resolveLootBossSession(raid, raidNum, rollSessionId, now)
        local sessionId = rollSessionId and tostring(rollSessionId) or nil
        if not sessionId or sessionId == "" then
            return 0
        end

        local currentTime = tonumber(now) or Time.GetCurrentTime()
        purgeExpiredLootBossSessions(currentTime)

        local state = getLootBossSessionState()
        local entry = state.bySessionId[sessionId]
        if type(entry) ~= "table" then
            return 0
        end

        local entryRaidNum = tonumber(entry.raidNum) or 0
        local entryBossNid = tonumber(entry.bossNid) or 0
        if entryRaidNum ~= (tonumber(raidNum) or 0) or entryBossNid <= 0 then
            state.bySessionId[sessionId] = nil
            return 0
        end

        local bosses = raid and raid.bossKills or {}
        for i = 1, #bosses do
            local boss = bosses[i]
            if boss and tonumber(boss.bossNid) == entryBossNid then
                return entryBossNid
            end
        end

        state.bySessionId[sessionId] = nil
        return 0
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

    local function shouldIgnoreBossKillNpcId(npcId)
        if type(IgnoredMobs.Contains) ~= "function" then
            return false
        end
        return IgnoredMobs.Contains(npcId)
    end

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
        raidState.bossEventContext = nil
    end

    local function setBossEventContext(raidNum, bossNid, bossName, source, seenAt)
        raidNum = tonumber(raidNum) or 0
        bossNid = tonumber(bossNid) or 0
        if raidNum <= 0 or bossNid <= 0 or not bossName then
            clearBossEventContext()
            return nil
        end

        raidState.bossEventContext = {
            raidNum = raidNum,
            bossNid = bossNid,
            name = bossName,
            source = source or "event",
            seenAt = tonumber(seenAt) or Time.GetCurrentTime(),
        }

        addon:debug(Diag.D.LogBossEventContextSet:format(tostring(bossName), bossNid, raidNum, tostring(source or "event")))

        return raidState.bossEventContext
    end

    local function resolveBossEventContext(raidNum, now, applyLastBoss)
        local bossEventContext = raidState.bossEventContext
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
            addon:debug(Diag.D.LogBossEventContextRecovered:format(tostring(contextBossName), contextBossNid, tonumber(delta) or -1, tostring(bossEventContext.source or "event")))
        end

        return contextBossNid
    end

    local function recoverBossEventContext(raidNum, now)
        return resolveBossEventContext(raidNum, now, true)
    end

    local function peekBossEventContext(raidNum, now)
        return resolveBossEventContext(raidNum, now, false)
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
            addon:debug(Diag.D.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
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

    function module:FindAndRememberBossEventContextForLootSession(raidNum, rollSessionId, ttlSeconds, now)
        local contextBossNid = peekBossEventContext(raidNum, now)
        if tonumber(contextBossNid) > 0 then
            rememberLootBossSession(raidNum, rollSessionId, contextBossNid, ttlSeconds)
        end
        return tonumber(contextBossNid) or 0
    end

    function module:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, options)
        options = options or {}
        local currentTime = tonumber(options.now) or Time.GetCurrentTime()
        local allowContextRecovery = options.allowContextRecovery == true
        local allowTrashFallback = options.allowTrashFallback == true
        local ttlSeconds = options.ttlSeconds

        local bossNid = resolveLootBossSession(raid, raidNum, rollSessionId, currentTime)
        if bossNid <= 0 and allowContextRecovery then
            bossNid = recoverBossEventContext(raidNum, currentTime)
        end
        if bossNid <= 0 and allowTrashFallback then
            bossNid = findOrCreateTrashBossNid(raidNum, raid)
        end
        if bossNid > 0 then
            rememberLootBossSession(raidNum, rollSessionId, bossNid, ttlSeconds)
        end
        return tonumber(bossNid) or 0
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
        clearBossEventContext()
        clearLootBossSessionState()
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

            for _, v in pairs(raid.players) do
                if not v.leave then
                    v.leave = currentTime
                end
            end
            raid.endTime = currentTime
        end
        Core.SetCurrentRaid(nil)
        Core.SetLastBoss(nil)
        clearBossEventContext()
        clearLootBossSessionState()
    end

    -- Performs an initial raid check on player login.
    function module:FirstCheck()
        -- Cancel any pending first-check timer before starting a new one
        addon.CancelTimer(module.firstCheckHandle, true)
        module.firstCheckHandle = nil
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
        addon:debug(
            Diag.D.LogRaidFirstCheck:format(
                tostring(addon.IsInGroup()),
                tostring(Core.GetCurrentRaid() ~= nil),
                tostring(instanceName),
                tostring(instanceType),
                tostring(instanceDiff)
            )
        )
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
                -- Preserve count if present
                t.count = t.count or p.count or 0
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
            t.count = t.count or 0
            t.playerNid = tonumber(t.playerNid) or nextPlayerNid
            raid.nextPlayerNid = tonumber(t.playerNid) + 1
            tinsert(raid.players, t)
            addon:trace(Diag.D.LogRaidPlayerJoin:format(tostring(t.name), tonumber(raidNum) or -1))
        else
            addon:trace(Diag.D.LogRaidPlayerRefresh:format(tostring(t.name), tonumber(raidNum) or -1))
        end
        invalidateRaidRuntime(raid)
    end

    -- Adds a boss kill to the active raid log.
    function module:AddBoss(bossName, manDiff, raidNum, sourceNpcId)
        sourceNpcId = tonumber(sourceNpcId)
        if sourceNpcId and shouldIgnoreBossKillNpcId(sourceNpcId) then
            addon:trace(Diag.D.LogBossUnitDiedIgnored:format(sourceNpcId, tostring(bossName)))
            return 0
        end

        if isUnknownName(bossName) then
            bossName = nil
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not bossName then
            addon:debug(Diag.D.LogBossAddSkipped:format(tostring(raidNum), tostring(bossName)))
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
            addon:trace(Diag.D.LogBossDuplicateSuppressed:format(tostring(bossName), sourceNpcId or -1, existingBossNid, tonumber(delta) or -1))
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
        addon:debug(Diag.D.LogBossLastBossHash:format(tonumber(Core.GetLastBoss()) or -1, tostring(killInfo.hash)))
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
        local bossLib = addon.BossIDs
        local bossIds = bossLib and bossLib.BossIDs
        if not (npcId and bossIds and bossIds[npcId]) then
            return
        end

        local boss = destName
        if not boss and bossLib and bossLib.GetBossName then
            boss = bossLib:GetBossName(npcId)
        end
        if boss then
            addon:trace(Diag.D.LogBossUnitDiedMatched:format(tonumber(npcId) or -1, tostring(boss)))
            module:AddBoss(boss, nil, nil, npcId)
        end
    end
end
