-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.UI = Utils.UI or {}
local UI = Utils.UI

-- @compat
-- @deprecated use addon.Frames.enableDrag
function UI.enableDrag(frame, dragButton)
    local Frames = addon.Frames
    if Frames and Frames.enableDrag then
        return Frames.enableDrag(frame, dragButton)
    end
end

-- @compat
-- @deprecated use addon.ListController.createRowDrawer
function UI.createRowDrawer(fn)
    local ListController = addon.ListController
    if ListController and ListController.createRowDrawer then
        return ListController.createRowDrawer(fn)
    end
end

-- @compat
-- @deprecated use addon.ListController.makeListController
function UI.makeListController(cfg)
    local ListController = addon.ListController
    if ListController and ListController.makeListController then
        return ListController.makeListController(cfg)
    end
end

-- @compat
-- @deprecated use addon.ListController.bindListController
function UI.bindListController(module, controller)
    local ListController = addon.ListController
    if ListController and ListController.bindListController then
        return ListController.bindListController(module, controller)
    end
end

-- @compat
-- @deprecated use addon.Frames.makeConfirmPopup
function UI.makeConfirmPopup(key, text, onAccept, cancels)
    local Frames = addon.Frames
    if Frames and Frames.makeConfirmPopup then
        return Frames.makeConfirmPopup(key, text, onAccept, cancels)
    end
end

-- @compat
-- @deprecated use addon.Frames.makeEditBoxPopup
function UI.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    local Frames = addon.Frames
    if Frames and Frames.makeEditBoxPopup then
        return Frames.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    end
end

-- @compat
-- @deprecated use addon.Frames.setFrameTitle
function UI.setFrameTitle(frameOrName, titleText, titleFormat)
    local Frames = addon.Frames
    if Frames and Frames.setFrameTitle then
        return Frames.setFrameTitle(frameOrName, titleText, titleFormat)
    end
end

-- @compat
-- @deprecated use addon.Frames.resetEditBox
function UI.resetEditBox(editBox, hide)
    local Frames = addon.Frames
    if Frames and Frames.resetEditBox then
        return Frames.resetEditBox(editBox, hide)
    end
end

-- @compat
-- @deprecated use addon.Frames.setEditBoxValue
function UI.setEditBoxValue(editBox, value, focus)
    local Frames = addon.Frames
    if Frames and Frames.setEditBoxValue then
        return Frames.setEditBoxValue(editBox, value, focus)
    end
end

-- @compat
-- @deprecated use addon.Frames.setShown
function UI.setShown(frame, show)
    local Frames = addon.Frames
    if Frames and Frames.setShown then
        return Frames.setShown(frame, show)
    end
end

-- @compat
-- @deprecated use addon.Frames.makeEventDrivenRefresher
function UI.makeEventDrivenRefresher(targetOrGetter, updateFn)
    local Frames = addon.Frames
    if Frames and Frames.makeEventDrivenRefresher then
        return Frames.makeEventDrivenRefresher(targetOrGetter, updateFn)
    end
end

-- @compat
-- @deprecated use addon.Frames.makeFrameGetter
function UI.makeFrameGetter(globalFrameName)
    local Frames = addon.Frames
    if Frames and Frames.makeFrameGetter then
        return Frames.makeFrameGetter(globalFrameName)
    end
end

-- @compat
-- @deprecated use addon.Frames.initModuleFrame
function UI.initModuleFrame(module, frame, opts)
    local Frames = addon.Frames
    if Frames and Frames.initModuleFrame then
        return Frames.initModuleFrame(module, frame, opts)
    end
end

-- @compat
-- @deprecated use addon.UIScaffold.bootstrapModuleUi
function UI.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local UIScaffold = addon.UIScaffold
    if UIScaffold and UIScaffold.bootstrapModuleUi then
        return UIScaffold.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    end
end

-- @compat
-- @deprecated use addon.UIScaffold.createListPanelScaffold
function UI.createListPanelScaffold(cfg)
    local UIScaffold = addon.UIScaffold
    if UIScaffold and UIScaffold.createListPanelScaffold then
        return UIScaffold.createListPanelScaffold(cfg)
    end
end

-- @compat
-- @deprecated use addon.Frames.bindEditBoxHandlers
function UI.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    local Frames = addon.Frames
    if Frames and Frames.bindEditBoxHandlers then
        return Frames.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    end
end

-- @compat
-- @deprecated use addon.UIScaffold.makeUIFrameController
function UI.makeUIFrameController(getFrame, requestRefreshFn)
    local UIScaffold = addon.UIScaffold
    if UIScaffold and UIScaffold.makeUIFrameController then
        return UIScaffold.makeUIFrameController(getFrame, requestRefreshFn)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.enableDisable
function UI.enableDisable(frame, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.enableDisable then
        return UIPrimitives.enableDisable(frame, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.toggle
function UI.toggle(frame)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.toggle then
        return UIPrimitives.toggle(frame)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.hideFrame
function UI.hideFrame(frame, onHide)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.hideFrame then
        return UIPrimitives.hideFrame(frame, onHide)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.showHide
function UI.showHide(frame, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.showHide then
        return UIPrimitives.showHide(frame, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.toggleHighlight
function UI.toggleHighlight(frame, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.toggleHighlight then
        return UIPrimitives.toggleHighlight(frame, cond)
    end
end

-- @compat
-- @deprecated use addon.UIRowVisuals.ensureRowVisuals
function UI.ensureRowVisuals(row)
    local UIRowVisuals = addon.UIRowVisuals
    if UIRowVisuals and UIRowVisuals.ensureRowVisuals then
        return UIRowVisuals.ensureRowVisuals(row)
    end
end

-- @compat
-- @deprecated use addon.UIRowVisuals.setRowSelected
function UI.setRowSelected(row, cond)
    local UIRowVisuals = addon.UIRowVisuals
    if UIRowVisuals and UIRowVisuals.setRowSelected then
        return UIRowVisuals.setRowSelected(row, cond)
    end
end

-- @compat
-- @deprecated use addon.UIRowVisuals.setRowFocused
function UI.setRowFocused(row, cond)
    local UIRowVisuals = addon.UIRowVisuals
    if UIRowVisuals and UIRowVisuals.setRowFocused then
        return UIRowVisuals.setRowFocused(row, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.setButtonCount
function UI.setButtonCount(btn, baseText, n)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.setButtonCount then
        return UIPrimitives.setButtonCount(btn, baseText, n)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.setText
function UI.setText(frame, str1, str2, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.setText then
        return UIPrimitives.setText(frame, str1, str2, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.getNamedFramePart
function UI.getNamedFramePart(frameName, suffix)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.getNamedFramePart then
        return UIPrimitives.getNamedFramePart(frameName, suffix)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.enableDisableNamedPart
function UI.enableDisableNamedPart(frameName, suffix, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.enableDisableNamedPart then
        return UIPrimitives.enableDisableNamedPart(frameName, suffix, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.showHideNamedPart
function UI.showHideNamedPart(frameName, suffix, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.showHideNamedPart then
        return UIPrimitives.showHideNamedPart(frameName, suffix, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.setTextNamedPart
function UI.setTextNamedPart(frameName, suffix, str1, str2, cond)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.setTextNamedPart then
        return UIPrimitives.setTextNamedPart(frameName, suffix, str1, str2, cond)
    end
end

-- @compat
-- @deprecated use addon.UIPrimitives.updateModeTextNamedPart
function UI.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    local UIPrimitives = addon.UIPrimitives
    if UIPrimitives and UIPrimitives.updateModeTextNamedPart then
        return UIPrimitives.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    end
    return lastMode
end
