-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

addon.Utils = addon.Utils or {}
local LegacyUtils = addon.Utils

local L = feature.L

local type = type
local format = string.format
local lower = string.lower
local tostring = tostring

local function getStrings()
    return addon.Strings
end

local function getBus()
    return addon.Bus
end

local function getUI()
    return LegacyUtils.UI
end

local function warnDeprecatedCompat(legacyName, ownerPath)
    local state = addon.State
    if not (state and state.debugEnabled == true) then
        return
    end

    state.utilsCompatWarned = state.utilsCompatWarned or {}
    if state.utilsCompatWarned[legacyName] then
        return
    end
    state.utilsCompatWarned[legacyName] = true

    if addon.warn then
        addon:warn("[Compat] LegacyUtils.%s is deprecated; use %s", tostring(legacyName), tostring(ownerPath))
    end
end

-- =========== String helpers  =========== --

function LegacyUtils.ucfirst(value)
    local Strings = getStrings()
    if Strings and Strings.ucfirst then
        return Strings.ucfirst(value)
    end
    return tostring(value or "")
end

-- @compat facade for legacy call-sites.
-- @deprecated use addon.Strings.trimText
function LegacyUtils.trimText(value, allowNil)
    warnDeprecatedCompat("trimText", "addon.Strings.trimText")
    local Strings = getStrings()
    if Strings and Strings.trimText then
        return Strings.trimText(value, allowNil)
    end
    if value == nil then
        return allowNil and nil or ""
    end
    return tostring(value)
end

-- @compat facade for legacy call-sites.
-- @deprecated use addon.Strings.normalizeName
function LegacyUtils.normalizeName(value, allowNil)
    warnDeprecatedCompat("normalizeName", "addon.Strings.normalizeName")
    local Strings = getStrings()
    if Strings and Strings.normalizeName then
        return Strings.normalizeName(value, allowNil)
    end
    return LegacyUtils.trimText(value, allowNil)
end

-- @compat facade for legacy call-sites.
-- @deprecated use addon.Strings.normalizeLower
function LegacyUtils.normalizeLower(value, allowNil)
    warnDeprecatedCompat("normalizeLower", "addon.Strings.normalizeLower")
    local Strings = getStrings()
    if Strings and Strings.normalizeLower then
        return Strings.normalizeLower(value, allowNil)
    end
    local text = LegacyUtils.trimText(value, allowNil)
    if text == nil then
        return nil
    end
    return lower(text)
end

function LegacyUtils.findAchievement(inp)
    local Strings = getStrings()
    if Strings and Strings.findAchievement then
        return Strings.findAchievement(inp)
    end
    return inp and tostring(inp) or ""
end

function LegacyUtils.formatChatMessage(text, prefix, outputFormat, prefixHex)
    local Strings = getStrings()
    if Strings and Strings.formatChatMessage then
        return Strings.formatChatMessage(text, prefix, outputFormat, prefixHex)
    end
    local msgPrefix = prefix or ""
    return format(outputFormat or "%s%s", msgPrefix, tostring(text))
end

-- @compat facade for legacy call-sites.
-- @deprecated use addon.Strings.splitArgs
function LegacyUtils.splitArgs(msg)
    warnDeprecatedCompat("splitArgs", "addon.Strings.splitArgs")
    local Strings = getStrings()
    if Strings and Strings.splitArgs then
        return Strings.splitArgs(msg)
    end
    msg = LegacyUtils.trimText(msg)
    if msg == "" then
        return "", ""
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    return lower(cmd or ""), LegacyUtils.trimText(rest)
end

function LegacyUtils.getItemIdFromLink(itemLink)
    local Strings = getStrings()
    if Strings and Strings.getItemIdFromLink then
        return Strings.getItemIdFromLink(itemLink)
    end
    return nil
end

function LegacyUtils.getItemStringFromLink(itemLink)
    local Strings = getStrings()
    if Strings and Strings.getItemStringFromLink then
        return Strings.getItemStringFromLink(itemLink)
    end
    return nil
