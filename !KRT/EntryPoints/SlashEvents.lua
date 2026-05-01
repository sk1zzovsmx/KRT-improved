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
local Services = feature.Services or addon.Services
local Comms = feature.Comms or addon.Comms

local RT_COLOR = feature.RT_COLOR

local pairs, ipairs = pairs, ipairs
local format = string.format
local upper = string.upper
local type = type
local tostring, tonumber = tostring, tonumber
local floor = math.floor
local _G = _G

local UI = addon.UI

-- =========== Slash Commands  =========== --
local module = {}

local function getCoreService(getterName)
    local getter = Core and Core[getterName]
    if type(getter) == "function" then
        return getter()
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
        return L.MsgValidateDetailSchemaNewer:format(index, raidNid, tonumber(data.schemaVersion) or 0, tonumber(data.currentVersion) or 0)
    end
    if code == "COUNTER_TOO_LOW" then
        return L.MsgValidateDetailCounterTooLow:format(index, raidNid, tostring(data.field or "?"), tonumber(data.actual) or 0, tonumber(data.required) or 0)
    end
    if code == "PLAYER_COUNT_TYPE" then
        return L.MsgValidateDetailPlayerCountType:format(index, raidNid, tonumber(data.playerIndex) or 0)
    end
    if code == "PLAYER_COUNT_NEGATIVE" then
        return L.MsgValidateDetailPlayerCountNegative:format(index, raidNid, tonumber(data.playerIndex) or 0, tonumber(data.value) or 0)
    end
    if code == "LOOT_MISSING_BOSS" then
        return L.MsgValidateDetailLootMissingBoss:format(index, raidNid, tonumber(data.lootIndex) or 0, tonumber(data.bossNid) or 0)
    end
    if code == "LOOT_UNKNOWN_BOSS_WITHOUT_TRASH" then
        return L.MsgValidateDetailLootNoBossTrash:format(index, raidNid, tonumber(data.lootIndex) or 0)
    end
    if code == "BOSS_ATTENDEE_INVALID" then
        return L.MsgValidateDetailBossAttendeeInvalid:format(index, raidNid, tonumber(data.bossIndex) or 0, tonumber(data.attendeeIndex) or 0)
    end
    if code == "BOSS_ATTENDEE_MISSING_PLAYER" then
        return L.MsgValidateDetailBossAttendeeMissingPlayer:format(index, raidNid, tonumber(data.bossIndex) or 0, tonumber(data.attendeeIndex) or 0, tonumber(data.playerNid) or 0)
    end
    if code == "LOOT_MISSING_LOOTER" then
        local looterNid = tonumber(data.looterNid)
        if looterNid and looterNid > 0 then
            return L.MsgValidateDetailLootMissingLooterNid:format(index, raidNid, tonumber(data.lootIndex) or 0, looterNid)
        end
        return L.MsgValidateDetailLootMissingLooter:format(index, raidNid, tonumber(data.lootIndex) or 0)
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

local cmdAchiev, cmdLFM, cmdConfig = { "ach", "achi", "achiev", "achievement" }, { "pug", "lfm", "group", "grouper" }, { "config", "conf", "options", "opt" }
local cmdChanges, cmdWarnings, cmdLogger = { "ms", "changes", "mschanges" }, { "warning", "warnings", "warn", "rw" }, { "logger", "history", "log" }
local cmdDebug, cmdLoot, cmdCounter = { "debug", "dbg", "debugger" }, { "loot", "ml", "master" }, { "counter", "counters", "counts" }
local cmdReserves, cmdMinimap, cmdValidate = { "res", "reserves", "reserve" }, { "minimap", "mm" }, { "validate" }
local cmdHelp, cmdBug, cmdVersion = { "help", "commands" }, { "bug", "report" }, { "version", "ver", "about" }
local cmdPerf = { "perf", "performance" }
local lootOnlySlashCommands = {}

local function markLootOnlyCommands(list)
    for i = 1, #list do
        local command = list[i]
        if type(command) == "string" and command ~= "" then
            lootOnlySlashCommands[command] = true
        end
    end
end

for _, commandList in ipairs({ cmdReserves }) do
    markLootOnlyCommands(commandList)
end

