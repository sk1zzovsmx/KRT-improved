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

    local normalizeNameLower = Strings.GetNormalizedNameLower

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

    local function appendAttendanceSegment(entry, startTime, endTime, subgroup, online)
        local resolvedStart = tonumber(startTime) or 0
        if resolvedStart <= 0 then
            return
        end

        local segment = {
            startTime = resolvedStart,
        }

        local resolvedEnd = tonumber(endTime) or 0
        if resolvedEnd > resolvedStart then
            segment.endTime = resolvedEnd
        end

        local resolvedSubgroup = tonumber(subgroup) or 1
        if resolvedSubgroup > 1 then
            segment.subgroup = resolvedSubgroup
        end

        if online == false then
            segment.online = false
        end

        entry.segments[#entry.segments + 1] = segment
    end

    local function buildAttendanceFromPlayers(players)
        local attendance = {}
        if type(players) ~= "table" then
            return attendance
        end

        for i = 1, #players do
            local player = players[i]
            local playerNid = type(player) == "table" and tonumber(player.playerNid) or nil
            local joinTime = type(player) == "table" and (tonumber(player.join) or 0) or 0
            if playerNid and playerNid > 0 and joinTime > 0 then
                local entry = {
                    playerNid = playerNid,
                    segments = {},
                }
                appendAttendanceSegment(entry, joinTime, player.leave, player.subgroup, true)
                if #entry.segments > 0 then
                    attendance[#attendance + 1] = entry
                end
            end
        end

        return attendance
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
                        local segment = segments[j]
                        if type(segment) == "table" then
                            appendAttendanceSegment(normalizedEntry, segment.startTime, segment.endTime, segment.subgroup, segment.online)
                        end
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
                -- Promote legacy 'count' → 'countMS' (handles pre-v5 saves).
                local countMS = tonumber(player.countMS) or tonumber(player.count) or 0
                if countMS < 0 then
                    countMS = 0
                end
                player.countMS = (countMS > 0) and countMS or nil
                player.count = nil -- remove legacy field

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
        raid.attendance = compactAttendance(raid.attendance)
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

                local countSR = tonumber(player.countSR) or 0
                if countSR < 0 then
                    countSR = 0
                end
                player.countSR = countSR
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

    -- v4 attendance ledger:
    -- - raid.attendance[] stores per-playerNid attendance segments.
    -- - segment online=true is the default and is omitted during compaction.
    MIGRATIONS[3] = function(raid)
        ensureTableField(raid, "players", false)
        ensureTableField(raid, "attendance", false)

        if #raid.attendance == 0 then
            raid.attendance = buildAttendanceFromPlayers(raid.players)
        else
            raid.attendance = compactAttendance(raid.attendance)
        end
    end

    -- v5 loot counter fields:
    -- - player.count (legacy MS counter) renamed to player.countMS.
    -- - player.countOs, player.countFree, player.countSR added.
    -- - Zero-value counts are stored as nil to save space.
    MIGRATIONS[4] = function(raid)
        local players = raid.players or {}
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local countMS = tonumber(player.countMS) or tonumber(player.count) or 0
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
            end
        end
    end
end
