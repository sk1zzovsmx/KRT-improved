-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type = type
local format = string.format
local ipairs = ipairs
local pairs = pairs
local strsub = string.sub

local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown

addon.Frames = addon.Frames or {}
local Frames = addon.Frames

addon.UIScaffold = addon.UIScaffold or {}
local UIScaffold = addon.UIScaffold
local tooltipColor = HIGHLIGHT_FONT_COLOR

-- ----- Internal state ----- --

-- ----- Private helpers ----- --
local function resolveFrameName(frameOrName)
    if type(frameOrName) == "string" then
        return frameOrName
    end
    if frameOrName and frameOrName.GetName then
        return frameOrName:GetName()
    end
    return nil
end

local function isModuleUiBound(module, uiState)
    return uiState and uiState.Bound and module and module.frame and module.refs
end

-- ----- Public methods ----- --
function Frames.EnableDrag(frame, dragButton)
    if not frame or not frame.RegisterForDrag then
        return
    end
    if frame.SetMovable then
        frame:SetMovable(true)
    end
    if frame.EnableMouse then
        frame:EnableMouse(true)
    end
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end

    if frame.GetScript and frame.SetScript then
        if not frame:GetScript("OnDragStart") then
            frame:SetScript("OnDragStart", function(self)
                if InCombatLockdown() then
                    return
                end
                if self.StartMoving then
                    self:StartMoving()
                end
            end)
        end
        if not frame:GetScript("OnDragStop") then
            frame:SetScript("OnDragStop", function(self)
                if InCombatLockdown() then
                    return
                end
                if self.StopMovingOrSizing then
                    self:StopMovingOrSizing()
                end
            end)
        end
    end

    frame:RegisterForDrag(dragButton or "LeftButton")
end

