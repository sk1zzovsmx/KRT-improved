-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local Options = feature.Options or addon.Options
local Frames = feature.Frames or addon.Frames
local Colors = feature.Colors or addon.Colors
local Strings = feature.Strings or addon.Strings
local Bus = feature.Bus or addon.Bus
local Core = feature.Core or addon.Core

local RT_COLOR = feature.RT_COLOR

local pairs, ipairs = pairs, ipairs
local format = string.format
local upper = string.upper
local tostring, tonumber = tostring, tonumber

local UI = addon.UI or {}
if type(UI.Call) ~= "function" then
    UI.Call = function()
        return nil
    end
end

-- =========== Slash Commands  =========== --
addon.Slash = addon.Slash or {}
local module = addon.Slash

local function getController(name)
    if Core and Core.GetController then
        return Core.GetController(name)
    end
    local controllers = addon.Controllers
    return controllers and controllers[name] or nil
end

local function getSyncerService()
    local services = addon.Services
    return services and services.Syncer or nil
end

local function getRaidValidatorService()
    if Core.GetRaidValidator then
        return Core.GetRaidValidator()
    end
    return nil
end

local function formatValidateRaidDetail(entry)
    local data = entry and entry.data or {}
    local index = tonumber(entry and entry.index) or 0
    local raidNid = tostring((entry and entry.raidNid) or "?")
    local code = entry and entry.code

    if code == "RAID_NOT_TABLE" then
        return L.MsgValidateDetailRaidNotTable:format(index, raidNid)
    end
    if code == "NORMALIZE_FAILED" then
        return L.MsgValidateDetailNormalizeFailed:format(index, raidNid)
    end
    if code == "SCHEMA_MISSING" then
        return L.MsgValidateDetailSchemaMissing:format(index, raidNid)
    end
    if code == "SCHEMA_NEWER" then
        return L.MsgValidateDetailSchemaNewer:format(
            index,
            raidNid,
            tonumber(data.schemaVersion) or 0,
            tonumber(data.currentVersion) or 0
        )
    end
    if code == "COUNTER_TOO_LOW" then
        return L.MsgValidateDetailCounterTooLow:format(
            index,
            raidNid,
            tostring(data.field or "?"),
            tonumber(data.actual) or 0,
            tonumber(data.required) or 0
        )
    end
    if code == "PLAYER_COUNT_TYPE" then
        return L.MsgValidateDetailPlayerCountType:format(index, raidNid, tonumber(data.playerIndex) or 0)
    end
    if code == "PLAYER_COUNT_NEGATIVE" then
        return L.MsgValidateDetailPlayerCountNegative:format(
            index,
            raidNid,
            tonumber(data.playerIndex) or 0,
            tonumber(data.value) or 0
        )
    end
    if code == "LOOT_MISSING_BOSS" then
        return L.MsgValidateDetailLootMissingBoss:format(
            index,
            raidNid,
            tonumber(data.lootIndex) or 0,
            tonumber(data.bossNid) or 0
        )
    end
    if code == "LOOT_UNKNOWN_BOSS_WITHOUT_TRASH" then
        return L.MsgValidateDetailLootNoBossTrash:format(index, raidNid, tonumber(data.lootIndex) or 0)
    end
    if code == "RUNTIME_OUTSIDE" then
        return L.MsgValidateDetailRuntimeOutside:format(index, raidNid, tostring(data.key or "?"))
    end
    if code == "LEGACY_RUNTIME" then
        return L.MsgValidateDetailLegacyRuntime:format(index, raidNid, tostring(data.key or "?"))
    end

    return L.MsgValidateDetailUnknown:format(index, raidNid, tostring(code or "UNKNOWN"))
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
local cmdValidate = { "validate" }

-- ----- Private helpers ----- --
local helpString = "%s: %s"
local function printHelp(cmd, desc)
    addon:info("%s", helpString:format(addon.WrapTextInColorCode(cmd, Colors.NormalizeHexColor(RT_COLOR)), desc))
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
    printHelp("validate", L.StrCmdValidate)
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
    local cmd, rest = Strings.SplitArgs(msg)
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
    local subCmd, arg = Strings.SplitArgs(rest)
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
            if Bus.ResetInternalCallbackStats then
                Bus.ResetInternalCallbackStats()
            end
            addon:info("Internal callback stats reset.")
        else
            if Bus.DumpInternalCallbackStats then
                Bus.DumpInternalCallbackStats(arg)
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
        Options.ApplyDebugSetting(true)
    elseif subCmd == "off" then
        Options.ApplyDebugSetting(false)
    else
        Options.ApplyDebugSetting(not Options.IsDebugEnabled())
    end

    if Options.IsDebugEnabled() then
        addon:info(L.MsgDebugOn)
    else
        addon:info(L.MsgDebugOff)
    end
