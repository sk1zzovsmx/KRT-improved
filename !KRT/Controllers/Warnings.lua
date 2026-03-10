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
local UnitIsGroupLeader = feature.UnitIsGroupLeader
local UnitIsGroupAssistant = feature.UnitIsGroupAssistant
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tinsert, twipe = table.insert, table.wipe
local ipairs = ipairs

local tonumber = tonumber

-- =========== Warnings Frame Module  =========== --
do
    addon.Controllers = addon.Controllers or {}
    addon.Controllers.Warnings = addon.Controllers.Warnings or {}
    local module = addon.Controllers.Warnings
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTWarnings")
    -- ----- Internal state ----- --
    local UI = {
        Localized = false,
        Loaded = false,
    }
    local fetched = false
    local warningsDirty = false

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local saveWarning
    local isEdit = false

    -- ----- Private helpers ----- --
    function UI.AcquireRefs(frame)
        return {
            name = Frames.Ref(frame, "Name"),
            content = Frames.Ref(frame, "Content"),
            editBtn = Frames.Ref(frame, "EditBtn"),
            deleteBtn = Frames.Ref(frame, "DeleteBtn"),
            announceBtn = Frames.Ref(frame, "AnnounceBtn"),
        }
    end

    local function bindWarningRow(row)
        if not row or row._krtBound then
            return
        end
        if row.RegisterForClicks then
            row:RegisterForClicks("LeftButtonUp")
        end
        Frames.SafeSetScript(row, "OnClick", function(self, button)
            module:Select(self, button)
        end)
        row._krtBound = true
    end

    -- ----- Public methods ----- --

    local controller = ListController.MakeListController({
        keyName = "WarningsList",
        poolTag = "warnings",
        _rowParts = { "ID", "Name" },

        getData = function(out)
            for i = 1, #KRT_Warnings do
                local w = KRT_Warnings[i]
                out[i] = { id = i, name = w and w.name or "" }
            end
        end,

        rowName = function(n, _, i)
            return n .. "WarningBtn" .. i
        end,
        rowTmpl = "KRTWarningButtonTemplate",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            bindWarningRow(row)
            local ui = row._p
            ui.ID:SetText(it.id)
            ui.Name:SetText(it.name)
        end),

        highlightId = function()
            return selectedID
        end,
    })

    local panelScaffold = UIScaffold.CreateListPanelScaffold({
        module = module,
        getFrame = getFrame,
        controller = controller,
        onShow = function()
            warningsDirty = true
            lastSelectedID = false
        end,
        localize = function()
            UI.Localize()
        end,
        update = function()
            UI.Refresh()
        end,
    })

    local function BindHandlers(_, frame, refs)
        if not (refs and refs.name and refs.content and refs.editBtn and refs.deleteBtn and refs.announceBtn) then
            return
        end
        if refs.editBtn and refs.editBtn.RegisterForClicks then
            refs.editBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        if refs.deleteBtn and refs.deleteBtn.RegisterForClicks then
            refs.deleteBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        if refs.announceBtn and refs.announceBtn.RegisterForClicks then
            refs.announceBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        if frame.HookScript then
            frame:HookScript("OnShow", function()
                module:Cancel()
            end)
            frame:HookScript("OnHide", function()
                module:Cancel()
            end)
        else
            Frames.SafeSetScript(frame, "OnShow", function()
                module:Cancel()
            end)
            Frames.SafeSetScript(frame, "OnHide", function()
                module:Cancel()
            end)
        end
        Frames.SafeSetScript(refs.announceBtn, "OnClick", function()
            module:Announce()
        end)
        Frames.SafeSetScript(refs.deleteBtn, "OnClick", function(self, button)
            module:Delete(self, button)
        end)
        Frames.SafeSetScript(refs.editBtn, "OnClick", function(self, button)
            module:Edit(self, button)
        end)
        Frames.SafeSetScript(refs.name, "OnTabPressed", function(self)
            local content = Frames.Ref(self:GetParent(), "Content")
            if content and content.SetFocus then
                content:SetFocus()
            end
        end)
        Frames.SafeSetScript(refs.content, "OnTabPressed", function(self)
            local name = Frames.Ref(self:GetParent(), "Name")
            if name and name.SetFocus then
                name:SetFocus()
            end
        end)
    end

    local function OnLoadFrame(frame)
        frameName = panelScaffold:OnLoad(frame) or (frame and frame.GetName and frame:GetName() or frameName)
        UI.Loaded = frameName ~= nil
        return frameName
    end

    UIScaffold.DefineModuleUi({
        module = module,
        getFrame = getFrame,
        acquireRefs = UI.AcquireRefs,
        bind = BindHandlers,
        localize = function()
            UI.Localize()
        end,
        onLoad = OnLoadFrame,
        refresh = function()
            panelScaffold:Refresh()
        end,
    })

    -- OnLoad frame:
    function module:OnLoad(frame)
        return OnLoadFrame(frame)
    end

    -- Warning selection:
    function module:Select(btn)
        if btn == nil or isEdit == true then
            return
        end
        local bName = btn:GetName()
        local wID = tonumber(_G[bName .. "ID"]:GetText())
        if KRT_Warnings[wID] == nil then
            return
        end
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
        local nameBox = _G[frameName .. "Name"]
        local contentBox = _G[frameName .. "Content"]
        if not (nameBox and contentBox) then
            return
        end
        local draftName = Strings.TrimText(nameBox:GetText())
        local draftContent = Strings.TrimText(contentBox:GetText())

        if selectedID ~= nil then
            local w = KRT_Warnings[selectedID]
            if w == nil then
                selectedID = nil
                return
            end
            if not isEdit and draftName == "" and draftContent == "" then
                nameBox:SetText(w.name)
                nameBox:SetFocus()
                contentBox:SetText(w.content)
                isEdit = true
                module:RequestRefresh()
                return
            end
        end
        wName = nameBox:GetText()
        wContent = contentBox:GetText()
        return saveWarning(wContent, wName, selectedID)
    end

    -- Delete Warning:
    function module:Delete(btn)
        if btn == nil or selectedID == nil then
            return
        end
        local oldWarnings = {}
        for i, w in ipairs(KRT_Warnings) do
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
        if KRT_Warnings == nil then
            return
        end
        if wID == nil then
            wID = (selectedID ~= nil) and selectedID or tempSelectedID
        end

        wID = tonumber(wID)
        if not wID or wID <= 0 or KRT_Warnings[wID] == nil then
            return
        end

        if addon.IsInRaid and addon.IsInRaid() and addon.options and addon.options.useRaidWarning then
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player")
            local isAssistant = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
            if not (isLeader or isAssistant) then
                addon:warn(L.WarnRaidWarningFallback)
            end
        end

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
    function UI.Localize()
        if UI.Localized then
            return
        end
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
        UI.Localized = true
    end

    local function updateSelectionUI()
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
    function UI.Refresh()
        if warningsDirty or not fetched then
            controller:Dirty()
            warningsDirty = false
            fetched = true
        end
        if selectedID ~= lastSelectedID then
            updateSelectionUI()
            controller:Touch()
        end
        tempName = _G[frameName .. "Name"]:GetText()
        tempContent = _G[frameName .. "Content"]:GetText()
        UIPrimitives.EnableDisableNamedPart(frameName, "EditBtn", (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
        UIPrimitives.EnableDisableNamedPart(frameName, "DeleteBtn", selectedID ~= nil)
        UIPrimitives.EnableDisableNamedPart(frameName, "AnnounceBtn", selectedID ~= nil)
        local editBtnMode = (tempName ~= "" or tempContent ~= "") or selectedID == nil
        lastEditBtnMode = UIPrimitives.UpdateModeTextNamedPart(frameName, "EditBtn", L.BtnSave, L.BtnEdit, editBtnMode, lastEditBtnMode)
    end

    function module:Refresh()
        panelScaffold:Refresh()
    end

    -- Saving a Warning:
    function saveWarning(wContent, wName, wID)
        local savedID
        if type(KRT_Warnings) ~= "table" then
            KRT_Warnings = {}
        end
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
            savedID = wID
            isEdit = false
        else
            tinsert(KRT_Warnings, { name = wName, content = wContent })
            savedID = #KRT_Warnings
        end

        Frames.ResetEditBox(_G[frameName .. "Name"])
        Frames.ResetEditBox(_G[frameName .. "Content"])
        selectedID = savedID
        tempSelectedID = nil
        isEdit = false
        lastSelectedID = false

        warningsDirty = true
        fetched = false
        controller:Dirty()
        module:RequestRefresh()
    end
end
