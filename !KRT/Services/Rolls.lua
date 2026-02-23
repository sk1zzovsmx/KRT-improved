-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local Events = feature.Events or addon.Events or {}

local tContains = feature.tContains

local rollTypes = feature.rollTypes

local lootState = feature.lootState

local InternalEvents = Events.Internal

local GetItem

local GetItemIndex = feature.GetItemIndex

local tinsert, twipe = table.insert, table.wipe
local ipairs = ipairs
local format = string.format

local tostring, tonumber = tostring, tonumber

local function getLootModule()
    return addon.Loot
end

local function getReservesService()
    local services = addon.Services
    return services and services.Reserves or nil
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
-- Manages roll tracking, sorting, and winner determination.
do
    addon.Services = addon.Services or {}
    addon.Services.Rolls = addon.Services.Rolls or addon.Rolls or {}
    addon.Rolls = addon.Services.Rolls -- Legacy alias during namespacing migration.
    local module = addon.Services.Rolls
    -- Multi-selection context for manual multi-award winner picking (Master Loot window)
    local MS_CTX_ROLLS = "MLRollWinners"

    -- ----- Internal state ----- --
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

    -- ----- Private helpers ----- --
    local function GetAllowedRolls(itemId, name)
        if not itemId or not name then return 1 end
        if lootState.currentRollType ~= rollTypes.RESERVED then
            return 1
        end
        local reserves = getReserveCountForItem(itemId, name)
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
        local usePlus = isPlusSystemEnabled()

        for _, entry in ipairs(state.rolls) do
            if module:IsReserved(itemId, entry.name) then
                local roll = entry.roll
                local plus = usePlus and getPlusForItem(itemId, entry.name) or 0

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
                v = getPlusForItem(itemId, name)
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

        local plusPriority = isSR and itemId and isPlusSystemEnabled()

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

    local function selectWinner(name, isShift, isControl)
        -- Selection allowed only after the countdown has finished.
        if state.canRoll then
            return false
        end

        -- Lock selection while a multi-award sequence is running.
        if lootState.multiAward and lootState.multiAward.active then
            addon:warn(Diag.W.ErrMLMultiAwardInProgress)
            return false
        end

        if not name or name == "" then
            return false
        end

        local itemCount = tonumber(lootState.itemCount) or 1
        if itemCount < 1 then itemCount = 1 end

        local ctrl = (isControl == true)
        local shift = (isShift == true)
        local pickMode = (not lootState.fromInventory)

        -- Loot window: CTRL toggles winners; plain click only focuses a row.
        if pickMode then
            if not ctrl then
                state.selected = name
                state.selectedAuto = false
                module:FetchRolls()
                return true
            end

            local maxSel = itemCount
            local display = state.display
            if display and maxSel > #display then
                maxSel = #display
            end
            if maxSel < 1 then maxSel = 1 end

            local isSel = Utils.multiSelectIsSelected(MS_CTX_ROLLS, name)
            local cur = Utils.multiSelectCount(MS_CTX_ROLLS) or 0
            if (not isSel) and cur >= maxSel then
                if maxSel == 1 then
                    Utils.multiSelectClear(MS_CTX_ROLLS)
                    Utils.multiSelectToggle(MS_CTX_ROLLS, name, true)
                else
                    addon:warn(Diag.W.ErrMLMultiSelectTooMany:format(maxSel))
                    return false
                end
            else
                Utils.multiSelectToggle(MS_CTX_ROLLS, name, true)
            end

            if shift then
                Utils.multiSelectSetAnchor(MS_CTX_ROLLS, name)
            end

            local picked = module:GetSelectedWinnersOrdered()
            lootState.winner = (picked[1] and picked[1].name) or nil
            state.selected = name
            state.selectedAuto = false

            module:FetchRolls()
            return true
        end

        -- Inventory/trade: legacy single selection behavior.
        Utils.multiSelectClear(MS_CTX_ROLLS)
        lootState.winner = name
        state.selected = name
        state.selectedAuto = false

        module:FetchRolls()
        Utils.sync("KRT-RollWinner", name)
        return true
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

        Utils.triggerEvent(InternalEvents.AddRoll, name, roll)
        sortRolls(itemId)
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

    function module:SelectWinner(name, isShift, isControl)
        return selectWinner(name, isShift, isControl)
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
            local reserves = getReserveCountForItem(itemId, player)
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
        local reserve = getReserveCountForItem(itemId, name)
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

    -- Clears all roll-related state.
    function module:ClearRolls(rec)
        resetRolls(rec)
        state.display = nil
        state.displayNames = nil
        state.lastModel = nil
        addon.Raid:ClearRaidIcons()
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
            and getReserveCountForItem(itemId, name)
            or 1
        return used < allowed
    end

    -- Checks if a player has reserved the specified item.
    function module:IsReserved(itemId, name)
        return getReserveCountForItem(itemId, name) > 0
    end

    -- Gets the number of reserves a player has used for an item.
    function module:GetUsedReserveCount(itemId, name)
        local tracker = AcquireItemTracker(itemId)
        return tracker[name] or 0
    end

    -- Gets the total number of reserves a player has for an item.
    function module:GetAllowedReserves(itemId, name)
        return getReserveCountForItem(itemId, name)
    end

    -- Rebuilds the roll model consumed by Master UI.
    function module:FetchRolls()
        local itemId = self:GetCurrentRollItemID()
        local isSR = lootState.currentRollType == rollTypes.RESERVED

        local plusPriority = isSR and itemId and isPlusSystemEnabled()

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

        local rows = {}
        for i = 1, #display do
            local entry = display[i]
            local name, roll = entry.name, entry.roll
            local isReserved = isSR and itemId and self:IsReserved(itemId, name)
            local isSelected = (msCount > 0 and Utils.multiSelectIsSelected(MS_CTX_ROLLS, name))
            local isFocused = (highlightTarget and highlightTarget == name) or false
            local counterText = ""

            if isReserved then
                if plusPriority then
                    local p = GetPlus(name)
                    if p and p > 0 then
                        counterText = format("(P+%d)", p)
                    end
                else
                    local allowed = self:GetAllowedReserves(itemId, name)
                    if allowed and allowed > 1 then
                        local used = self:GetUsedReserveCount(itemId, name)
                        counterText = format("(%d/%d)", used or 0, allowed)
                    end
                end
            elseif addon.options.showLootCounterDuringMSRoll == true
                and lootState.currentRollType == rollTypes.MAINSPEC
            then
                local c = addon.Raid:GetPlayerCount(name, addon.Core.getCurrentRaid()) or 0
                if c > 0 then
                    counterText = "+" .. c
                end
            end

            rows[i] = {
                id = i,
                name = name,
                displayName = (pickMode and msCount > 0 and isSelected) and ("> " .. name .. " <") or name,
                roll = roll,
                class = (addon.Raid:GetPlayerClass(name) or "UNKNOWN"):upper(),
                isReserved = isReserved and true or false,
                isSelected = isSelected and true or false,
                isFocused = isFocused and true or false,
                showStar = (starWinners and starWinners[name]) and true or false,
                canClick = selectionAllowed and true or false,
                counterText = counterText,
            }
        end

        state.lastModel = {
            itemId = itemId,
            isSR = isSR and true or false,
            rows = rows,
            selectionAllowed = selectionAllowed and true or false,
            pickMode = pickMode and true or false,
            msCount = msCount,
            highlightTarget = highlightTarget,
            winner = lootState.winner,
            rollWinner = lootState.rollWinner,
        }
        return state.lastModel
    end

    function module:GetDisplayModel()
        return module:FetchRolls()
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

end
