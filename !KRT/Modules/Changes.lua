local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper

-- MS Changes Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Changes = addon.Changes or {}
    local module = addon.Changes
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_CHANGES

    local changesTable = {}
    local FetchChanges, SaveChanges, CancelChanges
    local fetched = false
    local changesDirty = false
    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode
    local lastAddBtnMode
    local isAdd = false
    local isEdit = false

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIChanges = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:HookScript("OnShow", function()
            changesDirty = true
            lastSelectedID = false
        end)
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Toggle frame visibility:
    function module:Toggle()
        CancelChanges()
        Utils.toggle(UIChanges)
    end

    -- Hide frame:
    function module:Hide()
        Utils.hideFrame(UIChanges, CancelChanges)
    end

    -- Clear module:
    function module:Clear()
        if not KRT_CurrentRaid or changesTable == nil then return end
        for n, p in pairs(changesTable) do
            changesTable[n] = nil
            if _G[frameName .. "PlayerBtn" .. n] then
                _G[frameName .. "PlayerBtn" .. n]:Hide()
            end
        end
        CancelChanges()
        fetched = false
        changesDirty = true
    end

    -- Selecting Player:
    function module:Select(btn)
        -- No selection.
        if not btn then return end
        local btnName = btn:GetName()
        local name = _G[btnName .. "Name"]:GetText()
        -- No ID set.
        if not name then return end
        -- Make sure the player exists in the raid:
        local found = true
        if not addon.Raid:CheckPlayer(name) then found = false end
        if not changesTable[name] then found = false end
        if not found then
            if _G[frameName .. "PlayerBtn" .. name] then
                _G[frameName .. "PlayerBtn" .. name]:Hide()
            end
            fetched = false
            changesDirty = true
            return
        end
        -- Quick announce?
        if IsControlKeyDown() then
            tempSelectedID = (name ~= selectedID) and name or nil
            self:Announce()
            return
        end
        -- Selection:
        selectedID = (name ~= selectedID) and name or nil
        isAdd = false
        isEdit = false
    end

    -- Add / Delete:
    function module:Add(btn)
        if not KRT_CurrentRaid or not btn then return end
        if not selectedID then
            btn:Hide()
            _G[frameName .. "Name"]:Show()
            _G[frameName .. "Name"]:SetFocus()
            isAdd = true
        elseif changesTable[selectedID] then
            changesTable[selectedID] = nil
            if _G[frameName .. "PlayerBtn" .. selectedID] then
                _G[frameName .. "PlayerBtn" .. selectedID]:Hide()
            end
            CancelChanges()
            fetched = false
            changesDirty = true
        end
    end

    -- Edit / Save
    function module:Edit()
        if not KRT_CurrentRaid then return end
        if not selectedID or isEdit then
            local name = _G[frameName .. "Name"]:GetText()
            local spec = _G[frameName .. "Spec"]:GetText()
            SaveChanges(name, spec)
        elseif changesTable[selectedID] then
            _G[frameName .. "Name"]:SetText(selectedID)
            _G[frameName .. "Spec"]:SetText(changesTable[selectedID])
            _G[frameName .. "Spec"]:Show()
            _G[frameName .. "Spec"]:SetFocus()
            isAdd = false
            isEdit = true
        end
    end

    -- Remove player's change:
    function module:Delete(name)
        if not KRT_CurrentRaid or not name then return end
        KRT_Raids[KRT_CurrentRaid].changes[name] = nil
        if _G[frameName .. "PlayerBtn" .. name] then
            _G[frameName .. "PlayerBtn" .. name]:Hide()
        end
        changesDirty = true
    end

    Utils.registerCallback("RaidLeave", function(e, name)
        module:Delete(name)
        CancelChanges()
    end)

    -- Ask For module:
    function module:Demand()
        if not KRT_CurrentRaid then return end
        addon:Announce(L.StrChangesDemand)
    end

    -- Spam module:
    function module:Announce()
        if not KRT_CurrentRaid then return end
        -- In case of a reload/relog and the frame wasn't loaded
        if not fetched or #changesTable == 0 then
            InitChangesTable()
        end
        local count = addon.tLength(changesTable)
        local msg
        if count == 0 then
            if tempSelectedID then
                tempSelectedID = nil
                return
            end
            msg = L.StrChangesAnnounceNone
        elseif selectedID or tempSelectedID then
            local name = tempSelectedID and tempSelectedID or selectedID
            if tempSelectedID ~= nil then tempSelectedID = nil end
            if not changesTable[name] then return end
            msg = format(L.StrChangesAnnounceOne, name, changesTable[name])
        else
            msg = L.StrChangesAnnounce
            local i = count
            for n, c in pairs(changesTable) do
                msg = msg .. " " .. n .. "=" .. c
                i = i - 1
                if i > 0 then msg = msg .. " /" end
            end
        end
        addon:Announce(msg)
    end

    -- Localize UI Frame:
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
            _G[frameName .. "AddBtn"]:SetText(ADD)
            _G[frameName .. "EditBtn"]:SetText(L.BtnEdit)
            _G[frameName .. "DemandBtn"]:SetText(L.BtnDemand)
            _G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
        end
        Utils.setFrameTitle(frameName, L.StrChanges)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Spec"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Spec"]:SetScript("OnEscapePressed", CancelChanges)
        localized = true
    end

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
            if changesDirty or not fetched then
                InitChangesTable()
                FetchChanges()
                changesDirty = false
            end
            local count = addon.tLength(changesTable)
            if count > 0 then
            else
                tempSelectedID = nil
                selectedID = nil
            end
            if selectedID ~= lastSelectedID then
                if lastSelectedID and _G[frameName .. "PlayerBtn" .. lastSelectedID] then
                    _G[frameName .. "PlayerBtn" .. lastSelectedID]:UnlockHighlight()
                end
                if selectedID and _G[frameName .. "PlayerBtn" .. selectedID] then
                    _G[frameName .. "PlayerBtn" .. selectedID]:LockHighlight()
                end
                lastSelectedID = selectedID
            end
            Utils.showHide(_G[frameName .. "Name"], (isEdit or isAdd))
            Utils.showHide(_G[frameName .. "Spec"], (isEdit or isAdd))
            Utils.enableDisable(_G[frameName .. "EditBtn"], (selectedID or isEdit or isAdd))
            local editBtnMode = isAdd or (selectedID and isEdit)
            if editBtnMode ~= lastEditBtnMode then
                Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, editBtnMode)
                lastEditBtnMode = editBtnMode
            end
            local addBtnMode = (not selectedID and not isEdit and not isAdd)
            if addBtnMode ~= lastAddBtnMode then
                Utils.setText(_G[frameName .. "AddBtn"], ADD, DELETE, addBtnMode)
                lastAddBtnMode = addBtnMode
            end
            Utils.showHide(_G[frameName .. "AddBtn"], (not isEdit and not isAdd))
            Utils.enableDisable(_G[frameName .. "ClearBtn"], count > 0)
            Utils.enableDisable(_G[frameName .. "AnnounceBtn"], count > 0)
            Utils.enableDisable(_G[frameName .. "AddBtn"], KRT_CurrentRaid)
            Utils.enableDisable(_G[frameName .. "DemandBtn"], KRT_CurrentRaid)
        end)
    end

    -- Initialize changes table:
    function InitChangesTable()
        addon:debug("Changes: init table.")
        changesTable = KRT_CurrentRaid and KRT_Raids[KRT_CurrentRaid].changes or {}
    end

    -- Fetch All module:
    function FetchChanges()
        addon:debug("Changes: fetch all.")
        if not KRT_CurrentRaid then return end
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        local totalHeight = 0
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())
        for n, c in pairs(changesTable) do
            local btnName = frameName .. "PlayerBtn" .. n
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTChangesButtonTemplate")
            btn:Show()
            local name = _G[btnName .. "Name"]
            name:SetText(n)
            local class = addon.Raid:GetPlayerClass(n)
            local r, g, b = Utils.getClassColor(class)
            name:SetVertexColor(r, g, b)
            _G[btnName .. "Spec"]:SetText(c)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
        fetched = true
        lastSelectedID = false
    end

    -- Save module:
    function SaveChanges(name, spec)
        if not KRT_CurrentRaid or not name then return end
        name = Utils.normalizeName(name)
        spec = Utils.normalizeName(spec)
        -- Is the player in the raid?
        local found
        found, name = addon.Raid:CheckPlayer(name)
        if not found then
            addon:error(format((name == "" and L.ErrChangesNoPlayer or L.ErrCannotFindPlayer), name))
            return
        end
        changesTable[name] = (spec == "") and nil or spec
        CancelChanges()
        fetched = false
        changesDirty = true
    end

    -- Cancel all actions:
    function CancelChanges()
        isAdd = false
        isEdit = false
        selectedID = nil
        tempSelectedID = nil
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Spec"])
    end
end

