-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Rolls._Display
-- events: none
-- notes: display-model helpers for rolls service

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local rollTypes = feature.rollTypes

local sort = table.sort
local pairs = pairs
local tostring, tonumber = tostring, tonumber

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Rolls")
local Rolls = Services.Rolls
local module = Rolls
module._Display = module._Display or {}

local Display = module._Display
local Resolution = assert(module._Resolution, "Rolls resolution helpers are not initialized")
local Responses = assert(module._Responses, "Rolls response helpers are not initialized")
local Strategies = assert(module._Strategies, "Rolls strategy helpers are not initialized")

-- ----- Private helpers ----- --
local function assertContext(ctx)
    assert(type(ctx) == "table", "Rolls display context is required")
    assert(type(ctx.state) == "table", "Rolls display state is required")
    assert(type(ctx.lootState) == "table", "Rolls display loot state is required")
    assert(type(ctx.getCurrentRollContext) == "function", "Rolls display current-roll context is required")
    return ctx, ctx.state, ctx.lootState
end

local function getResolutionContext(ctx)
    if ctx._resolutionContext then
        return ctx._resolutionContext
    end

    ctx._resolutionContext = {
        state = ctx.state,
        rollTypes = ctx.rollTypes or rollTypes,
        responseStatus = Responses.STATUS,
        reasonCodes = Responses.REASONS,
        isSelectableRollResponse = ctx.isSelectableRollResponse or Responses.IsSelectableRollResponse,
        getExpectedWinnerCount = ctx.getExpectedWinnerCount,
        getPlusForItem = ctx.getPlusForItem,
        isPlusSystemEnabled = ctx.isPlusSystemEnabled,
        isSortAscending = ctx.isSortAscending,
        shouldShowLootCounterDuringMSRoll = ctx.shouldShowLootCounterDuringMSRoll,
        getRaidService = ctx.getRaidService,
        getCurrentRaid = ctx.getCurrentRaid,
    }
    return ctx._resolutionContext
end

local function copyNames(names)
    local out = {}
    for i = 1, #(names or {}) do
        out[i] = names[i]
    end
    return out
end

local function buildResolvedEntries(ctx, itemId, currentRollType)
    return Resolution.BuildResolvedEntries(ctx, itemId, currentRollType)
end

local function getResponsePlus(strategy, itemId, response, plusGetter)
    return Strategies.GetResponsePlus(strategy, itemId, response, plusGetter)
end

local function buildSrContext(ctx, itemId, currentRollType)
    if currentRollType ~= rollTypes.RESERVED or not itemId or not ctx.getItemReserveContext then
        return nil
    end

    local reserveContext = ctx.getItemReserveContext(itemId)
    if type(reserveContext) ~= "table" then
        return nil
    end

    return {
        itemId = reserveContext.itemId or itemId,
        hasReserves = reserveContext.hasReserves == true,
        hasEligibleReserve = reserveContext.hasPresentReserve == true,
        totalReserveCount = tonumber(reserveContext.totalReserveCount) or 0,
        eligibleReserveCount = tonumber(reserveContext.presentReserveCount) or 0,
        missingReserveCount = tonumber(reserveContext.missingReserveCount) or 0,
        eligibleReserveNames = copyNames(reserveContext.presentPlayers),
        missingReserveNames = copyNames(reserveContext.missingPlayers),
        eligibleReserveText = reserveContext.presentPlayersText or "",
        missingReserveText = reserveContext.missingPlayersText or "",
        rosterFilterApplied = reserveContext.rosterFilterApplied == true,
    }
end

