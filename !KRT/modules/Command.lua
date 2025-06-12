local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("KRT")
if not addon then return end

-- ==================== Slash Commands ==================== --

do
    -- Valid subcommands for each feature
    local cmdAchiev   = {"ach", "achi", "achiev", "achievement"}
    local cmdLFM      = {"pug", "lfm", "group", "grouper"}
    local cmdConfig   = {"config", "conf", "options", "opt"}
    local cmdChanges  = {"ms", "changes", "mschanges"}
    local cmdWarnings = {"warning", "warnings", "warn", "rw"}
    local cmdLog      = {"log", "logger", "history"}
    local cmdDebug    = {"debug", "dbg", "debugger"}
    local cmdLoot     = {"loot", "ml", "master"}
    local cmdReserves = {"res", "reserves", "reserve"}

    local helpString = "|caaf49141%s|r: %s"

    local function HandleSlashCmd(cmd)
        if not cmd or cmd == "" then return end

        if cmd == "show" or cmd == "toggle" then
            addon.Master:Toggle()
            return
        end

        local cmd1, cmd2, cmd3 = strsplit(" ", cmd, 3)

        -- ==== Debugger ====
        if Utils.checkEntry(cmdDebug, cmd1) then
            local subCmd = cmd2 and cmd2:lower()

            local actions = {
                clear  = function() addon.Debugger:Clear() end,
                show   = function() addon.Debugger:Show() end,
                hide   = function() addon.Debugger:Hide() end,
                toggle = function()
                    if addon.Debugger:IsShown() then
                        addon.Debugger:Hide()
                        addon.Debugger:Clear()
                    else
                        addon.Debugger:Show()
                    end
                end,
            }

            if not subCmd or subCmd == "" then
                actions.toggle()
            elseif subCmd == "level" or subCmd == "lvl" then
                if not cmd3 then
                    addon.Debugger:Add("INFO", "Current log level: %s", addon.Debugger:GetMinLevel())
                else
                    addon.Debugger:SetMinLevel(tonumber(cmd3) or cmd3)
                end
            elseif actions[subCmd] then
                actions[subCmd]()
            else
                addon.Debugger:Add("WARN", "Unknown debug command: %s", subCmd)
            end

        -- ==== Achievement Link ====
        elseif Utils.checkEntry(cmdAchiev, cmd1) and find(cmd, "achievement:%d*:") then
            local from, to = string.find(cmd, "achievement:%d*:")
            local id = string.sub(cmd, from + 11, to - 1)
            from, to = string.find(cmd, "|cffffff00|Hachievement:.*%]|h|r")
            local name = string.sub(cmd, from, to)
            print(helpString:format("KRT", name .. " - ID#" .. id))

        -- ==== Config ====
        elseif Utils.checkEntry(cmdConfig, cmd1) then
            if cmd2 == "reset" then
                addon.Config:Default()
            else
                addon.Config:Toggle()
            end

        -- ==== Warnings ====
        elseif Utils.checkEntry(cmdWarnings, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
                addon.Warnings:Toggle()
            elseif cmd2 == "help" then
                addon:Print(format(L.StrCmdCommands, "krt rw"), "KRT")
                print(helpString:format("toggle", L.StrCmdToggle))
                print(helpString:format("[ID]", L.StrCmdWarningAnnounce))
            else
                addon.Warnings:Announce(tonumber(cmd2))
            end

        -- ==== MS Changes ====
        elseif Utils.checkEntry(cmdChanges, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
                addon.Changes:Toggle()
            elseif cmd2 == "demand" or cmd2 == "ask" then
                addon.Changes:Demand()
            elseif cmd2 == "announce" or cmd2 == "spam" then
                addon.Changes:Announce()
            else
                addon:Print(format(L.StrCmdCommands, "krt ms"), "KRT")
                print(helpString:format("toggle", L.StrCmdToggle))
                print(helpString:format("demand", L.StrCmdChangesDemand))
                print(helpString:format("announce", L.StrCmdChangesAnnounce))
            end

        -- ==== Loot Log ====
        elseif Utils.checkEntry(cmdLog, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
                addon.Logger:Toggle()
            end

        -- ==== Master Looter ====
        elseif Utils.checkEntry(cmdLoot, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
                addon.Master:Toggle()
            end

        -- ==== Reserves ====
        elseif Utils.checkEntry(cmdReserves, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
                addon.Reserves:ShowWindow()
            elseif cmd2 == "import" then
                addon.Reserves:ShowImportBox()
            else
                addon:Print(format(L.StrCmdCommands, "krt res"), "KRT")
                print(helpString:format("toggle", L.StrCmdToggle))
                print(helpString:format("import", L.StrCmdReservesImport))
            end

        -- ==== LFM (Spammer) ====
        elseif Utils.checkEntry(cmdLFM, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" or cmd2 == "show" then
                addon.Spammer:Toggle()
            elseif cmd2 == "start" then
                addon.Spammer:Start()
            elseif cmd2 == "stop" then
                addon.Spammer:Stop()
            else
                addon:Print(format(L.StrCmdCommands, "krt pug"), "KRT")
                print(helpString:format("toggle", L.StrCmdToggle))
                print(helpString:format("start", L.StrCmdLFMStart))
                print(helpString:format("stop", L.StrCmdLFMStop))
            end

        -- ==== Help fallback ====
        else
            addon:Print(format(L.StrCmdCommands, "krt"), "KRT")
            print(helpString:format("config", L.StrCmdConfig))
            print(helpString:format("lfm", L.StrCmdGrouper))
            print(helpString:format("ach", L.StrCmdAchiev))
            print(helpString:format("changes", L.StrCmdChanges))
            print(helpString:format("warnings", L.StrCmdWarnings))
            print(helpString:format("log", L.StrCmdLog))
            print(helpString:format("reserves", L.StrCmdReserves))
        end
    end

    -- Register slash commands
    SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
    SlashCmdList["KRT"] = HandleSlashCmd
end

