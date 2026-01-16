local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local rollTypes = C.rollTypes
local RAID_TARGET_MARKERS = C.RAID_TARGET_MARKERS
addon.State = addon.State or {}
local coreState = addon.State
coreState.loot = coreState.loot or {}
local lootState = coreState.loot
lootState.itemInfo = lootState.itemInfo or {}
local itemInfo = lootState.itemInfo

---============================================================================
-- Master Looter Frame Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Master = addon.Master or {}
    local module = addon.Master
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_MASTER

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

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    local function SetItemCountValue(count, focus)
        frameName = frameName or Utils.getFrameName()
        if not frameName or frameName ~= UIMaster:GetName() then return end
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
        SetItemCountValue(addon.Loot:GetCurrentItemCount(), focus)
    end

    local function StopCountdown()
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
        countdownEndTimer = addon.After(duration, function()
            if not countdownRun then return end
            StopCountdown()
            addon:Announce(L.ChatCountdownEnd)

            -- ✅ a 0: stop roll (abilita selezione in Rolls) + refresh UI
            addon.Rolls:RecordRolls(false)
            addon.Rolls:FetchRolls()
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
        UpdateEnabled("openReserves", _G[frameName .. "OpenReservesBtn"], state.canOpenReserves)
        UpdateEnabled("importReserves", _G[frameName .. "ImportReservesBtn"], state.canImportReserves)
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
        addon:debug(L.LogMLCandidateCacheBuilt:format(tostring(itemLink),
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



    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIMaster = frame
        addon.UIMaster = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", UpdateUIFrame)
        frame:SetScript("OnHide", function()
            if selectionFrame then selectionFrame:Hide() end
        end)
    end

    --
    -- Toggles the visibility of the Master Looter frame.
    --
    function module:Toggle()
        Utils.toggle(UIMaster)
    end

    --
    -- Hides the Master Looter frame.
    --
    function module:Hide()
        Utils.hideFrame(UIMaster)
    end

    --
    -- Button: Select/Remove Item
    --
    function module:BtnSelectItem(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if countdownRun then return end
        if lootState.fromInventory == true then
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            announced = false
            lootState.fromInventory = false
            if lootState.opened == true then addon.Loot:FetchLoot() end
        elseif selectionFrame then
            Utils.toggle(selectionFrame)
        end
    end

    --
    -- Button: Spam Loot Links or Do Ready Check
    --
    function module:BtnSpamLoot(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if lootState.fromInventory == true then
            addon:Announce(L.ChatReadyCheck)
            DoReadyCheck()
        else
            addon:Announce(L.ChatSpamLoot, "RAID")
            for i = 1, lootState.lootCount do
                local itemLink = addon.Loot:GetItemLink(i)
                if itemLink then
                    addon:Announce(i .. ". " .. itemLink, "RAID")
                end
            end
        end
    end

    --
    -- Button: Open Reserves List
    --
    function module:BtnOpenReserves(btn)
        addon.Reserves:ShowWindow()
    end

    --
    -- Button: Import Reserves
    --
    function module:BtnImportReserves(btn)
        addon.Reserves:ShowImportBox()
    end

    --
    -- Generic function to announce a roll for the current item.
    --
    local function AnnounceRoll(rollType, chatMsg)
        if lootState.lootCount >= 1 then
            announced = false
            lootState.currentRollType = rollType
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(true)
            lootState.rollStarted = true
            lootState.itemTraded = 0

            local itemLink = addon.Loot:GetItemLink()
            local itemID = Utils.getItemIdFromLink(itemLink)
            local message = ""

            if rollType == rollTypes.RESERVED then
                local srList = addon.Reserves:FormatReservedPlayersLine(itemID)
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
        end
    end

    local function AssignToTarget(rollType, targetKey)
        if lootState.lootCount <= 0 or not lootState[targetKey] then return end
        countdownRun = false
        local itemLink = addon.Loot:GetItemLink()
        if not itemLink then return end
        lootState.currentRollType = rollType
        local target = lootState[targetKey]
        if lootState.fromInventory then
            return TradeItem(itemLink, target, rollType, 0)
        end
        return AssignItem(itemLink, target, rollType, 0)
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

    --
    -- Button: Starts or stops the roll countdown.
    --
    function module:BtnCountdown(btn)
        if countdownRun then
            addon.Rolls:RecordRolls(false)
            StopCountdown()
            addon.Rolls:FetchRolls()
        elseif not lootState.rollStarted then
            return
        else
            addon.Rolls:RecordRolls(true)
            announced = false
            StartCountdown()
        end
    end

    --
    -- Button: Clear Rolls
    --
    function module:BtnClear(btn)
        announced = false
        return addon.Rolls:ClearRolls()
    end

    --
    -- Button: Award/Trade
    --
    function module:BtnAward(btn)
        if countdownRun then
            addon:warn("Countdown ancora attivo: attendi la fine (0) prima di assegnare.")
            return
        end
        if lootState.lootCount <= 0 or lootState.rollsCount <= 0 then
            addon:debug("Award: blocked lootCount=%d rollsCount=%d.", lootState.lootCount or 0,
                lootState.rollsCount or 0)
            return
        end
        if not lootState.winner then
            addon:warn(L.ErrNoWinnerSelected)
            return
        end
        countdownRun = false
        local itemLink = addon.Loot:GetItemLink()
        addon:info(L.LogMLAwardRequested:format(tostring(lootState.winner),
            tonumber(lootState.currentRollType) or -1, addon.Rolls:HighestRoll() or 0, tostring(itemLink)))
        local result
        if lootState.fromInventory == true then
            result = TradeItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
        else
            result = AssignItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
            if result then
                RegisterAwardedItem()
            end
        end
        module:ResetItemCount()
        return result
    end

    --
    -- Button: Hold item
    --
    function module:BtnHold(btn)
        return AssignToTarget(rollTypes.HOLD, "holder")
    end

    --
    -- Button: Bank item
    --
    function module:BtnBank(btn)
        return AssignToTarget(rollTypes.BANK, "banker")
    end

    --
    -- Button: Disenchant item
    --
    function module:BtnDisenchant(btn)
        return AssignToTarget(rollTypes.DISENCHANT, "disenchanter")
    end

    --
    -- Selects a winner from the roll list.
    --
    function module:SelectWinner(btn)
        if not btn then return end
        local btnName = btn:GetName()
        local raw = btn.playerName or _G[btnName .. "Name"]:GetText() or ""
        local player = Utils.trimText(raw:gsub("^%s*>%s*(.-)%s*<%s*$", "%1"))
        if player ~= "" then
            if IsControlKeyDown() then
                local roll = _G[btnName .. "Roll"]:GetText()
                addon:Announce(format(L.ChatPlayerRolled, player, roll))
                return
            end
            lootState.winner = player
            addon.Rolls:FetchRolls()
            Utils.sync("KRT-RollWinner", player)
        end
        if lootState.itemCount == 1 then announced = false end
    end

    --
    -- Selects an item from the item selection frame.
    --
    function module:BtnSelectedItem(btn)
        if not btn then return end
        local index = btn:GetID()
        if index ~= nil then
            announced = false
            selectionFrame:Hide()
            addon.Loot:SelectItem(index)
            module:ResetItemCount()
        end
    end

    --
    -- Localizes UI frame elements.
    --
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
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
            _G[frameName .. "RollsHeaderRoll"]:SetText(L.StrRoll)
            _G[frameName .. "OpenReservesBtn"]:SetText(L.BtnOpenReserves)
            _G[frameName .. "RaidListBtn"]:SetText(L.BtnRaidList)
            _G[frameName .. "ImportReservesBtn"]:SetText(L.BtnImportReserves)
        end
        Utils.setFrameTitle(frameName, MASTER_LOOTER)
        _G[frameName .. "ItemCount"]:SetScript("OnTextChanged", function(self)
            announced = false
            dirtyFlags.itemCount = true
        end)
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
                if itemInfo.count and itemInfo.count ~= lootState.itemCount then
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

    --
    -- OnUpdate handler for the frame, updates UI elements periodically.
    --
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
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

            local hasItem = addon.Loot:ItemExists()
            FlagButtonsOnChange("hasItem", hasItem)

            local itemId
            if hasItem then
                itemId = Utils.getItemIdFromLink(addon.Loot:GetItemLink())
            end
            local hasItemReserves = itemId and addon.Reserves:HasItemReserves(itemId) or false
            FlagButtonsOnChange("hasItemReserves", hasItemReserves)
            FlagButtonsOnChange("countdownRun", countdownRun)

            if dirtyFlags.buttons then
                UpdateMasterButtonsIfChanged({
                    countdownText = countdownRun and L.BtnStop or L.BtnCountdown,
                    awardText = lootState.fromInventory and TRADE or L.BtnAward,
                    selectItemText = lootState.fromInventory and L.BtnRemoveItem or L.BtnSelectItem,
                    spamLootText = lootState.fromInventory and READY_CHECK or L.BtnSpamLoot,
                    canSelectItem = (lootState.lootCount > 1
                        or (lootState.fromInventory and lootState.lootCount >= 1)) and not countdownRun,
                    canChangeItem = hasItem and not countdownRun,
                    canSpamLoot = lootState.lootCount >= 1,
                    canStartRolls = lootState.lootCount >= 1,
                    canStartSR = lootState.lootCount >= 1 and hasItemReserves,
                    canCountdown = lootState.lootCount >= 1 and hasItem
                        and (lootState.rollStarted or countdownRun),
                    canHold = lootState.lootCount >= 1 and lootState.holder,
                    canBank = lootState.lootCount >= 1 and lootState.banker,
                    canDisenchant = lootState.lootCount >= 1 and lootState.disenchanter,
                    canAward = lootState.lootCount >= 1 and lootState.rollsCount >= 1 and not countdownRun,
                    canOpenReserves = hasReserves,
                    canImportReserves = not hasReserves,
                    canRoll = record and canRoll and rolled == false and countdownRun,
                    canClear = lootState.rollsCount >= 1,
                })
                dirtyFlags.buttons = false
            end

            dirtyFlags.rolls = false
            dirtyFlags.winner = false
        end)
    end

    --
    -- Initializes the dropdown menus for player selection.
    --
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

    --
    -- Prepares the data for the dropdowns by fetching the raid roster.
    --
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

    --
    -- OnClick handler for dropdown menu items.
    --
    function module:OnClickDropDown(owner, value)
        if not KRT_CurrentRaid then return end
        UIDropDownMenu_SetText(owner, value)
        UIDropDownMenu_SetSelectedValue(owner, value)
        local name = owner:GetName()
        if name == dropDownFrameHolder:GetName() then
            KRT_Raids[KRT_CurrentRaid].holder = value
            lootState.holder = value
        elseif name == dropDownFrameBanker:GetName() then
            KRT_Raids[KRT_CurrentRaid].banker = value
            lootState.banker = value
        elseif name == dropDownFrameDisenchanter:GetName() then
            KRT_Raids[KRT_CurrentRaid].disenchanter = value
            lootState.disenchanter = value
        end
        dropDownDirty = true
        dirtyFlags.dropdowns = true
        dirtyFlags.buttons = true
        CloseDropDownMenus()
    end

    --
    -- Updates the text of the dropdowns to reflect the current selection.
    --
    function UpdateDropDowns(frame)
        if not frame or not KRT_CurrentRaid then return end
        local name = frame:GetName()
        -- Update loot holder:
        if name == dropDownFrameHolder:GetName() then
            lootState.holder = KRT_Raids[KRT_CurrentRaid].holder
            if lootState.holder and addon.Raid:GetUnitID(lootState.holder) == "none" then
                KRT_Raids[KRT_CurrentRaid].holder = nil
                lootState.holder = nil
            end
            if lootState.holder then
                UIDropDownMenu_SetText(dropDownFrameHolder, lootState.holder)
                UIDropDownMenu_SetSelectedValue(dropDownFrameHolder, lootState.holder)
                dirtyFlags.buttons = true
            end
            -- Update loot banker:
        elseif name == dropDownFrameBanker:GetName() then
            lootState.banker = KRT_Raids[KRT_CurrentRaid].banker
            if lootState.banker and addon.Raid:GetUnitID(lootState.banker) == "none" then
                KRT_Raids[KRT_CurrentRaid].banker = nil
                lootState.banker = nil
            end
            if lootState.banker then
                UIDropDownMenu_SetText(dropDownFrameBanker, lootState.banker)
                UIDropDownMenu_SetSelectedValue(dropDownFrameBanker, lootState.banker)
                dirtyFlags.buttons = true
            end
            -- Update loot disenchanter:
        elseif name == dropDownFrameDisenchanter:GetName() then
            lootState.disenchanter = KRT_Raids[KRT_CurrentRaid].disenchanter
            if lootState.disenchanter and addon.Raid:GetUnitID(lootState.disenchanter) == "none" then
                KRT_Raids[KRT_CurrentRaid].disenchanter = nil
                lootState.disenchanter = nil
            end
            if lootState.disenchanter then
                UIDropDownMenu_SetText(dropDownFrameDisenchanter, lootState.disenchanter)
                UIDropDownMenu_SetSelectedValue(dropDownFrameDisenchanter, lootState.disenchanter)
                dirtyFlags.buttons = true
            end
        end
    end

    --
    -- Creates the item selection frame if it doesn't exist.
    --
    local function CreateSelectionFrame()
        if selectionFrame == nil then
            selectionFrame = CreateFrame("Frame", nil, UIMaster, "KRTSimpleFrameTemplate")
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

    --
    -- Updates the item selection frame with the current loot items.
    --
    function UpdateSelectionFrame()
        CreateSelectionFrame()
        local height = 5
        for i = 1, lootState.lootCount do
            local btnName = frameName .. "ItemSelectionBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
            btn:SetID(i)
            btn:Show()
            local itemName = addon.Loot:GetItemName(i)
            local itemNameBtn = _G[btnName .. "Name"]
            itemNameBtn:SetText(itemName)
            local itemTexture = addon.Loot:GetItemTexture(i)
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

    --------------------------------------------------------------------------
    -- Event Handlers & Callbacks
    --------------------------------------------------------------------------

    --
    -- ITEM_LOCKED: Triggered when an item is picked up from inventory.
    --
    function module:ITEM_LOCKED(inBag, inSlot)
        if not inBag or not inSlot then return end
        local itemTexture, count, locked, quality, _, _, itemLink = GetContainerItemInfo(inBag, inSlot)
        if not itemLink or not itemTexture then return end
        addon:trace(L.LogMLItemLocked:format(tostring(inBag), tostring(inSlot), tostring(itemLink),
            tostring(count), tostring(addon.Loot:ItemIsSoulbound(inBag, inSlot))))
        lootState.itemCount = count or lootState.itemCount or 1
        _G[frameName .. "ItemBtn"]:SetScript("OnClick", function(self)
            if countdownRun then
                return
            end
            if not addon.Loot:ItemIsSoulbound(inBag, inSlot) then
                -- Clear count:
                Utils.resetEditBox(_G[frameName .. "ItemCount"], true)

                lootState.fromInventory = true
                addon.Loot:AddItem(itemLink, count)
                addon.Loot:PrepareItem()
                announced        = false
                -- self.Logger:SetSource("inventory")
                itemInfo.bagID   = inBag
                itemInfo.slotID  = inSlot
                itemInfo.count   = count or 1
                itemInfo.isStack = (itemInfo.count > 1)
                module:ResetItemCount(true)
            else
                addon:warn(L.LogMLInventorySoulbound:format(tostring(itemLink)))
            end
            ClearCursor()
        end)
    end

    --
    -- LOOT_OPENED: Triggered when the loot window opens.
    --
    function module:LOOT_OPENED()
        if addon.Raid:IsMasterLooter() then
            lootState.opened = true
            announced = false
            addon.Loot:FetchLoot()
            addon:trace(L.LogMLLootOpenedTrace:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory)))
            UpdateSelectionFrame()
            if lootState.lootCount >= 1 then UIMaster:Show() end
            if not addon.Logger.container then
                addon.Logger.source = UnitName("target")
            end
            addon:info(L.LogMLLootOpenedInfo:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory), tostring(UnitName("target"))))
        end
    end

    --
    -- LOOT_CLOSED: Triggered when the loot window closes.
    --
    function module:LOOT_CLOSED()
        if addon.Raid:IsMasterLooter() then
            addon:trace(L.LogMLLootClosed:format(tostring(lootState.opened), lootState.lootCount or 0))
            addon:trace(L.LogMLLootClosedCleanup)
            if lootState.closeTimer then
                addon.CancelTimer(lootState.closeTimer)
                lootState.closeTimer = nil
            end
            lootState.closeTimer = addon.After(0.1, function()
                lootState.closeTimer = nil
                lootState.opened = false
                lootState.pendingAward = nil
                UIMaster:Hide()
                addon.Loot:ClearLoot()
                addon.Rolls:ClearRolls()
                addon.Rolls:RecordRolls(false)
            end)
        end
    end

    --
    -- LOOT_SLOT_CLEARED: Triggered when an item is looted.
    --
    function module:LOOT_SLOT_CLEARED()
        if addon.Raid:IsMasterLooter() then
            addon.Loot:FetchLoot()
            addon:trace(L.LogMLLootSlotCleared:format(lootState.lootCount or 0))
            UpdateSelectionFrame()
            if lootState.lootCount >= 1 then
                UIMaster:Show()
            else
                UIMaster:Hide()
                addon:info(L.LogMLLootWindowEmptied)
            end
            module:ResetItemCount()
        end
    end

    --
    -- TRADE_ACCEPT_UPDATE: Triggered during a trade.
    --
    function module:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
        addon:trace(L.LogTradeAcceptUpdate:format(tostring(lootState.trader), tostring(lootState.winner),
            tostring(tAccepted), tostring(pAccepted)))
        if lootState.trader and lootState.winner and lootState.trader ~= lootState.winner then
            if tAccepted == 1 and pAccepted == 1 then
                addon:info(L.LogTradeCompleted:format(tostring(lootState.currentRollItem),
                    tostring(lootState.winner), tonumber(lootState.currentRollType) or -1,
                    addon.Rolls:HighestRoll()))
                if lootState.currentRollItem and lootState.currentRollItem > 0 then
                    local ok = addon.Logger.Loot:Log(lootState.currentRollItem, lootState.winner,
                        lootState.currentRollType, addon.Rolls:HighestRoll(), "TRADE_ACCEPT", KRT_CurrentRaid)

                    if not ok then
                        addon:error(L.LogTradeLoggerLogFailed:format(tostring(KRT_CurrentRaid),
                            tostring(lootState.currentRollItem), tostring(addon.Loot:GetItemLink())))
                    end
                else
                    addon:warn("Trade: currentRollItem missing; cannot update loot entry.")
                end
                local done = RegisterAwardedItem()
                ResetTradeState()
                if done then
                    addon.Loot:ClearLoot()
                    addon.Raid:ClearRaidIcons()
                end
                screenshotWarn = false
            end
        end
    end

    --
    -- TRADE_CLOSED: trade window closed (completed or canceled)
    --
    function module:TRADE_CLOSED()
        ResetTradeState("TRADE_CLOSED")
    end

    --
    -- TRADE_REQUEST_CANCEL: trade request canceled before opening
    --
    function module:TRADE_REQUEST_CANCEL()
        ResetTradeState("TRADE_REQUEST_CANCEL")
    end

    --
    -- Assigns an item from the loot window to a player.
    --
    function AssignItem(itemLink, playerName, rollType, rollValue)
        local itemIndex, tempItemLink
        for i = 1, GetNumLootItems() do
            tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                itemIndex = i
                break
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
            addon:debug(L.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            BuildCandidateCache(itemLink)
            candidateIndex = candidateCache.indexByName[playerName]
        end
        if candidateIndex then
            -- Mark this award as addon-driven so AddLoot() won't classify it as MANUAL
            lootState.pendingAward = {
                itemLink  = itemLink,
                looter    = playerName,
                rollType  = rollType,
                rollValue = rollValue,
                ts        = GetTime(),
            }
            GiveMasterLoot(itemIndex, candidateIndex)
            addon:info(L.LogMLAwarded:format(tostring(itemLink), tostring(playerName),
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
            if lootState.currentRollItem and lootState.currentRollItem > 0 then
                local ok = addon.Logger.Loot:Log(lootState.currentRollItem, playerName, rollType, rollValue, "ML_AWARD",
                    KRT_CurrentRaid)
                if not ok then
                    addon:error(L.LogMLAwardLoggerFailed:format(tostring(KRT_CurrentRaid),
                        tostring(lootState.currentRollItem), tostring(itemLink)))
                end
            end
            return true
        end
        addon:error(L.ErrCannotFindPlayer:format(playerName))
        return false
    end

    --
    -- Trades an item from inventory to a player.
    --
    function TradeItem(itemLink, playerName, rollType, rollValue)
        if itemLink ~= addon.Loot:GetItemLink() then return end
        local isAwardRoll = (rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE)

        ResetTradeState("TRADE_START")

        lootState.trader = Utils.getPlayerName()
        lootState.winner = isAwardRoll and playerName or nil

        addon:info(L.LogTradeStart:format(tostring(itemLink), tostring(lootState.trader),
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
            SetRaidTarget(lootState.trader, 1)
            local rolls = addon.Rolls:GetRolls()
            local winners = {}
            for i = 1, lootState.itemCount do
                if rolls[i] then
                    if rolls[i].name == lootState.trader then
                        tinsert(winners, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
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
            addon:info(L.LogTradeTraderKeeps:format(tostring(itemLink), tostring(playerName)))
            local done = RegisterAwardedItem(lootState.itemCount)
            if done then
                addon.Loot:ClearLoot()
                addon.Raid:ClearRaidIcons()
            end
        else
            local unit = addon.Raid:GetUnitID(playerName)
            if unit ~= "none" and CheckInteractDistance(unit, 2) == 1 then
                -- Player is in range for trade
                if itemInfo.isStack and not addon.options.ignoreStacks then
                    addon:warn(L.LogTradeStackBlocked:format(tostring(addon.options.ignoreStacks),
                        tostring(itemLink)))
                    addon:warn(L.ErrItemStack:format(itemLink))
                    return false
                end
                ClearCursor()
                PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
                if CursorHasItem() then
                    InitiateTrade(playerName)
                    addon:info(L.LogTradeInitiated:format(tostring(itemLink), tostring(playerName)))
                    if addon.options.screenReminder and not screenshotWarn then
                        addon:warn(L.ErrScreenReminder)
                        screenshotWarn = true
                    end
                end
                -- Cannot trade the player?
            elseif unit ~= "none" then
                -- Player is out of range
                addon:warn(L.LogTradeDelayedOutOfRange:format(tostring(playerName), tostring(itemLink)))
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
                    addon:error(L.LogTradeKeepLoggerFailed:format(tostring(KRT_CurrentRaid),
                        tostring(lootState.currentRollItem), tostring(itemLink)))
                end
            end
            announced = true
        end
        return true
    end

    -- Register some callbacks:
    Utils.registerCallback("SetItem", function(f, itemLink)
        local oldItem = addon.Loot:GetItemLink()
        if oldItem ~= itemLink then
            announced = false
        end
    end)
end

---============================================================================
-- Loot Counter Module
-- Counter and display item distribution.
---============================================================================
do
    local module = addon.Master

    local rows, raidPlayers = {}, {}
    local twipe = twipe
    local countsFrame, scrollChild, needsUpdate, countsTicker = nil, nil, false, nil

    local function RequestCountsUpdate()
        needsUpdate = true
    end

    local function TickCounts()
        if needsUpdate then
            needsUpdate = false
            addon.Master:UpdateCountsFrame()
        end
    end

    local function StartCountsTicker()
        if not countsTicker then
            countsTicker = addon.NewTicker(C.LOOT_COUNTER_TICK_INTERVAL, TickCounts)
        end
    end

    local function StopCountsTicker()
        if countsTicker then
            addon.CancelTimer(countsTicker, true)
            countsTicker = nil
        end
    end

    -- Helper to ensure frames exist
    local function EnsureFrames()
        countsFrame = countsFrame or _G["KRTLootCounterFrame"]
        scrollChild = scrollChild or _G["KRTLootCounterFrameScrollFrameScrollChild"]
        if countsFrame and not countsFrame._krtCounterHook then
            local title = _G["KRTLootCounterFrameTitle"]
            Utils.setFrameTitle("KRTLootCounterFrame", L.StrLootCounter)
            if title then title:Show() end
            countsFrame:SetScript("OnShow", StartCountsTicker)
            countsFrame:SetScript("OnHide", StopCountsTicker)
            countsFrame._krtCounterHook = true
        end
    end

    -- Return sorted array of player names currently in the raid.
    local function GetCurrentRaidPlayers()
        twipe(raidPlayers)
        if not addon.IsInGroup() then
            return raidPlayers
        end
        for unit, owner in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" then
                raidPlayers[#raidPlayers + 1] = name
                if KRT_PlayerCounts[name] == nil then
                    KRT_PlayerCounts[name] = 0
                end
            end
        end
        table.sort(raidPlayers)
        return raidPlayers
    end

    -- Show or hide the loot counter frame.
    function module:ToggleCountsFrame()
        EnsureFrames()
        if countsFrame then
            if countsFrame:IsShown() then
                Utils.setShown(countsFrame, false)
            else
                RequestCountsUpdate()
                Utils.setShown(countsFrame, true)
            end
        end
    end

    -- Update the loot counter UI with current player counts.
    function module:UpdateCountsFrame()
        EnsureFrames()
        if not countsFrame or not scrollChild then return end

        local players = GetCurrentRaidPlayers()
        local numPlayers = #players
        local rowHeight = C.LOOT_COUNTER_ROW_HEIGHT
        local counts = KRT_PlayerCounts

        scrollChild:SetHeight(numPlayers * rowHeight)

        -- Create/reuse rows for each player
        for i = 1, numPlayers do
            local name = players[i]
            local row  = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, scrollChild)
                row:SetSize(160, 24)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)

                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.name:SetPoint("LEFT", row, "LEFT", 0, 0)

                row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.count:SetPoint("LEFT", row.name, "RIGHT", 10, 0)

                row.plus = CreateFrame("Button", nil, row, "KRTButtonTemplate")
                row.plus:SetSize(22, 22)
                row.plus:SetText("+")
                row.plus:SetPoint("LEFT", row.count, "RIGHT", 5, 0)

                row.minus = CreateFrame("Button", nil, row, "KRTButtonTemplate")
                row.minus:SetSize(22, 22)
                row.minus:SetText("-")
                row.minus:SetPoint("LEFT", row.plus, "RIGHT", 2, 0)

                row.plus:SetScript("OnClick", function()
                    local n = row._playerName
                    if n then
                        counts[n] = (counts[n] or 0) + 1
                        RequestCountsUpdate()
                    end
                end)
                row.minus:SetScript("OnClick", function()
                    local n = row._playerName
                    if n then
                        local c = (counts[n] or 0) - 1
                        counts[n] = c > 0 and c or 0
                        RequestCountsUpdate()
                    end
                end)

                rows[i] = row
            else
                -- Move if needed (in case of roster change)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            end

            row._playerName = name
            row.name:SetText(name)
            row.count:SetText(tostring(counts[name] or 0))
            row:Show()
        end

        -- Hide extra rows not needed
        for i = numPlayers + 1, #rows do
            if rows[i] then rows[i]:Hide() end
        end
    end

    -- Add a button to the master loot frame to open the loot counter UI
    -------------------------------------------------------
    -- Event hooks
    -------------------------------------------------------
    local function SetupMasterLootFrameHooks()
        local f = _G["KRTMasterLootFrame"]
        if f and not f.KRT_LootCounterBtn then
            local btn = CreateFrame("Button", nil, f, "KRTButtonTemplate")
            btn:SetSize(100, 24)
            btn:SetText(L.BtnLootCounter)
            btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -20)
            btn:SetScript("OnClick", function()
                addon.Master:ToggleCountsFrame()
            end)
            f.KRT_LootCounterBtn = btn

            f:HookScript("OnHide", function()
                if countsFrame and countsFrame:IsShown() then
                    Utils.setShown(countsFrame, false)
                end
            end)
        end
    end
    hooksecurefunc(addon.Master, "OnLoad", SetupMasterLootFrameHooks)
end
