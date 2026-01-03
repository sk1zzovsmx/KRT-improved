--[[
    KRT_EventDispatcher.lua
    - KRT uses a single event frame. If CallbackHandler-1.0 is available,
      you can optionally expose an addon:RegisterEvent(...) callback API.
    - If you already have an event system in KRT.lua, keep the repo one.
]]

local _, addon = ...

do
    local mainFrame = addon.EventFrame or CreateFrame("Frame")
    addon.EventFrame = mainFrame

    local events

    local function OnEvent(_, event, ...)
        if events then
            events:Fire(event, ...)
            return
        end

        local fn = addon[event]
        if type(fn) == "function" then
            fn(addon, ...)
        end
    end

    local function InitFallback()
        mainFrame:SetScript("OnEvent", OnEvent)

        function addon:RegisterEvent(eventName)
            mainFrame:RegisterEvent(eventName)
        end

        function addon:UnregisterEvent(eventName)
            mainFrame:UnregisterEvent(eventName)
        end

        function addon:UnregisterAllEvents()
            mainFrame:UnregisterAllEvents()
        end
    end

    local CB = addon.CallbackHandler or (LibStub and LibStub("CallbackHandler-1.0", true))
    if CB then
        events = CB:New(addon, "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents")
        events.OnUsed = function(_, _, eventName) mainFrame:RegisterEvent(eventName) end
        events.OnUnused = function(_, _, eventName) mainFrame:UnregisterEvent(eventName) end
        mainFrame:SetScript("OnEvent", OnEvent)
    else
        InitFallback()
    end
end
