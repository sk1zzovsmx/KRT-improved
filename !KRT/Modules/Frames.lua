-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type = type
local format = string.format

local _G = _G
local function CreateFrame(...)
    return _G.CreateFrame(...)
end

addon.Frames = addon.Frames or {}
local Frames = addon.Frames

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
        local Utils = addon.Utils
        if Utils and Utils.enableDrag then
            Utils.enableDrag(frame, opts.dragButton)
        end
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

function Frames.makeUIFrameController(getFrame, requestRefreshFn)
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

function Frames.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local uiController = Frames.makeUIFrameController(getFrame, requestRefreshFn)
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