end

-- =========== Event bus facade  =========== --

function LegacyUtils.resetInternalCallbackStats()
    local Bus = getBus()
    if Bus and Bus.resetInternalCallbackStats then
        return Bus.resetInternalCallbackStats()
    end
end

function LegacyUtils.dumpInternalCallbackStats(sortBy)
    local Bus = getBus()
    if Bus and Bus.dumpInternalCallbackStats then
        return Bus.dumpInternalCallbackStats(sortBy)
    end
end

-- =========== UI facade  =========== --

function LegacyUtils.enableDrag(frame, dragButton)
    local UI = getUI()
    if UI and UI.enableDrag then
        return UI.enableDrag(frame, dragButton)
    end
end

function LegacyUtils.createRowDrawer(fn)
    local UI = getUI()
    if UI and UI.createRowDrawer then
        return UI.createRowDrawer(fn)
    end
    return function(row, it)
        local rowHeight = (row and row:GetHeight()) or 20
        fn(row, it)
        return rowHeight
    end
end

function LegacyUtils.makeConfirmPopup(key, text, onAccept, cancels)
    local UI = getUI()
    if UI and UI.makeConfirmPopup then
        return UI.makeConfirmPopup(key, text, onAccept, cancels)
    end
end

function LegacyUtils.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    local UI = getUI()
    if UI and UI.makeEditBoxPopup then
        return UI.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    end
end

function LegacyUtils.setFrameTitle(frameOrName, titleText, titleFormat)
    local UI = getUI()
    if UI and UI.setFrameTitle then
        return UI.setFrameTitle(frameOrName, titleText, titleFormat)
    end
end

function LegacyUtils.resetEditBox(editBox, hide)
    local UI = getUI()
    if UI and UI.resetEditBox then
        return UI.resetEditBox(editBox, hide)
    end
end

function LegacyUtils.setEditBoxValue(editBox, value, focus)
    local UI = getUI()
    if UI and UI.setEditBoxValue then
        return UI.setEditBoxValue(editBox, value, focus)
    end
end

function LegacyUtils.setShown(frame, show)
    local UI = getUI()
    if UI and UI.setShown then
        return UI.setShown(frame, show)
    end
end

function LegacyUtils.makeEventDrivenRefresher(targetOrGetter, updateFn)
    local UI = getUI()
    if UI and UI.makeEventDrivenRefresher then
        return UI.makeEventDrivenRefresher(targetOrGetter, updateFn)
    end
    return function()
    end
end

function LegacyUtils.makeFrameGetter(globalFrameName)
    local UI = getUI()
    if UI and UI.makeFrameGetter then
        return UI.makeFrameGetter(globalFrameName)
    end
    return function()
        return _G[globalFrameName]
    end
end

function LegacyUtils.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    local UI = getUI()
    if UI and UI.bindEditBoxHandlers then
        return UI.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    end
end

function LegacyUtils.makeUIFrameController(getFrame, requestRefreshFn)
    local UI = getUI()
    if UI and UI.makeUIFrameController then
        return UI.makeUIFrameController(getFrame, requestRefreshFn)
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

function LegacyUtils.toggle(frame)
    local UI = getUI()
    if UI and UI.toggle then
        return UI.toggle(frame)
    end
end

function LegacyUtils.hideFrame(frame, onHide)
    local UI = getUI()
    if UI and UI.hideFrame then
        return UI.hideFrame(frame, onHide)
    end
end

function LegacyUtils.toggleHighlight(frame, cond)
    local UI = getUI()
    if UI and UI.toggleHighlight then
        return UI.toggleHighlight(frame, cond)
    end
end

function LegacyUtils.setRowFocused(row, cond)
    local UI = getUI()
    if UI and UI.setRowFocused then
        return UI.setRowFocused(row, cond)
    end
end

function LegacyUtils.setButtonCount(btn, baseText, n)
    local UI = getUI()
    if UI and UI.setButtonCount then
        return UI.setButtonCount(btn, baseText, n)
    end