-- ----- Public methods ----- --
function Display.BuildModel(ctx)
    local _, state, lootState = assertContext(ctx)
    local context = ctx.getCurrentRollContext()
    local itemId = context.itemId
    local itemLink = context.itemLink
    local currentRollType = context.rollType
    local resolutionContext = getResolutionContext(ctx)
    local isSR = currentRollType == rollTypes.RESERVED
    local wantLow = ctx.isSortAscending and ctx.isSortAscending() or false
    local display = {}
    local rows = {}
    local resolvedEntries
    local strategy
    local usePlus
    local plusGetter
    local tieGroups
    local resolution
    local multiAward
    local selectionAllowed
    local raid = ctx.getRaidService and ctx.getRaidService() or nil
    local srContext = buildSrContext(ctx, itemId, currentRollType)
    local outOfFlowCount = 0

    if ctx.prepareResponseState then
        ctx.prepareResponseState(context, {
            seedTieReroll = true,
        })
    end
    if ctx.refreshMaterializedResponses then
        ctx.refreshMaterializedResponses(itemId, itemLink, currentRollType)
    end
    if state.canRoll == false and ctx.finalizeMaterializedResponses then
        ctx.finalizeMaterializedResponses(itemId, itemLink, currentRollType)
    end

    resolvedEntries, strategy, plusGetter = buildResolvedEntries(resolutionContext, itemId, currentRollType)
    usePlus = strategy and strategy.usePlus == true
    tieGroups = Resolution.BuildTieGroups(resolutionContext, resolvedEntries, strategy)
    resolution = Resolution.BuildResolution(resolutionContext, resolvedEntries, strategy)
    state.resolution = resolution
    lootState.rollWinner = resolution.topRollName

    for name, response in pairs(state.responsesByPlayer) do
        display[#display + 1] = {
            name = name,
            response = response,
            bucket = response.bucket,
            bucketPriority = Resolution.GetBucketPriority(strategy, response.bucket, currentRollType),
            plus = getResponsePlus(strategy, itemId, response, plusGetter),
            roll = tonumber(response.bestRoll),
            isTied = tieGroups[name] ~= nil,
            tieGroup = tieGroups[name],
            displayTier = Resolution.GetDisplayTier(resolutionContext, response),
        }
    end

    sort(display, function(a, b)
        if a.displayTier ~= b.displayTier then
            return a.displayTier < b.displayTier
        end

        if a.bucketPriority ~= b.bucketPriority then
            return a.bucketPriority < b.bucketPriority
        end

        if usePlus and a.bucket == "SR" and b.bucket == "SR" and a.plus ~= b.plus then
            return a.plus > b.plus
        end

        if a.roll ~= nil and b.roll ~= nil and a.roll ~= b.roll then
            return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
        end

        if a.roll ~= nil and b.roll == nil then
            return true
        end
        if a.roll == nil and b.roll ~= nil then
            return false
        end

        return tostring(a.name) < tostring(b.name)
    end)

    multiAward = lootState.multiAward
    selectionAllowed = (state.canRoll == false or state.countdownExpired == true) and not (multiAward and multiAward.active)

    for i = 1, #display do
        local entry = display[i]
        local response = entry.response
        local name = entry.name
        local roll = entry.roll

        rows[i] = {
            id = i,
            name = name,
            roll = roll,
            class = (raid and raid.GetPlayerClass and raid:GetPlayerClass(name) or "UNKNOWN"):upper(),
            isReserved = response.bucket == "SR",
            counterText = Resolution.BuildRowCounterText(resolutionContext, itemId, response, currentRollType, plusGetter),
            infoText = Resolution.BuildRowInfoText(resolutionContext, response, entry.isTied),
            status = response.status,
            explicitStatus = response.explicitStatus,
            hasExplicitResponse = Responses.IsExplicitResponseStatus(response.explicitStatus),
            bucket = response.bucket,
            reason = response.reason,
            outOfFlowReason = response.outOfFlowReason,
            outOfFlowCount = tonumber(response.outOfFlowCount) or 0,
            outOfFlowLastRoll = tonumber(response.outOfFlowLastRoll),
            outOfFlowLastReason = response.outOfFlowLastReason,
            outOfFlowLastSource = response.outOfFlowLastSource,
            isEligible = response.isEligible == true,
            isTied = entry.isTied and true or false,
            tieGroup = entry.tieGroup,
            selectionAllowed = Responses.IsSelectableRollResponse(response),
        }
        outOfFlowCount = outOfFlowCount + (tonumber(response.outOfFlowCount) or 0)
    end

    return {
        itemId = itemId,
        isSR = isSR and true or false,
        rows = rows,
        selectionAllowed = selectionAllowed and true or false,
        rollWinner = lootState.rollWinner,
        resolution = resolution,
        requiredWinnerCount = ctx.getExpectedWinnerCount and ctx.getExpectedWinnerCount() or 1,
        winnerSuggestions = resolution.autoWinners,
        countdownExpired = state.countdownExpired == true,
        srContext = srContext,
        outOfFlowCount = outOfFlowCount,
    }
end

function Display.GetResolvedWinner(ctx, model)
    local _, _, lootState = assertContext(ctx)
    local activeModel = model or Display.BuildModel(ctx)
    if activeModel then
        return activeModel.winner or activeModel.rollWinner or (activeModel.resolution and activeModel.resolution.topRollName) or lootState.winner
    end
    return lootState.winner
end

function Display.ShouldUseTieReroll(ctx, model)
    local activeModel = model or Display.BuildModel(ctx)
    local resolution = activeModel and activeModel.resolution or nil
    local requiredWinnerCount = tonumber(activeModel and activeModel.requiredWinnerCount) or 1
    local selectedCount = tonumber(activeModel and activeModel.msCount) or 0

    return resolution and resolution.requiresManualResolution == true and requiredWinnerCount == 1 and selectedCount <= 0
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Rolls/Display", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Services/Rolls/Responses",
            "Services/Rolls/Resolution",
        },
    })
    registry.SetLoaded("Services/Rolls/Display")
end
