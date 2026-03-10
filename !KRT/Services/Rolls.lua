-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Events = feature.Events or addon.Events or {}
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Item = feature.Item or addon.Item
local Strings = feature.Strings or addon.Strings
local Comms = feature.Comms or addon.Comms
local Services = feature.Services or addon.Services or {}

local rollTypes = feature.rollTypes

local lootState = feature.lootState

local InternalEvents = Events.Internal

local GetItem

local GetItemIndex = feature.GetItemIndex

local tconcat, twipe = table.concat, table.wipe
local pairs, next = pairs, next
local format = string.format

local tostring, tonumber = tostring, tonumber

local function getLootModule()
    return Services.Loot
end

local function getRaidService()
    return Services.Raid
end

local function getReservesService()
    return Services.Reserves
end

local function getReserveCountForItem(itemId, name)
    local reserves = getReservesService()
    if reserves and reserves.GetReserveCountForItem then
        return reserves:GetReserveCountForItem(itemId, name) or 0
    end
    return 0
end

local function getPlusForItem(itemId, name)
    local reserves = getReservesService()
    if reserves and reserves.GetPlusForItem then
        return reserves:GetPlusForItem(itemId, name) or 0
    end
    return 0
end

local function isPlusSystemEnabled()
    local reserves = getReservesService()
    if reserves and reserves.GetPlusForItem and reserves.GetImportMode and reserves.IsPlusSystem then
        return reserves:IsPlusSystem()
    end
    return false
end

GetItem = function(i)
    local loot = getLootModule()
    return loot and loot.GetItem and loot.GetItem(i) or nil
end

