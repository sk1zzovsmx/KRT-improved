-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local ListController = feature.ListController or addon.ListController
local Frames = feature.Frames or addon.Frames
local Strings = feature.Strings or addon.Strings
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives

local bindModuleRequestRefresh = feature.BindModuleRequestRefresh
local bindModuleToggleHide = feature.BindModuleToggleHide
local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tinsert, twipe = table.insert, table.wipe
local ipairs = ipairs

local tonumber = tonumber

-- =========== Warnings Frame Module  =========== --
do
    addon.Controllers = addon.Controllers or {}
    addon.Controllers.Warnings = addon.Controllers.Warnings or {}
    addon.Warnings = addon.Controllers.Warnings -- Legacy alias during namespacing migration.
    local module = addon.Controllers.Warnings
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTWarnings")
    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local fetched = false
    local warningsDirty = false

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local SaveWarning
    local isEdit = false

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    local controller = ListController.MakeListController {
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

        drawRow = ListController.CreateRowDrawer(function(row, it)
            local ui = row._p
            ui.ID:SetText(it.id)
            ui.Name:SetText(it.name)
        end),

        highlightId = function() return selectedID end,
    }

    local panelScaffold = UIScaffold.CreateListPanelScaffold({
        module = module,
        getFrame = getFrame,
        controller = controller,
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
        onShow = function()
            warningsDirty = true
            lastSelectedID = false
        end,
        localize = function()
            if LocalizeUIFrame then
                LocalizeUIFrame()
            end
        end,
        update = function()
            if UpdateUIFrame then
                UpdateUIFrame()
            end
        end,
    })

    -- OnLoad frame:
    function module:OnLoad(frame)
        frameName = panelScaffold:OnLoad(frame)
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
        Frames.ResetEditBox(_G[frameName .. "Name"])
        Frames.ResetEditBox(_G[frameName .. "Content"])
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
        Frames.SetFrameTitle(frameName, RAID_WARNING)
        Frames.BindEditBoxHandlers(frameName, {
            { suffix = "Name", onEscape = module.Cancel, onEnter = module.Edit },
            { suffix = "Content", onEscape = module.Cancel, onEnter = module.Edit },
        }, function()
            module:RequestRefresh()
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

    -- UI refresh.
    function UpdateUIFrame()
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
        UIPrimitives.EnableDisableNamedPart(frameName, "EditBtn", (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
        UIPrimitives.EnableDisableNamedPart(frameName, "DeleteBtn", selectedID ~= nil)
        UIPrimitives.EnableDisableNamedPart(frameName, "AnnounceBtn", selectedID ~= nil)
        local editBtnMode = (tempName ~= "" or tempContent ~= "") or selectedID == nil
        lastEditBtnMode = UIPrimitives.UpdateModeTextNamedPart(
            frameName,
            "EditBtn",
            L.BtnSave,
            L.BtnEdit,
            editBtnMode,
            lastEditBtnMode
        )
    end

    function module:Refresh()
        panelScaffold:Refresh()
    end

    -- Saving a Warning:
    function SaveWarning(wContent, wName, wID)
        wID = wID and tonumber(wID) or 0
        wName = Strings.TrimText(wName)
        wContent = Strings.TrimText(wContent)
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
        warningsDirty = true
        module:RequestRefresh()
    end
end

