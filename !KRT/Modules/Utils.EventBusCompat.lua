-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.EventBusCompat = Utils.EventBusCompat or {}
local EventBusCompat = Utils.EventBusCompat

function EventBusCompat.registerCallback(eventName, callback)
    local Bus = addon.Bus
    if Bus and Bus.registerCallback then
        return Bus.registerCallback(eventName, callback)
    end
    error(L.StrCbErrUsage)
end

function EventBusCompat.unregisterCallback(handle)
    local Bus = addon.Bus
    if Bus and Bus.unregisterCallback then
        return Bus.unregisterCallback(handle)
    end
end

function EventBusCompat.triggerEvent(eventName, ...)
    local Bus = addon.Bus
    if Bus and Bus.triggerEvent then
        return Bus.triggerEvent(eventName, ...)
    end
end

function EventBusCompat.registerCallbacks(names, callback)
    local Bus = addon.Bus
    if Bus and Bus.registerCallbacks then
        return Bus.registerCallbacks(names, callback)
    end
end

function EventBusCompat.getInternalCallbackStats()
    local Bus = addon.Bus
    if Bus and Bus.getInternalCallbackStats then
        return Bus.getInternalCallbackStats()
    end
    return {}
end

function EventBusCompat.resetInternalCallbackStats()
    local Bus = addon.Bus
    if Bus and Bus.resetInternalCallbackStats then
        return Bus.resetInternalCallbackStats()
    end
end

function EventBusCompat.dumpInternalCallbackStats(sortBy)
    local Bus = addon.Bus
    if Bus and Bus.dumpInternalCallbackStats then
        return Bus.dumpInternalCallbackStats(sortBy)
    end
end