end)

registerAliases(cmdMinimap, function(rest)
    local sub, arg = Strings.SplitArgs(rest)
    if sub == "on" then
        Options.SetOption("minimapButton", true)
        Frames.SetShown(KRT_MINIMAP_GUI, true)
    elseif sub == "off" then
        Options.SetOption("minimapButton", false)
        Frames.SetShown(KRT_MINIMAP_GUI, false)
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
    local sub = Strings.SplitArgs(rest)
    if sub == "reset" then
        UI:Call("Config", "Default")
    else
        UI:Call("Config", "Toggle")
    end
end)

registerAliases(cmdWarnings, function(rest)
    local sub = Strings.SplitArgs(rest)
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
    local sub = Strings.SplitArgs(rest)
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
    local sub, arg = Strings.SplitArgs(rest)
    if not sub or sub == "" or sub == "toggle" then
        local moduleRef = getController("Logger")
        if moduleRef and moduleRef.Toggle then
            moduleRef:Toggle()
        end
    elseif sub == "req" then
        local raidRefArg, targetArg = Strings.SplitArgs(arg)
        local syncer = getSyncerService()
        if syncer and syncer.RequestLoggerReq then
            syncer:RequestLoggerReq(tonumber(raidRefArg), targetArg)
        end
    elseif sub == "push" then
        local raidRefArg, targetArg = Strings.SplitArgs(arg)
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
    local sub = Strings.SplitArgs(rest)
    if not sub or sub == "" or sub == "toggle" then
        local moduleRef = getController("Master")
        if moduleRef and moduleRef.Toggle then
            moduleRef:Toggle()
        end
    end
end)

registerAliases(cmdCounter, function(rest)
    local sub = Strings.SplitArgs(rest)
    if not sub or sub == "" or sub == "toggle" then
        UI:Call("LootCounter", "Toggle")
    end
end)

registerAliases(cmdReserves, function(rest)
    local sub = Strings.SplitArgs(rest)
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

registerAliases(cmdValidate, function(rest)
    local sub, arg = Strings.SplitArgs(rest)
    if sub == "raids" then
        local verboseArg = Strings.SplitArgs(arg)
        local validator = getRaidValidatorService()
        if not (validator and validator.ValidateAllRaids) then
            addon:warn(L.MsgValidateUnavailable)
            return
        end

        local report = validator:ValidateAllRaids({
            includeInfo = (verboseArg == "verbose" or verboseArg == "all"),
            maxDetails = 60,
        })
        if not report then
            addon:warn(L.MsgValidateUnavailable)
            return
        end

        local raidsCount = tonumber(report.raids) or 0
        if raidsCount <= 0 then
            addon:info(L.MsgValidateRaidsNoData)
            return
        end

        local summary = L.MsgValidateRaidsSummary:format(
            raidsCount,
            tonumber(report.ok) or 0,
            tonumber(report.warn) or 0,
            tonumber(report.err) or 0,
            tonumber(report.currentSchemaVersion) or 0
        )

        if tonumber(report.err) and report.err > 0 then
            addon:error(summary)
        elseif tonumber(report.warn) and report.warn > 0 then
            addon:warn(summary)
        else
            addon:info(summary)
        end

        local details = report.details or {}
        for i = 1, #details do
            local entry = details[i]
            local line = formatValidateRaidDetail(entry)
            if entry.level == "E" then
                addon:error(line)
            elseif entry.level == "W" then
                addon:warn(line)
            else
                addon:info(line)
            end
        end

        if tonumber(report.truncatedCount) and report.truncatedCount > 0 then
            addon:warn(L.MsgValidateRaidsDetailsTruncated:format(report.truncatedCount))
        end
    else
        addon:info(format(L.StrCmdCommands, "krt validate"), "KRT")
        printHelp("raids [verbose]", L.StrCmdValidateRaids)
    end
end)

registerAliases(cmdLFM, function(rest)
    local sub = Strings.SplitArgs(rest)
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