-- ----- Private helpers ----- --
local helpString = "%s: %s"
local function printHelp(cmd, desc)
    addon:info("%s", helpString:format(addon.WrapTextInColorCode(cmd, Colors.NormalizeHexColor(RT_COLOR)), desc))
end

local function showHelp()
    addon:info(format(L.StrCmdCommands, "krt"), "KRT")
    printHelp("help [command]", L.StrCmdHelp)
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
    printHelp("perf", L.StrCmdPerf)
    printHelp("version", L.StrCmdVersion)
    printHelp("bug", L.StrCmdBug)
end

local function showLootHelp()
    addon:info(format(L.StrCmdCommands, "krt ml"), "KRT")
    printHelp("toggle", L.StrCmdToggle)
end

local function showCounterHelp()
    addon:info(format(L.StrCmdCommands, "krt counter"), "KRT")
    printHelp("toggle", L.StrCmdToggle)
end

local function showDebugRaidHelp()
    addon:info(format(L.StrCmdCommands, "krt debug raid"), "KRT")
    printHelp("seed", L.StrCmdDebugRaidSeed)
    printHelp("clear", L.StrCmdDebugRaidClear)
    printHelp("rolls [tie]", L.StrCmdDebugRaidRolls)
    printHelp("roll <1-4|name> [1-100]", L.StrCmdDebugRaidRoll)
end

local debugNoActiveRollReasons = {
    record_inactive = true,
    missing_item = true,
    session_inactive = true,
}

local function reportDebugRaidError(reason, playerRef)
    if reason == "no_current_raid" then
        addon:warn(L.MsgDebugRaidNoCurrent)
        return
    end
    if reason == "invalid_player" or reason == "unknown_player" then
        addon:warn(L.MsgDebugRaidUnknownPlayer, tostring(playerRef or "?"))
        return
    end
    if reason == "invalid_roll" then
        addon:warn(L.MsgDebugRaidInvalidRoll)
        return
    end
    if reason == "raid_service_unavailable" then
        addon:warn(L.MsgFeatureUnavailable, "Debug", "raid")
        return
    end
    if reason == "rolls_service_unavailable" then
        addon:warn(L.MsgFeatureUnavailable, "Debug", "rolls")
        return
    end
    if debugNoActiveRollReasons[reason] then
        addon:warn(L.MsgDebugRaidNoActiveRoll)
        return
    end
    addon:warn(L.MsgDebugRaidRollRejected, tostring(playerRef or "?"), tostring(reason or "unknown"))
end

local function handleDebugRaidCommand(arg)
    local raidCmd, raidArg = Strings.SplitArgs(arg)
    local result
    local err
    local playerRef
    local rollArg

    local debugService = Services and Services.Debug or nil
    if not debugService then
        addon:warn(L.MsgFeatureUnavailable, "Debug", "raid")
        return
    end

    if raidCmd == "" then
        raidCmd = nil
    end
    if not raidCmd or raidCmd == "help" then
        showDebugRaidHelp()
        return
    end

    if raidCmd == "seed" or raidCmd == "add" then
        result, err = debugService:SeedRaidPlayers()
        if not result then
            reportDebugRaidError(err)
            return
        end
        addon:info(L.MsgDebugRaidSeeded, result.total, result.added, result.refreshed)
        return
    end

    if raidCmd == "clear" or raidCmd == "reset" then
        result, err = debugService:ClearRaidPlayers()
        if not result then
            reportDebugRaidError(err)
            return
        end
        addon:info(L.MsgDebugRaidCleared, result.removed, result.blocked)
        if result.clearedRolls then
            addon:info(L.MsgDebugRaidClearResetRolls)
        end
        return
    end

    if raidCmd == "rolls" or raidCmd == "all" then
        local rollsMode, rollsModeExtra = Strings.SplitArgs(raidArg)
        if rollsMode == "" then
            rollsMode = nil
        end
        if (rollsMode and rollsMode ~= "tie") or (rollsModeExtra and rollsModeExtra ~= "") then
            showDebugRaidHelp()
            return
        end

        result, err = debugService:RequestRaidRolls(rollsMode)
        if not result then
            reportDebugRaidError(err)
            return
        end
        if result.submitted <= 0 and result.firstFailure then
            if debugNoActiveRollReasons[result.firstFailure] then
                reportDebugRaidError(result.firstFailure)
            else
                addon:warn(L.MsgDebugRaidRollsPartial, result.submitted, result.total, tostring(result.firstFailure))
            end
            return
        end
        if result.failed > 0 and result.firstFailure then
            addon:warn(L.MsgDebugRaidRollsPartial, result.submitted, result.total, tostring(result.firstFailure))
            return
        end
        if result.tieMode then
            addon:info(L.MsgDebugRaidRollsTie, result.submitted, result.total, tonumber(result.tieCount) or 0, tonumber(result.tieRoll) or 0)
        else
            addon:info(L.MsgDebugRaidRolls, result.submitted, result.total)
        end
        return
    end

    if raidCmd == "roll" then
        playerRef, rollArg = Strings.SplitArgs(raidArg)
        if not playerRef or playerRef == "" then
            showDebugRaidHelp()
            return
        end

        result, err = debugService:RollRaidPlayer(playerRef, rollArg)
        if not result then
            reportDebugRaidError(err, playerRef)
            return
        end
        if not result.ok then
            reportDebugRaidError(result.reason, result.name)
            return
        end

        addon:info(L.MsgDebugRaidRollSingle, result.name, result.roll)
        return
    end

    showDebugRaidHelp()
