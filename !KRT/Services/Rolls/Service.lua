-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: emits AddRoll through History; owns countdown facade calls
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Database = feature.Database
local Deformat = feature.Deformat
local Item = feature.Item
local Options = feature.Options
local Services = feature.Services
local Strings = feature.Strings

local rollTypes = feature.rollTypes

local lootState = feature.lootState or {}
feature.lootState = lootState
lootState.lootCount = tonumber(lootState.lootCount) or 0
lootState.rollsCount = tonumber(lootState.rollsCount) or 0
lootState.selectedItemCount = tonumber(lootState.selectedItemCount) or 1
if lootState.selectedItemCount < 1 then
    lootState.selectedItemCount = 1
end
lootState.itemTraded = tonumber(lootState.itemTraded) or 0
lootState.currentRollItem = tonumber(lootState.currentRollItem) or 0
if lootState.fromInventory == nil then
    lootState.fromInventory = false
end

local GetItem

local GetItemIndex = feature.GetItemIndex

local tconcat = table.concat

local tostring, tonumber = tostring, tonumber
local upper = string.upper

local function getReserveCountForItem(itemId, name)
    local reserves = Services.Reserves
    if reserves and reserves.GetReserveCountForItem then
        return reserves:GetReserveCountForItem(itemId, name) or 0
    end
    return 0
end

local function getPlusForItem(itemId, name)
    local reserves = Services.Reserves
    if reserves and reserves.GetPlusForItem then
        return reserves:GetPlusForItem(itemId, name) or 0
    end
    return 0
end

local function getItemReserveContext(itemId)
    local reserves = Services.Reserves
    if reserves and reserves.GetItemReserveContext then
        return reserves:GetItemReserveContext(itemId)
    end
    return nil
end

local function isPlusSystemEnabled()
    local reserves = Services.Reserves
    if reserves and reserves.GetPlusForItem and reserves.GetImportMode and reserves.IsPlusSystem then
        return reserves:IsPlusSystem() == true
    end
    return false
end

local function getRaidService()
    return Services.Raid
end

GetItem = function(i)
    local loot = Services.Loot
    return loot and loot.GetItem and loot.GetItem(i) or nil
end

