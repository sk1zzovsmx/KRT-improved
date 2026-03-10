-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Frames = feature.Frames or addon.Frames
local Item = feature.Item or addon.Item
local Colors = feature.Colors or addon.Colors
local Comms = feature.Comms or addon.Comms
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local UIRowVisuals = addon.UIRowVisuals
local Events = feature.Events or addon.Events or {}
local C = feature.C
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local MultiSelect = feature.MultiSelect or addon.MultiSelect
local Services = feature.Services or addon.Services or {}
local Loot = Services.Loot
local Raid = Services.Raid
local Rolls = Services.Rolls
local UnitIsGroupLeader = feature.UnitIsGroupLeader
local UnitIsGroupAssistant = feature.UnitIsGroupAssistant

local InternalEvents = Events.Internal

local rollTypes = feature.rollTypes
local RAID_TARGET_MARKERS = feature.RAID_TARGET_MARKERS
local PENDING_AWARD_TTL_SECONDS = C.PENDING_AWARD_TTL_SECONDS
local ML_MULTI_AWARD_TIMEOUT_SECONDS = C.ML_MULTI_AWARD_TIMEOUT_SECONDS

local UIFacade = addon.UI or {}
if type(UIFacade.Call) ~= "function" then
    UIFacade.Call = function()
        return nil
    end
end

local lootState = feature.lootState
local itemInfo = feature.itemInfo

local _G = _G
if not UnitIsGroupLeader then
    UnitIsGroupLeader = _G.UnitIsGroupLeader
end
if not UnitIsGroupAssistant then
    UnitIsGroupAssistant = _G.UnitIsGroupAssistant
end

local tinsert, tconcat, twipe = table.insert, table.concat, table.wipe
local pairs, select, next = pairs, select, next

local tostring, tonumber = tostring, tonumber

-- ----- Service accessors ----- --
local function getReservesService()
    return Services.Reserves
end

-- ----- Item helpers ----- --
local function getItem(i)
    local loot = Loot
    return loot and loot.GetItem and loot.GetItem(i) or nil
end

local function getItemName(i)
    local loot = Loot
    return loot and loot.GetItemName and loot.GetItemName(i) or nil
end

local function getItemLink(i)
    local loot = Loot
    return loot and loot.GetItemLink and loot.GetItemLink(i) or nil
end

local function getItemTexture(i)
    local loot = Loot
    return loot and loot.GetItemTexture and loot.GetItemTexture(i) or nil
end

local function itemExists(i)
    local loot = Loot
    return loot and loot.ItemExists and loot.ItemExists(i) or false
end

local function itemIsSoulbound(bag, slot)
    local loot = Loot
    return loot and loot.ItemIsSoulbound and loot.ItemIsSoulbound(bag, slot) or false
end