end

local function getFeatureProfile()
    local features = addon.Features
    if type(features) == "table" and type(features.GetProfile) == "function" then
        return features:GetProfile()
    end
    return "full"
end

local function notifyWidgetCallUnavailable(widgetId, methodName)
    if type(UI.IsEnabled) == "function" and not UI:IsEnabled(widgetId) then
        addon:warn(L.MsgFeatureDisabledByProfile, widgetId, getFeatureProfile())
        return
    end
    addon:warn(L.MsgFeatureUnavailable, widgetId, methodName)
end

local function callWidget(widgetId, methodName, ...)
    if type(UI.IsEnabled) == "function" and not UI:IsEnabled(widgetId) then
        notifyWidgetCallUnavailable(widgetId, methodName)
        return nil
    end

    if type(UI.IsRegistered) == "function" and not UI:IsRegistered(widgetId) then
        notifyWidgetCallUnavailable(widgetId, methodName)
        return nil
    end

    return UI:Call(widgetId, methodName, ...)
end

local function registerAliases(list, fn)
    for _, cmd in ipairs(list) do
        module.sub[cmd] = fn
    end
end

local function isBlank(value)
    return not value or value == ""
end

local function isToggleCommand(sub)
    return isBlank(sub) or sub == "toggle"
end

local function callSyncerMethod(methodName, ...)
    local syncer = getCoreService("GetSyncer")
    local method = syncer and syncer[methodName]
    if type(method) == "function" then
        return method(syncer, ...)
    end
    return nil
end

local function callSyncerMethodWithTarget(methodName, args)
    local raidRefArg, targetArg = Strings.SplitArgs(args)
    callSyncerMethod(methodName, tonumber(raidRefArg), targetArg)
end

local function getVersionInfo()
    local getter = Comms and Comms.GetVersionInfo
    if type(getter) == "function" then
        return getter()
    end

    local unknown = tostring(L.StrUnknown)
    local schemaGetter = Core and Core.GetRaidSchemaVersion
    local syncer = getCoreService("GetSyncer")
    local syncGetter = syncer and syncer.GetProtocolVersion

    return {
        addonVersion = unknown,
        interfaceVersion = unknown,
        raidSchemaVersion = type(schemaGetter) == "function" and tostring(schemaGetter() or unknown) or unknown,
        syncProtocolVersion = type(syncGetter) == "function" and tostring(syncGetter(syncer) or unknown) or unknown,
    }
end

local function getLogLevelName()
    local level = addon.GetLogLevel and addon:GetLogLevel() or nil
    for name, value in pairs(addon.logLevels or {}) do
        if value == level then
            return tostring(name)
        end
    end
    return tostring(level or L.StrUnknown)
end

local function yesNo(value)
    if value then
        return L.StrYes
    end
    return L.StrNo
end

local function countRaidHistory()
    local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("SlashEvents.BugReport", { "GetAllRaids" }) or nil
    local raids = raidStore and raidStore:GetAllRaids() or nil
    if type(raids) ~= "table" then
        return 0
    end
    return #raids
