--[[
    Features/Rolls.lua
]]

local addon = select(2, ...)
addon = addon or {}

local feature = (addon.Core and addon.Core.getFeatureShared and addon.Core.getFeatureShared()) or {}

local L = feature.L or addon.L or {}
local Diag = feature.Diag or {}
local Utils = feature.Utils or addon.Utils
local C = feature.C or addon.C or {}

local tContains = feature.tContains or _G.tContains

local rollTypes = feature.rollTypes or C.rollTypes

local lootState = feature.lootState or ((feature.coreState or addon.State or {}).loot) or {}

local GetItem

local GetItemIndex = feature.GetItemIndex or function()
    return lootState.currentItemIndex or 0
end

local _G = _G
local tinsert, twipe = table.insert, table.wipe
local ipairs = ipairs
local format = string.format

local tostring, tonumber = tostring, tonumber

local function getLootModule()
    return addon.Loot
end

GetItem = function(i)
    local loot = getLootModule()
    return loot and loot.GetItem and loot.GetItem(i) or nil
end

-- =========== Rolls Helpers Module  =========== --
-- Manages roll tracking, sorting, and winner determination.
do
    addon.Rolls = addon.Rolls or {}
    local module = addon.Rolls
    -- Multi-selection context for manual multi-award winner picking (Master Loot window)
    local MS_CTX_ROLLS = "MLRollWinners"

    -- ---Internal state ----- --
    local state = {
        record       = false,
        canRoll      = true,
        warned       = false,
        rolled       = false,
        selected     = nil,
        selectedAuto = false,
        lastSortAsc  = nil,
        lastSortType = nil,
        rolls        = {},
        rerolled     = {},
        playerCounts = {},
        itemCounts   = nil,
        count        = 0,
        display      = nil,   -- compact list entries in current sort order
        displayNames = nil,   -- array of names in display order
        msPrefilled  = false, -- true after first Top-N prefill in multi-pick mode
    }
    local newItemCounts, delItemCounts
    if addon.TablePool then
        newItemCounts, delItemCounts = addon.TablePool("k")
    end
    state.itemCounts = newItemCounts and newItemCounts() or {}

    local function getMasterFrame()
        return (addon.Master and addon.Master.frame) or _G["KRTMaster"]
    end

    local requestRollsUiRefresh = Utils.makeEventDrivenRefresher(getMasterFrame, function()
        module:FetchRolls()
    end)

    local function requestRollsRefresh()
        requestRollsUiRefresh()
    end

    -- ----- Private helpers ----- --
    local function GetAllowedRolls(itemId, name)
        if not itemId or not name then return 1 end
        if lootState.currentRollType ~= rollTypes.RESERVED then
            return 1
        end
        local reserves = addon.Reserves:GetReserveCountForItem(itemId, name)
        return (reserves and reserves > 0) and reserves or 1
    end

    local function UpdateLocalRollState(itemId, name)
        if not itemId or not name then
            state.rolled = false
            return false
        end
        local allowed = GetAllowedRolls(itemId, name)
        local used = state.playerCounts[itemId] or 0
        state.rolled = used >= allowed
        return state.rolled
    end

    local function AcquireItemTracker(itemId)
        local tracker = state.itemCounts
        if not tracker[itemId] then
            tracker[itemId] = newItemCounts and newItemCounts() or {}
            -- Tracker tables are released via resetRolls() using delItemCounts(..., true)
        end
        return tracker[itemId]
    end

    local function PickBestReserved(itemId)
        if not itemId then return nil end
        local bestName, bestRoll, bestPlus = nil, nil, nil
        local wantLow = addon.options.sortAscending == true

        -- SR "Plus priority" is enabled only when the item has no multi-reserve entries.
        local usePlus = addon.Reserves
            and addon.Reserves.GetPlusForItem
            and addon.Reserves.GetImportMode
            and (addon.Reserves:IsPlusSystem())

        for _, entry in ipairs(state.rolls) do
            if module:IsReserved(itemId, entry.name) then
                local roll = entry.roll
                local plus = usePlus and (addon.Reserves:GetPlusForItem(itemId, entry.name) or 0) or 0

                if not bestName then
                    bestName, bestRoll, bestPlus = entry.name, roll, plus
                else
                    if usePlus and plus ~= bestPlus then
                        if plus > bestPlus then
                            bestName, bestRoll, bestPlus = entry.name, roll, plus
                        end
                    else
                        if wantLow then
                            if roll < bestRoll then
                                bestName, bestRoll, bestPlus = entry.name, roll, plus
                            end
                        else
                            if roll > bestRoll then
                                bestName, bestRoll, bestPlus = entry.name, roll, plus
                            end
                        end
                    end
                end
            end
        end

        return bestName, bestRoll
    end

    -- Factory to create a GetPlus function with its own cache for a specific itemId.
    local function MakePlusGetter(itemId)
        local plusCache = {}
        return function(name)
            local v = plusCache[name]
            if v == nil then
                v = (addon.Reserves and addon.Reserves.GetPlusForItem)
                    and (addon.Reserves:GetPlusForItem(itemId, name) or 0)
                    or 0
                plusCache[name] = v
            end
            return v
        end
    end

    -- Sorts rolls table + updates lootState.winner (top entry after sort).
    local function sortRolls(itemId)
        local rolls = state.rolls
        if #rolls == 0 then
            lootState.winner = nil
            lootState.rollWinner = nil
            addon:debug(Diag.D.LogRollsSortNoEntries)
            return
        end

        local isSR         = (lootState.currentRollType == rollTypes.RESERVED)
        local wantLow      = (addon.options.sortAscending == true)

        local plusPriority = isSR and itemId
            and addon.Reserves
            and addon.Reserves.GetPlusForItem
            and addon.Reserves.GetImportMode
            and (addon.Reserves:IsPlusSystem())

        local GetPlus      = MakePlusGetter(itemId)

        table.sort(rolls, function(a, b)
            -- SR: reserved first (session itemId)
            if isSR and itemId then
                local ar = module:IsReserved(itemId, a.name)
                local br = module:IsReserved(itemId, b.name)
                if ar ~= br then
                    return ar -- true first
                end

                -- SR + Plus priority (only when no multi-reserve exists for this item)
                if plusPriority and ar and br then
                    local ap = GetPlus(a.name)
                    local bp = GetPlus(b.name)
                    if ap ~= bp then
                        return ap > bp
                    end
                end
            end

            if a.roll ~= b.roll then
                return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
            end

            -- stable tie-breaker
            return tostring(a.name) < tostring(b.name)
        end)

        -- * top roll (always follows ascending/descending sort order)
        lootState.rollWinner = rolls[1].name

        -- Award target follows the top roll only when not manually selected
        if state.canRoll or state.selectedAuto or (lootState.winner == nil) then
            lootState.winner = lootState.rollWinner
            state.selectedAuto = true
        end

        state.lastSortAsc  = wantLow
        state.lastSortType = lootState.currentRollType
    end

    local function onRollButtonClick(self, button)
        -- Selection allowed only after the countdown has finished
        if state.canRoll then
            return
        end

        -- Lock selection while a multi-award sequence is running
        if lootState.multiAward and lootState.multiAward.active then
            addon:warn(Diag.W.ErrMLMultiAwardInProgress)
            return
        end

        local name = self.playerName
        if not name or name == "" then return end

        local itemCount = tonumber(lootState.itemCount) or 1
        if itemCount < 1 then itemCount = 1 end

        local ctrl = IsControlKeyDown()
        local pickMode = (not lootState.fromInventory) -- loot window (single and multi): CTRL-only winner picking

        -- Loot window: CTRL+Click toggles winners; regular click is "focus" (no side-effects).
        if pickMode then
            if not ctrl then
                state.selected = name
                state.selectedAuto = false
                module:FetchRolls()
                return
            end

            local maxSel = itemCount
            local display = state.display
            if display and maxSel > #display then
                maxSel = #display
            end
            if maxSel < 1 then maxSel = 1 end

            local isSel = Utils.multiSelectIsSelected(MS_CTX_ROLLS, name)
            local cur   = Utils.multiSelectCount(MS_CTX_ROLLS) or 0

            -- If capacity is 1, CTRL+Click on another player replaces the current selection (swap).
            if (not isSel) and cur >= maxSel then
                if maxSel == 1 then
                    Utils.multiSelectClear(MS_CTX_ROLLS)
                    Utils.multiSelectToggle(MS_CTX_ROLLS, name, true)
                else
                    addon:warn(Diag.W.ErrMLMultiSelectTooMany:format(maxSel))
                    return
                end
            else
                Utils.multiSelectToggle(MS_CTX_ROLLS, name, true)
            end

            -- Keep lootState.winner aligned with the current selection for single-award flows and UI state.
            local picked = module.GetSelectedWinnersOrdered and module:GetSelectedWinnersOrdered() or {}
            lootState.winner = (picked[1] and picked[1].name) or nil

            state.selected = name
            state.selectedAuto = false

            module:FetchRolls()
            -- NOTE: do not sync per-click in pick mode (avoids RAID/PARTY addon message spam)
            return
        end

        -- Inventory/trade: legacy single selection behavior.
        Utils.multiSelectClear(MS_CTX_ROLLS)

        lootState.winner = name
        state.selected = name
        state.selectedAuto = false

        module:FetchRolls()
        Utils.sync("KRT-RollWinner", name)
    end

    local function addRoll(name, roll, itemId)
        roll = tonumber(roll)
        state.count = state.count + 1
        lootState.rollsCount = lootState.rollsCount + 1

        local entry = {}
        entry.name = name
        entry.roll = roll
        entry.itemId = itemId
        state.rolls[state.count] = entry
        -- Roll entries are released via resetRolls().

        addon:debug(Diag.D.LogRollsAddEntry:format(name, roll, tostring(itemId)))
        if itemId then
            local tracker = AcquireItemTracker(itemId)
            tracker[name] = (tracker[name] or 0) + 1
        end

        Utils.triggerEvent("AddRoll", name, roll)
        sortRolls(itemId)
        requestRollsRefresh()
    end

    local function resetRolls(rec)
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry then
                twipe(entry)
            end
        end
        twipe(state.rolls)
        twipe(state.rerolled)
        twipe(state.playerCounts)
        if delItemCounts then
            delItemCounts(state.itemCounts, true)
        end

        state.rolls = {}
        state.rerolled = {}
        state.playerCounts = {}
        state.itemCounts = newItemCounts and newItemCounts() or {}

        state.count, lootState.rollsCount = 0, 0
        state.selected, state.selectedAuto = nil, false
        state.rolled, state.warned = false, false
        state.lastSortAsc, state.lastSortType = nil, nil

        lootState.winner = nil
        lootState.rollWinner = nil
        lootState.itemTraded = 0
        lootState.rollStarted = false

        -- Clear any manual multi-winner selection (Master Loot window)
        state.msPrefilled = false
        Utils.multiSelectClear(MS_CTX_ROLLS)
        Utils.multiSelectSetAnchor(MS_CTX_ROLLS, nil)

        if rec == false then state.record = false end
    end

    -- ----- Public methods ----- --
    -- Initiates a /roll 1-100 for the player.
    function module:Roll(btn)
        local itemId = self:GetCurrentRollItemID()
        if not itemId then return end

        local name = Utils.getPlayerName()
        local allowed = GetAllowedRolls(itemId, name)

        state.playerCounts[itemId] = state.playerCounts[itemId] or 0
        if state.playerCounts[itemId] >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            addon:debug(Diag.D.LogRollsBlockedPlayer:format(name, state.playerCounts[itemId], allowed))
            return
        end

        RandomRoll(1, 100)
        state.playerCounts[itemId] = state.playerCounts[itemId] + 1
        UpdateLocalRollState(itemId, name)
        addon:debug(Diag.D.LogRollsPlayerRolled:format(name, itemId))
    end

    -- Returns the current roll session state.
    function module:RollStatus()
        local itemId = self:GetCurrentRollItemID()
        local name = Utils.getPlayerName()
        UpdateLocalRollState(itemId, name)
        return lootState.currentRollType, state.record, state.canRoll, state.rolled
    end

    -- Enables or disables the recording of rolls.
    function module:RecordRolls(bool)
        local on      = (bool == true)
        state.canRoll = on
        state.record  = on

        if on then
            state.warned = false

            -- Reset only if we are starting a clean session
            if state.count == 0 then
                state.selected = nil
                state.selectedAuto = true
                lootState.winner = nil
                lootState.rollWinner = nil
            end
        end

        addon:debug(Diag.D.LogRollsRecordState:format(tostring(bool)))
    end

    -- Intercepts system messages to detect player rolls.
    function module:CHAT_MSG_SYSTEM(msg)
        if not msg or not state.record then return end
        local player, roll, min, max = addon.Deformat(msg, RANDOM_ROLL_RESULT)
        if not player or not roll or min ~= 1 or max ~= 100 then return end

        if not state.canRoll then
            if not state.warned then
                addon:Announce(L.ChatCountdownBlock)
                state.warned = true
            end
            addon:debug(Diag.D.LogRollsCountdownBlocked)
            return
        end

        local itemId = self:GetCurrentRollItemID()
        if not itemId or lootState.lootCount == 0 then
            addon:warn(Diag.W.LogRollsMissingItem)
            return
        end

        local allowed = 1
        if lootState.currentRollType == rollTypes.RESERVED then
            local reserves = addon.Reserves:GetReserveCountForItem(itemId, player)
            allowed = reserves > 0 and reserves or 1
        end

        local tracker = AcquireItemTracker(itemId)
        local used = tracker[player] or 0
        if used >= allowed then
            if not tContains(state.rerolled, player) then
                Utils.whisper(player, L.ChatOnlyRollOnce)
                tinsert(state.rerolled, player)
            end
            addon:debug(Diag.D.LogRollsDeniedPlayer:format(player, used, allowed))
            return
        end

        addon:debug(Diag.D.LogRollsAcceptedPlayer:format(player, used + 1, allowed))
        addRoll(player, roll, itemId)
    end

    -- Returns the current table of rolls.
    function module:GetRolls()
        return state.rolls
    end

    -- Sets the flag indicating the player has rolled.
    function module:SetRolled()
        local itemId = self:GetCurrentRollItemID()
        local name = Utils.getPlayerName()
        UpdateLocalRollState(itemId, name)
    end

    -- Checks if a player has already used all their rolls for an item.
    function module:DidRoll(itemId, name)
        if not itemId then
            for i = 1, state.count do
                if state.rolls[i].name == name then return true end
            end
            return false
        end
        local tracker = AcquireItemTracker(itemId)
        local used = tracker[name] or 0
        local reserve = addon.Reserves:GetReserveCountForItem(itemId, name)
        local allowed = (lootState.currentRollType == rollTypes.RESERVED and reserve > 0) and reserve or 1
        return used >= allowed
    end

    -- Returns the highest roll value from the current winner.
    function module:HighestRoll()
        if not lootState.winner then return 0 end

        local winner = lootState.winner
        local wantLow = (addon.options.sortAscending == true)
        local best = nil

        -- Prefer rolls tied to the current session item when available.
        local sessionItemId = self:GetCurrentRollItemID()

        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry and entry.name == winner then
                if (not sessionItemId) or (not entry.itemId) or (entry.itemId == sessionItemId) then
                    if best == nil then
                        best = entry.roll
                    elseif wantLow then
                        if entry.roll < best then best = entry.roll end
                    else
                        if entry.roll > best then best = entry.roll end
                    end
                end
            end
        end

        return best or 0
    end

    -- Clears all roll-related state and UI elements.
    function module:ClearRolls(rec)
        local mf = (addon.Master and addon.Master.frame) or _G["KRTMaster"]
        local frameName = mf and mf:GetName() or nil
        resetRolls(rec)
        if frameName then
            local i, btn = 1, _G[frameName .. "PlayerBtn1"]
            while btn do
                btn:Hide()
                i = i + 1
                btn = _G[frameName .. "PlayerBtn" .. i]
            end
            addon.Raid:ClearRaidIcons()
        end
    end

    -- Gets the item ID of the item currently being rolled for.
    function module:GetCurrentRollItemID()
        local index = GetItemIndex()
        local item = GetItem and GetItem(index)
        local itemLink = item and item.itemLink
        if not itemLink then return nil end
        local itemId = Utils.getItemIdFromLink(itemLink)
        addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(itemId)))
        return itemId
    end

    -- Validates if a player can still roll for an item.
    function module:IsValidRoll(itemId, name)
        local tracker = AcquireItemTracker(itemId)
        local used = tracker[name] or 0
        local allowed = (lootState.currentRollType == rollTypes.RESERVED)
            and addon.Reserves:GetReserveCountForItem(itemId, name)
            or 1
        return used < allowed
    end

    -- Checks if a player has reserved the specified item.
    function module:IsReserved(itemId, name)
        return addon.Reserves:GetReserveCountForItem(itemId, name) > 0
    end

    -- Gets the number of reserves a player has used for an item.
    function module:GetUsedReserveCount(itemId, name)
        local tracker = AcquireItemTracker(itemId)
        return tracker[name] or 0
    end

    -- Gets the total number of reserves a player has for an item.
    function module:GetAllowedReserves(itemId, name)
        return addon.Reserves:GetReserveCountForItem(itemId, name)
    end

    -- Rebuilds the roll list UI and marks the top roller or selected winner.
    function module:FetchRolls()
        local mf = (addon.Master and addon.Master.frame) or _G["KRTMaster"]
        local frameName = mf and mf:GetName() or nil
        if not frameName then return end
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())

        local itemId = self:GetCurrentRollItemID()
        local isSR = lootState.currentRollType == rollTypes.RESERVED

        local plusPriority = isSR and itemId
            and addon.Reserves
            and addon.Reserves.GetPlusForItem
            and addon.Reserves.GetImportMode
            and (addon.Reserves:IsPlusSystem())

        local GetPlus = MakePlusGetter(itemId)

        local wantAsc = addon.options.sortAscending == true
        if state.lastSortAsc ~= wantAsc or state.lastSortType ~= lootState.currentRollType then
            sortRolls(itemId)
        end

        -- Build a compact display list: one row per player.
        -- If the player rolled multiple times (multi-reserve), keep only the best roll according to sort order.
        local wantLow = wantAsc
        local bestByName = {}
        local display = {}
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry then
                local name, roll = entry.name, entry.roll
                local best = bestByName[name]
                if not best then
                    best = { name = name, roll = roll }
                    bestByName[name] = best
                    display[#display + 1] = best
                else
                    if wantLow then
                        if roll < best.roll then best.roll = roll end
                    else
                        if roll > best.roll then best.roll = roll end
                    end
                end
            end
        end

        table.sort(display, function(a, b)
            -- SR: reserved first (session itemId)
            if isSR and itemId then
                local ar = module:IsReserved(itemId, a.name)
                local br = module:IsReserved(itemId, b.name)
                if ar ~= br then
                    return ar
                end

                -- SR + Plus priority (only when no multi-reserve exists for this item)
                if plusPriority and ar and br then
                    local ap = GetPlus(a.name)
                    local bp = GetPlus(b.name)
                    if ap ~= bp then
                        return ap > bp
                    end
                end
            end

            if a.roll ~= b.roll then
                return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
            end

            return tostring(a.name) < tostring(b.name)
        end)

        -- Cache current display order (used for manual multi-winner selection / shift-range).
        state.display = display
        state.displayNames = {}
        for i = 1, #display do
            local e = display[i]
            state.displayNames[i] = e and e.name or nil
        end

        -- Inventory/trade: keep legacy single-selection behavior.
        -- In loot window (pick mode) we support the same MultiSelect flow for both single and multi-copy items.
        if lootState.fromInventory then
            Utils.multiSelectClear(MS_CTX_ROLLS)
            Utils.multiSelectSetAnchor(MS_CTX_ROLLS, nil)
            state.msPrefilled = false
        end

        -- Top roll for UI star (compact list).
        local starTarget = display[1] and display[1].name or lootState.rollWinner

        -- Fallback (if for some reason it has not been set yet)
        if not starTarget then
            if isSR then
                local bestName = PickBestReserved(itemId)
                starTarget = bestName or lootState.winner
            else
                starTarget = lootState.winner
            end
        end

        local ma = lootState.multiAward
        local selectionAllowed = (state.canRoll == false) and not (ma and ma.active)
        local pickName = selectionAllowed and lootState.winner or nil

        -- highlight: durante CD = top roll; post-CD = pick (se esiste) altrimenti top roll
        local highlightTarget = selectionAllowed and (pickName or starTarget) or starTarget
        local available = tonumber(addon.Loot:GetCurrentItemCount()) or 1
        if available < 1 then available = 1 end
        local pickMode = selectionAllowed and (not lootState.fromInventory)

        -- Prefill MultiSelect with top-N winners (Top-N = ItemCount) in pick mode.
        -- This keeps the UI identical for single- and multi-copy loot: the addon always starts with an auto-selection.
        if pickMode then
            local n = tonumber(lootState.itemCount) or 1
            if n and n >= 1 and #display > 0 then
                if n > #display then n = #display end
                if (not state.msPrefilled) and (Utils.multiSelectCount(MS_CTX_ROLLS) or 0) == 0 then
                    for i = 1, n do
                        local e = display[i]
                        if e and e.name then
                            Utils.multiSelectToggle(MS_CTX_ROLLS, e.name, true)
                        end
                    end
                end
                state.msPrefilled = true
            end
        end

        local msCount = pickMode and (Utils.multiSelectCount(MS_CTX_ROLLS) or 0) or 0
        if msCount > 0 then
            -- In pick mode, persistent background highlight comes from MultiSelect.
            highlightTarget = nil
        end

        -- Star is a pure "top roll" indicator (UI hint), independent from manual MultiSelect winners.
        local starWinners = {}
        do
            local n = tonumber(lootState.itemCount) or 1
            if n < 1 then n = 1 end

            if display and #display > 0 then
                if n > #display then n = #display end
                for i = 1, n do
                    local e = display[i]
                    if e and e.name then
                        starWinners[e.name] = true
                    end
                end
            elseif starTarget then
                -- Fallback: keep at least the best known target.
                starWinners[starTarget] = true
            end
        end

        local starShown, totalHeight = false, 0
        for i = 1, #display do
            local entry = display[i]
            local name, roll = entry.name, entry.roll
            local btnName = frameName .. "PlayerBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")

            btn:SetID(i)
            btn:Show()
            btn.playerName = name

            -- enable click only after the countdown has finished
            btn:EnableMouse(selectionAllowed)

            Utils.ensureRowVisuals(btn)

            local nameStr, rollStr, counterStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"],
                _G[btnName .. "Counter"], _G[btnName .. "Star"]

            if nameStr and nameStr.SetVertexColor then
                local class = addon.Raid:GetPlayerClass(name)
                class = class and class:upper() or "UNKNOWN"
                if isSR and itemId and self:IsReserved(itemId, name) then
                    nameStr:SetVertexColor(0.4, 0.6, 1.0)
                else
                    local r, g, b = Utils.getClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
            end

            -- Pick mode: show current winners (MultiSelect) with > < (single and multi-copy loot).
            if pickMode and (msCount > 0) and Utils.multiSelectIsSelected(MS_CTX_ROLLS, name) then
                nameStr:SetText("> " .. name .. " <")
            else
                nameStr:SetText(name)
            end

            local isFocus = (highlightTarget and highlightTarget == name)
            local isSelected = (msCount > 0 and Utils.multiSelectIsSelected(MS_CTX_ROLLS, name))

            Utils.setRowSelected(btn, isSelected)
            Utils.setRowFocused(btn, isFocus)

            -- Roll value always in its own column
            if rollStr then
                rollStr:SetText(tostring(roll))
            end

            -- SR roll counter: show only (used/allowed) on the single compact row
            -- Optional: during MS rolls, show the player's positive MS loot count in the same column ("+N"), if enabled in config.
            if counterStr then
                if isSR and itemId and self:IsReserved(itemId, name) then
                    -- SR + Plus priority (only when no multi-reserve exists for this item)
                    if plusPriority then
                        local p = GetPlus(name)
                        if p and p > 0 then
                            counterStr:SetText(format("(P+%d)", p))
                        else
                            counterStr:SetText("")
                        end
                    else
                        local allowed = self:GetAllowedReserves(itemId, name)
                        if allowed and allowed > 1 then
                            local used = self:GetUsedReserveCount(itemId, name)
                            counterStr:SetText(format("(%d/%d)", used or 0, allowed))
                        else
                            counterStr:SetText("")
                        end
                    end
                else
                    if addon.options.showLootCounterDuringMSRoll == true
                        and lootState.currentRollType == rollTypes.MAINSPEC
                    then
                        local c = addon.Raid:GetPlayerCount(name, KRT_CurrentRaid) or 0
                        if c > 0 then
                            counterStr:SetText("+" .. c)
                        else
                            counterStr:SetText("")
                        end
                    else
                        counterStr:SetText("")
                    end
                end
            end

            local showStar
            if starWinners then
                showStar = (starWinners[name] == true)
            else
                -- Default: star marks only the top roll (compact list)
                showStar = (not starShown) and (starTarget ~= nil) and (name == starTarget)
            end
            Utils.showHide(star, showStar)
            if (not starWinners) and showStar then starShown = true end

            if not btn.krtHasOnClick then
                btn:SetScript("OnClick", onRollButtonClick)
                btn.krtHasOnClick = true
            end

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end

        -- Hide leftover buttons from previous renders.
        local j = #display + 1
        local btn = _G[frameName .. "PlayerBtn" .. j]
        while btn do
            btn:Hide()
            j = j + 1
            btn = _G[frameName .. "PlayerBtn" .. j]
        end

        if addon.Master and addon.Master.RequestRefresh then
            addon.Master:RequestRefresh()
        end
    end

    -- Returns selected winners (manual multi-pick) in current display order.
    -- Each entry is { name = <string>, roll = <number> }.
    function module:GetSelectedWinnersOrdered()
        local selected = {}
        local display = state.display
        if not display or #display == 0 then
            return selected
        end
        for i = 1, #display do
            local e = display[i]
            if e and e.name and Utils.multiSelectIsSelected(MS_CTX_ROLLS, e.name) then
                selected[#selected + 1] = { name = e.name, roll = tonumber(e.roll) or 0 }
            end
        end
        return selected
    end

    Utils.registerCallback("ConfigsortAscending", function(_, value)
        addon.Rolls:FetchRolls()
    end)
end






