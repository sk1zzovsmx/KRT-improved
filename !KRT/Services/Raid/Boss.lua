-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core
local twipe = table.wipe
local tonumber = tonumber

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    function module:GetBossByNid(bossNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        if not raid or bossNid == nil then
            return nil
        end

        Core.EnsureRaidSchema(raid)

        bossNid = tonumber(bossNid) or 0
        if bossNid <= 0 then
            return nil
        end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local b = bosses[i]
            if b and tonumber(b.bossNid) == bossNid then
                return b, i
            end
        end
        return nil
    end

    function module:GetBosses(raidNum, out)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = raidNum and Core.EnsureRaidById(raidNum)
        if not raid or not raid.bossKills then
            return {}
        end

        Core.EnsureRaidSchema(raid)

        local bosses = out or {}
        if out then
            twipe(bosses)
        end

        for i = 1, #raid.bossKills do
            local boss = raid.bossKills[i]
            bosses[#bosses + 1] = {
                id = tonumber(boss.bossNid), -- stable selection id
                seq = i, -- display order
                name = boss.name,
                time = boss.time,
                mode = boss.mode or ((boss.difficulty == 3 or boss.difficulty == 4) and "h" or "n"),
            }
        end
        return bosses
    end

    function module:ClearRaidIcons()
        local players = module:GetPlayers()
        for i = 1, #players do
            SetRaidTarget("raid" .. tostring(i), 0)
        end
    end
end