end

function LegacyUtils.setText(frame, str1, str2, cond)
    local UI = getUI()
    if UI and UI.setText then
        return UI.setText(frame, str1, str2, cond)
    end
end

function LegacyUtils.getNamedFramePart(frameName, suffix)
    local UI = getUI()
    if UI and UI.getNamedFramePart then
        return UI.getNamedFramePart(frameName, suffix)
    end
    return nil
end

function LegacyUtils.enableDisableNamedPart(frameName, suffix, cond)
    local UI = getUI()
    if UI and UI.enableDisableNamedPart then
        return UI.enableDisableNamedPart(frameName, suffix, cond)
    end
    return nil
end

function LegacyUtils.showHideNamedPart(frameName, suffix, cond)
    local UI = getUI()
    if UI and UI.showHideNamedPart then
        return UI.showHideNamedPart(frameName, suffix, cond)
    end
    return nil
end

function LegacyUtils.setTextNamedPart(frameName, suffix, str1, str2, cond)
    local UI = getUI()
    if UI and UI.setTextNamedPart then
        return UI.setTextNamedPart(frameName, suffix, str1, str2, cond)
    end
    return nil
end

function LegacyUtils.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    local UI = getUI()
    if UI and UI.updateModeTextNamedPart then
        return UI.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    end
    return lastMode
end

-- =========== Tooltip facade  =========== --

function addon:SetTooltip(frame, text, anchor, title)
    local Frames = addon.Frames
    if Frames and Frames.setTooltip then
        return Frames.setTooltip(frame, text, anchor, title)
    end
end

-- =========== Color utilities  =========== --

function LegacyUtils.normalizeHexColor(color)
    local Colors = addon.Colors
    if Colors and Colors.normalizeHexColor then
        return Colors.normalizeHexColor(color)
    end
    return "ffffffff"
end

function LegacyUtils.getClassColor(className)
    local Colors = addon.Colors
    if Colors and Colors.getClassColor then
        return Colors.getClassColor(className)
    end
    return 1, 1, 1
end

-- =========== Chat + comms helpers  =========== --

function LegacyUtils.sync(prefix, msg)
    local Comms = addon.Comms
    if Comms and Comms.sync then
        return Comms.sync(prefix, msg)
    end
end

function LegacyUtils.chat(msg, channel, language, target, bypass)
    local Comms = addon.Comms
    if Comms and Comms.chat then
        return Comms.chat(msg, channel, language, target, bypass)
    end
end

function LegacyUtils.whisper(target, msg)
    local Comms = addon.Comms
    if Comms and Comms.whisper then
        return Comms.whisper(target, msg)
    end
end

-- =========== Time helpers  =========== --

function LegacyUtils.sec2clock(seconds)
    local Time = addon.Time
    if Time and Time.sec2clock then
        return Time.sec2clock(seconds)
    end
    return "00:00:00"
end

function LegacyUtils.isRaidInstance()
    local Time = addon.Time
    if Time and Time.isRaidInstance then
        return Time.isRaidInstance()
    end
    return false
end

function LegacyUtils.getDifficulty()
    local Time = addon.Time
    if Time and Time.getDifficulty then
        return Time.getDifficulty()
    end
    return nil
end

function LegacyUtils.getCurrentTime(server)
    local Time = addon.Time
    if Time and Time.getCurrentTime then
        return Time.getCurrentTime(server)
    end
    return time()
end

function LegacyUtils.getServerOffset()
    local Time = addon.Time
    if Time and Time.getServerOffset then
        return Time.getServerOffset()
    end
    return 0
end

-- =========== Base64 encode/decode  =========== --

function LegacyUtils.encode(data)
    local Base64 = addon.Base64
    if Base64 and Base64.encode then
        return Base64.encode(data)
    end
    return data
end

function LegacyUtils.decode(data)
    local Base64 = addon.Base64
    if Base64 and Base64.decode then
        return Base64.decode(data)
    end
    return data
end
