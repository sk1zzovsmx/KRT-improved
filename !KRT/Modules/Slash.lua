local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local RT_COLOR = C.RT_COLOR

---============================================================================
do
    addon.Slash = addon.Slash or {}
    local Slash = addon.Slash
    local L = addon.L

    Slash.sub = Slash.sub or {}

    local cmdAchiev = { "ach", "achi", "achiev", "achievement" }
    local cmdLFM = { "pug", "lfm", "group", "grouper" }
    local cmdConfig = { "config", "conf", "options", "opt" }
    local cmdChanges = { "ms", "changes", "mschanges" }
    local cmdWarnings = { "warning", "warnings", "warn", "rw" }
    local cmdLogger = { "logger", "history", "log" }
    local cmdDebug = { "debug", "dbg", "debugger" }
    local cmdLoot = { "loot", "ml", "master" }
    local cmdReserves = { "res", "reserves", "reserve" }
    local cmdMinimap = { "minimap", "mm" }

    local helpString = "%s: %s"
    local function printHelp(cmd, desc)
        addon:info("%s", helpString:format(addon.WrapTextInColorCode(cmd, Utils.normalizeHexColor(RT_COLOR)), desc))
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
        printHelp("reserves", L.StrCmdReserves)
    end

    local function registerAliases(list, fn)
        for _, cmd in ipairs(list) do
            Slash.sub[cmd] = fn
        end
    end

    function Slash:Register(cmd, fn)
        self.sub[cmd] = fn
    end

    function Slash:Handle(msg)
        if not msg or msg == "" then return end
        local cmd, rest = Utils.splitArgs(msg)
        if cmd == "show" or cmd == "toggle" then
            addon.Master:Toggle()
            return
        end
        local fn = self.sub[cmd]
        if fn then
            return fn(rest, cmd, msg)
        end
        showHelp()
    end

    registerAliases(cmdDebug, function(rest)
        local subCmd, arg = Utils.splitArgs(rest)
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

        if subCmd == "on" then
            Utils.applyDebugSetting(true)
        elseif subCmd == "off" then
            Utils.applyDebugSetting(false)
        else
            Utils.applyDebugSetting(not addon.options.debug)
        end

        if addon.options.debug then
            addon:info(L.MsgDebugOn)
        else
            addon:info(L.MsgDebugOff)
        end
    end)

    registerAliases(cmdMinimap, function(rest)
        local sub, arg = Utils.splitArgs(rest)
        if sub == "on" then
            addon.options.minimapButton = true
            Utils.setShown(KRT_MINIMAP_GUI, true)
        elseif sub == "off" then
            addon.options.minimapButton = false
            Utils.setShown(KRT_MINIMAP_GUI, false)
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
        local sub = Utils.splitArgs(rest)
        if sub == "reset" then
            addon.Config:Default()
        else
            addon.Config:Toggle()
        end
    end)

    registerAliases(cmdWarnings, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Warnings:Toggle()
        elseif sub == "help" then
            addon:info(format(L.StrCmdCommands, "krt rw"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("[ID]", L.StrCmdWarningAnnounce)
        else
            addon.Warnings:Announce(tonumber(sub))
        end
    end)

    registerAliases(cmdChanges, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Changes:Toggle()
        elseif sub == "demand" or sub == "ask" then
            addon.Changes:Demand()
        elseif sub == "announce" or sub == "spam" then
            addon.Changes:Announce()
        else
            addon:info(format(L.StrCmdCommands, "krt ms"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("demand", L.StrCmdChangesDemand)
            printHelp("announce", L.StrCmdChangesAnnounce)
        end
    end)

    registerAliases(cmdLogger, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Logger:Toggle()
        end
    end)

    registerAliases(cmdLoot, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Master:Toggle()
        end
    end)

    registerAliases(cmdReserves, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Reserves:ShowWindow()
        elseif sub == "import" then
            addon.Reserves:ShowImportBox()
        else
            addon:info(format(L.StrCmdCommands, "krt res"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("import", L.StrCmdReservesImport)
        end
    end)

    registerAliases(cmdLFM, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" or sub == "show" then
            addon.Spammer:Toggle()
        elseif sub == "start" then
            addon.Spammer:Start()
        elseif sub == "stop" then
            addon.Spammer:Stop()
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
        Slash:Handle(msg)
    end

    SLASH_KRTCOUNTS1 = "/krtcounts"
    SlashCmdList["KRTCOUNTS"] = function()
        addon.Master:ToggleCountsFrame() -- Loot Counter is not yet refactored.
    end
end
