--[[
    Features/Master.lua
]]

local addon = select(2, ...)
addon = addon or {}

local feature = (addon.Core and addon.Core.getFeatureShared and addon.Core.getFeatureShared()) or {}

local L = feature.L or addon.L or {}
local Diag = feature.Diag or {}
local Utils = feature.Utils or addon.Utils
local C = feature.C or addon.C or {}
local Core = feature.Core or addon.Core or {}

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh or Core.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide or Core.bindModuleToggleHide

local rollTypes = feature.rollTypes or C.rollTypes
local RAID_TARGET_MARKERS = feature.RAID_TARGET_MARKERS or C.RAID_TARGET_MARKERS

local lootState = feature.lootState or ((feature.coreState or addon.State or {}).loot) or {}
local itemInfo = feature.itemInfo or lootState.itemInfo or {}

local ItemExists, ItemIsSoulbound, GetItem
local GetItemName, GetItemLink, GetItemTexture

local _G = _G
local tinsert, tconcat, twipe = table.insert, table.concat, table.wipe
local pairs, select, next = pairs, select, next

local tostring, tonumber = tostring, tonumber

local function getLootModule()
    return addon.Loot
end

GetItem = function(i)
    local loot = getLootModule()
    return loot and loot.GetItem and loot.GetItem(i) or nil
end

GetItemName = function(i)
    local loot = getLootModule()
    return loot and loot.GetItemName and loot.GetItemName(i) or nil
end

GetItemLink = function(i)
    local loot = getLootModule()
    return loot and loot.GetItemLink and loot.GetItemLink(i) or nil
end

GetItemTexture = function(i)
    local loot = getLootModule()
    return loot and loot.GetItemTexture and loot.GetItemTexture(i) or nil
end

ItemExists = function(i)
    local loot = getLootModule()
    return loot and loot.ItemExists and loot.ItemExists(i) or false
end

ItemIsSoulbound = function(bag, slot)
    local loot = getLootModule()
    return loot and loot.ItemIsSoulbound and loot.ItemIsSoulbound(bag, slot) or false
end

