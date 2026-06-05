-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.DB.RaidMigrations
-- events: none
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local DB = feature.DB
local Database = feature.Database
local Strings = feature.Strings

local isBossFightRecord = Database._IsBossFightRecord

-- Current-schema raid persistence helpers.
do
    DB.RaidMigrations = DB.RaidMigrations or {}
    local module = DB.RaidMigrations

    -- ----- Internal state ----- --
    local EMPTY_MIGRATIONS = {}

    -- ----- Private helpers ----- --
    local normalizeNameLower = function(value)
        return Strings.NormalizeLower(value, true)
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

    local function appendAttendanceSegment(entry, segment)
        if type(segment) ~= "table" then
            return
        end

        local startTime = tonumber(segment.startTime) or 0
        if startTime <= 0 then
            return
        end

        local out = {
            startTime = startTime,
        }

        local endTime = tonumber(segment.endTime) or 0
        if endTime > startTime then
            out.endTime = endTime
        end

        local subgroup = tonumber(segment.subgroup) or 1
        if subgroup > 1 then
            out.subgroup = subgroup
        end

        if segment.online == false then
            out.online = false
        end

        entry.segments[#entry.segments + 1] = out
    end

    local function compactAttendance(attendance)
        local out = {}
        if type(attendance) ~= "table" then
            return out
        end

        local seenPlayers = {}
        for i = 1, #attendance do
            local entry = attendance[i]
            local playerNid = tonumber(entry and entry.playerNid) or 0
            if playerNid > 0 and not seenPlayers[playerNid] then
                local normalizedEntry = {
                    playerNid = playerNid,
                    segments = {},
                }
                seenPlayers[playerNid] = true

                local segments = entry.segments
                if type(segments) == "table" then
                    for j = 1, #segments do
                        appendAttendanceSegment(normalizedEntry, segments[j])
                    end
                end

                if #normalizedEntry.segments > 0 then
                    out[#out + 1] = normalizedEntry
                end
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
        ensureTableField(raid, "attendance", false)

        local players = raid.players
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local countMS = tonumber(player.countMS) or 0
                if countMS < 0 then
                    countMS = 0
                end
                player.countMS = (countMS > 0) and countMS or nil
                player.count = nil

                local countOs = tonumber(player.countOs) or 0
                if countOs < 0 then
                    countOs = 0
                end
                player.countOs = (countOs > 0) and countOs or nil

                local countFree = tonumber(player.countFree) or 0
                if countFree < 0 then
                    countFree = 0
                end
                player.countFree = (countFree > 0) and countFree or nil

                local countSR = tonumber(player.countSR) or 0
                if countSR < 0 then
                    countSR = 0
                end
                player.countSR = (countSR > 0) and countSR or nil

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
                if isBossFightRecord(boss) then
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
        raid.attendance = compactAttendance(raid.attendance)
        return raid
    end

    -- ----- Public methods ----- --
    function module:GetCurrentVersion()
        local version = Database.GetRaidSchemaVersion() or 1
        version = tonumber(version) or 1
        if version < 1 then
            version = 1
        end
        return version
    end

    function module:CompactRaidForPersistence(raid)
        return compactRaidForPersistence(raid)
    end
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Database/DBRaidMigrations", { deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBSchema", "Modules/Strings" } })
    registry.SetLoaded("Database/DBRaidMigrations")
end
