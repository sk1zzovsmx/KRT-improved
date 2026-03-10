-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core
local Time = feature.Time or addon.Time

local tinsert, tremove = table.insert, table.remove
local pairs, type = pairs, type
local tonumber, tostring = tonumber, tostring

addon.DBManager = addon.DBManager or {}
local DBManager = addon.DBManager
DBManager.Mock = DBManager.Mock or {}
local Mock = DBManager.Mock

-- ----- Private helpers ----- --
local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return out
end

local function normalizeInt(value, fallback)
    local out = tonumber(value)
    if not out then
        out = fallback or 0
    end
    return out
end

local function allocateNid(preferred, used, nextNid)
    local candidate = tonumber(preferred)
    if candidate and candidate > 0 and not used[candidate] then
        used[candidate] = true
        if candidate >= nextNid then
            nextNid = candidate + 1
        end
        return candidate, nextNid
    end

    while used[nextNid] do
        nextNid = nextNid + 1
    end
    local out = nextNid
    used[out] = true
    return out, nextNid + 1
end

local function currentSchemaVersion()
    local version = Core.GetRaidSchemaVersion and Core.GetRaidSchemaVersion() or 1
    version = tonumber(version) or 1
    if version < 1 then
        version = 1
    end
    return version
end

local function getMigrations()
    if Core.GetRaidMigrations then
        local migrations = Core.GetRaidMigrations()
        if migrations then
            return migrations
        end
    end
    local db = addon.DB
    return db and db.RaidMigrations or nil
end

local function normalizeRaidRecord(raid)
    if type(raid) ~= "table" then
        return nil
    end

    local version = currentSchemaVersion()
    local migrations = getMigrations()
    if migrations and migrations.ApplyRaidMigrations then
        migrations:ApplyRaidMigrations(raid, version)
    end

    raid.schemaVersion = normalizeInt(raid.schemaVersion, version)
    if raid.schemaVersion < 1 then
        raid.schemaVersion = version
    end

    raid.players = (type(raid.players) == "table") and raid.players or {}
    raid.bossKills = (type(raid.bossKills) == "table") and raid.bossKills or {}
    raid.loot = (type(raid.loot) == "table") and raid.loot or {}
    raid.changes = (type(raid.changes) == "table") and raid.changes or {}

    local usedPlayerNids = {}
    local nextPlayerNid = normalizeInt(raid.nextPlayerNid, 1)
    if nextPlayerNid < 1 then
        nextPlayerNid = 1
    end

    for i = 1, #raid.players do
        local player = raid.players[i]
        if type(player) == "table" then
            local nid
            nid, nextPlayerNid = allocateNid(player.playerNid, usedPlayerNids, nextPlayerNid)
            player.playerNid = nid

            local count = normalizeInt(player.count, 0)
            if count < 0 then
                count = 0
            end
            player.count = count
        end
    end

    local usedBossNids = {}
    local nextBossNid = normalizeInt(raid.nextBossNid, 1)
    if nextBossNid < 1 then
        nextBossNid = 1
    end

    for i = 1, #raid.bossKills do
        local boss = raid.bossKills[i]
        if type(boss) == "table" then
            local nid
            nid, nextBossNid = allocateNid(boss.bossNid, usedBossNids, nextBossNid)
            boss.bossNid = nid
        end
    end

    local usedLootNids = {}
    local nextLootNid = normalizeInt(raid.nextLootNid, 1)
    if nextLootNid < 1 then
        nextLootNid = 1
    end

    for i = 1, #raid.loot do
        local loot = raid.loot[i]
        if type(loot) == "table" then
            local nid
            nid, nextLootNid = allocateNid(loot.lootNid, usedLootNids, nextLootNid)
            loot.lootNid = nid
        end
    end

    raid.nextPlayerNid = nextPlayerNid
    raid.nextBossNid = nextBossNid
    raid.nextLootNid = nextLootNid
    raid.raidNid = tonumber(raid.raidNid)

    if type(raid._runtime) ~= "table" then
        raid._runtime = nil
    end

    return raid
