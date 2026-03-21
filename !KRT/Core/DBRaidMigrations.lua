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

    local function normalizeName(name)
        if Strings and Strings.NormalizeName then
            return Strings.NormalizeName(name, true)
        end
        if name == nil then
            return nil
        end
        local text = tostring(name)
        if text == "" then
            return nil
        end
        return text
    end

    local function normalizeTextOrNil(value)
        if value == nil then
            return nil
        end
        local text = nil
        if Strings and Strings.TrimText then
            text = Strings.TrimText(value, true)
        else
            text = tostring(value)
        end
        if type(text) ~= "string" or text == "" then
            return nil
        end
        return text
    end

    local function normalizePositiveNumberOrNil(value)
        local num = tonumber(value)
        if not num or num <= 0 then
            return nil
        end
        return num
    end

    local function compactChangesMap(changes)
        local out = {}
        if type(changes) ~= "table" then
            return out
        end

        for rawName, rawSpec in pairs(changes) do
            local playerName = normalizeName(rawName)
            local spec = normalizeName(rawSpec)
            if playerName and spec then
                out[playerName] = spec
            end
        end

        return out
    end

    local function compactRaidForPersistence(raid)
        if type(raid) ~= "table" then
            return nil
        end

        ensureTableField(raid, "players", false)
        ensureTableField(raid, "bossKills", false)
        ensureTableField(raid, "loot", false)
        ensureTableField(raid, "changes", true)

        local players = raid.players
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local count = tonumber(player.count) or 0
                if count < 0 then
                    count = 0
                end
                player.count = count

                local rank = tonumber(player.rank) or 0
                player.rank = (rank > 0) and rank or nil

                local subgroup = tonumber(player.subgroup) or 1
                player.subgroup = (subgroup > 1) and subgroup or nil

                player.join = normalizePositiveNumberOrNil(player.join)
                player.leave = normalizePositiveNumberOrNil(player.leave)

                local playerName = normalizeName(player.name)
                if playerName then
                    player.name = playerName
                end

                local className = normalizeTextOrNil(player.class)
                player.class = className or "UNKNOWN"
            end
        end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local boss = bosses[i]
            if type(boss) == "table" then
                local difficulty = tonumber(boss.difficulty) or 0
                boss.difficulty = (difficulty > 0) and difficulty or nil

                local mode = normalizeNameLower(boss.mode)
                local derivedMode = nil
                if difficulty > 0 then
                    derivedMode = (difficulty == 3 or difficulty == 4) and "h" or "n"
                end
                if mode == "h" or mode == "n" then
                    boss.mode = (mode ~= derivedMode) and mode or nil
                else
                    boss.mode = nil
                end

                boss.time = normalizePositiveNumberOrNil(boss.time)
                boss.hash = normalizeTextOrNil(boss.hash)
                boss.attendanceMask = nil

                local attendees = {}
                local seen = {}
                local rawPlayers = boss.players
                if type(rawPlayers) == "table" then
                    for j = 1, #rawPlayers do
                        local playerNid = tonumber(rawPlayers[j])
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
                loot.itemId = normalizePositiveNumberOrNil(loot.itemId)
                loot.itemName = normalizeTextOrNil(loot.itemName)
                loot.itemString = normalizeTextOrNil(loot.itemString)
                loot.itemLink = normalizeTextOrNil(loot.itemLink)
                loot.itemTexture = normalizeTextOrNil(loot.itemTexture)
                loot.rollSessionId = normalizeTextOrNil(loot.rollSessionId)
                loot.source = normalizeTextOrNil(loot.source)

                local itemRarity = tonumber(loot.itemRarity) or 0
                loot.itemRarity = (itemRarity > 0) and itemRarity or nil

                local itemCount = tonumber(loot.itemCount) or 1
                if itemCount < 1 then
                    itemCount = 1
                end
                loot.itemCount = (itemCount > 1) and itemCount or nil

                local looterNid = tonumber(loot.looterNid)
                if looterNid and looterNid > 0 then
                    loot.looterNid = looterNid
                else
                    loot.looterNid = nil
                end
                loot.looter = nil

                local rollType = tonumber(loot.rollType) or 0
                loot.rollType = (rollType ~= 0) and rollType or nil

                local rollValue = tonumber(loot.rollValue) or 0
                loot.rollValue = (rollValue ~= 0) and rollValue or nil

                local bossNid = tonumber(loot.bossNid) or 0
                loot.bossNid = (bossNid > 0) and bossNid or nil

                loot.time = normalizePositiveNumberOrNil(loot.time)
            end
        end

        raid.changes = compactChangesMap(raid.changes)
        return raid
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

    function module:CompactRaidForPersistence(raid)
        return compactRaidForPersistence(raid)
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
                local looterNid = tonumber(loot.looterNid)
                if looterNid and looterNid > 0 then
                    loot.looterNid = looterNid
                else
                    loot.looterNid = nil
                end
                loot.looter = nil
            end
        end
    end

    -- v3 canonicalization and lean persistence:
    -- - compact default-only values from persisted rows
    -- - trim empty optional fields
    -- - canonicalize changes map keys/values
    MIGRATIONS[2] = function(raid)
        compactRaidForPersistence(raid)
    end
end
