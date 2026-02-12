--[[
    Features/Warnings.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Utils = feature.Utils

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

local _G = _G
local tinsert, twipe = table.insert, table.wipe
local ipairs = ipairs

local tonumber = tonumber

-- =========== Warnings Frame Module  =========== --
do
    addon.Warnings = addon.Warnings or {}
    local module = addon.Warnings
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTWarnings")
    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local fetched = false
    local warningsDirty = false

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local SaveWarning
    local isEdit = false

    local controller = Utils.makeListController {
        keyName = "WarningsList",
        poolTag = "warnings",
        _rowParts = { "ID", "Name" },

        getData = function(out)
            for i = 1, #KRT_Warnings do
                local w = KRT_Warnings[i]
                out[i] = { id = i, name = w and w.name or "" }
            end
        end,

        rowName = function(n, _, i) return n .. "WarningBtn" .. i end,
        rowTmpl = "KRTWarningButtonTemplate",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.ID:SetText(it.id)
            ui.Name:SetText(it.name)
        end),

        highlightId = function() return selectedID end,
    }

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)
        frame:HookScript("OnShow", function()
            warningsDirty = true
            lastSelectedID = false
        end)
        controller:OnLoad(frame)
    end

    -- Externally update frame:
    function module:Update()
        warningsDirty = true
        module:RequestRefresh()
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function()
        warningsDirty = true
        lastSelectedID = false
        module:RequestRefresh()
    end)
    bindModuleToggleHide(module, uiController)

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
        module:RequestRefresh()
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
                module:RequestRefresh()
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
        module:RequestRefresh()
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
        module:RequestRefresh()
    end

    -- Localizing UI frame:
    function LocalizeUIFrame()
        if localized then return end
        _G[frameName .. "NameStr"]:SetText(L.StrName)
        _G[frameName .. "MessageStr"]:SetText(L.StrMessage)
        _G[frameName .. "EditBtn"]:SetText(L.BtnSave)
        _G[frameName .. "DeleteBtn"]:SetText(L.BtnDelete)
        _G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
        _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelpTitle)
        Utils.setFrameTitle(frameName, RAID_WARNING)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Content"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Content"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        _G[frameName .. "Content"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        localized = true
    end

    local function UpdateSelectionUI()
        if selectedID and KRT_Warnings[selectedID] then
            _G[frameName .. "OutputName"]:SetText(KRT_Warnings[selectedID].name)
            _G[frameName .. "OutputContent"]:SetText(KRT_Warnings[selectedID].content)
            _G[frameName .. "OutputContent"]:SetTextColor(1, 1, 1)
        else
            _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelpTitle)
            _G[frameName .. "OutputContent"]:SetText(L.StrWarningsHelpBody)
            _G[frameName .. "OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
        end
        lastSelectedID = selectedID
    end

    -- OnUpdate frame:
    function UpdateUIFrame()
        LocalizeUIFrame()
        if warningsDirty or not fetched then
            controller:Dirty()
            warningsDirty = false
            fetched = true
        end
        if selectedID ~= lastSelectedID then
            UpdateSelectionUI()
            controller:Touch()
        end
        tempName    = _G[frameName .. "Name"]:GetText()
        tempContent = _G[frameName .. "Content"]:GetText()
        Utils.enableDisable(_G[frameName .. "EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
        Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID ~= nil)
        Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID ~= nil)
        local editBtnMode = (tempName ~= "" or tempContent ~= "") or selectedID == nil
        if editBtnMode ~= lastEditBtnMode then
            Utils.setText(_G[frameName .. "EditBtn"], L.BtnSave, L.BtnEdit, editBtnMode)
            lastEditBtnMode = editBtnMode
        end
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    bindModuleRequestRefresh(module, getFrame)

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
end
