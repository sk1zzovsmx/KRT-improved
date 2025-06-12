local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("KRT")
if not addon then return end

-- ==================== Debugger ==================== --

do
    addon.Debugger = {}
    local Debugger = addon.Debugger

    -- Local references
    local frameName, frame, scrollFrame
    local isDebuggerOpen = false
    local buffer = {} -- Holds messages if the frame isn't ready

    local logLevelPriority = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
    local logLevelNames    = { [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }
    local minLevel = "DEBUG" -- Default log level

    -- Called when the XML frame is loaded
    function Debugger:OnLoad(self)
        frame = self
        frameName = frame:GetName()
        scrollFrame = _G[frameName.."ScrollFrame"]
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

        if scrollFrame then
            print("[Debugger] scrollFrame found:", scrollFrame:GetName())
        else
            print("[Debugger] ERROR: scrollFrame is nil!")
        end

        -- Restore saved position if available
        if KRT_Debug and KRT_Debug.Pos and KRT_Debug.Pos.point then
            local p = KRT_Debug.Pos
            frame:ClearAllPoints()
            frame:SetPoint(p.point, p.relativeTo or UIParent, p.relativePoint, p.xOfs, p.yOfs)
        end
    end

    -- Show the debugger window
    function Debugger:Show()
        if not frame then return end
        frame:Show()

        if not isDebuggerOpen then
            isDebuggerOpen = true
            self:Add("DEBUG", "Debugger window opened.")
            self:AddBufferedMessages()
        end
    end

    -- Hide the debugger window
    function Debugger:Hide()
        if frame then
            frame:Hide()
            isDebuggerOpen = false
        end
    end

    -- Clear the debug output
    function Debugger:Clear()
        if scrollFrame then
            scrollFrame:Clear()
        end
        buffer = {}
    end

    -- Set the minimum log level
    function Debugger:SetMinLevel(level)
        if type(level) == "number" and logLevelNames[level] then
            minLevel = logLevelNames[level]
            self:Add("INFO", "Log level set to [%s]", minLevel)
        elseif type(level) == "string" then
            level = string.upper(level)
            if logLevelPriority[level] then
                minLevel = level
                self:Add("INFO", "Log level set to [%s]", minLevel)
            else
                self:Add("ERROR", "Invalid log level: %s", level)
            end
        else
            self:Add("ERROR", "Invalid log level type.")
        end
    end

    -- Get the current minimum log level
    function Debugger:GetMinLevel()
        return minLevel
    end

    -- Add a message to the log (with optional level)
    function Debugger:Add(level, msg, ...)
        -- Allow call like Add("message") without level
        if not msg then
            msg = level
            level = "DEBUG"
        end

        if logLevelPriority[level] < logLevelPriority[minLevel] then return end

        if ... then msg = string.format(msg, ...) end
        local line = string.format("[%s][%s] %s", date("%H:%M:%S"), level, msg)

        if not scrollFrame then
            tinsert(buffer, line)
            return
        end

        -- Choose color by level
        local r, g, b = 1, 1, 1 -- default white
        if level == "ERROR" then
            r, g, b = 1, 0.2, 0.2
        elseif level == "WARN" then
            r, g, b = 1, 0.8, 0
        elseif level == "INFO" then
            r, g, b = 0.6, 0.8, 1
        elseif level == "DEBUG" then
            r, g, b = 0.8, 0.8, 0.8
        end

        scrollFrame:AddMessage(line, r, g, b)
    end

    -- Replay any buffered messages
    function Debugger:AddBufferedMessages()
        for _, msg in ipairs(buffer) do
            scrollFrame:AddMessage(msg)
        end
        buffer = {}
    end

    -- Returns true if debugger is visible
    function Debugger:IsShown()
        return frame and frame:IsShown()
    end
end

