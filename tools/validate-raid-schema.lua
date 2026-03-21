-- Offline raid schema validator for KRT_Raids-like tables.
-- Usage:
--   lua tools/validate-raid-schema.lua
--   lua tools/validate-raid-schema.lua path\\to\\raids_dump.lua
--
-- Optional input file behavior:
-- - If the chunk returns a table, that value is used as raids array.
-- - Otherwise, if it sets global KRT_Raids, that global is used.

local tonumber, tostring, type = tonumber, tostring, type
local pairs = pairs

local function toNumber(value, fallback)
    local num = tonumber(value)
    if num == nil then
        return fallback
    end
    return num
end

local function ensureTableField(record, key)
    if type(record[key]) ~= "table" then
        record[key] = {}
    end
end

local function normalizeRaidFallback(raid, currentSchemaVersion)
    if type(raid) ~= "table" then
        return nil
    end

    local schemaVersion = toNumber(raid.schemaVersion, 0)
    if schemaVersion < 1 then
        schemaVersion = 1
    end
    if schemaVersion > currentSchemaVersion then
        schemaVersion = currentSchemaVersion
    end
    raid.schemaVersion = schemaVersion

    ensureTableField(raid, "players")
    ensureTableField(raid, "bossKills")
    ensureTableField(raid, "loot")
    ensureTableField(raid, "changes")

    local usedPlayerNids = {}
    local nextPlayerNid = toNumber(raid.nextPlayerNid, 1)
    if nextPlayerNid < 1 then
        nextPlayerNid = 1
    end

    local function allocatePlayerNid(preferred)
        local playerNid = toNumber(preferred, nil)
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

    for i = 1, #raid.players do
        local player = raid.players[i]
        if type(player) == "table" then
            player.playerNid = allocatePlayerNid(player.playerNid)
            local count = toNumber(player.count, 0)
            if count < 0 then
                count = 0
            end
            player.count = count
        end
    end

    local usedBossNids = {}
    local nextBossNid = toNumber(raid.nextBossNid, 1)
    if nextBossNid < 1 then
        nextBossNid = 1
    end

    local function allocateBossNid(preferred)
        local bossNid = toNumber(preferred, nil)
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

    for i = 1, #raid.bossKills do
        local boss = raid.bossKills[i]
        if type(boss) == "table" then
            boss.bossNid = allocateBossNid(boss.bossNid)
        end
    end

    local usedLootNids = {}
    local nextLootNid = toNumber(raid.nextLootNid, 1)
    if nextLootNid < 1 then
        nextLootNid = 1
    end

    local function allocateLootNid(preferred)
        local lootNid = toNumber(preferred, nil)
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

    for i = 1, #raid.loot do
        local loot = raid.loot[i]
        if type(loot) == "table" then
            loot.lootNid = allocateLootNid(loot.lootNid)
        end
    end

    raid.nextPlayerNid = nextPlayerNid
    raid.nextBossNid = nextBossNid
    raid.nextLootNid = nextLootNid

    return raid
end

local function normalizeRaid(raid, currentSchemaVersion)
    local addonRoot = rawget(_G, "KRT")
    if type(addonRoot) == "table" then
        local services = addonRoot.Services
        local migrations = services and services.RaidMigrations or nil
        if migrations and type(migrations.ApplyRaidMigrations) == "function" then
            migrations:ApplyRaidMigrations(raid, currentSchemaVersion)
        end

        local raidStore = services and services.RaidStore or nil
        if raidStore and type(raidStore.NormalizeRaidRecord) == "function" then
            local normalized = raidStore:NormalizeRaidRecord(raid)
            if normalized then
                return normalized
            end
        end
    end

    return normalizeRaidFallback(raid, currentSchemaVersion)
end

