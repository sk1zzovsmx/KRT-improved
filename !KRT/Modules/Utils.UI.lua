-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type = type
local _G = _G

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.UI = Utils.UI or {}
local UI = Utils.UI

-- Enable basic drag-to-move behavior on a frame.
--
-- Intentionally kept in Lua (not XML) so window behavior is standardized
-- without embedding logic into Templates.xml.
function UI.enableDrag(frame, dragButton)
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

--
-- createRowDrawer(fn)
--
-- Wraps a row drawing function with logic to cache and return the row height.
-- Each invocation of this helper returns a new closure with its own cached
-- height.
function UI.createRowDrawer(fn)
    local ListController = addon.ListController
    if ListController and ListController.createRowDrawer then
        return ListController.createRowDrawer(fn)
    end
    return function(row, it)
        local rowHeight = (row and row:GetHeight()) or 20
        fn(row, it)
        return rowHeight
    end
end

function UI.makeListController(cfg)
    local ListController = addon.ListController
    if ListController and ListController.makeListController then
        return ListController.makeListController(cfg)
    end
    return nil
end

function UI.bindListController(module, controller)
    local ListController = addon.ListController
    if ListController and ListController.bindListController then
        return ListController.bindListController(module, controller)
    end
    module.OnLoad = function(_, frame)
        controller:OnLoad(frame)
    end
    module.Fetch = function()
        controller:Fetch()
    end
    module.Sort = function(_, key)
        controller:Sort(key)
    end
end

function UI.makeConfirmPopup(key, text, onAccept, cancels)
    local Frames = addon.Frames
    if Frames and Frames.makeConfirmPopup then
        return Frames.makeConfirmPopup(key, text, onAccept, cancels)
    end
end

function UI.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    local Frames = addon.Frames
    if Frames and Frames.makeEditBoxPopup then
        return Frames.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    end
end

function UI.setFrameTitle(frameOrName, titleText, titleFormat)
    local Frames = addon.Frames
    if Frames and Frames.setFrameTitle then
        return Frames.setFrameTitle(frameOrName, titleText, titleFormat)
    end
end

function UI.resetEditBox(editBox, hide)
    local Frames = addon.Frames
    if Frames and Frames.resetEditBox then
        return Frames.resetEditBox(editBox, hide)
    end
end

function UI.setEditBoxValue(editBox, value, focus)
    local Frames = addon.Frames
    if Frames and Frames.setEditBoxValue then
        return Frames.setEditBoxValue(editBox, value, focus)
    end
end

function UI.setShown(frame, show)
    local Frames = addon.Frames
    if Frames and Frames.setShown then
        return Frames.setShown(frame, show)
    end
end

function UI.makeEventDrivenRefresher(targetOrGetter, updateFn)
    local Frames = addon.Frames
    if Frames and Frames.makeEventDrivenRefresher then
        return Frames.makeEventDrivenRefresher(targetOrGetter, updateFn)
    end
    return function()
    end
end

function UI.makeFrameGetter(globalFrameName)
    local Frames = addon.Frames
    if Frames and Frames.makeFrameGetter then
        return Frames.makeFrameGetter(globalFrameName)
    end
    return function()
        return _G[globalFrameName]
    end
end

function UI.initModuleFrame(module, frame, opts)
    local Frames = addon.Frames
    if Frames and Frames.initModuleFrame then
        return Frames.initModuleFrame(module, frame, opts)
    end
    if module then
        module.frame = frame
    end
    return frame and frame:GetName() or nil
end

function UI.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local Frames = addon.Frames
    if Frames and Frames.bootstrapModuleUi then
        return Frames.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    end
    return UI.makeUIFrameController(getFrame, requestRefreshFn)
end

function UI.createListPanelScaffold(cfg)
    local Frames = addon.Frames
    if Frames and Frames.createListPanelScaffold then
        return Frames.createListPanelScaffold(cfg)
    end
    return nil
end

function UI.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    local Frames = addon.Frames
    if Frames and Frames.bindEditBoxHandlers then
        return Frames.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    end
end

