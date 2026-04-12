-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Core = feature.Core

local format = string.format
local pairs = pairs
local tonumber = tonumber
local type = type

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --
    local raidInstanceCheckHandles = {}
    local RAID_INSTANCE_CHECK_DELAYS = { 0.3, 0.8, 1.5, 2.5, 3.5 }

    -- ----- Private helpers ----- --
    local function cancelRaidInstanceChecks()
        for idx, handle in pairs(raidInstanceCheckHandles) do
            addon.CancelTimer(handle, true)
            raidInstanceCheckHandles[idx] = nil
        end
    end

    local function runLiveRaidInstanceCheck()
        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        if instanceType ~= "raid" then
            return
        end
        if L.RaidZones[instanceName] == nil then
            return
        end
        module:Check(instanceName, instanceDiff)
    end

    local function createRaidSessionWithReason(instanceName, newSize, instanceDiff, isCreate)
        local created = module:Create(instanceName, newSize, instanceDiff)
        if not created then
            return false
        end
        addon:info(L.StrNewRaidSessionChange)
        local template = isCreate and Diag.D.LogRaidSessionCreate or Diag.D.LogRaidSessionChange
        addon:debug(template:format(tostring(instanceName), newSize, tonumber(instanceDiff) or -1))
        return true
    end

    local function resolveRaidNum(raidNum)
        if raidNum ~= nil then
            return raidNum
        end
        if Core.GetCurrentRaid then
            return Core.GetCurrentRaid()
        end
        return nil
    end

    local function getRaidStoreForChangeCall(contextTag, methodName)
        return Core.GetRaidStoreOrNil(contextTag, { methodName })
    end

    -- ----- Public methods ----- --

    function module:GetRaid(raidNum)
        raidNum = resolveRaidNum(raidNum)
        if not raidNum then
            return nil, nil
        end

        local raidStore = Core.GetRaidStoreOrNil("Raid.GetRaid", { "GetRaidByIndex" })
        if raidStore then
            return raidStore:GetRaidByIndex(raidNum)
        end
        return nil, raidNum
    end

    function module:InvalidateRaidRuntime(raidNum)
        local raid = Core.EnsureRaidById(raidNum)
        if raid then
            if type(module._InvalidateRaidRuntimeInternal) == "function" then
                module._InvalidateRaidRuntimeInternal(raid)
            end
        end
    end

    function module:CancelInstanceChecks()
        cancelRaidInstanceChecks()
    end

    function module:ScheduleInstanceChecks()
        cancelRaidInstanceChecks()

        -- Immediate live check, then short retries to catch delayed server fallback updates.
        runLiveRaidInstanceCheck()

        for i = 1, #RAID_INSTANCE_CHECK_DELAYS do
            local idx = i
            local delaySeconds = RAID_INSTANCE_CHECK_DELAYS[idx]
            raidInstanceCheckHandles[idx] = addon.NewTimer(delaySeconds, function()
                raidInstanceCheckHandles[idx] = nil
                runLiveRaidInstanceCheck()
            end)
        end
    end

    -- Checks the current raid status and creates a new session if needed.
    function module:Check(instanceName, instanceDiff)
        instanceDiff = module._ResolveRaidDifficultyInternal(instanceDiff)
        local newSize = module._GetRaidSizeFromDifficultyInternal(instanceDiff)
        addon:debug(Diag.D.LogRaidCheck:format(tostring(instanceName), tostring(instanceDiff), tostring(Core.GetCurrentRaid())))
        if not newSize then
            return
        end

        if not Core.GetCurrentRaid() then
            module:Create(instanceName, newSize, instanceDiff)
            return
        end

        local current = Core.EnsureRaidById(Core.GetCurrentRaid())
        if not current then
            createRaidSessionWithReason(instanceName, newSize, instanceDiff, true)
            return
        end

        local shouldCreate = current.zone ~= instanceName or tonumber(current.size) ~= newSize or tonumber(current.difficulty) ~= instanceDiff

        if shouldCreate then
            createRaidSessionWithReason(instanceName, newSize, instanceDiff, false)
        end
    end

    -- ----- Boss helpers (merged from Raid/Boss.lua) ----- --

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
            table.wipe(bosses)
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

    -- ----- Changes helpers (merged from Raid/Changes.lua) ----- --

    function module:GetRaidChanges(raidNum)
        raidNum = resolveRaidNum(raidNum)
        if not raidNum then
            return {}
        end

        local raidStore = getRaidStoreForChangeCall("Raid.GetRaidChanges", "GetRaidChanges")
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
        raidNum = resolveRaidNum(raidNum)
        if not raidNum then
            return false, nil, nil
        end

        local raidStore = getRaidStoreForChangeCall("Raid.UpsertRaidChange", "UpsertRaidChange")
        if not raidStore then
            return false, nil, nil
        end

        local ok, savedName, savedSpec = raidStore:UpsertRaidChange(raidNum, playerName, spec)
        return ok == true, savedName, savedSpec
    end

    function module:DeleteRaidChange(raidNum, playerName)
        raidNum = resolveRaidNum(raidNum)
        if not raidNum then
            return false, false
        end

        local raidStore = getRaidStoreForChangeCall("Raid.DeleteRaidChange", "DeleteRaidChange")
        if not raidStore then
            return false, false
        end

        local ok, existed = raidStore:DeleteRaidChange(raidNum, playerName)
        return ok == true, existed == true
    end

    function module:ClearRaidChanges(raidNum)
        raidNum = resolveRaidNum(raidNum)
        if not raidNum then
            return false, 0
        end

        local raidStore = getRaidStoreForChangeCall("Raid.ClearRaidChanges", "ClearRaidChanges")
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
        table.wipe(names)

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
