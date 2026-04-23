-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Events = feature.Events or addon.Events
local Core = feature.Core

local InternalEvents = Events.Internal

local tostring = tostring
local tonumber = tonumber

local twipe = table.wipe

-- Maps loot type string to the player field name.
local LOOT_FIELD = {
    ms = "countMS",
    os = "countOs",
    free = "countFree",
    sr = "countSR",
}

-- Maps C.rollTypes values to loot type strings (only countable types).
local ROLL_TYPE_TO_LOOT_TYPE = {
    [1] = "ms", -- MAINSPEC
    [2] = "os", -- OFFSPEC
    [3] = "sr", -- RESERVED (SR)
    [4] = "free", -- FREE
}

local function findRaidPlayerByNid(raid, playerNid)
    local nid = tonumber(playerNid)
    if not nid or nid <= 0 then
        return nil
    end

    local players = raid and raid.players or {}
    for i = #players, 1, -1 do
        local player = players[i]
        if player and tonumber(player.playerNid) == nid then
            return player, i
        end
    end
    return nil
end

local function resolveRaidWithSchema(raidNum)
    local resolvedRaidNum = raidNum or Core.GetCurrentRaid()
    local raid = Core.EnsureRaidById(resolvedRaidNum)
    if not raid then
        return nil, nil
    end
    Core.EnsureRaidSchema(raid)
    return raid, resolvedRaidNum
end

local function resolveRaidPlayerByNid(playerNid, raidNum)
    local raid, resolvedRaidNum = resolveRaidWithSchema(raidNum)
    if not raid then
        return nil, nil
    end
    local player = findRaidPlayerByNid(raid, playerNid)
    return player, resolvedRaidNum
end

