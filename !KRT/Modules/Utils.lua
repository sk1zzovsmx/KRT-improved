-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

local L = feature.L

local type = type
local format = string.format
local lower = string.lower
local tostring = tostring
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitIsGroupLeader = _G.UnitIsGroupLeader

local function getStrings()
    return addon.Strings
end

local function getOptions()
    return Utils.Options
end

local function getRaidState()
    return Utils.RaidState
end

local function getEventBusCompat()
    return Utils.EventBusCompat
end

local function getUI()
    return Utils.UI
end

local function getTooltip()
    return Utils.Tooltip
end

-- =========== Debug/state helpers  =========== --

function Utils.isDebugEnabled()
    local Options = getOptions()
    if Options and Options.isDebugEnabled then
        return Options.isDebugEnabled()
    end
    return addon and addon.State and addon.State.debugEnabled == true
end

function Utils.applyDebugSetting(enabled)
    local Options = getOptions()
    if Options and Options.applyDebugSetting then
        return Options.applyDebugSetting(enabled)
    end

    local state = addon.State
    state.debugEnabled = enabled and true or false

    local levels = addon and addon.Debugger and addon.Debugger.logLevels
    local level = enabled and (levels and levels.DEBUG) or (levels and levels.INFO)
    if level and addon and addon.SetLogLevel then
        addon:SetLogLevel(level)
    end
end

function Utils.setOption(key, value)
    local Options = getOptions()
    if Options and Options.setOption then
        return Options.setOption(key, value)
    end

    if type(key) ~= "string" or key == "" then
        return false
    end

    local options = addon and addon.options
    if type(options) ~= "table" then
        if type(KRT_Options) == "table" then
            options = KRT_Options
        else
            options = {}
            KRT_Options = options
        end
        addon.options = options
    end

    options[key] = value

    if type(KRT_Options) == "table" and KRT_Options ~= options then
        KRT_Options[key] = value
    end

    return true
end

-- =========== Raid/state helpers  =========== --

function Utils.getPlayerName()
    local RaidState = getRaidState()
    if RaidState and RaidState.getPlayerName then
        return RaidState.getPlayerName()
    end
    local state = addon.State
    state.player = state.player or {}
    local name = state.player.name
        or addon.UnitFullName("player")
    state.player.name = name
    return name
end

function Utils.getRaid(raidNum)
    local RaidState = getRaidState()
    if RaidState and RaidState.getRaid then
        return RaidState.getRaid(raidNum)
    end
    if raidNum == nil then
        local core = addon.Core
        if core and core.getCurrentRaid then
            raidNum = core.getCurrentRaid()
        else
            local state = addon.State
            raidNum = state and state.currentRaid or nil
        end
    end
    if not raidNum then
        return nil, nil
    end
    local raids = KRT_Raids
    local raid = raids and raids[raidNum] or nil
    return raid, raidNum
end

Utils.GetRaid = Utils.getRaid

function Utils.getRealmName()
    local RaidState = getRaidState()
    if RaidState and RaidState.getRealmName then
        return RaidState.getRealmName()
    end
    local realm = GetRealmName()
    if type(realm) ~= "string" then
        return ""
    end
    return realm
end

function Utils.getUnitRank(unit, fallback)
    local RaidState = getRaidState()
    if RaidState and RaidState.getUnitRank then
        return RaidState.getUnitRank(unit, fallback)
    end

    local groupLeader = (addon and addon.UnitIsGroupLeader) or UnitIsGroupLeader
    local groupAssistant = (addon and addon.UnitIsGroupAssistant) or UnitIsGroupAssistant

    if groupLeader and groupLeader(unit) then
        return 2
    end
    if groupAssistant and groupAssistant(unit) then
        return 1
    end
    return fallback or 0
end

-- =========== String helpers  =========== --

function Utils.ucfirst(value)
    local Strings = getStrings()
    if Strings and Strings.ucfirst then
        return Strings.ucfirst(value)
    end
    return tostring(value or "")
end

function Utils.trimText(value, allowNil)
    local Strings = getStrings()
    if Strings and Strings.trimText then
        return Strings.trimText(value, allowNil)
    end
    if value == nil then
        return allowNil and nil or ""
    end
    return tostring(value)
end

function Utils.normalizeName(value, allowNil)
    local Strings = getStrings()
    if Strings and Strings.normalizeName then
        return Strings.normalizeName(value, allowNil)
    end
    return Utils.trimText(value, allowNil)
end

function Utils.normalizeLower(value, allowNil)
    local Strings = getStrings()
    if Strings and Strings.normalizeLower then
        return Strings.normalizeLower(value, allowNil)
    end
    local text = Utils.trimText(value, allowNil)
    if text == nil then
        return nil
    end
    return lower(text)
