-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core

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
end