local function iterateRaidsForScope(scope, n, callback)
    local raids = _G.KRT_Raids
    if type(raids) ~= "table" then
        return
    end
    local ids = {}
    for k in pairs(raids) do
        local num = tonumber(k)
        if num then
            ids[#ids + 1] = num
        end
    end
    table.sort(ids, function(a, b)
        return a > b
    end)
    if scope == "CURRENT" then
        local current = Core.GetCurrentRaid()
        if not current then
            return
        end
        local raid = Core.EnsureRaidById(current)
        if raid then
            Core.EnsureRaidSchema(raid)
            callback(raid, current)
        end
        return
    end
    local limit = (scope == "LAST_N") and (tonumber(n) or 0) or #ids
    if limit <= 0 then
        return
    end
    local visited = 0
    for _, raidNum in ipairs(ids) do
        if visited >= limit then
            break
        end
        local raid = Core.EnsureRaidById(raidNum)
        if raid then
            Core.EnsureRaidSchema(raid)
            callback(raid, raidNum)
        end
        visited = visited + 1
    end
end

local function sumCountMSForName(raid, name)
    if not (raid and raid.players and name) then
        return 0
    end
    for i = #raid.players, 1, -1 do
        local p = raid.players[i]
        if p and p.name == name then
            return tonumber(p.countMS) or 0
        end
    end
    return 0
end

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid
    module._FindRaidPlayerByNid = findRaidPlayerByNid

    -- ----- Internal state ----- --

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    function module:GetLootCounterRows(raidNum, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        local rows = out or {}
        if out then
            twipe(rows)
        end
        if not raid or not raid.players then
            return rows
        end

        Core.EnsureRaidSchema(raid)

        local seenByName = {}
        for i = #raid.players, 1, -1 do
            local p = raid.players[i]
            if p and p.name and not seenByName[p.name] then
                seenByName[p.name] = true
                rows[#rows + 1] = {
                    playerNid = tonumber(p.playerNid),
                    name = p.name,
                    class = p.class,
                    msCount = tonumber(p.countMS) or 0,
                    osCount = tonumber(p.countOs) or 0,
                    freeCount = tonumber(p.countFree) or 0,
                    srCount = tonumber(p.countSR) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        return rows
    end

    -- Generic count access by loot type ("ms", "os", "free").
    function module:GetPlayerLootCountByNid(playerNid, lootType, raidNum)
        local player = resolveRaidPlayerByNid(playerNid, raidNum)
        if not player then
            return 0
        end
        local field = LOOT_FIELD[lootType] or "count"
        return tonumber(player[field]) or 0
    end

    function module:SetPlayerLootCountByNid(playerNid, lootType, value, raidNum)
        local player, resolvedRaidNum = resolveRaidPlayerByNid(playerNid, raidNum)
        if not player then
            return
        end

        local field = LOOT_FIELD[lootType] or "count"
        value = tonumber(value) or 0
        if value < 0 then
            value = 0
        end

        local old = tonumber(player[field]) or 0
        player[field] = value

        if old ~= value then
            local bus = feature.Bus or addon.Bus
            bus.TriggerEvent(InternalEvents.PlayerCountChanged, player.name, value, old, resolvedRaidNum)
        end
    end

    function module:AddPlayerLootCountByNid(playerNid, lootType, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        local current = module:GetPlayerLootCountByNid(playerNid, lootType, raidNum) or 0
        local nextVal = current + delta
        if nextVal < 0 then
            nextVal = 0
        end

        module:SetPlayerLootCountByNid(playerNid, lootType, nextVal, raidNum)
    end

    -- MS-specific aliases kept for backward compatibility.
    function module:GetPlayerCountByNid(playerNid, raidNum)
        return module:GetPlayerLootCountByNid(playerNid, "ms", raidNum)
    end

    function module:SetPlayerCountByNid(playerNid, value, raidNum)
        module:SetPlayerLootCountByNid(playerNid, "ms", value, raidNum)
    end

    function module:AddPlayerCountByNid(playerNid, delta, raidNum)
        module:AddPlayerLootCountByNid(playerNid, "ms", delta, raidNum)
    end

    function module:AddPlayerLootCount(name, lootType, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not name then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        if type(module.CheckPlayer) == "function" then
            local ok, fixed = module:CheckPlayer(name, raidNum)
            if ok and fixed then
                name = fixed
            end
        end

        name = (feature.Strings or addon.Strings).NormalizeName(name, true)
        if not name then
            return
        end

        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid <= 0 then
            if type(module.AddPlayer) == "function" then
                module:AddPlayer({ name = name }, raidNum)
                playerNid = module:GetPlayerID(name, raidNum)
                if playerNid <= 0 then
                    return
                end
            else
                return
            end
        end
        module:AddPlayerLootCountByNid(playerNid, lootType, delta, raidNum)
    end

    -- Increments the correct counter based on the C.rollTypes value.
    -- Only MAINSPEC, OFFSPEC, and FREE are tracked; other types are ignored.
    function module:AddPlayerCountForRollType(name, rollType, delta, raidNum)
        local lootType = ROLL_TYPE_TO_LOOT_TYPE[tonumber(rollType)]
        if not lootType then
            return
        end
        module:AddPlayerLootCount(name, lootType, delta, raidNum)
    end

    -- MS alias kept for backward compatibility.
    function module:AddPlayerCount(name, delta, raidNum)
        module:AddPlayerLootCount(name, "ms", delta, raidNum)
    end

    function module:GetPlayerCount(name, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return 0
        end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid <= 0 then
            return 0
        end
        return module:GetPlayerCountByNid(playerNid, raidNum)
    end

    function module:GetPlayerMSCount(name, opts)
        if type(name) ~= "string" or name == "" then
            return 0
        end
        local scope = (opts and opts.scope) or "CURRENT"
        local n = opts and opts.n
        local total = 0
        iterateRaidsForScope(scope, n, function(raid)
            total = total + sumCountMSForName(raid, name)
        end)
        return total
    end

    function module:GetMSCountsForNames(names, opts, out)
        local result = out or {}
        if out then
            twipe(result)
        end
        if type(names) ~= "table" or #names == 0 then
            return result
        end
        local nameSet = {}
        for _, nm in ipairs(names) do
            if type(nm) == "string" and nm ~= "" then
                nameSet[nm] = true
                result[nm] = 0
            end
        end
        if next(nameSet) == nil then
            return result
        end
        local scope = (opts and opts.scope) or "CURRENT"
        local n = opts and opts.n
        iterateRaidsForScope(scope, n, function(raid)
            if not (raid and raid.players) then
                return
            end
            local seen = {}
            for i = #raid.players, 1, -1 do
                local p = raid.players[i]
                if p and p.name and nameSet[p.name] and not seen[p.name] then
                    seen[p.name] = true
                    result[p.name] = (result[p.name] or 0) + (tonumber(p.countMS) or 0)
                end
            end
        end)
        return result
    end

    function module:SetPlayerCount(name, value, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return
        end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid <= 0 then
            return
        end
        module:SetPlayerCountByNid(playerNid, value, raidNum)
    end
end
