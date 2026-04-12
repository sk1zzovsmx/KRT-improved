-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local Core = feature.Core

local format = string.format
local pairs = pairs
local tonumber = tonumber
local type = type

local twipe = table.wipe

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    function module:GetRaidChanges(raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return {}
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.GetRaidChanges", { "GetRaidChanges" })
        if not raidStore then
            return {}
        end

        local changes = raidStore:GetRaidChanges(raidNum)
        if type(changes) ~= "table" then
            return {}
        end

        return changes
    end

    function module:UpsertRaidChange(raidNum, playerName, spec)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return false, nil, nil
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.UpsertRaidChange", { "UpsertRaidChange" })
        if not raidStore then
            return false, nil, nil
        end

        local ok, savedName, savedSpec = raidStore:UpsertRaidChange(raidNum, playerName, spec)
        return ok == true, savedName, savedSpec
    end

    function module:DeleteRaidChange(raidNum, playerName)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return false, false
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.DeleteRaidChange", { "DeleteRaidChange" })
        if not raidStore then
            return false, false
        end

        local ok, existed = raidStore:DeleteRaidChange(raidNum, playerName)
        return ok == true, existed == true
    end

    function module:ClearRaidChanges(raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return false, 0
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.ClearRaidChanges", { "ClearRaidChanges" })
        if not raidStore then
            return false, 0
        end

        local ok, removed = raidStore:ClearRaidChanges(raidNum)
        return ok == true, tonumber(removed) or 0
    end

    function module:BuildRaidChangesDemandText()
        return L.StrChangesDemand
    end

    function module:BuildRaidChangesAnnouncement(changesByName, selectedName, namesOut)
        local count = (type(changesByName) == "table") and addon.tLength(changesByName) or 0
        if count == 0 then
            return L.StrChangesAnnounceNone, 0
        end

        if selectedName then
            local spec = changesByName[selectedName]
            if spec == nil then
                return nil, count
            end
            return format(L.StrChangesAnnounceOne, selectedName, spec), count
        end

        local names = namesOut or {}
        if twipe then
            twipe(names)
        else
            for i = 1, #names do
                names[i] = nil
            end
        end

        for name in pairs(changesByName) do
            names[#names + 1] = name
        end
        table.sort(names)

        local msg = L.StrChangesAnnounce
        for i = 1, #names do
            local name = names[i]
            msg = msg .. " " .. name .. "=" .. tostring(changesByName[name])
            if i < #names then
                msg = msg .. " /"
            end
        end
        return msg, count
    end
end
