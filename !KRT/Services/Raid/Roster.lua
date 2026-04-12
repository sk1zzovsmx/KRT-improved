-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag

local Core = feature.Core
local Events = feature.Events or addon.Events
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Time = feature.Time or addon.Time

local InternalEvents = Events.Internal

local tinsert, twipe = table.insert, table.wipe
local pairs, ipairs, type = pairs, ipairs, type
local strlen = string.len
local strmatch = string.match
local tostring, tonumber = tostring, tonumber
local getRaidRosterInfo = GetRaidRosterInfo
local UnitRace, UnitSex = UnitRace, UnitSex

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --
    local numRaid = 0
    local rosterVersion = 0
    local liveUnitsByName = {}
    local liveNamesByUnit = {}
    local pendingUnits = {}

    local UNKNOWN_OBJECT = _G.UNKNOWNOBJECT
    local UNKNOWN_BEING = _G.UNKNOWNBEING or _G.UKNOWNBEING
    local RETRY_DELAY_SECONDS = 1
    local RETRY_MAX_ATTEMPTS = 5
    local ROSTER_REFRESH_DELAY_SECONDS = 2

    -- ----- Private helpers ----- --
    local function resetLiveUnitCaches()
        twipe(liveUnitsByName)
        twipe(liveNamesByUnit)
    end

    local function cancelPendingUnitRetryTimer()
        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = nil
    end

    local function cancelScheduledRosterRefresh()
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
    end

    local function scheduleRosterRefresh()
        cancelScheduledRosterRefresh()
        module.updateRosterHandle = addon.NewTimer(ROSTER_REFRESH_DELAY_SECONDS, function()
            module.updateRosterHandle = nil
            module:UpdateRaidRoster()
        end)
    end

    local function resetPendingUnitRetry()
        cancelPendingUnitRetryTimer()
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

        cancelPendingUnitRetryTimer()
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

    local function isUnknownName(name)
        return (not name) or name == "" or name == UNKNOWN_OBJECT or name == UNKNOWN_BEING
    end
    module._IsUnknownNameInternal = isUnknownName

    -- ----- Public methods ----- --
    local function setNumRaidInternal(value)
        numRaid = tonumber(value) or 0
    end

    local function bumpRosterVersionInternal()
        rosterVersion = rosterVersion + 1
        return rosterVersion
    end

    local function resetRosterTrackingInternal()
        resetPendingUnitRetry()
        resetLiveUnitCaches()
    end

    local function cancelRosterRefreshInternal()
        cancelScheduledRosterRefresh()
    end

    local function scheduleRosterRefreshInternal()
        scheduleRosterRefresh()
    end

    local function ensureRealmPlayerMetaInternal(realm)
        return ensureRealmPlayerMeta(realm)
    end

    local function upsertPlayerMetaInternal(realmPlayers, name, unitID, level, race, raceL, class, classL)
        upsertPlayerMeta(realmPlayers, name, unitID, level, race, raceL, class, classL)
    end

    function module:GetRosterVersion()
        return rosterVersion
    end

    function module:GetNumRaid()
        return numRaid
    end

    local function publishRosterDeltaInternal(delta, raidNum)
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

    module._SetNumRaidInternal = setNumRaidInternal
    module._BumpRosterVersionInternal = bumpRosterVersionInternal
    module._ResetRosterTrackingInternal = resetRosterTrackingInternal
    module._CancelRosterRefreshInternal = cancelRosterRefreshInternal
    module._ScheduleRosterRefreshInternal = scheduleRosterRefreshInternal
    module._EnsureRealmPlayerMetaInternal = ensureRealmPlayerMetaInternal
    module._UpsertPlayerMetaInternal = upsertPlayerMetaInternal
    module._PublishRosterDelta = publishRosterDeltaInternal

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

    -- Updates the current raid roster, adding new players and marking those who left.
    -- Returns rosterChanged, delta where delta contains joined/updated/left/unresolved lists.
    function module:UpdateRaidRoster()
        if addon.IsInRaid() then
            local instanceName, instanceType, instanceDiff = GetInstanceInfo()
            if instanceType == "raid" and feature.L.RaidZones[instanceName] ~= nil then
                module:Check(instanceName, instanceDiff)
            end
        end

        if not Core.GetCurrentRaid() then
            resetPendingUnitRetry()
            resetLiveUnitCaches()
            return false
        end
        -- Cancel any pending roster update timer.
        cancelScheduledRosterRefresh()

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
                table.insert(items, v)
            end
        end
        return items
    end

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

    function module:GetPlayerClass(name)
        local class = "UNKNOWN"
        local realm = Core.GetRealmName()
        local resolvedName = name or Core.GetPlayerName()
        if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
            class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
        end
        return class
    end

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
end