end

local function countReserves()
    local reserves = _G.KRT_Reserves
    local players = 0
    local entries = 0
    if type(reserves) ~= "table" then
        return players, entries
    end

    for _, record in pairs(reserves) do
        players = players + 1
        local list = record and record.reserves
        if type(list) == "table" then
            entries = entries + #list
        end
    end
    return players, entries
end

local function getCurrentRaidSummary()
    local currentRaid = Core and Core.GetCurrentRaid and Core.GetCurrentRaid() or nil
    local raidNid
    local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("SlashEvents.CurrentRaid", { "GetRaidNidByIndex" }) or nil
    if raidStore and currentRaid and raidStore.GetRaidNidByIndex then
        raidNid = raidStore:GetRaidNidByIndex(currentRaid)
    end
    return tostring(currentRaid or L.StrNone), tostring(raidNid or L.StrNone)
end

local function getRoleState()
    local raid = Services and Services.Raid or nil
    if raid and type(raid.GetPlayerRoleState) == "function" then
        return raid:GetPlayerRoleState() or {}
    end
    return {}
end

local function showVersion()
    local info = getVersionInfo()
    addon:info(L.MsgVersionTitle)
    addon:info(L.MsgVersionAddon:format(info.addonVersion))
    addon:info(L.MsgVersionInterface:format(info.interfaceVersion))
    addon:info(L.MsgVersionRaidSchema:format(info.raidSchemaVersion))
    addon:info(L.MsgVersionSyncProtocol:format(info.syncProtocolVersion))
end

local function showBugReport()
    local reservePlayers, reserveEntries = countReserves()
    local currentRaid, raidNid = getCurrentRaidSummary()
    local role = getRoleState()
    local info = getVersionInfo()

    addon:info(L.MsgBugReportTitle)
    addon:info(L.MsgVersionAddon:format(info.addonVersion))
    addon:info(L.MsgVersionInterface:format(info.interfaceVersion))
    addon:info(L.MsgVersionRaidSchema:format(info.raidSchemaVersion))
    addon:info(L.MsgVersionSyncProtocol:format(info.syncProtocolVersion))
    addon:info(L.MsgBugReportLog:format(getLogLevelName(), yesNo(Options.IsDebugEnabled and Options.IsDebugEnabled())))
    addon:info(L.MsgBugReportCurrentRaid:format(currentRaid, raidNid))
    addon:info(L.MsgBugReportRaidHistory:format(countRaidHistory()))
    addon:info(L.MsgBugReportReserves:format(reservePlayers, reserveEntries))
    addon:info(L.MsgBugReportRole:format(yesNo(role.inRaid), yesNo(role.isLeader), yesNo(role.isAssistant), yesNo(role.isMasterLooter)))
end

local function handleDebugCommand(rest)
    local subCmd, arg = Strings.SplitArgs(rest)
    if isBlank(subCmd) then
        subCmd = nil
    end

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
            if addon.Timer and addon.Timer.RefreshStats then
                addon.Timer.RefreshStats()
                addon:info("Timer stats reset.")
            end
        else
            if addon.Timer and addon.Timer.ShowStats then
                addon.Timer.ShowStats(arg)
            else
                addon:warn("Timer module not available.")
            end
        end
        return
    end

    if subCmd == "raid" or subCmd == "players" then
        handleDebugRaidCommand(arg)
        return
    end

    if subCmd == "on" then
        Options.SetDebugEnabled(true)
    elseif subCmd == "off" then
        Options.SetDebugEnabled(false)
    else
        Options.SetDebugEnabled(not Options.IsDebugEnabled())
    end

    if Options.IsDebugEnabled() then
        addon:info(L.MsgDebugOn)
    else
        addon:info(L.MsgDebugOff)
    end
end

local function formatPerfThreshold(value)
    local n = tonumber(value) or 0
    if n == floor(n) then
        return tostring(n)
    end
    return format("%.1f", n)
end

local function getPerfThreshold()
    if addon.GetPerfThresholdMs then
        return addon:GetPerfThresholdMs()
    end
    return 5
end

