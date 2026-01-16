local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local rollTypes = C.rollTypes
addon.State = addon.State or {}
local coreState = addon.State
coreState.loot = coreState.loot or {}
local lootState = coreState.loot

-- Rolls Helpers Module
-- Manages roll tracking, sorting, and winner determination.
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Rolls = addon.Rolls or {}
    local module = addon.Rolls
    local L = addon.L

    -------------------------------------------------------
    -- 2. Internal state
    -------------------------------------------------------
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
    }
    local newItemCounts, delItemCounts = addon.TablePool and addon.TablePool("k")
    state.itemCounts = newItemCounts and newItemCounts() or {}

    -------------------------------------------------------
    -- 3. Private helpers
    -------------------------------------------------------
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
        local bestName, bestRoll = nil, nil
        local wantLow = addon.options.sortAscending == true

        for _, entry in ipairs(state.rolls) do
            if module:IsReserved(itemId, entry.name) then
                if not bestName then
                    bestName, bestRoll = entry.name, entry.roll
                elseif wantLow then
                    if entry.roll < bestRoll then
                        bestName, bestRoll = entry.name, entry.roll
                    end
                else
                    if entry.roll > bestRoll then
                        bestName, bestRoll = entry.name, entry.roll
                    end
                end
            end
        end

        return bestName, bestRoll
    end

    -- Returns the "real" winner for UI (top roll, with SR priority if active).
    local function GetEffectiveWinner(itemId)
        if lootState.currentRollType == rollTypes.RESERVED then
            return PickBestReserved(itemId) or lootState.winner
        end
        return lootState.winner
    end

    -- Sorts rolls table + updates lootState.winner (top entry after sort).
    local function sortRolls(itemId)
        local rolls = state.rolls
        if #rolls == 0 then
            lootState.winner = nil
            lootState.rollWinner = nil
            addon:debug("Rolls: sort no entries.")
            return
        end

        local isSR    = (lootState.currentRollType == rollTypes.RESERVED)
        local wantLow = (addon.options.sortAscending == true)

        table.sort(rolls, function(a, b)
            -- SR: reserved first (session itemId)
            if isSR and itemId then
                local ar = module:IsReserved(itemId, a.name)
                local br = module:IsReserved(itemId, b.name)
                if ar ~= br then
                    return ar -- true first
                end
            end

            if a.roll ~= b.roll then
                return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
            end

            -- tie-breaker stabile
            return tostring(a.name) < tostring(b.name)
        end)

        -- ⭐ top roll (segue SEMPRE Asc/Desc)
        lootState.rollWinner = rolls[1].name

        -- award target segue top roll solo se non è manuale
        if state.canRoll or state.selectedAuto or (lootState.winner == nil) then
            lootState.winner = lootState.rollWinner
            state.selectedAuto = true
        end

        state.lastSortAsc  = wantLow
        state.lastSortType = lootState.currentRollType
    end

    local function onRollButtonClick(self)
        -- ✅ Selezione SOLO a countdown finito
        if state.canRoll then
            return
        end

        local name = self.playerName
        if not name or name == "" then return end

        -- ✅ award target = selezione manuale
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

        addon:debug("Rolls: add name=%s roll=%d item=%s.", name, roll, tostring(itemId))
        if itemId then
            local tracker = AcquireItemTracker(itemId)
            tracker[name] = (tracker[name] or 0) + 1
        end

        Utils.triggerEvent("AddRoll", name, roll)
        sortRolls(itemId)
        module:FetchRolls()
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

        if rec == false then state.record = false end
    end

    -------------------------------------------------------
    -- 4. Public methods
    -------------------------------------------------------
    -- Initiates a /roll 1-100 for the player.
    function module:Roll(btn)
        local itemId = self:GetCurrentRollItemID()
        if not itemId then return end

        local name = Utils.getPlayerName()
        local allowed = 1
        if lootState.currentRollType == rollTypes.RESERVED then
            local reserve = addon.Reserves:GetReserveCountForItem(itemId, name)
            allowed = (reserve > 0) and reserve or 1
        end

        state.playerCounts[itemId] = state.playerCounts[itemId] or 0
        if state.playerCounts[itemId] >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            addon:debug("Rolls: blocked player=%s (%d/%d).", name, state.playerCounts[itemId], allowed)
            return
        end

        RandomRoll(1, 100)
        state.rolled = true
        state.playerCounts[itemId] = state.playerCounts[itemId] + 1
        addon:debug("Rolls: player=%s item=%d.", name, itemId)
    end

    -- Returns the current roll session state.
    function module:RollStatus()
        return lootState.currentRollType, state.record, state.canRoll, state.rolled
    end

    -- Enables or disables the recording of rolls.
    function module:RecordRolls(bool)
        local on      = (bool == true)
        state.canRoll = on
        state.record  = on

        if on then
            state.warned = false

            -- reset SOLO se stiamo iniziando una sessione “pulita”
            if state.count == 0 then
                state.selected = nil
                state.selectedAuto = true
                lootState.winner = nil
                lootState.rollWinner = nil
            end
        end

        addon:debug("Rolls: record=%s.", tostring(bool))
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
            addon:debug("Rolls: blocked countdown active.")
            return
        end

        local itemId = self:GetCurrentRollItemID()
        if not itemId or lootState.lootCount == 0 then
            addon:error("Item ID missing or loot table not ready – roll ignored.")
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
            addon:debug("Rolls: denied player=%s (%d/%d).", player, used, allowed)
            return
        end

        addon:debug("Rolls: accepted player=%s (%d/%d).", player, used + 1, allowed)
        addRoll(player, roll, itemId)
    end

    -- Returns the current table of rolls.
    function module:GetRolls()
        return state.rolls
    end

    -- Sets the flag indicating the player has rolled.
    function module:SetRolled()
        state.rolled = true
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
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry.name == lootState.winner then return entry.roll end
        end
        return 0
    end

    -- Clears all roll-related state and UI elements.
    function module:ClearRolls(rec)
        local frameName = Utils.getFrameName()
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
        local index = addon.Loot:GetItemIndex()
        local item = addon.Loot and addon.Loot:GetItem(index)
        local itemLink = item and item.itemLink
        if not itemLink then return nil end
        local itemId = Utils.getItemIdFromLink(itemLink)
        addon:debug("Rolls: current itemId=%s.", tostring(itemId))
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
        local frameName = Utils.getFrameName()
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())

        local itemId = self:GetCurrentRollItemID()
        local isSR = lootState.currentRollType == rollTypes.RESERVED

        local wantAsc = addon.options.sortAscending == true
        if state.lastSortAsc ~= wantAsc or state.lastSortType ~= lootState.currentRollType then
            sortRolls(itemId)
        end

        -- top roll
        local starTarget = lootState.rollWinner

        -- fallback (se per qualche motivo non è ancora valorizzato)
        if not starTarget then
            if isSR then
                local bestName = PickBestReserved(itemId)
                starTarget = bestName or lootState.winner
            else
                starTarget = lootState.winner
            end
        end

        local selectionAllowed = (state.canRoll == false)
        local pickName = selectionAllowed and lootState.winner or nil

        -- highlight: durante CD = top roll; post-CD = pick (se esiste) altrimenti top roll
        local highlightTarget = selectionAllowed and (pickName or starTarget) or starTarget

        local starShown, totalHeight = false, 0
        for i = 1, state.count do
            local entry = state.rolls[i]
            local name, roll = entry.name, entry.roll
            local btnName = frameName .. "PlayerBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")

            btn:SetID(i)
            btn:Show()
            btn.playerName = name

            -- click solo post-CD
            btn:EnableMouse(selectionAllowed)

            if not btn.selectedBackground then
                btn.selectedBackground = btn:CreateTexture("KRTSelectedHighlight", "ARTWORK")
                btn.selectedBackground:SetAllPoints()
                btn.selectedBackground:SetTexture(1, 0.8, 0, 0.1)
                btn.selectedBackground:Hide()
            end

            local nameStr, rollStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"], _G[btnName .. "Star"]

            if nameStr and nameStr.SetVertexColor then
                local class = addon.Raid:GetPlayerClass(name)
                class = class and class:upper() or "UNKNOWN"
                if isSR and self:IsReserved(itemId, name) then
                    nameStr:SetVertexColor(0.4, 0.6, 1.0)
                else
                    local r, g, b = Utils.getClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
            end

            -- > < SOLO se manuale (cioè: post-CD e selectedAuto=false)
            if selectionAllowed and (state.selectedAuto == false) and pickName and pickName == name then
                nameStr:SetText("> " .. name .. " <")
            else
                nameStr:SetText(name)
            end

            if highlightTarget and highlightTarget == name then
                btn.selectedBackground:Show()
            else
                btn.selectedBackground:Hide()
            end

            if isSR and self:IsReserved(itemId, name) then
                local count = self:GetAllowedReserves(itemId, name)
                local used = self:GetUsedReserveCount(itemId, name)
                rollStr:SetText(count > 1 and format("%d (%d/%d)", roll, used, count) or tostring(roll))
            else
                rollStr:SetText(roll)
            end

            -- ⭐ STAR sempre top roll (rollWinner)
            local showStar = (not starShown) and (starTarget ~= nil) and (name == starTarget)
            Utils.showHide(star, showStar)
            if showStar then starShown = true end

            if not btn.krtHasOnClick then
                btn:SetScript("OnClick", onRollButtonClick)
                btn.krtHasOnClick = true
            end

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
    end

    Utils.registerCallback("ConfigsortAscending", function(_, value)
        addon.Rolls:FetchRolls()
    end)
end
