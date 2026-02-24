-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Utils = feature.Utils
local Options = feature.Options or addon.Options
local Frames = feature.Frames or addon.Frames
local Colors = feature.Colors or addon.Colors
local Strings = feature.Strings or addon.Strings
local Bus = feature.Bus or addon.Bus

local K_COLOR = feature.K_COLOR
local RT_COLOR = feature.RT_COLOR
local Core = feature.Core or addon.Core

local UI = addon.UI or {}
if type(UI.Call) ~= "function" then
    UI.Call = function()
        return nil
    end
end

local pairs, ipairs = pairs, ipairs
local format = string.format
local upper = string.upper
local tostring, tonumber = tostring, tonumber

-- =========== Minimap Button Module  =========== --
do
    addon.Minimap = addon.Minimap or {}
    local module = addon.Minimap

    local function getController(name)
        if Core and Core.getController then
            return Core.getController(name)
        end
        local controllers = addon.Controllers
        return controllers and controllers[name] or nil
    end

    -- ----- Internal state ----- --
    local addonMenu
    local dragMode

    -- Cached math functions
    local sqrt = math.sqrt
    local cos, sin = math.cos, math.sin
    local rad, atan2, deg = math.rad, math.atan2, math.deg

    -- ----- Private helpers ----- --
    -- Menu definition for EasyMenu (built once).
    local minimapMenu = {
        {
            text = MASTER_LOOTER,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Master")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        { text = L.StrLootCounter, notCheckable = 1, func = function() UI:Call("LootCounter", "Toggle") end },
        {
            text = L.StrLootLogger,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Logger")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrClearIcons,  notCheckable = 1, func = function() addon.Raid:ClearRaidIcons() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        {
            text = RAID_WARNING,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Warnings")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        {
            text = L.StrMSChanges,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Changes")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        {
            text = L.BtnDemand,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Changes")
                if moduleRef and moduleRef.Demand then
                    moduleRef:Demand()
                end
            end
        },
        {
            text = CHAT_ANNOUNCE,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Changes")
                if moduleRef and moduleRef.Announce then
                    moduleRef:Announce()
                end
            end
        },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        {
            text = L.StrLFMSpam,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Spammer")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
    }

    -- Initializes and opens the menu for the minimap button.
    local function OpenMenu()
        addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
        -- EasyMenu handles UIDropDownMenu initialization and opening.
        EasyMenu(minimapMenu, addonMenu, KRT_MINIMAP_GUI, 0, 0, "MENU")
    end

    local function IsMenuOpen()
        return addonMenu and UIDROPDOWNMENU_OPEN_MENU == addonMenu and DropDownList1 and DropDownList1:IsShown()
    end

    local function ToggleMenu()
        if IsMenuOpen() then
            CloseDropDownMenus()
            return
        end
        OpenMenu()
    end

    -- Moves the minimap button while dragging.
    local function moveButton(self)
        local centerX, centerY = Minimap:GetCenter()
        local x, y = GetCursorPosition()
        x, y = x / self:GetEffectiveScale() - centerX, y / self:GetEffectiveScale() - centerY

        if dragMode == "free" then
            -- Free drag mode
            self:ClearAllPoints()
            self:SetPoint("CENTER", x, y)
        else
            -- Circular drag mode (snap to ring radius ~80)
            local dist = sqrt(x * x + y * y)
            local px, py = (x / dist) * 80, (y / dist) * 80
            self:ClearAllPoints()
            self:SetPoint("CENTER", px, py)
        end
    end

    local function SetMinimapShown(show)
        Frames.setShown(KRT_MINIMAP_GUI, show)
    end

    -- ----- Public methods ----- --
    function module:SetPos(angle)
        angle = angle % 360
        Options.setOption("minimapPos", angle)
        local r = rad(angle)
        KRT_MINIMAP_GUI:ClearAllPoints()
        KRT_MINIMAP_GUI:SetPoint("CENTER", cos(r) * 80, sin(r) * 80)
    end

    function module:OnLoad()
        local options = addon.options or KRT_Options or {}
        KRT_MINIMAP_GUI:SetUserPlaced(true)
        self:SetPos(options.minimapPos or 325)
        SetMinimapShown(options.minimapButton ~= false)
        KRT_MINIMAP_GUI:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        KRT_MINIMAP_GUI:SetScript("OnMouseDown", function(self, button)
            if IsAltKeyDown() then
                dragMode = "free"
                self:SetScript("OnUpdate", moveButton)
            elseif IsShiftKeyDown() then
                dragMode = nil
                self:SetScript("OnUpdate", moveButton)
            end
        end)
        KRT_MINIMAP_GUI:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil)
            if dragMode == "free" then
                dragMode = nil
                return
            end
            local mx, my = Minimap:GetCenter()
            local bx, by = self:GetCenter()
            module:SetPos(deg(atan2(by - my, bx - mx)))
            dragMode = nil
        end)
        KRT_MINIMAP_GUI:SetScript("OnClick", function(self, button, down)
            -- Ignore clicks if Shift or Alt keys are held:
            if IsShiftKeyDown() or IsAltKeyDown() then return end
            if button == "RightButton" then
                UI:Call("Config", "Toggle")
            elseif button == "LeftButton" then
                ToggleMenu()
            end
        end)
        KRT_MINIMAP_GUI:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetText(
                addon.WrapTextInColorCode("Kader", Colors.normalizeHexColor(K_COLOR))
                .. " "
                .. addon.WrapTextInColorCode("Raid Tools", Colors.normalizeHexColor("aad4af37"))
            )
            GameTooltip:AddLine(L.StrMinimapLClick, 1, 1, 1)
            GameTooltip:AddLine(L.StrMinimapRClick, 1, 1, 1)
            GameTooltip:AddLine(L.StrMinimapSClick, 1, 1, 1)
            GameTooltip:AddLine(L.StrMinimapAClick, 1, 1, 1)
            GameTooltip:Show()
        end)
        KRT_MINIMAP_GUI:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end

    -- Toggles the visibility of the minimap button.
    function module:ToggleMinimapButton()
        local options = addon.options or KRT_Options or {}
        local nextValue = not options.minimapButton
        Options.setOption("minimapButton", nextValue)
        SetMinimapShown(nextValue)
    end

    -- Hides the minimap button.
    function module:HideMinimapButton()
        return Frames.setShown(KRT_MINIMAP_GUI, false)
    end