local function isPerfEnabled()
    if addon.IsPerfModeEnabled then
        return addon:IsPerfModeEnabled()
    end
    return addon.State and addon.State.perfEnabled == true
end

local function setPerfEnabled(enabled)
    if addon.SetPerfMode then
        return addon:SetPerfMode(enabled)
    end
    addon.State = addon.State or {}
    addon.State.perfEnabled = enabled and true or false
    addon.hasPerf = addon.State.perfEnabled and true or nil
    return addon.State.perfEnabled
end

local function setPerfThreshold(value)
    if addon.SetPerfThresholdMs then
        return addon:SetPerfThresholdMs(value)
    end
    local threshold = tonumber(value)
    if not threshold or threshold < 0 then
        return nil
    end
    addon.State = addon.State or {}
    addon.State.perfThresholdMs = threshold
    return threshold
end

local function handlePerfCommand(rest)
    local subCmd, arg = Strings.SplitArgs(rest)
    if isBlank(subCmd) then
        subCmd = "status"
    end

    if subCmd == "on" then
        setPerfEnabled(true)
        addon:info(L.MsgPerfOn:format(formatPerfThreshold(getPerfThreshold())))
        return
    end

    if subCmd == "off" then
        setPerfEnabled(false)
        addon:info(L.MsgPerfOff)
        return
    end

    if subCmd == "threshold" or subCmd == "th" or subCmd == "ms" then
        local threshold = setPerfThreshold(arg)
        if not threshold then
            addon:warn(L.MsgPerfThresholdInvalid)
            return
        end
        addon:info(L.MsgPerfThreshold:format(formatPerfThreshold(threshold)))
        return
    end

    if subCmd == "status" then
        local status = isPerfEnabled() and L.StrEnabled or L.StrDisabled
        addon:info(L.MsgPerfStatus:format(status, formatPerfThreshold(getPerfThreshold())))
        return
    end

    addon:info(format(L.StrCmdCommands, "krt perf"), "KRT")
    printHelp("on", L.StrCmdPerfOn)
    printHelp("off", L.StrCmdPerfOff)
    printHelp("threshold <ms>", L.StrCmdPerfThreshold)
end

local function handleMinimapCommand(rest)
    local sub, arg = Strings.SplitArgs(rest)
    if sub == "on" then
        Options.Set("minimapButton", true)
        Frames.SetShown(KRT_MINIMAP_GUI, true)
    elseif sub == "off" then
        Options.Set("minimapButton", false)
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
end

local function handleAchievementCommand(_, _, raw)
    if not raw or not raw:find("achievement:%d*:") then
        addon:info(format(L.StrCmdCommands, "krt ach"), "KRT")
        return
    end

    local from, to = raw:find("achievement%:%d*%:")
    if not (from and to) then
        return
    end
    local id = raw:sub(from + 12, to - 1)
    from, to = raw:find("%|cffffff00%|Hachievement%:.*%]%|h%|r")
    local name = (from and to) and raw:sub(from, to) or ""
    printHelp("KRT", name .. " - ID#" .. id)
end

local function handleConfigCommand(rest)
    local sub = Strings.SplitArgs(rest)
    if sub == "reset" then
        callWidget("Config", "Default")
    else
        callWidget("Config", "Toggle")
    end
end

local function handleWarningsCommand(rest)
    local sub = Strings.SplitArgs(rest)
    if isToggleCommand(sub) then
        Core.RequestControllerMethod("Warnings", "Toggle")
    elseif sub == "help" then
        addon:info(format(L.StrCmdCommands, "krt rw"), "KRT")
        printHelp("toggle", L.StrCmdToggle)
        printHelp("[ID]", L.StrCmdWarningAnnounce)
    else
        Core.RequestControllerMethod("Warnings", "Announce", sub)
    end
end

local function handleChangesCommand(rest)
    local sub = Strings.SplitArgs(rest)
    if isToggleCommand(sub) then
        Core.RequestControllerMethod("Changes", "Toggle")
    elseif sub == "demand" or sub == "ask" then
        Core.RequestControllerMethod("Changes", "Demand")
    elseif sub == "announce" or sub == "spam" then
        Core.RequestControllerMethod("Changes", "Announce")
    else
        addon:info(format(L.StrCmdCommands, "krt ms"), "KRT")
        printHelp("toggle", L.StrCmdToggle)
        printHelp("demand", L.StrCmdChangesDemand)
        printHelp("announce", L.StrCmdChangesAnnounce)
    end