local function validateRaid(raid, index, currentSchemaVersion)
    local result = { ok = 0, warn = 0, err = 0, messages = {} }

    local function add(level, msg)
        result.messages[#result.messages + 1] = level .. " raid[" .. tostring(index) .. "]: " .. msg
        if level == "E" then
            result.err = result.err + 1
        elseif level == "W" then
            result.warn = result.warn + 1
        else
            result.ok = result.ok + 1
        end
    end

    if type(raid) ~= "table" then
        add("E", "record is not a table")
        return result
    end

    raid = normalizeRaid(raid, currentSchemaVersion)
    if not raid then
        add("E", "normalization failed")
        return result
    end

    local schemaVersion = toNumber(raid.schemaVersion, nil)
    if not schemaVersion then
        add("E", "schemaVersion missing")
    elseif schemaVersion > currentSchemaVersion then
        add("E", "schemaVersion is newer than current")
    else
        add("I", "schemaVersion=" .. tostring(schemaVersion))
    end

    local maxPlayerNid = 0
    local players = raid.players or {}
    for i = 1, #players do
        local player = players[i]
        if type(player) == "table" then
            local playerNid = toNumber(player.playerNid, 0)
            if playerNid > maxPlayerNid then
                maxPlayerNid = playerNid
            end
            local count = toNumber(player.count, nil)
            if count == nil then
                add("E", "players[" .. i .. "].count is not a number")
            elseif count < 0 then
                add("E", "players[" .. i .. "].count is negative")
            end
        end
    end

    local maxBossNid = 0
    local bossByNid = {}
    local hasTrashBoss = false
    local bosses = raid.bossKills or {}
    for i = 1, #bosses do
        local boss = bosses[i]
        if type(boss) == "table" then
            local bossNid = toNumber(boss.bossNid, 0)
            if bossNid > maxBossNid then
                maxBossNid = bossNid
            end
            if bossNid > 0 then
                bossByNid[bossNid] = true
            end
            if boss.name == "_TrashMob_" then
                hasTrashBoss = true
            end
        end
    end

    local maxLootNid = 0
    local lootRows = raid.loot or {}
    for i = 1, #lootRows do
        local loot = lootRows[i]
        if type(loot) == "table" then
            local lootNid = toNumber(loot.lootNid, 0)
            if lootNid > maxLootNid then
                maxLootNid = lootNid
            end

            local lootBossNid = toNumber(loot.bossNid, 0)
            if lootBossNid > 0 and not bossByNid[lootBossNid] then
                add("E", "loot[" .. i .. "].bossNid points to a missing boss")
            elseif lootBossNid <= 0 and not hasTrashBoss then
                add("W", "loot[" .. i .. "] has no valid bossNid and no _TrashMob_ boss exists")
            end
        end
    end

    local nextPlayerNid = toNumber(raid.nextPlayerNid, 0)
    local nextBossNid = toNumber(raid.nextBossNid, 0)
    local nextLootNid = toNumber(raid.nextLootNid, 0)

    if nextPlayerNid < (maxPlayerNid + 1) then
        add("E", "nextPlayerNid is lower than max playerNid + 1")
    else
        add("I", "nextPlayerNid coherent")
    end

    if nextBossNid < (maxBossNid + 1) then
        add("E", "nextBossNid is lower than max bossNid + 1")
    else
        add("I", "nextBossNid coherent")
    end

    if nextLootNid < (maxLootNid + 1) then
        add("E", "nextLootNid is lower than max lootNid + 1")
    else
        add("I", "nextLootNid coherent")
    end

    for key in pairs(raid) do
        if type(key) == "string" and key:sub(1, 1) == "_" and key ~= "_runtime" then
            add("E", "runtime key found outside _runtime: " .. key)
        end
    end

    if raid._runtime ~= nil and type(raid._runtime) ~= "table" then
        add("E", "_runtime is not a table")
    end

    return result
end

local function loadRaidsFromPath(path)
    if not path or path == "" then
        return nil, "missing input path"
    end

    local chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, "cannot load input file: " .. tostring(loadErr)
    end

    local ok, ret = pcall(chunk)
    if not ok then
        return nil, "input execution failed: " .. tostring(ret)
    end

    if type(ret) == "table" then
        return ret
    end
    if type(_G.KRT_Raids) == "table" then
        return _G.KRT_Raids
    end

    return nil, "input did not return a raids table and did not define KRT_Raids"
end

local function run()
    local currentSchemaVersion = 3
    local addonRoot = rawget(_G, "KRT")
    if type(addonRoot) == "table" and type(addonRoot.Core) == "table" and type(addonRoot.Core.GetRaidSchemaVersion) == "function" then
        currentSchemaVersion = toNumber(addonRoot.Core.GetRaidSchemaVersion(), 1)
    end

    local inputPath = arg and arg[1] or nil
    local raids
    local err

    if inputPath and inputPath ~= "" then
        raids, err = loadRaidsFromPath(inputPath)
        if not raids then
            print("[E] " .. tostring(err))
            return 1
        end
    else
        raids = _G.KRT_Raids
    end

    if type(raids) ~= "table" then
        print("[E] KRT_Raids is not available. Provide an input path.")
        return 1
    end

    local okCount, warnCount, errCount = 0, 0, 0
    for i = 1, #raids do
        local result = validateRaid(raids[i], i, currentSchemaVersion)
        okCount = okCount + (result.ok or 0)
        warnCount = warnCount + (result.warn or 0)
        errCount = errCount + (result.err or 0)
        for j = 1, #result.messages do
            print(result.messages[j])
        end
    end

    print(("Summary: raids=%d ok=%d warn=%d err=%d"):format(#raids, okCount, warnCount, errCount))
    if errCount > 0 then
        return 2
    end
    return 0
end

local exitCode = run()
if exitCode ~= 0 then
    os.exit(exitCode)
end