end

-- =========== Slash Commands  =========== --
do
    addon.Slash = addon.Slash or {}
    local module = addon.Slash

    local function getController(name)
        if Core and Core.getController then
            return Core.getController(name)
        end
        local controllers = addon.Controllers
        return controllers and controllers[name] or nil
    end

    local function getSyncerService()
        local services = addon.Services
        return services and services.Syncer or nil
    end

    -- ----- Internal state ----- --
    module.sub = module.sub or {}

    local cmdAchiev = { "ach", "achi", "achiev", "achievement" }
    local cmdLFM = { "pug", "lfm", "group", "grouper" }
    local cmdConfig = { "config", "conf", "options", "opt" }
    local cmdChanges = { "ms", "changes", "mschanges" }
    local cmdWarnings = { "warning", "warnings", "warn", "rw" }
    local cmdLogger = { "logger", "history", "log" }
    local cmdDebug = { "debug", "dbg", "debugger" }
    local cmdLoot = { "loot", "ml", "master" }
    local cmdCounter = { "counter", "counters", "counts" }
    local cmdReserves = { "res", "reserves", "reserve" }
    local cmdMinimap = { "minimap", "mm" }

    -- ----- Private helpers ----- --
    local helpString = "%s: %s"
    local function printHelp(cmd, desc)
        addon:info("%s", helpString:format(addon.WrapTextInColorCode(cmd, Colors.normalizeHexColor(RT_COLOR)), desc))
    end

    local function showHelp()
        addon:info(format(L.StrCmdCommands, "krt"), "KRT")
        printHelp("config", L.StrCmdConfig)
        printHelp("lfm", L.StrCmdGrouper)
        printHelp("ach", L.StrCmdAchiev)
        printHelp("changes", L.StrCmdChanges)
        printHelp("warnings", L.StrCmdWarnings)
        printHelp("logger", L.StrCmdLogger)
        printHelp("debug", L.StrCmdDebug)
        printHelp("counter", L.StrCmdCounter)
        printHelp("reserves", L.StrCmdReserves)
    end

    local function registerAliases(list, fn)
        for _, cmd in ipairs(list) do
            module.sub[cmd] = fn
        end
    end

    -- ----- Public methods ----- --
    function module:Register(cmd, fn)
        self.sub[cmd] = fn
    end

    function module:Handle(msg)
        if not msg or msg == "" then return end
        local cmd, rest = Strings.splitArgs(msg)
        if cmd == "show" or cmd == "toggle" then
            local moduleRef = getController("Master")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
            return
        end
        local fn = self.sub[cmd]
        if fn then
            return fn(rest, cmd, msg)
        end
        showHelp()
    end

    registerAliases(cmdDebug, function(rest)
        local subCmd, arg = Strings.splitArgs(rest)
        if subCmd == "" then subCmd = nil end

        if subCmd == "levels" then
            addon:info(L.MsgLogLevelList)
            return
        end

        if subCmd == "level" or subCmd == "lvl" then
            if not arg or arg == "" then
                local lvl = addon.GetLogLevel and addon:GetLogLevel()
                local name
                for k, v in pairs(addon.logLevels or {}) do
                    if v == lvl then
                        name = k
                        break
                    end
                end
                addon:info(L.MsgLogLevelCurrent, name or tostring(lvl))
                addon:info(L.MsgLogLevelList)
                return
            end

            local lv = tonumber(arg)
            if not lv and addon.logLevels then
                lv = addon.logLevels[upper(arg)]
            end
            if lv then
                addon:SetLogLevel(lv)
                addon:info(L.MsgLogLevelSet, arg)
            else
                addon:warn(L.MsgLogLevelUnknown, arg)
            end
            return
        end

        if subCmd == "callbacks" or subCmd == "cb" or subCmd == "bus" then
            if arg == "reset" then
                if Bus.resetInternalCallbackStats then
                    Bus.resetInternalCallbackStats()
                end
                addon:info("Internal callback stats reset.")
            else
                if Bus.dumpInternalCallbackStats then
                    Bus.dumpInternalCallbackStats(arg)
                else
                    addon:warn("Callback stats not available in this build.")
                end
            end
            return
        end

        if subCmd == "timers" or subCmd == "timer" then
            if arg == "reset" then
                if addon.ResetTimerDebug then
                    addon:ResetTimerDebug()
                end
                addon:info("Timer debug stats reset.")
            else
                if addon.DumpTimerDebug then
                    addon:DumpTimerDebug(arg)
                else
                    addon:warn("Timer debug not available in this build.")
                end
            end
            return
        end


        if subCmd == "on" then
            Options.applyDebugSetting(true)
        elseif subCmd == "off" then
            Options.applyDebugSetting(false)
        else
            Options.applyDebugSetting(not Options.isDebugEnabled())
        end

        if Options.isDebugEnabled() then
            addon:info(L.MsgDebugOn)
        else
            addon:info(L.MsgDebugOff)
        end
    end)

    registerAliases(cmdMinimap, function(rest)
        local sub, arg = Strings.splitArgs(rest)
        if sub == "on" then
            Options.setOption("minimapButton", true)
            Frames.setShown(KRT_MINIMAP_GUI, true)
        elseif sub == "off" then
            Options.setOption("minimapButton", false)
            Frames.setShown(KRT_MINIMAP_GUI, false)
        elseif sub == "pos" and arg ~= "" then
            local angle = tonumber(arg)
            if angle then
                addon.Minimap:SetPos(angle)
                addon:info(L.MsgMinimapPosSet, angle)
            end
        elseif sub == "pos" then
            addon:info(L.MsgMinimapPosSet, addon.options.minimapPos)
        else
            addon:info(format(L.StrCmdCommands, "krt minimap"), "KRT")
            printHelp("on", L.StrCmdToggle)
            printHelp("off", L.StrCmdToggle)
            printHelp("pos <deg>", L.StrCmdMinimapPos)
        end
    end)

    registerAliases(cmdAchiev, function(_, _, raw)
        if not raw or not raw:find("achievement:%d*:") then
            addon:info(format(L.StrCmdCommands, "krt ach"), "KRT")
            return
        end

        local from, to = raw:find("achievement%:%d*%:")
        if not (from and to) then return end
        local id = raw:sub(from + 12, to - 1)
        from, to = raw:find("%|cffffff00%|Hachievement%:.*%]%|h%|r")
        local name = (from and to) and raw:sub(from, to) or ""
        printHelp("KRT", name .. " - ID#" .. id)
    end)

    registerAliases(cmdConfig, function(rest)
        local sub = Strings.splitArgs(rest)
        if sub == "reset" then
            UI:Call("Config", "Default")
        else
            UI:Call("Config", "Toggle")
        end
    end)

    registerAliases(cmdWarnings, function(rest)
        local sub = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            local moduleRef = getController("Warnings")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
        elseif sub == "help" then
            addon:info(format(L.StrCmdCommands, "krt rw"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("[ID]", L.StrCmdWarningAnnounce)
        else
            local moduleRef = getController("Warnings")
            if moduleRef and moduleRef.Announce then
                moduleRef:Announce(tonumber(sub))
            end
        end
    end)

    registerAliases(cmdChanges, function(rest)
        local sub = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            local moduleRef = getController("Changes")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
        elseif sub == "demand" or sub == "ask" then
            local moduleRef = getController("Changes")
            if moduleRef and moduleRef.Demand then
                moduleRef:Demand()
            end
        elseif sub == "announce" or sub == "spam" then
            local moduleRef = getController("Changes")
            if moduleRef and moduleRef.Announce then
                moduleRef:Announce()
            end
        else
            addon:info(format(L.StrCmdCommands, "krt ms"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("demand", L.StrCmdChangesDemand)
            printHelp("announce", L.StrCmdChangesAnnounce)
        end
    end)

    registerAliases(cmdLogger, function(rest)
        local sub, arg = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            local moduleRef = getController("Logger")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
        elseif sub == "req" then
            local raidRefArg, targetArg = Strings.splitArgs(arg)
            local syncer = getSyncerService()
            if syncer and syncer.RequestLoggerReq then
                syncer:RequestLoggerReq(tonumber(raidRefArg), targetArg)
            end
        elseif sub == "push" then
            local raidRefArg, targetArg = Strings.splitArgs(arg)
            local syncer = getSyncerService()
            if syncer and syncer.BroadcastLoggerPush then
                syncer:BroadcastLoggerPush(tonumber(raidRefArg), targetArg)
            end
        elseif sub == "sync" then
            local syncer = getSyncerService()
            if syncer and syncer.RequestLoggerSync then
                syncer:RequestLoggerSync()
            end
        else
            addon:info(format(L.StrCmdCommands, "krt logger"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("req <raidId|raidNid> <player>", L.StrCmdLoggerReq)
            printHelp("push <raidId|raidNid> <player>", L.StrCmdLoggerPush)
            printHelp("sync", L.StrCmdLoggerSync)
        end
    end)

    registerAliases(cmdLoot, function(rest)
        local sub = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            local moduleRef = getController("Master")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
        end
    end)

    registerAliases(cmdCounter, function(rest)
        local sub = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            UI:Call("LootCounter", "Toggle")
        end
    end)

    registerAliases(cmdReserves, function(rest)
        local sub = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            UI:Call("Reserves", "Toggle")
        elseif sub == "import" then
            UI:Call("Reserves", "ToggleImport")
        else
            addon:info(format(L.StrCmdCommands, "krt res"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("import", L.StrCmdReservesImport)
        end
    end)

    registerAliases(cmdLFM, function(rest)
        local sub = Strings.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" or sub == "show" then
            local moduleRef = getController("Spammer")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
        elseif sub == "start" then
            local moduleRef = getController("Spammer")
            if moduleRef and moduleRef.Start then
                moduleRef:Start()
            end
        elseif sub == "stop" then
            local moduleRef = getController("Spammer")
            if moduleRef and moduleRef.Stop then
                moduleRef:Stop()
            end
        else
            addon:info(format(L.StrCmdCommands, "krt pug"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("start", L.StrCmdLFMStart)
            printHelp("stop", L.StrCmdLFMStop)
        end
    end)

    -- Register slash commands
    SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
    SlashCmdList["KRT"] = function(msg)
        module:Handle(msg)
    end
end