function Frames.MakeConfirmPopup(key, text, onAccept, cancels)
    StaticPopupDialogs[key] = {
        text = text,
        button1 = OKAY,
        button2 = CANCEL,
        OnAccept = onAccept,
        cancels = cancels or key,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end

function Frames.MakeEditBoxPopup(key, text, onAccept, onShow, validate)
    StaticPopupDialogs[key] = {
        text = text,
        button1 = SAVE,
        button2 = CANCEL,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        hasEditBox = 1,
        cancels = key,
        OnShow = function(self)
            if onShow then
                onShow(self)
            end
        end,
        OnHide = function(self)
            self.editBox:SetText("")
            self.editBox:ClearFocus()
        end,
        OnAccept = function(self)
            local Strings = addon.Strings
            local trimText = Strings and Strings.TrimText
            local value = trimText and trimText(self.editBox:GetText(), true) or self.editBox:GetText()
            if validate then
                local ok, cleanValue = validate(self, value)
                if not ok then
                    return
                end
                if cleanValue ~= nil then
                    value = cleanValue
                end
            end
            onAccept(self, value)
        end,
    }
end

function Frames.SetFrameTitle(frameOrName, titleText, titleFormat)
    local frameName = resolveFrameName(frameOrName)
    if not frameName then
        return
    end
    local titleFrame = _G[frameName .. "Title"]
    if not titleFrame then
        return
    end
    local fmt = titleFormat or (addon.C and addon.C.titleString) or "%s"
    titleFrame:SetText(format(fmt, titleText))
end

function Frames.ResetEditBox(editBox, hide)
    if not editBox then
        return
    end
    editBox:SetText("")
    editBox:ClearFocus()
    if hide then
        editBox:Hide()
    end
end

function Frames.SetEditBoxValue(editBox, value, focus)
    if not editBox then
        return
    end
    editBox:SetText(value)
    editBox:Show()
    if focus then
        editBox:SetFocus()
    end
end

function Frames.SetShown(frame, show)
    if not frame then
        return
    end
    if show then
        if not frame:IsShown() then
            frame:Show()
        end
    elseif frame:IsShown() then
        frame:Hide()
    end
end

function Frames.Get(frameName)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end
    return _G[frameName]
end

function Frames.Ref(frameOrName, childName)
    local frameName = resolveFrameName(frameOrName)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end
    if type(childName) ~= "string" or childName == "" then
        return nil
    end

    if strsub(childName, 1, #frameName) == frameName then
        return _G[childName]
    end

    local exact = _G[childName]
    if exact then
        return exact
    end

    return _G[frameName .. childName]
end

function Frames.GetNamedParts(widget, parts, cacheField)
    if not widget or type(parts) ~= "table" then
        return nil
    end

    cacheField = cacheField or "_krtRefs"
    if widget[cacheField] then
        return widget[cacheField]
    end

    local widgetName = widget.GetName and widget:GetName() or nil
    local refs = {}

    for key, suffix in pairs(parts) do
        local refKey = type(key) == "number" and suffix or key
        refs[refKey] = widgetName and _G[widgetName .. suffix] or nil
    end

    widget[cacheField] = refs
    return refs
end

function Frames.SafeSetScript(widget, scriptType, handler)
    if not widget or not widget.SetScript then
        return false
    end
    if type(scriptType) ~= "string" or scriptType == "" then
        return false
    end
    if handler ~= nil and type(handler) ~= "function" then
        if addon.State and addon.State.debugEnabled then
            error("Frames.SafeSetScript: handler must be a function or nil")
        end
        return false
    end

    widget:SetScript(scriptType, handler)
    return true
end

function Frames.GetButtonPopup(cfg)
    cfg = cfg or {}

    local popup = {
        frame = nil,
        buttons = {},
    }

    local function resolveParent()
        if type(cfg.getParent) == "function" then
            return cfg.getParent()
        end
        return cfg.parent
    end

    local function ensureFrame()
        if popup.frame then
            return popup.frame
        end

        local parent = resolveParent()
        if not parent then
            return nil
        end

        popup.frame = CreateFrame("Frame", cfg.frameName, parent, cfg.frameTemplate or "KRTSimpleFrameTemplate")
        popup.frame:Hide()
        return popup.frame
    end

    local function ensureButton(index)
        local frame = ensureFrame()
        if not frame then
            return nil
        end

        local button = popup.buttons[index]
        if button then
            return button
        end

        local buttonName = cfg.buttonName and cfg.buttonName(index) or nil
        button = CreateFrame("Button", buttonName, frame, cfg.buttonTemplate)
        button:SetID(index)
        if button.RegisterForClicks then
            button:RegisterForClicks(cfg.clickRegistration or "AnyUp")
        end
        if cfg.onButtonClick then
            Frames.SafeSetScript(button, "OnClick", cfg.onButtonClick)
        end
        if cfg.initButton then
            cfg.initButton(button, index)
        end

        popup.buttons[index] = button
        return button
    end

    function popup:GetFrame()
        return self.frame or ensureFrame()
    end

    function popup:Hide()
        if self.frame then
            self.frame:Hide()
        end
    end

    function popup:Toggle()
        local frame = ensureFrame()
        if not frame then
            return false
        end

        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end

        return frame:IsShown()
    end

    function popup:Refresh(count)
        local frame = ensureFrame()
        local rowCount = tonumber(count) or 0
        local height = tonumber(cfg.topInset) or 5
        local rowStep = tonumber(cfg.rowStep) or 37
        local leftInset = tonumber(cfg.leftInset) or 0

        if not frame then
            return nil
        end

        for index = 1, rowCount do
            local button = ensureButton(index)
            if button then
                if cfg.drawButton then
                    cfg.drawButton(button, index)
                end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", frame, "TOPLEFT", leftInset, -height)
                button:Show()
                height = height + rowStep
            end
        end

        for index = rowCount + 1, #self.buttons do
            local button = self.buttons[index]
            if button then
                button:Hide()
            end
        end

        frame:SetHeight(height)
        if rowCount <= 0 then
            frame:Hide()
        end

        return frame
    end

    return popup
end

local function showTooltip(frame)
    if not frame.tooltip_anchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    else
        GameTooltip:SetOwner(frame, frame.tooltip_anchor)
    end

    if frame.tooltip_title then
        GameTooltip:SetText(frame.tooltip_title)
    end

    if frame.tooltip_text then
        if type(frame.tooltip_text) == "string" then
            GameTooltip:AddLine(frame.tooltip_text, tooltipColor.r, tooltipColor.g, tooltipColor.b, true)
        elseif type(frame.tooltip_text) == "table" then
            for _, line in ipairs(frame.tooltip_text) do
                GameTooltip:AddLine(line, tooltipColor.r, tooltipColor.g, tooltipColor.b, true)
            end
        end
    end

    if frame.tooltip_item then
        GameTooltip:SetHyperlink(frame.tooltip_item)
    end

    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

function Frames.SetTooltip(frame, text, anchor, title)
    if not frame then
        return
    end
    frame.tooltip_text = text and text or frame.tooltip_text
    frame.tooltip_anchor = anchor and anchor or frame.tooltip_anchor
    frame.tooltip_title = title and title or frame.tooltip_title
    if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then
        return
    end
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", hideTooltip)
end

function Frames.MakeEventDrivenRefresher(targetOrGetter, updateFn)
    if type(updateFn) ~= "function" then
        error("Frames.MakeEventDrivenRefresher: updateFn must be a function")
    end

    local driver = CreateFrame("Frame")
    local pending = false
    local dirtyWhileHidden = false
    local hookedFrame = nil

    local function resolveTarget()
        if type(targetOrGetter) == "function" then
            return targetOrGetter()
        end
        return targetOrGetter
    end

    local function ensureHook(target)
        if not target or not target.HookScript then
            return
        end
        if hookedFrame == target then
            return
        end
        hookedFrame = target
        target:HookScript("OnShow", function()
            if dirtyWhileHidden then
                dirtyWhileHidden = false
                updateFn()
            end
        end)
    end

    local function run()
        driver:SetScript("OnUpdate", nil)
        pending = false

        local target = resolveTarget()
        if not target or not target.IsShown or not target:IsShown() then
            dirtyWhileHidden = true
            if target then
                ensureHook(target)
            end
            return
        end
        updateFn()
    end

    return function()
        local target = resolveTarget()
        if not target then
            return
        end
        ensureHook(target)

        if not target:IsShown() then
            dirtyWhileHidden = true
            return
        end

        if pending then
            return
        end
        pending = true
        driver:SetScript("OnUpdate", run)
    end
end

function Frames.MakeFrameGetter(globalFrameName)
    local cached = nil
    return function()
        if cached then
            return cached
        end
        local frame = _G[globalFrameName]
        if frame then
            cached = frame
        end
        return frame
    end
end

function Frames.InitModuleFrame(module, frame, opts)
    if not frame then
        return nil
    end
    if module then
        module.frame = frame
    end

    local frameName = frame:GetName()
    opts = opts or {}

    if opts.enableDrag then
        Frames.EnableDrag(frame, opts.dragButton)
    end

    if opts.hookOnShow then
        frame:HookScript("OnShow", opts.hookOnShow)
    end
    if opts.setOnShow then
        frame:SetScript("OnShow", opts.setOnShow)
    end
    if opts.hookOnHide then
        frame:HookScript("OnHide", opts.hookOnHide)
    end
    if opts.setOnHide then
        frame:SetScript("OnHide", opts.setOnHide)
    end

    return frameName
end

local function makeUIFrameController(getFrame, requestRefreshFn)
    local function showFrame(frame)
        if requestRefreshFn then
            requestRefreshFn()
        end
        Frames.SetShown(frame, true)
    end

    return {
        Toggle = function(self)
            local frame = getFrame()
            if not frame then
                return
            end
            if frame:IsShown() then
                Frames.SetShown(frame, false)
            else
                showFrame(frame)
            end
        end,
        Hide = function(self)
            local frame = getFrame()
            if frame then
                Frames.SetShown(frame, false)
            end
        end,
        Show = function(self)
            local frame = getFrame()
            if frame then
                showFrame(frame)
            end
        end,
    }
end

function UIScaffold.BootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local uiController = makeUIFrameController(getFrame, requestRefreshFn)
    if opts then
        if opts.bindToggleHide then
            opts.bindToggleHide(module, uiController)
        end
        if opts.bindRequestRefresh then
            opts.bindRequestRefresh(module, getFrame)
        end
    end
    return uiController
end

function UIScaffold.DefineModuleUi(cfg)
    cfg = cfg or {}
    local module = cfg.module
    local getFrame = cfg.getFrame
    local acquireRefs = cfg.acquireRefs
    local bindHandlers = cfg.bind
    local localize = cfg.localize
    local onLoadFrame = cfg.onLoad
    local initFrameOpts = cfg.initFrameOpts
    local refreshFn = cfg.refresh

    if type(module) ~= "table" then
        error("UIScaffold.DefineModuleUi: cfg.module must be a table")
    end
    if type(getFrame) ~= "function" then
        error("UIScaffold.DefineModuleUi: cfg.getFrame must be a function")
    end
    if acquireRefs and type(acquireRefs) ~= "function" then
        error("UIScaffold.DefineModuleUi: cfg.acquireRefs must be a function")
    end
    if bindHandlers and type(bindHandlers) ~= "function" then
        error("UIScaffold.DefineModuleUi: cfg.bind must be a function")
    end
    if localize and type(localize) ~= "function" then
        error("UIScaffold.DefineModuleUi: cfg.localize must be a function")
    end
    if onLoadFrame and type(onLoadFrame) ~= "function" then
        error("UIScaffold.DefineModuleUi: cfg.onLoad must be a function")
    end
    if refreshFn and type(refreshFn) ~= "function" then
        error("UIScaffold.DefineModuleUi: cfg.refresh must be a function")
    end

    module._ui = module._ui
        or {
            Loaded = false,
            Bound = false,
            Localized = false,
            Dirty = true,
            Reason = nil,
            FrameName = nil,
        }
    local UI = module._ui

    local function doRefresh()
        local frame = getFrame()
        if not frame then
            return
        end

        local dirty = UI.Dirty
        local reason = UI.Reason
        UI.Dirty = false
        UI.Reason = nil

        local refs = module.refs
        if refreshFn then
            return refreshFn(UI.FrameName, frame, refs, dirty, reason)
        end
        if type(module.RefreshUI) == "function" then
            return module:RefreshUI(UI.FrameName, frame, refs, dirty, reason)
        end
        if type(module.Refresh) == "function" then
            return module:Refresh(dirty, reason)
        end
    end

    local requestRefresh = Frames.MakeEventDrivenRefresher(getFrame, doRefresh)

    function module:MarkDirty(reason)
        UI.Dirty = true
        if reason then
            UI.Reason = reason
        end
    end

    function module:RequestRefresh(reason)
        self:MarkDirty(reason)
        requestRefresh()
    end

    local uiController = makeUIFrameController(getFrame, function()
        module:RequestRefresh("toggle")
    end)

    function module:BindUI()
        if isModuleUiBound(self, UI) then
            return self.frame, self.refs
        end

        local frame = getFrame()
        if not frame then
            return nil
        end

        if not UI.Loaded then
            local frameName
            if onLoadFrame then
                frameName = onLoadFrame(frame)
            else
                frameName = Frames.InitModuleFrame(module, frame, initFrameOpts)
            end
            UI.FrameName = frameName or (frame.GetName and frame:GetName()) or UI.FrameName
            UI.Loaded = UI.FrameName ~= nil
        end

        local refs = acquireRefs and acquireRefs(frame, UI.FrameName) or {}
        self.frame = frame
        self.refs = refs

        if bindHandlers then
            bindHandlers(UI.FrameName, frame, refs)
        end

        if (not UI.Localized) and localize then
            localize(UI.FrameName, frame, refs)
            UI.Localized = true
        end

        UI.Bound = true

        if frame.IsShown and frame:IsShown() then
            self:RequestRefresh("bind")
        end

        return frame, refs
    end

    function module:EnsureUI()
        if isModuleUiBound(self, UI) then
            return self.frame
        end
        local frame = self:BindUI()
        return frame
    end

    function module:Toggle()
        if not self:EnsureUI() then
            return
        end
        return uiController:Toggle()
    end

    function module:Hide()
        if not self:EnsureUI() then
            return
        end
        return uiController:Hide()
    end

    function module:Show()
        if not self:EnsureUI() then
            return
        end
        return uiController:Show()
    end

    return UI
end

function UIScaffold.MakeStandardWidgetApi(module, extraMethods)
    if type(module) ~= "table" then
        error("UIScaffold.MakeStandardWidgetApi: module must be a table")
    end

    local api = {
        Toggle = function()
            return module:Toggle()
        end,
        Hide = function()
            return module:Hide()
        end,
        RequestRefresh = function()
            return module:RequestRefresh()
        end,
    }

    if type(extraMethods) == "table" then
        for key, method in pairs(extraMethods) do
            api[key] = method
        end
    end

    return api
end

function UIScaffold.CreateListPanelScaffold(cfg)
    cfg = cfg or {}
    local module = cfg.module
    local getFrame = cfg.getFrame
    local controller = cfg.controller

    if type(module) ~= "table" then
        error("UIScaffold.CreateListPanelScaffold: cfg.module must be a table")
    end
    if type(getFrame) ~= "function" then
        error("UIScaffold.CreateListPanelScaffold: cfg.getFrame must be a function")
    end
    if type(controller) ~= "table" then
        error("UIScaffold.CreateListPanelScaffold: cfg.controller must be a table")
    end

    local frameName
    local dirty = true
    local initOpts = cfg.initOpts or {}

    local scaffold = {}

    local function markDirty()
        dirty = true
    end

    local function requestRefresh()
        markDirty()
        if module.RequestRefresh then
            module:RequestRefresh()
        end
    end

    local frameInitOpts = {
        enableDrag = (initOpts.enableDrag ~= false),
        dragButton = initOpts.dragButton,
        setOnShow = initOpts.setOnShow,
        setOnHide = initOpts.setOnHide,
        hookOnShow = function(...)
            markDirty()
            if cfg.onShow then
                cfg.onShow(...)
            end
        end,
        hookOnHide = function(...)
            if cfg.onHide then
                cfg.onHide(...)
            end
        end,
    }

    UIScaffold.BootstrapModuleUi(module, getFrame, requestRefresh, {
        bindToggleHide = cfg.bindToggleHide,
        bindRequestRefresh = cfg.bindRequestRefresh,
    })

    function scaffold:OnLoad(frame)
        frameName = Frames.InitModuleFrame(module, frame, frameInitOpts)
        if not frameName then
            return nil
        end
        if controller.OnLoad then
            controller:OnLoad(frame)
        end
        return frameName
    end

    function scaffold:Refresh()
        local frame = getFrame()
        if not frame then
            return
        end
        if cfg.localize then
            cfg.localize(frameName, frame)
        end
        if cfg.update then
            cfg.update(frameName, frame, dirty)
        end
        dirty = false
    end

    function scaffold:MarkDirty()
        markDirty()
    end

    function scaffold:GetFrameName()
        return frameName
    end

    return scaffold
end

function Frames.BindEditBoxHandlers(frameName, specs, requestRefreshFn)
    if type(frameName) ~= "string" or type(specs) ~= "table" then
        return
    end

    for i = 1, #specs do
        local spec = specs[i]
        local suffix = spec and spec.suffix
        local editBox = suffix and _G[frameName .. suffix] or nil
        if editBox then
            if spec.onEscape then
                editBox:SetScript("OnEscapePressed", spec.onEscape)
            end
            if spec.onEnter then
                editBox:SetScript("OnEnterPressed", spec.onEnter)
            end
            if spec.onFocusLost then
                editBox:SetScript("OnEditFocusLost", spec.onFocusLost)
            end
            if requestRefreshFn then
                editBox:SetScript("OnTextChanged", function(_, isUserInput)
                    if isUserInput then
                        requestRefreshFn()
                    end
                end)
            end
        end
    end
end