end

-- ----- Public methods ----- --
function Mock.CreateInMemoryRaidStore(seedRaids)
    local state = {
        raids = (type(seedRaids) == "table") and deepCopy(seedRaids) or {},
        raidIdxByNid = {},
        nextRaidNid = 1,
    }

    local store = {}

    local function rebuildRaidIndex()
        local used = {}
        local raidIdxByNid = {}
        local nextRaidNid = 1

        for i = 1, #state.raids do
            local raid = normalizeRaidRecord(state.raids[i])
            if raid then
                local raidNid
                raidNid, nextRaidNid = allocateNid(raid.raidNid, used, nextRaidNid)
                raid.raidNid = raidNid
                raidIdxByNid[raidNid] = i
            end
        end

        state.raidIdxByNid = raidIdxByNid
        state.nextRaidNid = nextRaidNid
    end

    local function ensureRuntime(raid)
        local runtime = raid._runtime
        if type(runtime) ~= "table" then
            runtime = {}
            raid._runtime = runtime
        end

        runtime.playersByName = {}
        runtime.playerIdxByNid = {}
        runtime.bossIdxByNid = {}
        runtime.lootIdxByNid = {}
        runtime.bossByNid = {}
        runtime.lootByNid = {}

        for i = 1, #(raid.players or {}) do
            local player = raid.players[i]
            if type(player) == "table" then
                if player.name then
                    runtime.playersByName[player.name] = player
                end
                local playerNid = tonumber(player.playerNid)
                if playerNid then
                    runtime.playerIdxByNid[playerNid] = i
                end
            end
        end

        for i = 1, #(raid.bossKills or {}) do
            local boss = raid.bossKills[i]
            if type(boss) == "table" then
                local bossNid = tonumber(boss.bossNid)
                if bossNid then
                    runtime.bossIdxByNid[bossNid] = i
                    runtime.bossByNid[bossNid] = boss
                end
            end
        end

        for i = 1, #(raid.loot or {}) do
            local loot = raid.loot[i]
            if type(loot) == "table" then
                local lootNid = tonumber(loot.lootNid)
                if lootNid then
                    runtime.lootIdxByNid[lootNid] = i
                    runtime.lootByNid[lootNid] = loot
                end
            end
        end

        runtime.signature = tostring(#(raid.players or {})) .. "|" .. tostring(#(raid.bossKills or {}))
            .. "|" .. tostring(#(raid.loot or {}))

        return runtime
    end

    function store:GetAllRaids()
        rebuildRaidIndex()
        return state.raids
    end

    function store:GetRawRaids()
        return state.raids
    end

    function store:IsLegacyRuntimeKey(key)
        if key == nil then
            return false
        end
        return false
    end

    function store:GetRaidByIndex(index)
        local idx = tonumber(index)
        if not idx or idx < 1 then
            return nil, nil
        end
        rebuildRaidIndex()
        local raid = normalizeRaidRecord(state.raids[idx])
        if not raid then
            return nil, idx
        end
        return raid, idx
    end

    function store:GetRaidByNid(raidNid)
        local nid = tonumber(raidNid)
        if not nid then
            return nil, nil, nil
        end
        rebuildRaidIndex()
        local idx = state.raidIdxByNid[nid]
        if not idx then
            return nil, nil, nid
        end
        local raid = normalizeRaidRecord(state.raids[idx])
        if not raid then
            return nil, nil, nid
        end
        return raid, idx, nid
    end

    function store:GetRaidNidByIndex(index)
        local raid = self:GetRaidByIndex(index)
        return raid and tonumber(raid.raidNid) or nil
    end

    function store:GetRaidIndexByNid(raidNid)
        local _, idx = self:GetRaidByNid(raidNid)
        return idx
    end

    function store:NormalizeRaidRecord(raid)
        return normalizeRaidRecord(raid)
    end

    function store:BuildRuntimeIndexes(raid)
        raid = normalizeRaidRecord(raid)
        if not raid then
            return nil
        end
        return ensureRuntime(raid)
    end

    function store:EnsureRaidRuntime(raid)
        return self:BuildRuntimeIndexes(raid)
    end

    function store:StripRuntime(raid)
        if type(raid) ~= "table" then
            return
        end
        raid._runtime = nil
    end

    function store:StripAllRuntime()
        for i = 1, #state.raids do
            self:StripRuntime(state.raids[i])
        end
    end

    function store:CreateRaidRecord(args)
        args = args or {}
        rebuildRaidIndex()

        local startTime = args.startTime
        if startTime == nil then
            startTime = (Time and Time.GetCurrentTime and Time.GetCurrentTime()) or time()
        end

        local raid = {
            schemaVersion = currentSchemaVersion(),
            raidNid = state.nextRaidNid,
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

        state.nextRaidNid = state.nextRaidNid + 1
        return normalizeRaidRecord(raid)
    end

    function store:InsertRaid(raid)
        raid = normalizeRaidRecord(raid)
        if not raid then
            return nil, nil
        end

        rebuildRaidIndex()
        if not raid.raidNid or state.raidIdxByNid[raid.raidNid] then
            raid.raidNid = state.nextRaidNid
            state.nextRaidNid = state.nextRaidNid + 1
        end

        tinsert(state.raids, raid)
        rebuildRaidIndex()
        local idx = state.raidIdxByNid[raid.raidNid] or #state.raids
        return raid, idx
    end

    function store:CreateRaid(args)
        local raid = self:CreateRaidRecord(args)
        if not raid then
            return nil, nil
        end
        return self:InsertRaid(raid)
    end

    function store:DeleteRaid(raidNid)
        local raid, idx = self:GetRaidByNid(raidNid)
        if not (raid and idx) then
            return false, nil
        end
        tremove(state.raids, idx)
        rebuildRaidIndex()
        return true, idx
    end

    function store:SaveRaid(raid)
        raid = normalizeRaidRecord(raid)
        if not raid then
            return false, nil
        end
        return true, raid
    end

    function store:Reset(seed)
        state.raids = (type(seed) == "table") and deepCopy(seed) or {}
        state.raidIdxByNid = {}
        state.nextRaidNid = 1
        rebuildRaidIndex()
    end

    rebuildRaidIndex()
    return store
end

function DBManager.CreateInMemoryManager(seed)
    local seedData = (type(seed) == "table") and seed or {}
    local db = addon.DB or {}
    local raidStore = Mock.CreateInMemoryRaidStore(seedData.raids or seedData.Raids)
    local raidQueries = seedData.raidQueries or seedData.RaidQueries or db.RaidQueries or nil
    local raidMigrations = seedData.raidMigrations or seedData.RaidMigrations or db.RaidMigrations or nil
    local raidValidator = seedData.raidValidator or seedData.RaidValidator or db.RaidValidator or nil
    local syncer = seedData.syncer or seedData.Syncer or db.Syncer or nil

    local managerFactory = DBManager.CreateManager
    if type(managerFactory) == "function" then
        return managerFactory({
            raidStore = raidStore,
            raidQueries = raidQueries,
            raidMigrations = raidMigrations,
            raidValidator = raidValidator,
            syncer = syncer,
            charStore = seedData.charStore or seedData.CharStore,
            configStore = seedData.configStore or seedData.ConfigStore,
        })
    end

    local manager = {}
    function manager:GetRaidStore() return raidStore end
    function manager:GetRaidQueries() return raidQueries end
    function manager:GetRaidMigrations() return raidMigrations end
    function manager:GetRaidValidator() return raidValidator end
    function manager:GetSyncer() return syncer end
    function manager:GetCharStore() return seedData.charStore end
    function manager:GetConfigStore() return seedData.configStore end
    return manager
end
