--[[
    Features/SlashEvents.lua
]]

local addonName, addon = ...
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils

local RT_COLOR = feature.RT_COLOR

local pairs, ipairs, select = pairs, ipairs, select
local format = string.format
local upper = string.upper
local tostring, tonumber = tostring, tonumber

-- =========== Slash Commands  =========== --
do
    addon.Slash = addon.Slash or {}
    local module = addon.Slash

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
            Utils.applyDebugSetting(not Utils.isDebugEnabled())
        end

        if Utils.isDebugEnabled() then
            addon:info(L.MsgDebugOn)
        else
            addon:info(L.MsgDebugOff)
        end
    end)

    registerAliases(cmdMinimap, function(rest)
        local sub, arg = Utils.splitArgs(rest)
        if sub == "on" then
            Utils.setOption("minimapButton", true)
            Utils.setShown(KRT_MINIMAP_GUI, true)
        elseif sub == "off" then
            Utils.setOption("minimapButton", false)
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

    registerAliases(cmdCounter, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            if addon.LootCounter and addon.LootCounter.Toggle then addon.LootCounter:Toggle() end
        end
    end)

    registerAliases(cmdReserves, function(rest)
        local sub = Utils.splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Reserves:Toggle()
        elseif sub == "import" then
            if addon.ReservesImport and addon.ReservesImport.Toggle then addon.ReservesImport:Toggle() end
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
        module:Handle(msg)
    end
end

-- =========== Main Event Handlers  =========== --
local addonEvents = {
    CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM",
    CHAT_MSG_LOOT = "CHAT_MSG_LOOT",
    CHAT_MSG_MONSTER_YELL = "CHAT_MSG_MONSTER_YELL",
    RAID_ROSTER_UPDATE = "RAID_ROSTER_UPDATE",
    PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
    COMBAT_LOG_EVENT_UNFILTERED = "COMBAT_LOG_EVENT_UNFILTERED",
    RAID_INSTANCE_WELCOME = "RAID_INSTANCE_WELCOME",
    LOOT_CLOSED = "LOOT_CLOSED",
    LOOT_OPENED = "LOOT_OPENED",
    LOOT_SLOT_CLEARED = "LOOT_SLOT_CLEARED",
    TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
    TRADE_REQUEST_CANCEL = "TRADE_REQUEST_CANCEL",
    TRADE_CLOSED = "TRADE_CLOSED",
}

-- Master looter events
do
    local forward = {
        LOOT_OPENED = "LOOT_OPENED",
        LOOT_CLOSED = "LOOT_CLOSED",
        LOOT_SLOT_CLEARED = "LOOT_SLOT_CLEARED",
        TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
        TRADE_REQUEST_CANCEL = "TRADE_REQUEST_CANCEL",
        TRADE_CLOSED = "TRADE_CLOSED",
    }
    for e, m in pairs(forward) do
        local method = m
        addon[e] = function(_, ...)
            addon.Master[method](addon.Master, ...)
        end
    end
end

-- ADDON_LOADED: Initializes the addon after loading.
function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    local lvl = addon.GetLogLevel and addon:GetLogLevel()
    addon:info(Diag.I.LogCoreLoaded:format(tostring(GetAddOnMetadata(addonName, "Version")),
        tostring(lvl), tostring(true)))
    addon.LoadOptions()
    addon.Reserves:Load()
    for event in pairs(addonEvents) do
        self:RegisterEvent(event)
    end
    addon:debug(Diag.D.LogCoreEventsRegistered:format(addon.tLength(addonEvents)))
    self:RAID_ROSTER_UPDATE(true)
end

local rosterUpdateDebounceSeconds = 0.2

local function processRaidRosterUpdate()
    local changed, delta = addon.Raid:UpdateRaidRoster()
    if not changed then
        return
    end

    -- Single source of truth for roster change notifications (join/update/leave delta).
    Utils.triggerEvent("RaidRosterDelta", delta, addon.Raid:GetRosterVersion(), KRT_CurrentRaid)
    -- Keep Master Looter UI in sync (event-driven; no polling).
    local mf = addon.Master and addon.Master.frame
    if addon.Master and addon.Master.RequestRefresh and mf and mf.IsShown and mf:IsShown() then
        addon.Master:RequestRefresh()
    end

    -- If the Logger is open on the *current* raid, keep the visible lists in sync automatically.
    -- (Throttled to avoid multiple redraws during bursty roster updates.)
    local log = addon.Logger
    local logFrame = log and log.frame
    if not (log and logFrame and logFrame.IsShown and logFrame:IsShown()) then return end
    if not (KRT_CurrentRaid and log.selectedRaid and tonumber(log.selectedRaid) == tonumber(KRT_CurrentRaid)) then
        return
    end

    addon.CancelTimer(log._rosterUiHandle, true)
    log._rosterUiHandle = addon.NewTimer(0.25, function()
        if not (logFrame and logFrame.IsShown and logFrame:IsShown()) then return end
        if not (KRT_CurrentRaid and log.selectedRaid and tonumber(log.selectedRaid) == tonumber(KRT_CurrentRaid)) then
            return
        end

        if log.RaidAttendees and log.RaidAttendees._ctrl and log.RaidAttendees._ctrl.Dirty then
            log.RaidAttendees._ctrl:Dirty()
        end
        if log.BossAttendees and log.BossAttendees._ctrl and log.BossAttendees._ctrl.Dirty then
            log.BossAttendees._ctrl:Dirty()
        end
        if log.Loot and log.Loot._ctrl and log.Loot._ctrl.Dirty then
            log.Loot._ctrl:Dirty()
        end
    end)
end

-- RAID_ROSTER_UPDATE: Updates the raid roster when it changes.
function addon:RAID_ROSTER_UPDATE(forceImmediate)
    addon.CancelTimer(self._raidRosterUpdateHandle, true)
    self._raidRosterUpdateHandle = nil

    if forceImmediate then
        processRaidRosterUpdate()
        return
    end

    self._raidRosterUpdateHandle = addon.NewTimer(rosterUpdateDebounceSeconds, function()
        self._raidRosterUpdateHandle = nil
        processRaidRosterUpdate()
    end)
end

-- RAID_INSTANCE_WELCOME: Triggered when entering a raid instance.
function addon:RAID_INSTANCE_WELCOME(...)
    local instanceName, instanceType, instanceDiff = GetInstanceInfo()
    local _, nextReset = ...
    KRT_NextReset = nextReset
    addon:trace(Diag.D.LogRaidInstanceWelcome:format(tostring(instanceName), tostring(instanceType),
        tostring(instanceDiff), tostring(KRT_NextReset)))
    if instanceType == "raid" and not L.RaidZones[instanceName] then
        addon:warn(Diag.W.LogRaidUnmappedZone:format(tostring(instanceName), tostring(instanceDiff)))
    end
    if L.RaidZones[instanceName] ~= nil then
        addon:debug(Diag.D.LogRaidInstanceRecognized:format(tostring(instanceName), tostring(instanceDiff)))
        addon.After(3, function()
            addon.Raid:Check(instanceName, instanceDiff)
        end)
    end
end

-- PLAYER_ENTERING_WORLD: Performs initial checks when the player logs in.
function addon:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local module = self.Raid
    addon:trace(Diag.D.LogCorePlayerEnteringWorld)
    -- Restart the first-check timer on login
    addon.CancelTimer(module.firstCheckHandle, true)
    module.firstCheckHandle = nil
    module.firstCheckHandle = addon.NewTimer(3, function() module:FirstCheck() end)
end

-- CHAT_MSG_LOOT: Adds looted items to the raid log.
function addon:CHAT_MSG_LOOT(msg)
    addon:trace(Diag.D.LogLootChatMsgLootRaw:format(tostring(msg)))
    if KRT_CurrentRaid then
        self.Raid:AddLoot(msg)
    end
end

-- CHAT_MSG_SYSTEM: Forwards roll messages to the Rolls module.
function addon:CHAT_MSG_SYSTEM(msg)
    addon.Rolls:CHAT_MSG_SYSTEM(msg)
end

-- CHAT_MSG_MONSTER_YELL: Logs a boss kill based on specific boss yells.
function addon:CHAT_MSG_MONSTER_YELL(...)
    local text = ...
    if L.BossYells[text] and KRT_CurrentRaid then
        addon:trace(Diag.D.LogBossYellMatched:format(tostring(text), tostring(L.BossYells[text])))
        self.Raid:AddBoss(L.BossYells[text])
    end
end

-- COMBAT_LOG_EVENT_UNFILTERED: Logs a boss kill when a boss unit dies.
function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
    if not KRT_CurrentRaid then return end

    -- Hot-path fast check: inspect the event type before unpacking extra args.
    local subEvent = select(2, ...)
    if subEvent ~= "UNIT_DIED" then return end

    -- 3.3.5a base params (8):
    -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags
    local destGUID, destName, destFlags = select(6, ...)
    if bit.band(destFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then return end

    -- LibCompat embeds GetCreatureId with the 3.3.5a GUID parsing rules.
    local npcId = destGUID and addon.GetCreatureId(destGUID)
    local bossLib = addon.BossIDs
    local bossIds = bossLib and bossLib.BossIDs
    if not (npcId and bossIds and bossIds[npcId]) then return end

    local boss = destName or bossLib:GetBossName(npcId)
    if boss then
        addon:trace(Diag.D.LogBossUnitDiedMatched:format(tonumber(npcId) or -1, tostring(boss)))
        self.Raid:AddBoss(boss)
    end
end
