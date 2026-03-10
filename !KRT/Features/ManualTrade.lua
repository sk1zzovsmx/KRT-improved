--[[
    Features/ManualTrade.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local Core = feature.Core

local rollTypes = feature.rollTypes
local lootState = feature.lootState

local _G = _G
local tinsert = table.insert
local twipe = table.wipe or function(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
end
local tconcat = table.concat
local pairs = pairs
local tostring, tonumber = tostring, tonumber

-- =========== Manual Trade Module =========== --
do
    addon.ManualTrade = addon.ManualTrade or {}
    local module = addon.ManualTrade

    -- ----- Internal state ----- --
    local reasonOrder = {
        rollTypes.MAINSPEC,
        rollTypes.OFFSPEC,
        rollTypes.RESERVED,
        rollTypes.FREE,
        rollTypes.HOLD,
        rollTypes.BANK,
        rollTypes.DISENCHANT,
    }

    local openRollTypes = {
        [rollTypes.HOLD] = true,
        [rollTypes.BANK] = true,
        [rollTypes.DISENCHANT] = true,
        [rollTypes.MANUAL] = true,
    }
    local dropdownTextSize = 9

    -- ----- Private helpers ----- --
    local function getReasonText(reason)
        if reason == rollTypes.MAINSPEC then
            return L.BtnMS
        elseif reason == rollTypes.OFFSPEC then
            return L.BtnOS
        elseif reason == rollTypes.RESERVED then
            return L.BtnSR
        elseif reason == rollTypes.FREE then
            return L.BtnFree
        elseif reason == rollTypes.BANK then
            return L.BtnBank
        elseif reason == rollTypes.DISENCHANT then
            return L.BtnDisenchant
        end
        return L.BtnHold
    end

    local function normalizeReason(reason)
        local value = tonumber(reason)
        for i = 1, #reasonOrder do
            if value == reasonOrder[i] then
                return value
            end
        end
        return rollTypes.HOLD
    end

    local function normalizeTradeName(name)
        name = Utils.trimText(name, true)
        if not name or name == "" then
            return nil
        end
        if name:find("-", 1, true) then
            name = name:match("^([^%-]+)") or name
        end
        name = Utils.normalizeName(name, true)
        return name
    end

    local function isAddonDrivenTradeActive()
        return lootState.trader and lootState.winner and lootState.trader ~= lootState.winner
    end

    local function ensureState()
        lootState.manualTrade = lootState.manualTrade or {}
        local state = lootState.manualTrade
        if state.active == nil then
            state.active = false
        end
        if state.acceptProcessed == nil then
            state.acceptProcessed = false
        end
        state.candidatesBySlot = state.candidatesBySlot or {}
        state.candidatesOrdered = state.candidatesOrdered or {}
        state.selectedReasonByLootNid = state.selectedReasonByLootNid or {}
        state.dropdownFrames = state.dropdownFrames or {}
        return state
    end

    local function hideReasonDropdowns()
        local state = lootState.manualTrade
        if not state then
            return
        end

        local frames = state.dropdownFrames
        if frames then
            for slot = 1, 6 do
                local dropdown = frames[slot]
                if dropdown then
                    dropdown:Hide()
                end
            end
        end
    end

    local function getTradePlayerSlotAnchor(slot)
        local baseName = "TradePlayerItem" .. tostring(slot)
        local slotAnchor = _G[baseName]
            or _G[baseName .. "ItemButton"]
        return slotAnchor
    end

    local function applyDropdownTextStyle(dropdown)
        if not (dropdown and dropdown.GetName) then
            return
        end

        local text = _G[dropdown:GetName() .. "Text"]
        if not text then
            return
        end

        local fontPath, _, fontFlags = text:GetFont()
        if fontPath and text.SetFont then
            text:SetFont(fontPath, dropdownTextSize, fontFlags)
        elseif text.SetFontObject then
            text:SetFontObject(GameFontNormalSmall)
        end
        text:SetTextColor(1, 1, 1)
    end

    local function buildOrUpdateReasonDropdown(slot)
        local tradeFrame = _G.TradeFrame
        if not tradeFrame then
            return nil
        end

        local state = ensureState()
        local dropdown = state.dropdownFrames[slot]
        if not dropdown then
            local dropdownName = "KRTManualTradeReasonDropDown" .. tostring(slot)
            dropdown = _G[dropdownName]
                or CreateFrame("Frame", dropdownName, tradeFrame, "UIDropDownMenuTemplate")
            state.dropdownFrames[slot] = dropdown
            dropdown.krtSlot = slot
            dropdown:SetFrameStrata("DIALOG")
            dropdown:SetToplevel(true)
            UIDropDownMenu_SetWidth(dropdown, 47)
            UIDropDownMenu_JustifyText(dropdown, "LEFT")

            UIDropDownMenu_Initialize(dropdown, function(frame, level)
                if level ~= 1 then
                    return
                end
                local stateNow = ensureState()
                local slotNow = tonumber(frame.krtSlot) or 0
                local selectedReason = rollTypes.HOLD
                local candidate = stateNow.candidatesBySlot and stateNow.candidatesBySlot[slotNow]
                if candidate then
                    selectedReason = normalizeReason(stateNow.selectedReasonByLootNid[candidate.lootNid])
                end

                for i = 1, #reasonOrder do
                    local reason = reasonOrder[i]
                    local info = UIDropDownMenu_CreateInfo()
                    info.hasArrow = false
                    info.notCheckable = 1
                    info.text = getReasonText(reason)
                    info.arg1 = reason
                    info.func = function(_, pickedReason)
                        local current = ensureState()
                        local slotCurrent = tonumber(frame.krtSlot) or 0
                        local currentCandidate = current.candidatesBySlot and current.candidatesBySlot[slotCurrent]
                        if not currentCandidate then
                            CloseDropDownMenus()
                            return
                        end
                        local picked = normalizeReason(pickedReason)
                        current.selectedReasonByLootNid[currentCandidate.lootNid] = picked
                        currentCandidate.selectedReason = picked
                        UIDropDownMenu_SetSelectedValue(frame, picked)
                        UIDropDownMenu_SetText(frame, getReasonText(picked))
                        CloseDropDownMenus()
                    end
                    info.checked = (selectedReason == reason) and 1 or nil
                    UIDropDownMenu_AddButton(info, level)
                end
            end)

            applyDropdownTextStyle(dropdown)
        end

        local slotAnchor = getTradePlayerSlotAnchor(slot)
        if not slotAnchor then
            dropdown:Hide()
            return nil
        end

        applyDropdownTextStyle(dropdown)
        dropdown:ClearAllPoints()
        -- Anchor to the player trade slot row so the dropdown stays in the left panel.
        dropdown:SetPoint("BOTTOMRIGHT", slotAnchor, "BOTTOMRIGHT", 8, -8)
        return dropdown
    end

    local function showReasonDropdowns()
        local state = ensureState()

        for slot = 1, 6 do
            local candidate = state.candidatesBySlot[slot]
            if candidate then
                local dropdown = buildOrUpdateReasonDropdown(slot)
                if dropdown then
                    local reason = normalizeReason(state.selectedReasonByLootNid[candidate.lootNid])
                    state.selectedReasonByLootNid[candidate.lootNid] = reason
                    candidate.selectedReason = reason
                    UIDropDownMenu_SetSelectedValue(dropdown, reason)
                    UIDropDownMenu_SetText(dropdown, getReasonText(reason))
                    applyDropdownTextStyle(dropdown)
                    dropdown:Show()
                end
            else
                local dropdown = state.dropdownFrames[slot]
                if dropdown then
                    dropdown:Hide()
                end
            end
        end
    end

    local function getTradePlayerItems()
        local items = {}
        local itemCount = 0

        for slot = 1, 6 do
            local itemLink = GetTradePlayerItemLink(slot)
            if itemLink then
                itemCount = itemCount + 1
                tinsert(items, {
                    slot = slot,
                    itemLink = itemLink,
                    itemString = Utils.getItemStringFromLink(itemLink),
                    itemId = tonumber(Utils.getItemIdFromLink(itemLink)),
                })
            end
        end

        return items, itemCount
    end

    local function resolveTradePartnerName(raidId)
        local partnerName
        local recipientText = _G.TradeFrameRecipientNameText
        if recipientText and recipientText.GetText then
            partnerName = recipientText:GetText()
        end
        if not partnerName or partnerName == "" then
            partnerName = UnitName("NPC")
        end
        if not partnerName or partnerName == "" then
            partnerName = UnitName("target")
        end

        partnerName = normalizeTradeName(partnerName)
        if not partnerName then
            return nil
        end

        if addon.Raid and addon.Raid.CheckPlayer then
            local found, fixed = addon.Raid:CheckPlayer(partnerName, raidId)
            if found and fixed and fixed ~= "" then
                partnerName = fixed
            end
        end
        return partnerName
    end

    local function resolveSelfLooterName(raidId)
        local looterName = normalizeTradeName(Utils.getPlayerName())
        if not looterName then
            return nil
        end
        if addon.Raid and addon.Raid.CheckPlayer then
            local found, fixed = addon.Raid:CheckPlayer(looterName, raidId)
            if found and fixed and fixed ~= "" then
                looterName = fixed
            end
        end
        return looterName
    end

    local function collectOpenHoldEntries(looterName, raidId)
        if not (looterName and raidId) then
            return {}
        end

        local raid = Core.ensureRaidById and Core.ensureRaidById(raidId) or nil
        if not raid then
            return {}
        end
        if Core.ensureRaidSchema then
            Core.ensureRaidSchema(raid)
        end

        local loot = raid.loot or {}
        local looterLower = Utils.normalizeLower(looterName, true)
        if not looterLower then
            return {}
        end
        local out = {}

        for i = #loot, 1, -1 do
            local entry = loot[i]
            local entryType = tonumber(entry and entry.rollType) or -1
            if entry and openRollTypes[entryType] then
                local entryLooter = Utils.normalizeLower(entry.looter, true)
                if entryLooter and entryLooter == looterLower then
                    local lootNid = tonumber(entry.lootNid) or 0
                    if lootNid > 0 then
                        local entryString = entry.itemString
                        if not entryString and entry.itemLink then
                            entryString = Utils.getItemStringFromLink(entry.itemLink)
                        end
                        tinsert(out, {
                            lootNid = lootNid,
                            itemLink = entry.itemLink,
                            itemString = entryString,
                            itemId = tonumber(entry.itemId),
                        })
                    end
                end
            end
        end

        return out
    end

    local function findBestOpenEntry(openEntries, usedLootNids, tradeItem)
        if tradeItem.itemString then
            for i = 1, #openEntries do
                local entry = openEntries[i]
                if (not usedLootNids[entry.lootNid]) and entry.itemString == tradeItem.itemString then
                    return entry, "itemString"
                end
            end
        end

        if tradeItem.itemId then
            for i = 1, #openEntries do
                local entry = openEntries[i]
                if (not usedLootNids[entry.lootNid]) and entry.itemId == tradeItem.itemId then
                    return entry, "itemId"
                end
            end
        end

        return nil, nil
    end

    local function findOpenHoldMatches(tradeItems, looterName, raidId)
        local matchesBySlot = {}
        local matchesOrdered = {}
        if #tradeItems <= 0 then
            return matchesBySlot, matchesOrdered
        end

        local openEntries = collectOpenHoldEntries(looterName, raidId)
        if #openEntries <= 0 then
            return matchesBySlot, matchesOrdered
        end

        local usedLootNids = {}
        for i = 1, #tradeItems do
            local item = tradeItems[i]
            local matched, matchedBy = findBestOpenEntry(openEntries, usedLootNids, item)
            if matched then
                usedLootNids[matched.lootNid] = true
                local candidate = {
                    slot = item.slot,
                    lootNid = matched.lootNid,
                    itemLink = item.itemLink,
                    itemString = item.itemString,
                    itemId = item.itemId,
                    matchedBy = matchedBy,
                }
                matchesBySlot[item.slot] = candidate
                tinsert(matchesOrdered, candidate)
            end
        end

        return matchesBySlot, matchesOrdered
    end

    local function buildCandidateKey(candidatesBySlot, partnerName)
        local keyParts = { tostring(partnerName or "") }
        for slot = 1, 6 do
            local candidate = candidatesBySlot[slot]
            if candidate then
                keyParts[#keyParts + 1] = tostring(slot) .. ":" .. tostring(candidate.lootNid)
            end
        end
        return tconcat(keyParts, "\001")
    end

    local function resolveCounterTarget(partnerName, raidId)
        local canCount = false
        local counterName = partnerName
        if addon.Raid and addon.Raid.CheckPlayer then
            local found, fixed = addon.Raid:CheckPlayer(partnerName, raidId)
            if found then
                canCount = true
                if fixed and fixed ~= "" then
                    counterName = fixed
                end
            end
        end
        if (not canCount) and addon.Raid and addon.Raid.GetPlayerID then
            canCount = (tonumber(addon.Raid:GetPlayerID(partnerName, raidId)) or 0) > 0
        end
        return canCount, counterName
    end

    -- ----- Public methods ----- --
    function module:Reset(hideDropdown, keepAcceptProcessed)
        local state = ensureState()
        state.active = false
        if not keepAcceptProcessed then
            state.acceptProcessed = false
        end
        state.candidatesBySlot = state.candidatesBySlot or {}
        state.candidatesOrdered = state.candidatesOrdered or {}
        state.selectedReasonByLootNid = state.selectedReasonByLootNid or {}
        twipe(state.candidatesBySlot)
        twipe(state.candidatesOrdered)
        twipe(state.selectedReasonByLootNid)
        state.candidateLootNid = nil
        state.candidateItemLink = nil
        state.candidateItemString = nil
        state.candidateItemId = nil
        state.partnerName = nil
        state.candidateKey = nil
        if hideDropdown ~= false then
            hideReasonDropdowns()
        end
    end

    function module:RefreshCandidate(source)
        local state = ensureState()

        if isAddonDrivenTradeActive() then
            self:Reset(true, true)
            addon:trace(Diag.D.LogTradeManualCandidateOff:format(
                tostring(source or "trade"), "addon_driven"
            ))
            return nil
        end

        local tradeFrame = _G.TradeFrame
        if not (tradeFrame and tradeFrame.IsShown and tradeFrame:IsShown()) then
            self:Reset(true, true)
            addon:trace(Diag.D.LogTradeManualCandidateOff:format(
                tostring(source or "trade"), "frame_hidden"
            ))
            return nil
        end

        local raidId = Core.getCurrentRaid and Core.getCurrentRaid() or nil
        if not raidId then
            self:Reset(true, true)
            addon:trace(Diag.D.LogTradeManualCandidateOff:format(
                tostring(source or "trade"), "no_current_raid"
            ))
            return nil
        end

        local tradeItems, itemCount = getTradePlayerItems()
        if itemCount <= 0 then
            self:Reset(true, true)
            addon:trace(Diag.D.LogTradeManualCandidateOff:format(
                tostring(source or "trade"), "player_items_missing"
            ))
            return nil
        end

        local looterName = resolveSelfLooterName(raidId)
        if not looterName then
            self:Reset(true, true)
            addon:trace(Diag.D.LogTradeManualCandidateOff:format(
                tostring(source or "trade"), "looter_missing"
            ))
            return nil
        end

        local matchesBySlot, matchesOrdered = findOpenHoldMatches(tradeItems, looterName, raidId)
        if #matchesOrdered <= 0 then
            self:Reset(true, true)
            addon:trace(Diag.D.LogTradeManualNoHoldMatch:format(tostring(itemCount), tostring(looterName)))
            return nil
        end

        local partnerName = resolveTradePartnerName(raidId) or ""
        local nextKey = buildCandidateKey(matchesBySlot, partnerName)
        if state.acceptProcessed and state.candidateKey == nextKey then
            return state
        end

        local oldReasons = state.selectedReasonByLootNid or {}
        local nextReasons = {}
        for i = 1, #matchesOrdered do
            local candidate = matchesOrdered[i]
            local reason = oldReasons[candidate.lootNid]
            if reason == nil then
                reason = rollTypes.HOLD
            end
            reason = normalizeReason(reason)
            nextReasons[candidate.lootNid] = reason
            candidate.selectedReason = reason
        end

        local firstCandidate = matchesOrdered[1]
        state.active = true
        state.acceptProcessed = false
        state.candidatesBySlot = matchesBySlot
        state.candidatesOrdered = matchesOrdered
        state.selectedReasonByLootNid = nextReasons
        state.candidateLootNid = firstCandidate and firstCandidate.lootNid or nil
        state.candidateItemLink = firstCandidate and firstCandidate.itemLink or nil
        state.candidateItemString = firstCandidate and firstCandidate.itemString or nil
        state.candidateItemId = firstCandidate and firstCandidate.itemId or nil
        state.partnerName = partnerName
        state.candidateKey = nextKey

        showReasonDropdowns()
        for i = 1, #matchesOrdered do
            local candidate = matchesOrdered[i]
            addon:trace(Diag.D.LogTradeManualCandidateOn:format(
                tostring(candidate.lootNid), tostring(candidate.itemLink),
                tostring(partnerName), tostring(candidate.matchedBy)
            ))
        end
        return state
    end

    function module:HandleTradeAcceptUpdate(tAccepted, pAccepted)
        if tAccepted ~= 1 or pAccepted ~= 1 then
            return false
        end

        local state = ensureState()
        if state.acceptProcessed then
            addon:trace(Diag.D.LogTradeManualAcceptSkipped:format("already_processed"))
            return false
        end
        if isAddonDrivenTradeActive() then
            addon:trace(Diag.D.LogTradeManualAcceptSkipped:format("addon_driven"))
            return false
        end

        state = self:RefreshCandidate("TRADE_ACCEPT")
        if not (state and state.active) then
            addon:trace(Diag.D.LogTradeManualAcceptSkipped:format("candidate_missing"))
            return false
        end

        local raidId = Core.getCurrentRaid and Core.getCurrentRaid() or nil
        local partnerName = state.partnerName
        if not partnerName or partnerName == "" then
            partnerName = resolveTradePartnerName(raidId)
            state.partnerName = partnerName
        end
        if not partnerName or not raidId then
            addon:trace(Diag.D.LogTradeManualAcceptSkipped:format("invalid_payload"))
            return false
        end

        local candidates = state.candidatesOrdered or {}
        if #candidates <= 0 then
            addon:trace(Diag.D.LogTradeManualAcceptSkipped:format("candidate_missing"))
            return false
        end

        local loggedCount = 0
        local msCount = 0
        for i = 1, #candidates do
            local candidate = candidates[i]
            local lootNid = tonumber(candidate.lootNid) or 0
            if lootNid > 0 then
                local selectedReason = normalizeReason(state.selectedReasonByLootNid[lootNid])
                local ok = addon.Logger.Loot:Log(lootNid, partnerName, selectedReason, 0,
                    "TRADE_MANUAL_ACCEPT", raidId)
                if ok then
                    loggedCount = loggedCount + 1
                    if selectedReason == rollTypes.MAINSPEC then
                        msCount = msCount + 1
                    end
                    addon:debug(Diag.D.LogTradeManualAcceptDone:format(tostring(lootNid),
                        tostring(candidate.itemLink), tostring(partnerName), tostring(selectedReason)))
                else
                    addon:error(Diag.E.LogTradeManualLoggerFailed:format(
                        tostring(raidId), tostring(lootNid), tostring(candidate.itemLink), tostring(partnerName)
                    ))
                end
            end
        end

        if loggedCount <= 0 then
            addon:trace(Diag.D.LogTradeManualAcceptSkipped:format("logger_failed"))
            return false
        end

        if msCount > 0 then
            local canCount, counterName = resolveCounterTarget(partnerName, raidId)
            if canCount and addon.Raid and addon.Raid.AddPlayerCount then
                addon.Raid:AddPlayerCount(counterName, msCount, raidId)
            else
                addon:warn(Diag.W.LogTradeManualCounterSkipped:format(tostring(partnerName), tostring(raidId)))
            end
        end

        state.acceptProcessed = true
        state.active = false
        hideReasonDropdowns()
        return true
    end
end