-- =========== Rolls Helpers Module  =========== --
-- Manages roll tracking, response state, and winner determination.
do
    addon.Services = addon.Services or {}
    addon.Services.Rolls = addon.Services.Rolls or {}
    local module = addon.Services.Rolls
    --[[
    Response state machine

    Meaning:
      ACTIVE      = eligible/known participant with no final explicit response yet
      ROLL        = active valid roll response
      PASS        = player explicitly passed on the item
      CANCELLED   = player explicitly withdrew a previous response
      TIMED_OUT   = response window expired for this player/session
      INELIGIBLE  = player is not currently eligible for this session

    General rules:
      - Only ROLL responses can be considered by the resolver.
      - PASS, CANCELLED, TIMED_OUT, INELIGIBLE are never resolver candidates.
      - State changes are only allowed while the session is open, except automatic
        eligibility refresh transitions.
      - PASS is reversible while the session remains open.
      - CANCELLED is reversible while the session remains open.
      - TIMED_OUT is terminal for the current session.
      - INELIGIBLE may recover only through eligibility refresh while the session
        remains open.
    ]]
    local RESPONSE_STATUS = {
        ACTIVE = "ACTIVE",
        ROLL = "ROLL",
        PASS = "PASS",
        CANCELLED = "CANCELLED",
        TIMED_OUT = "TIMED_OUT",
        INELIGIBLE = "INELIGIBLE",
    }
    local RESPONSE_TRANSITIONS = {
        [RESPONSE_STATUS.ACTIVE] = {
            [RESPONSE_STATUS.ACTIVE] = true,
            [RESPONSE_STATUS.ROLL] = true,
            [RESPONSE_STATUS.PASS] = true,
            [RESPONSE_STATUS.TIMED_OUT] = true,
            [RESPONSE_STATUS.INELIGIBLE] = true,
        },
        [RESPONSE_STATUS.ROLL] = {
            [RESPONSE_STATUS.ROLL] = true,
            [RESPONSE_STATUS.PASS] = true,
            [RESPONSE_STATUS.CANCELLED] = true,
            [RESPONSE_STATUS.INELIGIBLE] = true,
        },
        [RESPONSE_STATUS.PASS] = {
            [RESPONSE_STATUS.PASS] = true,
            [RESPONSE_STATUS.ROLL] = true,
            [RESPONSE_STATUS.CANCELLED] = true,
            [RESPONSE_STATUS.INELIGIBLE] = true,
        },
        [RESPONSE_STATUS.CANCELLED] = {
            [RESPONSE_STATUS.CANCELLED] = true,
            [RESPONSE_STATUS.ROLL] = true,
            [RESPONSE_STATUS.PASS] = true,
            [RESPONSE_STATUS.INELIGIBLE] = true,
        },
        [RESPONSE_STATUS.TIMED_OUT] = {
            [RESPONSE_STATUS.TIMED_OUT] = true,
        },
        [RESPONSE_STATUS.INELIGIBLE] = {
            [RESPONSE_STATUS.INELIGIBLE] = true,
            [RESPONSE_STATUS.ACTIVE] = true,
            [RESPONSE_STATUS.ROLL] = true,
        },
    }
    local reasonCodes = {
        ELIGIBLE = "eligible",
        RESERVED = "reserved",
        FALLBACK = "fallback",
        INELIGIBLE = "ineligible",
        UNINITIALIZED = "uninitialized",
        NAME_UNRESOLVED = "name_unresolved",
        MISSING_ITEM = "missing_item",
        NOT_IN_RAID = "not_in_raid",
        MANUAL_EXCLUSION = "manual_exclusion",
        REROLL_FILTERED = "reroll_filtered",
        SESSION_INACTIVE = "session_inactive",
        ROLL_LIMIT = "roll_limit",
        PLAYER_PASS = "player_pass",
        PLAYER_CANCEL = "player_cancel",
        TIMED_OUT = "timed_out",
        MISSING_ROLL_RESPONSE = "missing_roll_response",
        NO_ACTIVE_RESPONSE = "no_active_response",
        STATE_TRANSITION_DENIED = "state_transition_denied",
        RECORD_INACTIVE = "record_inactive",
        INVALID_PLAYER = "invalid_player",
        INVALID_ROLL = "invalid_roll",
    }
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
    }
    local newItemCounts, delItemCounts
    if addon.TablePool then
        newItemCounts, delItemCounts = addon.TablePool("k")
    end
    state.itemCounts = newItemCounts and newItemCounts() or {}

    -- ----- Private helpers ----- --

    -- ============================================================================
    -- Session helpers
    -- ============================================================================
    local function getRollSession()
        local session = lootState.rollSession
        if type(session) ~= "table" then
            return nil
        end
        if not session.id or session.id == "" then
            return nil
        end
        return session
    end

    local function normalizeCandidateKey(name)
        local normalized = Strings and Strings.NormalizeLower and Strings.NormalizeLower(name) or nil
        if normalized and normalized ~= "" then
            return normalized
        end
        if type(name) == "string" and name ~= "" then
            return string.lower(name)
        end
        return nil
    end

    local function clearTieRerollFilter()
        state.tieReroll = nil
    end

    local function setTieRerollFilter(names)
        local ordered = {}
        local keyed = {}
        local reroll

        if type(names) ~= "table" then
            clearTieRerollFilter()
            return nil
        end

        for i = 1, #names do
            local name = names[i]
            local key = normalizeCandidateKey(name)
            if key and not keyed[key] then
                ordered[#ordered + 1] = name
                keyed[key] = name
            end
        end

        if #ordered <= 0 then
            clearTieRerollFilter()
            return nil
        end

        reroll = {
            ordered = ordered,
            keyed = keyed,
        }
        state.tieReroll = reroll
        return reroll
    end

    local function isTieRerollRestricted(name)
        local reroll = state.tieReroll
        local key

        if not (reroll and reroll.keyed and next(reroll.keyed)) then
            return false
        end

        key = normalizeCandidateKey(name)
        return not key or reroll.keyed[key] == nil
    end

    local function getManualExclusionEntry(name)
        local key = normalizeCandidateKey(name)
        if not key then
            return nil
        end
        return state.manualExclusions[key]
    end

    local function getActiveRollType()
        local session = getRollSession()
        local rollType = session and tonumber(session.rollType) or tonumber(lootState.currentRollType)
        return rollType or rollTypes.FREE
    end

    local function getCurrentItemLink()
        local session = getRollSession()
        if session and session.itemLink then
            return session.itemLink
        end

        local item = GetItem and GetItem(GetItemIndex())
        return item and item.itemLink or nil
    end

    local function syncSessionStateFromRollSession(session)
        if not session then
            return
        end
        if tonumber(session.rollType) then
            lootState.currentRollType = tonumber(session.rollType)
        end
        if tonumber(session.lootNid) then
            lootState.currentRollItem = tonumber(session.lootNid)
        end
    end

    local function updateSessionRollWindow(opened)
        local session = getRollSession()
        if not session then
            return
        end
        if opened then
            session.endsAt = nil
        elseif session.endsAt == nil then
            session.endsAt = GetTime()
        end
        syncSessionStateFromRollSession(session)
    end

    local function closeRollSession()
        local session = getRollSession()
        if session and session.endsAt == nil then
            session.endsAt = GetTime()
        end
        lootState.rollSession = nil
    end

    local function getSelectionTargetCount()
        local count = tonumber(lootState.selectedItemCount) or 1
        if count < 1 then
            count = 1
        end

        if lootState.fromInventory then
            local traded = tonumber(lootState.itemTraded) or 0
            local remaining = count - traded
            if remaining > 0 then
                count = remaining
            end
        end

        return count
    end

    local function getExpectedWinnerCount()
        local session = getRollSession()
        local count = session and tonumber(session.expectedWinners) or getSelectionTargetCount()
        if not count or count < 1 then
            count = 1
        end
        return count
    end

    -- ============================================================================
    -- Eligibility helpers
    -- ============================================================================
    local function getAllowedRolls(itemId, name)
        if not itemId or not name then
            return 1
        end
        if getActiveRollType() ~= rollTypes.RESERVED then
            return 1
        end
        local reserves = getReserveCountForItem(itemId, name)
        return (reserves and reserves > 0) and reserves or 1
    end

    local function updateLocalRollState(itemId, name)
        if not itemId or not name then
            state.rolled = false
            return false
        end
        local allowed = getAllowedRolls(itemId, name)
        local used = state.playerCounts[itemId] or 0
        state.rolled = used >= allowed
        return state.rolled
    end

    local function acquireItemTracker(itemId)
        local tracker = state.itemCounts
        if not tracker[itemId] then
            tracker[itemId] = newItemCounts and newItemCounts() or {}
        end
        return tracker[itemId]
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

    local function getBucketPriority(bucket, rollType)
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

    -- ============================================================================
    -- Display helpers
    -- ============================================================================
    local function getDisplayTier(response)
        if response.status == RESPONSE_STATUS.ROLL and response.isEligible == true then
            return 1
        end
        if response.bestRoll ~= nil then
            return 2
        end
        if response.status == RESPONSE_STATUS.PASS then
            return 3
        end
        if response.status == RESPONSE_STATUS.CANCELLED then
            return 4
        end
        if response.status == RESPONSE_STATUS.ACTIVE then
            return 5
        end
        if response.status == RESPONSE_STATUS.TIMED_OUT then
            return 6
        end
        return 7
    end

    -- ============================================================================
    -- Response lifecycle / transitions
    -- ============================================================================
    local function isExplicitResponseStatus(status)
        return status == RESPONSE_STATUS.PASS or status == RESPONSE_STATUS.CANCELLED
    end

    local function canTransitionResponseState(fromStatus, toStatus)
        local allowed

        if not toStatus then
            return false
        end

        fromStatus = fromStatus or RESPONSE_STATUS.ACTIVE
        if fromStatus == toStatus then
            return true
        end

        allowed = RESPONSE_TRANSITIONS[fromStatus]
        return allowed and allowed[toStatus] == true or false
    end

    local function getDenialMessage(reason)
        if reason == reasonCodes.NOT_IN_RAID then
            return L.ChatRollNotInRaid
        end
        if reason == reasonCodes.MANUAL_EXCLUSION then
            return L.ChatRollExcluded
        end
        if reason == reasonCodes.ROLL_LIMIT then
            return L.ChatOnlyRollOnce
        end
        if reason == reasonCodes.SESSION_INACTIVE then
            return L.ChatRollInactive
        end
        if reason == reasonCodes.REROLL_FILTERED then
            return L.ChatRollTieOnly
        end
        return nil
    end

    local function getOrCreateResponse(name)
        local response = state.responsesByPlayer[name]
        if response then
            return response
        end

        response = {
            name = name,
            status = RESPONSE_STATUS.ACTIVE,
            explicitStatus = nil,
            bucket = "INELIGIBLE",
            reason = reasonCodes.UNINITIALIZED,
            bestRoll = nil,
            lastRoll = nil,
            usedRolls = 0,
            allowedRolls = 0,
            source = nil,
            updatedAt = nil,
            isEligible = false,
        }
        state.responsesByPlayer[name] = response
        return response
    end

    local function clearResponseState(opts)
        opts = opts or {}
        twipe(state.responsesByPlayer)
        twipe(state.deniedReasons)
        if not opts.preserveManualExclusions then
            twipe(state.manualExclusions)
        end
        if not opts.preserveTieReroll then
            clearTieRerollFilter()
        end
        state.resolution = nil
        state.sessionId = nil
    end

    local function ensureResponseSession()
        local session = getRollSession()
        local sessionId = session and tostring(session.id) or nil
        if state.sessionId == sessionId then
            return session
        end

        clearResponseState()
        state.sessionId = sessionId
        return session
    end

    local function isRollSubmissionOpen()
        return state.record == true and state.canRoll == true
    end

    -- ============================================================================
    -- Eligibility / validation
    -- ============================================================================
    local function buildEligibilityResult(opts, candidateOk, bucket, candidateReason, allowedRolls, usedRolls, itemId, itemLink, canSubmit, submitReason)
        local result = {
            candidateOk = candidateOk == true,
            bucket = bucket or "INELIGIBLE",
            reason = candidateReason,
            allowedRolls = allowedRolls or 0,
            usedRolls = usedRolls or 0,
            itemId = itemId,
            itemLink = itemLink,
        }

        result.canSubmit = result.candidateOk == true and canSubmit ~= false
        result.submitReason = submitReason or candidateReason
        if opts and opts.mode == "submission" then
            result.ok = result.canSubmit == true
            if not result.ok then
                result.reason = result.submitReason
            end
        else
            result.ok = result.candidateOk == true
        end
        return result
    end

    local function getEligibilityBaseReason(currentRollType, bucket)
        if currentRollType == rollTypes.RESERVED then
            return bucket == "SR" and reasonCodes.RESERVED or reasonCodes.FALLBACK
        end
        return reasonCodes.ELIGIBLE
    end

    local function isAwardRollType(rollType)
        return rollType == rollTypes.MAINSPEC or rollType == rollTypes.OFFSPEC or rollType == rollTypes.RESERVED or rollType == rollTypes.FREE
    end

    local function buildCandidateEligibility(name, itemId, itemLink, rollType, opts)
        local currentRollType = tonumber(rollType) or getActiveRollType()
        local currentItemLink = itemLink or getCurrentItemLink()
        local currentItemId = tonumber(itemId)
        local allowedRolls = 1
        local usedRolls = 0
        local bucket = getRollTypeBucket(currentRollType)

        if not currentItemId and currentItemLink then
            currentItemId = Item.GetItemIdFromLink(currentItemLink)
        end
        if not currentItemId then
            currentItemId = module:GetCurrentRollItemID()
        end
        if currentItemId then
            currentItemId = tonumber(currentItemId)
        end

        if currentRollType == rollTypes.RESERVED and currentItemId then
            local reserveCount = getReserveCountForItem(currentItemId, name)
            if reserveCount and reserveCount > 0 then
                bucket = "SR"
                allowedRolls = reserveCount
            else
                bucket = "FREE"
            end
        end

        if not name or name == "" then
            return buildEligibilityResult(opts, false, "INELIGIBLE", reasonCodes.NAME_UNRESOLVED, 0, 0, currentItemId, currentItemLink, false, reasonCodes.NAME_UNRESOLVED)
        end

        if not currentItemId then
            return buildEligibilityResult(opts, false, "INELIGIBLE", reasonCodes.MISSING_ITEM, 0, 0, nil, currentItemLink, false, reasonCodes.MISSING_ITEM)
        end

        local tracker = acquireItemTracker(currentItemId)
        usedRolls = tracker[name] or 0

        if opts and opts.requireOpenSession and not isRollSubmissionOpen() then
            return buildEligibilityResult(
                opts,
                true,
                bucket,
                getEligibilityBaseReason(currentRollType, bucket),
                allowedRolls,
                usedRolls,
                currentItemId,
                currentItemLink,
                false,
                reasonCodes.SESSION_INACTIVE
            )
        end

        local raid = getRaidService()
        local unitId = raid and raid.GetUnitID and raid:GetUnitID(name) or "none"
        local isSyntheticPlayer = raid and raid.IsSyntheticPlayerActive and raid:IsSyntheticPlayerActive(name, Core.GetCurrentRaid and Core.GetCurrentRaid() or nil)
        if (not unitId or unitId == "none") and not isSyntheticPlayer then
            return buildEligibilityResult(opts, false, bucket, reasonCodes.NOT_IN_RAID, allowedRolls, usedRolls, currentItemId, currentItemLink, false, reasonCodes.NOT_IN_RAID)
        end

        local manualExclusion = getManualExclusionEntry(name)
        if manualExclusion then
            return buildEligibilityResult(
                opts,
                false,
                bucket,
                reasonCodes.MANUAL_EXCLUSION,
                allowedRolls,
                usedRolls,
                currentItemId,
                currentItemLink,
                false,
                reasonCodes.MANUAL_EXCLUSION
            )
        end

        if isTieRerollRestricted(name) then
            return buildEligibilityResult(
                opts,
                false,
                bucket,
                reasonCodes.REROLL_FILTERED,
                allowedRolls,
                usedRolls,
                currentItemId,
                currentItemLink,
                false,
                reasonCodes.REROLL_FILTERED
            )
        end

        local candidateReason = getEligibilityBaseReason(currentRollType, bucket)
        local canSubmit = usedRolls < allowedRolls
        local submitReason = canSubmit and candidateReason or reasonCodes.ROLL_LIMIT

        return buildEligibilityResult(opts, true, bucket, candidateReason, allowedRolls, usedRolls, currentItemId, currentItemLink, canSubmit, submitReason)
    end

    local function traceEligibility(name, eligibility)
        addon:debug(
            Diag.D.LogRollsEligibility:format(
                tostring(name),
                tostring(eligibility.ok),
                tostring(eligibility.bucket),
                tostring(eligibility.reason),
                tonumber(eligibility.usedRolls) or 0,
                tonumber(eligibility.allowedRolls) or 0
            )
        )
    end

    local function getAwardValidationMessage(reason, playerName)
        if reason == reasonCodes.NAME_UNRESOLVED then
            return L.ErrMLWinnerNameUnresolved
        end
        if reason == reasonCodes.MANUAL_EXCLUSION then
            return L.ErrMLWinnerExcluded:format(tostring(playerName))
        end
        if reason == reasonCodes.NOT_IN_RAID then
            return L.ErrMLWinnerNotInRaid:format(tostring(playerName))
        end
        if reason == reasonCodes.PLAYER_PASS then
            return L.ErrMLWinnerPassed:format(tostring(playerName))
        end
        if reason == reasonCodes.PLAYER_CANCEL then
            return L.ErrMLWinnerCancelled:format(tostring(playerName))
        end
        if reason == reasonCodes.TIMED_OUT then
            return L.ErrMLWinnerTimedOut:format(tostring(playerName))
        end
        if reason == reasonCodes.MISSING_ROLL_RESPONSE then
            return L.ErrMLWinnerNoRoll:format(tostring(playerName))
        end
        return L.ErrMLWinnerIneligible:format(tostring(playerName))
    end

    local function buildWinnerValidationResult(ok, reason, playerName, eligibility, response)
        return {
            ok = ok == true,
            reason = reason,
            eligibility = eligibility,
            response = response,
            warnMessage = (ok == true) and nil or getAwardValidationMessage(reason, playerName),
        }
    end

    -- ============================================================================
    -- Response materialization / submission
    -- ============================================================================
    -- Resolver candidate rule:
    -- A response participates only when:
    --   status == ROLL
    --   and isEligible == true
    --   and bestRoll ~= nil
    local function isSelectableRollResponse(response)
        return response and response.status == RESPONSE_STATUS.ROLL and response.bestRoll ~= nil and response.isEligible == true
    end

    local function getAwardValidationResponseReason(response, eligibility)
        if eligibility and eligibility.ok ~= true then
            return eligibility.reason or reasonCodes.INELIGIBLE
        end
        if not response then
            return reasonCodes.MISSING_ROLL_RESPONSE
        end
        if response.status == RESPONSE_STATUS.PASS then
            return reasonCodes.PLAYER_PASS
        end
        if response.status == RESPONSE_STATUS.CANCELLED then
            return reasonCodes.PLAYER_CANCEL
        end
        if response.status == RESPONSE_STATUS.TIMED_OUT then
            return reasonCodes.TIMED_OUT
        end
        if response.status == RESPONSE_STATUS.INELIGIBLE then
            return response.reason or (eligibility and eligibility.reason) or reasonCodes.INELIGIBLE
        end
        if not isSelectableRollResponse(response) then
            return response.reason or reasonCodes.MISSING_ROLL_RESPONSE
        end
        return nil
    end

    local function syncResponseEligibility(name, itemId, itemLink, rollType, source)
        local eligibility = buildCandidateEligibility(name, itemId, itemLink, rollType)
        local response = getOrCreateResponse(name)

        response.bucket = eligibility.bucket
        response.allowedRolls = eligibility.allowedRolls
        response.usedRolls = eligibility.usedRolls
        response.isEligible = eligibility.ok == true
        response.name = name
        if source then
            response.source = source
        end
        response.updatedAt = GetTime()

        if response.bestRoll ~= nil then
            response.explicitStatus = nil
            response.status = eligibility.ok and RESPONSE_STATUS.ROLL or RESPONSE_STATUS.INELIGIBLE
            response.reason = eligibility.reason
            return response, eligibility
        end

        if eligibility.ok ~= true then
            if response.status ~= RESPONSE_STATUS.TIMED_OUT then
                response.status = RESPONSE_STATUS.INELIGIBLE
            end
        elseif isExplicitResponseStatus(response.explicitStatus) then
            response.status = response.explicitStatus
        elseif response.status ~= RESPONSE_STATUS.TIMED_OUT then
            response.status = eligibility.ok and RESPONSE_STATUS.ACTIVE or RESPONSE_STATUS.INELIGIBLE
        end

        if response.status == RESPONSE_STATUS.TIMED_OUT then
            response.reason = reasonCodes.TIMED_OUT
        elseif response.status == RESPONSE_STATUS.PASS then
            response.reason = reasonCodes.PLAYER_PASS
        elseif response.status == RESPONSE_STATUS.CANCELLED then
            response.reason = reasonCodes.PLAYER_CANCEL
        else
            response.reason = eligibility.reason
        end

        return response, eligibility
    end

    local function seedReservedCandidates(itemId, itemLink, rollType)
        if not itemId or rollType ~= rollTypes.RESERVED then
            return
        end

        local reserves = getReservesService()
        if not (reserves and reserves.GetPlayersForItem) then
            return
        end

        local players = reserves:GetPlayersForItem(itemId, false, false, false) or {}
        for i = 1, #players do
            local name = players[i]
            if type(name) == "string" and name ~= "" then
                syncResponseEligibility(name, itemId, itemLink, rollType, "reserve_seed")
            end
        end
    end

    local function seedTieRerollCandidates(itemId, itemLink, rollType)
        local reroll = state.tieReroll
        if not (reroll and reroll.ordered) then
            return
        end

        for i = 1, #reroll.ordered do
            local name = reroll.ordered[i]
            if type(name) == "string" and name ~= "" then
                syncResponseEligibility(name, itemId, itemLink, rollType, "tie_reroll")
            end
        end
    end

    local function refreshMaterializedResponses(itemId, itemLink, rollType)
        for name in pairs(state.responsesByPlayer) do
            syncResponseEligibility(name, itemId, itemLink, rollType)
        end
    end

    local function finalizeMaterializedResponses(itemId, itemLink, rollType)
        refreshMaterializedResponses(itemId, itemLink, rollType)
        for name, response in pairs(state.responsesByPlayer) do
            if response.bestRoll == nil and response.status == RESPONSE_STATUS.ACTIVE then
                response.status = RESPONSE_STATUS.TIMED_OUT
                response.reason = reasonCodes.TIMED_OUT
                response.updatedAt = GetTime()
                addon:debug(Diag.D.LogRollsTimedOut:format(tostring(name)))
            end
        end
    end

    local function applyAcceptedRollResponse(name, roll, eligibility, source)
        local response = getOrCreateResponse(name)
        local wantLow = addon.options.sortAscending == true
        local nextUsedRolls = (eligibility and tonumber(eligibility.usedRolls) or 0) + 1

        if response.bestRoll == nil then
            response.bestRoll = roll
        elseif wantLow then
            if roll < response.bestRoll then
                response.bestRoll = roll
            end
        elseif roll > response.bestRoll then
            response.bestRoll = roll
        end

        response.lastRoll = roll
        response.status = RESPONSE_STATUS.ROLL
        response.explicitStatus = nil
        response.bucket = eligibility and eligibility.bucket or response.bucket
        response.reason = eligibility and eligibility.reason or reasonCodes.ELIGIBLE
        response.allowedRolls = eligibility and eligibility.allowedRolls or response.allowedRolls or 0
        response.usedRolls = nextUsedRolls
        response.source = source or "system_roll"
        response.updatedAt = GetTime()
        response.isEligible = true

        addon:debug(Diag.D.LogRollsResponse:format(tostring(name), tostring(response.status), tostring(response.bucket), tostring(response.bestRoll), tostring(response.lastRoll)))
    end

    local function applyExplicitResponse(name, status, eligibility, reason, source)
        local response = getOrCreateResponse(name)

        response.bestRoll = nil
        response.lastRoll = nil
        response.status = status
        response.explicitStatus = status
        response.bucket = eligibility and eligibility.bucket or response.bucket
        response.reason = reason
        response.allowedRolls = eligibility and eligibility.allowedRolls or response.allowedRolls or 0
        response.usedRolls = eligibility and eligibility.usedRolls or response.usedRolls or 0
        response.source = source or reason
        response.updatedAt = GetTime()
        response.isEligible = eligibility and eligibility.ok == true or false

        addon:debug(Diag.D.LogRollsResponse:format(tostring(name), tostring(response.status), tostring(response.bucket), tostring(response.bestRoll), tostring(response.lastRoll)))

        return response
    end

    -- ============================================================================
    -- Resolver
    -- ============================================================================
    local function getResponsePlus(itemId, response, plusGetter)
        if not itemId or response.bucket ~= "SR" or not plusGetter then
            return 0
        end
        return plusGetter(response.name)
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

    local function buildResolvedEntries(itemId, currentRollType)
        local usePlus = currentRollType == rollTypes.RESERVED and itemId and isPlusSystemEnabled()
        local plusGetter = itemId and function(name)
            return getPlusForItem(itemId, name)
        end or nil
        local wantLow = addon.options.sortAscending == true
        local resolved = {}

        for name, response in pairs(state.responsesByPlayer) do
            if isSelectableRollResponse(response) then
                resolved[#resolved + 1] = {
                    name = name,
                    bucket = response.bucket,
                    bucketPriority = getBucketPriority(response.bucket, currentRollType),
                    plus = getResponsePlus(itemId, response, plusGetter),
                    roll = tonumber(response.bestRoll) or 0,
                }
            end
        end

        table.sort(resolved, function(a, b)
            return compareResolvedEntries(a, b, wantLow, usePlus)
        end)

        return resolved, usePlus, plusGetter
    end

    local function buildTieGroups(resolvedEntries, usePlus)
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

    -- Public resolver contract consumed by controller code via GetDisplayModel():
    --   autoWinners               = deterministic winner suggestions above any cutoff tie
    --   tiedNames                 = player names tied across the cutoff boundary
    --   requiresManualResolution  = cutoff tie exists; controller must not auto-award
    --   cutoff                    = expected winner count used for this resolution pass
    --   topRollName               = top-ranked resolver candidate for compatibility/UI
    -- Keep these fields stable; Master consumes them as part of the service API.
    local function buildResolution(resolvedEntries, usePlus)
        local resolution = {
            autoWinners = {},
            tiedNames = {},
            requiresManualResolution = false,
            cutoff = getExpectedWinnerCount(),
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

    -- ============================================================================
    -- Display model builders
    -- ============================================================================
    local function buildRowCounterText(itemId, response, currentRollType, plusGetter)
        local counterText = ""

        if response.bucket == "SR" then
            if currentRollType == rollTypes.RESERVED and itemId and isPlusSystemEnabled() then
                local plus = getResponsePlus(itemId, response, plusGetter)
                if plus and plus > 0 then
                    counterText = format("(P+%d)", plus)
                end
            else
                local allowed = tonumber(response.allowedRolls) or 0
                if allowed > 1 then
                    local used = tonumber(response.usedRolls) or 0
                    counterText = format("(%d/%d)", used, allowed)
                end
            end
        elseif addon.options.showLootCounterDuringMSRoll == true and currentRollType == rollTypes.MAINSPEC then
            local raid = getRaidService()
            local count = raid and raid.GetPlayerCount and raid:GetPlayerCount(response.name, addon.Core.GetCurrentRaid()) or 0
            if count and count > 0 then
                counterText = "+" .. count
            end
        end

        return counterText
    end

    local function buildRowInfoText(response, isTied)
        if isTied then
            return L.StrRollTieTag
        end

        if response.status == RESPONSE_STATUS.PASS then
            return L.StrRollPassTag
        elseif response.status == RESPONSE_STATUS.CANCELLED then
            return L.StrRollCancelledTag
        elseif response.status == RESPONSE_STATUS.TIMED_OUT then
            return L.StrRollTimedOutTag
        elseif response.status == RESPONSE_STATUS.INELIGIBLE then
            if response.reason == reasonCodes.NOT_IN_RAID then
                return L.StrRollOutTag
            end
            return L.StrRollBlockedTag
        end

        return ""
    end

    -- ============================================================================
    -- Submission / session mutations
    -- ============================================================================
    local function submitExplicitResponse(name, status, reason, source)
        local player = (Strings and Strings.NormalizeName and Strings.NormalizeName(name, true)) or name
        local itemId
        local itemLink
        local currentRollType
        local eligibility
        local response

        if not isRollSubmissionOpen() then
            return false, reasonCodes.SESSION_INACTIVE
        end

        if not player or player == "" then
            return false, reasonCodes.NAME_UNRESOLVED
        end

        itemId = module:GetCurrentRollItemID()
        if not itemId or lootState.lootCount == 0 then
            return false, reasonCodes.MISSING_ITEM
        end

        itemLink = getCurrentItemLink()
        currentRollType = getActiveRollType()
        ensureResponseSession()
        seedReservedCandidates(itemId, itemLink, currentRollType)
        eligibility = buildCandidateEligibility(player, itemId, itemLink, currentRollType)
        traceEligibility(player, eligibility)
        if eligibility.ok ~= true then
            state.deniedReasons[player] = eligibility.reason
            return false, eligibility.reason
        end

        response, eligibility = syncResponseEligibility(player, itemId, itemLink, currentRollType, source)
        if status == RESPONSE_STATUS.CANCELLED and not (response and (response.bestRoll ~= nil or isExplicitResponseStatus(response.explicitStatus))) then
            return false, reasonCodes.NO_ACTIVE_RESPONSE
        end
        if not canTransitionResponseState(response and response.status, status) then
            return false, reasonCodes.STATE_TRANSITION_DENIED
        end

        applyExplicitResponse(player, status, eligibility, reason, source)
        return true, nil
    end

    local function clearRollEntries()
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry then
                twipe(entry)
            end
        end
        twipe(state.rolls)
        twipe(state.playerCounts)
        if delItemCounts then
            delItemCounts(state.itemCounts, true)
        end

        state.rolls = {}
        state.playerCounts = {}
        state.itemCounts = newItemCounts and newItemCounts() or {}
        state.count = 0
    end

    local function addRoll(name, roll, itemId)
        local tracker = acquireItemTracker(itemId)

        roll = tonumber(roll)
        state.count = state.count + 1
        lootState.rollsCount = lootState.rollsCount + 1

        state.rolls[state.count] = {
            name = name,
            roll = roll,
            itemId = itemId,
        }

        addon:debug(Diag.D.LogRollsAddEntry:format(name, roll, tostring(itemId)))
        tracker[name] = (tracker[name] or 0) + 1
        Bus.TriggerEvent(InternalEvents.AddRoll, name, roll)
    end

    local function resetRolls()
        clearRollEntries()
        clearResponseState()
        state.rolled = false
        state.warned = false
        state.canRoll = false

        lootState.winner = nil
        lootState.rollWinner = nil
        lootState.rollsCount = 0
        lootState.itemTraded = 0
        lootState.rollStarted = false
        closeRollSession()
        state.record = false
    end

    local function submitIncomingRoll(player, roll, source)
        local itemId
        local itemLink
        local currentRollType
        local eligibility
        local denyMessage
        local denyKey
        local isDebugSource = source == "debug_roll"

        if not state.record then
            return false, reasonCodes.RECORD_INACTIVE
        end

        itemId = module:GetCurrentRollItemID()
        if not itemId or lootState.lootCount == 0 then
            addon:warn(Diag.W.LogRollsMissingItem)
            return false, reasonCodes.MISSING_ITEM
        end

        itemLink = getCurrentItemLink()
        currentRollType = getActiveRollType()

        ensureResponseSession()
        seedReservedCandidates(itemId, itemLink, currentRollType)

        eligibility = buildCandidateEligibility(player, itemId, itemLink, currentRollType, {
            mode = "submission",
            requireOpenSession = true,
        })
        traceEligibility(player, eligibility)
        if not eligibility.ok then
            if eligibility.reason == reasonCodes.SESSION_INACTIVE and not state.warned and not isDebugSource then
                addon:Announce(L.ChatCountdownBlock)
                state.warned = true
            end
            denyMessage = getDenialMessage(eligibility.reason)
            denyKey = tostring(player) .. ":" .. tostring(eligibility.reason)
            if denyMessage and not state.deniedReasons[denyKey] and not isDebugSource then
                Comms.Whisper(player, denyMessage)
                state.deniedReasons[denyKey] = true
            end
            addon:debug(Diag.D.LogRollsDeniedPlayer:format(player, tonumber(eligibility.usedRolls) or 0, tonumber(eligibility.allowedRolls) or 0))
            return false, eligibility.reason
        end

        addon:debug(Diag.D.LogRollsAcceptedPlayer:format(player, (tonumber(eligibility.usedRolls) or 0) + 1, tonumber(eligibility.allowedRolls) or 0))
        if not canTransitionResponseState(state.responsesByPlayer[player] and state.responsesByPlayer[player].status, RESPONSE_STATUS.ROLL) then
            return false, REASON.STATE_TRANSITION_DENIED
        end
        addRoll(player, roll, itemId)
        applyAcceptedRollResponse(player, tonumber(roll), eligibility, source or "system_roll")
        return true, nil
    end

    -- ----- Public methods ----- --
    function module:Roll(_btn)
        local itemId = self:GetCurrentRollItemID()
        if not itemId then
            return
        end

        local name = Core.GetPlayerName()
        local allowed = getAllowedRolls(itemId, name)

        state.playerCounts[itemId] = state.playerCounts[itemId] or 0
        if state.playerCounts[itemId] >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            addon:debug(Diag.D.LogRollsBlockedPlayer:format(name, state.playerCounts[itemId], allowed))
            return
        end

        RandomRoll(1, 100)
        state.playerCounts[itemId] = state.playerCounts[itemId] + 1
        updateLocalRollState(itemId, name)
        addon:debug(Diag.D.LogRollsPlayerRolled:format(name, itemId))
    end

    function module:PlayerPass(name)
        return submitExplicitResponse(name, RESPONSE_STATUS.PASS, reasonCodes.PLAYER_PASS, reasonCodes.PLAYER_PASS)
    end

    function module:PlayerCancel(name)
        return submitExplicitResponse(name, RESPONSE_STATUS.CANCELLED, reasonCodes.PLAYER_CANCEL, reasonCodes.PLAYER_CANCEL)
    end

    function module:RollStatus()
        local itemId = self:GetCurrentRollItemID()
        local name = Core.GetPlayerName()
        updateLocalRollState(itemId, name)
        return getActiveRollType(), state.record, state.canRoll, state.rolled
    end

    function module:RecordRolls(bool)
        local on = (bool == true)
        state.canRoll = on
        state.record = on

        if on then
            state.warned = false

            -- Reset only if we are starting a clean session
            if state.count == 0 then
                lootState.winner = nil
                lootState.rollWinner = nil
            end
        else
            local itemId = self:GetCurrentRollItemID()
            local itemLink = getCurrentItemLink()
            local currentRollType = getActiveRollType()
            ensureResponseSession()
            seedReservedCandidates(itemId, itemLink, currentRollType)
            finalizeMaterializedResponses(itemId, itemLink, currentRollType)
        end
        updateSessionRollWindow(on)

        addon:debug(Diag.D.LogRollsRecordState:format(tostring(bool)))
    end

    function module:CHAT_MSG_SYSTEM(msg)
        if not msg or not state.record then
            return
        end
        local player, roll, min, max = addon.Deformat(msg, RANDOM_ROLL_RESULT)
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

    function module:GetRolls()
        return state.rolls
    end

    function module:SetRolled()
        local itemId = self:GetCurrentRollItemID()
        local name = Core.GetPlayerName()
        updateLocalRollState(itemId, name)
    end

    function module:DidRoll(itemId, name)
        if not itemId then
            for i = 1, state.count do
                local entry = state.rolls[i]
                if entry and entry.name == name then
                    return true
                end
            end
            return false
        end
        local tracker = acquireItemTracker(itemId)
        local used = tracker[name] or 0
        local reserve = getReserveCountForItem(itemId, name)
        local allowed = (getActiveRollType() == rollTypes.RESERVED and reserve > 0) and reserve or 1
        return used >= allowed
    end

    function module:HighestRoll(name)
        local winnerName = name or lootState.winner
        if not winnerName then
            return 0
        end

        local response = state.responsesByPlayer[winnerName]
        if response and response.bestRoll ~= nil then
            return tonumber(response.bestRoll) or 0
        end

        local wantLow = addon.options.sortAscending == true
        local bestRoll = nil
        local sessionItemId = self:GetCurrentRollItemID()

        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry and entry.name == winnerName then
                if (not sessionItemId) or not entry.itemId or (entry.itemId == sessionItemId) then
                    if bestRoll == nil then
                        bestRoll = entry.roll
                    elseif wantLow and entry.roll < bestRoll then
                        bestRoll = entry.roll
                    elseif (not wantLow) and entry.roll > bestRoll then
                        bestRoll = entry.roll
                    end
                end
            end
        end

        return bestRoll or 0
    end

    function module:ClearRolls(_rec)
        resetRolls()
        local raid = getRaidService()
        if raid and raid.ClearRaidIcons then
            raid:ClearRaidIcons()
        end
    end

    function module:BeginTieReroll(names)
        local session = ensureResponseSession()
        local reroll
        local itemId
        local itemLink
        local currentRollType

        if not session then
            return false
        end

        reroll = setTieRerollFilter(names)
        if not (reroll and reroll.ordered and #reroll.ordered > 1) then
            return false
        end

        itemId = self:GetCurrentRollItemID()
        itemLink = getCurrentItemLink()
        currentRollType = getActiveRollType()

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

        lootState.winner = nil
        lootState.rollWinner = nil
        lootState.rollsCount = 0
        lootState.itemTraded = 0
        lootState.rollStarted = true

        session.active = true
        session.endsAt = nil
        updateSessionRollWindow(true)
        seedTieRerollCandidates(itemId, itemLink, currentRollType)

        addon:debug(Diag.D.LogRollsTieReroll:format(tostring(itemLink), tconcat(reroll.ordered, ",")))
        module:GetDisplayModel()
        return true, reroll.ordered
    end

    function module:GetCurrentRollItemID()
        local session = getRollSession()
        local sessionItemId = session and tonumber(session.itemId) or nil
        if sessionItemId and sessionItemId > 0 then
            addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(sessionItemId)))
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
        addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(itemId)))
        return itemId
    end

    function module:GetCandidateEligibility(name, itemLink, rollType)
        return buildCandidateEligibility(name, nil, itemLink, rollType)
    end

    function module:ValidateWinner(playerName, itemLink, rollType)
        local currentRollType = tonumber(rollType) or getActiveRollType()
        local currentItemLink = itemLink or getCurrentItemLink()
        local currentItemId = Item.GetItemIdFromLink(currentItemLink) or module:GetCurrentRollItemID()
        local eligibility = buildCandidateEligibility(playerName, currentItemId, currentItemLink, currentRollType)
        local response = state.responsesByPlayer[playerName]
        local reason

        if not playerName or playerName == "" then
            return buildWinnerValidationResult(false, reasonCodes.NAME_UNRESOLVED, playerName, eligibility, response)
        end

        if getRollSession() then
            seedReservedCandidates(currentItemId, currentItemLink, currentRollType)
            seedTieRerollCandidates(currentItemId, currentItemLink, currentRollType)
            response = select(1, syncResponseEligibility(playerName, currentItemId, currentItemLink, currentRollType, "award_validation"))
        end

        if not isAwardRollType(currentRollType) then
            if eligibility.ok == true then
                return buildWinnerValidationResult(true, nil, playerName, eligibility, response)
            end
            return buildWinnerValidationResult(false, eligibility.reason or reasonCodes.INELIGIBLE, playerName, eligibility, response)
        end

        reason = getAwardValidationResponseReason(response, eligibility)
        if reason then
            return buildWinnerValidationResult(false, reason, playerName, eligibility, response)
        end
        return buildWinnerValidationResult(true, nil, playerName, eligibility, response)
    end

    function module:SetManualExclusion(name, excluded)
        local key = normalizeCandidateKey(name)
        if not key then
            return false
        end

        if excluded == false then
            state.manualExclusions[key] = nil
        else
            state.manualExclusions[key] = true
        end
        return true
    end

    function module:ClearManualExclusions()
        twipe(state.manualExclusions)
    end

    function module:IsManuallyExcluded(name)
        return getManualExclusionEntry(name) ~= nil
    end

    function module:IsValidRoll(itemId, name)
        local eligibility = buildCandidateEligibility(name, itemId, nil, getActiveRollType(), {
            mode = "submission",
            requireOpenSession = true,
        })
        return eligibility.ok == true
    end

    -- Checks if a player has reserved the specified item.
    function module:IsReserved(itemId, name)
        return getReserveCountForItem(itemId, name) > 0
    end

    -- Gets the number of reserves a player has used for an item.
    function module:GetUsedReserveCount(itemId, name)
        local tracker = acquireItemTracker(itemId)
        return tracker[name] or 0
    end

    -- Gets the total number of reserves a player has for an item.
    function module:GetAllowedReserves(itemId, name)
        return getReserveCountForItem(itemId, name)
    end

    local function buildDisplayModel()
        ensureResponseSession()

        local itemId = module:GetCurrentRollItemID()
        local itemLink = getCurrentItemLink()
        local currentRollType = getActiveRollType()
        local isSR = currentRollType == rollTypes.RESERVED
        local wantLow = addon.options.sortAscending == true
        local display = {}
        local rows = {}
        local resolvedEntries
        local usePlus
        local plusGetter
        local tieGroups
        local resolution
        local ma
        local selectionAllowed

        seedReservedCandidates(itemId, itemLink, currentRollType)
        seedTieRerollCandidates(itemId, itemLink, currentRollType)
        refreshMaterializedResponses(itemId, itemLink, currentRollType)
        if state.canRoll == false then
            finalizeMaterializedResponses(itemId, itemLink, currentRollType)
        end

        resolvedEntries, usePlus, plusGetter = buildResolvedEntries(itemId, currentRollType)
        tieGroups = buildTieGroups(resolvedEntries, usePlus)
        resolution = buildResolution(resolvedEntries, usePlus)
        state.resolution = resolution
        lootState.rollWinner = resolution.topRollName

        for name, response in pairs(state.responsesByPlayer) do
            display[#display + 1] = {
                name = name,
                response = response,
                bucket = response.bucket,
                bucketPriority = getBucketPriority(response.bucket, currentRollType),
                plus = getResponsePlus(itemId, response, plusGetter),
                roll = tonumber(response.bestRoll),
                isTied = tieGroups[name] ~= nil,
                tieGroup = tieGroups[name],
                displayTier = getDisplayTier(response),
            }
        end

        table.sort(display, function(a, b)
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

        ma = lootState.multiAward
        selectionAllowed = (state.canRoll == false) and not (ma and ma.active)

        for i = 1, #display do
            local entry = display[i]
            local response = entry.response
            local name = entry.name
            local roll = entry.roll

            rows[i] = {
                id = i,
                name = name,
                roll = roll,
                class = (getRaidService():GetPlayerClass(name) or "UNKNOWN"):upper(),
                isReserved = response.bucket == "SR",
                counterText = buildRowCounterText(itemId, response, currentRollType, plusGetter),
                infoText = buildRowInfoText(response, entry.isTied),
                status = response.status,
                explicitStatus = response.explicitStatus,
                hasExplicitResponse = isExplicitResponseStatus(response.explicitStatus),
                bucket = response.bucket,
                reason = response.reason,
                isEligible = response.isEligible == true,
                isTied = entry.isTied and true or false,
                tieGroup = entry.tieGroup,
                -- Domain capability consumed by the controller: this row is currently
                -- pickable by the winner-selection flow.
                selectionAllowed = isSelectableRollResponse(response),
            }
        end

        return {
            itemId = itemId,
            isSR = isSR and true or false,
            rows = rows,
            -- Domain capability consumed by the controller: the session may currently
            -- accept winner selection (closed rolls, no multi-award lock).
            selectionAllowed = selectionAllowed and true or false,
            rollWinner = lootState.rollWinner,
            -- Public service contract. Master may consume these stable fields directly:
            -- autoWinners, tiedNames, requiresManualResolution, cutoff, topRollName.
            resolution = resolution,
            requiredWinnerCount = getExpectedWinnerCount(),
            -- Convenience alias over resolution.autoWinners for controller prefill flows.
            winnerSuggestions = resolution.autoWinners,
        }
    end

    -- Public display-model contract for controller/UI consumers. The returned
    -- `resolution` table is a stable part of this API, not an internal detail.
    function module:GetDisplayModel()
        return buildDisplayModel()
    end

    -- Legacy alias retained for compatibility while consumers migrate to GetDisplayModel().
    function module:FetchRolls()
        return module:GetDisplayModel()
    end

    function module:GetRollSession()
        return getRollSession()
    end

    function module:SyncSessionState(session)
        syncSessionStateFromRollSession(session or getRollSession())
    end
end
