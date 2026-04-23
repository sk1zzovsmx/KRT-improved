-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core
local Sort = feature.Sort or addon.Sort
local GetLootSortName = Sort and Sort.GetLootSortName

local pairs, type = pairs, type
local tonumber, tostring = tonumber, tostring

-- Raid read-only projection/query service.
do
    addon.DB.RaidQueries = addon.DB.RaidQueries or {}
    local module = addon.DB.RaidQueries

    -- ----- Internal state ----- --

    -- ----- Private helpers ----- --
    local function normalizeRaid(raid)
        local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("DBRaidQueries.NormalizeRaid", { "NormalizeRaidRecord" }) or nil
        if raidStore then
            return raidStore:NormalizeRaidRecord(raid)
        end
        return raid
    end

    local function ensureRuntime(raid)
        local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("DBRaidQueries.EnsureRuntime", { "EnsureRaidRuntime" }) or nil
        if raidStore then
            return raidStore:EnsureRaidRuntime(raid)
        end
        return nil
    end

    local function appendRows(out, rows)
        if type(out) ~= "table" then
            return
        end
        for i = 1, #out do
            out[i] = nil
        end
        for i = 1, #rows do
            out[i] = rows[i]
        end
    end

    local function getPlayerByNid(raid, runtime, playerNid)
        local queryNid = tonumber(playerNid)
        if not (raid and queryNid and queryNid > 0) then
            return nil
        end

        local idxByNid = runtime and runtime.playerIdxByNid or nil
        local idx = idxByNid and idxByNid[queryNid] or nil
        local players = raid.players or {}
        if idx then
            local player = players[idx]
            if player and tonumber(player.playerNid) == queryNid then
                return player
            end
        end

        for i = 1, #players do
            local player = players[i]
            if player and tonumber(player.playerNid) == queryNid then
                return player
            end
        end
        return nil
    end

    local function resolveLootLooterNid(loot)
        if type(loot) ~= "table" then
            return nil
        end
        local looterNid = tonumber(loot.looterNid)
        if looterNid and looterNid > 0 then
            return looterNid
        end
        return nil
    end

    local function resolveLootLooterName(raid, runtime, loot)
        local looterNid = resolveLootLooterNid(loot)
        if looterNid then
            local player = getPlayerByNid(raid, runtime, looterNid)
            if player and player.name then
                return player.name, looterNid
            end
            return nil, looterNid
        end
        return nil, nil
    end

    local function getAttendanceEntry(raid, playerNid)
        local attendance = raid and raid.attendance or nil
        local queryNid = tonumber(playerNid) or 0
        if type(attendance) ~= "table" or queryNid <= 0 then
            return nil
        end

        for i = 1, #attendance do
            local entry = attendance[i]
            if type(entry) == "table" and tonumber(entry.playerNid) == queryNid then
                return entry
            end
        end
        return nil
    end

    local function summarizeAttendance(entry, fallbackJoin, fallbackLeave)
        local now = time()
        local totalSeconds = 0
        local onlineSeconds = 0
        local offlineSeconds = 0
        local segmentCount = 0
        local segments = entry and entry.segments or nil

        if type(segments) == "table" then
            for i = 1, #segments do
                local segment = segments[i]
                if type(segment) == "table" then
                    local startTime = tonumber(segment.startTime) or 0
                    local endTime = tonumber(segment.endTime) or now
                    if startTime > 0 and endTime >= startTime then
                        local duration = endTime - startTime
                        totalSeconds = totalSeconds + duration
                        if segment.online == false then
                            offlineSeconds = offlineSeconds + duration
                        else
                            onlineSeconds = onlineSeconds + duration
                        end
                        segmentCount = segmentCount + 1
                    end
                end
            end
        end

        if segmentCount == 0 then
            local joinTime = tonumber(fallbackJoin) or 0
            local leaveTime = tonumber(fallbackLeave) or now
            if joinTime > 0 and leaveTime >= joinTime then
                totalSeconds = leaveTime - joinTime
                onlineSeconds = totalSeconds
                segmentCount = 1
            end
        end

        return totalSeconds, onlineSeconds, offlineSeconds, segmentCount
    end

    -- ----- Public methods ----- --
    function module:GetRaidSummary(raid)
        raid = normalizeRaid(raid)
        if type(raid) ~= "table" then
            return nil
        end

        return {
            raidNid = tonumber(raid.raidNid),
            zone = raid.zone,
            size = tonumber(raid.size) or 0,
            difficulty = tonumber(raid.difficulty) or 0,
            startTime = tonumber(raid.startTime) or 0,
            endTime = tonumber(raid.endTime) or 0,
            playersCount = #(raid.players or {}),
            bossCount = #(raid.bossKills or {}),
            lootCount = #(raid.loot or {}),
            changesCount = (function()
                local changes = raid.changes or {}
                local count = 0
                for _ in pairs(changes) do
                    count = count + 1
                end
                return count
            end)(),
        }
    end

    function module:GetBossKills(raid, out)
        raid = normalizeRaid(raid)
        local rows = {}
        local bosses = raid and raid.bossKills or {}
        for i = 1, #bosses do
            local boss = bosses[i]
            if type(boss) == "table" then
                local mode = boss.mode
                if not mode and boss.difficulty then
                    mode = (boss.difficulty == 3 or boss.difficulty == 4) and "h" or "n"
                end
                local killTime = tonumber(boss.time) or 0
                rows[#rows + 1] = {
                    id = tonumber(boss.bossNid),
                    seq = i,
                    name = boss.name or "",
                    mode = (mode == "h") and "H" or "N",
                    difficulty = tonumber(boss.difficulty) or 0,
                    time = killTime,
                    timeFmt = (killTime > 0) and date("%H:%M", killTime) or "",
                }
            end
        end

        if out then
            appendRows(out, rows)
            return out
        end
        return rows
    end

    function module:GetRaidAttendance(raid, out)
        raid = normalizeRaid(raid)
        local rows = {}
        local players = raid and raid.players or {}
        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local joinTime = tonumber(player.join)
                local leaveTime = tonumber(player.leave)
                local totalSeconds, onlineSeconds, offlineSeconds, segmentCount = summarizeAttendance(getAttendanceEntry(raid, player.playerNid), joinTime, leaveTime)
                rows[#rows + 1] = {
                    id = tonumber(player.playerNid),
                    name = player.name,
                    class = player.class,
                    join = joinTime,
                    leave = leaveTime,
                    joinFmt = joinTime and date("%H:%M", joinTime) or "",
                    leaveFmt = leaveTime and date("%H:%M", leaveTime) or "",
                    attendanceSeconds = totalSeconds,
                    onlineSeconds = onlineSeconds,
                    offlineSeconds = offlineSeconds,
                    segmentCount = segmentCount,
                }
            end
        end

        if out then
            appendRows(out, rows)
            return out
        end
        return rows
    end

    function module:GetBossAttendance(raid, bossNid, out)
        raid = normalizeRaid(raid)
        local rows = {}
        local queryNid = tonumber(bossNid)
        if not (raid and queryNid) then
            if out then
                appendRows(out, rows)
                return out
            end
            return rows
        end

        local runtime = ensureRuntime(raid)
        local bossByNid = runtime and runtime.bossByNid or nil
        local bossKill = bossByNid and bossByNid[queryNid] or nil
        if not (bossKill and type(bossKill.players) == "table") then
            if out then
                appendRows(out, rows)
                return out
            end
            return rows
        end

        local set = {}
        for i = 1, #bossKill.players do
            local playerNid = tonumber(bossKill.players[i])
            if playerNid and playerNid > 0 then
                set[playerNid] = true
            end
        end

        local players = raid.players or {}
        for i = 1, #players do
            local player = players[i]
            local playerNid = player and tonumber(player.playerNid) or nil
            if type(player) == "table" and player.name and playerNid and set[playerNid] then
                rows[#rows + 1] = {
                    id = playerNid,
                    name = player.name,
                    class = player.class,
                }
            end
        end

        if out then
            appendRows(out, rows)
            return out
        end
        return rows
    end

    function module:GetLoot(raid, bossNid, playerName, out)
        raid = normalizeRaid(raid)
        local rows = {}
        local bossFilter = tonumber(bossNid) or bossNid
        local playerFilterNid = nil
        if playerName and playerName ~= "" then
            local queryName = tostring(playerName)
            local players = raid and raid.players or {}
            for i = #players, 1, -1 do
                local player = players[i]
                if player and player.name == queryName then
                    playerFilterNid = tonumber(player.playerNid)
                    break
                end
            end
        end

        local runtime = raid and ensureRuntime(raid) or nil
        local bossByNid = runtime and runtime.bossByNid or nil
        local lootRows = raid and raid.loot or {}

        for i = 1, #lootRows do
            local loot = lootRows[i]
            if type(loot) == "table" then
                local looterNid = nil
                local looterName = nil
                looterName, looterNid = resolveLootLooterName(raid, runtime, loot)
                local okBoss = (not bossFilter) or (bossFilter <= 0) or (tonumber(loot.bossNid) == bossFilter)
                local okPlayer = not playerName
                    or (playerFilterNid and looterNid and playerFilterNid == looterNid)
                    or ((not playerFilterNid) and looterName and looterName == playerName)
                if okBoss and okPlayer then
                    local lootTime = tonumber(loot.time) or 0
                    local sourceBoss = bossByNid and bossByNid[tonumber(loot.bossNid)] or nil
                    local looterPlayer = looterNid and getPlayerByNid(raid, runtime, looterNid) or nil
                    rows[#rows + 1] = {
                        id = tonumber(loot.lootNid),
                        itemId = tonumber(loot.itemId),
                        itemName = loot.itemName,
                        itemRarity = loot.itemRarity,
                        itemTexture = loot.itemTexture,
                        itemLink = loot.itemLink,
                        bossNid = tonumber(loot.bossNid) or 0,
                        sourceName = (sourceBoss and sourceBoss.name) or "",
                        looterNid = looterNid,
                        looter = looterName or "",
                        looterClass = looterPlayer and looterPlayer.class or nil,
                        rollType = tonumber(loot.rollType) or 0,
                        rollValue = tonumber(loot.rollValue) or 0,
                        sortName = (GetLootSortName and GetLootSortName(loot.itemName, loot.itemLink, loot.itemId)) or tostring(loot.itemName or ""),
                        time = lootTime,
                        timeFmt = (lootTime > 0) and date("%H:%M", lootTime) or "",
                    }
                end
            end
        end

        if out then
            appendRows(out, rows)
            return out
        end
        return rows
    end

    function module:GetLootByBoss(raid, bossNid, out)
        return self:GetLoot(raid, bossNid, nil, out)
    end

    function module:GetPlayerCounts(raid, out)
        raid = normalizeRaid(raid)
        local rows = {}
        local seenByName = {}
        local players = raid and raid.players or {}

        for i = #players, 1, -1 do
            local player = players[i]
            if type(player) == "table" and player.name and not seenByName[player.name] then
                seenByName[player.name] = true
                rows[#rows + 1] = {
                    playerNid = tonumber(player.playerNid),
                    name = player.name,
                    class = player.class,
                    count = tonumber(player.countMS) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        if out then
            appendRows(out, rows)
            return out
        end
        return rows
    end
end
