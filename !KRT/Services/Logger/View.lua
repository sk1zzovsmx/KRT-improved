-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Sort = feature.Sort
local Core = feature.Core

local GetLootSortName = Sort.GetLootSortName

local twipe = table.wipe
local tostring, tonumber = tostring, tonumber
local date, time = date, time

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Logger", "View")
local View = addon.Services.Logger.View
local Store = addon.Services.Logger.Store
local buildRows

local function getRaidQueries()
    if Core.GetRaidQueries then
        return Core.GetRaidQueries()
    end
    return nil
end

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

function View:GetBossModeLabel(bossData)
    if not bossData then
        return "?"
    end
    local mode = bossData.mode
    if not mode and bossData.difficulty then
        mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
    end
    return (mode == "h") and "H" or "N"
end

function View:GetRaidDifficultyLabel(raid)
    local diff = tonumber(raid and raid.difficulty)
    local size = tonumber(raid and raid.size)
    if diff == 1 then
        return "10N"
    elseif diff == 2 then
        return "25N"
    elseif diff == 3 then
        return "10H"
    elseif diff == 4 then
        return "25H"
    end
    if size then
        return tostring(size) .. "?"
    end
    return ""
end

buildRows = function(out, list, pred, map)
    if not out then
        return
    end
    twipe(out)
    if not list then
        return
    end
    local n = 0
    for i = 1, #list do
        local e = list[i]
        if (not pred) or pred(e, i) then
            n = n + 1
            out[n] = map(e, i, n)
        end
    end
end

function View:FillBossList(out, raid)
    local queries = getRaidQueries()
    if queries and queries.GetBossKills then
        return queries:GetBossKills(raid, out)
    end
    buildRows(out, raid and raid.bossKills, nil, function(boss, i)
        local it = {}
        it.id = tonumber(boss and boss.bossNid)
        it.seq = i
        it.name = boss and boss.name or ""
        it.time = boss and boss.time or time()
        it.timeFmt = date("%H:%M", it.time)
        it.mode = self:GetBossModeLabel(boss)
        return it
    end)
end

function View:FillRaidAttendeesList(out, raid)
    local queries = getRaidQueries()
    if queries and queries.GetRaidAttendance then
        return queries:GetRaidAttendance(raid, out)
    end
    buildRows(out, raid and raid.players, nil, function(p)
        local it = {}
        it.id = tonumber(p and p.playerNid)
        it.name = p.name
        it.class = p.class
        it.join = p.join
        it.leave = p.leave
        it.joinFmt = p.join and date("%H:%M", p.join) or ""
        it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
        return it
    end)
end

function View:FillBossAttendeesList(out, raid, bossNid)
    local queries = getRaidQueries()
    if queries and queries.GetBossAttendance then
        return queries:GetBossAttendance(raid, bossNid, out)
    end
    if not out then
        return
    end
    twipe(out)
    if not (raid and bossNid) then
        return
    end
    local bossKill = Store:GetBoss(raid, bossNid)
    if not (bossKill and bossKill.players and raid.players) then
        return
    end

    local set = {}
    for i = 1, #bossKill.players do
        local playerNid = tonumber(bossKill.players[i])
        if playerNid and playerNid > 0 then
            set[playerNid] = true
        end
    end

    local n = 0
    for i = 1, #raid.players do
        local p = raid.players[i]
        local playerNid = p and tonumber(p.playerNid) or nil
        if p and p.name and playerNid and set[playerNid] then
            n = n + 1
            local it = {}
            it.id = playerNid
            it.name = p.name
            it.class = p.class
            out[n] = it
        end
    end
end

function View:FillLootList(out, raid, bossNid, playerName)
    local queries = getRaidQueries()
    if queries and queries.GetLoot then
        return queries:GetLoot(raid, bossNid, playerName, out)
    end
    local bossFilter = tonumber(bossNid) or bossNid
    local playerFilterNid = Store._ResolveLootLooterNid(raid, playerName)
    buildRows(out, raid and raid.loot, function(v)
        if not v then
            return false
        end
        local okBoss = (not bossFilter) or (bossFilter <= 0) or (tonumber(v.bossNid) == bossFilter)
        local looterNid = tonumber(v.looterNid)
        local looterName = Store._ResolveLootLooterName(raid, v)
        local okPlayer = not playerName or (playerFilterNid and looterNid and playerFilterNid == looterNid) or ((not playerFilterNid) and looterName and looterName == playerName)
        return okBoss and okPlayer
    end, function(v)
        local it = {}
        it.id = v.lootNid
        it.itemId = v.itemId
        it.itemName = v.itemName
        it.itemRarity = v.itemRarity
        it.itemTexture = v.itemTexture
        it.itemLink = v.itemLink
        it.bossNid = v.bossNid
        it.sortName = GetLootSortName(v.itemName, v.itemLink, v.itemId)
        local boss = Store:GetBoss(raid, v.bossNid)
        it.sourceName = (boss and boss.name) or ""
        it.looterNid = tonumber(v.looterNid)
        it.looter = Store._ResolveLootLooterName(raid, v) or ""
        it.looterClass = Store._ResolveLootLooterClass(raid, v)
        it.rollType = tonumber(v.rollType) or 0
        it.rollValue = v.rollValue
        it.time = v.time or time()
        it.timeFmt = date("%H:%M", it.time)
        return it
    end)
end
