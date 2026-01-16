local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper

---============================================================================
-- Warnings Frame Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Warnings = addon.Warnings or {}
    local module = addon.Warnings
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_WARNINGS

    local FetchWarnings
    local fetched = false
    local warningsDirty = false

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local SaveWarning
    local isEdit = false

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIWarnings = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:HookScript("OnShow", function()
            warningsDirty = true
            lastSelectedID = false
        end)
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Externally update frame:
    function module:Update()
        warningsDirty = true
    end

    -- Toggle frame visibility:
    function module:Toggle()
        Utils.toggle(UIWarnings)
    end

    -- Hide frame:
    function module:Hide()
        Utils.hideFrame(UIWarnings)
    end

    -- Warning selection:
    function module:Select(btn)
        if btn == nil or isEdit == true then return end
        local bName = btn:GetName()
        local wID = tonumber(_G[bName .. "ID"]:GetText())
        if KRT_Warnings[wID] == nil then return end
        if IsControlKeyDown() then
            selectedID = nil
            tempSelectedID = wID
            return self:Announce(tempSelectedID)
        end
        selectedID = (wID ~= selectedID) and wID or nil
    end

    -- Edit/Save warning:
    function module:Edit()
        local wName, wContent
        if selectedID ~= nil then
            local w = KRT_Warnings[selectedID]
            if w == nil then
                selectedID = nil
                return
            end
            if not isEdit and (tempName == "" and tempContent == "") then
                _G[frameName .. "Name"]:SetText(w.name)
                _G[frameName .. "Name"]:SetFocus()
                _G[frameName .. "Content"]:SetText(w.content)
                isEdit = true
                return
            end
        end
        wName    = _G[frameName .. "Name"]:GetText()
        wContent = _G[frameName .. "Content"]:GetText()
        return SaveWarning(wContent, wName, selectedID)
    end

    -- Delete Warning:
    function module:Delete(btn)
        if btn == nil or selectedID == nil then return end
        local oldWarnings = {}
        for i, w in ipairs(KRT_Warnings) do
            _G[frameName .. "WarningBtn" .. i]:Hide()
            if i ~= selectedID then
                tinsert(oldWarnings, w)
            end
        end
        twipe(KRT_Warnings)
        KRT_Warnings = oldWarnings
        local count = #KRT_Warnings
        if count <= 0 then
            selectedID = nil
        elseif count == 1 then
            selectedID = 1
        elseif selectedID > count then
            selectedID = selectedID - 1
        end
        warningsDirty = true
    end

    -- Announce Warning:
    function module:Announce(wID)
        if KRT_Warnings == nil then return end
        if wID == nil then
            wID = (selectedID ~= nil) and selectedID or tempSelectedID
        end
        if wID <= 0 or KRT_Warnings[wID] == nil then return end
        tempSelectedID = nil -- Always clear temporary selected id:
        return addon:Announce(KRT_Warnings[wID].content)
    end

    -- Cancel editing/adding:
    function module:Cancel()
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Content"])
        selectedID = nil
        tempSelectedID = nil
        isEdit = false
    end

    -- Localizing UI frame:
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            Utils.setTextByName(frameName, "MessageStr", L.StrMessage)
            Utils.setTextByName(frameName, "EditBtn", SAVE)
            Utils.setTextByName(frameName, "OutputName", L.StrWarningsHelpTitle)
        end
        Utils.setFrameTitle(frameName, RAID_WARNING)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Content"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Content"]:SetScript("OnEnterPressed", module.Edit)
        localized = true
    end

    local function UpdateSelectionUI()
        if lastSelectedID and _G[frameName .. "WarningBtn" .. lastSelectedID] then
            _G[frameName .. "WarningBtn" .. lastSelectedID]:UnlockHighlight()
        end
        if selectedID and KRT_Warnings[selectedID] then
            local btn = _G[frameName .. "WarningBtn" .. selectedID]
            if btn then
                btn:LockHighlight()
            end
            Utils.setTextByName(frameName, "OutputName", KRT_Warnings[selectedID].name)
            Utils.setTextByName(frameName, "OutputContent", KRT_Warnings[selectedID].content)
            Utils.setTextColor(_G[frameName .. "OutputContent"], 1, 1, 1)
        else
            Utils.setTextByName(frameName, "OutputName", L.StrWarningsHelpTitle)
            Utils.setTextByName(frameName, "OutputContent", L.StrWarningsHelpBody)
            Utils.setTextColor(_G[frameName .. "OutputContent"], 0.5, 0.5, 0.5)
        end
        lastSelectedID = selectedID
    end

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
            if warningsDirty or not fetched then
                FetchWarnings()
                warningsDirty = false
            end
            if selectedID ~= lastSelectedID then
                UpdateSelectionUI()
            end
            tempName    = _G[frameName .. "Name"]:GetText()
            tempContent = _G[frameName .. "Content"]:GetText()
            Utils.enableDisable(_G[frameName .. "EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
            Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID ~= nil)
            Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID ~= nil)
            local editBtnMode = (tempName ~= "" or tempContent ~= "") or selectedID == nil
            if editBtnMode ~= lastEditBtnMode then
                Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, editBtnMode)
                lastEditBtnMode = editBtnMode
            end
        end)
    end

    -- Saving a Warning:
    function SaveWarning(wContent, wName, wID)
        wID = wID and tonumber(wID) or 0
        wName = Utils.trimText(wName)
        wContent = Utils.trimText(wContent)
        if wName == "" then
            wName = (isEdit and wID > 0) and wID or (#KRT_Warnings + 1)
        end
        if wContent == "" then
            addon:error(L.StrWarningsError)
            return
        end
        if isEdit and wID > 0 and KRT_Warnings[wID] ~= nil then
            KRT_Warnings[wID].name = wName
            KRT_Warnings[wID].content = wContent
            isEdit = false
        else
            tinsert(KRT_Warnings, { name = wName, content = wContent })
        end
        module:Cancel()
        module:Update()
    end

    -- Fetch module:
    function FetchWarnings()
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        local totalHeight = 0
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())
        for i, w in pairs(KRT_Warnings) do
            local btnName = frameName .. "WarningBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTWarningButtonTemplate")
            btn:Show()
            local ID = _G[btnName .. "ID"]
            ID:SetText(i)
            local wName = _G[btnName .. "Name"]
            wName:SetText(w.name)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
        fetched = true
        lastSelectedID = false
    end
end