end

local function handleLoggerCommand(rest)
    local sub, arg = Strings.SplitArgs(rest)
    if isToggleCommand(sub) then
        Core.RequestControllerMethod("Logger", "Toggle")
    elseif sub == "req" then
        callSyncerMethodWithTarget("RequestLoggerReq", arg)
    elseif sub == "push" then
        callSyncerMethodWithTarget("BroadcastLoggerPush", arg)
    elseif sub == "sync" then
        callSyncerMethod("RequestLoggerSync")
    else
        addon:info(format(L.StrCmdCommands, "krt logger"), "KRT")
        printHelp("toggle", L.StrCmdToggle)
        printHelp("req <raidId|raidNid> <player>", L.StrCmdLoggerReq)
        printHelp("push <raidId|raidNid> <player>", L.StrCmdLoggerPush)
        printHelp("sync", L.StrCmdLoggerSync)
    end
end

local function handleLootCommand(rest)
    local sub = Strings.SplitArgs(rest)
    if isToggleCommand(sub) then
        Core.RequestControllerMethod("Master", "Toggle")
    end
end

local function handleCounterCommand(rest)
    local sub = Strings.SplitArgs(rest)
    if isToggleCommand(sub) then
        callWidget("LootCounter", "Toggle")
    end
end

local function handleReservesCommand(rest)
    local sub = Strings.SplitArgs(rest)
    local reserves = Services and Services.Reserves or nil
    local sync = reserves and reserves._Sync or nil
    if isToggleCommand(sub) then
        callWidget("Reserves", "Toggle")
    elseif sub == "import" then
        callWidget("Reserves", "ToggleImport")
    elseif sub == "sync" then
        if sync and sync.RequestMetadata then
            sync:RequestMetadata()
        else
            addon:warn(L.MsgFeatureUnavailable, "Reserves", "sync")
        end
    elseif sub == "meta" then
        if reserves and reserves.GetSyncMetadata then
            local meta = reserves:GetSyncMetadata()
            addon:info(
                L.MsgReservesSyncMetaLocal:format(
                    tostring(meta.source or L.StrUnknown),
                    tostring(meta.checksum or L.StrUnknown),
                    tostring(meta.mode or L.StrUnknown),
                    tonumber(meta.players) or 0,
                    tonumber(meta.entries) or 0,
                    (meta.runtime and L.StrYes or L.StrNo)
                )
            )
        else
            addon:warn(L.MsgFeatureUnavailable, "Reserves", "meta")
        end
    elseif sub == "clearcache" then
        if reserves and reserves.DeleteSyncedReservesCache and reserves:DeleteSyncedReservesCache() then
            addon:info(L.MsgReservesSyncCacheCleared)
        else
            addon:warn(L.MsgReservesSyncNoRuntimeCache)
        end
    else
        addon:info(format(L.StrCmdCommands, "krt res"), "KRT")
        printHelp("toggle", L.StrCmdToggle)
        printHelp("import", L.StrCmdReservesImport)
        printHelp("sync", L.StrCmdReservesSync)
        printHelp("meta", L.StrCmdReservesMeta)
        printHelp("clearcache", L.StrCmdReservesClearCache)
    end
end

local function handleValidateCommand(rest)
    local sub, arg = Strings.SplitArgs(rest)
    if sub == "raids" then
        local verboseArg = Strings.SplitArgs(arg)
        local validator = getCoreService("GetRaidValidator")
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
end

local function handleLfmCommand(rest)
    local sub = Strings.SplitArgs(rest)
    if isToggleCommand(sub) or sub == "show" then
        Core.RequestControllerMethod("Spammer", "Toggle")
    elseif sub == "start" then
        Core.RequestControllerMethod("Spammer", "Start")
    elseif sub == "stop" then
        Core.RequestControllerMethod("Spammer", "Stop")
    else
        addon:info(format(L.StrCmdCommands, "krt pug"), "KRT")
        printHelp("toggle", L.StrCmdToggle)
        printHelp("start", L.StrCmdLFMStart)
        printHelp("stop", L.StrCmdLFMStop)
    end
