-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Events = feature.Events or addon.Events or {}
local C = feature.C
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Time = feature.Time or addon.Time
local Base64 = feature.Base64 or addon.Base64
local IgnoredItems = feature.IgnoredItems or addon.IgnoredItems or {}
local IgnoredMobs = feature.IgnoredMobs or addon.IgnoredMobs or {}

local InternalEvents = Events.Internal

local ITEM_LINK_PATTERN = feature.ITEM_LINK_PATTERN
local rollTypes = feature.rollTypes

local lootState = feature.lootState
local raidState = feature.raidState

local tinsert, twipe = table.insert, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select
local strlen = string.len
local strmatch = string.match

local tostring, tonumber = tostring, tonumber
local UnitRace, UnitSex = UnitRace, UnitSex

-- Raid helper module.
-- Manages raid state, roster, boss kills, and loot logging.
do
    addon.Services = addon.Services or {}
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid
    -- ----- Internal state ----- --
    local numRaid = 0
    local rosterVersion = 0
    local getLootMethod = GetLootMethod
    local getRaidRosterInfo = GetRaidRosterInfo
    local unitIsUnit = UnitIsUnit
    local liveUnitsByName = {}
    local liveNamesByUnit = {}
    local pendingUnits = {}
    local raidInstanceCheckHandles = {}

    local UNKNOWN_OBJECT = _G.UNKNOWNOBJECT
    local UNKNOWN_BEING = _G.UNKNOWNBEING or _G.UKNOWNBEING
    local RETRY_DELAY_SECONDS = 1
    local RETRY_MAX_ATTEMPTS = 5
    local RAID_INSTANCE_CHECK_DELAYS = { 0.3, 0.8, 1.5, 2.5, 3.5 }

    local function getLootService()
        local services = addon.Services
        return services and services.Loot or nil
    end

    local function getRollsService()
        local services = addon.Services
        return services and services.Rolls or nil
    end
    local BOSS_KILL_DEDUPE_WINDOW_SECONDS = tonumber(C.BOSS_KILL_DEDUPE_WINDOW_SECONDS) or 30
    local PENDING_AWARD_TTL_SECONDS = C.PENDING_AWARD_TTL_SECONDS

    -- ----- Private helpers ----- --
    local function isUnknownName(name)
        return (not name) or name == "" or name == UNKNOWN_OBJECT or name == UNKNOWN_BEING
    end

    local function resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        local session = lootState.rollSession
        if type(session) ~= "table" then
            return nil
        end
        local sessionId = session.id
        if not sessionId or sessionId == "" then
            return nil
        end

        local sessionItemId = tonumber(session.itemId)
        local parsedItemId = tonumber(itemId)
        if sessionItemId and parsedItemId and sessionItemId == parsedItemId then
            return tostring(sessionId)
        end

        local sessionKey = session.itemKey
        if sessionKey and itemString and sessionKey == itemString then
            return tostring(sessionId)
        end
        if sessionKey and itemLink and sessionKey == itemLink then
            return tostring(sessionId)
        end
        return nil
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

    local function bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        local resolvedLootNid = tonumber(lootNid)
        local session = lootState.rollSession
        if not resolvedLootNid or resolvedLootNid <= 0 or type(session) ~= "table" then
            return
        end

        local sessionId = session.id and tostring(session.id) or nil
        local matchedSessionId = rollSessionId and tostring(rollSessionId) or nil
        if not matchedSessionId then
            matchedSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end
        if not sessionId or matchedSessionId ~= sessionId then
            return
        end

        session.lootNid = resolvedLootNid
        lootState.currentRollItem = resolvedLootNid
    end

    local function resetLiveUnitCaches()
        twipe(liveUnitsByName)
        twipe(liveNamesByUnit)
    end

    local function resetPendingUnitRetry()
        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = nil
        twipe(pendingUnits)
    end

    local function markPendingUnit(unitID)
        local tries = tonumber(pendingUnits[unitID]) or 0
        if tries < RETRY_MAX_ATTEMPTS then
            pendingUnits[unitID] = tries + 1
        end
    end

    local function trimPendingUnits(maxRaidSize)
        for unitID in pairs(pendingUnits) do
            local idx = tonumber(strmatch(unitID, "^raid(%d+)$")) or 0
            if idx <= 0 or idx > maxRaidSize then
                pendingUnits[unitID] = nil
            end
        end
    end

    local function hasRetryablePendingUnits()
        for _, tries in pairs(pendingUnits) do
            if (tonumber(tries) or 0) < RETRY_MAX_ATTEMPTS then
                return true
            end
        end
        return false
    end

    local function schedulePendingUnitRetry()
        if not hasRetryablePendingUnits() then
            return
        end

        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = addon.NewTimer(RETRY_DELAY_SECONDS, function()
            module.pendingUnitRetryHandle = nil
            if not addon.IsInRaid() then
                return
            end
            addon:RAID_ROSTER_UPDATE(true)
        end)
    end

    local function finalizeRosterDelta(delta)
        if #delta.joined == 0 then
            delta.joined = nil
        end
        if #delta.updated == 0 then
            delta.updated = nil
        end
        if #delta.left == 0 then
            delta.left = nil
        end
        if #delta.unresolved == 0 then
            delta.unresolved = nil
        end
        if delta.joined or delta.updated or delta.left or delta.unresolved then
            return delta
        end
        return nil
    end

    local function ensureRealmPlayerMeta(realm)
        KRT_Players[realm] = KRT_Players[realm] or {}
        return KRT_Players[realm]
    end

    local function getSyntheticRosterState(raidNum)
        local debugState = addon.State and addon.State.debug or nil
        local syntheticByRaid = debugState and debugState.syntheticByRaid or nil
        if type(syntheticByRaid) ~= "table" then
            return nil
        end
        return syntheticByRaid[tonumber(raidNum) or -1]
    end

    local function isSyntheticRosterPlayer(name, raidNum)
        local syntheticState = getSyntheticRosterState(raidNum)
        if type(syntheticState) ~= "table" or not name then
            return false
        end
        return syntheticState[name] == true
    end

    local function upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
        if not (realmPlayers and name and unitID) then
            return
        end

        local known = realmPlayers[name]
        if not known then
            known = {}
            realmPlayers[name] = known
        end

        known.name = name
        known.level = level or 0
        known.race = race
        known.raceL = raceL
        known.class = class or "UNKNOWN"
        known.classL = classL
        known.sex = UnitSex(unitID) or 0
    end

    local function findRaidPlayerByNid(raid, playerNid)
        local nid = tonumber(playerNid)
        if not nid or nid <= 0 then
            return nil
        end

        local players = raid and raid.players or {}
        for i = #players, 1, -1 do
            local player = players[i]
            if player and tonumber(player.playerNid) == nid then
                return player, i
            end
        end
        return nil
    end

    local function resolveLootLooterName(raid, loot)
        if type(loot) ~= "table" then
            return nil
        end
        local looterNid = tonumber(loot.looterNid)
        if looterNid and looterNid > 0 then
            local player = findRaidPlayerByNid(raid, looterNid)
            if player and player.name then
                return player.name
            end
        end
        return nil
    end

    local function resolveRaidDifficulty(instanceDiff)
        local diff = tonumber(instanceDiff)
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

    local function cancelRaidInstanceChecks()
        for idx, handle in pairs(raidInstanceCheckHandles) do
            addon.CancelTimer(handle, true)
            raidInstanceCheckHandles[idx] = nil
        end
    end

    local function runLiveRaidInstanceCheck()
        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        if instanceType ~= "raid" then
            return
        end
        if L.RaidZones[instanceName] == nil then
            return
        end
        module:Check(instanceName, instanceDiff)
    end

    local function createRaidSessionWithReason(instanceName, newSize, instanceDiff, isCreate)
        local created = module:Create(instanceName, newSize, instanceDiff)
        if not created then
            return false
        end
        addon:info(L.StrNewRaidSessionChange)
        local template = isCreate and Diag.D.LogRaidSessionCreate or Diag.D.LogRaidSessionChange
        addon:debug(template:format(tostring(instanceName), newSize, tonumber(instanceDiff) or -1))
        return true
    end

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

    -- ----- Public methods ----- --

    function module:GetRosterVersion()
        return rosterVersion
    end

    function module:PublishRosterDelta(delta, raidNum)
        local payload

        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return nil, nil
        end

        if type(delta) ~= "table" then
            delta = {}
        end

        payload = {
            joined = type(delta.joined) == "table" and delta.joined or {},
            updated = type(delta.updated) == "table" and delta.updated or {},
            left = type(delta.left) == "table" and delta.left or {},
            unresolved = type(delta.unresolved) == "table" and delta.unresolved or {},
        }

        rosterVersion = rosterVersion + 1
        payload = finalizeRosterDelta(payload) or payload
        Bus.TriggerEvent(InternalEvents.RaidRosterDelta, payload, rosterVersion, raidNum)
        return rosterVersion, payload
    end

    function module:GetRaid(raidNum)
        if raidNum == nil then
            raidNum = Core.GetCurrentRaid and Core.GetCurrentRaid() or nil
        end
        if not raidNum then
            return nil, nil
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.GetRaid", { "GetRaidByIndex" })
        if raidStore then
            return raidStore:GetRaidByIndex(raidNum)
        end
        return nil, raidNum
    end

    function module:ResolveRaid(raidNum)
        return module:GetRaid(raidNum)
    end

    function module:InvalidateRaidRuntime(raidNum)
        local raid = Core.EnsureRaidById(raidNum)
        if raid then
            invalidateRaidRuntime(raid)
        end
    end

    function module:IsSyntheticPlayerActive(name, raidNum)
        local currentRaidId = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(currentRaidId)
        local resolvedName

        if not raid or not name then
            return false
        end

        resolvedName = Strings.NormalizeName(name, true)
        if not resolvedName or resolvedName == "" then
            return false
        end

        if not isSyntheticRosterPlayer(resolvedName, currentRaidId) then
            return false
        end

        return module:GetPlayerID(resolvedName, currentRaidId) > 0
    end

    function module:CancelInstanceChecks()
        cancelRaidInstanceChecks()
    end

    function module:ScheduleInstanceChecks()
        cancelRaidInstanceChecks()

        -- Immediate live check, then short retries to catch delayed server fallback updates.
        runLiveRaidInstanceCheck()

        for i = 1, #RAID_INSTANCE_CHECK_DELAYS do
            local idx = i
            local delaySeconds = RAID_INSTANCE_CHECK_DELAYS[idx]
            raidInstanceCheckHandles[idx] = addon.NewTimer(delaySeconds, function()
                raidInstanceCheckHandles[idx] = nil
                runLiveRaidInstanceCheck()
            end)
        end
    end

    function module:IsIgnoredItem(itemId)
        if type(IgnoredItems.Contains) ~= "function" then
            return false
        end
        return IgnoredItems.Contains(itemId)
    end

    -- Updates the current raid roster, adding new players and marking those who left.
    -- Returns rosterChanged, delta where delta contains joined/updated/left/unresolved lists.
    function module:UpdateRaidRoster()
        if addon.IsInRaid() then
            local instanceName, instanceType, instanceDiff = GetInstanceInfo()
            if instanceType == "raid" and L.RaidZones[instanceName] ~= nil then
                module:Check(instanceName, instanceDiff)
            end
        end

        if not Core.GetCurrentRaid() then
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            return false
        end
        -- Cancel any pending roster update timer.
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil

        local rosterChanged = false
        local delta = {
            joined = {},
            updated = {},
            left = {},
            unresolved = {},
        }

        if not addon.IsInRaid() then
            rosterChanged = true
            numRaid = 0
            addon:debug(Diag.D.LogRaidLeftGroupEndSession)
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            module:End()
            if rosterChanged then
                rosterVersion = rosterVersion + 1
            end
            return rosterChanged
        end

        local currentRaidId = Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(currentRaidId)
        if not raid then
            return false
        end

        local realm = Core.GetRealmName()
        local realmPlayers = ensureRealmPlayerMeta(realm)
        local raidStore = Core.GetRaidStoreOrNil("Raid.UpdateRaidRoster", { "EnsureRaidRuntime" })
        local runtime = raidStore and raidStore:EnsureRaidRuntime(raid) or nil
        local playersByName = runtime and runtime.playersByName or {}

        local prevNumRaid = numRaid
        local n = GetNumRaidMembers()

        -- Keep local raid-size cache in sync.
        numRaid = n
        if n ~= prevNumRaid then
            rosterChanged = true
        end

        if n == 0 then
            rosterChanged = true
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            module:End()
            rosterVersion = rosterVersion + 1
            return rosterChanged
        end

        local prevUnitsByName = liveUnitsByName
        local prevNamesByUnit = liveNamesByUnit
        local nextUnitsByName = {}
        local nextNamesByUnit = {}
        local seen = {}
        local now = Time.GetCurrentTime()
        local hasUnknownUnits = false

        for i = 1, n do
            local unitID = "raid" .. tostring(i)
            local name, rank, subgroup, level, classL, class = getRaidRosterInfo(i)
            if isUnknownName(name) then
                hasUnknownUnits = true
                markPendingUnit(unitID)
                local prevName = prevNamesByUnit[unitID]
                if prevName and not nextUnitsByName[prevName] then
                    seen[prevName] = true
                    nextUnitsByName[prevName] = unitID
                    nextNamesByUnit[unitID] = prevName
                end
                tinsert(delta.unresolved, { unitID = unitID, name = prevName })
            else
                pendingUnits[unitID] = nil
                nextUnitsByName[name] = unitID
                nextNamesByUnit[unitID] = name

                local raceL, race = UnitRace(unitID)
                local oldUnitID = prevUnitsByName[name]
                local prevPlayer = playersByName[name]
                local active = prevPlayer and prevPlayer.leave == nil
                local player = prevPlayer

                if not active then
                    rosterChanged = true
                    local newRank = rank or (prevPlayer and prevPlayer.rank) or 0
                    local newSubgroup = subgroup or (prevPlayer and prevPlayer.subgroup) or 1
                    local newClass = class or (prevPlayer and prevPlayer.class) or "UNKNOWN"
                    player = {
                        playerNid = prevPlayer and prevPlayer.playerNid or nil,
                        name = name,
                        rank = newRank,
                        subgroup = newSubgroup,
                        class = newClass,
                        join = now,
                        leave = nil,
                        count = (prevPlayer and prevPlayer.count) or 0,
                    }
                    tinsert(delta.joined, {
                        name = name,
                        unitID = unitID,
                        rank = newRank,
                        subgroup = newSubgroup,
                        class = newClass,
                    })
                else
                    local oldRank = player.rank or 0
                    local oldSubgroup = player.subgroup or 1
                    local oldClass = player.class or "UNKNOWN"
                    local newRank = rank or oldRank
                    local newSubgroup = subgroup or oldSubgroup
                    local newClass = class or oldClass
                    local fieldChanged = (oldRank ~= newRank) or (oldSubgroup ~= newSubgroup) or (oldClass ~= newClass)
                    local unitChanged = oldUnitID and (oldUnitID ~= unitID)

                    if fieldChanged or unitChanged then
                        rosterChanged = true
                        tinsert(delta.updated, {
                            name = name,
                            oldUnitID = oldUnitID,
                            unitID = unitID,
                            oldRank = oldRank,
                            rank = newRank,
                            oldSubgroup = oldSubgroup,
                            subgroup = newSubgroup,
                            oldClass = oldClass,
                            class = newClass,
                        })
                    end

                    player.rank = newRank
                    player.subgroup = newSubgroup
                    player.class = newClass
                end

                -- Keep raid.players consistent even if rows were manually edited.
                module:AddPlayer(player)

                seen[name] = true

                upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
            end
        end

        trimPendingUnits(n)
        liveUnitsByName = nextUnitsByName
        liveNamesByUnit = nextNamesByUnit

        -- Mark leavers
        for pname, p in pairs(playersByName) do
            if p.leave == nil and not seen[pname] then
                if isSyntheticRosterPlayer(pname, currentRaidId) then
                    seen[pname] = true
                else
                    p.leave = now
                    rosterChanged = true
                    tinsert(delta.left, {
                        name = pname,
                        unitID = prevUnitsByName[pname],
                        rank = p.rank or 0,
                        subgroup = p.subgroup or 1,
                        class = p.class or "UNKNOWN",
                    })
                end
            end
        end

        if hasUnknownUnits then
            schedulePendingUnitRetry()
        else
            resetPendingUnitRetry()
        end

        delta = finalizeRosterDelta(delta)

        if rosterChanged then
            rosterVersion = rosterVersion + 1
            addon:debug(Diag.D.LogRaidRosterUpdate:format(rosterVersion, n))
        end
        return rosterChanged, delta
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

        numRaid = num

        local realm = Core.GetRealmName()
        local realmPlayers = ensureRealmPlayerMeta(realm)
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

                upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
            end
        end

        local _, raidId = raidStore:InsertRaid(raidInfo)
        if not raidId then
            return false
        end
        Core.SetCurrentRaid(raidId)
        -- New session context: force version-gated roster consumers (e.g. Master dropdowns) to rebuild.
        rosterVersion = rosterVersion + 1
        resetPendingUnitRetry()
        resetLiveUnitCaches()

        addon:info(Diag.I.LogRaidCreated:format(Core.GetCurrentRaid() or -1, tostring(zoneName), tonumber(raidSize) or -1, #raidInfo.players))

        Bus.TriggerEvent(InternalEvents.RaidCreate, Core.GetCurrentRaid())

        -- Schedule one delayed roster refresh.
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        module.updateRosterHandle = addon.NewTimer(2, function()
            module:UpdateRaidRoster()
        end)
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

    function module:GetBossByNid(bossNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or bossNid == nil then
            return nil
        end
        Core.EnsureRaidSchema(raid)

        bossNid = tonumber(bossNid) or 0
        if bossNid <= 0 then
            return nil
        end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local b = bosses[i]
            if b and tonumber(b.bossNid) == bossNid then
                return b, i
            end
        end
        return nil
    end

    function module:GetLootByNid(lootNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or lootNid == nil then
            return nil
        end
        Core.EnsureRaidSchema(raid)

        lootNid = tonumber(lootNid) or 0
        if lootNid <= 0 then
            return nil
        end

        local loot = raid.loot
        for i = 1, #loot do
            local l = loot[i]
            if l and tonumber(l.lootNid) == lootNid then
                return l, i
            end
        end
        return nil
    end

    -- Ends the current raid log entry, marking end time.
    function module:End()
        cancelRaidInstanceChecks()
        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = nil
        twipe(pendingUnits)
        resetLiveUnitCaches()
        if not Core.GetCurrentRaid() then
            return
        end
        -- Stop any pending roster update when ending the raid
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
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
    end

    -- Checks the current raid status and creates a new session if needed.
    function module:Check(instanceName, instanceDiff)
        instanceDiff = resolveRaidDifficulty(instanceDiff)
        local newSize = getRaidSizeFromDifficulty(instanceDiff)
        addon:debug(Diag.D.LogRaidCheck:format(tostring(instanceName), tostring(instanceDiff), tostring(Core.GetCurrentRaid())))
        if not newSize then
            return
        end

        if not Core.GetCurrentRaid() then
            module:Create(instanceName, newSize, instanceDiff)
            return
        end

        local current = Core.EnsureRaidById(Core.GetCurrentRaid())
        if not current then
            createRaidSessionWithReason(instanceName, newSize, instanceDiff, true)
            return
        end

        local shouldCreate = current.zone ~= instanceName or tonumber(current.size) ~= newSize or tonumber(current.difficulty) ~= instanceDiff

        if shouldCreate then
            createRaidSessionWithReason(instanceName, newSize, instanceDiff, false)
        end
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
            addon.CancelTimer(module.updateRosterHandle, true)
            module.updateRosterHandle = nil
            module.updateRosterHandle = addon.NewTimer(2, function()
                module:UpdateRaidRoster()
            end)
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
        local existingBoss, delta = findRecentBossKillByName(raid, bossName, currentTime)
        if existingBoss then
            local existingBossNid = tonumber(existingBoss.bossNid) or 0
            if existingBossNid > 0 then
                Core.SetLastBoss(existingBossNid)
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
                    local playerNid = module:GetPlayerID(resolvedName, raidNum)
                    if playerNid == 0 then
                        module:AddPlayer({
                            name = resolvedName,
                            rank = 0,
                            subgroup = 1,
                            class = "UNKNOWN",
                            join = Time.GetCurrentTime(),
                            leave = nil,
                            count = 0,
                        }, raidNum)
                        playerNid = module:GetPlayerID(resolvedName, raidNum)
                    end
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
        addon:info(Diag.I.LogBossLogged:format(tostring(bossName), tonumber(instanceDiff) or -1, tonumber(raidNum) or -1, #players))
        addon:debug(Diag.D.LogBossLastBossHash:format(tonumber(Core.GetLastBoss()) or -1, tostring(killInfo.hash)))
        return bossNid
    end

    -- Adds a loot item to the active raid log.
    function module:AddLoot(msg, rollType, rollValue)
        -- Parse loot chat variants ("receives loot" and "receives item").
        local player, itemLink, count = addon.Deformat(msg, LOOT_ITEM_MULTIPLE)
        local itemCount = count or 1

        if not player then
            player, itemLink = addon.Deformat(msg, LOOT_ITEM)
            itemCount = 1
        end

        -- Self loot path (no player name in the string).
        if not itemLink then
            local link
            link, count = addon.Deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
            if link then
                itemLink = link
                itemCount = count or 1
                player = Core.GetPlayerName()
            end
        end

        if not itemLink then
            local link = addon.Deformat(msg, LOOT_ITEM_SELF)
            if link then
                itemLink = link
                itemCount = 1
                player = Core.GetPlayerName()
            end
        end

        -- Fallback for alternate loot-roll chat formats.
        if not player or not itemLink then
            itemLink = addon.Deformat(msg, LOOT_ROLL_YOU_WON)
            player = Core.GetPlayerName()
            itemCount = 1
        end
        if not itemLink then
            addon:debug(Diag.D.LogLootParseFailed:format(tostring(msg)))
            return
        end

        player = Strings.NormalizeName(player, true) or player
        itemCount = tonumber(itemCount) or 1

        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        itemId = tonumber(itemId)
        addon:trace(Diag.D.LogLootParsed:format(tostring(player), tostring(itemLink), itemCount))

        -- Ignore low-rarity and explicitly ignored items.
        local lootThreshold = GetLootThreshold()
        if itemRarity and itemRarity < lootThreshold then
            addon:debug(Diag.D.LogLootIgnoredBelowThreshold:format(tostring(itemRarity), tonumber(lootThreshold) or -1, tostring(itemLink)))
            return
        end
        if itemId and module:IsIgnoredItem(itemId) then
            addon:debug(Diag.D.LogLootIgnoredItemId:format(tostring(itemId), tostring(itemLink)))
            return
        end
        raidState.lastLootCount = itemCount

        if not Core.GetLastBoss() then
            addon:debug(Diag.D.LogBossNoContextTrash)
            self:AddBoss("_TrashMob_")
        end
        local rollSessionId
        -- Resolve award source: pending award -> master-looter manual -> current roll type.
        if not rollType then
            local lootService = getLootService()
            local p = lootService and lootService:ConsumePendingAward(itemLink, player, PENDING_AWARD_TTL_SECONDS)
            if p then
                rollType = p.rollType
                rollValue = p.rollValue
                rollSessionId = p.rollSessionId and tostring(p.rollSessionId) or nil
            elseif self:IsMasterLooter() and not lootState.fromInventory then
                rollType = rollTypes.MANUAL
                rollValue = 0

                -- Debug marker for manual-tagged loot.
                addon:debug(Diag.D.LogLootTaggedManual, tostring(itemLink), tostring(player), tostring(lootState.currentRollType))
            else
                rollType = lootState.currentRollType
            end
        end
        if not rollSessionId then
            rollSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end

        if not rollValue then
            local rollsService = getRollsService()
            rollValue = rollsService and rollsService:HighestRoll() or 0
        end

        local raid = Core.EnsureRaidById(Core.GetCurrentRaid())
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local looterNid = module:GetPlayerID(player, Core.GetCurrentRaid())
        if looterNid == 0 then
            module:AddPlayer({
                name = player,
                rank = 0,
                subgroup = 1,
                class = "UNKNOWN",
                join = Time.GetCurrentTime(),
                leave = nil,
                count = 0,
            }, Core.GetCurrentRaid())
            looterNid = module:GetPlayerID(player, Core.GetCurrentRaid())
        end

        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local lootInfo = {
            itemId = itemId,
            itemName = itemName,
            itemString = itemString,
            itemLink = itemLink,
            itemRarity = itemRarity,
            itemTexture = itemTexture,
            itemCount = itemCount,
            looterNid = (looterNid > 0) and looterNid or nil,
            rollType = rollType,
            rollValue = rollValue,
            rollSessionId = rollSessionId,
            lootNid = lootNid,
            bossNid = tonumber(Core.GetLastBoss()) or 0,
            time = Time.GetCurrentTime(),
        }

        -- LootCounter (MS only): increment the winner's count when the loot is actually awarded.
        -- This runs off the authoritative LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event.
        if tonumber(rollType) == rollTypes.MAINSPEC then
            module:AddPlayerCount(player, itemCount, Core.GetCurrentRaid())
        end

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, Core.GetCurrentRaid(), lootInfo)
        addon:debug(Diag.D.LogLootLogged:format(tonumber(Core.GetCurrentRaid()) or -1, tostring(itemId), tostring(lootInfo.bossNid), tostring(player)))
    end

    -- Creates a local raid loot entry for inventory-trade awards when no reliable loot context exists.
    function module:LogTradeOnlyLoot(itemLink, looter, rollType, rollValue, itemCount, source, raidNum, bossNid, rollSessionId)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not itemLink or not looter or looter == "" then
            return 0
        end
        looter = Strings.NormalizeName(looter, true) or looter

        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end
        Core.EnsureRaidSchema(raid)

        local looterNid = module:GetPlayerID(looter, raidNum)
        if looterNid == 0 then
            module:AddPlayer({
                name = looter,
                rank = 0,
                subgroup = 1,
                class = "UNKNOWN",
                join = Time.GetCurrentTime(),
                leave = nil,
                count = 0,
            }, raidNum)
            looterNid = module:GetPlayerID(looter, raidNum)
        end

        local count = tonumber(itemCount) or 1
        if count < 1 then
            count = 1
        end

        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        itemId = tonumber(itemId)
        if not itemName then
            itemName = strmatch(itemLink, "%[(.-)%]") or tostring(itemLink)
        end

        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local lootInfo = {
            itemId = itemId,
            itemName = itemName,
            itemString = itemString,
            itemLink = itemLink,
            itemRarity = itemRarity,
            itemTexture = itemTexture,
            itemCount = count,
            looterNid = (looterNid > 0) and looterNid or nil,
            rollType = tonumber(rollType),
            rollValue = tonumber(rollValue) or 0,
            rollSessionId = rollSessionId and tostring(rollSessionId) or nil,
            lootNid = lootNid,
            bossNid = tonumber(bossNid) or tonumber(Core.GetLastBoss()) or 0,
            time = Time.GetCurrentTime(),
            source = source or "TRADE_ONLY",
        }

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, raidNum, lootInfo)
        addon:debug(Diag.D.LogLootTradeOnlyLogged:format(tonumber(raidNum) or -1, tostring(itemId), tostring(lootNid), tostring(looter), count, tostring(lootInfo.source)))
        return lootNid
    end

    -- Player count API.

    function module:GetPlayerCountByNid(playerNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end
        Core.EnsureRaidSchema(raid)

        local player = findRaidPlayerByNid(raid, playerNid)
        if not player then
            return 0
        end
        return tonumber(player.count) or 0
    end

    function module:SetPlayerCountByNid(playerNid, value, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local player = findRaidPlayerByNid(raid, playerNid)
        if not player then
            return
        end

        value = tonumber(value) or 0
        -- Hard clamp: counts are always non-negative.
        if value < 0 then
            value = 0
        end

        local old = tonumber(player.count) or 0
        player.count = value

        if old ~= value then
            Bus.TriggerEvent(InternalEvents.PlayerCountChanged, player.name, value, old, raidNum)
        end
    end

    function module:AddPlayerCountByNid(playerNid, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        local current = module:GetPlayerCountByNid(playerNid, raidNum) or 0
        local nextVal = current + delta
        if nextVal < 0 then
            nextVal = 0
        end

        module:SetPlayerCountByNid(playerNid, nextVal, raidNum)
    end

    -- Adds (or subtracts) from the per-raid player count.
    -- Used by LootCounter UI and MS auto-counting.
    -- Clamps to 0 (never negative).
    function module:AddPlayerCount(name, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not name then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        -- Normalize/resolve name if possible.
        local ok, fixed = module:CheckPlayer(name, raidNum)
        if ok and fixed then
            name = fixed
        end

        -- Ensure the player exists in the raid log.
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            module:AddPlayer({
                name = name,
                rank = 0,
                subgroup = 1,
                class = "UNKNOWN",
                join = Time.GetCurrentTime(),
                leave = nil,
                count = 0,
            }, raidNum)
            playerNid = module:GetPlayerID(name, raidNum)
        end

        if playerNid == 0 then
            return
        end

        module:AddPlayerCountByNid(playerNid, delta, raidNum)
    end

    function module:GetPlayerCount(name, raidNum)
        if not name then
            return 0
        end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            return 0
        end
        return module:GetPlayerCountByNid(playerNid, raidNum)
    end

    function module:SetPlayerCount(name, value, raidNum)
        if not name then
            return
        end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            return
        end
        module:SetPlayerCountByNid(playerNid, value, raidNum)
    end

    function module:IncrementPlayerCount(name, raidNum)
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            addon:error(L.ErrCannotFindPlayer:format(name))
            return
        end

        local c = module:GetPlayerCountByNid(playerNid, raidNum)
        module:SetPlayerCountByNid(playerNid, c + 1, raidNum)
    end

    function module:DecrementPlayerCount(name, raidNum)
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            addon:error(L.ErrCannotFindPlayer:format(name))
            return
        end

        local c = module:GetPlayerCountByNid(playerNid, raidNum)
        if c <= 0 then
            -- Already at floor; keep it at 0 without spamming errors.
            module:SetPlayerCountByNid(playerNid, 0, raidNum)
            return
        end
        module:SetPlayerCountByNid(playerNid, c - 1, raidNum)
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

    -- Returns the number of members in the raid.
    function module:GetNumRaid()
        return numRaid
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

    -- Retrieves the position of a specific loot item within the raid's loot table.
    function module:GetLootID(itemID, raidNum, holderName)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        itemID = tonumber(itemID)
        if not itemID then
            return 0
        end

        local bossNid = tonumber(Core.GetLastBoss()) or 0
        local loot = raid.loot or {}

        for i = #loot, 1, -1 do
            local v = loot[i]
            if v and tonumber(v.itemId) == itemID then
                local winnerName = resolveLootLooterName(raid, v)
                if not holderName or holderName == "" or winnerName == holderName then
                    if bossNid <= 0 or tonumber(v.bossNid) == bossNid then
                        return tonumber(v.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    function module:GetHeldLootNid(itemLink, raidNum, holderName, bossNid)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or not itemLink then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        local queryBossNid = tonumber(bossNid) or 0
        local _, _, queryItemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local _, _, _, _, queryItemId = string.find(itemLink, ITEM_LINK_PATTERN)
        queryItemId = tonumber(queryItemId)

        local loot = raid.loot or {}
        for i = #loot, 1, -1 do
            local entry = loot[i]
            if entry and tonumber(entry.rollType) == rollTypes.HOLD then
                local winnerName = resolveLootLooterName(raid, entry)
                if (not holderName or holderName == "" or winnerName == holderName) and (queryBossNid <= 0 or tonumber(entry.bossNid) == queryBossNid) then
                    local sameItem = false
                    if queryItemString and entry.itemString and entry.itemString == queryItemString then
                        sameItem = true
                    elseif queryItemId and tonumber(entry.itemId) == queryItemId then
                        sameItem = true
                    elseif entry.itemLink and entry.itemLink == itemLink then
                        sameItem = true
                    end
                    if sameItem then
                        return tonumber(entry.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    function module:GetLootNidByRollSessionId(rollSessionId, raidNum, holderName, bossNid)
        local sessionId = rollSessionId and tostring(rollSessionId) or nil
        if not sessionId or sessionId == "" then
            return 0
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        local queryBossNid = tonumber(bossNid) or 0
        local loot = raid.loot or {}
        for i = #loot, 1, -1 do
            local entry = loot[i]
            if entry and tostring(entry.rollSessionId or "") == sessionId then
                local winnerName = resolveLootLooterName(raid, entry)
                if (not holderName or holderName == "" or winnerName == holderName) and (queryBossNid <= 0 or tonumber(entry.bossNid) == queryBossNid) then
                    return tonumber(entry.lootNid) or 0
                end
            end
        end
        return 0
    end

    -- Retrieves all boss kills for a given raid.
    function module:GetBosses(raidNum, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or not raid.bossKills then
            return {}
        end

        Core.EnsureRaidSchema(raid)

        local bosses = out or {}
        if out then
            twipe(bosses)
        end

        for i = 1, #raid.bossKills do
            local boss = raid.bossKills[i]
            bosses[#bosses + 1] = {
                id = tonumber(boss.bossNid), -- stable selection id
                seq = i, -- display order
                name = boss.name,
                time = boss.time,
                mode = boss.mode or ((boss.difficulty == 3 or boss.difficulty == 4) and "h" or "n"),
            }
        end

        return bosses
    end

    -- Player functions.

    -- Returns players from the raid log. Can be filtered by boss kill.
    function module:GetPlayers(raidNum, bossNid, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return {}
        end

        Core.EnsureRaidSchema(raid)

        local raidPlayers = raid.players or {}

        bossNid = tonumber(bossNid) or 0
        if bossNid > 0 then
            local bossKill = module:GetBossByNid(bossNid, raidNum)
            if bossKill and bossKill.players then
                local players = out or {}
                if out then
                    twipe(players)
                end
                local bossPlayers = {}
                for i = 1, #bossKill.players do
                    local playerNid = tonumber(bossKill.players[i])
                    if playerNid and playerNid > 0 then
                        bossPlayers[playerNid] = true
                    end
                end
                for _, p in ipairs(raidPlayers) do
                    local playerNid = tonumber(p and p.playerNid)
                    if playerNid and bossPlayers[playerNid] then
                        tinsert(players, p)
                    end
                end
                -- Caller releases when using a pooled table.
                return players
            end
        end

        return raidPlayers
    end

    -- Returns LootCounter rows from canonical raid data (unique by player name).
    function module:GetLootCounterRows(raidNum, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        local rows = out or {}
        if out then
            twipe(rows)
        end
        if not raid or not raid.players then
            return rows
        end

        Core.EnsureRaidSchema(raid)

        local seenByName = {}
        for i = #raid.players, 1, -1 do
            local p = raid.players[i]
            if p and p.name and not seenByName[p.name] then
                seenByName[p.name] = true
                rows[#rows + 1] = {
                    playerNid = tonumber(p.playerNid),
                    name = p.name,
                    class = p.class,
                    count = tonumber(p.count) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        return rows
    end

    -- Checks if a player is in the raid log.
    function module:CheckPlayer(name, raidNum)
        local found = false
        local players = module:GetPlayers(raidNum)
        if players ~= nil then
            name = Strings.NormalizeName(name)
            for _, p in ipairs(players) do
                if name == p.name then
                    found = true
                    break
                elseif strlen(name) >= 5 and p.name:startsWith(name) then
                    name = p.name
                    found = true
                    break
                end
            end
        end
        return found, name
    end

    -- Returns the player's stable ID (playerNid) from the raid log.
    function module:GetPlayerID(name, raidNum)
        local playerNid = 0
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        if raid then
            name = Strings.NormalizeName(name or Core.GetPlayerName(), true)
            local players = raid.players or {}
            for i = #players, 1, -1 do
                local p = players[i]
                if p and p.name == name then
                    playerNid = tonumber(p.playerNid) or 0
                    break
                end
            end
        end
        return playerNid
    end

    -- Gets a player's name by stable ID (playerNid).
    function module:GetPlayerName(id, raidNum)
        local name
        raidNum = raidNum or (addon.State and addon.State.selectedRaid) or Core.GetCurrentRaid()
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        if raid then
            local qid = tonumber(id) or id
            local players = raid.players or {}
            for i = 1, #players do
                local p = players[i]
                local pid = p and (tonumber(p.playerNid) or p.playerNid)
                if pid == qid then
                    name = p.name
                    break
                end
            end
        end
        return name
    end

    -- Returns a table of items looted by the selected player.
    function module:GetPlayerLoot(name, raidNum, bossNid)
        local items = {}
        local loot = module:GetLoot(raidNum, bossNid)
        local playerNid
        if type(name) == "number" then
            playerNid = tonumber(name)
        else
            local resolvedName = Strings.NormalizeName(name, true)
            playerNid = module:GetPlayerID(resolvedName, raidNum)
        end
        if not playerNid or playerNid <= 0 then
            return items
        end
        for _, v in ipairs(loot) do
            if tonumber(v.looterNid) == playerNid then
                tinsert(items, v)
            end
        end
        return items
    end

    -- Gets a player's rank.
    function module:GetPlayerRank(name, raidNum)
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        local players = raid and raid.players or {}
        local rank = 0
        name = name or Core.GetPlayerName() or UnitName("player")
        if #players == 0 then
            if addon.IsInGroup() then
                local unit = module:GetUnitID(name)
                if unit and unit ~= "none" then
                    rank = Core.GetUnitRank(unit) or 0
                end
            end
        else
            for _, p in ipairs(players) do
                if p.name == name then
                    rank = p.rank or 0
                    break
                end
            end
        end
        return rank
    end

    -- Gets a player's class from the saved players database.
    function module:GetPlayerClass(name)
        local class = "UNKNOWN"
        local realm = Core.GetRealmName()
        local resolvedName = name or Core.GetPlayerName()
        if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
            class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
        end
        return class
    end

    -- Gets a player's unit ID (e.g., "raid1").
    function module:GetUnitID(name)
        if not addon.IsInGroup() or not name then
            return "none"
        end

        name = Strings.NormalizeName(name)
        local cachedUnit = liveUnitsByName[name]
        if cachedUnit then
            if UnitExists(cachedUnit) and UnitName(cachedUnit) == name then
                return cachedUnit
            end
            liveUnitsByName[name] = nil
            if liveNamesByUnit[cachedUnit] == name then
                liveNamesByUnit[cachedUnit] = nil
            end
        end

        for unit in addon.UnitIterator(true) do
            local unitName = UnitName(unit)
            if unitName then
                unitName = Strings.NormalizeName(unitName)
                liveUnitsByName[unitName] = unit
                liveNamesByUnit[unit] = unitName
                if unitName == name then
                    return unit
                end
            end
        end
        return "none"
    end

    -- Raid and loot status checks.

    -- Checks if the group is using the Master Looter system.
    function module:IsMasterLoot()
        local method = select(1, getLootMethod())
        return (method == "master")
    end

    -- Checks if the player is the Master Looter.
    function module:IsMasterLooter()
        local method, partyMaster, raidMaster = getLootMethod()
        if method ~= "master" then
            return false
        end
        if partyMaster then
            if partyMaster == 0 or unitIsUnit("party" .. tostring(partyMaster), "player") then
                return true
            end
        end
        if raidMaster then
            if raidMaster == 0 or unitIsUnit("raid" .. tostring(raidMaster), "player") then
                return true
            end
        end
        return false
    end

    -- Clears all raid target icons.
    function module:ClearRaidIcons()
        local players = module:GetPlayers()
        for i = 1, #players do
            SetRaidTarget("raid" .. tostring(i), 0)
        end
    end
end
