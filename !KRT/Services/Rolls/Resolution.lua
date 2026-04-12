-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: resolution and display helpers for rolls service
-- exports: addon.Services.Rolls._Resolution

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local tconcat = table.concat
local pairs = pairs
local tostring, tonumber = tostring, tonumber

addon.Services = addon.Services or {}
addon.Services.Rolls = addon.Services.Rolls or {}

-- ----- Internal state ----- --
local module = addon.Services.Rolls
module._Resolution = module._Resolution or {}

local Resolution = module._Resolution

-- ----- Private helpers ----- --
local function assertContext(ctx)
    assert(type(ctx) == "table", "Rolls resolution context is required")
    assert(type(ctx.state) == "table", "Rolls resolution state is required")
    return ctx, ctx.state
end

local function compareResolvedEntries(a, b, wantLow, usePlus)
    if a.bucketPriority ~= b.bucketPriority then
        return a.bucketPriority < b.bucketPriority
    end

    if usePlus and a.bucket == "SR" and b.bucket == "SR" and a.plus ~= b.plus then
        return a.plus > b.plus
    end

    if a.roll ~= b.roll then
        return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
    end

    return tostring(a.name) < tostring(b.name)
end

local function areResolvedEntriesTied(a, b, usePlus)
    if not (a and b) then
        return false
    end
    if a.bucketPriority ~= b.bucketPriority or a.bucket ~= b.bucket then
        return false
    end
    if usePlus and a.bucket == "SR" and a.plus ~= b.plus then
        return false
    end
    return a.roll ~= nil and a.roll == b.roll
end

-- ----- Public methods ----- --
function Resolution.GetBucketPriority(ctx, bucket, rollType)
    local rollTypes = ctx.rollTypes or feature.rollTypes

    if bucket == "INELIGIBLE" then
        return 99
    end
    if rollType == rollTypes.RESERVED then
        if bucket == "SR" then
            return 1
        end
        return 2
    end
    return 1
end

function Resolution.GetDisplayTier(ctx, response)
    local responseStatus = ctx.responseStatus or {}

    if response.status == responseStatus.ROLL and response.isEligible == true then
        return 1
    end
    if response.bestRoll ~= nil then
        return 2
    end
    if response.status == responseStatus.PASS then
        return 3
    end
    if response.status == responseStatus.CANCELLED then
        return 4
    end
    if response.status == responseStatus.ACTIVE then
        return 5
    end
    if response.status == responseStatus.TIMED_OUT then
        return 6
    end
    return 7
end

function Resolution.GetResponsePlus(ctx, itemId, response, plusGetter)
    if not itemId or response.bucket ~= "SR" or not plusGetter then
        return 0
    end
    return plusGetter(response.name)
end

function Resolution.BuildResolvedEntries(ctx, itemId, currentRollType)
    local _, state = assertContext(ctx)
    local rollTypes = ctx.rollTypes or feature.rollTypes
    local usePlus = currentRollType == rollTypes.RESERVED and itemId and ctx.isPlusSystemEnabled and ctx.isPlusSystemEnabled()
    local plusGetter = itemId and function(name)
        return ctx.getPlusForItem and ctx.getPlusForItem(itemId, name) or 0
    end or nil
    local wantLow = ctx.isSortAscending and ctx.isSortAscending() or false
    local resolved = {}

    for name, response in pairs(state.responsesByPlayer) do
        if ctx.isSelectableRollResponse and ctx.isSelectableRollResponse(response) then
            resolved[#resolved + 1] = {
                name = name,
                bucket = response.bucket,
                bucketPriority = Resolution.GetBucketPriority(ctx, response.bucket, currentRollType),
                plus = Resolution.GetResponsePlus(ctx, itemId, response, plusGetter),
                roll = tonumber(response.bestRoll) or 0,
            }
        end
    end

    table.sort(resolved, function(a, b)
        return compareResolvedEntries(a, b, wantLow, usePlus)
    end)

    return resolved, usePlus, plusGetter
end

function Resolution.BuildTieGroups(_ctx, resolvedEntries, usePlus)
    local tieGroupByName = {}
    local groupId = 0
    local i = 1

    while i <= #resolvedEntries do
        local j = i
        while j < #resolvedEntries and areResolvedEntriesTied(resolvedEntries[j], resolvedEntries[j + 1], usePlus) do
            j = j + 1
        end

        if j > i then
            groupId = groupId + 1
            for k = i, j do
                tieGroupByName[resolvedEntries[k].name] = groupId
            end
        end

        i = j + 1
    end

    return tieGroupByName