end

local function handleHelpCommand(rest)
    local topic = Strings.SplitArgs(rest)
    if isBlank(topic) then
        showHelp()
        return
    end

    if topic == "logger" or topic == "history" or topic == "log" then
        handleLoggerCommand("help")
    elseif topic == "res" or topic == "reserve" or topic == "reserves" then
        handleReservesCommand("help")
    elseif topic == "ml" or topic == "loot" or topic == "master" then
        showLootHelp()
    elseif topic == "counter" or topic == "counters" or topic == "counts" then
        showCounterHelp()
    elseif topic == "debug" or topic == "dbg" or topic == "debugger" then
        addon:info(format(L.StrCmdCommands, "krt debug"), "KRT")
        printHelp("on", L.StrCmdToggle)
        printHelp("off", L.StrCmdToggle)
        printHelp("level <name|num>", L.StrCmdDebugLevel)
        printHelp("raid", L.StrCmdDebugRaid)
    elseif topic == "perf" or topic == "performance" then
        handlePerfCommand("help")
    elseif topic == "rw" or topic == "warn" or topic == "warning" or topic == "warnings" then
        handleWarningsCommand("help")
    elseif topic == "ms" or topic == "changes" or topic == "mschanges" then
        handleChangesCommand("help")
    elseif topic == "lfm" or topic == "pug" or topic == "group" or topic == "grouper" then
        handleLfmCommand("help")
    elseif topic == "config" or topic == "conf" or topic == "options" or topic == "opt" then
        addon:info(format(L.StrCmdCommands, "krt config"), "KRT")
        printHelp("toggle", L.StrCmdToggle)
        printHelp("reset", L.StrCmdConfigReset)
    elseif topic == "minimap" or topic == "mm" then
        handleMinimapCommand("help")
    elseif topic == "validate" then
        handleValidateCommand("help")
    elseif topic == "version" or topic == "ver" or topic == "about" then
        showVersion()
    elseif topic == "bug" or topic == "report" then
        showBugReport()
    else
        showHelp()
    end
end

local function handleBugCommand()
    showBugReport()
end

local function handleVersionCommand(rest)
    showVersion()
    local sub = Strings.SplitArgs(rest)
    if sub ~= "local" and Comms and Comms.RequestVersionCheck then
        Comms:RequestVersionCheck()
    end
end

-- ----- Public methods ----- --
function module:Register(cmd, fn)
    self.sub[cmd] = fn
end

function module:Handle(msg)
    if isBlank(msg) then
        showHelp()
        return
    end

    local cmd, rest = Strings.SplitArgs(msg)
    if isBlank(cmd) then
        showHelp()
        return
    end

    local requiresLootAccess = (lootOnlySlashCommands[cmd] == true)
    local raid = Services and Services.Raid or nil
    if requiresLootAccess and raid and raid.EnsureMasterOnlyAccess and not raid:EnsureMasterOnlyAccess() then
        return
    end

    if cmd == "show" or cmd == "toggle" then
        Core.RequestControllerMethod("Master", "Toggle")
        return
    end
    local fn = self.sub[cmd]
    if fn then
        return fn(rest, cmd, msg)
    end
    showHelp()
end

registerAliases(cmdHelp, handleHelpCommand)
registerAliases(cmdBug, handleBugCommand)
registerAliases(cmdVersion, handleVersionCommand)
registerAliases(cmdDebug, handleDebugCommand)
registerAliases(cmdPerf, handlePerfCommand)
registerAliases(cmdMinimap, handleMinimapCommand)
registerAliases(cmdAchiev, handleAchievementCommand)
registerAliases(cmdConfig, handleConfigCommand)
registerAliases(cmdWarnings, handleWarningsCommand)
registerAliases(cmdChanges, handleChangesCommand)
registerAliases(cmdLogger, handleLoggerCommand)
registerAliases(cmdLoot, handleLootCommand)
registerAliases(cmdCounter, handleCounterCommand)
registerAliases(cmdReserves, handleReservesCommand)
registerAliases(cmdValidate, handleValidateCommand)
registerAliases(cmdLFM, handleLfmCommand)

-- Register slash commands
SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
SlashCmdList["KRT"] = function(msg)
    module:Handle(msg)
end