-- =========== Rolls Helpers Module  =========== --
-- Manages roll tracking, response state, and winner determination.
do
    feature.EnsureServiceNamespace("Rolls")
    local Rolls = Services.Rolls
    local module = Rolls

    -- Namespace registration: options that control countdown and roll-response policy.
    Options.AddNamespace("Rolls", {
        countdownDuration = 5,
        countdownSimpleRaidMsg = false,
        countdownRollsBlock = true,
    })

    local Countdown = assert(module._Countdown, "Rolls countdown helpers are not initialized")
    local Sessions = assert(module._Sessions, "Rolls session helpers are not initialized")
    local History = assert(module._History, "Rolls history helpers are not initialized")
    local Responses = assert(module._Responses, "Rolls response helpers are not initialized")
    local Strategies = assert(module._Strategies, "Rolls strategy helpers are not initialized")
    local Display = assert(module._Display, "Rolls display helpers are not initialized")
    local reasonCodes = Responses.REASONS
    -- ----- Internal state ----- --
    local state = {
        record = false,
        canRoll = true,
        warned = false,
        rolled = false,
        rolls = {},
        responsesByPlayer = {},
        deniedReasons = {},
        playerCounts = {},
        itemCounts = nil,
        count = 0,
        resolution = nil,
        sessionId = nil,
        manualExclusions = {},
        tieReroll = nil,
        countdownRunning = false,
        countdownDuration = 0,
        countdownRemaining = 0,
        countdownExpired = false,
        countdownTicker = nil,
        countdownEndTimer = nil,
    }
    local newItemCounts, delItemCounts
    if addon.TablePool then
        newItemCounts, delItemCounts = addon.TablePool("k")
    end
    state.itemCounts = newItemCounts and newItemCounts() or {}

    -- ----- Private helpers ----- --
    local function isDebugEnabled()
        return addon.hasDebug ~= nil
    end

    local function getOption(namespace, key)
        local cfg = Options and Options.Get and Options.Get(namespace)
        if cfg and cfg.Get then
            return cfg:Get(key)
        end
        return nil
    end

    -- ============================================================================
    -- Session helpers
    -- ============================================================================
    local sessionsContext
    local getCurrentRollItemID

    local function getSessionsContext()
        if sessionsContext then
            return sessionsContext
        end

        sessionsContext = {
            state = state,
            lootState = lootState,
            getItem = GetItem,
            getItemIndex = GetItemIndex,
            getCurrentRollItemID = function()
                return getCurrentRollItemID()
            end,
        }
        return sessionsContext
    end

    local function getRollSession()
        return Sessions.GetRollSession(getSessionsContext())
    end

    local function clearTieRerollFilter()
        Sessions.ClearTieRerollFilter(getSessionsContext())
    end

    local function setTieRerollFilter(names)
        return Sessions.SetTieRerollFilter(getSessionsContext(), names)
    end

    local function isTieRerollRestricted(name)
        return Sessions.IsTieRerollRestricted(getSessionsContext(), name)
    end

    local function getManualExclusionEntry(name)
        return Sessions.GetManualExclusionEntry(getSessionsContext(), name)
    end

    local getManualExclusionKey = assert(Sessions._NormalizeCandidateKey, "Rolls session candidate-key normalizer is not initialized")

    local function getActiveRollType()
        return Sessions.GetActiveRollType(getSessionsContext())
    end

    local function getCurrentItemLink()
        return Sessions.GetCurrentItemLink(getSessionsContext())
    end

    local function syncSessionStateFromRollSession(session)
        Sessions.SyncSessionState(getSessionsContext(), session)
    end

    local function normalizeExpectedWinners(count)
        return Sessions.NormalizeExpectedWinners(getSessionsContext(), count)
    end

    local function ensureAdHocRollSession()
        return Sessions.EnsureAdHocRollSession(getSessionsContext())
    end

    local function ensureRollSession(itemLink, rollType, source)
        return Sessions.EnsureRollSession(getSessionsContext(), itemLink, rollType, source)
    end

    local function updateSessionRollWindow(opened)
        Sessions.UpdateSessionRollWindow(getSessionsContext(), opened)
    end

    local function closeRollSession()
        Sessions.CloseRollSession(getSessionsContext())
    end

    local function getExpectedWinnerCount()
        return Sessions.GetExpectedWinnerCount(getSessionsContext())
    end

    local function getCurrentRollContext(itemLink, rollType)
        return Sessions.GetCurrentRollContext(getSessionsContext(), itemLink, rollType)
    end

    -- ============================================================================
    -- Eligibility helpers
    -- ============================================================================
    local historyContext
    getCurrentRollItemID = function()
        local session = getRollSession()
        local sessionItemId = session and tonumber(session.itemId) or nil
        if sessionItemId and sessionItemId > 0 then
            if isDebugEnabled() then
                addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(sessionItemId)))
            end
            return sessionItemId
        end

        local index = GetItemIndex()
        local item = GetItem and GetItem(index)
        local itemLink = item and item.itemLink
        if not itemLink then
            return nil
        end
        local itemId = Item.GetItemIdFromLink(itemLink)
        if itemId and session then
            session.itemId = itemId
            session.itemLink = itemLink
            session.itemKey = Item.GetItemStringFromLink(itemLink) or itemLink
        end
        if isDebugEnabled() then
            addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(itemId)))
        end
        return itemId
    end

    local function getHistoryContext()
        if historyContext then
            return historyContext
        end

        historyContext = {
            state = state,
            lootState = lootState,
            newItemCounts = newItemCounts,
            delItemCounts = delItemCounts,
            getActiveRollType = getActiveRollType,
            getReserveCountForItem = getReserveCountForItem,
            getCurrentWinner = function()
                return lootState.winner
            end,
            getCurrentRollItemID = function()
                return getCurrentRollItemID()
            end,
            getResponseBestRoll = function(name)
                local response = state.responsesByPlayer[name]
                return response and response.bestRoll or nil
            end,
            isSortAscending = function()
                return getOption("Master", "sortAscending") == true
            end,
        }
        return historyContext
    end

    local function getAllowedRolls(itemId, name)
        return History.GetAllowedRolls(getHistoryContext(), itemId, name)
    end

    local function getLocalPlayerRollCount(itemId)
        return History.GetLocalPlayerRollCount(getHistoryContext(), itemId)
    end

    local function incrementLocalPlayerRollCount(itemId)
        return History.IncrementLocalPlayerRollCount(getHistoryContext(), itemId)
    end

    local function updateLocalRollState(itemId, name)
        return History.UpdateLocalRollState(getHistoryContext(), itemId, name)
    end

    local function acquireItemTracker(itemId)
        return History.AcquireItemTracker(getHistoryContext(), itemId)
    end

    local function getRollTypeBucket(rollType)
        if rollType == rollTypes.MAINSPEC then
            return "MS"
        end
        if rollType == rollTypes.OFFSPEC then
            return "OS"
        end
        return "FREE"
    end

    -- ============================================================================
    -- Response lifecycle / transitions
    -- ============================================================================
    local responseContext

    local function getResponsesContext()
        if responseContext then
            return responseContext
        end

        responseContext = {
            state = state,
            getRollSession = getRollSession,
            clearTieRerollFilter = clearTieRerollFilter,
            getActiveRollType = getActiveRollType,
            getCurrentItemLink = getCurrentItemLink,
            getCurrentRollItemID = function()
                return getCurrentRollItemID()
            end,
            getReserveCountForItem = getReserveCountForItem,
            getRollTypeBucket = getRollTypeBucket,
            acquireItemTracker = acquireItemTracker,
            getManualExclusionEntry = getManualExclusionEntry,
            isTieRerollRestricted = isTieRerollRestricted,
            getRaidService = getRaidService,
            getCurrentRollContext = getCurrentRollContext,
            getLootCount = function()
                return tonumber(lootState.lootCount) or 0
            end,
            addRoll = function(name, roll, itemId)
                return History.AddRoll(getHistoryContext(), name, roll, itemId)
            end,
        }
        return responseContext
    end

    local function clearResponseState(opts)
        return Responses.ClearResponseState(getResponsesContext(), opts)
    end

    local function ensureResponseSession()
        return Responses.EnsureResponseSession(getResponsesContext())
    end

    local function buildCandidateEligibility(name, itemId, itemLink, rollType, opts)
        return Responses.BuildCandidateEligibility(getResponsesContext(), name, itemId, itemLink, rollType, opts)
    end

    local function prepareResponseState(context, opts)
        return Responses.PrepareResponseState(getResponsesContext(), context, opts)
    end

    local function refreshMaterializedResponses(itemId, itemLink, rollType)
        return Responses.RefreshMaterializedResponses(getResponsesContext(), itemId, itemLink, rollType)
    end

    local function finalizeMaterializedResponses(itemId, itemLink, rollType)
        return Responses.FinalizeMaterializedResponses(getResponsesContext(), itemId, itemLink, rollType)
    end

    local function submitExplicitResponse(name, status, reason, source)
        return Responses.SubmitExplicitResponse(getResponsesContext(), name, status, reason, source)
    end

    local function submitIncomingRoll(player, roll, source)
        return Responses.SubmitIncomingRoll(getResponsesContext(), player, roll, source)
    end

    -- ============================================================================
    -- Display model / winner policy
    -- ============================================================================
    local displayContext

    local function getDisplayContext()
        if displayContext then
            return displayContext
        end

        displayContext = {
            state = state,
            lootState = lootState,
            rollTypes = rollTypes,
            getCurrentRollContext = getCurrentRollContext,
            prepareResponseState = prepareResponseState,
            refreshMaterializedResponses = refreshMaterializedResponses,
            finalizeMaterializedResponses = finalizeMaterializedResponses,
            strategyHelpers = Strategies,
            getExpectedWinnerCount = getExpectedWinnerCount,
            getPlusForItem = getPlusForItem,
            isPlusSystemEnabled = isPlusSystemEnabled,
            isSortAscending = function()
                return getOption("Master", "sortAscending") == true
            end,
            shouldShowLootCounterDuringMSRoll = function()
                return getOption("LootCounter", "showLootCounterDuringMSRoll") == true
            end,
            getRaidService = getRaidService,
            getItemReserveContext = getItemReserveContext,
            getCurrentRaid = function()
                return Database.GetCurrentRaid and Database.GetCurrentRaid() or nil
            end,
            getSourceRollType = function()
                return state.tieReroll and state.tieReroll.sourceRollType or getActiveRollType()
            end,
        }
        return displayContext
    end

    -- ============================================================================
    -- Submission / session mutations
    -- ============================================================================
    local function clearRollEntries()
        History.ClearRollEntries(getHistoryContext())
    end

    local function resetRolls()
        clearRollEntries()
        clearResponseState()
        state.rolled = false
        state.warned = false
        state.canRoll = false
        state.countdownExpired = false

        lootState.winner = nil
        lootState.rollWinner = nil
        lootState.rollsCount = 0
        lootState.itemTraded = 0
        lootState.rollStarted = false
        closeRollSession()
        state.record = false
    end

    -- ----- Public methods ----- --
    function module:Roll(_btn)
        local itemId = getCurrentRollItemID()
        if not itemId then
            return
        end

        local name = Database.GetPlayerName()
        local allowed = getAllowedRolls(itemId, name)
        local used = getLocalPlayerRollCount(itemId)

        if used >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            if isDebugEnabled() then
                addon:debug(Diag.D.LogRollsBlockedPlayer:format(name, used, allowed))
            end
            return
        end

        RandomRoll(1, 100)
        incrementLocalPlayerRollCount(itemId)
        updateLocalRollState(itemId, name)
        if isDebugEnabled() then
            addon:debug(Diag.D.LogRollsPlayerRolled:format(name, itemId))
        end
    end

    function module:GetRollStatus()
        local itemId = getCurrentRollItemID()
        local name = Database.GetPlayerName()
        updateLocalRollState(itemId, name)
        return getActiveRollType(), state.record, state.canRoll, state.rolled
    end

    function module:SetRollRecordingEnabled(bool)
        local on = (bool == true)
        state.canRoll = on
        state.record = on

        if on then
            -- Starting intake always reopens the roll-started UI state, even when
            -- the session was materialized earlier by the service bootstrap.
            lootState.rollStarted = true
            ensureAdHocRollSession()
            ensureResponseSession()
            state.warned = false
            state.countdownExpired = false

            -- Reset only if we are starting a clean session
            if state.count == 0 then
                lootState.winner = nil
                lootState.rollWinner = nil
            end
        else
            local context = getCurrentRollContext()
            prepareResponseState(context)
            finalizeMaterializedResponses(context.itemId, context.itemLink, context.rollType)
        end
        updateSessionRollWindow(on)

        if isDebugEnabled() then
            addon:debug(Diag.D.LogRollsRecordState:format(tostring(bool)))
        end
    end

    function module:CHAT_MSG_SYSTEM(msg)
        if not msg or not state.record then
            return
        end
        local player, roll, min, max = Deformat(msg, RANDOM_ROLL_RESULT)
        if not player or not roll or min ~= 1 or max ~= 100 then
            return
        end
        submitIncomingRoll(player, roll, "system_roll")
    end

    function module:SubmitDebugRoll(name, roll)
        local player = Strings.NormalizeName(name, true)
        local value = tonumber(roll)

        if not player or player == "" then
            return false, reasonCodes.INVALID_PLAYER
        end
        if not value or value < 1 or value > 100 then
            return false, reasonCodes.INVALID_ROLL
        end

        return submitIncomingRoll(player, value, "debug_roll")
    end

    function module:GetCandidateEligibility(name, itemLink, rollType, opts)
        local itemId = Item and Item.GetItemIdFromLink and Item.GetItemIdFromLink(itemLink) or nil
        return buildCandidateEligibility(name, itemId, itemLink, rollType, opts)
    end

    function module:SetManualExclusion(name, excluded, reason)
        local key = getManualExclusionKey(name)
        if not key then
            return false
        end

        if excluded == false or excluded == nil then
            state.manualExclusions[key] = nil
            return true
        end

        state.manualExclusions[key] = {
            name = Strings.NormalizeName and Strings.NormalizeName(name, true) or name,
            reason = reason or reasonCodes.MANUAL_EXCLUSION,
        }
        return true
    end

    function module:SetPlayerResponse(name, status)
        local responseStatus = type(status) == "string" and upper(status) or status
        if responseStatus == Responses.STATUS.PASS then
            return submitExplicitResponse(name, Responses.STATUS.PASS, reasonCodes.PLAYER_PASS, "player_pass")
        end
        if responseStatus == Responses.STATUS.CANCELLED or responseStatus == "CANCEL" then
            return submitExplicitResponse(name, Responses.STATUS.CANCELLED, reasonCodes.PLAYER_CANCEL, "player_cancel")
        end
        return false, reasonCodes.STATE_TRANSITION_DENIED
    end

    function module:GetRolls()
        return History.GetRolls(getHistoryContext())
    end

    function module:GetHighestRoll(name)
        return History.GetHighestRoll(getHistoryContext(), name)
    end

    function module:ClearRolls(_rec)
        resetRolls()
        local raid = Services.Raid
        if raid and raid.ClearRaidIcons then
            raid:ClearRaidIcons()
        end
    end

    function module:BeginTieReroll(names)
        local session = getRollSession() or ensureAdHocRollSession()
        local reroll
        local itemId
        local itemLink
        local currentRollType

        if not session then
            return false
        end
        ensureResponseSession()

        reroll = setTieRerollFilter(names)
        if not (reroll and reroll.ordered and #reroll.ordered > 1) then
            return false
        end

        itemId = getCurrentRollItemID()
        itemLink = getCurrentItemLink()
        currentRollType = getActiveRollType()
        reroll.sourceRollType = currentRollType

        clearRollEntries()
        clearResponseState({
            preserveManualExclusions = true,
            preserveTieReroll = true,
        })
        state.sessionId = tostring(session.id)
        state.rolled = false
        state.warned = false
        state.record = true
        state.canRoll = true
        state.countdownExpired = false

        lootState.winner = nil
        lootState.rollWinner = nil
        lootState.rollsCount = 0
        lootState.itemTraded = 0
        lootState.rollStarted = true

        session.active = true
        session.endsAt = nil
        updateSessionRollWindow(true)
        prepareResponseState({
            itemId = itemId,
            itemLink = itemLink,
            rollType = currentRollType,
        }, {
            seedReserved = false,
            seedTieReroll = true,
        })

        if isDebugEnabled() then
            addon:debug(Diag.D.LogRollsTieReroll:format(tostring(itemLink), tconcat(reroll.ordered, ",")))
        end
        module:GetDisplayModel()
        return true, reroll.ordered
    end

    function module:ValidateWinner(playerName, itemLink, rollType)
        return Responses.ValidateWinner(getResponsesContext(), playerName, itemLink, rollType)
    end

    -- Public display-model contract for controller/UI consumers. The returned
    -- `resolution` table is a stable part of this API, not an internal detail.
    function module:GetDisplayModel()
        return Display.BuildModel(getDisplayContext())
    end

    function module:GetRollSession()
        return getRollSession()
    end

    function module:SetExpectedWinners(count)
        local session = getRollSession()
        if not session then
            return nil
        end
        session.expectedWinners = normalizeExpectedWinners(count)
        return session.expectedWinners
    end

    function module:EnsureRollSession(itemLink, rollType, source)
        return ensureRollSession(itemLink, rollType, source)
    end

    function module:SyncSessionState(session)
        syncSessionStateFromRollSession(session or getRollSession())
    end

    function module:GetResolvedWinner(model)
        return Display.GetResolvedWinner(getDisplayContext(), model)
    end

    function module:ShouldUseTieReroll(model)
        return Display.ShouldUseTieReroll(getDisplayContext(), model)
    end

    function module:StopCountdown()
        Countdown.Stop(state)
    end

    function module:StartCountdown(duration, onTick, onComplete)
        return Countdown.Start(state, duration, onTick, onComplete)
    end

    function module:IsCountdownRunning()
        return Countdown.IsRunning(state)
    end

    function module:FinalizeRollSession()
        module:SetRollRecordingEnabled(false)
        module:StopCountdown()
        module:GetDisplayModel()
    end
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Rolls/Service", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Item",
            "Modules/Strings",
            "Services/Rolls/Countdown",
            "Services/Rolls/Sessions",
            "Services/Rolls/History",
            "Services/Rolls/Responses",
            "Services/Rolls/Strategies",
            "Services/Rolls/Resolution",
            "Services/Rolls/Display",
        },
    })
    registry.SetLoaded("Services/Rolls/Service")
end
