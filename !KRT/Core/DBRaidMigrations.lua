-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core
local Strings = feature.Strings or addon.Strings

-- Raid schema migrations service.
do
    addon.DB = addon.DB or {}
    addon.DB.RaidMigrations = addon.DB.RaidMigrations or {}
    local module = addon.DB.RaidMigrations

    -- ----- Internal state ----- --
    local MIGRATIONS = {}

    -- ----- Private helpers ----- --
    local function normalizeNonNegativeNumber(value, fallback)
        local num = tonumber(value) or fallback or 0
        if num < 0 then
            num = fallback or 0
        end
        return num
    end

    local function ensureTableField(raid, key, emptyAsMap)
        local value = raid[key]
        if type(value) ~= "table" then
            raid[key] = {}
            return
        end

        if emptyAsMap then
            return
        end
    end

    local function normalizeNameLower(name)
        if Strings and Strings.NormalizeLower then
            return Strings.NormalizeLower(name, true)
        end
        if type(name) ~= "string" then
            return nil
        end
        return string.lower(name)
    end


    -- ----- Public methods ----- --
    function module:GetMigrations()
        return MIGRATIONS
    end

    function module:GetCurrentVersion()
        local version = Core.GetRaidSchemaVersion and Core.GetRaidSchemaVersion() or 1
        version = tonumber(version) or 1
        if version < 1 then
            version = 1
        end
        return version
    end

    function module:ApplyRaidMigrations(raid, currentVersion)
        if type(raid) ~= "table" then
            return nil
        end

        local targetVersion = tonumber(currentVersion)
        if targetVersion == nil then
            targetVersion = self:GetCurrentVersion()
        end
        if targetVersion < 1 then
            targetVersion = 1
        end

        local version = tonumber(raid.schemaVersion) or 0
        if version < 0 then
            version = 0
        end

        while version < targetVersion do
            local migrateFn = MIGRATIONS[version]
            if type(migrateFn) == "function" then
                migrateFn(raid)
            end
            version = version + 1
            raid.schemaVersion = version
        end

        if version > targetVersion then
            raid.schemaVersion = targetVersion
        end

        return raid
    end

    MIGRATIONS[0] = function(raid)
        ensureTableField(raid, "players", false)
        ensureTableField(raid, "bossKills", false)
        ensureTableField(raid, "loot", false)
        ensureTableField(raid, "changes", true)

        raid.nextPlayerNid = normalizeNonNegativeNumber(raid.nextPlayerNid, 1)
        if raid.nextPlayerNid < 1 then
            raid.nextPlayerNid = 1
        end

        raid.nextBossNid = normalizeNonNegativeNumber(raid.nextBossNid, 1)
        if raid.nextBossNid < 1 then
            raid.nextBossNid = 1
        end

        raid.nextLootNid = normalizeNonNegativeNumber(raid.nextLootNid, 1)
        if raid.nextLootNid < 1 then
            raid.nextLootNid = 1
        end

        local players = raid.players
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local count = tonumber(player.count) or 0
                if count < 0 then
                    count = 0
                end
                player.count = count
            end
        end
    end

    -- v2 canonicalization:
    -- - raid.bossKills[].players stores playerNid numbers (not names)
    -- - raid.loot[].looterNid stores winner playerNid (legacy loot.looter removed)
    MIGRATIONS[1] = function(raid)
        ensureTableField(raid, "players", false)
        ensureTableField(raid, "bossKills", false)
        ensureTableField(raid, "loot", false)

        local playerNidByName = {}
        local players = raid.players
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local playerNid = tonumber(player.playerNid)
                local key = normalizeNameLower(player.name)
                if key and playerNid and playerNid > 0 and playerNidByName[key] == nil then
                    playerNidByName[key] = playerNid
                end
            end
        end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local boss = bosses[i]
            if type(boss) == "table" then
                local rawPlayers = boss.players
                local attendees = {}
                local seen = {}
                if type(rawPlayers) == "table" then
                    for j = 1, #rawPlayers do
                        local rawPlayer = rawPlayers[j]
                        local playerNid = tonumber(rawPlayer)
                        if not playerNid and type(rawPlayer) == "string" then
                            playerNid = playerNidByName[normalizeNameLower(rawPlayer)]
                        end
                        if playerNid and playerNid > 0 and not seen[playerNid] then
                            seen[playerNid] = true
                            attendees[#attendees + 1] = playerNid
                        end
                    end
                end
                boss.players = attendees
            end
        end

        local lootRows = raid.loot
        for i = 1, #lootRows do
            local loot = lootRows[i]
            if type(loot) == "table" then
                local looterNid = tonumber(loot.looterNid) or tonumber(loot.looter)
                if not looterNid and type(loot.looter) == "string" then
                    looterNid = playerNidByName[normalizeNameLower(loot.looter)]
                end
                if looterNid and looterNid > 0 then
                    loot.looterNid = looterNid
                else
                    loot.looterNid = nil
                end
                loot.looter = nil
            end
        end
    end
end
