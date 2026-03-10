-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Bus = feature.Bus or addon.Bus
local type = type

addon.UI = addon.UI or {}
local UI = addon.UI

UI._registry = UI._registry or {}

local function isWidgetEnabled(widgetId)
    local Features = addon.Features
    if type(Features) ~= "table" then
        return true
    end
    if type(Features.IsEnabled) == "function" then
        return Features:IsEnabled(widgetId)
    end
    local flags = Features.WidgetFlags
    if type(flags) == "table" and flags[widgetId] ~= nil then
        return flags[widgetId] == true
    end
    return true
end

function UI:IsEnabled(widgetId)
    if type(widgetId) ~= "string" or widgetId == "" then
        return false
    end
    return isWidgetEnabled(widgetId)
end

function UI:IsRegistered(widgetId)
    if type(widgetId) ~= "string" or widgetId == "" then
        return false
    end
    local api = self._registry and self._registry[widgetId]
    return type(api) == "table"
end

function UI:Register(widgetId, apiTable)
    if type(widgetId) ~= "string" or widgetId == "" then
        return false
    end
    if type(apiTable) ~= "table" then
        return false
    end
    if not self:IsEnabled(widgetId) then
        self._registry[widgetId] = nil
        return false
    end
    self._registry[widgetId] = apiTable
    return true
end

function UI:Call(widgetId, methodName, ...)
    if not self:IsEnabled(widgetId) then
        return nil
    end
    local api = self._registry and self._registry[widgetId]
    if type(api) ~= "table" then
        return nil
    end
    local fn = api[methodName]
    if type(fn) ~= "function" then
        return nil
    end
    return fn(...)
end

function UI:Emit(eventName, ...)
    if not (Bus and Bus.TriggerEvent) then
        return nil
    end
    Bus.TriggerEvent(eventName, ...)
    return true
end