-- =========== Master Looter Frame Module  =========== --
do
    addon.Controllers = addon.Controllers or {}
    addon.Controllers.Master = addon.Controllers.Master or {}
    local module = addon.Controllers.Master
    local frameName

    -- ----- Internal state ----- --
    local UI = {
        Localized = false,
        Bound = false,
        Loaded = false,
    }

    local getFrame = Frames.MakeFrameGetter("KRTMaster")

    local initializeDropDowns, prepareDropDowns, updateDropDowns
    local dropDownData, dropDownGroupData = {}, {}
    -- Ensure subgroup tables exist even when the Master UI hasn't been opened yet.
    for i = 1, 8 do
        dropDownData[i] = dropDownData[i] or {}
    end
    local dropDownFrameHolder, dropDownFrameBanker, dropDownFrameDisenchanter
    local dropDownsInitialized
    local dropDownDirty = true

    local selectionFrame, updateSelectionFrame
    local rollRows = {}

    local lastUIState = {
        buttons = {},
        texts = {},
        rollStatus = {},
    }
    local dirtyFlags = {
        itemCount = true,
        dropdowns = true,
        winner = true,
        rolls = true,
        buttons = true,
    }

    local countdownRun = false
    local countdownTicker
    local countdownEndTimer

    local assignItem, tradeItem, registerAwardedItem, clearMultiAwardState
    local advanceInventoryWinnerSelection
    local completeInventoryAwardProgress
    local updateRollSessionExpectedWinners
    local screenshotWarn = false

    local announced = false
    local cachedRosterVersion
    local ROLL_WINNERS_CTX = "MLRollWinners"
    local ROLL_SELECTION_MODE = {
        AUTO = "AUTO",
        MANUAL_SINGLE = "MANUAL_SINGLE",
        MANUAL_MULTI = "MANUAL_MULTI",
    }
    local rollUiState = {
        mode = ROLL_SELECTION_MODE.AUTO,
        sessionKey = nil,
        showRollsOnly = true,
        model = nil,
    }
    local FLOW_STATES = {
        IDLE = "idle",
        LOOT = "loot",
        ROLLING = "rolling",
        COUNTDOWN = "countdown",
        INVENTORY = "inventory",
        MULTI_AWARD = "multi_award",
        TRADE = "trade",
    }
    local flowState = FLOW_STATES.IDLE
    local rollAnnouncementKeys = {
        [rollTypes.MAINSPEC] = "ChatRollMS",
        [rollTypes.OFFSPEC] = "ChatRollOS",
        [rollTypes.RESERVED] = "ChatRollSR",
        [rollTypes.FREE] = "ChatRollFree",
    }
    local assignDropDownWidth = 132
    local assignDropDownButtonWidth = 152
    local candidateCache = {
        itemLink = nil,
        rosterVersion = nil,
        indexByName = {},
    }

    -- ----- Private helpers ----- --

    -- ============================================================================
    -- Dropdown / frame helpers
    -- ============================================================================
    local function configureAssignDropDown(frame)
        if not frame then
            return
        end
        frame:SetWidth(assignDropDownButtonWidth)
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(frame, assignDropDownWidth)
        end
        if UIDropDownMenu_SetButtonWidth then
            UIDropDownMenu_SetButtonWidth(frame, assignDropDownButtonWidth)
        end
        if UIDropDownMenu_JustifyText then
            UIDropDownMenu_JustifyText(frame, "LEFT")
        end
    end

    -- ============================================================================
    -- Roll selection / UI model helpers
    -- ============================================================================
    local function resetRollWinnerSelection(mode)
        MultiSelect.MultiSelectClear(ROLL_WINNERS_CTX)
        MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, nil)
        rollUiState.mode = mode or ROLL_SELECTION_MODE.AUTO
        rollUiState.model = nil
    end

    local function invalidateRollUiModel()
        rollUiState.model = nil
    end

    local function getRollSelectionSessionKey()
        local session = Rolls and Rolls.GetRollSession and Rolls:GetRollSession() or nil
        return session and tostring(session.id) or nil
    end

    local function syncRollSelectionSession()
        local sessionKey = getRollSelectionSessionKey()
        if rollUiState.sessionKey == sessionKey then
            return sessionKey
        end
        resetRollWinnerSelection(ROLL_SELECTION_MODE.AUTO)
        rollUiState.sessionKey = sessionKey
        return sessionKey
    end

    local function isSelectableRollRow(row)
        return row and row.selectionAllowed == true
    end

    local function getSelectedRollWinnersOrdered(rows)
        local selected = {}
        if type(rows) ~= "table" then
            return selected
        end

        for i = 1, #rows do
            local row = rows[i]
            if row and row.name and MultiSelect.MultiSelectIsSelected(ROLL_WINNERS_CTX, row.name) then
                selected[#selected + 1] = {
                    name = row.name,
                    roll = tonumber(row.roll) or 0,
                }
            end
        end

        return selected
    end

    local function replaceRollWinnerSelection(names, mode)
        local lastName = nil

        resetRollWinnerSelection(mode)
        if type(names) ~= "table" then
            return 0
        end

        for i = 1, #names do
            local name = names[i]
            if type(name) == "string" and name ~= "" then
                MultiSelect.MultiSelectToggle(ROLL_WINNERS_CTX, name, true)
                lastName = name
            end
        end

        MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, lastName)
        return MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0
    end

    local function pruneRollWinnerSelection(rows)
        local valid = {}
        local selected = MultiSelect.MultiSelectGetSelected(ROLL_WINNERS_CTX) or {}
        local changed = false
        local ordered

        if type(rows) ~= "table" then
            return 0
        end

        for i = 1, #rows do
            local row = rows[i]
            if row and row.name and isSelectableRollRow(row) then
                valid[row.name] = true
            end
        end

        for i = 1, #selected do
            local name = selected[i]
            if not valid[name] then
                MultiSelect.MultiSelectToggle(ROLL_WINNERS_CTX, name, true)
                changed = true
            end
        end

        if changed then
            ordered = getSelectedRollWinnersOrdered(rows)
            MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, ordered[#ordered] and ordered[#ordered].name or nil)
        end

        return MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0
    end

    local buildRollUiModel

    local function applyRollWinnerSelection(name, pickMode, maxSel)
        local isMulti
        local isSelected
        local currentCount

        if not name or name == "" then
            return false
        end

        if not pickMode then
            MultiSelect.MultiSelectToggle(ROLL_WINNERS_CTX, name, false, false)
            MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, name)
            rollUiState.mode = ROLL_SELECTION_MODE.MANUAL_SINGLE
            return true
        end

        isMulti = MultiSelect.MultiSelectResolveModifiers and select(1, MultiSelect.MultiSelectResolveModifiers(ROLL_WINNERS_CTX, { allowRange = false }))
            or ((IsControlKeyDown and IsControlKeyDown()) or false)
        isSelected = MultiSelect.MultiSelectIsSelected(ROLL_WINNERS_CTX, name)
        currentCount = MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0

        if isMulti then
            if (not isSelected) and currentCount >= maxSel then
                if maxSel == 1 then
                    replaceRollWinnerSelection({ name }, ROLL_SELECTION_MODE.MANUAL_MULTI)
                    return true
                end
                addon:warn(Diag.W.ErrMLMultiSelectTooMany:format(maxSel))
                return false
            end
            MultiSelect.MultiSelectToggle(ROLL_WINNERS_CTX, name, true, true)
        else
            MultiSelect.MultiSelectToggle(ROLL_WINNERS_CTX, name, false, false)
        end

        rollUiState.mode = ROLL_SELECTION_MODE.MANUAL_MULTI
        if (MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0) > 0 then
            MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, name)
        else
            MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, nil)
        end
        return true
    end

    -- ============================================================================
    -- UI binding helpers
    -- ============================================================================
    function UI.AcquireRefs(frame)
        return {
            configBtn = Frames.Ref(frame, "ConfigBtn"),
            selectItemBtn = Frames.Ref(frame, "SelectItemBtn"),
            spamLootBtn = Frames.Ref(frame, "SpamLootBtn"),
            msBtn = Frames.Ref(frame, "MSBtn"),
            osBtn = Frames.Ref(frame, "OSBtn"),
            srBtn = Frames.Ref(frame, "SRBtn"),
            freeBtn = Frames.Ref(frame, "FreeBtn"),
            countdownBtn = Frames.Ref(frame, "CountdownBtn"),
            awardBtn = Frames.Ref(frame, "AwardBtn"),
            rollBtn = Frames.Ref(frame, "RollBtn"),
            clearBtn = Frames.Ref(frame, "ClearBtn"),
            holdBtn = Frames.Ref(frame, "HoldBtn"),
            bankBtn = Frames.Ref(frame, "BankBtn"),
            disenchantBtn = Frames.Ref(frame, "DisenchantBtn"),
            reserveListBtn = Frames.Ref(frame, "ReserveListBtn"),
            lootCounterBtn = Frames.Ref(frame, "LootCounterBtn"),
            itemCountBox = Frames.Ref(frame, "ItemCount"),
            holdDropDown = Frames.Ref(frame, "HoldDropDown"),
            bankDropDown = Frames.Ref(frame, "BankDropDown"),
            disenchantDropDown = Frames.Ref(frame, "DisenchantDropDown"),
        }
    end

    local function bindMainControlScripts(frame, refs)
        if not (frame and refs) then
            return
        end
        if frame._krtBound then
            return
        end

        Frames.SafeSetScript(refs.configBtn, "OnClick", function()
            UIFacade:Call("Config", "Toggle")
        end)
        Frames.SafeSetScript(refs.selectItemBtn, "OnClick", function(self, button)
            module:BtnSelectItem(self, button)
        end)
        Frames.SafeSetScript(refs.spamLootBtn, "OnClick", function(self, button)
            module:BtnSpamLoot(self, button)
        end)
        Frames.SafeSetScript(refs.msBtn, "OnClick", function(self, button)
            module:BtnMS(self, button)
        end)
        Frames.SafeSetScript(refs.osBtn, "OnClick", function(self, button)
            module:BtnOS(self, button)
        end)
        Frames.SafeSetScript(refs.srBtn, "OnClick", function(self, button)
            module:BtnSR(self, button)
        end)
        Frames.SafeSetScript(refs.freeBtn, "OnClick", function(self, button)
            module:BtnFree(self, button)
        end)
        if refs.countdownBtn and refs.countdownBtn.RegisterForClicks then
            local ok = pcall(function()
                refs.countdownBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            end)
            if not ok then
                -- Keep left-click behavior even on clients/templates that reject custom click registration.
                refs.countdownBtn:RegisterForClicks("LeftButtonUp")
            end
        end
        Frames.SafeSetScript(refs.countdownBtn, "OnClick", function(self, button)
            module:BtnCountdown(self, button)
        end)
        Frames.SafeSetScript(refs.awardBtn, "OnClick", function(self, button)
            module:BtnAward(self, button)
        end)
        Frames.SafeSetScript(refs.rollBtn, "OnClick", function(self, button)
            Rolls:Roll(self, button)
        end)
        Frames.SafeSetScript(refs.clearBtn, "OnClick", function(self, button)
            module:BtnClear(self, button)
        end)
        Frames.SafeSetScript(refs.holdBtn, "OnClick", function(self, button)
            module:BtnHold(self, button)
        end)
        Frames.SafeSetScript(refs.bankBtn, "OnClick", function(self, button)
            module:BtnBank(self, button)
        end)
        Frames.SafeSetScript(refs.disenchantBtn, "OnClick", function(self, button)
            module:BtnDisenchant(self, button)
        end)
        Frames.SafeSetScript(refs.reserveListBtn, "OnClick", function(self, button)
            module:BtnReserveList(self, button)
        end)
        Frames.SafeSetScript(refs.lootCounterBtn, "OnClick", function(self, button)
            module:BtnLootCounter(self, button)
        end)

        frame._krtBound = true
    end

    -- ============================================================================
    -- Flow / session helpers
    -- ============================================================================
    local function setItemCountValue(count, focus)
        local frame = getFrame()
        if not frame then
            return
        end
        frameName = frameName or frame:GetName()
        if not frameName or frameName ~= frame:GetName() then
            return
        end
        local itemCountBox = _G[frameName .. "ItemCount"]
        if not itemCountBox then
            return
        end
        count = tonumber(count) or 1
        if count < 1 then
            count = 1
        end
        lootState.selectedItemCount = count
        updateRollSessionExpectedWinners()
        Frames.SetEditBoxValue(itemCountBox, count, focus)
        lastUIState.itemCountText = tostring(count)
        dirtyFlags.itemCount = false
    end

    local function getRaidRosterVersion()
        if Raid and Raid.GetRosterVersion then
            return Raid:GetRosterVersion()
        end
        return nil
    end

    local function invalidateCandidateCache()
        candidateCache.itemLink = nil
        candidateCache.rosterVersion = nil
        twipe(candidateCache.indexByName)
    end

    local function computeFlowState()
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return FLOW_STATES.MULTI_AWARD
        end
        if lootState.trader then
            return FLOW_STATES.TRADE
        end
        if lootState.fromInventory then
            return FLOW_STATES.INVENTORY
        end
        if countdownRun then
            return FLOW_STATES.COUNTDOWN
        end
        if lootState.rollStarted then
            return FLOW_STATES.ROLLING
        end
        if (lootState.lootCount or 0) > 0 then
            return FLOW_STATES.LOOT
        end
        return FLOW_STATES.IDLE
    end

    local function syncFlowState()
        local nextState = computeFlowState()
        if flowState ~= nextState then
            flowState = nextState
            dirtyFlags.buttons = true
        end
        return flowState
    end

    local function getCurrentMultiAwardWinner()
        local ma = lootState.multiAward
        if ma and ma.active and not lootState.fromInventory then
            return ma.currentWinner
        end
        return nil
    end

    local function getCurrentTradeWinner()
        if lootState.trader then
            return lootState.tradeWinner
        end
        return nil
    end

    local function shouldShowRollRowInFrame(row)
        return row and (row.roll ~= nil or row.hasExplicitResponse == true)
    end

    local function buildRollStarWinnerMap(resolution)
        local starMap = {}

        for i = 1, #(resolution.autoWinners or {}) do
            local winner = resolution.autoWinners[i]
            if winner and winner.name then
                starMap[winner.name] = true
            end
        end

        if not next(starMap) and resolution.requiresManualResolution then
            for i = 1, #(resolution.tiedNames or {}) do
                local name = resolution.tiedNames[i]
                if name and name ~= "" then
                    starMap[name] = true
                end
            end
        end

        if not next(starMap) and resolution.topRollName then
            starMap[resolution.topRollName] = true
        end

        return starMap
    end

    buildRollUiModel = function(forceRefresh)
        if forceRefresh ~= true and rollUiState.model then
            return rollUiState.model
        end

        local model = Rolls and Rolls.GetDisplayModel and Rolls:GetDisplayModel() or {}
        local baseRows = model.rows or {}
        local decoratedRows = {}
        local visibleRows = {}
        local resolution = model.resolution or {}
        local starWinners = buildRollStarWinnerMap(resolution)
        local selectionAllowed = model.selectionAllowed == true
        local requiredWinnerCount = tonumber(model.requiredWinnerCount) or 1
        local inventoryMultiSelectMode
        local pickMode
        local selectedWinners
        local selectedNames = {}
        local msCount
        local manualEmptySelection
        local autoWinner = resolution.autoWinners and resolution.autoWinners[1] or nil
        local autoWinnerName = autoWinner and autoWinner.name or nil
        local winnerName
        local pickName
        local starTarget
        local highlightTarget
        local singleWinnerSelected

        syncRollSelectionSession()

        if selectionAllowed then
            pruneRollWinnerSelection(baseRows)
        elseif (MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0) > 0 then
            resetRollWinnerSelection(ROLL_SELECTION_MODE.AUTO)
        end

        inventoryMultiSelectMode = lootState.fromInventory and (requiredWinnerCount > 1 or rollUiState.mode == ROLL_SELECTION_MODE.MANUAL_MULTI)
        pickMode = selectionAllowed and ((not lootState.fromInventory) or inventoryMultiSelectMode)

        if pickMode and rollUiState.mode == ROLL_SELECTION_MODE.AUTO then
            local prefillNames = {}
            for i = 1, #(resolution.autoWinners or {}) do
                local winner = resolution.autoWinners[i]
                if winner and winner.name then
                    prefillNames[#prefillNames + 1] = winner.name
                end
            end
            replaceRollWinnerSelection(prefillNames, ROLL_SELECTION_MODE.AUTO)
        elseif not pickMode and rollUiState.mode ~= ROLL_SELECTION_MODE.MANUAL_SINGLE and (MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0) > 0 then
            resetRollWinnerSelection(ROLL_SELECTION_MODE.AUTO)
        end

        selectedWinners = getSelectedRollWinnersOrdered(baseRows)
        for i = 1, #selectedWinners do
            local winner = selectedWinners[i]
            if winner and winner.name then
                selectedNames[winner.name] = true
            end
        end

        msCount = pickMode and #selectedWinners or 0
        manualEmptySelection = pickMode and rollUiState.mode == ROLL_SELECTION_MODE.MANUAL_MULTI and msCount == 0

        if pickMode then
            if rollUiState.mode == ROLL_SELECTION_MODE.MANUAL_MULTI then
                winnerName = selectedWinners[1] and selectedWinners[1].name or nil
            else
                winnerName = autoWinnerName
            end
        else
            if rollUiState.mode == ROLL_SELECTION_MODE.MANUAL_SINGLE and selectedWinners[1] and selectedWinners[1].name then
                winnerName = selectedWinners[1].name
            elseif selectionAllowed and resolution.requiresManualResolution and not autoWinnerName then
                winnerName = nil
            else
                if rollUiState.mode == ROLL_SELECTION_MODE.MANUAL_SINGLE and not (selectedWinners[1] and selectedWinners[1].name) then
                    resetRollWinnerSelection(ROLL_SELECTION_MODE.AUTO)
                end
                winnerName = autoWinnerName
            end
        end

        pickName = selectionAllowed and winnerName or nil
        starTarget = resolution.topRollName
        highlightTarget = selectionAllowed and (pickName or starTarget) or starTarget
        singleWinnerSelected = selectionAllowed and not pickMode and winnerName ~= nil and winnerName ~= ""
        if msCount > 0 or singleWinnerSelected or manualEmptySelection then
            highlightTarget = nil
        end

        for i = 1, #baseRows do
            local row = baseRows[i]
            local isSelected
            local isFocused
            local decorated

            if row then
                isSelected = selectedNames[row.name] == true or (singleWinnerSelected and winnerName == row.name)
                isFocused = (highlightTarget and highlightTarget == row.name) or false

                decorated = {}
                for key, value in pairs(row) do
                    decorated[key] = value
                end
                decorated.displayName = (selectionAllowed and isSelected) and ("> " .. row.name .. " <") or row.name
                decorated.isSelected = isSelected and true or false
                decorated.isFocused = isFocused and true or false
                decorated.canClick = selectionAllowed and isSelectableRollRow(row)
                decorated.showStar = starWinners[row.name] and true or false
                decoratedRows[#decoratedRows + 1] = decorated

                if rollUiState.showRollsOnly ~= true or shouldShowRollRowInFrame(decorated) then
                    visibleRows[#visibleRows + 1] = decorated
                end
            end
        end

        model.rows = decoratedRows
        model.visibleRows = visibleRows
        model.pickMode = pickMode and true or false
        model.msCount = msCount
        model.highlightTarget = highlightTarget
        model.winner = winnerName
        model.selectionAllowed = selectionAllowed and true or false
        model.showRollsOnly = rollUiState.showRollsOnly == true
        rollUiState.model = model
        return model
    end

    local function selectRollWinnerRow(name)
        local model = buildRollUiModel(true)
        local rows = model and model.rows or {}
        local requiredWinnerCount = tonumber(model and model.requiredWinnerCount) or 1
        local pickMode = model and model.pickMode == true
        local maxSel = requiredWinnerCount
        local row

        if not (model and model.selectionAllowed == true) then
            return false
        end

        if lootState.multiAward and lootState.multiAward.active then
            addon:warn(Diag.W.ErrMLMultiAwardInProgress)
            return false
        end

        for i = 1, #rows do
            if rows[i] and rows[i].name == name then
                row = rows[i]
                break
            end
        end

        if not isSelectableRollRow(row) then
            return false
        end

        if maxSel > #rows then
            maxSel = #rows
        end
        if maxSel < 1 then
            maxSel = 1
        end

        if not applyRollWinnerSelection(name, pickMode, maxSel) then
            return false
        end

        invalidateRollUiModel()
        buildRollUiModel(true)
        if not pickMode then
            Comms.Sync("KRT-RollWinner", name)
        end
        return true
    end

    local function getDisplayedWinnerName(model)
        local currentWinner = getCurrentTradeWinner() or getCurrentMultiAwardWinner()
        if currentWinner then
            return currentWinner
        end

        local activeModel = model or (buildRollUiModel and buildRollUiModel(true)) or nil
        return activeModel and activeModel.winner or lootState.winner
    end

    local function getResolvedRollWinnerName(model)
        local activeModel = model or (buildRollUiModel and buildRollUiModel(true)) or nil
        return activeModel and activeModel.winner or lootState.winner
    end

    local function shouldUseTieReroll(model)
        local resolution = model and model.resolution or nil
        local requiredWinnerCount = tonumber(model and model.requiredWinnerCount) or 1
        return resolution and resolution.requiresManualResolution == true and model and model.pickMode ~= true and requiredWinnerCount == 1
    end

    local function resetItemCountAndRefresh(focus)
        module:ResetItemCount(focus)
        module:RequestRefresh()
    end

    local function allocateRollSessionId()
        local nextId = tonumber(lootState.nextRollSessionId) or 1
        if nextId < 1 then
            nextId = 1
        end
        lootState.nextRollSessionId = nextId + 1
        return "RS:" .. tostring(nextId)
    end

    local function getRollSessionItemKey(itemLink)
        if not itemLink then
            return nil
        end
        return Item.GetItemStringFromLink(itemLink) or itemLink
    end

    local function matchHeldInventoryLoot(entry, raidNum, itemLink, holderName)
        if type(entry) ~= "table" or tonumber(entry.rollType) ~= rollTypes.HOLD or not itemLink then
            return false
        end

        local queryItemKey = getRollSessionItemKey(itemLink)
        local queryItemId = tonumber(Item.GetItemIdFromLink(itemLink)) or 0
        local entryItemKey = entry.itemString or entry.itemLink
        local sameItem = false
        if queryItemKey and entryItemKey and queryItemKey == entryItemKey then
            sameItem = true
        elseif queryItemId > 0 and tonumber(entry.itemId) == queryItemId then
            sameItem = true
        end
        if not sameItem then
            return false
        end

        local resolvedHolder = holderName or Core.GetPlayerName()
        if not resolvedHolder or resolvedHolder == "" then
            return true
        end

        local holderNid = Raid.GetPlayerID and Raid:GetPlayerID(resolvedHolder, raidNum) or 0
        if holderNid > 0 then
            return tonumber(entry.looterNid) == holderNid
        end
        return true
    end

    local function resolveHeldInventoryLootNid(itemLink, preferredLootNid, holderName)
        if not lootState.fromInventory or not itemLink then
            return 0
        end

        local raidNum = Core.GetCurrentRaid()
        if not raidNum then
            return 0
        end

        local preferred = tonumber(preferredLootNid) or 0
        if preferred > 0 and Raid.GetLootByNid then
            local entry = Raid:GetLootByNid(preferred, raidNum)
            if matchHeldInventoryLoot(entry, raidNum, itemLink, holderName) then
                return preferred
            end
        end

        if Raid.GetHeldLootNid then
            return tonumber(Raid:GetHeldLootNid(itemLink, raidNum, holderName, 0)) or 0
        end

        return 0
    end

    updateRollSessionExpectedWinners = function()
        local session = Rolls:GetRollSession()
        if not session then
            return
        end
        local expected = tonumber(lootState.selectedItemCount) or 1
        if expected < 1 then
            expected = 1
        end
        session.expectedWinners = expected
    end

    local function openRollSession(itemLink, rollType, source)
        if not itemLink then
            return nil
        end
        local expected = tonumber(lootState.selectedItemCount) or 1
        if expected < 1 then
            expected = 1
        end
        local itemId = Item.GetItemIdFromLink(itemLink)

        local session = {
            id = allocateRollSessionId(),
            itemKey = getRollSessionItemKey(itemLink),
            itemId = tonumber(itemId) or nil,
            itemLink = itemLink,
            rollType = tonumber(rollType) or tonumber(lootState.currentRollType) or rollTypes.FREE,
            startedAt = GetTime(),
            endsAt = nil,
            source = source or (lootState.fromInventory and "inventory" or "lootWindow"),
            expectedWinners = expected,
            lootNid = 0,
            active = true,
        }

        lootState.rollSession = session
        lootState.rollStarted = true
        Rolls:SyncSessionState(session)
        return session
    end

    local function ensureRollSession(itemLink, rollType, source)
        local session = Rolls:GetRollSession()
        if not session then
            return openRollSession(itemLink, rollType, source)
        end

        if itemLink then
            local previousItemKey = session.itemKey
            local previousItemId = tonumber(session.itemId) or nil
            local nextItemKey = getRollSessionItemKey(itemLink)
            session.itemLink = itemLink
            session.itemKey = nextItemKey
            local itemId = Item.GetItemIdFromLink(itemLink)
            local nextItemId = tonumber(itemId) or nil
            local isSameItem = false
            if nextItemKey and previousItemKey and nextItemKey == previousItemKey then
                isSameItem = true
            elseif nextItemId and previousItemId and nextItemId == previousItemId then
                isSameItem = true
            end
            session.itemId = nextItemId or session.itemId
            if not isSameItem then
                session.lootNid = 0
            end
        end
        if rollType ~= nil then
            session.rollType = tonumber(rollType) or session.rollType
        end
        session.source = source or session.source or (lootState.fromInventory and "inventory" or "lootWindow")
        session.lootNid = tonumber(session.lootNid) or 0
        if lootState.fromInventory then
            local heldLootNid = resolveHeldInventoryLootNid(itemLink or session.itemLink, session.lootNid, Core.GetPlayerName())
            if heldLootNid > 0 then
                session.lootNid = heldLootNid
                lootState.currentRollItem = heldLootNid
            else
                session.lootNid = 0
                lootState.currentRollItem = 0
            end
        end
        session.active = true
        session.endsAt = nil
        if not session.startedAt then
            session.startedAt = GetTime()
        end
        updateRollSessionExpectedWinners()
        Rolls:SyncSessionState(session)
        return session
    end

    local function requestLoggerLootLog(lootNid, looter, rollType, rollValue, source, raidId)
        local request = {
            lootNid = lootNid,
            itemID = lootNid,
            looter = looter,
            rollType = rollType,
            rollValue = rollValue,
            source = source,
            raidId = raidId,
            raidID = raidId,
            ok = false,
        }
        Bus.TriggerEvent(InternalEvents.LoggerLootLogRequest, request)
        return request.ok == true
    end

    local function ensureTradeLootContext(itemLink, playerName, rollType, rollValue, awardedCount, source)
        local session = Rolls:GetRollSession()
        local sessionLootNid = session and tonumber(session.lootNid) or 0
        local currentLootNid = tonumber(lootState.currentRollItem) or 0
        local lootNid = 0

        if lootState.fromInventory then
            local holderName = lootState.trader or Core.GetPlayerName() or playerName
            local preferredLootNid = sessionLootNid > 0 and sessionLootNid or currentLootNid
            lootNid = resolveHeldInventoryLootNid(itemLink, preferredLootNid, holderName)
        else
            lootNid = sessionLootNid > 0 and sessionLootNid or currentLootNid
        end

        if lootNid <= 0 and not lootState.fromInventory and session and session.id and Raid.GetLootNidByRollSessionId then
            lootNid = Raid:GetLootNidByRollSessionId(session.id, addon.Core.GetCurrentRaid(), playerName, addon.Core.GetLastBoss())
        end

        local createdTradeOnly = false
        if lootNid <= 0 and Raid.LogTradeOnlyLoot then
            local created = Raid:LogTradeOnlyLoot(
                itemLink,
                playerName,
                rollType,
                rollValue,
                awardedCount,
                source,
                addon.Core.GetCurrentRaid(),
                addon.Core.GetLastBoss(),
                session and session.id or nil
            ) or 0
            created = tonumber(created) or 0
            if created > 0 then
                lootNid = created
                createdTradeOnly = true
            end
        end

        if lootNid > 0 then
            lootState.currentRollItem = lootNid
            if session then
                session.lootNid = lootNid
                Rolls:SyncSessionState(session)
            end
        end

        return lootNid, createdTradeOnly
    end

    local function stopCountdown()
        -- Cancel active countdown timers and clear their handles
        addon.CancelTimer(countdownTicker, true)
        addon.CancelTimer(countdownEndTimer, true)
        countdownTicker = nil
        countdownEndTimer = nil
        countdownRun = false
    end

    local function shouldAnnounceCountdownTick(remaining, duration)
        if remaining >= duration then
            return true
        end
        if remaining >= 10 then
            return (remaining % 10 == 0)
        end
        if remaining > 0 and remaining < 10 and remaining % 7 == 0 then
            return true
        end
        if remaining > 0 and remaining >= 5 and remaining % 5 == 0 then
            return true
        end
        return remaining > 0 and remaining <= 3
    end

    local function refreshRollDisplay()
        Rolls:GetDisplayModel()
        module:RequestRefresh()
    end

    local function resetRecordedRolls()
        Rolls:ClearRolls()
        Rolls:RecordRolls(false)
    end

    local function clearLootAndResetRecordedRolls()
        Loot:ClearLoot()
        resetRecordedRolls()
    end

    local function startCountdown()
        stopCountdown()
        countdownRun = true
        local duration = addon.options.countdownDuration or 0
        local remaining = duration
        if shouldAnnounceCountdownTick(remaining, duration) then
            addon:Announce(L.ChatCountdownTic:format(remaining))
        end
        countdownTicker = addon.NewTicker(1, function()
            remaining = remaining - 1
            if remaining > 0 then
                if shouldAnnounceCountdownTick(remaining, duration) then
                    addon:Announce(L.ChatCountdownTic:format(remaining))
                end
            end
        end, duration)
        countdownEndTimer = addon.NewTimer(duration, function()
            if not countdownRun then
                return
            end
            stopCountdown()
            addon:Announce(L.ChatCountdownEnd)

            -- At zero: stop roll (enables selection in rolls) and refresh the UI
            Rolls:RecordRolls(false)
            refreshRollDisplay()
        end)
    end

    local function finalizeRollSession()
        Rolls:RecordRolls(false)
        stopCountdown()
        refreshRollDisplay()
    end

    local function updateMasterButtonsIfChanged(state)
        local buttons = lastUIState.buttons
        local texts = lastUIState.texts

        local function updateEnabled(key, frame, enabled)
            if buttons[key] ~= enabled then
                UIPrimitives.EnableDisable(frame, enabled)
                buttons[key] = enabled
            end
        end

        local function updateItemState(enabled)
            local itemBtn = _G[frameName .. "ItemBtn"]
            if itemBtn and buttons.itemBtn ~= enabled then
                UIPrimitives.EnableDisable(itemBtn, enabled)
                local texture = itemBtn:GetNormalTexture()
                if texture and texture.SetDesaturated then
                    texture:SetDesaturated(not enabled)
                end
                buttons.itemBtn = enabled
            end
        end

        local function updateText(key, frame, text)
            if texts[key] ~= text then
                frame:SetText(text)
                texts[key] = text
            end
        end

        updateText("countdown", _G[frameName .. "CountdownBtn"], state.countdownText)
        updateText("award", _G[frameName .. "AwardBtn"], state.awardText)
        updateText("selectItem", _G[frameName .. "SelectItemBtn"], state.selectItemText)
        updateText("spamLoot", _G[frameName .. "SpamLootBtn"], state.spamLootText)

        updateEnabled("selectItem", _G[frameName .. "SelectItemBtn"], state.canSelectItem)
        updateEnabled("spamLoot", _G[frameName .. "SpamLootBtn"], state.canSpamLoot)
        updateEnabled("ms", _G[frameName .. "MSBtn"], state.canStartRolls)
        updateEnabled("os", _G[frameName .. "OSBtn"], state.canStartRolls)
        updateEnabled("sr", _G[frameName .. "SRBtn"], state.canStartSR)
        updateEnabled("free", _G[frameName .. "FreeBtn"], state.canStartRolls)
        updateEnabled("countdown", _G[frameName .. "CountdownBtn"], state.canCountdown)
        updateEnabled("hold", _G[frameName .. "HoldBtn"], state.canHold)
        updateEnabled("bank", _G[frameName .. "BankBtn"], state.canBank)
        updateEnabled("disenchant", _G[frameName .. "DisenchantBtn"], state.canDisenchant)
        updateEnabled("award", _G[frameName .. "AwardBtn"], state.canAward)
        updateText("reserveList", _G[frameName .. "ReserveListBtn"], state.reserveListText)
        updateEnabled("reserveList", _G[frameName .. "ReserveListBtn"], state.canReserveList)
        updateEnabled("roll", _G[frameName .. "RollBtn"], state.canRoll)
        updateEnabled("clear", _G[frameName .. "ClearBtn"], state.canClear)
        updateItemState(state.canChangeItem)
    end

    local function refreshDropDowns(force)
        if not dropDownsInitialized then
            return
        end
        if not force and not dropDownDirty then
            return
        end
        updateDropDowns(dropDownFrameHolder)
        updateDropDowns(dropDownFrameBanker)
        updateDropDowns(dropDownFrameDisenchanter)
        dropDownDirty = false
        dirtyFlags.dropdowns = false
    end

    local function hookDropDownOpen(frame)
        if not frame then
            return
        end
        local button = _G[frame:GetName() .. "Button"]
        if button and not button._krtHooked then
            button:HookScript("OnClick", function()
                refreshDropDowns(true)
            end)
            button._krtHooked = true
        end
    end

    local function buildCandidateCache(itemLink)
        candidateCache.itemLink = itemLink
        candidateCache.rosterVersion = getRaidRosterVersion()
        twipe(candidateCache.indexByName)
        for p = 1, addon.GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                candidateCache.indexByName[candidate] = p
            end
        end
        addon:debug(Diag.D.LogMLCandidateCacheBuilt:format(tostring(itemLink), addon.tLength(candidateCache.indexByName)))
    end

    local function findLootSlotIndex(itemLink)
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        for i = 1, GetNumLootItems() do
            local tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                return i
            end
            if wantedKey and tempItemLink then
                local tempKey = Item.GetItemStringFromLink(tempItemLink) or tempItemLink
                if tempKey == wantedKey then
                    return i
                end
            end
        end
        return nil
    end

    local function resolveCandidateIndex(itemLink, playerName)
        local rosterVersion = getRaidRosterVersion()
        local rosterChanged = rosterVersion and candidateCache.rosterVersion ~= rosterVersion
        if candidateCache.itemLink ~= itemLink or rosterChanged then
            buildCandidateCache(itemLink)
        end
        local candidateIndex = candidateCache.indexByName[playerName]
        if not candidateIndex then
            addon:debug(Diag.D.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            buildCandidateCache(itemLink)
            candidateIndex = candidateCache.indexByName[playerName]
        end
        return candidateIndex
    end

    local function validateAwardWinner(playerName, itemLink, rollType)
        return Rolls:ValidateWinner(playerName, itemLink, rollType)
    end

    local function refreshCandidateUiState()
        cachedRosterVersion = nil
        invalidateCandidateCache()
        dropDownDirty = true
        dirtyFlags.dropdowns = true
        if prepareDropDowns then
            prepareDropDowns()
        end
    end

    -- ============================================================================
    -- Award / candidate helpers
    -- ============================================================================
    local function buildAssignMessages(itemLink, playerName, rollType)
        local output, whisper
        if rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE and addon.options.announceOnWin then
            output = L.ChatAward:format(playerName, itemLink)
        elseif rollType == rollTypes.HOLD and addon.options.announceOnHold then
            output = L.ChatHold:format(playerName, itemLink)
            if addon.options.lootWhispers then
                whisper = L.WhisperHoldAssign:format(itemLink)
            end
        elseif rollType == rollTypes.BANK and addon.options.announceOnBank then
            output = L.ChatBank:format(playerName, itemLink)
            if addon.options.lootWhispers then
                whisper = L.WhisperBankAssign:format(itemLink)
            end
        elseif rollType == rollTypes.DISENCHANT and addon.options.announceOnDisenchant then
            output = L.ChatDisenchant:format(itemLink, playerName)
            if addon.options.lootWhispers then
                whisper = L.WhisperDisenchantAssign:format(itemLink)
            end
        end
        return output, whisper
    end

    -- ============================================================================
    -- Multi-award helpers
    -- ============================================================================
    local function collectMultiAwardNames(ma)
        local names = {}
        if not ma then
            return names
        end
        local total = ma.total or (ma.winners and #ma.winners) or 0
        for i = 1, total do
            local winner = ma.winners and ma.winners[i]
            if winner and winner.name then
                names[#names + 1] = winner.name
            end
        end
        return names
    end

    local function announceMultiAwardCompletion(ma)
        if not (ma and ma.announceOnWin and not ma.congratsSent) then
            return
        end
        local names = collectMultiAwardNames(ma)
        if #names <= 0 then
            return
        end
        if #names == 1 then
            addon:Announce(L.ChatAward:format(names[1], ma.itemLink))
        else
            addon:Announce(L.ChatAwardMutiple:format(table.concat(names, ", "), ma.itemLink))
        end
        ma.congratsSent = true
    end

    local function buildMultiAwardSlotCandidates(itemLink)
        local slots = {}
        local slotMap = {}
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        for slot = 1, (GetNumLootItems() or 0) do
            local link = GetLootSlotLink(slot)
            if link then
                local slotKey = Item.GetItemStringFromLink(link) or link
                if slotKey == wantedKey then
                    slots[#slots + 1] = slot
                    slotMap[slot] = true
                end
            end
        end
        return slots, slotMap
    end

    local function getCurrentMultiAwardCount(itemKey)
        local currentCount = 0
        for i = 1, (lootState.lootCount or 0) do
            local it = getItem and getItem(i)
            if it and it.itemKey == itemKey then
                currentCount = tonumber(it.count) or 1
                break
            end
        end
        return currentCount
    end

    local function cancelMultiAwardTimeout(ma)
        if ma and ma.timeoutHandle then
            addon.CancelTimer(ma.timeoutHandle, true)
            ma.timeoutHandle = nil
        end
    end

    local function cancelMultiAwardDelay(ma)
        if ma and ma.delayHandle then
            addon.CancelTimer(ma.delayHandle, true)
            ma.delayHandle = nil
        end
        if ma then
            ma.scheduled = false
        end
    end

    local function armMultiAwardProgressTimeout(ma)
        if not (ma and ma.active and not lootState.fromInventory) then
            return
        end
        local timeout = tonumber(ML_MULTI_AWARD_TIMEOUT_SECONDS) or 0
        ma.waitingForDecrement = true
        if timeout <= 0 then
            return
        end

        cancelMultiAwardTimeout(ma)
        local expectedLessThan = tonumber(ma.lastCount) or 0
        ma.timeoutHandle = addon.NewTimer(timeout, function()
            local cur = lootState.multiAward
            if cur ~= ma or not (cur and cur.active and cur.waitingForDecrement and not lootState.fromInventory) then
                return
            end
            local observed = getCurrentMultiAwardCount(cur.itemKey)
            addon:warn(Diag.W.ErrMLMultiAwardInterruptedTimeout:format(timeout, tostring(cur.itemLink), expectedLessThan, observed, tostring(cur.lastClearedSlot or "?")))
            clearMultiAwardState(true)
            module:RequestRefresh()
        end)
    end

    clearMultiAwardState = function(resetItemCount)
        local ma = lootState.multiAward
        if ma then
            ma.waitingForDecrement = false
            cancelMultiAwardTimeout(ma)
            cancelMultiAwardDelay(ma)
        end
        lootState.multiAward = nil
        announced = false
        if resetItemCount then
            module:ResetItemCount()
        end
    end

    local function finalizeMultiAwardIfDone()
        local ma = lootState.multiAward
        if not ma then
            return false
        end
        local total = ma.total or (ma.winners and #ma.winners) or 0
        local pos = tonumber(ma.pos) or 1
        if pos <= total then
            return false
        end
        announceMultiAwardCompletion(ma)
        clearMultiAwardState(true)
        return true
    end

    local function buildMultiAwardWinners(target)
        local selCount = MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0
        local rollModel
        local picked
        if selCount <= 0 then
            return nil, "empty_selection"
        end

        local awardCount = selCount
        if awardCount > target then
            awardCount = target
        end

        rollModel = buildRollUiModel(true)
        picked = getSelectedRollWinnersOrdered(rollModel and rollModel.rows or nil)
        if (not picked) or (#picked < awardCount) then
            return nil, "not_enough_selection", awardCount, picked and #picked or 0
        end

        local winners = {}
        for i = 1, awardCount do
            local p = picked[i]
            if p and p.name then
                winners[#winners + 1] = { name = p.name, roll = tonumber(p.roll) or 0 }
            end
        end

        MultiSelect.MultiSelectClear(ROLL_WINNERS_CTX)
        MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, nil)

        if #winners <= 0 then
            return nil, "empty_winners"
        end

        return winners
    end

    local function startMultiAwardSequence(itemLink, available, winners)
        setItemCountValue(#winners, false)
        local candidateSlots, candidateSlotMap = buildMultiAwardSlotCandidates(itemLink)
        local timeout = tonumber(ML_MULTI_AWARD_TIMEOUT_SECONDS) or 0

        lootState.multiAward = {
            active = true,
            itemLink = itemLink,
            itemKey = Item.GetItemStringFromLink(itemLink) or itemLink,
            lastCount = available,
            rollType = lootState.currentRollType,
            winners = winners,
            currentWinner = winners[1] and winners[1].name or nil,
            pos = 2, -- first award is immediate; the rest continues on LOOT_SLOT_CLEARED
            total = #winners,
            slotCandidates = candidateSlots,
            slotCandidateMap = candidateSlotMap,
            lastClearedSlot = nil,
            waitingForDecrement = false,
        }

        lootState.multiAward.announceOnWin = addon.options.announceOnWin and true or false
        lootState.multiAward.congratsSent = false
        addon:debug(Diag.D.LogMLMultiAwardStarted:format(tostring(itemLink), #winners, available, tconcat(candidateSlots, ","), timeout))

        -- Suppress per-copy ChatAward spam during multi-award; announce once on completion.
        announced = true
        return assignItem(itemLink, winners[1].name, lootState.currentRollType, winners[1].roll)
    end

    local function computeAwardTargetAndAvailability()
        local target = tonumber(lootState.selectedItemCount) or 1
        if target < 1 then
            target = 1
        end
        local available = tonumber(Loot:GetCurrentItemCount()) or 1
        if available < 1 then
            available = 1
        end
        if target > available then
            target = available
        end
        if lootState.rollsCount and target > lootState.rollsCount then
            target = lootState.rollsCount
        end
        return target, available
    end

    local function tryAwardMultipleCopies(itemLink, target, available)
        local winners, errType, wantedCount, pickedCount = buildMultiAwardWinners(target)
        if errType == "empty_selection" then
            addon:warn(L.ErrNoWinnerSelected)
            module:ResetItemCount()
            return false
        end
        if errType == "not_enough_selection" then
            addon:warn(Diag.W.ErrMLMultiSelectNotEnough:format(wantedCount or 0, pickedCount or 0))
            module:ResetItemCount()
            return false
        end
        if errType == "empty_winners" or #winners <= 0 then
            addon:warn(L.ErrNoWinnerSelected)
            module:ResetItemCount()
            return false
        end

        local result = startMultiAwardSequence(itemLink, available, winners)
        if result then
            registerAwardedItem(1)
            local done = finalizeMultiAwardIfDone()
            if not done and lootState.multiAward and lootState.multiAward.active then
                armMultiAwardProgressTimeout(lootState.multiAward)
            end
            module:RequestRefresh()
            return true
        end

        clearMultiAwardState(true)
        module:RequestRefresh()
        return false
    end

    local function tryAwardSingleCopy(itemLink, winnerName)
        local selectedWinner = winnerName or lootState.winner
        local result = assignItem(itemLink, selectedWinner, lootState.currentRollType, Rolls:HighestRoll(selectedWinner))
        if result then
            registerAwardedItem(1)
        end
        resetItemCountAndRefresh()
        return result
    end

    local function continueMultiAwardOnLootSlotCleared(clearedSlot)
        local ma = lootState.multiAward
        if not (ma and ma.active and not lootState.fromInventory) then
            return
        end
        local slot = tonumber(clearedSlot)
        if slot then
            ma.lastClearedSlot = slot
        end

        -- Prevent double-scheduling if the loot window fires multiple clear events quickly.
        if ma.scheduled then
            return
        end

        -- Gate: proceed only when the number of copies for this itemKey has decreased since last award.
        local currentCount = getCurrentMultiAwardCount(ma.itemKey)
        if ma.lastCount and currentCount >= ma.lastCount then
            return
        end

        ma.waitingForDecrement = false
        cancelMultiAwardTimeout(ma)
        local refreshedSlots, refreshedSlotMap = buildMultiAwardSlotCandidates(ma.itemLink)
        ma.slotCandidates = refreshedSlots
        ma.slotCandidateMap = refreshedSlotMap
        ma.lastCount = currentCount
        local idx = tonumber(ma.pos) or 1
        local entry = ma.winners and ma.winners[idx]
        if not entry then
            clearMultiAwardState(true)
            module:RequestRefresh()
            return
        end

        ma.scheduled = true
        local delay = tonumber(C.ML_MULTI_AWARD_DELAY) or 0
        if delay < 0 then
            delay = 0
        end

        ma.delayHandle = addon.After(delay, function()
            local ma2 = lootState.multiAward
            if not (ma2 and ma2.active and ma2.scheduled and not lootState.fromInventory) then
                return
            end
            ma2.delayHandle = nil
            ma2.scheduled = false

            local idx2 = tonumber(ma2.pos) or 1
            local e2 = ma2.winners and ma2.winners[idx2]
            if not e2 then
                clearMultiAwardState(true)
                module:RequestRefresh()
                return
            end

            -- Suppress per-copy ChatAward spam during multi-award; announce once on completion.
            announced = true
            ma2.currentWinner = e2.name
            lootState.currentRollType = ma2.rollType
            module:RequestRefresh()

            local ok = assignItem(ma2.itemLink, e2.name, ma2.rollType, e2.roll)
            if ok then
                registerAwardedItem(1)
                ma2.pos = idx2 + 1
                local done = finalizeMultiAwardIfDone()
                if not done and lootState.multiAward and lootState.multiAward.active then
                    armMultiAwardProgressTimeout(lootState.multiAward)
                end
                module:RequestRefresh()
            else
                clearMultiAwardState(true)
                module:RequestRefresh()
            end
        end)
    end

    -- ============================================================================
    -- Award request / trade-state helpers
    -- ============================================================================
    local function handleAwardRequest()
        local model = buildRollUiModel(true) or {}
        local resolution = model.resolution or {}
        local requiredWinnerCount = tonumber(model.requiredWinnerCount) or 1
        local winnerName = model.winner or lootState.winner
        local rerollNames
        local rerollStarted

        if countdownRun then
            addon:warn(Diag.W.LogMLCountdownActive)
            return
        end
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            addon:warn(Diag.W.ErrMLMultiAwardInProgress)
            return
        end
        if lootState.lootCount <= 0 or lootState.rollsCount <= 0 then
            addon:debug(Diag.D.LogMLAwardBlocked:format(lootState.lootCount or 0, lootState.rollsCount or 0))
            return
        end
        if shouldUseTieReroll(model) then
            if not (Rolls and Rolls.BeginTieReroll) then
                addon:warn(L.ErrMLWinnerTieUnresolved)
                return false
            end
            rerollStarted, rerollNames = Rolls:BeginTieReroll(resolution.tiedNames)
            if not rerollStarted then
                addon:warn(L.ErrMLWinnerTieUnresolved)
                return false
            end
            announced = false
            resetRollWinnerSelection(ROLL_SELECTION_MODE.AUTO)
            addon:Announce(L.ChatTieReroll:format(tconcat(rerollNames or {}, ", "), getItemLink() or ""))
            addon:debug(Diag.I.LogMLTieReroll:format(tostring(getItemLink() or ""), tconcat(rerollNames or {}, ",")))
            module:RequestRefresh()
            return true
        end
        if resolution.requiresManualResolution then
            if model.pickMode then
                if (tonumber(model.msCount) or 0) < requiredWinnerCount then
                    addon:warn(L.ErrMLWinnerTieUnresolved)
                    return
                end
            elseif not winnerName then
                addon:warn(L.ErrMLWinnerTieUnresolved)
                return
            end
        end
        if not winnerName then
            addon:warn(L.ErrNoWinnerSelected)
            return
        end

        lootState.winner = winnerName
        countdownRun = false
        local itemLink = getItemLink()
        addon:debug(Diag.D.LogMLAwardRequested:format(tostring(winnerName), tonumber(lootState.currentRollType) or -1, Rolls:HighestRoll(winnerName) or 0, tostring(itemLink)))

        if lootState.fromInventory == true then
            local result = tradeItem(itemLink, winnerName, lootState.currentRollType, Rolls:HighestRoll(winnerName))
            resetItemCountAndRefresh()
            return result
        end

        local target, available = computeAwardTargetAndAvailability()
        if available > 1 then
            return tryAwardMultipleCopies(itemLink, target, available)
        end

        return tryAwardSingleCopy(itemLink, winnerName)
    end

    local function resetTradeState()
        lootState.trader = nil
        lootState.tradeWinner = nil
        lootState.winner = nil
        lootState.tradeItemId = nil
        lootState.tradeItemLink = nil
        itemInfo.tradeStartCount = nil
        itemInfo.tradeStartItemLink = nil
        itemInfo.tradeStartBag = nil
        itemInfo.tradeStartSlot = nil
        screenshotWarn = false
    end

    local function resolveTradeAwardedCount()
        local selected = tonumber(lootState.selectedItemCount) or 1
        if selected < 1 then
            selected = 1
        end

        local before = tonumber(itemInfo.tradeStartCount)
        local after = nil
        local source = "fallback"
        local awarded = 1

        local bag = tonumber(itemInfo.tradeStartBag) or tonumber(itemInfo.bagID)
        local slot = tonumber(itemInfo.tradeStartSlot) or tonumber(itemInfo.slotID)
        if bag and slot and before and before > 0 then
            local expectedLink = itemInfo.tradeStartItemLink or lootState.tradeItemLink or getItemLink()
            local expectedKey = expectedLink and (Item.GetItemStringFromLink(expectedLink) or expectedLink) or nil
            local afterLink = GetContainerItemLink(bag, slot)
            if not afterLink then
                after = 0
            else
                local afterKey = Item.GetItemStringFromLink(afterLink) or afterLink
                if expectedKey and afterKey == expectedKey then
                    local _, count = GetContainerItemInfo(bag, slot)
                    after = tonumber(count) or 1
                else
                    after = 0
                end
            end

            local delta = before - (after or 0)
            if delta > 0 then
                awarded = delta
                source = "delta"
            end
        end

        if awarded < 1 then
            awarded = 1
        end

        addon:debug(Diag.D.LogTradeAwardedCountResolved:format(awarded, source, tostring(before), tostring(after), selected))
        return awarded
    end

    registerAwardedItem = function(count)
        local targetCount = tonumber(lootState.selectedItemCount) or 1
        if targetCount < 1 then
            targetCount = 1
        end
        local increment = tonumber(count) or 1
        if increment < 1 then
            increment = 1
        end
        lootState.itemTraded = (lootState.itemTraded or 0) + increment
        if lootState.itemTraded >= targetCount then
            lootState.itemTraded = 0
            resetRecordedRolls()
            return true
        end
        return false
    end

    -- ----- Public methods ----- --

    function module:Refresh()
        UI.Refresh()
    end

    function module:GetFlowState()
        return syncFlowState()
    end

    function module:SetCurrentItemView(itemName, itemLink, itemTexture, itemColor)
        if not (itemName and itemLink and itemTexture and itemColor) then
            return false
        end

        local frame = getFrame()
        if not frame then
            return false
        end
        frameName = frameName or frame:GetName()
        if not frameName or frameName ~= frame:GetName() then
            return false
        end

        local currentItemLink = _G[frameName .. "Name"]
        local currentItemBtn = _G[frameName .. "ItemBtn"]
        if not (currentItemLink and currentItemBtn) then
            return false
        end

        currentItemLink:SetText(addon.WrapTextInColorCode(itemName, Colors.NormalizeHexColor(itemColor)))
        currentItemBtn:SetNormalTexture(itemTexture)

        local options = addon.options or KRT_Options or {}
        if options.showTooltips then
            currentItemBtn.tooltip_item = itemLink
            Frames.SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
        end
        return true
    end

    function module:ClearCurrentItemView(focusItemCount)
        local frame = getFrame()
        if not frame then
            return false
        end
        frameName = frameName or frame:GetName()
        if not frameName or frameName ~= frame:GetName() then
            return false
        end

        local currentItemLink = _G[frameName .. "Name"]
        local currentItemBtn = _G[frameName .. "ItemBtn"]
        if not (currentItemLink and currentItemBtn) then
            return false
        end

        currentItemLink:SetText(L.StrNoItemSelected)
        currentItemBtn:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        currentItemBtn.tooltip_item = nil
        GameTooltip:Hide()

        local mf = module.frame
        if mf and frameName == mf:GetName() then
            local itemCountBox = _G[frameName .. "ItemCount"]
            if itemCountBox then
                Frames.ResetEditBox(itemCountBox, focusItemCount and true or false)
            end
        end
        return true
    end

    function module:ResetItemCount(focus)
        -- During multi-award from loot window we keep ItemCount stable (target N) to avoid
        -- mid-sequence clamping to the remaining copies.
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return
        end
        setItemCountValue(Loot:GetCurrentItemCount(), focus)
    end

    -- OnLoad frame:
    function module:OnLoad(frame)
        frameName = Frames.InitModuleFrame(module, frame, {
            enableDrag = true,
            hookOnHide = function()
                if selectionFrame then
                    selectionFrame:Hide()
                end
            end,
        })
        if not frameName then
            return
        end
        UI.Loaded = true
        UIFacade:Call("LootCounter", "AttachToMaster", frame)

        -- Initialize ItemBtn scripts once (clean inventory drop support: click-to-drop).
        local itemBtn = _G[frameName .. "ItemBtn"]
        if itemBtn and not itemBtn._krtMlInvDropInit then
            itemBtn._krtMlInvDropInit = true
            itemBtn:RegisterForClicks("AnyUp")
            itemBtn:RegisterForDrag("LeftButton")

            -- Blizz-like gesture support:
            -- - Click while holding an item on the cursor
            -- - Drag&drop (release) an item onto the button
            local function tryAcceptFromCursor()
                if CursorHasItem and CursorHasItem() then
                    module:TryAcceptInventoryItemFromCursor()
                end
            end

            itemBtn:SetScript("OnClick", function(self, button)
                tryAcceptFromCursor()
            end)

            itemBtn:SetScript("OnReceiveDrag", function(self)
                tryAcceptFromCursor()
            end)
        end
    end

    local function BindHandlers(_, frame, refs)
        bindMainControlScripts(frame, refs)
    end

    local function Localize()
        local ok = pcall(UI.Localize)
        if not ok then
            addon:error("[Master] UI localization failed; controls are still bound.")
        end
    end

    local function OnLoadFrame(frame)
        module:OnLoad(frame)
        return frameName
    end

    UIScaffold.DefineModuleUi({
        module = module,
        getFrame = getFrame,
        acquireRefs = UI.AcquireRefs,
        bind = BindHandlers,
        localize = Localize,
        onLoad = OnLoadFrame,
    })

    -- ============================================================================
    -- Button handlers
    -- ============================================================================
    -- Button: Select/Remove Item
    function module:BtnSelectItem(btn)
        if btn == nil or lootState.lootCount <= 0 then
            return
        end
        if countdownRun then
            return
        end
        clearMultiAwardState(false)
        if lootState.fromInventory == true then
            clearLootAndResetRecordedRolls()
            announced = false
            lootState.fromInventory = false
            itemInfo.count = 0
            itemInfo.isStack = nil
            itemInfo.bagID = nil
            itemInfo.slotID = nil
            if lootState.opened == true then
                Loot:FetchLoot()
            end
        elseif selectionFrame then
            UIPrimitives.Toggle(selectionFrame)
        end
        module:RequestRefresh()
    end

    -- Button: Spam Loot Links or Do Ready Check
    function module:BtnSpamLoot(btn)
        if btn == nil or lootState.lootCount <= 0 then
            return
        end
        if lootState.fromInventory == true then
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player")
            local isAssistant = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
            local canReadyCheck = isLeader or isAssistant
            if not canReadyCheck then
                addon:warn(L.WarnReadyCheckNotAllowed)
                return
            end
            addon:Announce(L.ChatReadyCheck)
            DoReadyCheck()
        else
            addon:Announce(L.ChatSpamLoot, "RAID")
            for i = 1, lootState.lootCount do
                local itemLink = getItemLink(i)
                if itemLink then
                    local item = getItem(i)
                    local count = item and item.count or 1
                    local suffix = (count and count > 1) and (" x" .. count) or ""
                    addon:Announce(i .. ". " .. itemLink .. suffix, "RAID")
                end
            end
        end
    end

    -- Button: Reserve List (contextual)
    function module:BtnReserveList(btn)
        local reserves = getReservesService()
        if reserves and reserves.HasData and reserves:HasData() then
            UIFacade:Call("Reserves", "Toggle")
        else
            UIFacade:Call("Reserves", "ToggleImport")
        end
    end

    -- Button: Loot Counter
    function module:BtnLootCounter(btn)
        UIFacade:Call("LootCounter", "Toggle")
    end

    -- ============================================================================
    -- Roll announcement / assignment helpers
    -- ============================================================================
    -- Generic function to announce a roll for the current item.
    local function announceRoll(rollType, chatMsg)
        if lootState.lootCount >= 1 then
            announced = false
            lootState.currentRollType = rollType
            Rolls:ClearRolls()
            Rolls:RecordRolls(true)
            lootState.itemTraded = 0

            local itemLink = getItemLink()
            local itemID = Item.GetItemIdFromLink(itemLink)
            ensureRollSession(itemLink, rollType, lootState.fromInventory and "inventory" or "lootWindow")
            if not Rolls:GetRollSession() then
                lootState.rollStarted = true
            end
            local message

            if rollType == rollTypes.RESERVED then
                -- Chat-safe: keep UI colors in the Reserve Frame, but do not send class color codes in chat.
                local reserves = getReservesService()
                local srList = reserves and reserves.FormatReservedPlayersLine and reserves:FormatReservedPlayersLine(itemID, false, false, false) or ""
                local suff = addon.options.sortAscending and "Low" or "High"
                message = lootState.selectedItemCount > 1 and L[chatMsg .. "Multiple" .. suff]:format(srList, itemLink, lootState.selectedItemCount)
                    or L[chatMsg]:format(srList, itemLink)
            else
                local suff = addon.options.sortAscending and "Low" or "High"
                message = lootState.selectedItemCount > 1 and L[chatMsg .. "Multiple" .. suff]:format(itemLink, lootState.selectedItemCount) or L[chatMsg]:format(itemLink)
            end

            addon:Announce(message)
            _G[frameName .. "ItemCount"]:ClearFocus()
            local session = Rolls:GetRollSession()
            if session and tonumber(session.lootNid) then
                lootState.currentRollItem = session.lootNid
            else
                lootState.currentRollItem = 0
            end
            module:RequestRefresh()
        end
    end

    local function assignToTarget(rollType, targetKey)
        if lootState.lootCount <= 0 or not lootState[targetKey] then
            return
        end
        countdownRun = false
        local itemLink = getItemLink()
        if not itemLink then
            return
        end
        lootState.currentRollType = rollType
        local target = lootState[targetKey]
        local ok
        if lootState.fromInventory then
            ok = tradeItem(itemLink, target, rollType, 0)
        else
            ok = assignItem(itemLink, target, rollType, 0)
        end
        if ok and not lootState.fromInventory then
            announced = false
            Rolls:ClearRolls()
        end
        module:RequestRefresh()
        return ok
    end

    function module:BtnMS(btn)
        return announceRoll(rollTypes.MAINSPEC, rollAnnouncementKeys[rollTypes.MAINSPEC])
    end

    function module:BtnOS(btn)
        return announceRoll(rollTypes.OFFSPEC, rollAnnouncementKeys[rollTypes.OFFSPEC])
    end

    function module:BtnSR(btn)
        return announceRoll(rollTypes.RESERVED, rollAnnouncementKeys[rollTypes.RESERVED])
    end

    function module:BtnFree(btn)
        return announceRoll(rollTypes.FREE, rollAnnouncementKeys[rollTypes.FREE])
    end

    -- Button: left click starts/stops countdown, right click finalizes rolls immediately.
    function module:BtnCountdown(btn, button)
        if countdownRun then
            finalizeRollSession()
        elseif not lootState.rollStarted then
            return
        elseif button == "RightButton" then
            finalizeRollSession()
        else
            local duration = tonumber(addon.options.countdownDuration) or 0
            if duration <= 0 then
                finalizeRollSession()
                return
            end
            Rolls:RecordRolls(true)
            announced = false
            startCountdown()
            module:RequestRefresh()
        end
    end

    -- Button: Clear Rolls
    function module:BtnClear(btn)
        announced = false
        Rolls:ClearRolls()
        module:RequestRefresh()
    end

    -- Button: Award/Trade
    function module:BtnAward(btn)
        return handleAwardRequest()
    end

    -- Button: Hold item
    function module:BtnHold(btn)
        return assignToTarget(rollTypes.HOLD, "holder")
    end

    -- Button: Bank item
    function module:BtnBank(btn)
        return assignToTarget(rollTypes.BANK, "banker")
    end

    -- Button: Disenchant item
    function module:BtnDisenchant(btn)
        return assignToTarget(rollTypes.DISENCHANT, "disenchanter")
    end

    -- Selects an item from the item selection frame.
    function module:BtnSelectedItem(btn)
        if not btn then
            return
        end
        local index = btn:GetID()
        if index ~= nil then
            announced = false
            selectionFrame:Hide()
            Loot:SelectItem(index)
            resetItemCountAndRefresh()
        end
    end

    -- Localizes UI frame elements.
    function UI.Localize()
        if UI.Localized then
            return
        end
        _G[frameName .. "ConfigBtn"]:SetText(L.BtnConfigure)
        _G[frameName .. "SelectItemBtn"]:SetText(L.BtnSelectItem)
        _G[frameName .. "SpamLootBtn"]:SetText(L.BtnSpamLoot)
        _G[frameName .. "MSBtn"]:SetText(L.BtnMS)
        _G[frameName .. "OSBtn"]:SetText(L.BtnOS)
        _G[frameName .. "SRBtn"]:SetText(L.BtnSR)
        _G[frameName .. "FreeBtn"]:SetText(L.BtnFree)
        _G[frameName .. "CountdownBtn"]:SetText(L.BtnCountdown)
        _G[frameName .. "AwardBtn"]:SetText(L.BtnAward)
        _G[frameName .. "RollBtn"]:SetText(L.BtnRoll)
        _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
        _G[frameName .. "HoldBtn"]:SetText(L.BtnHold)
        _G[frameName .. "BankBtn"]:SetText(L.BtnBank)
        _G[frameName .. "DisenchantBtn"]:SetText(L.BtnDisenchant)
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "RollsHeaderPlayer"]:SetText(L.StrPlayer)
        _G[frameName .. "RollsHeaderInfo"]:SetText(L.StrInfo)
        _G[frameName .. "RollsHeaderCounter"]:SetText(L.StrCounter)
        _G[frameName .. "RollsHeaderRoll"]:SetText(L.StrRolls)
        _G[frameName .. "ReserveListBtn"]:SetText(L.BtnInsertList)
        _G[frameName .. "LootCounterBtn"]:SetText(L.BtnLootCounter)
        Frames.SetFrameTitle(frameName, MASTER_LOOTER)

        local itemCountBox = _G[frameName .. "ItemCount"]
        if itemCountBox and not itemCountBox._krtItemCountHooked then
            itemCountBox._krtItemCountHooked = true
            itemCountBox:SetScript("OnTextChanged", function(self, isUserInput)
                if not isUserInput then
                    return
                end
                announced = false
                dirtyFlags.itemCount = true
                dirtyFlags.buttons = true
                module:RequestRefresh()
            end)
            itemCountBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                announced = false
                dirtyFlags.itemCount = true
                dirtyFlags.buttons = true
                module:RequestRefresh()
            end)
            itemCountBox:SetScript("OnEditFocusLost", function(self)
                announced = false
                dirtyFlags.itemCount = true
                dirtyFlags.buttons = true
                module:RequestRefresh()
            end)
        end
        if next(dropDownData) == nil then
            for i = 1, 8 do
                dropDownData[i] = {}
            end
        end
        dropDownFrameHolder = _G[frameName .. "HoldDropDown"]
        dropDownFrameBanker = _G[frameName .. "BankDropDown"]
        dropDownFrameDisenchanter = _G[frameName .. "DisenchantDropDown"]
        prepareDropDowns()
        UIDropDownMenu_Initialize(dropDownFrameHolder, initializeDropDowns)
        UIDropDownMenu_Initialize(dropDownFrameBanker, initializeDropDowns)
        UIDropDownMenu_Initialize(dropDownFrameDisenchanter, initializeDropDowns)
        configureAssignDropDown(dropDownFrameHolder)
        configureAssignDropDown(dropDownFrameBanker)
        configureAssignDropDown(dropDownFrameDisenchanter)
        dropDownsInitialized = true
        hookDropDownOpen(dropDownFrameHolder)
        hookDropDownOpen(dropDownFrameBanker)
        hookDropDownOpen(dropDownFrameDisenchanter)
        refreshDropDowns(true)
        UI.Localized = true
    end

    -- ============================================================================
    -- Roll frame / rendering helpers
    -- ============================================================================
    local function updateItemCountFromBox(itemCountBox)
        -- While a multi-award sequence is running from the loot window, ItemCount represents
        -- the target number of copies to distribute (not the remaining copies). Ignore edits.
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return
        end
        if not itemCountBox or not itemCountBox:IsVisible() then
            return
        end
        local rawCount = itemCountBox:GetText()
        if rawCount ~= lastUIState.itemCountText then
            lastUIState.itemCountText = rawCount
            dirtyFlags.itemCount = true
        end
        if dirtyFlags.itemCount then
            local count = tonumber(rawCount)
            if count and count > 0 then
                lootState.selectedItemCount = count
                updateRollSessionExpectedWinners()
                if lootState.fromInventory and itemInfo.count and itemInfo.count ~= lootState.selectedItemCount then
                    if itemInfo.count < lootState.selectedItemCount then
                        lootState.selectedItemCount = itemInfo.count
                        updateRollSessionExpectedWinners()
                        itemCountBox:SetNumber(itemInfo.count)
                        lastUIState.itemCountText = tostring(itemInfo.count)
                    end
                end
            end
            dirtyFlags.itemCount = false
        end
    end

    local function updateRollStatusState()
        local rollType, record, canRoll, rolled = Rolls:RollStatus()
        local rollStatus = lastUIState.rollStatus
        if rollStatus.record ~= record or rollStatus.canRoll ~= canRoll or rollStatus.rolled ~= rolled or rollStatus.rollType ~= rollType then
            rollStatus.record = record
            rollStatus.canRoll = canRoll
            rollStatus.rolled = rolled
            rollStatus.rollType = rollType
            dirtyFlags.rolls = true
            dirtyFlags.buttons = true
        end
        return record, canRoll, rolled
    end

    local function ensureRollRow(i, scrollChild)
        local btnName = frameName .. "PlayerBtn" .. i
        local btn = _G[btnName]
        if not btn then
            btn = CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")
        end
        if not btn.krtHasOnClick then
            btn:SetScript("OnClick", function(self)
                if selectRollWinnerRow(self.playerName) then
                    module:RequestRefresh()
                end
            end)
            btn.krtHasOnClick = true
        end
        rollRows[i] = btn
        return btn
    end

    local function renderRollRows(model)
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        if not (scrollFrame and scrollChild) then
            return
        end

        local rows = (model and (model.visibleRows or model.rows)) or {}
        local count = #rows

        scrollChild:SetHeight(scrollFrame:GetHeight())
        local contentW = math.max(1, scrollFrame:GetWidth() or 0)
        scrollChild:SetWidth(contentW)

        local totalHeight = 0
        for i = 1, count do
            local data = rows[i]
            local btn = ensureRollRow(i, scrollChild)
            btn:SetID(tonumber(data.id) or i)
            btn.playerName = data.name
            btn:EnableMouse(data.canClick == true)
            btn:Show()

            UIRowVisuals.EnsureRowVisuals(btn)

            local nameStr = _G[btn:GetName() .. "Name"]
            local rollStr = _G[btn:GetName() .. "Roll"]
            local counterStr = _G[btn:GetName() .. "Counter"]
            local infoStr = _G[btn:GetName() .. "Info"]
            local star = _G[btn:GetName() .. "Star"]

            if nameStr then
                local class = data.class or "UNKNOWN"
                if data.isReserved then
                    nameStr:SetVertexColor(0.4, 0.6, 1.0)
                else
                    local r, g, b = Colors.GetClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
                nameStr:SetText(data.displayName or data.name or "")
                nameStr:Show()
            end

            if rollStr then
                rollStr:SetText(tostring(data.roll or ""))
                rollStr:Show()
            end
            if counterStr then
                counterStr:SetText(data.counterText or "")
                counterStr:Show()
            end
            if infoStr then
                infoStr:SetText(data.infoText or "")
                infoStr:Show()
            end

            UIRowVisuals.SetRowSelected(btn, data.isSelected == true)
            UIRowVisuals.SetRowFocused(btn, data.isFocused == true)
            UIPrimitives.ShowHide(star, data.showStar == true)

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end

        local i = count + 1
        local btn = rollRows[i] or _G[frameName .. "PlayerBtn" .. i]
        while btn do
            btn:Hide()
            i = i + 1
            btn = rollRows[i] or _G[frameName .. "PlayerBtn" .. i]
        end
    end

    local function flagButtonsOnChange(key, value)
        if lastUIState[key] ~= value then
            lastUIState[key] = value
            dirtyFlags.buttons = true
        end
    end
    -- Refreshes the UI once (event-driven; coalesced via module:RequestRefresh()).
    function UI.Refresh()
        UI.Localize()
        local currentFlowState = syncFlowState()

        local itemCountBox = _G[frameName .. "ItemCount"]
        updateItemCountFromBox(itemCountBox)

        if dropDownDirty then
            dirtyFlags.dropdowns = true
        end

        local record, canRoll, rolled = updateRollStatusState()
        if lastUIState.rollsCount ~= lootState.rollsCount then
            lastUIState.rollsCount = lootState.rollsCount
            dirtyFlags.rolls = true
            dirtyFlags.buttons = true
        end

        local rollModel = buildRollUiModel(true) or {}

        local displayedWinner = getDisplayedWinnerName(rollModel)
        if lastUIState.winner ~= displayedWinner then
            lastUIState.winner = displayedWinner
            dirtyFlags.winner = true
            dirtyFlags.buttons = true
        end

        flagButtonsOnChange("lootCount", lootState.lootCount)
        flagButtonsOnChange("fromInventory", lootState.fromInventory)
        flagButtonsOnChange("holder", lootState.holder)
        flagButtonsOnChange("banker", lootState.banker)
        flagButtonsOnChange("disenchanter", lootState.disenchanter)

        local reserves = getReservesService()
        local hasReserves = reserves and reserves.HasData and reserves:HasData() or false
        flagButtonsOnChange("hasReserves", hasReserves)

        local hasItem = itemExists()
        flagButtonsOnChange("hasItem", hasItem)

        local itemId
        if hasItem then
            itemId = Item.GetItemIdFromLink(getItemLink())
        end
        local hasItemReserves = itemId and reserves and reserves.HasItemReserves and reserves:HasItemReserves(itemId) or false
        flagButtonsOnChange("hasItemReserves", hasItemReserves)
        flagButtonsOnChange("countdownRun", countdownRun)
        flagButtonsOnChange("flowState", currentFlowState)

        local rollResolution = rollModel.resolution or {}
        local pickMode = rollModel.pickMode == true
        local msCount = pickMode and (tonumber(rollModel.msCount) or 0) or 0
        local canAwardSelection = (not pickMode) or msCount > 0
        local isTieReroll = shouldUseTieReroll(rollModel)
        if rollResolution.requiresManualResolution and pickMode then
            canAwardSelection = msCount >= (tonumber(rollModel.requiredWinnerCount) or 1)
        end
        flagButtonsOnChange("msCount", msCount)
        flagButtonsOnChange("manualResolution", rollResolution.requiresManualResolution == true)

        if dirtyFlags.buttons then
            updateMasterButtonsIfChanged({
                countdownText = countdownRun and L.BtnStop or L.BtnCountdown,
                awardText = isTieReroll and L.BtnReroll or (lootState.fromInventory and TRADE or L.BtnAward),
                selectItemText = lootState.fromInventory and L.BtnRemoveItem or L.BtnSelectItem,
                spamLootText = lootState.fromInventory and READY_CHECK or L.BtnSpamLoot,
                canSelectItem = (lootState.lootCount > 1 or (lootState.fromInventory and lootState.lootCount >= 1)) and not countdownRun,
                canChangeItem = (currentFlowState ~= FLOW_STATES.COUNTDOWN),
                canSpamLoot = lootState.lootCount >= 1,
                canStartRolls = lootState.lootCount >= 1,
                canStartSR = lootState.lootCount >= 1 and hasItemReserves,
                canCountdown = lootState.lootCount >= 1 and hasItem and (lootState.rollStarted or countdownRun),
                canHold = lootState.lootCount >= 1 and lootState.holder,
                canBank = lootState.lootCount >= 1 and lootState.banker,
                canDisenchant = lootState.lootCount >= 1 and lootState.disenchanter,
                canAward = lootState.lootCount >= 1 and lootState.rollsCount >= 1 and not countdownRun and canAwardSelection,
                reserveListText = hasReserves and L.BtnOpenList or L.BtnInsertList,
                canReserveList = true,
                canRoll = record and canRoll and rolled == false and countdownRun,
                canClear = lootState.rollsCount >= 1,
            })
            dirtyFlags.buttons = false
        end

        renderRollRows(rollModel)

        dirtyFlags.rolls = false
        dirtyFlags.winner = false
    end

    -- ============================================================================
    -- Dropdown / item selection helpers
    -- ============================================================================
    -- Initializes the dropdown menus for player selection.
    function initializeDropDowns()
        if UIDROPDOWNMENU_MENU_LEVEL == 2 then
            local g = UIDROPDOWNMENU_MENU_VALUE
            local m = dropDownData[g]
            for key in pairs(m) do
                local info = UIDropDownMenu_CreateInfo()
                info.hasArrow = false
                info.notCheckable = 1
                info.text = key
                info.func = module.OnClickDropDown
                info.arg1 = UIDROPDOWNMENU_OPEN_MENU
                info.arg2 = key
                UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end
        if UIDROPDOWNMENU_MENU_LEVEL == 1 then
            for key in pairs(dropDownData) do
                if dropDownGroupData[key] == true then
                    local info = UIDropDownMenu_CreateInfo()
                    info.hasArrow = 1
                    info.notCheckable = 1
                    info.text = GROUP .. " " .. key
                    info.value = key
                    info.owner = UIDROPDOWNMENU_OPEN_MENU
                    UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
                end
            end
        end
    end

    -- Prepares the data for the dropdowns by fetching the raid roster.
    function prepareDropDowns()
        local rosterVersion = getRaidRosterVersion()
        if rosterVersion and cachedRosterVersion == rosterVersion then
            return
        end
        if rosterVersion ~= cachedRosterVersion then
            invalidateCandidateCache()
        end
        cachedRosterVersion = rosterVersion
        dropDownDirty = true
        dirtyFlags.dropdowns = true

        for i = 1, 8 do
            local t = dropDownData[i]
            if t then
                twipe(t)
            else
                t = {}
                dropDownData[i] = t
            end
        end

        dropDownGroupData = dropDownGroupData or {}
        twipe(dropDownGroupData)

        for unit in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" then
                local subgroup = 1

                -- If we are in raid, resolve the real subgroup.
                local idx = tonumber(unit:match("^raid(%d+)$"))
                if idx then
                    subgroup = (select(3, GetRaidRosterInfo(idx))) or 1
                end

                dropDownData[subgroup] = dropDownData[subgroup] or {}
                dropDownData[subgroup][name] = name
                dropDownGroupData[subgroup] = true
            end
        end

        refreshDropDowns(true)
    end

    module.PrepareDropDowns = prepareDropDowns

    -- Dropdown field metadata: maps frame name suffixes to state keys (lazily bound at runtime).
    local function findDropDownField(frameNameFull)
        if not frameNameFull then
            return nil
        end

        -- Match dropdown frame name to find the field type
        if frameNameFull == dropDownFrameHolder:GetName() then
            return { stateKey = "holder", raidKey = "holder", frame = dropDownFrameHolder }
        elseif frameNameFull == dropDownFrameBanker:GetName() then
            return { stateKey = "banker", raidKey = "banker", frame = dropDownFrameBanker }
        elseif frameNameFull == dropDownFrameDisenchanter:GetName() then
            return { stateKey = "disenchanter", raidKey = "disenchanter", frame = dropDownFrameDisenchanter }
        end
        return nil
    end

    -- OnClick handler for dropdown menu items (consolidated from 3 similar branches).
    function module:OnClickDropDown(owner, value)
        if not addon.Core.GetCurrentRaid() then
            return
        end
        UIDropDownMenu_SetText(owner, value)
        UIDropDownMenu_SetSelectedValue(owner, value)

        local field = findDropDownField(owner:GetName())
        if field then
            local raidStore = Core.GetRaidStoreOrNil("Master.OnClickDropDown", { "GetRaidByIndex" })
            local raid = raidStore and raidStore:GetRaidByIndex(addon.Core.GetCurrentRaid()) or nil
            if raid then
                raid[field.raidKey] = value
                lootState[field.stateKey] = value
            end
        end

        dropDownDirty = true
        dirtyFlags.dropdowns = true
        dirtyFlags.buttons = true
        CloseDropDownMenus()
        module:RequestRefresh()
    end

    -- Updates the text of the dropdowns to reflect the current selection (consolidated from 3 similar branches).
    function updateDropDowns(frame)
        if not frame or not addon.Core.GetCurrentRaid() then
            return
        end

        local field = findDropDownField(frame:GetName())
        if not field then
            return
        end

        -- Sync state from raid data
        local raidStore = Core.GetRaidStoreOrNil("Master.UpdateDropDowns", { "GetRaidByIndex" })
        local raid = raidStore and raidStore:GetRaidByIndex(addon.Core.GetCurrentRaid()) or nil
        if not raid then
            return
        end
        lootState[field.stateKey] = raid[field.raidKey]

        -- Clear if unit is no longer in raid
        if lootState[field.stateKey] and Raid:GetUnitID(lootState[field.stateKey]) == "none" then
            raid[field.raidKey] = nil
            lootState[field.stateKey] = nil
        end

        -- Update UI if value is valid
        if lootState[field.stateKey] then
            UIDropDownMenu_SetText(field.frame, lootState[field.stateKey])
            UIDropDownMenu_SetSelectedValue(field.frame, lootState[field.stateKey])
            dirtyFlags.buttons = true
        end
    end

    -- Creates the item selection frame if it doesn't exist.
    local function createSelectionFrame()
        if selectionFrame == nil then
            local frame = getFrame()
            if not frame then
                return
            end
            selectionFrame = CreateFrame("Frame", nil, frame, "KRTSimpleFrameTemplate")
            selectionFrame:Hide()
        end
        local index = 1
        local btnName = frameName .. "ItemSelectionBtn" .. index
        local btn = _G[btnName]
        while btn ~= nil do
            btn:Hide()
            index = index + 1
            btnName = frameName .. "ItemSelectionBtn" .. index
            btn = _G[btnName]
        end
    end

    -- Updates the item selection frame with the current loot items.
    function updateSelectionFrame()
        createSelectionFrame()
        local height = 5
        for i = 1, lootState.lootCount do
            local btnName = frameName .. "ItemSelectionBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
            btn:SetID(i)
            btn:Show()
            if not btn._krtBound then
                if btn.RegisterForClicks then
                    btn:RegisterForClicks("AnyUp")
                end
                Frames.SafeSetScript(btn, "OnClick", function(self, button)
                    module:BtnSelectedItem(self, button)
                end)
                btn._krtBound = true
            end
            local itemName = getItemName(i)
            local itemNameBtn = _G[btnName .. "Name"]
            local item = getItem(i)
            local count = item and item.count or 1
            if count and count > 1 then
                itemNameBtn:SetText(itemName .. " x" .. count)
            else
                itemNameBtn:SetText(itemName)
            end
            local itemTexture = getItemTexture(i)
            local itemTextureBtn = _G[btnName .. "Icon"]
            itemTextureBtn:SetTexture(itemTexture)
            btn:SetPoint("TOPLEFT", selectionFrame, "TOPLEFT", 0, -height)
            height = height + 37
        end
        selectionFrame:SetHeight(height)
        if lootState.lootCount <= 0 then
            selectionFrame:Hide()
        end
    end

    -- ----- Event Handlers & Callbacks ----- --

    -- ============================================================================
    -- Inventory / cursor helpers
    -- ============================================================================
    local function scanTradeableInventory(itemLink, itemId)
        if not itemLink and not itemId then
            return nil
        end
        local wantedKey = itemLink and (Item.GetItemStringFromLink(itemLink) or itemLink) or nil
        local wantedId = tonumber(itemId) or (itemLink and Item.GetItemIdFromLink(itemLink)) or nil
        local totalCount = 0
        local firstBag, firstSlot, firstSlotCount
        local hasMatch = false
        -- Backpack (0) + 4 bag slots (1..4) in WoW 3.3.5a.
        for bag = 0, 4 do
            local n = GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local key = Item.GetItemStringFromLink(link) or link
                    local linkId = Item.GetItemIdFromLink(link)
                    local matches = (wantedKey and key == wantedKey) or (wantedId and linkId == wantedId)
                    if matches then
                        hasMatch = true
                        if not itemIsSoulbound(bag, slot) then
                            local _, count = GetContainerItemInfo(bag, slot)
                            local slotCount = tonumber(count) or 1
                            totalCount = totalCount + slotCount
                            if not firstBag then
                                firstBag = bag
                                firstSlot = slot
                                firstSlotCount = slotCount
                            end
                        end
                    end
                end
            end
        end
        return totalCount, firstBag, firstSlot, firstSlotCount, hasMatch
    end

    local function applyInventoryItem(itemLink, totalCount, inBag, inSlot, slotCount)
        if countdownRun then
            return false
        end
        if not itemLink then
            return false
        end
        local itemCount = tonumber(totalCount) or 1
        if itemCount < 1 then
            itemCount = 1
        end

        -- Clear count:
        Frames.ResetEditBox(_G[frameName .. "ItemCount"], true)

        lootState.fromInventory = true
        Loot:AddItem(itemLink, itemCount)
        Loot:PrepareItem()
        announced = false

        itemInfo.bagID = inBag
        itemInfo.slotID = inSlot
        itemInfo.count = itemCount
        itemInfo.isStack = (tonumber(slotCount) or 1) > 1

        ClearCursor()
        resetItemCountAndRefresh(true)
        return true
    end

    -- Accept an item currently held on the cursor (bag click-pickup).
    -- This is triggered by ItemBtn's OnClick.
    function module:TryAcceptInventoryItemFromCursor()
        if countdownRun then
            return false
        end
        if not CursorHasItem or not CursorHasItem() then
            return false
        end

        local infoType, itemId, itemLink = GetCursorInfo()
        if infoType ~= "item" then
            return false
        end

        local totalCount, bag, slot, slotCount, hasMatch = scanTradeableInventory(itemLink, itemId)
        if not totalCount or totalCount < 1 then
            local itemRef = tostring(itemLink or itemId or "unknown")
            if hasMatch then
                addon:warn(L.ErrMLInventorySoulbound:format(itemRef))
                addon:debug(Diag.D.LogMLInventorySoulbound:format(itemRef))
            else
                addon:warn(L.ErrMLInventoryItemMissing:format(itemRef))
            end
            ClearCursor()
            return true
        end

        if not itemLink and bag and slot then
            itemLink = GetContainerItemLink(bag, slot)
        end
        if not itemLink then
            addon:warn(L.ErrMLInventoryItemMissing:format(tostring(itemLink or itemId or "unknown")))
            ClearCursor()
            return true
        end

        return applyInventoryItem(itemLink, totalCount, bag, slot, slotCount)
    end

    -- ============================================================================
    -- Loot window helpers / event flow
    -- ============================================================================
    local function refreshAndMaybeShowLootFrame(shouldShow)
        local frame
        if shouldShow then
            frame = module:EnsureUI() or getFrame()
        else
            frame = getFrame()
        end
        if not shouldShow then
            return frame, false
        end

        if not frame then
            return nil, false
        end

        -- Request while hidden to refresh immediately on OnShow (avoid an extra refresh).
        module:RequestRefresh()
        if frame and not frame:IsShown() then
            frame:Show()
        end
        return frame, true
    end

    local function handleLootOpenedVisibility()
        local shouldShow = (lootState.lootCount or 0) >= 1
        if shouldShow then
            refreshAndMaybeShowLootFrame(true)
        else
            -- Keep state dirty for the next time the frame is shown.
            module:RequestRefresh()
        end
    end

    local function handleLootSlotClearedVisibility()
        local shouldShow = (lootState.lootCount or 0) >= 1
        local frame, shown = refreshAndMaybeShowLootFrame(shouldShow)
        if shown then
            return
        end

        if frame then
            frame:Hide()
        end
        addon:debug(Diag.D.LogMLLootWindowEmptied)
    end

    local function completeLootClosedCleanup()
        lootState.opened = false
        Loot:PurgePendingAwards(PENDING_AWARD_TTL_SECONDS)
        local frame = getFrame()
        if frame then
            frame:Hide()
        end
        clearLootAndResetRecordedRolls()
        module:RequestRefresh()
    end

    local function cancelLootClosedCleanup()
        if lootState.closeTimer then
            addon.CancelTimer(lootState.closeTimer)
            lootState.closeTimer = nil
        end
    end

    local function scheduleLootClosedCleanup()
        -- Cancel any scheduled close timer and schedule a new one.
        cancelLootClosedCleanup()

        lootState.closeTimer = addon.NewTimer(0.1, function()
            lootState.closeTimer = nil
            completeLootClosedCleanup()
        end)
    end

    -- LOOT_OPENED: Triggered when the loot window opens.
    function module:LOOT_OPENED()
        cancelLootClosedCleanup()
        if Raid:IsMasterLooter() then
            lootState.opened = true
            announced = false
            Loot:FetchLoot()
            addon:trace(Diag.D.LogMLLootOpenedTrace:format(lootState.lootCount or 0, tostring(lootState.fromInventory)))
            updateSelectionFrame()
            addon:debug(Diag.D.LogMLLootOpenedInfo:format(lootState.lootCount or 0, tostring(lootState.fromInventory), tostring(UnitName("target"))))
            handleLootOpenedVisibility()
        end
    end

    -- LOOT_CLOSED: Triggered when the loot window closes.
    function module:LOOT_CLOSED()
        if Raid:IsMasterLooter() then
            addon:trace(Diag.D.LogMLLootClosed:format(tostring(lootState.opened), lootState.lootCount or 0))
            addon:trace(Diag.D.LogMLLootClosedCleanup)
            clearMultiAwardState(false)
            scheduleLootClosedCleanup()
        end
    end

    -- LOOT_SLOT_CLEARED: Triggered when an item is looted.
    function module:LOOT_SLOT_CLEARED(clearedSlot)
        if Raid:IsMasterLooter() then
            Loot:FetchLoot()
            addon:trace(Diag.D.LogMLLootSlotCleared:format(lootState.lootCount or 0))
            updateSelectionFrame()
            module:ResetItemCount()
            handleLootSlotClearedVisibility()

            -- Continue a multi-award sequence (loot window only).
            continueMultiAwardOnLootSlotCleared(clearedSlot)
        end
    end

    function module:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
        local tradeWinner = getCurrentTradeWinner()
        addon:trace(Diag.D.LogTradeAcceptUpdate:format(tostring(lootState.trader), tostring(tradeWinner), tostring(tAccepted), tostring(pAccepted)))
        if lootState.trader and tradeWinner and lootState.trader ~= tradeWinner then
            if tAccepted == 1 and pAccepted == 1 then
                local awardedCount = resolveTradeAwardedCount()
                local rollValue = Rolls:HighestRoll(tradeWinner)
                local lootNid, createdTradeOnly =
                    ensureTradeLootContext(lootState.tradeItemLink or getItemLink(), tradeWinner, lootState.currentRollType, rollValue, awardedCount, "TRADE_ACCEPT_NO_CONTEXT")
                if lootNid > 0 and createdTradeOnly then
                    addon:warn(
                        Diag.W.LogTradeNoLootContextTradeOnly:format(tostring(lootNid), tostring(tradeWinner), tostring(lootState.tradeItemLink or getItemLink()), awardedCount)
                    )
                end

                addon:debug(Diag.D.LogTradeCompleted:format(tostring(lootState.currentRollItem), tostring(tradeWinner), tonumber(lootState.currentRollType) or -1, rollValue))
                if lootNid > 0 then
                    local ok = requestLoggerLootLog(lootNid, tradeWinner, lootState.currentRollType, rollValue, "TRADE_ACCEPT", addon.Core.GetCurrentRaid())

                    if not ok then
                        addon:error(
                            Diag.E.LogTradeLoggerLogFailed:format(tostring(addon.Core.GetCurrentRaid()), tostring(lootNid), tostring(lootState.tradeItemLink or getItemLink()))
                        )
                    end
                else
                    addon:warn(
                        Diag.W.LogTradeCurrentRollItemMissingContext:format(
                            tostring(tradeWinner),
                            tostring(lootState.tradeItemId),
                            tostring(lootState.tradeItemLink or getItemLink())
                        )
                    )
                end

                local completedWinner = tradeWinner
                completeInventoryAwardProgress(completedWinner, lootState.currentRollType, awardedCount)
            end
        end
    end

    -- TRADE_CLOSED: trade window closed (completed or canceled)
    function module:TRADE_CLOSED()
        resetTradeState()
        module:RequestRefresh()
    end

    -- TRADE_REQUEST_CANCEL: trade request canceled before opening
    function module:TRADE_REQUEST_CANCEL()
        resetTradeState()
        module:RequestRefresh()
    end

    -- ============================================================================
    -- Assignment / trade execution
    -- ============================================================================
    -- Assigns an item from the loot window to a player.
    function assignItem(itemLink, playerName, rollType, rollValue)
        local itemIndex = findLootSlotIndex(itemLink)
        if itemIndex == nil then
            addon:error(L.ErrCannotFindItem:format(itemLink))
            return false
        end

        if not (Raid and Raid.IsMasterLooter and Raid:IsMasterLooter()) then
            addon:warn(L.WarnMLNoPermission)
            refreshCandidateUiState()
            module:RequestRefresh()
            return false
        end

        local validation = validateAwardWinner(playerName, itemLink, rollType)
        if not (validation and validation.ok == true) then
            addon:warn((validation and validation.warnMessage) or L.ErrMLWinnerIneligible:format(tostring(playerName)))
            refreshCandidateUiState()
            module:RequestRefresh()
            return false
        end

        local candidateIndex = resolveCandidateIndex(itemLink, playerName)
        if candidateIndex then
            -- Mark this award as addon-driven so AddLoot() won't classify it as MANUAL
            local session = ensureRollSession(itemLink, rollType, lootState.fromInventory and "inventory" or "lootWindow")
            Loot:QueuePendingAward(itemLink, playerName, rollType, rollValue, session and session.id or nil)
            GiveMasterLoot(itemIndex, candidateIndex)
            addon:debug(
                Diag.D.LogMLAwarded:format(
                    tostring(itemLink),
                    tostring(playerName),
                    tonumber(rollType) or -1,
                    tonumber(rollValue) or 0,
                    tonumber(itemIndex) or -1,
                    tonumber(candidateIndex) or -1
                )
            )
            local output, whisper = buildAssignMessages(itemLink, playerName, rollType)

            if output and not announced then
                addon:Announce(output)
                announced = true
            end
            if whisper then
                Comms.Whisper(playerName, whisper)
            end
            -- IMPORTANT:
            -- Do NOT force-update an existing raid.loot entry here.
            -- For Master Loot awards from the loot window, the authoritative record is created by Raid:AddLoot()
            -- from the LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event, where we also apply the pending rollType/rollValue.
            --
            -- If multiple identical items are distributed across different roll types ("partial award" workflow),
            -- using a pre-resolved lootNid can overwrite previous entries because GetLootID() matches by itemId.
            -- Keeping the logging entirely event-driven avoids that class of data corruption.
            return true
        end

        if not next(candidateCache.indexByName) then
            addon:warn(L.WarnMLNoCandidatesAvailable)
        else
            addon:warn(L.WarnMLWinnerNoCandidate:format(tostring(playerName)))
        end
        refreshCandidateUiState()
        module:RequestRefresh()
        return false
    end

    -- ============================================================================
    -- Trade / inventory execution helpers
    -- ============================================================================
    local function buildTradeInitialOutput(itemLink, playerName, rollType, isAwardRoll)
        if isAwardRoll and addon.options.announceOnWin then
            return L.ChatAward:format(playerName, itemLink)
        end
        if rollType == rollTypes.HOLD and addon.options.announceOnHold then
            return L.ChatNoneRolledHold:format(itemLink, playerName)
        end
        if rollType == rollTypes.BANK and addon.options.announceOnBank then
            return L.ChatNoneRolledBank:format(itemLink, playerName)
        end
        if rollType == rollTypes.DISENCHANT and addon.options.announceOnDisenchant then
            return L.ChatNoneRolledDisenchant:format(itemLink, playerName)
        end
        return nil
    end

    local function buildTradeKeepWhisper(itemLink, rollType)
        if rollType == rollTypes.HOLD then
            return L.WhisperHoldTrade:format(itemLink)
        end
        if rollType == rollTypes.BANK then
            return L.WhisperBankTrade:format(itemLink)
        end
        if rollType == rollTypes.DISENCHANT then
            return L.WhisperDisenchantTrade:format(itemLink)
        end
        return nil
    end

    local function resolveInventoryAwardedCount()
        local awardedCount = tonumber(lootState.selectedItemCount) or 1
        if awardedCount < 1 then
            awardedCount = 1
        end
        if lootState.fromInventory and awardedCount > 1 then
            awardedCount = 1
        end
        return awardedCount
    end

    local function resolveTradeExecutionWinner(playerName, isAwardRoll)
        if not isAwardRoll then
            return nil
        end

        local winner = playerName or getResolvedRollWinnerName()
        local multiInventoryAward = lootState.fromInventory and ((tonumber(lootState.selectedItemCount) or 1) > 1)
        if multiInventoryAward then
            local rollModel = buildRollUiModel(true)
            local picked = getSelectedRollWinnersOrdered(rollModel and rollModel.rows or nil)
            if picked[1] and picked[1].name then
                winner = picked[1].name
            end
        end

        return winner
    end

    advanceInventoryWinnerSelection = function(completedWinner)
        if not lootState.fromInventory then
            return
        end
        if (tonumber(lootState.selectedItemCount) or 1) <= 1 then
            return
        end

        local selCount = MultiSelect.MultiSelectCount(ROLL_WINNERS_CTX) or 0
        if selCount <= 0 then
            lootState.winner = nil
            return
        end

        if completedWinner and MultiSelect.MultiSelectIsSelected(ROLL_WINNERS_CTX, completedWinner) then
            MultiSelect.MultiSelectToggle(ROLL_WINNERS_CTX, completedWinner, true)
            if MultiSelect.MultiSelectGetAnchor and MultiSelect.MultiSelectGetAnchor(ROLL_WINNERS_CTX) == completedWinner then
                MultiSelect.MultiSelectSetAnchor(ROLL_WINNERS_CTX, nil)
            end
        end

        invalidateRollUiModel()
        buildRollUiModel(true)
    end

    completeInventoryAwardProgress = function(completedWinner, rollType, awardedCount)
        if tonumber(rollType) == rollTypes.MAINSPEC and completedWinner and completedWinner ~= "" then
            Raid:AddPlayerCount(completedWinner, awardedCount, addon.Core.GetCurrentRaid())
        end

        local done = registerAwardedItem(awardedCount)
        resetTradeState()
        if not done then
            advanceInventoryWinnerSelection(completedWinner)
        end
        if done then
            Loot:ClearLoot()
            Raid:ClearRaidIcons()
        end
        screenshotWarn = false
        module:RequestRefresh()
        return done
    end

    local function buildTradeMultiWinnersOutput(currentWinner)
        Raid:ClearRaidIcons()
        if lootState.trader ~= currentWinner then
            SetRaidTarget(lootState.trader, 1)
        end

        local winners = {}
        local rollModel = buildRollUiModel(true)
        local rolls = getSelectedRollWinnersOrdered(rollModel and rollModel.rows or nil)
        local maxWinners = #rolls
        if maxWinners <= 0 then
            rolls = Rolls:GetRolls()
            maxWinners = tonumber(lootState.selectedItemCount) or 0
        end
        for i = 1, maxWinners do
            local roll = rolls[i]
            if roll then
                if roll.name == lootState.trader then
                    if lootState.trader ~= currentWinner then
                        tinsert(winners, "{star} " .. roll.name .. "(" .. roll.roll .. ")")
                    else
                        tinsert(winners, roll.name .. "(" .. roll.roll .. ")")
                    end
                else
                    SetRaidTarget(roll.name, i + 1)
                    tinsert(winners, RAID_TARGET_MARKERS[i] .. " " .. roll.name .. "(" .. roll.roll .. ")")
                end
            end
        end

        return L.ChatTradeMutiple:format(tconcat(winners, ", "), lootState.trader)
    end

    local function resolveTradeableInventoryItem(itemLink)
        local totalCount, bag, slot, slotCount
        local usedFastPath = false
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        local wantedId = Item.GetItemIdFromLink(itemLink)

        -- Fast-path: reuse the previously selected bag slot when still valid.
        local cachedBag = tonumber(itemInfo.bagID)
        local cachedSlot = tonumber(itemInfo.slotID)
        if cachedBag and cachedSlot then
            local cachedLink = GetContainerItemLink(cachedBag, cachedSlot)
            if cachedLink then
                local cachedKey = Item.GetItemStringFromLink(cachedLink) or cachedLink
                local cachedId = Item.GetItemIdFromLink(cachedLink)
                local sameItem = (wantedKey and cachedKey == wantedKey) or (wantedId and cachedId == wantedId)
                if sameItem and not itemIsSoulbound(cachedBag, cachedSlot) then
                    local _, count = GetContainerItemInfo(cachedBag, cachedSlot)
                    bag = cachedBag
                    slot = cachedSlot
                    slotCount = tonumber(count) or 1
                    usedFastPath = true
                end
            end
        end

        if not (bag and slot) then
            totalCount, bag, slot, slotCount = scanTradeableInventory(itemLink, wantedId)
        elseif usedFastPath then
            if (tonumber(lootState.selectedItemCount) or 1) > 1 then
                totalCount = scanTradeableInventory(itemLink, wantedId)
            else
                totalCount = tonumber(slotCount) or 1
            end
        end

        if not (bag and slot) then
            return nil
        end

        return {
            bag = bag,
            slot = slot,
            slotCount = tonumber(slotCount) or 1,
            totalCount = tonumber(totalCount) or tonumber(slotCount) or 1,
        }
    end

    local function prepareTradeableItem(itemLink)
        local itemData = resolveTradeableInventoryItem(itemLink)
        if not itemData then
            addon:warn(L.ErrMLInventoryItemMissing:format(tostring(itemLink)))
            return false
        end

        itemInfo.bagID = itemData.bag
        itemInfo.slotID = itemData.slot
        itemInfo.slotCount = itemData.slotCount
        itemInfo.isStack = itemData.slotCount > 1
        itemInfo.count = itemData.totalCount

        if itemInfo.isStack and not addon.options.ignoreStacks then
            addon:debug(Diag.D.LogTradeStackBlocked:format(tostring(addon.options.ignoreStacks), tostring(itemLink)))
            addon:warn(L.ErrItemStack:format(itemLink))
            return false
        end

        return true
    end

    local function tryInitiateTrade(itemLink, playerName, isAwardRoll)
        local unit = Raid:GetUnitID(playerName)
        if unit == "none" then
            return true, nil
        end

        if CheckInteractDistance(unit, 2) ~= 1 then
            addon:warn(Diag.W.LogTradeDelayedOutOfRange:format(tostring(playerName), tostring(itemLink)))
            Raid:ClearRaidIcons()
            SetRaidTarget(lootState.trader, 1)
            if isAwardRoll then
                SetRaidTarget(playerName, 4)
            end
            return true, L.ChatTrade:format(playerName, itemLink)
        end

        if not prepareTradeableItem(itemLink) then
            return false, nil
        end

        local _, startCount = GetContainerItemInfo(itemInfo.bagID, itemInfo.slotID)
        itemInfo.tradeStartCount = tonumber(startCount) or tonumber(itemInfo.slotCount) or 1
        itemInfo.tradeStartBag = itemInfo.bagID
        itemInfo.tradeStartSlot = itemInfo.slotID
        itemInfo.tradeStartItemLink = GetContainerItemLink(itemInfo.bagID, itemInfo.slotID)

        ClearCursor()
        PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
        if CursorHasItem() then
            InitiateTrade(playerName)
            addon:debug(Diag.D.LogTradeInitiated:format(tostring(itemLink), tostring(playerName)))
            if addon.options.screenReminder and not screenshotWarn then
                addon:warn(L.ErrScreenReminder)
                screenshotWarn = true
            end
        end

        return true, nil
    end

    local function finalizeTradeNotifications(itemLink, playerName, rollType, rollValue, output, whisper)
        if announced then
            return true
        end

        if output then
            addon:Announce(output)
        end
        if whisper then
            if playerName == lootState.trader then
                clearLootAndResetRecordedRolls()
            else
                Comms.Whisper(playerName, whisper)
            end
        end
        announced = true
        return true
    end

    -- Trades an item from inventory to a player.
    function tradeItem(itemLink, playerName, rollType, rollValue)
        if itemLink ~= getItemLink() then
            return
        end
        local isAwardRoll = (rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE)
        local winnerName
        ensureRollSession(itemLink, rollType, lootState.fromInventory and "inventory" or "lootWindow")

        resetTradeState()

        lootState.trader = Core.GetPlayerName()
        winnerName = resolveTradeExecutionWinner(playerName, isAwardRoll)
        lootState.tradeItemLink = itemLink
        lootState.tradeItemId = Item.GetItemIdFromLink(itemLink)

        if isAwardRoll and (not winnerName or winnerName == "") then
            addon:warn(L.ErrNoWinnerSelected)
            resetTradeState()
            return false
        end
        if isAwardRoll then
            local validation = validateAwardWinner(winnerName, itemLink, rollType)
            if not (validation and validation.ok == true) then
                addon:warn((validation and validation.warnMessage) or L.ErrMLWinnerIneligible:format(tostring(winnerName)))
                resetTradeState()
                return false
            end
        end
        lootState.tradeWinner = winnerName

        addon:debug(
            Diag.D.LogTradeStart:format(
                tostring(itemLink),
                tostring(lootState.trader),
                tostring(winnerName or playerName),
                tonumber(rollType) or -1,
                tonumber(rollValue) or 0,
                lootState.selectedItemCount or 1
            )
        )

        -- Prepare initial output and whisper:
        local output = buildTradeInitialOutput(itemLink, winnerName or playerName, rollType, isAwardRoll)
        local whisper
        local keep = not isAwardRoll

        -- Keeping the item:
        if keep then
            whisper = buildTradeKeepWhisper(itemLink, rollType)
        elseif lootState.selectedItemCount > 1 then
            output = buildTradeMultiWinnersOutput(winnerName)
        end

        if not keep and lootState.trader == winnerName then
            -- Trader won: complete the current inventory award step without opening a trade window.
            addon:debug(Diag.D.LogTradeTraderKeeps:format(tostring(itemLink), tostring(winnerName)))
            local awardedCount = resolveInventoryAwardedCount()
            local lootNid, createdTradeOnly = ensureTradeLootContext(itemLink, winnerName, rollType, rollValue, awardedCount, "TRADE_KEEP_NO_CONTEXT")
            if lootNid <= 0 then
                addon:error(Diag.E.LogTradeKeepLoggerFailed:format(tostring(addon.Core.GetCurrentRaid()), tostring(lootNid), tostring(itemLink)))
            elseif createdTradeOnly ~= true then
                local ok = requestLoggerLootLog(lootNid, winnerName, rollType, rollValue, "TRADE_KEEP", addon.Core.GetCurrentRaid())
                if not ok then
                    addon:error(Diag.E.LogTradeKeepLoggerFailed:format(tostring(addon.Core.GetCurrentRaid()), tostring(lootNid), tostring(itemLink)))
                end
            end

            finalizeTradeNotifications(itemLink, winnerName, rollType, rollValue, output, whisper)
            completeInventoryAwardProgress(winnerName, rollType, awardedCount)
            return true
        end

        if not keep then
            local ok, outputOverride = tryInitiateTrade(itemLink, winnerName, isAwardRoll)
            if not ok then
                return false
            end
            if outputOverride then
                output = outputOverride
            end
        end

        return finalizeTradeNotifications(itemLink, winnerName or playerName, rollType, rollValue, output, whisper)
    end

    -- ============================================================================
    -- Bus callbacks
    -- ============================================================================
    -- Register some callbacks:
    local wowForwardEvents = {
        "LOOT_OPENED",
        "LOOT_CLOSED",
        "LOOT_SLOT_CLEARED",
        "TRADE_ACCEPT_UPDATE",
        "TRADE_REQUEST_CANCEL",
        "TRADE_CLOSED",
    }

    for i = 1, #wowForwardEvents do
        local methodName = wowForwardEvents[i]
        local wowEventName = Events.WowForwarded and Events.WowForwarded(methodName)
        Bus.RegisterCallback(wowEventName, function(_, ...)
            local fn = module[methodName]
            if fn then
                fn(module, ...)
            end
        end)
    end

    Bus.RegisterCallback(InternalEvents.SetItem, function(_, itemLink, itemData)
        if itemLink ~= nil and type(itemLink) ~= "string" then
            addon:warn(Diag.W.LogMLSetItemPayloadInvalid:format(tostring(itemLink), type(itemData)))
            return
        end
        if itemData ~= nil and type(itemData) ~= "table" then
            addon:warn(Diag.W.LogMLSetItemPayloadInvalid:format(tostring(itemLink), type(itemData)))
            return
        end

        if lastUIState.currentItemLink ~= itemLink then
            announced = false
            lastUIState.currentItemLink = itemLink
        end

        if itemData and itemData.itemName and itemData.itemTexture and itemData.itemColor and itemData.itemLink then
            module:SetCurrentItemView(itemData.itemName, itemData.itemLink, itemData.itemTexture, itemData.itemColor)
            module:ResetItemCount()
        else
            module:ClearCurrentItemView(true)
        end

        module:RequestRefresh()
    end)

    Bus.RegisterCallback(InternalEvents.RaidRosterDelta, function(_, delta, rosterVersion, raidId)
        local raidIdType = type(raidId)
        if type(delta) ~= "table" then
            addon:warn(Diag.W.LogMLRaidRosterDeltaPayloadInvalid:format(type(delta), tostring(rosterVersion), tostring(raidId)))
            return
        end
        if type(rosterVersion) ~= "number" then
            addon:warn(Diag.W.LogMLRaidRosterDeltaPayloadInvalid:format(type(delta), tostring(rosterVersion), tostring(raidId)))
            return
        end
        if raidId == nil then
            addon:warn(Diag.W.LogMLRaidRosterDeltaPayloadInvalid:format(type(delta), tostring(rosterVersion), tostring(raidId)))
            return
        end
        if raidIdType ~= "number" and raidIdType ~= "string" then
            addon:warn(Diag.W.LogMLRaidRosterDeltaPayloadInvalid:format(type(delta), tostring(rosterVersion), tostring(raidId)))
            return
        end

        refreshCandidateUiState()
        module:RequestRefresh()
    end)

    -- Keep Master UI in sync when SoftRes data changes (import/clear), event-driven.
    Bus.RegisterCallback(InternalEvents.ReservesDataChanged, function()
        module:RequestRefresh()
    end)

    Bus.RegisterCallback(InternalEvents.AddRoll, function(_, name, roll)
        if type(name) ~= "string" or name == "" or tonumber(roll) == nil then
            addon:warn(Diag.W.LogMLAddRollPayloadInvalid:format(tostring(name), tostring(roll)))
            return
        end
        module:RequestRefresh()
    end)

    Bus.RegisterCallback(InternalEvents.ConfigSortAscending, function()
        module:RequestRefresh()
    end)

    -- Immediate redraw when toggling the optional +N column in MS roll list.
    Bus.RegisterCallback(InternalEvents.ConfigShowLootCounterDuringMSRoll, function()
        module:RequestRefresh()
    end)
end