end

function Utils.findAchievement(inp)
    local Strings = getStrings()
    if Strings and Strings.findAchievement then
        return Strings.findAchievement(inp)
    end
    return inp and tostring(inp) or ""
end

function Utils.formatChatMessage(text, prefix, outputFormat, prefixHex)
    local Strings = getStrings()
    if Strings and Strings.formatChatMessage then
        return Strings.formatChatMessage(text, prefix, outputFormat, prefixHex)
    end
    local msgPrefix = prefix or ""
    return format(outputFormat or "%s%s", msgPrefix, tostring(text))
end

function Utils.splitArgs(msg)
    local Strings = getStrings()
    if Strings and Strings.splitArgs then
        return Strings.splitArgs(msg)
    end
    msg = Utils.trimText(msg)
    if msg == "" then
        return "", ""
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    return lower(cmd or ""), Utils.trimText(rest)
end

function Utils.getItemIdFromLink(itemLink)
    local Strings = getStrings()
    if Strings and Strings.getItemIdFromLink then
        return Strings.getItemIdFromLink(itemLink)
    end
    return nil
end

function Utils.getItemStringFromLink(itemLink)
    local Strings = getStrings()
    if Strings and Strings.getItemStringFromLink then
        return Strings.getItemStringFromLink(itemLink)
    end
    return nil
end

-- =========== Event bus facade  =========== --

function Utils.registerCallback(eventName, callback)
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.registerCallback then
        return EventBusCompat.registerCallback(eventName, callback)
    end
    error(L.StrCbErrUsage)
end

function Utils.unregisterCallback(handle)
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.unregisterCallback then
        return EventBusCompat.unregisterCallback(handle)
    end
end

function Utils.triggerEvent(eventName, ...)
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.triggerEvent then
        return EventBusCompat.triggerEvent(eventName, ...)
    end
end

function Utils.registerCallbacks(names, callback)
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.registerCallbacks then
        return EventBusCompat.registerCallbacks(names, callback)
    end
end

function Utils.getInternalCallbackStats()
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.getInternalCallbackStats then
        return EventBusCompat.getInternalCallbackStats()
    end
    return {}
end

function Utils.resetInternalCallbackStats()
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.resetInternalCallbackStats then
        return EventBusCompat.resetInternalCallbackStats()
    end
end

function Utils.dumpInternalCallbackStats(sortBy)
    local EventBusCompat = getEventBusCompat()
    if EventBusCompat and EventBusCompat.dumpInternalCallbackStats then
        return EventBusCompat.dumpInternalCallbackStats(sortBy)
    end
end

-- =========== UI facade  =========== --

function Utils.enableDrag(frame, dragButton)
    local UI = getUI()
    if UI and UI.enableDrag then
        return UI.enableDrag(frame, dragButton)
    end
end

function Utils.createRowDrawer(fn)
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

function Utils.makeListController(cfg)
    local UI = getUI()
    if UI and UI.makeListController then
        return UI.makeListController(cfg)
    end
    return nil
end

function Utils.bindListController(module, controller)
    local UI = getUI()
    if UI and UI.bindListController then
        return UI.bindListController(module, controller)
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

function Utils.makeConfirmPopup(key, text, onAccept, cancels)
    local UI = getUI()
    if UI and UI.makeConfirmPopup then
        return UI.makeConfirmPopup(key, text, onAccept, cancels)
    end
end

function Utils.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    local UI = getUI()
    if UI and UI.makeEditBoxPopup then
        return UI.makeEditBoxPopup(key, text, onAccept, onShow, validate)
    end
end

function Utils.setFrameTitle(frameOrName, titleText, titleFormat)
    local UI = getUI()
    if UI and UI.setFrameTitle then
        return UI.setFrameTitle(frameOrName, titleText, titleFormat)
    end
end

function Utils.resetEditBox(editBox, hide)
    local UI = getUI()
    if UI and UI.resetEditBox then
        return UI.resetEditBox(editBox, hide)
    end
end

function Utils.setEditBoxValue(editBox, value, focus)
    local UI = getUI()
    if UI and UI.setEditBoxValue then
        return UI.setEditBoxValue(editBox, value, focus)
    end
end

function Utils.setShown(frame, show)
    local UI = getUI()
    if UI and UI.setShown then
        return UI.setShown(frame, show)
    end
end

function Utils.makeEventDrivenRefresher(targetOrGetter, updateFn)
    local UI = getUI()
    if UI and UI.makeEventDrivenRefresher then
        return UI.makeEventDrivenRefresher(targetOrGetter, updateFn)
    end
    return function()
    end
end

