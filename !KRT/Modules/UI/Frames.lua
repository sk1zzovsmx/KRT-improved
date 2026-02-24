-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type = type
local format = string.format
local ipairs = ipairs

local _G = _G
local function CreateFrame(...)
    return _G.CreateFrame(...)
end

addon.Frames = addon.Frames or {}
local Frames = addon.Frames

addon.UIScaffold = addon.UIScaffold or {}
local UIScaffold = addon.UIScaffold
local tooltipColor = HIGHLIGHT_FONT_COLOR

function Frames.enableDrag(frame, dragButton)
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
                if self.StartMoving then
                    self:StartMoving()
                end
            end)
        end
        if not frame:GetScript("OnDragStop") then
            frame:SetScript("OnDragStop", function(self)
                if self.StopMovingOrSizing then
                    self:StopMovingOrSizing()
                end
            end)
        end
    end

    frame:RegisterForDrag(dragButton or "LeftButton")
end

function Frames.makeConfirmPopup(key, text, onAccept, cancels)
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

function Frames.makeEditBoxPopup(key, text, onAccept, onShow, validate)
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
            local trimText = Strings and Strings.trimText
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

function Frames.setFrameTitle(frameOrName, titleText, titleFormat)
    local frameName = frameOrName
    if type(frameOrName) ~= "string" then
        frameName = frameOrName and frameOrName.GetName and frameOrName:GetName() or nil
    end
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

function Frames.resetEditBox(editBox, hide)
    if not editBox then
        return
    end
    editBox:SetText("")
    editBox:ClearFocus()
    if hide then
        editBox:Hide()
    end
end

function Frames.setEditBoxValue(editBox, value, focus)
    if not editBox then
        return
    end
    editBox:SetText(value)
    editBox:Show()
    if focus then
        editBox:SetFocus()
    end
end

function Frames.setShown(frame, show)
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

function Frames.setTooltip(frame, text, anchor, title)
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

function Frames.makeEventDrivenRefresher(targetOrGetter, updateFn)
    if type(updateFn) ~= "function" then
        error("Frames.makeEventDrivenRefresher: updateFn must be a function")
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

function Frames.makeFrameGetter(globalFrameName)
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

function Frames.initModuleFrame(module, frame, opts)
    if not frame then
        return nil
    end
    if module then
        module.frame = frame
    end

    local frameName = frame:GetName()
    opts = opts or {}

    if opts.enableDrag then
        Frames.enableDrag(frame, opts.dragButton)
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

function UIScaffold.makeUIFrameController(getFrame, requestRefreshFn)
    return {
        Toggle = function(self)
            local frame = getFrame()
            if not frame then
                return
            end
            if frame:IsShown() then
                Frames.setShown(frame, false)
            else
                if requestRefreshFn then
                    requestRefreshFn()
                end
                Frames.setShown(frame, true)
            end
        end,
        Hide = function(self)
            local frame = getFrame()
            if frame then
                Frames.setShown(frame, false)
            end
        end,
        Show = function(self)
            local frame = getFrame()
            if frame then
                if requestRefreshFn then
                    requestRefreshFn()
                end
                Frames.setShown(frame, true)
            end
        end,
    }
end

function UIScaffold.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local uiController = UIScaffold.makeUIFrameController(getFrame, requestRefreshFn)
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

function UIScaffold.createListPanelScaffold(cfg)
    cfg = cfg or {}
    local module = cfg.module
    local getFrame = cfg.getFrame
    local controller = cfg.controller

    if type(module) ~= "table" then
        error("UIScaffold.createListPanelScaffold: cfg.module must be a table")
    end
    if type(getFrame) ~= "function" then
        error("UIScaffold.createListPanelScaffold: cfg.getFrame must be a function")
    end
    if type(controller) ~= "table" then
        error("UIScaffold.createListPanelScaffold: cfg.controller must be a table")
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

    UIScaffold.bootstrapModuleUi(module, getFrame, requestRefresh, {
        bindToggleHide = cfg.bindToggleHide,
        bindRequestRefresh = cfg.bindRequestRefresh,
    })

    function scaffold:OnLoad(frame)
        frameName = Frames.initModuleFrame(module, frame, frameInitOpts)
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

-- @compat
-- @deprecated use addon.UIScaffold.makeUIFrameController
function Frames.makeUIFrameController(getFrame, requestRefreshFn)
    local UIScaffold = addon.UIScaffold
    if UIScaffold and UIScaffold.makeUIFrameController then
        return UIScaffold.makeUIFrameController(getFrame, requestRefreshFn)
    end
end

-- @compat
-- @deprecated use addon.UIScaffold.bootstrapModuleUi
function Frames.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local UIScaffold = addon.UIScaffold
    if UIScaffold and UIScaffold.bootstrapModuleUi then
        return UIScaffold.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    end
end

-- @compat
-- @deprecated use addon.UIScaffold.createListPanelScaffold
function Frames.createListPanelScaffold(cfg)
    local UIScaffold = addon.UIScaffold
    if UIScaffold and UIScaffold.createListPanelScaffold then
        return UIScaffold.createListPanelScaffold(cfg)
    end
end

function Frames.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
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
