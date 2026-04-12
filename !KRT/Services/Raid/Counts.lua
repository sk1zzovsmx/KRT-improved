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
                    count = tonumber(p.count) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        return rows
    end

    function module:GetPlayerCountByNid(playerNid, raidNum)
        local player = resolveRaidPlayerByNid(playerNid, raidNum)
        if not player then
            return 0
        end
        return tonumber(player.count) or 0
    end

    function module:SetPlayerCountByNid(playerNid, value, raidNum)
        local player, resolvedRaidNum = resolveRaidPlayerByNid(playerNid, raidNum)
        if not player then
            return
        end

        value = tonumber(value) or 0
        -- Hard clamp: counts are always non-negative.
        if value < 0 then
            value = 0
        end

        local old = tonumber(player.count) or 0
        player.count = value

        if old ~= value then
            local bus = feature.Bus or addon.Bus
            bus.TriggerEvent(InternalEvents.PlayerCountChanged, player.name, value, old, resolvedRaidNum)
        end
    end

    function module:AddPlayerCountByNid(playerNid, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        local current = module:GetPlayerCountByNid(playerNid, raidNum) or 0
        local nextVal = current + delta
        if nextVal < 0 then
            nextVal = 0
        end

        module:SetPlayerCountByNid(playerNid, nextVal, raidNum)
    end

    function module:AddPlayerCount(name, delta, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum or not name then
            return
        end

        delta = tonumber(delta) or 0
        if delta == 0 then
            return
        end

        -- Normalize/resolve name if possible.
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
        module:AddPlayerCountByNid(playerNid, delta, raidNum)
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