function Utils.makeFrameGetter(globalFrameName)
    local UI = getUI()
    if UI and UI.makeFrameGetter then
        return UI.makeFrameGetter(globalFrameName)
    end
    return function()
        return _G[globalFrameName]
    end
end

function Utils.initModuleFrame(module, frame, opts)
    local UI = getUI()
    if UI and UI.initModuleFrame then
        return UI.initModuleFrame(module, frame, opts)
    end
    if module then
        module.frame = frame
    end
    return frame and frame:GetName() or nil
end

function Utils.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    local UI = getUI()
    if UI and UI.bootstrapModuleUi then
        return UI.bootstrapModuleUi(module, getFrame, requestRefreshFn, opts)
    end
    return Utils.makeUIFrameController(getFrame, requestRefreshFn)
end

function Utils.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    local UI = getUI()
    if UI and UI.bindEditBoxHandlers then
        return UI.bindEditBoxHandlers(frameName, specs, requestRefreshFn)
    end
end

function Utils.makeUIFrameController(getFrame, requestRefreshFn)
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

function Utils.enableDisable(frame, cond)
    local UI = getUI()
    if UI and UI.enableDisable then
        return UI.enableDisable(frame, cond)
    end
end

function Utils.toggle(frame)
    local UI = getUI()
    if UI and UI.toggle then
        return UI.toggle(frame)
    end
end

function Utils.hideFrame(frame, onHide)
    local UI = getUI()
    if UI and UI.hideFrame then
        return UI.hideFrame(frame, onHide)
    end
end

function Utils.showHide(frame, cond)
    local UI = getUI()
    if UI and UI.showHide then
        return UI.showHide(frame, cond)
    end
end

function Utils.toggleHighlight(frame, cond)
    local UI = getUI()
    if UI and UI.toggleHighlight then
        return UI.toggleHighlight(frame, cond)
    end
end

function Utils.ensureRowVisuals(row)
    local UI = getUI()
    if UI and UI.ensureRowVisuals then
        return UI.ensureRowVisuals(row)
    end
end

function Utils.setRowSelected(row, cond)
    local UI = getUI()
    if UI and UI.setRowSelected then
        return UI.setRowSelected(row, cond)
    end
end

function Utils.setRowFocused(row, cond)
    local UI = getUI()
    if UI and UI.setRowFocused then
        return UI.setRowFocused(row, cond)
    end
end

function Utils.setButtonCount(btn, baseText, n)
    local UI = getUI()
    if UI and UI.setButtonCount then
        return UI.setButtonCount(btn, baseText, n)
    end
end

function Utils.setText(frame, str1, str2, cond)
    local UI = getUI()
    if UI and UI.setText then
        return UI.setText(frame, str1, str2, cond)
    end
end

function Utils.getNamedFramePart(frameName, suffix)
    local UI = getUI()
    if UI and UI.getNamedFramePart then
        return UI.getNamedFramePart(frameName, suffix)
    end
    return nil
end

function Utils.enableDisableNamedPart(frameName, suffix, cond)
    local UI = getUI()
    if UI and UI.enableDisableNamedPart then
        return UI.enableDisableNamedPart(frameName, suffix, cond)
    end
    return nil
end

function Utils.showHideNamedPart(frameName, suffix, cond)
    local UI = getUI()
    if UI and UI.showHideNamedPart then
        return UI.showHideNamedPart(frameName, suffix, cond)
    end
    return nil
end

function Utils.setTextNamedPart(frameName, suffix, str1, str2, cond)
    local UI = getUI()
    if UI and UI.setTextNamedPart then
        return UI.setTextNamedPart(frameName, suffix, str1, str2, cond)
    end
    return nil
end

function Utils.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    local UI = getUI()
    if UI and UI.updateModeTextNamedPart then
        return UI.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    end
    return lastMode
end

-- =========== Tooltip facade  =========== --

function addon:SetTooltip(frame, text, anchor, title)
    local Tooltip = getTooltip()
    if Tooltip and Tooltip.setTooltip then
        return Tooltip.setTooltip(frame, text, anchor, title)
    end
end

function Utils.warmItemCache(itemLink)
    local Tooltip = getTooltip()
    if Tooltip and Tooltip.warmItemCache then
        return Tooltip.warmItemCache(itemLink)
    end
end

function Utils.isBagItemSoulbound(bag, slot)
    local Tooltip = getTooltip()
    if Tooltip and Tooltip.isBagItemSoulbound then
        return Tooltip.isBagItemSoulbound(bag, slot)
    end
    return false
end

-- =========== Color utilities  =========== --

function Utils.normalizeHexColor(color)
    local Colors = addon.Colors
    if Colors and Colors.normalizeHexColor then
        return Colors.normalizeHexColor(color)
    end
    return "ffffffff"
