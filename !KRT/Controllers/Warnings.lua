-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: owns warning UI scripts; sends announcements through Services/Chat
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Controllers = feature.Controllers
local coreState = feature.coreState
local Database = feature.Database

local ListController = feature.ListController
local Frames = feature.Frames
local Strings = feature.Strings
local Services = feature.Services
local UIScaffold = feature.UIScaffold
local UIPrimitives = feature.UIPrimitives

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tconcat = table.concat
local tinsert, tremove = table.insert, table.remove

local tonumber, tostring = tonumber, tostring
local lower = string.lower

local requireServiceMethod = Database.RequireServiceMethod

local Chat = Services.Chat
local ChatApi = {
    AnnounceWarningMessage = requireServiceMethod("Chat", Chat, "AnnounceWarningMessage"),
}

-- =========== Warnings Frame Module  =========== --
do
    Controllers.Warnings = Controllers.Warnings or {}
    local module = Controllers.Warnings
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui

    local getFrame = makeModuleFrameGetter(module, "KRTWarnings")
    -- ----- Internal state ----- --
    local fetched = false
    local warningsDirty = false

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local saveWarning, editWarning, deleteWarning, announceWarning
    local isEdit = false
    local defaultWarningTemplates = {
        {
            name = "StrRaidWarningTemplatePullName",
            content = "StrRaidWarningTemplatePullContent",
            fallbackName = "Pull",
            fallbackContent = "Pull in 10 seconds.",
        },
        {
            name = "StrRaidWarningTemplateSpreadName",
            content = "StrRaidWarningTemplateSpreadContent",
            fallbackName = "Spread",
            fallbackContent = "Spread out.",
        },
        {
            name = "StrRaidWarningTemplateStackName",
            content = "StrRaidWarningTemplateStackContent",
            fallbackName = "Stack",
            fallbackContent = "Stack on marker.",
        },
        {
            name = "StrRaidWarningTemplateStopDpsName",
            content = "StrRaidWarningTemplateStopDpsContent",
            fallbackName = "Stop DPS",
            fallbackContent = "Stop DPS now.",
        },
        {
            name = "StrRaidWarningTemplateBloodlustName",
            content = "StrRaidWarningTemplateBloodlustContent",
            fallbackName = "Bloodlust",
            fallbackContent = "Use Bloodlust/Heroism now.",
        },
        {
            name = "StrRaidWarningTemplateBreakName",
            content = "StrRaidWarningTemplateBreakContent",
            fallbackName = "Break",
            fallbackContent = "Break time. Be back soon.",
        },
    }

    -- ----- Private helpers ----- --
    local function getWarningsStore()
        if type(KRT_Warnings) ~= "table" then
            KRT_Warnings = {}
        end
        return KRT_Warnings
    end

    local function getTemplateValue(template, key, fallbackKey)
        local value = template and L[template[key]]
        if type(value) == "string" and value ~= "" and value ~= template[key] and value ~= ("L." .. template[key]) then
            return value
        end
        return template and template[fallbackKey] or ""
    end

    local function normalizeTemplateName(value)
        local text = Strings.TrimText(value or "")
        return text ~= "" and lower(text) or nil
    end

    local function resetWarningState()
        selectedID = nil
        tempSelectedID = nil
        lastSelectedID = false
        lastEditBtnMode = nil
        tempName = nil
        tempContent = nil
        isEdit = false
    end

    local function ensureDefaultTemplates(refreshReason)
        local warnings = getWarningsStore()
        local existing = {}
        for i = 1, #warnings do
            local key = normalizeTemplateName(warnings[i] and warnings[i].name)
            if key then
                existing[key] = true
            end
        end

        local added = 0
        for i = 1, #defaultWarningTemplates do
            local template = defaultWarningTemplates[i]
            local name = getTemplateValue(template, "name", "fallbackName")
            local key = normalizeTemplateName(name)
            if key and not existing[key] then
                tinsert(warnings, {
                    name = name,
                    content = getTemplateValue(template, "content", "fallbackContent"),
                })
                existing[key] = true
                added = added + 1
            end
        end

        warningsDirty = true
        fetched = false
        if refreshReason ~= false and module.RequestRefresh then
            module:RequestRefresh(refreshReason or "templates")
        end
        return {
            added = added,
            total = #warnings,
        }
    end

    local function isDefaultTemplateWarning(warning)
        if type(warning) ~= "table" then
            return false
        end
        local warningName = normalizeTemplateName(warning.name)
        local warningContent = tostring(warning.content or "")
        for i = 1, #defaultWarningTemplates do
            local template = defaultWarningTemplates[i]
            local templateName = normalizeTemplateName(getTemplateValue(template, "name", "fallbackName"))
            local templateContent = getTemplateValue(template, "content", "fallbackContent")
            if warningName == templateName and warningContent == templateContent then
                return true
            end
        end
        return false
    end

    local function collectStockWarnings(warnings)
        local stock = {}
        if type(warnings) ~= "table" then
            return stock
        end
        for i = 1, #warnings do
            local warning = warnings[i]
            if isDefaultTemplateWarning(warning) then
                stock[#stock + 1] = {
                    name = warning.name,
                    content = warning.content,
                }
            end
        end
        return stock
    end

    function UI.AcquireRefs(frame)
        return {
            name = Frames.GetRef(frame, "Name"),
            content = Frames.GetRef(frame, "Content"),
            editBtn = Frames.GetRef(frame, "EditBtn"),
            deleteBtn = Frames.GetRef(frame, "DeleteBtn"),
            announceBtn = Frames.GetRef(frame, "AnnounceBtn"),
        }
    end

    local function cancelWarning()
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        Frames.ResetEditBox(_G[frameName .. "Name"])
        Frames.ResetEditBox(_G[frameName .. "Content"])
        selectedID = nil
        tempSelectedID = nil
        isEdit = false
        module:RequestRefresh()
    end

    local function selectWarning(btn)
        if btn == nil or isEdit == true then
            return
        end
        local bName = btn:GetName()
        local wID = tonumber(_G[bName .. "ID"]:GetText())
        local warnings = getWarningsStore()
        if warnings[wID] == nil then
            return
        end
        if IsControlKeyDown() then
            selectedID = nil
            tempSelectedID = wID
            return announceWarning(tempSelectedID)
        end
        selectedID = (wID ~= selectedID) and wID or nil
        module:RequestRefresh()
    end

    local function bindWarningRow(row)
        if not row or row._krtBound then
            return
        end
        if row.RegisterForClicks then
            row:RegisterForClicks("LeftButtonUp")
        end
        Frames.SetScriptSafely(row, "OnClick", function(self, button)
            selectWarning(self, button)
        end)
        row._krtBound = true
    end

    -- ----- Public methods ----- --

    local controller = ListController.MakeListController({
        keyName = "WarningsList",
        poolTag = "warnings",
        _rowParts = { "ID", "Name" },

        getData = function(out)
            local warnings = getWarningsStore()
            for i = 1, #warnings do
                local w = warnings[i]
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
                cancelWarning()
            end)
            frame:HookScript("OnHide", function()
                cancelWarning()
            end)
        else
            Frames.SetScriptSafely(frame, "OnShow", function()
                cancelWarning()
            end)
            Frames.SetScriptSafely(frame, "OnHide", function()
                cancelWarning()
            end)
        end
        Frames.SetScriptSafely(refs.announceBtn, "OnClick", function()
            announceWarning()
        end)
        Frames.SetScriptSafely(refs.deleteBtn, "OnClick", function(self, button)
            deleteWarning(self, button)
        end)
        Frames.SetScriptSafely(refs.editBtn, "OnClick", function(self, button)
            editWarning(self, button)
        end)
        Frames.SetScriptSafely(refs.name, "OnTabPressed", function(self)
            local content = Frames.GetRef(self:GetParent(), "Content")
            if content and content.SetFocus then
                content:SetFocus()
            end
        end)
        Frames.SetScriptSafely(refs.content, "OnTabPressed", function(self)
            local name = Frames.GetRef(self:GetParent(), "Name")
            if name and name.SetFocus then
                name:SetFocus()
            end
        end)
    end

    local function OnLoadFrame(frame)
        UI.FrameName = panelScaffold:OnLoad(frame) or (frame and frame.GetName and frame:GetName() or UI.FrameName)
        UI.Loaded = UI.FrameName ~= nil
        return UI.FrameName
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

    -- Edit/Save warning:
    function editWarning()
        local wName, wContent
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        local nameBox = _G[frameName .. "Name"]
        local contentBox = _G[frameName .. "Content"]
        if not (nameBox and contentBox) then
            return
        end
        local draftName = Strings.TrimText(nameBox:GetText())
        local draftContent = Strings.TrimText(contentBox:GetText())

        if selectedID ~= nil then
            local warnings = getWarningsStore()
            local w = warnings[selectedID]
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
    function deleteWarning(btn)
        if btn == nil or selectedID == nil then
            return
        end
        local warnings = getWarningsStore()
        if warnings[selectedID] == nil then
            selectedID = nil
            warningsDirty = true
            module:RequestRefresh()
            return
        end
        tremove(warnings, selectedID)
        local count = #warnings
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
    function announceWarning(wID)
        local warnings = getWarningsStore()
        if wID == nil then
            wID = (selectedID ~= nil) and selectedID or tempSelectedID
        end

        wID = tonumber(wID)
        if not wID or wID <= 0 or warnings[wID] == nil then
            return
        end

        tempSelectedID = nil -- Always clear temporary selected id:

        return ChatApi.AnnounceWarningMessage(Chat, warnings[wID].content)
    end

    function module:RequestAnnounce(wID)
        return announceWarning(wID)
    end

    function module:RequestEnsureDefaultTemplates()
        return ensureDefaultTemplates("templates")
    end

    function module:RequestTemplatePreview()
        local warnings = getWarningsStore()
        local lines = {}
        for i = 1, #warnings do
            local warning = warnings[i]
            if warning then
                lines[#lines + 1] = tostring(i) .. ". " .. tostring(warning.name or "") .. ": " .. tostring(warning.content or "")
            end
        end
        if #lines == 0 then
            lines[1] = L.StrConfigRaidWarningPreviewEmpty or ""
        end
        return {
            text = tconcat(lines, "\n"),
            total = #warnings,
        }
    end

    function module:RequestClearSavedWarnings(includeStock)
        local warnings = getWarningsStore()
        local removed = #warnings
        local keptStock = includeStock == false and collectStockWarnings(warnings) or nil
        for i = #warnings, 1, -1 do
            tremove(warnings, i)
        end

        resetWarningState()
        if keptStock then
            for i = 1, #keptStock do
                tinsert(warnings, keptStock[i])
            end
            removed = removed - #keptStock
            if removed < 0 then
                removed = 0
            end
        end
        warningsDirty = true
        fetched = false
        if module.RequestRefresh then
            module:RequestRefresh("clear_saved")
        end
        return {
            removed = removed,
            total = #warnings,
        }
    end

    -- Localizing UI frame:
    function UI.Localize()
        if UI.Localized then
            return
        end
        local frameName = UI.FrameName
        if not frameName then
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
            { suffix = "Name", onEscape = cancelWarning, onEnter = editWarning },
            { suffix = "Content", onEscape = cancelWarning, onEnter = editWarning },
        }, function()
            module:RequestRefresh()
        end)
        UI.Localized = true
    end

    local function updateSelectionUI()
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        local warnings = getWarningsStore()
        if selectedID and warnings[selectedID] then
            _G[frameName .. "OutputName"]:SetText(warnings[selectedID].name)
            _G[frameName .. "OutputContent"]:SetText(warnings[selectedID].content)
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
        local frameName = UI.FrameName
        if not frameName then
            return
        end
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

    -- Saving a Warning:
    function saveWarning(wContent, wName, wID)
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        local savedID
        local warnings = getWarningsStore()
        wID = wID and tonumber(wID) or 0
        wName = Strings.TrimText(wName)
        wContent = Strings.TrimText(wContent)
        if wName == "" then
            wName = (isEdit and wID > 0) and wID or (#warnings + 1)
        end
        if wContent == "" then
            addon:error(L.StrWarningsError)
            return
        end
        if isEdit and wID > 0 and warnings[wID] ~= nil then
            warnings[wID].name = wName
            warnings[wID].content = wContent
            savedID = wID
            isEdit = false
        else
            tinsert(warnings, { name = wName, content = wContent })
            savedID = #warnings
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

    if coreState and coreState.warningsSavedVariablesFresh == true then
        module:RequestEnsureDefaultTemplates()
        coreState.warningsSavedVariablesFresh = false
    end
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Controllers/Warnings", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Modules/UI/ListController",
            "Services/Chat",
        },
    })
    registry.SetLoaded("Controllers/Warnings")
end