end

function Resolution.BuildResolution(ctx, resolvedEntries, usePlus)
    local resolution = {
        autoWinners = {},
        tiedNames = {},
        requiresManualResolution = false,
        cutoff = ctx.getExpectedWinnerCount and ctx.getExpectedWinnerCount() or 1,
        topRollName = resolvedEntries[1] and resolvedEntries[1].name or nil,
    }
    local appliedCutoff = resolution.cutoff

    if appliedCutoff > #resolvedEntries then
        appliedCutoff = #resolvedEntries
    end
    if appliedCutoff < 0 then
        appliedCutoff = 0
    end
    if appliedCutoff == 0 then
        return resolution
    end

    local groupStart = appliedCutoff
    local groupEnd = appliedCutoff
    while groupStart > 1 and areResolvedEntriesTied(resolvedEntries[groupStart - 1], resolvedEntries[appliedCutoff], usePlus) do
        groupStart = groupStart - 1
    end
    while groupEnd < #resolvedEntries and areResolvedEntriesTied(resolvedEntries[groupEnd + 1], resolvedEntries[appliedCutoff], usePlus) do
        groupEnd = groupEnd + 1
    end

    if groupEnd > appliedCutoff then
        resolution.requiresManualResolution = true
        for i = 1, groupStart - 1 do
            local entry = resolvedEntries[i]
            resolution.autoWinners[#resolution.autoWinners + 1] = {
                name = entry.name,
                roll = entry.roll,
            }
        end
        for i = groupStart, groupEnd do
            resolution.tiedNames[#resolution.tiedNames + 1] = resolvedEntries[i].name
        end
    else
        for i = 1, appliedCutoff do
            local entry = resolvedEntries[i]
            resolution.autoWinners[#resolution.autoWinners + 1] = {
                name = entry.name,
                roll = entry.roll,
            }
        end
    end

    addon:debug(
        Diag.D.LogRollsResolution:format(
            tostring(resolution.topRollName),
            tconcat(resolution.tiedNames, ","),
            tonumber(resolution.cutoff) or 0,
            tostring(resolution.requiresManualResolution)
        )
    )

    return resolution
end

function Resolution.BuildRowCounterText(ctx, itemId, response, currentRollType, plusGetter)
    local counterText = ""
    local rollTypes = ctx.rollTypes or feature.rollTypes
    local currentRaid

    if response.bucket == "SR" then
        if currentRollType == rollTypes.RESERVED and itemId and ctx.isPlusSystemEnabled and ctx.isPlusSystemEnabled() then
            local plus = Resolution.GetResponsePlus(ctx, itemId, response, plusGetter)
            if plus and plus > 0 then
                counterText = string.format("(P+%d)", plus)
            end
        else
            local allowed = tonumber(response.allowedRolls) or 0
            if allowed > 1 then
                local used = tonumber(response.usedRolls) or 0
                counterText = string.format("(%d/%d)", used, allowed)
            end
        end
    elseif ctx.shouldShowLootCounterDuringMSRoll and ctx.shouldShowLootCounterDuringMSRoll() and currentRollType == rollTypes.MAINSPEC then
        local raid = ctx.getRaidService and ctx.getRaidService() or nil
        currentRaid = ctx.getCurrentRaid and ctx.getCurrentRaid() or nil
        local count = raid and raid.GetPlayerCount and raid:GetPlayerCount(response.name, currentRaid) or 0
        if count and count > 0 then
            counterText = "+" .. count
        end
    end

    return counterText
end

function Resolution.BuildRowInfoText(ctx, response, isTied)
    local responseStatus = ctx.responseStatus or {}
    local reasonCodes = ctx.reasonCodes or {}

    if response and response.isOutOfTime == true then
        return L.StrRollTimedOutTag
    end

    if isTied then
        return L.StrRollTieTag
    end

    if response.status == responseStatus.PASS then
        return L.StrRollPassTag
    elseif response.status == responseStatus.CANCELLED then
        return L.StrRollCancelledTag
    elseif response.status == responseStatus.TIMED_OUT then
        return L.StrRollTimedOutTag
    elseif response.status == responseStatus.INELIGIBLE then
        if response.reason == reasonCodes.NOT_IN_RAID then
            return L.StrRollOutTag
        end
        return L.StrRollBlockedTag
    end

    return ""
end