end

function Utils.getClassColor(className)
    local Colors = addon.Colors
    if Colors and Colors.getClassColor then
        return Colors.getClassColor(className)
    end
    return 1, 1, 1
end

-- =========== Multi-select utility (reusable)  =========== --

function Utils.multiSelectInit(contextKey)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectInit then
        return MultiSelect.multiSelectInit(contextKey)
    end
    return nil
end

function Utils.multiSelectClear(contextKey)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectClear then
        return MultiSelect.multiSelectClear(contextKey)
    end
    return nil
end

function Utils.multiSelectToggle(contextKey, id, isMulti, allowDeselect)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectToggle then
        return MultiSelect.multiSelectToggle(contextKey, id, isMulti, allowDeselect)
    end
    return nil, 0
end

function Utils.multiSelectSetAnchor(contextKey, id)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectSetAnchor then
        return MultiSelect.multiSelectSetAnchor(contextKey, id)
    end
    return nil
end

function Utils.multiSelectGetAnchor(contextKey)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectGetAnchor then
        return MultiSelect.multiSelectGetAnchor(contextKey)
    end
    return nil
end

function Utils.multiSelectRange(contextKey, ordered, id, isAdd)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectRange then
        return MultiSelect.multiSelectRange(contextKey, ordered, id, isAdd)
    end
    return nil, 0
end

function Utils.multiSelectIsSelected(contextKey, id)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectIsSelected then
        return MultiSelect.multiSelectIsSelected(contextKey, id)
    end
    return false
end

function Utils.multiSelectCount(contextKey)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectCount then
        return MultiSelect.multiSelectCount(contextKey)
    end
    return 0
end

function Utils.multiSelectGetVersion(contextKey)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectGetVersion then
        return MultiSelect.multiSelectGetVersion(contextKey)
    end
    return 0
end

function Utils.multiSelectGetSelected(contextKey)
    local MultiSelect = addon.MultiSelect
    if MultiSelect and MultiSelect.multiSelectGetSelected then
        return MultiSelect.multiSelectGetSelected(contextKey)
    end
    return {}
end

Utils.MultiSelect_Init = Utils.multiSelectInit
Utils.MultiSelect_Clear = Utils.multiSelectClear
Utils.MultiSelect_Toggle = Utils.multiSelectToggle
Utils.MultiSelect_SetAnchor = Utils.multiSelectSetAnchor
Utils.MultiSelect_GetAnchor = Utils.multiSelectGetAnchor
Utils.MultiSelect_Range = Utils.multiSelectRange
Utils.MultiSelect_IsSelected = Utils.multiSelectIsSelected
Utils.MultiSelect_Count = Utils.multiSelectCount
Utils.MultiSelect_GetVersion = Utils.multiSelectGetVersion
Utils.MultiSelect_GetSelected = Utils.multiSelectGetSelected

-- =========== Chat + comms helpers  =========== --

function Utils.sync(prefix, msg)
    local Comms = addon.Comms
    if Comms and Comms.sync then
        return Comms.sync(prefix, msg)
    end
end

function Utils.chat(msg, channel, language, target, bypass)
    local Comms = addon.Comms
    if Comms and Comms.chat then
        return Comms.chat(msg, channel, language, target, bypass)
    end
end

function Utils.whisper(target, msg)
    local Comms = addon.Comms
    if Comms and Comms.whisper then
        return Comms.whisper(target, msg)
    end
end

-- =========== Time helpers  =========== --

function Utils.sec2clock(seconds)
    local Time = addon.Time
    if Time and Time.sec2clock then
        return Time.sec2clock(seconds)
    end
    return "00:00:00"
end

function Utils.isRaidInstance()
    local Time = addon.Time
    if Time and Time.isRaidInstance then
        return Time.isRaidInstance()
    end
    return false
end

function Utils.getDifficulty()
    local Time = addon.Time
    if Time and Time.getDifficulty then
        return Time.getDifficulty()
    end
    return nil
end

function Utils.getCurrentTime(server)
    local Time = addon.Time
    if Time and Time.getCurrentTime then
        return Time.getCurrentTime(server)
    end
    return time()
end

function Utils.getServerOffset()
    local Time = addon.Time
    if Time and Time.getServerOffset then
        return Time.getServerOffset()
    end
    return 0
end

-- =========== Base64 encode/decode  =========== --

function Utils.encode(data)
    local Base64 = addon.Base64
    if Base64 and Base64.encode then
        return Base64.encode(data)
    end
    return data
end

function Utils.decode(data)
    local Base64 = addon.Base64
    if Base64 and Base64.decode then
        return Base64.decode(data)
    end
    return data
end