-- =========== Master Looter Frame Module  =========== --
do
    addon.Master = addon.Master or {}
    local module = addon.Master
    local frameName

    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame

    local getFrame = Utils.makeFrameGetter("KRTMaster")

    bindModuleRequestRefresh(module, getFrame)

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    local InitializeDropDowns, PrepareDropDowns, UpdateDropDowns
    local dropDownData, dropDownGroupData = {}, {}
    -- Ensure subgroup tables exist even when the Master UI hasn't been opened yet.
    for i = 1, 8 do dropDownData[i] = dropDownData[i] or {} end
    local dropDownFrameHolder, dropDownFrameBanker, dropDownFrameDisenchanter
    local dropDownsInitialized
    local dropDownDirty = true

    local selectionFrame, UpdateSelectionFrame

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

    local AssignItem, TradeItem
    local screenshotWarn = false

    local announced = false
    local cachedRosterVersion
    local candidateCache = {
        itemLink = nil,
        indexByName = {},
    }

    -- ----- Private helpers ----- --
    local function SetItemCountValue(count, focus)
        local frame = getFrame()
        if not frame then return end
        frameName = frameName or frame:GetName()
        if not frameName or frameName ~= frame:GetName() then return end
        local itemCountBox = _G[frameName .. "ItemCount"]
        if not itemCountBox then return end
        count = tonumber(count) or 1
        if count < 1 then count = 1 end
        lootState.itemCount = count
        Utils.setEditBoxValue(itemCountBox, count, focus)
        lastUIState.itemCountText = tostring(count)
        dirtyFlags.itemCount = false
    end

    function module:ResetItemCount(focus)
        -- During multi-award from loot window we keep ItemCount stable (target N) to avoid
        -- mid-sequence clamping to the remaining copies.
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return
        end
        SetItemCountValue(addon.Loot:GetCurrentItemCount(), focus)
    end

    local function StopCountdown()
        -- Cancel active countdown timers and clear their handles
        addon.CancelTimer(countdownTicker, true)
        addon.CancelTimer(countdownEndTimer, true)
        countdownTicker = nil
        countdownEndTimer = nil
        countdownRun = false
    end

    local function ShouldAnnounceCountdownTick(remaining, duration)
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

    local function StartCountdown()
        StopCountdown()
        countdownRun = true
        local duration = addon.options.countdownDuration or 0
        local remaining = duration
        if ShouldAnnounceCountdownTick(remaining, duration) then
            addon:Announce(L.ChatCountdownTic:format(remaining))
        end
        countdownTicker = addon.NewTicker(1, function()
            remaining = remaining - 1
            if remaining > 0 then
                if ShouldAnnounceCountdownTick(remaining, duration) then
                    addon:Announce(L.ChatCountdownTic:format(remaining))
                end
            end
        end, duration)
        countdownEndTimer = addon.NewTimer(duration, function()
            if not countdownRun then return end
            StopCountdown()
            addon:Announce(L.ChatCountdownEnd)

            -- At zero: stop roll (enables selection in rolls) and refresh the UI
            addon.Rolls:RecordRolls(false)
            addon.Rolls:FetchRolls()
            module:RequestRefresh()
        end)
    end

    local function UpdateMasterButtonsIfChanged(state)
        local buttons = lastUIState.buttons
        local texts = lastUIState.texts

        local function UpdateEnabled(key, frame, enabled)
            if buttons[key] ~= enabled then
                Utils.enableDisable(frame, enabled)
                buttons[key] = enabled
            end
        end

        local function UpdateItemState(enabled)
            local itemBtn = _G[frameName .. "ItemBtn"]
            if itemBtn and buttons.itemBtn ~= enabled then
                Utils.enableDisable(itemBtn, enabled)
                local texture = itemBtn:GetNormalTexture()
                if texture and texture.SetDesaturated then
                    texture:SetDesaturated(not enabled)
                end
                buttons.itemBtn = enabled
            end
        end

        local function UpdateText(key, frame, text)
            if texts[key] ~= text then
                frame:SetText(text)
                texts[key] = text
            end
        end

        UpdateText("countdown", _G[frameName .. "CountdownBtn"], state.countdownText)
        UpdateText("award", _G[frameName .. "AwardBtn"], state.awardText)
        UpdateText("selectItem", _G[frameName .. "SelectItemBtn"], state.selectItemText)
        UpdateText("spamLoot", _G[frameName .. "SpamLootBtn"], state.spamLootText)

        UpdateEnabled("selectItem", _G[frameName .. "SelectItemBtn"], state.canSelectItem)
        UpdateEnabled("spamLoot", _G[frameName .. "SpamLootBtn"], state.canSpamLoot)
        UpdateEnabled("ms", _G[frameName .. "MSBtn"], state.canStartRolls)
        UpdateEnabled("os", _G[frameName .. "OSBtn"], state.canStartRolls)
        UpdateEnabled("sr", _G[frameName .. "SRBtn"], state.canStartSR)
        UpdateEnabled("free", _G[frameName .. "FreeBtn"], state.canStartRolls)
        UpdateEnabled("countdown", _G[frameName .. "CountdownBtn"], state.canCountdown)
        UpdateEnabled("hold", _G[frameName .. "HoldBtn"], state.canHold)
        UpdateEnabled("bank", _G[frameName .. "BankBtn"], state.canBank)
        UpdateEnabled("disenchant", _G[frameName .. "DisenchantBtn"], state.canDisenchant)
        UpdateEnabled("award", _G[frameName .. "AwardBtn"], state.canAward)
        UpdateText("reserveList", _G[frameName .. "ReserveListBtn"], state.reserveListText)
        UpdateEnabled("reserveList", _G[frameName .. "ReserveListBtn"], state.canReserveList)
        UpdateEnabled("roll", _G[frameName .. "RollBtn"], state.canRoll)
        UpdateEnabled("clear", _G[frameName .. "ClearBtn"], state.canClear)
        UpdateItemState(state.canChangeItem)
    end

    local function RefreshDropDowns(force)
        if not dropDownsInitialized then return end
        if not force and not dropDownDirty then return end
        UpdateDropDowns(dropDownFrameHolder)
        UpdateDropDowns(dropDownFrameBanker)
        UpdateDropDowns(dropDownFrameDisenchanter)
        dropDownDirty = false
        dirtyFlags.dropdowns = false
    end

    local function HookDropDownOpen(frame)
        if not frame then return end
        local button = _G[frame:GetName() .. "Button"]
        if button and not button._krtDropDownHook then
            button:HookScript("OnClick", function() RefreshDropDowns(true) end)
            button._krtDropDownHook = true
        end
    end

    local function BuildCandidateCache(itemLink)
        candidateCache.itemLink = itemLink
        twipe(candidateCache.indexByName)
        for p = 1, addon.GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                candidateCache.indexByName[candidate] = p
            end
        end
        addon:debug(Diag.D.LogMLCandidateCacheBuilt:format(tostring(itemLink),
            addon.tLength(candidateCache.indexByName)))
    end

    local function ResetTradeState()
        lootState.trader = nil
        lootState.winner = nil
        screenshotWarn = false
    end

    local function RegisterAwardedItem(count)
        local targetCount = tonumber(lootState.itemCount) or 1
        if targetCount < 1 then targetCount = 1 end
        local increment = tonumber(count) or 1
        if increment < 1 then increment = 1 end
        lootState.itemTraded = (lootState.itemTraded or 0) + increment
        if lootState.itemTraded >= targetCount then
            lootState.itemTraded = 0
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            return true
        end
        return false
    end

    -- ----- Public methods ----- --

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)
        -- Initialize ItemBtn scripts once (clean inventory drop support: click-to-drop).
        local itemBtn = _G[frameName .. "ItemBtn"]
        if itemBtn and not itemBtn.__krtMLInvDropInit then
            itemBtn.__krtMLInvDropInit = true
            itemBtn:RegisterForClicks("AnyUp")
            itemBtn:RegisterForDrag("LeftButton")

            -- Blizz-like gesture support:
            -- - Click while holding an item on the cursor
            -- - Drag&drop (release) an item onto the button
            local function TryAcceptFromCursor()
                if CursorHasItem and CursorHasItem() then
                    module:TryAcceptInventoryItemFromCursor()
                end
            end

            itemBtn:SetScript("OnClick", function(self, button)
                TryAcceptFromCursor()
            end)

            itemBtn:SetScript("OnReceiveDrag", function(self)
                TryAcceptFromCursor()
            end)
        end
        frame:SetScript("OnHide", function()
            if selectionFrame then selectionFrame:Hide() end
        end)
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    -- Button: Select/Remove Item
    function module:BtnSelectItem(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if countdownRun then return end
        lootState.multiAward = nil
        if lootState.fromInventory == true then
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            announced = false
            lootState.fromInventory = false
            itemInfo.count = 0
            itemInfo.isStack = nil
            itemInfo.bagID = nil
            itemInfo.slotID = nil
            if lootState.opened == true then addon.Loot:FetchLoot() end
        elseif selectionFrame then
            Utils.toggle(selectionFrame)
        end
        module:RequestRefresh()
    end

    -- Button: Spam Loot Links or Do Ready Check
    function module:BtnSpamLoot(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if lootState.fromInventory == true then
            addon:Announce(L.ChatReadyCheck)
            DoReadyCheck()
        else
            addon:Announce(L.ChatSpamLoot, "RAID")
            for i = 1, lootState.lootCount do
                local itemLink = GetItemLink(i)
                if itemLink then
                    local item = GetItem(i)
                    local count = item and item.count or 1
                    local suffix = (count and count > 1) and (" x" .. count) or ""
                    addon:Announce(i .. ". " .. itemLink .. suffix, "RAID")
                end
            end
        end
    end

    -- Button: Reserve List (contextual)
    function module:BtnReserveList(btn)
        if addon.Reserves:HasData() then
            addon.Reserves:Toggle()
        else
            addon.ReserveImport:Toggle()
        end
    end

    -- Button: Loot Counter
    function module:BtnLootCounter(btn)
        if addon.LootCounter and addon.LootCounter.Toggle then addon.LootCounter:Toggle() end
    end

    -- Generic function to announce a roll for the current item.
    local function AnnounceRoll(rollType, chatMsg)
        if lootState.lootCount >= 1 then
            announced = false
            lootState.currentRollType = rollType
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(true)
            lootState.rollStarted = true
            lootState.itemTraded = 0

            local itemLink = GetItemLink()
            local itemID = Utils.getItemIdFromLink(itemLink)
            local message = ""

            if rollType == rollTypes.RESERVED then
                -- Chat-safe: keep UI colors in the Reserve Frame, but do not send class color codes in chat.
                local srList = addon.Reserves:FormatReservedPlayersLine(itemID, false, false, false)
                local suff = addon.options.sortAscending and "Low" or "High"
                message = lootState.itemCount > 1
                    and L[chatMsg .. "Multiple" .. suff]:format(srList, itemLink, lootState.itemCount)
                    or L[chatMsg]:format(srList, itemLink)
            else
                local suff = addon.options.sortAscending and "Low" or "High"
                message = lootState.itemCount > 1
                    and L[chatMsg .. "Multiple" .. suff]:format(itemLink, lootState.itemCount)
                    or L[chatMsg]:format(itemLink)
            end

            addon:Announce(message)
            _G[frameName .. "ItemCount"]:ClearFocus()
            lootState.currentRollItem = addon.Raid:GetLootID(itemID)
            module:RequestRefresh()
        end
    end

    local function AssignToTarget(rollType, targetKey)
        if lootState.lootCount <= 0 or not lootState[targetKey] then return end
        countdownRun = false
        local itemLink = GetItemLink()
        if not itemLink then return end
        lootState.currentRollType = rollType
        local target = lootState[targetKey]
        local ok
        if lootState.fromInventory then
            ok = TradeItem(itemLink, target, rollType, 0)
        else
            ok = AssignItem(itemLink, target, rollType, 0)
        end
        if ok and not lootState.fromInventory then
            announced = false
            addon.Rolls:ClearRolls()
        end
        module:RequestRefresh()
        return ok
    end

    function module:BtnMS(btn)
        return AnnounceRoll(1, "ChatRollMS")
    end

    function module:BtnOS(btn)
        return AnnounceRoll(2, "ChatRollOS")
    end

    function module:BtnSR(btn)
        return AnnounceRoll(3, "ChatRollSR")
    end

    function module:BtnFree(btn)
        return AnnounceRoll(4, "ChatRollFree")
    end

    -- Button: Starts or stops the roll countdown.
    function module:BtnCountdown(btn)
        if countdownRun then
            addon.Rolls:RecordRolls(false)
            StopCountdown()
            addon.Rolls:FetchRolls()
            module:RequestRefresh()
        elseif not lootState.rollStarted then
            return
        else
            addon.Rolls:RecordRolls(true)
            announced = false
            StartCountdown()
            module:RequestRefresh()
        end
    end

    -- Button: Clear Rolls
    function module:BtnClear(btn)
        announced = false
        addon.Rolls:ClearRolls()
        module:RequestRefresh()
    end

    -- Button: Award/Trade
    function module:BtnAward(btn)
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
        if not lootState.winner then
            addon:warn(L.ErrNoWinnerSelected)
            return
        end
        countdownRun = false
        local itemLink = GetItemLink()
        addon:debug(Diag.D.LogMLAwardRequested:format(tostring(lootState.winner),
            tonumber(lootState.currentRollType) or -1, addon.Rolls:HighestRoll() or 0, tostring(itemLink)))
        local result
        if lootState.fromInventory == true then
            result = TradeItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
            module:ResetItemCount()
            module:RequestRefresh()
            return result
        end

        -- Loot window: support multi-award when ItemCount > 1 by consuming multiple identical copies
        -- (same itemString) sequentially on LOOT_SLOT_CLEARED.
        local target = tonumber(lootState.itemCount) or 1
        if target < 1 then target = 1 end
        local available = tonumber(addon.Loot:GetCurrentItemCount()) or 1
        if available < 1 then available = 1 end
        if target > available then target = available end
        if lootState.rollsCount and target > lootState.rollsCount then
            target = lootState.rollsCount
        end
        if available and available > 1 then
            local winners = {}

            -- Winners are taken from the current MultiSelect (CTRL+Click in roll list).
            -- In multi-copy mode, at least 1 winner must be selected; the addon awards exactly the selected count
            -- (clamped to the available copies).
            local selCount = Utils.multiSelectCount("MLRollWinners") or 0
            if selCount <= 0 then
                addon:warn(L.ErrNoWinnerSelected)
                module:ResetItemCount()
                return false
            end

            local awardCount = selCount
            if awardCount > target then awardCount = target end

            local picked = addon.Rolls.GetSelectedWinnersOrdered and addon.Rolls:GetSelectedWinnersOrdered() or {}
            if (not picked) or (#picked < awardCount) then
                addon:warn(Diag.W.ErrMLMultiSelectNotEnough:format(awardCount, picked and #picked or 0))
                module:ResetItemCount()
                return false
            end
            for i = 1, awardCount do
                local p = picked[i]
                if p and p.name then
                    winners[#winners + 1] = { name = p.name, roll = tonumber(p.roll) or 0 }
                end
            end

            -- Clear manual selection after capturing winners (prevents stale selection on next item).
            Utils.multiSelectClear("MLRollWinners")
            Utils.multiSelectSetAnchor("MLRollWinners", nil)
            if #winners <= 0 then
                addon:warn(L.ErrNoWinnerSelected)
                module:ResetItemCount()
                return false
            end

            -- Stabilize target count for the whole sequence and reflect the clamp in the UI.
            SetItemCountValue(#winners, false)

            lootState.multiAward = {
                active    = true,
                itemLink  = itemLink,
                itemKey   = Utils.getItemStringFromLink(itemLink) or itemLink,
                lastCount = available,
                rollType  = lootState.currentRollType,
                winners   = winners,
                pos       = 2, -- first award is immediate; the rest continues on LOOT_SLOT_CLEARED
                total     = #winners,
            }

            lootState.multiAward.announceOnWin = addon.options.announceOnWin and true or false
            lootState.multiAward.congratsSent = false

            -- Suppress per-copy ChatAward spam during multi-award; announce once on completion.
            announced = true
            -- First award immediately.
            lootState.winner = winners[1].name
            result = AssignItem(itemLink, winners[1].name, lootState.currentRollType, winners[1].roll)
            if result then
                RegisterAwardedItem(1)
                -- If this was the last copy for any reason, close the sequence now.
                if lootState.multiAward and lootState.multiAward.pos > lootState.multiAward.total then
                    local ma = lootState.multiAward
                    if ma and ma.announceOnWin and not ma.congratsSent then
                        local names = {}
                        for i = 1, (ma.total or (ma.winners and #ma.winners) or 0) do
                            local w = ma.winners and ma.winners[i]
                            if w and w.name then names[#names + 1] = w.name end
                        end
                        if #names > 0 then
                            if #names == 1 then
                                addon:Announce(L.ChatAward:format(names[1], ma.itemLink))
                            else
                                addon:Announce(L.ChatAwardMutiple:format(table.concat(names, ", "), ma.itemLink))
                            end
                        end
                        ma.congratsSent = true
                    end
                    lootState.multiAward = nil
                    announced = false
                    module:ResetItemCount()
                end
                module:RequestRefresh()
                return true
            end

            lootState.multiAward = nil
            announced = false
            module:ResetItemCount()
            module:RequestRefresh()
            return false
        end

        -- Single award (existing behavior): uses the currently selected winner.
        result = AssignItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
        if result then
            RegisterAwardedItem(1)
        end
        module:ResetItemCount()
        module:RequestRefresh()
        return result
    end

    -- Button: Hold item
    function module:BtnHold(btn)
        return AssignToTarget(rollTypes.HOLD, "holder")
    end

    -- Button: Bank item
    function module:BtnBank(btn)
        return AssignToTarget(rollTypes.BANK, "banker")
    end

    -- Button: Disenchant item
    function module:BtnDisenchant(btn)
        return AssignToTarget(rollTypes.DISENCHANT, "disenchanter")
    end

    -- Selects an item from the item selection frame.
    function module:BtnSelectedItem(btn)
        if not btn then return end
        local index = btn:GetID()
        if index ~= nil then
            announced = false
            selectionFrame:Hide()
            addon.Loot:SelectItem(index)
            module:ResetItemCount()
            module:RequestRefresh()
        end
    end

    -- Localizes UI frame elements.
    function LocalizeUIFrame()
        if localized then return end
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
        --_G[frameName .. "RollsHeaderCounter"]:SetText(L.StrCounter) -- (future use)
        _G[frameName .. "RollsHeaderRoll"]:SetText(L.StrRoll)
        _G[frameName .. "ReserveListBtn"]:SetText(L.BtnInsertList)
        _G[frameName .. "LootCounterBtn"]:SetText(L.BtnLootCounter)
        Utils.setFrameTitle(frameName, MASTER_LOOTER)

        local itemCountBox = _G[frameName .. "ItemCount"]
        if itemCountBox and not itemCountBox.__krtMLHooked then
            itemCountBox.__krtMLHooked = true
            itemCountBox:SetScript("OnTextChanged", function(self, isUserInput)
                if not isUserInput then return end
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
            for i = 1, 8 do dropDownData[i] = {} end
        end
        dropDownFrameHolder       = _G[frameName .. "HoldDropDown"]
        dropDownFrameBanker       = _G[frameName .. "BankDropDown"]
        dropDownFrameDisenchanter = _G[frameName .. "DisenchantDropDown"]
        PrepareDropDowns()
        UIDropDownMenu_Initialize(dropDownFrameHolder, InitializeDropDowns)
        UIDropDownMenu_Initialize(dropDownFrameBanker, InitializeDropDowns)
        UIDropDownMenu_Initialize(dropDownFrameDisenchanter, InitializeDropDowns)
        dropDownsInitialized = true
        HookDropDownOpen(dropDownFrameHolder)
        HookDropDownOpen(dropDownFrameBanker)
        HookDropDownOpen(dropDownFrameDisenchanter)
        RefreshDropDowns(true)
        localized = true
    end

    local function UpdateItemCountFromBox(itemCountBox)
        -- While a multi-award sequence is running from the loot window, ItemCount represents
        -- the target number of copies to distribute (not the remaining copies). Ignore edits.
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return
        end
        if not itemCountBox or not itemCountBox:IsVisible() then return end
        local rawCount = itemCountBox:GetText()
        if rawCount ~= lastUIState.itemCountText then
            lastUIState.itemCountText = rawCount
            dirtyFlags.itemCount = true
        end
        if dirtyFlags.itemCount then
            local count = tonumber(rawCount)
            if count and count > 0 then
                lootState.itemCount = count
                if lootState.fromInventory and itemInfo.count and itemInfo.count ~= lootState.itemCount then
                    if itemInfo.count < lootState.itemCount then
                        lootState.itemCount = itemInfo.count
                        itemCountBox:SetNumber(itemInfo.count)
                        lastUIState.itemCountText = tostring(itemInfo.count)
                    end
                end
            end
            dirtyFlags.itemCount = false
        end
    end

    local function UpdateRollStatusState()
        local rollType, record, canRoll, rolled = addon.Rolls:RollStatus()
        local rollStatus = lastUIState.rollStatus
        if rollStatus.record ~= record
            or rollStatus.canRoll ~= canRoll
            or rollStatus.rolled ~= rolled
            or rollStatus.rollType ~= rollType then
            rollStatus.record = record
            rollStatus.canRoll = canRoll
            rollStatus.rolled = rolled
            rollStatus.rollType = rollType
            dirtyFlags.rolls = true
            dirtyFlags.buttons = true
        end
        return record, canRoll, rolled
    end

    local function FlagButtonsOnChange(key, value)
        if lastUIState[key] ~= value then
            lastUIState[key] = value
            dirtyFlags.buttons = true
        end
    end
    -- Refreshes the UI once (event-driven; coalesced via module:RequestRefresh()).
    function UpdateUIFrame()
        LocalizeUIFrame()

        local itemCountBox = _G[frameName .. "ItemCount"]
        UpdateItemCountFromBox(itemCountBox)

        if dropDownDirty then
            dirtyFlags.dropdowns = true
        end

        local record, canRoll, rolled = UpdateRollStatusState()
        if lastUIState.rollsCount ~= lootState.rollsCount then
            lastUIState.rollsCount = lootState.rollsCount
            dirtyFlags.rolls = true
            dirtyFlags.buttons = true
        end

        if lastUIState.winner ~= lootState.winner then
            lastUIState.winner = lootState.winner
            dirtyFlags.winner = true
            dirtyFlags.buttons = true
        end

        FlagButtonsOnChange("lootCount", lootState.lootCount)
        FlagButtonsOnChange("fromInventory", lootState.fromInventory)
        FlagButtonsOnChange("holder", lootState.holder)
        FlagButtonsOnChange("banker", lootState.banker)
        FlagButtonsOnChange("disenchanter", lootState.disenchanter)

        local hasReserves = addon.Reserves:HasData()
        FlagButtonsOnChange("hasReserves", hasReserves)

        local hasItem = ItemExists()
        FlagButtonsOnChange("hasItem", hasItem)

        local itemId
        if hasItem then
            itemId = Utils.getItemIdFromLink(GetItemLink())
        end
        local hasItemReserves = itemId and addon.Reserves:HasItemReserves(itemId) or false
        FlagButtonsOnChange("hasItemReserves", hasItemReserves)
        FlagButtonsOnChange("countdownRun", countdownRun)

        local available = tonumber(addon.Loot:GetCurrentItemCount()) or 1
        if available < 1 then available = 1 end
        local pickMode = (not lootState.fromInventory)
        local msCount = pickMode and (Utils.multiSelectCount("MLRollWinners") or 0) or 0
        FlagButtonsOnChange("msCount", msCount)

        if dirtyFlags.buttons then
            UpdateMasterButtonsIfChanged({
                countdownText = countdownRun and L.BtnStop or L.BtnCountdown,
                awardText = lootState.fromInventory and TRADE or L.BtnAward,
                selectItemText = lootState.fromInventory and L.BtnRemoveItem or L.BtnSelectItem,
                spamLootText = lootState.fromInventory and READY_CHECK or L.BtnSpamLoot,
                canSelectItem = (lootState.lootCount > 1
                    or (lootState.fromInventory and lootState.lootCount >= 1)) and not countdownRun,
                canChangeItem = not countdownRun,
                canSpamLoot = lootState.lootCount >= 1,
                canStartRolls = lootState.lootCount >= 1,
                canStartSR = lootState.lootCount >= 1 and hasItemReserves,
                canCountdown = lootState.lootCount >= 1 and hasItem
                    and (lootState.rollStarted or countdownRun),
                canHold = lootState.lootCount >= 1 and lootState.holder,
                canBank = lootState.lootCount >= 1 and lootState.banker,
                canDisenchant = lootState.lootCount >= 1 and lootState.disenchanter,
                canAward = lootState.lootCount >= 1 and lootState.rollsCount >= 1 and not countdownRun and
                    (not pickMode or msCount > 0),
                reserveListText = hasReserves and L.BtnOpenList or L.BtnInsertList,
                canReserveList = true,
                canRoll = record and canRoll and rolled == false and countdownRun,
                canClear = lootState.rollsCount >= 1,
            })
            dirtyFlags.buttons = false
        end

        dirtyFlags.rolls = false
        dirtyFlags.winner = false
    end

    -- Initializes the dropdown menus for player selection.
    function InitializeDropDowns()
        if UIDROPDOWNMENU_MENU_LEVEL == 2 then
            local g = UIDROPDOWNMENU_MENU_VALUE
            local m = dropDownData[g]
            for key, value in pairs(m) do
                local info        = UIDropDownMenu_CreateInfo()
                info.hasArrow     = false
                info.notCheckable = 1
                info.text         = key
                info.func         = module.OnClickDropDown
                info.arg1         = UIDROPDOWNMENU_OPEN_MENU
                info.arg2         = key
                UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end
        if UIDROPDOWNMENU_MENU_LEVEL == 1 then
            for key, value in pairs(dropDownData) do
                if dropDownGroupData[key] == true then
                    local info        = UIDropDownMenu_CreateInfo()
                    info.hasArrow     = 1
                    info.notCheckable = 1
                    info.text         = GROUP .. " " .. key
                    info.value        = key
                    info.owner        = UIDROPDOWNMENU_OPEN_MENU
                    UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
                end
            end
        end
    end

    -- Prepares the data for the dropdowns by fetching the raid roster.
    function PrepareDropDowns()
        local rosterVersion = addon.Raid.GetRosterVersion and addon.Raid:GetRosterVersion() or nil
        if rosterVersion and cachedRosterVersion == rosterVersion then
            return
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

        for unit, owner in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" then
                local subgroup = 1

                -- Se siamo in raid, ricava il subgroup reale
                local idx = tonumber(unit:match("^raid(%d+)$"))
                if idx then
                    subgroup = (select(3, GetRaidRosterInfo(idx))) or 1
                end

                dropDownData[subgroup] = dropDownData[subgroup] or {}
                dropDownData[subgroup][name] = name
                dropDownGroupData[subgroup] = true
            end
        end

        RefreshDropDowns(true)
    end

    module.PrepareDropDowns = PrepareDropDowns

    -- Dropdown field metadata: maps frame name suffixes to state keys (lazily bound at runtime).
    local function FindDropDownField(frameNameFull)
        if not frameNameFull then return nil end

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
        if not KRT_CurrentRaid then return end
        UIDropDownMenu_SetText(owner, value)
        UIDropDownMenu_SetSelectedValue(owner, value)

        local field = FindDropDownField(owner:GetName())
        if field then
            KRT_Raids[KRT_CurrentRaid][field.raidKey] = value
            lootState[field.stateKey] = value
        end

        dropDownDirty = true
        dirtyFlags.dropdowns = true
        dirtyFlags.buttons = true
        CloseDropDownMenus()
        module:RequestRefresh()
    end

    -- Updates the text of the dropdowns to reflect the current selection (consolidated from 3 similar branches).
    function UpdateDropDowns(frame)
        if not frame or not KRT_CurrentRaid then return end

        local field = FindDropDownField(frame:GetName())
        if not field then return end

        -- Sync state from raid data
        lootState[field.stateKey] = KRT_Raids[KRT_CurrentRaid][field.raidKey]

        -- Clear if unit is no longer in raid
        if lootState[field.stateKey] and addon.Raid:GetUnitID(lootState[field.stateKey]) == "none" then
            KRT_Raids[KRT_CurrentRaid][field.raidKey] = nil
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
    local function CreateSelectionFrame()
        if selectionFrame == nil then
            local frame = getFrame()
            if not frame then return end
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
    function UpdateSelectionFrame()
        CreateSelectionFrame()
        local height = 5
        for i = 1, lootState.lootCount do
            local btnName = frameName .. "ItemSelectionBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
            btn:SetID(i)
            btn:Show()
            local itemName = GetItemName(i)
            local itemNameBtn = _G[btnName .. "Name"]
            local item = GetItem(i)
            local count = item and item.count or 1
            if count and count > 1 then
                itemNameBtn:SetText(itemName .. " x" .. count)
            else
                itemNameBtn:SetText(itemName)
            end
            local itemTexture = GetItemTexture(i)
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

    local function ScanTradeableInventory(itemLink, itemId)
        if not itemLink and not itemId then return nil end
        local wantedKey = itemLink and (Utils.getItemStringFromLink(itemLink) or itemLink) or nil
        local wantedId = tonumber(itemId) or (itemLink and Utils.getItemIdFromLink(itemLink)) or nil
        local totalCount = 0
        local firstBag, firstSlot, firstSlotCount
        local hasMatch = false
        -- Backpack (0) + 4 bag slots (1..4) in WoW 3.3.5a.
        for bag = 0, 4 do
            local n = GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local key = Utils.getItemStringFromLink(link) or link
                    local linkId = Utils.getItemIdFromLink(link)
                    local matches = (wantedKey and key == wantedKey) or (wantedId and linkId == wantedId)
                    if matches then
                        hasMatch = true
                        if not ItemIsSoulbound(bag, slot) then
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

    local function ApplyInventoryItem(itemLink, totalCount, inBag, inSlot, slotCount)
        if countdownRun then return false end
        if not itemLink then return false end
        local itemCount = tonumber(totalCount) or 1
        if itemCount < 1 then itemCount = 1 end

        -- Clear count:
        Utils.resetEditBox(_G[frameName .. "ItemCount"], true)

        lootState.fromInventory = true
        addon.Loot:AddItem(itemLink, itemCount)
        addon.Loot:PrepareItem()
        announced = false

        itemInfo.bagID = inBag
        itemInfo.slotID = inSlot
        itemInfo.count = itemCount
        itemInfo.isStack = (tonumber(slotCount) or 1) > 1

        module:ResetItemCount(true)
        ClearCursor()
        module:RequestRefresh()
        return true
    end

    -- Accept an item currently held on the cursor (bag click-pickup).
    -- This is triggered by ItemBtn's OnClick.
    function module:TryAcceptInventoryItemFromCursor()
        if countdownRun then return false end
        if not CursorHasItem or not CursorHasItem() then return false end

        local infoType, itemId, itemLink = GetCursorInfo()
        if infoType ~= "item" then return false end

        local totalCount, bag, slot, slotCount, hasMatch = ScanTradeableInventory(itemLink, itemId)
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

        return ApplyInventoryItem(itemLink, totalCount, bag, slot, slotCount)
    end

    -- LOOT_OPENED: Triggered when the loot window opens.
    function module:LOOT_OPENED()
        if addon.Raid:IsMasterLooter() then
            lootState.opened = true
            announced = false
            addon.Loot:FetchLoot()
            addon:trace(Diag.D.LogMLLootOpenedTrace:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory)))
            UpdateSelectionFrame()
            if not addon.Logger.container then
                addon.Logger.source = UnitName("target")
            end
            addon:debug(Diag.D.LogMLLootOpenedInfo:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory), tostring(UnitName("target"))))

            local shouldShow = (lootState.lootCount or 0) >= 1
            local frame = getFrame()
            if shouldShow and frame then
                -- Request while hidden to refresh immediately on OnShow (avoid an extra refresh).
                module:RequestRefresh()
                frame:Show()
            else
                -- Keep state dirty for the next time the frame is shown.
                module:RequestRefresh()
            end
        end
    end

    -- LOOT_CLOSED: Triggered when the loot window closes.
    function module:LOOT_CLOSED()
        if addon.Raid:IsMasterLooter() then
            addon:trace(Diag.D.LogMLLootClosed:format(tostring(lootState.opened), lootState.lootCount or 0))
            addon:trace(Diag.D.LogMLLootClosedCleanup)
            lootState.multiAward = nil
            announced = false
            -- Cancel any scheduled close timer and schedule a new one
            if lootState.closeTimer then
                addon.CancelTimer(lootState.closeTimer)
                lootState.closeTimer = nil
            end
            lootState.closeTimer = addon.NewTimer(0.1, function()
                lootState.closeTimer = nil
                lootState.opened = false
                lootState.pendingAwards = {}
                local frame = getFrame()
                if frame then frame:Hide() end
                addon.Loot:ClearLoot()
                addon.Rolls:ClearRolls()
                addon.Rolls:RecordRolls(false)
                module:RequestRefresh()
            end)
        end
    end

    -- LOOT_SLOT_CLEARED: Triggered when an item is looted.
    function module:LOOT_SLOT_CLEARED()
        if addon.Raid:IsMasterLooter() then
            addon.Loot:FetchLoot()
            addon:trace(Diag.D.LogMLLootSlotCleared:format(lootState.lootCount or 0))
            UpdateSelectionFrame()
            module:ResetItemCount()

            local frame = getFrame()
            local shouldShow = (lootState.lootCount or 0) >= 1
            if shouldShow then
                local wasShown = frame and frame:IsShown()
                if not wasShown then
                    -- Request while hidden to refresh immediately on OnShow (avoid an extra refresh).
                    module:RequestRefresh()
                    if frame then frame:Show() end
                else
                    module:RequestRefresh()
                end
            else
                if frame then frame:Hide() end
                addon:debug(Diag.D.LogMLLootWindowEmptied)
            end

            -- Continue a multi-award sequence (loot window only). We award one copy per LOOT_SLOT_CLEARED
            -- with a small delay to stay in sync with server/loot window refresh (and avoid lag spikes).
            local ma = lootState.multiAward
            if ma and ma.active and not lootState.fromInventory then
                -- Prevent double-scheduling if the loot window fires multiple clear events quickly.
                if ma.scheduled then
                    return
                end
                -- Gate: proceed only when the number of copies for this itemKey has decreased since last award.
                local currentCount = 0
                for i = 1, (lootState.lootCount or 0) do
                    local it = GetItem and GetItem(i)
                    if it and it.itemKey == ma.itemKey then
                        currentCount = tonumber(it.count) or 1
                        break
                    end
                end
                if ma.lastCount and currentCount >= ma.lastCount then
                    return
                end
                ma.lastCount = currentCount
                local idx = tonumber(ma.pos) or 1
                local entry = ma.winners and ma.winners[idx]
                if not entry then
                    lootState.multiAward = nil
                    announced = false
                    module:ResetItemCount()
                    module:RequestRefresh()
                    return
                end

                ma.scheduled = true
                local delay = tonumber(C.ML_MULTI_AWARD_DELAY) or 0
                if delay < 0 then delay = 0 end

                addon.After(delay, function()
                    local ma2 = lootState.multiAward
                    if not (ma2 and ma2.active and ma2.scheduled and not lootState.fromInventory) then
                        return
                    end
                    ma2.scheduled = false

                    local idx2 = tonumber(ma2.pos) or 1
                    local e2 = ma2.winners and ma2.winners[idx2]
                    if not e2 then
                        lootState.multiAward = nil
                        announced = false
                        module:ResetItemCount()
                        module:RequestRefresh()
                        return
                    end

                    -- Suppress per-copy ChatAward spam during multi-award; announce once on completion.
                    announced = true
                    lootState.winner = e2.name
                    lootState.currentRollType = ma2.rollType
                    module:RequestRefresh()

                    local ok = AssignItem(ma2.itemLink, e2.name, ma2.rollType, e2.roll)
                    if ok then
                        RegisterAwardedItem(1)
                        ma2.pos = idx2 + 1
                        if ma2.pos > (ma2.total or #ma2.winners) then
                            local ma = lootState.multiAward
                            if ma and ma.announceOnWin and not ma.congratsSent then
                                local names = {}
                                for i = 1, (ma.total or (ma.winners and #ma.winners) or 0) do
                                    local w = ma.winners and ma.winners[i]
                                    if w and w.name then names[#names + 1] = w.name end
                                end
                                if #names > 0 then
                                    if #names == 1 then
                                        addon:Announce(L.ChatAward:format(names[1], ma.itemLink))
                                    else
                                        addon:Announce(L.ChatAwardMutiple:format(table.concat(names, ", "), ma.itemLink))
                                    end
                                end
                                ma.congratsSent = true
                            end
                            lootState.multiAward = nil
                            announced = false
                            module:ResetItemCount()
                            module:RequestRefresh()
                        end
                    else
                        lootState.multiAward = nil
                        announced = false
                        module:ResetItemCount()
                        module:RequestRefresh()
                    end
                end)
            end
        end
    end

    function module:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
        addon:trace(Diag.D.LogTradeAcceptUpdate:format(tostring(lootState.trader), tostring(lootState.winner),
            tostring(tAccepted), tostring(pAccepted)))
        if lootState.trader and lootState.winner and lootState.trader ~= lootState.winner then
            if tAccepted == 1 and pAccepted == 1 then
                addon:debug(Diag.D.LogTradeCompleted:format(tostring(lootState.currentRollItem),
                    tostring(lootState.winner), tonumber(lootState.currentRollType) or -1,
                    addon.Rolls:HighestRoll()))
                if lootState.currentRollItem and lootState.currentRollItem > 0 then
                    local ok = addon.Logger.Loot:Log(lootState.currentRollItem, lootState.winner,
                        lootState.currentRollType, addon.Rolls:HighestRoll(), "TRADE_ACCEPT", KRT_CurrentRaid)

                    if not ok then
                        addon:error(Diag.E.LogTradeLoggerLogFailed:format(tostring(KRT_CurrentRaid),
                            tostring(lootState.currentRollItem), tostring(GetItemLink())))
                    end
                else
                    addon:warn(Diag.W.LogTradeCurrentRollItemMissing)
                end

                -- LootCounter (MS only): trade awards don't emit LOOT_ITEM for the winner.
                if tonumber(lootState.currentRollType) == rollTypes.MAINSPEC then
                    addon.Raid:AddPlayerCount(lootState.winner, 1, KRT_CurrentRaid)
                end

                local done = RegisterAwardedItem()
                ResetTradeState()
                if done then
                    addon.Loot:ClearLoot()
                    addon.Raid:ClearRaidIcons()
                end
                screenshotWarn = false
                module:RequestRefresh()
            end
        end
    end

    -- TRADE_CLOSED: trade window closed (completed or canceled)
    function module:TRADE_CLOSED()
        ResetTradeState("TRADE_CLOSED")
        module:RequestRefresh()
    end

    -- TRADE_REQUEST_CANCEL: trade request canceled before opening
    function module:TRADE_REQUEST_CANCEL()
        ResetTradeState("TRADE_REQUEST_CANCEL")
        module:RequestRefresh()
    end

    -- Assigns an item from the loot window to a player.
    function AssignItem(itemLink, playerName, rollType, rollValue)
        local itemIndex, tempItemLink
        local wantedKey = Utils.getItemStringFromLink(itemLink) or itemLink
        for i = 1, GetNumLootItems() do
            tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                itemIndex = i
                break
            end
            if wantedKey and tempItemLink then
                local tempKey = Utils.getItemStringFromLink(tempItemLink) or tempItemLink
                if tempKey == wantedKey then
                    itemIndex = i
                    break
                end
            end
        end
        if itemIndex == nil then
            addon:error(L.ErrCannotFindItem:format(itemLink))
            return false
        end

        if candidateCache.itemLink ~= itemLink then
            BuildCandidateCache(itemLink)
        end
        local candidateIndex = candidateCache.indexByName[playerName]
        if not candidateIndex then
            addon:debug(Diag.D.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            BuildCandidateCache(itemLink)
            candidateIndex = candidateCache.indexByName[playerName]
        end
        if candidateIndex then
            -- Mark this award as addon-driven so AddLoot() won't classify it as MANUAL
            addon.Loot:QueuePendingAward(itemLink, playerName, rollType, rollValue)
            GiveMasterLoot(itemIndex, candidateIndex)
            addon:debug(Diag.D.LogMLAwarded:format(tostring(itemLink), tostring(playerName),
                tonumber(rollType) or -1, tonumber(rollValue) or 0, tonumber(itemIndex) or -1,
                tonumber(candidateIndex) or -1))
            local output, whisper
            if rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE
                and addon.options.announceOnWin then
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

            if output and not announced then
                addon:Announce(output)
                announced = true
            end
            if whisper then
                Utils.whisper(playerName, whisper)
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
        addon:error(L.ErrCannotFindPlayer:format(playerName))
        return false
    end

    -- Trades an item from inventory to a player.
    function TradeItem(itemLink, playerName, rollType, rollValue)
        if itemLink ~= GetItemLink() then return end
        local isAwardRoll = (rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE)

        ResetTradeState("TRADE_START")

        lootState.trader = Utils.getPlayerName()
        lootState.winner = isAwardRoll and playerName or nil

        addon:debug(Diag.D.LogTradeStart:format(tostring(itemLink), tostring(lootState.trader),
            tostring(playerName), tonumber(rollType) or -1, tonumber(rollValue) or 0,
            lootState.itemCount or 1))

        -- Prepare initial output and whisper:
        local output, whisper
        local keep = not isAwardRoll

        if isAwardRoll and addon.options.announceOnWin then
            output = L.ChatAward:format(playerName, itemLink)
        elseif rollType == rollTypes.HOLD and addon.options.announceOnHold then
            output = L.ChatNoneRolledHold:format(itemLink, playerName)
        elseif rollType == rollTypes.BANK and addon.options.announceOnBank then
            output = L.ChatNoneRolledBank:format(itemLink, playerName)
        elseif rollType == rollTypes.DISENCHANT and addon.options.announceOnDisenchant then
            output = L.ChatNoneRolledDisenchant:format(itemLink, playerName)
        end

        -- Keeping the item:
        if keep then
            if rollType == rollTypes.HOLD then
                whisper = L.WhisperHoldTrade:format(itemLink)
            elseif rollType == rollTypes.BANK then
                whisper = L.WhisperBankTrade:format(itemLink)
            elseif rollType == rollTypes.DISENCHANT then
                whisper = L.WhisperDisenchantTrade:format(itemLink)
            end
            -- Multiple winners:
        elseif lootState.itemCount > 1 then
            -- Announce multiple winners
            addon.Raid:ClearRaidIcons()
            if lootState.trader ~= lootState.winner then
                SetRaidTarget(lootState.trader, 1)
            end
            local rolls = addon.Rolls:GetRolls()
            local winners = {}
            for i = 1, lootState.itemCount do
                if rolls[i] then
                    if rolls[i].name == lootState.trader then
                        if lootState.trader ~= lootState.winner then
                            tinsert(winners, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
                        else
                            tinsert(winners, rolls[i].name .. "(" .. rolls[i].roll .. ")")
                        end
                    else
                        SetRaidTarget(rolls[i].name, i + 1)
                        tinsert(winners, RAID_TARGET_MARKERS[i] .. " " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
                    end
                end
            end
            output = L.ChatTradeMutiple:format(tconcat(winners, ", "), lootState.trader)
            -- Trader is the winner:
        elseif lootState.trader == lootState.winner then
            -- Trader won, clear state
            addon:debug(Diag.D.LogTradeTraderKeeps:format(tostring(itemLink), tostring(playerName)))

            -- LootCounter (MS only): award is immediate (no trade window completion event).
            if tonumber(rollType) == rollTypes.MAINSPEC then
                addon.Raid:AddPlayerCount(playerName, 1, KRT_CurrentRaid)
            end

            local done = RegisterAwardedItem(lootState.itemCount)
            if done then
                addon.Loot:ClearLoot()
                addon.Raid:ClearRaidIcons()
            end
        else
            local unit = addon.Raid:GetUnitID(playerName)
            if unit ~= "none" and CheckInteractDistance(unit, 2) == 1 then
                -- Player is in range for trade
                local totalCount, bag, slot, slotCount
                local usedFastPath = false
                local wantedKey = Utils.getItemStringFromLink(itemLink) or itemLink
                local wantedId = Utils.getItemIdFromLink(itemLink)

                -- Fast-path: reuse the previously selected bag slot when still valid.
                local cachedBag = tonumber(itemInfo.bagID)
                local cachedSlot = tonumber(itemInfo.slotID)
                if cachedBag and cachedSlot then
                    local cachedLink = GetContainerItemLink(cachedBag, cachedSlot)
                    if cachedLink then
                        local cachedKey = Utils.getItemStringFromLink(cachedLink) or cachedLink
                        local cachedId = Utils.getItemIdFromLink(cachedLink)
                        local sameItem = (wantedKey and cachedKey == wantedKey)
                            or (wantedId and cachedId == wantedId)
                        if sameItem and not ItemIsSoulbound(cachedBag, cachedSlot) then
                            local _, count = GetContainerItemInfo(cachedBag, cachedSlot)
                            bag = cachedBag
                            slot = cachedSlot
                            slotCount = tonumber(count) or 1
                            usedFastPath = true
                        end
                    end
                end

                if not (bag and slot) then
                    totalCount, bag, slot, slotCount = ScanTradeableInventory(itemLink, wantedId)
                elseif usedFastPath then
                    if (tonumber(lootState.itemCount) or 1) > 1 then
                        totalCount = ScanTradeableInventory(itemLink, wantedId)
                    else
                        totalCount = tonumber(slotCount) or 1
                    end
                end
                if bag and slot then
                    itemInfo.bagID = bag
                    itemInfo.slotID = slot
                    itemInfo.isStack = (tonumber(slotCount) or 1) > 1
                    itemInfo.count = tonumber(totalCount) or tonumber(slotCount) or 1
                else
                    addon:warn(L.ErrMLInventoryItemMissing:format(tostring(itemLink)))
                    return false
                end
                if itemInfo.isStack and not addon.options.ignoreStacks then
                    addon:debug(Diag.D.LogTradeStackBlocked:format(tostring(addon.options.ignoreStacks),
                        tostring(itemLink)))
                    addon:warn(L.ErrItemStack:format(itemLink))
                    return false
                end
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
                -- Cannot trade the player?
            elseif unit ~= "none" then
                -- Player is out of range
                addon:warn(Diag.W.LogTradeDelayedOutOfRange:format(tostring(playerName), tostring(itemLink)))
                addon.Raid:ClearRaidIcons()
                SetRaidTarget(lootState.trader, 1)
                if isAwardRoll then SetRaidTarget(playerName, 4) end
                output = L.ChatTrade:format(playerName, itemLink)
            end
        end

        if not announced then
            if output then addon:Announce(output) end
            if whisper then
                if playerName == lootState.trader then
                    addon.Loot:ClearLoot()
                    addon.Rolls:ClearRolls()
                    addon.Rolls:RecordRolls(false)
                else
                    Utils.whisper(playerName, whisper)
                end
            end
            if rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE
                and playerName == lootState.trader then
                local ok = addon.Logger.Loot:Log(lootState.currentRollItem, lootState.trader, rollType, rollValue,
                    "TRADE_KEEP", KRT_CurrentRaid)
                if not ok then
                    addon:error(Diag.E.LogTradeKeepLoggerFailed:format(tostring(KRT_CurrentRaid),
                        tostring(lootState.currentRollItem), tostring(itemLink)))
                end
            end
            announced = true
        end
        return true
    end

    -- Register some callbacks:
    Utils.registerCallback("SetItem", function(f, itemLink)
        local oldItem = GetItemLink()
        if oldItem ~= itemLink then
            announced = false
        end
    end)

    -- Keep Master UI in sync when SoftRes data changes (import/clear), event-driven.
    Utils.registerCallback("ReservesDataChanged", function()
        module:RequestRefresh()
    end)
end




