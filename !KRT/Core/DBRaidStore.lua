-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core
local Time = feature.Time or addon.Time
local Strings = feature.Strings or addon.Strings
local Diag = feature.Diag or {}

local tinsert, tremove = table.insert, table.remove
local pairs, type = pairs, type
local tostring, tonumber = tostring, tonumber
local tconcat = table.concat

-- Raid storage service.
do
    addon.DB = addon.DB or {}
    addon.DB.RaidStore = addon.DB.RaidStore or {}
    local module = addon.DB.RaidStore

    -- ----- Internal state ----- --
    local LEGACY_RUNTIME_KEYS = {
        _playersByName = true,
        _playerIdxByNid = true,
        _bossIdxByNid = true,
        _lootIdxByNid = true,
    }

    local storeState = addon.State.raidStore
    if type(storeState) ~= "table" then
        storeState = {}
        addon.State.raidStore = storeState
    end

    -- ----- Private helpers ----- --
    local function clearMap(map)
        if type(map) ~= "table" then
            return {}
        end
        for key in pairs(map) do
            map[key] = nil
        end
        return map
    end

    local function ensureRaidsTable()
        if type(KRT_Raids) ~= "table" then
            KRT_Raids = {}
        end
        return KRT_Raids
    end

    local function getSchemaVersion()
        local version = Core.GetRaidSchemaVersion and Core.GetRaidSchemaVersion() or 1
        version = tonumber(version) or 1
        if version < 1 then
            version = 1
        end
        return version
    end

    local function getMigrations()
        if Core.GetRaidMigrations then
            return Core.GetRaidMigrations()
        end
        return nil
    end

    local function removeLegacyRuntimeCaches(raid)
        for key in pairs(LEGACY_RUNTIME_KEYS) do
            raid[key] = nil
        end
    end

    local function isRuntimeIndexReady(runtime)
        return type(runtime) == "table"
            and type(runtime.playersByName) == "table"
            and type(runtime.playerIdxByNid) == "table"
            and type(runtime.bossIdxByNid) == "table"
            and type(runtime.bossByNid) == "table"
            and type(runtime.lootIdxByNid) == "table"
            and type(runtime.lootByNid) == "table"
    end

    local function normalizeChangeName(value)
        local out = nil
        if Strings and Strings.NormalizeName then
            out = Strings.NormalizeName(value)
        elseif value ~= nil then
            out = tostring(value)
        end
        if type(out) ~= "string" or out == "" then
            return nil
        end
        return out
    end

    local function normalizeChangeSpec(value)
        if value == nil then
            return nil
        end
        local out = nil
        if Strings and Strings.NormalizeName then
            out = Strings.NormalizeName(value)
        else
            out = tostring(value)
        end
        if type(out) ~= "string" or out == "" then
            return nil
        end
        return out
    end

    local function normalizeNameLower(value)
        if Strings and Strings.NormalizeLower then
            return Strings.NormalizeLower(value, true)
        end
        if type(value) ~= "string" then
            return nil
        end
        return string.lower(value)
    end

    local function isLegacyDiagnosticPhase(contextTag)
        return contextTag == "load" or contextTag == "save"
    end

    local function scanLegacyRaidPayload(raid)
        local legacyRuntimeKeys = {}
        for key in pairs(LEGACY_RUNTIME_KEYS) do
            if raid[key] ~= nil then
                legacyRuntimeKeys[#legacyRuntimeKeys + 1] = key
            end
        end

        local legacyAttendanceMaskCount = 0
        local bosses = (type(raid.bossKills) == "table") and raid.bossKills or nil
        if bosses then
            for i = 1, #bosses do
                local boss = bosses[i]
                if type(boss) == "table" and boss.attendanceMask ~= nil then
                    legacyAttendanceMaskCount = legacyAttendanceMaskCount + 1
                end
            end
        end

        local legacyLootLooterCount = 0
        local lootRows = (type(raid.loot) == "table") and raid.loot or nil
        if lootRows then
            for i = 1, #lootRows do
                local loot = lootRows[i]
                if type(loot) == "table" and loot.looter ~= nil then
                    legacyLootLooterCount = legacyLootLooterCount + 1
                end
            end
        end

        return {
            legacyRuntimeKeys = legacyRuntimeKeys,
            legacyAttendanceMaskCount = legacyAttendanceMaskCount,
            legacyLootLooterCount = legacyLootLooterCount,
        }
    end

    local function warnLegacyRaidPayload(contextTag, raid, raidIndex, legacy)
        local runtimeKeys = legacy.legacyRuntimeKeys or {}
        local runtimeKeysCount = #runtimeKeys
        local lootLooterCount = tonumber(legacy.legacyLootLooterCount) or 0
        local attendanceMaskCount = tonumber(legacy.legacyAttendanceMaskCount) or 0
        if runtimeKeysCount == 0 and lootLooterCount == 0 and attendanceMaskCount == 0 then
            return
        end

        local runtimeText = (runtimeKeysCount > 0) and tconcat(runtimeKeys, ";") or "-"
        local raidNid = tostring(tonumber(raid and raid.raidNid) or "?")
        local idxText = tostring(tonumber(raidIndex) or "?")
        local template = Diag.W and Diag.W.LogRaidLegacyFieldsDetected
        if type(template) == "string" then
            addon:warn(template:format(contextTag, raidNid, idxText, runtimeText, lootLooterCount, attendanceMaskCount))
            return
        end

        addon:warn(
            ("[RaidStore] Legacy fields detected phase=%s raidNid=%s idx=%s runtime=%s looter=%d mask=%d"):format(
                tostring(contextTag or "?"),
                raidNid,
                idxText,
                runtimeText,
                lootLooterCount,
                attendanceMaskCount
            )
        )
    end

    local function rebuildRaidNidIndex()
        local raids = ensureRaidsTable()
        local usedRaidNids = {}
        local raidIdxByNid = {}
        local nextRaidNid = 1

        local function allocateRaidNid(preferred)
            local raidNid = tonumber(preferred)
            if raidNid and raidNid > 0 and not usedRaidNids[raidNid] then
                usedRaidNids[raidNid] = true
                if raidNid >= nextRaidNid then
                    nextRaidNid = raidNid + 1
                end
                return raidNid
            end

            while usedRaidNids[nextRaidNid] do
                nextRaidNid = nextRaidNid + 1
            end

            local out = nextRaidNid
            usedRaidNids[out] = true
            nextRaidNid = out + 1
            return out
        end

        for i = 1, #raids do
            local raid = module:NormalizeRaidRecord(raids[i])
            if raid then
                local raidNid = allocateRaidNid(raid.raidNid)
                raid.raidNid = raidNid
                raidIdxByNid[raidNid] = i
            end
        end

        storeState.raidIdxByNid = raidIdxByNid
        storeState.nextRaidNid = nextRaidNid
    end

    local function getNextRaidNid(preferred)
        rebuildRaidNidIndex()

        local raidIdxByNid = storeState.raidIdxByNid or {}
        local raidNid = tonumber(preferred)
        if raidNid and raidNid > 0 and not raidIdxByNid[raidNid] then
            if raidNid >= (tonumber(storeState.nextRaidNid) or 1) then
                storeState.nextRaidNid = raidNid + 1
            end
            return raidNid
        end

        local nextRaidNid = tonumber(storeState.nextRaidNid) or 1
        if nextRaidNid < 1 then
            nextRaidNid = 1
        end
        while raidIdxByNid[nextRaidNid] do
            nextRaidNid = nextRaidNid + 1
        end
        storeState.nextRaidNid = nextRaidNid + 1
        return nextRaidNid
    end

    -- ----- Public methods ----- --
    function module:GetAllRaids()
        rebuildRaidNidIndex()
        return ensureRaidsTable()
    end

    function module:GetRawRaids()
        return ensureRaidsTable()
    end

    function module:IsLegacyRuntimeKey(key)
        return LEGACY_RUNTIME_KEYS[key] == true
    end

    function module:GetRaidByIndex(index)
        local idx = tonumber(index)
        if not idx or idx < 1 then
            return nil, nil
        end

        rebuildRaidNidIndex()
        local raids = ensureRaidsTable()
        local raid = raids[idx]
        if not raid then
            return nil, idx
        end
        return self:NormalizeRaidRecord(raid), idx
    end

    function module:GetRaidByNid(raidNid)
        local nid = tonumber(raidNid)
        if not nid then
            return nil, nil, nil
        end

        rebuildRaidNidIndex()
        local raidIdxByNid = storeState.raidIdxByNid or {}
        local idx = raidIdxByNid[nid]
        if not idx then
            return nil, nil, nid
        end

        local raids = ensureRaidsTable()
        local raid = raids[idx]
        if not raid then
            return nil, nil, nid
        end
        return self:NormalizeRaidRecord(raid), idx, nid
    end

    function module:GetRaidNidByIndex(index)
        local raid = self:GetRaidByIndex(index)
        return raid and tonumber(raid.raidNid) or nil
    end

    function module:GetRaidIndexByNid(raidNid)
        local _, idx = self:GetRaidByNid(raidNid)
        return idx
    end

    function module:GetRaidChanges(index)
        local raid, idx = self:GetRaidByIndex(index)
        if not raid then
            return nil, idx, nil
        end
        raid.changes = (type(raid.changes) == "table") and raid.changes or {}
        return raid.changes, idx, raid
    end

    function module:UpsertRaidChange(index, playerName, spec)
        local changes, idx = self:GetRaidChanges(index)
        if type(changes) ~= "table" then
            return false, nil, nil, idx
        end

        local normalizedName = normalizeChangeName(playerName)
        if not normalizedName then
            return false, nil, nil, idx
        end

        local normalizedSpec = normalizeChangeSpec(spec)
        changes[normalizedName] = normalizedSpec
        return true, normalizedName, normalizedSpec, idx
    end

    function module:DeleteRaidChange(index, playerName)
        local changes, idx = self:GetRaidChanges(index)
        if type(changes) ~= "table" then
            return false, false, idx
        end

        local normalizedName = normalizeChangeName(playerName)
        if not normalizedName then
            return false, false, idx
        end

        local existed = changes[normalizedName] ~= nil
        changes[normalizedName] = nil
        return true, existed, idx
    end

    function module:ClearRaidChanges(index)
        local changes, idx = self:GetRaidChanges(index)
        if type(changes) ~= "table" then
            return false, 0, idx
        end

        local removed = 0
        for name in pairs(changes) do
            changes[name] = nil
            removed = removed + 1
        end
        return true, removed, idx
    end

    function module:NormalizeRaidRecord(raid, contextTag, raidIndex)
        if type(raid) ~= "table" then
            return nil
        end

        if isLegacyDiagnosticPhase(contextTag) then
            local legacy = scanLegacyRaidPayload(raid)
            warnLegacyRaidPayload(contextTag, raid, raidIndex, legacy)
        end

        local schemaVersion = getSchemaVersion()
        local migrations = getMigrations()
        if migrations and migrations.ApplyRaidMigrations then
            migrations:ApplyRaidMigrations(raid, schemaVersion)
        else
            raid.schemaVersion = tonumber(raid.schemaVersion) or schemaVersion
        end

        raid.schemaVersion = tonumber(raid.schemaVersion) or schemaVersion
        if raid.schemaVersion < 1 then
            raid.schemaVersion = schemaVersion
        end

        raid.players = (type(raid.players) == "table") and raid.players or {}
        raid.bossKills = (type(raid.bossKills) == "table") and raid.bossKills or {}
        raid.loot = (type(raid.loot) == "table") and raid.loot or {}
        raid.changes = (type(raid.changes) == "table") and raid.changes or {}

        local usedPlayerNids = {}
        local nextPlayerNid = tonumber(raid.nextPlayerNid) or 1
        if nextPlayerNid < 1 then
            nextPlayerNid = 1
        end
        local assignedByRef = {}

        local function allocatePlayerNid(preferred)
            local playerNid = tonumber(preferred)
            if playerNid and playerNid > 0 and not usedPlayerNids[playerNid] then
                usedPlayerNids[playerNid] = true
                return playerNid
            end

            while usedPlayerNids[nextPlayerNid] do
                nextPlayerNid = nextPlayerNid + 1
            end
            local out = nextPlayerNid
            usedPlayerNids[out] = true
            nextPlayerNid = out + 1
            return out
        end

        local players = raid.players
        local playerNidByName = {}
        local validPlayerNids = {}
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local assigned = assignedByRef[player]
                if assigned then
                    player.playerNid = assigned
                else
                    local playerNid = allocatePlayerNid(player.playerNid)
                    player.playerNid = playerNid
                    assignedByRef[player] = playerNid
                end

                local count = tonumber(player.count) or 0
                if count < 0 then
                    count = 0
                end
                player.count = count

                local playerNid = tonumber(player.playerNid)
                if playerNid and playerNid > 0 then
                    validPlayerNids[playerNid] = true
                    local normalizedName = normalizeNameLower(player.name)
                    if normalizedName and playerNidByName[normalizedName] == nil then
                        playerNidByName[normalizedName] = playerNid
                    end
                end
            end
        end

        local usedBossNids = {}
        local nextBossNid = tonumber(raid.nextBossNid) or 1
        if nextBossNid < 1 then
            nextBossNid = 1
        end

        local function allocateBossNid(preferred)
            local bossNid = tonumber(preferred)
            if bossNid and bossNid > 0 and not usedBossNids[bossNid] then
                usedBossNids[bossNid] = true
                return bossNid
            end

            while usedBossNids[nextBossNid] do
                nextBossNid = nextBossNid + 1
            end
            local out = nextBossNid
            usedBossNids[out] = true
            nextBossNid = out + 1
            return out
        end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local boss = bosses[i]
            if type(boss) == "table" then
                boss.bossNid = allocateBossNid(boss.bossNid)

                local attendees = {}
                local seen = {}
                local rawPlayers = boss.players
                if type(rawPlayers) == "table" then
                    for j = 1, #rawPlayers do
                        local rawPlayer = rawPlayers[j]
                        local playerNid = tonumber(rawPlayer)
                        if not playerNid and type(rawPlayer) == "string" then
                            playerNid = playerNidByName[normalizeNameLower(rawPlayer)]
                        end
                        if playerNid and playerNid > 0 and validPlayerNids[playerNid] and not seen[playerNid] then
                            seen[playerNid] = true
                            attendees[#attendees + 1] = playerNid
                        end
                    end
                end
                if #attendees == 0 then
                    local killTime = tonumber(boss.time) or 0
                    for j = 1, #players do
                        local player = players[j]
                        local playerNid = player and tonumber(player.playerNid) or nil
                        if playerNid and validPlayerNids[playerNid] and not seen[playerNid] then
                            local include = true
                            if killTime > 0 then
                                local joinTime = tonumber(player.join)
                                if joinTime and joinTime > killTime then
                                    include = false
                                end
                                local leaveTime = tonumber(player.leave)
                                if leaveTime and leaveTime > 0 and leaveTime < killTime then
                                    include = false
                                end
                            end
                            if include then
                                seen[playerNid] = true
                                attendees[#attendees + 1] = playerNid
                            end
                        end
                    end
                end
                boss.players = attendees
                boss.attendanceMask = nil
            end
        end

        local usedLootNids = {}
        local nextLootNid = tonumber(raid.nextLootNid) or 1
        if nextLootNid < 1 then
            nextLootNid = 1
        end

        local function allocateLootNid(preferred)
            local lootNid = tonumber(preferred)
            if lootNid and lootNid > 0 and not usedLootNids[lootNid] then
                usedLootNids[lootNid] = true
                return lootNid
            end

            while usedLootNids[nextLootNid] do
                nextLootNid = nextLootNid + 1
            end
            local out = nextLootNid
            usedLootNids[out] = true
            nextLootNid = out + 1
            return out
        end

        local lootRows = raid.loot
        for i = 1, #lootRows do
            local loot = lootRows[i]
            if type(loot) == "table" then
                loot.lootNid = allocateLootNid(loot.lootNid)

                local looterNid = tonumber(loot.looterNid)
                if looterNid and looterNid > 0 and validPlayerNids[looterNid] then
                    loot.looterNid = looterNid
                else
                    loot.looterNid = nil
                end
                loot.looter = nil
            end
        end

        raid.nextPlayerNid = nextPlayerNid
        raid.nextBossNid = nextBossNid
        raid.nextLootNid = nextLootNid
        raid.raidNid = tonumber(raid.raidNid)

        if type(raid._runtime) ~= "table" then
            raid._runtime = nil
        end
        removeLegacyRuntimeCaches(raid)
        return raid
    end

    function module:BuildRuntimeIndexes(raid)
        raid = self:NormalizeRaidRecord(raid)
        if not raid then
            return nil
        end

        local runtime = raid._runtime
        if type(runtime) ~= "table" then
            runtime = {}
            raid._runtime = runtime
        end

        local playersByName = clearMap(runtime.playersByName)
        runtime.playersByName = playersByName

        local playerIdxByNid = clearMap(runtime.playerIdxByNid)
        runtime.playerIdxByNid = playerIdxByNid

        local bossIdxByNid = clearMap(runtime.bossIdxByNid)
        runtime.bossIdxByNid = bossIdxByNid

        local bossByNid = clearMap(runtime.bossByNid)
        runtime.bossByNid = bossByNid

        local lootIdxByNid = clearMap(runtime.lootIdxByNid)
        runtime.lootIdxByNid = lootIdxByNid

        local lootByNid = clearMap(runtime.lootByNid)
        runtime.lootByNid = lootByNid

        local players = raid.players or {}
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                if player.name then
                    playersByName[player.name] = player
                end
                local playerNid = tonumber(player.playerNid)
                if playerNid then
                    playerIdxByNid[playerNid] = i
                end
            end
        end

        local bosses = raid.bossKills or {}
        for i = 1, #bosses do
            local boss = bosses[i]
            if type(boss) == "table" then
                local bossNid = tonumber(boss.bossNid)
                if bossNid then
                    bossIdxByNid[bossNid] = i
                    bossByNid[bossNid] = boss
                end
            end
        end

        local lootRows = raid.loot or {}
        for i = 1, #lootRows do
            local loot = lootRows[i]
            if type(loot) == "table" then
                local lootNid = tonumber(loot.lootNid)
                if lootNid then
                    lootIdxByNid[lootNid] = i
                    lootByNid[lootNid] = loot
                end
            end
        end

        runtime.signature = tostring(#players)
            .. "|"
            .. tostring(#bosses)
            .. "|"
            .. tostring(#lootRows)
            .. "|"
            .. tostring(tonumber(raid.nextPlayerNid) or 1)
            .. "|"
            .. tostring(tonumber(raid.nextBossNid) or 1)
            .. "|"
            .. tostring(tonumber(raid.nextLootNid) or 1)

        return runtime
    end

    function module:EnsureRaidRuntime(raid)
        raid = self:NormalizeRaidRecord(raid)
        if not raid then
            return nil
        end

        local runtime = raid._runtime
        if isRuntimeIndexReady(runtime) then
            return runtime
        end
        return self:BuildRuntimeIndexes(raid)
    end

    function module:StripRuntime(raid)
        if type(raid) ~= "table" then
            return
        end
        removeLegacyRuntimeCaches(raid)
        raid._runtime = nil
    end

    function module:StripAllRuntime()
        local raids = ensureRaidsTable()
        for i = 1, #raids do
            self:StripRuntime(raids[i])
        end
    end

    function module:NormalizeAllRaids(contextTag)
        local raids = ensureRaidsTable()
        for i = 1, #raids do
            self:NormalizeRaidRecord(raids[i], contextTag, i)
        end
        rebuildRaidNidIndex()
        return raids
    end

    function module:PrepareRaidForSave(raid, raidIndex)
        raid = self:NormalizeRaidRecord(raid, "save", raidIndex)
        if not raid then
            return nil
        end

        self:StripRuntime(raid)

        local migrations = getMigrations()
        if migrations and migrations.CompactRaidForPersistence then
            migrations:CompactRaidForPersistence(raid)
        end

        return raid
    end

    function module:PrepareAllRaidsForSave()
        local raids = ensureRaidsTable()
        for i = 1, #raids do
            self:PrepareRaidForSave(raids[i], i)
        end
    end

    function module:CreateRaidRecord(args)
        args = args or {}

        local raidNid = getNextRaidNid(args.raidNid)
        local startTime = args.startTime
        if startTime == nil then
            startTime = (Time and Time.GetCurrentTime and Time.GetCurrentTime()) or time()
        end

        local raid = {
            schemaVersion = getSchemaVersion(),
            raidNid = raidNid,
            realm = args.realm,
            zone = args.zone,
            size = args.size,
            difficulty = args.difficulty,
            startTime = startTime,
            endTime = args.endTime,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
            nextBossNid = 1,
            nextLootNid = 1,
            nextPlayerNid = 1,
        }

        return self:NormalizeRaidRecord(raid)
    end

    function module:InsertRaid(raid)
        raid = self:NormalizeRaidRecord(raid)
        if not raid then
            return nil, nil
        end

        local raidNid = getNextRaidNid(raid.raidNid)
        raid.raidNid = raidNid

        local raids = ensureRaidsTable()
        tinsert(raids, raid)
        rebuildRaidNidIndex()

        local idx = (storeState.raidIdxByNid and storeState.raidIdxByNid[raidNid]) or #raids
        return raid, idx
    end

    function module:CreateRaid(args)
        local raid = self:CreateRaidRecord(args)
        if not raid then
            return nil, nil
        end
        return self:InsertRaid(raid)
    end

    function module:DeleteRaid(raidNid)
        local raid, idx = self:GetRaidByNid(raidNid)
        if not (raid and idx) then
            return false, nil
        end

        local raids = ensureRaidsTable()
        tremove(raids, idx)
        rebuildRaidNidIndex()
        return true, idx
    end

    function module:SaveRaid(raid)
        raid = self:NormalizeRaidRecord(raid, "save")
        if not raid then
            return false, nil
        end
        return true, raid
    end
end