function UI.makeUIFrameController(getFrame, requestRefreshFn)
    local Frames = addon.Frames
    if Frames and Frames.makeUIFrameController then
        return Frames.makeUIFrameController(getFrame, requestRefreshFn)
    end
    return {
        Toggle = function(self)
            local frame = getFrame()
            if not frame then
                return
            end
            if frame:IsShown() then
                frame:Hide()
            else
                if requestRefreshFn then
                    requestRefreshFn()
                end
                frame:Show()
            end
        end,
        Hide = function(self)
            local frame = getFrame()
            if frame then
                frame:Hide()
            end
        end,
        Show = function(self)
            local frame = getFrame()
            if frame then
                if requestRefreshFn then
                    requestRefreshFn()
                end
                frame:Show()
            end
        end,
    }
end

function UI.enableDisable(frame, cond)
    if not frame then
        return
    end
    if cond and frame:IsEnabled() == 0 then
        frame:Enable()
    elseif not cond and frame:IsEnabled() == 1 then
        frame:Disable()
    end
end

function UI.toggle(frame)
    if not frame then
        return
    end
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
    end
end

function UI.hideFrame(frame, onHide)
    if frame and frame:IsShown() then
        if onHide then
            onHide()
        end
        frame:Hide()
    end
end

function UI.showHide(frame, cond)
    if not frame then
        return
    end
    if cond and not frame:IsShown() then
        frame:Show()
    elseif not cond and frame:IsShown() then
        frame:Hide()
    end
end

function UI.toggleHighlight(frame, cond)
    if not frame then
        return
    end
    if cond then
        frame:LockHighlight()
    else
        frame:UnlockHighlight()
    end
end

local function ensureRowVisuals(row)
    if not row or row._krtSelTex then
        return
    end

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints(row)
    sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD")
    sel:SetVertexColor(0.20, 0.60, 1.00, 0.52)
    sel:Hide()
    row._krtSelTex = sel

    local focus = row:CreateTexture(nil, "ARTWORK")
    focus:SetAllPoints(row)
    focus:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    focus:SetBlendMode("ADD")
    focus:SetVertexColor(0.20, 0.60, 1.00, 0.72)
    focus:Hide()
    row._krtFocusTex = focus

    local pushed = row:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints(row)
    pushed:SetTexture(1, 1, 1, 0.08)
    row:SetPushedTexture(pushed)
end

function UI.ensureRowVisuals(row)
    ensureRowVisuals(row)
end

function UI.setRowSelected(row, cond)
    ensureRowVisuals(row)
    if not row or not row._krtSelTex then
        return
    end
    if cond then
        row._krtSelTex:Show()
    else
        row._krtSelTex:Hide()
    end
end

function UI.setRowFocused(row, cond)
    ensureRowVisuals(row)
    local texture = row and row._krtFocusTex
    if not texture then
        return
    end
    if cond then
        texture:Show()
    else
        texture:Hide()
    end
end

function UI.setButtonCount(btn, baseText, n)
    if not btn then
        return
    end
    if not btn._krtBaseText then
        btn._krtBaseText = baseText or btn:GetText() or ""
    end
    local base = baseText or btn._krtBaseText or ""
    if n and n > 1 then
        btn:SetText(("%s (%d)"):format(base, n))
    else
        btn:SetText(base)
    end
end

function UI.setText(frame, str1, str2, cond)
    if not frame then
        return
    end
    if cond then
        frame:SetText(str1)
    else
        frame:SetText(str2)
    end
end

function UI.getNamedFramePart(frameName, suffix)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end
    if type(suffix) ~= "string" or suffix == "" then
        return nil
    end
    return _G[frameName .. suffix]
end

function UI.enableDisableNamedPart(frameName, suffix, cond)
    local frame = UI.getNamedFramePart(frameName, suffix)
    if frame then
        UI.enableDisable(frame, cond)
    end
    return frame
end

function UI.showHideNamedPart(frameName, suffix, cond)
    local frame = UI.getNamedFramePart(frameName, suffix)
    if frame then
        UI.showHide(frame, cond)
    end
    return frame
end

function UI.setTextNamedPart(frameName, suffix, str1, str2, cond)
    local frame = UI.getNamedFramePart(frameName, suffix)
    if frame then
        UI.setText(frame, str1, str2, cond)
    end
    return frame
end

function UI.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    if mode ~= lastMode then
        UI.setTextNamedPart(frameName, suffix, str1, str2, mode)
        return mode
    end
    return lastMode
end
