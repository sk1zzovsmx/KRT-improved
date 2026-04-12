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

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --
    local raidInstanceCheckHandles = {}
    local RAID_INSTANCE_CHECK_DELAYS = { 0.3, 0.8, 1.5, 2.5, 3.5 }

    -- ----- Private helpers ----- --
    local function resolveRaidDifficulty(instanceDiff)
        return module._ResolveRaidDifficultyInternal(instanceDiff)
    end

    local function getRaidSizeFromDifficulty(instanceDiff)
        return module._GetRaidSizeFromDifficultyInternal(instanceDiff)
    end

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

    -- ----- Public methods ----- --

    function module:GetRaid(raidNum)
        if raidNum == nil then
            raidNum = Core.GetCurrentRaid and Core.GetCurrentRaid() or nil
        end
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
        instanceDiff = resolveRaidDifficulty(instanceDiff)
        local newSize = getRaidSizeFromDifficulty(instanceDiff)
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
end
