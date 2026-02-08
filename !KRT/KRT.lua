--[[
    KRT.lua
]]

local addonName, addon    = ...
addon                     = addon or {}
addon.name                = addon.name or addonName
addon.L                   = addon.L or {}
addon.Diagnose            = addon.Diagnose or {}
local L                   = addon.L
local Diagnose            = addon.Diagnose
local Diag                = setmetatable({}, {
    __index = Diagnose,
})
local Utils               = addon.Utils
local C                   = addon.C

local _G                  = _G
_G["KRT"]                 = addon

-- =========== Constants  =========== --

local ITEM_LINK_PATTERN   = C.ITEM_LINK_PATTERN
local rollTypes           = C.rollTypes
local lootTypesColored    = C.lootTypesColored
local itemColors          = C.itemColors
local RAID_TARGET_MARKERS = C.RAID_TARGET_MARKERS
local K_COLOR             = C.K_COLOR
local RT_COLOR            = C.RT_COLOR

-- =========== Saved Variables  =========== --
-- These variables are persisted across sessions for the addon.

KRT_Options               = KRT_Options or {}
KRT_Raids                 = KRT_Raids or {}
KRT_Players               = KRT_Players or {}
KRT_Warnings              = KRT_Warnings or {}
KRT_ExportString          = KRT_ExportString or "$I,$N,$S,$W,$T,$R,$H:$M,$d/$m/$y"
KRT_Spammer               = KRT_Spammer or {}
KRT_CurrentRaid           = KRT_CurrentRaid or nil
KRT_LastBoss              = KRT_LastBoss or nil
KRT_NextReset             = KRT_NextReset or 0
KRT_SavedReserves         = KRT_SavedReserves or {}
KRT_PlayerCounts          = KRT_PlayerCounts or {}

-- =========== External Libraries / Bootstrap  =========== --
local Compat              = LibStub("LibCompat-1.0")
addon.Compat              = Compat
addon.BossIDs             = LibStub("LibBossIDs-1.0")
addon.Debugger            = LibStub("LibLogger-1.0")
addon.Deformat            = LibStub("LibDeformat-3.0")
addon.CallbackHandler     = LibStub("CallbackHandler-1.0")

Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
addon.Debugger:Embed(addon)

-- Keep LibCompat chat output behavior, but without prepending tostring(addon) ("table: ...").
function addon:Print(...)
    return Compat.Print(Compat, ...)
end

-- Local aliases (safe and fast)
local UnitIsGroupLeader    = addon.UnitIsGroupLeader
local UnitIsGroupAssistant = addon.UnitIsGroupAssistant
local tContains            = _G.tContains

do
    local lv = addon.Debugger.logLevels.INFO
    if KRT_Options and KRT_Options.debug then
        lv = addon.Debugger.logLevels.DEBUG
    end
    addon:SetLogLevel(lv)
end

-- =========== Core Addon Frames & Locals  =========== --

-- Centralised addon state
addon.State                = addon.State or {}
local coreState            = addon.State

coreState.frames           = coreState.frames or {}
local Frames               = coreState.frames
Frames.main                = Frames.main or CreateFrame("Frame")

-- Addon UI Frames
local mainFrame            = Frames.main

-- Player info helper
coreState.player           = coreState.player or {}
-- Rolls & Loot
coreState.loot             = coreState.loot or {}
local lootState            = coreState.loot
lootState.itemInfo         = lootState.itemInfo or {}
lootState.currentRollType  = lootState.currentRollType or 4
lootState.currentRollItem  = lootState.currentRollItem or 0
lootState.currentItemIndex = lootState.currentItemIndex or 0
lootState.itemCount        = lootState.itemCount or 1
lootState.lootCount        = lootState.lootCount or 0
lootState.rollsCount       = lootState.rollsCount or 0
lootState.itemTraded       = lootState.itemTraded or 0
lootState.rollStarted      = lootState.rollStarted or false
if lootState.opened == nil then lootState.opened = false end
if lootState.fromInventory == nil then lootState.fromInventory = false end
lootState.pendingAwards = lootState.pendingAwards or {}

local itemInfo          = lootState.itemInfo

-- Function placeholders for loot helpers
local ItemExists, ItemIsSoulbound, GetItem
local GetItemIndex, GetItemName, GetItemLink, GetItemTexture

function GetItemIndex()
    return lootState.currentItemIndex
end

-- =========== Cached Functions & Libraries  =========== --

local tinsert, tremove, tconcat, twipe  = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local format, find, strlen              = string.format, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber                = tostring, tonumber
local UnitRace, UnitSex, GetRealmName   = UnitRace, UnitSex, GetRealmName
-- =========== Event System (WoW API events)  =========== --
-- Clean frame-based dispatcher (NO CallbackHandler here)
do
    -- listeners[event] = { obj1, obj2, ... }
    local listeners = {}

    local function HandleEvent(_, e, ...)
        local list = listeners[e]
        if not list then return end

        for i = 1, #list do
            local obj = list[i]
            local fn = obj and obj[e]
            if type(fn) == "function" then
                local ok, err = pcall(fn, obj, ...)
                if not ok then
                    addon:error(Diag.E.LogCoreEventHandlerFailed:format(tostring(e), tostring(err)))
                end
            end
        end
    end

    local function AddListener(obj, e)
        if type(e) ~= "string" or e == "" then
            error("Usage: RegisterEvent(\"EVENT_NAME\")", 3)
        end

        local list = listeners[e]
        if not list then
            list = {}
            listeners[e] = list
            mainFrame:RegisterEvent(e)
        else
            for i = 1, #list do
                if list[i] == obj then return end -- already registered
            end
        end

        list[#list + 1] = obj
    end

    local function RemoveListener(obj, e)
        local list = listeners[e]
        if not list then return end

        for i = #list, 1, -1 do
            if list[i] == obj then
                tremove(list, i)
            end
        end

        if #list == 0 then
            listeners[e] = nil
            mainFrame:UnregisterEvent(e)
        end
    end

    function addon:RegisterEvent(e)
        AddListener(self, e)
    end

    function addon:RegisterEvents(...)
        for i = 1, select("#", ...) do
            AddListener(self, select(i, ...))
        end
    end

    function addon:UnregisterEvent(e)
        RemoveListener(self, e)
    end

    function addon:UnregisterEvents()
        local keys = {}
        for e in pairs(listeners) do
            keys[#keys + 1] = e
        end
        for i = 1, #keys do
            RemoveListener(self, keys[i])
        end
    end

    function addon:UnregisterAllEvents()
        self:UnregisterEvents()
    end

    mainFrame:SetScript("OnEvent", HandleEvent)

    -- bootstrap
    addon:RegisterEvent("ADDON_LOADED")
end

-- Alias: redirect to Utils for backwards compatibility
-- (function moved to Utils.lua; this wrapper allows existing code to use addon:makeUIFrameController(...))
function addon:makeUIFrameController(getFrame, requestRefreshFn)
    return Utils.makeUIFrameController(getFrame, requestRefreshFn)
end

local function bindModuleRequestRefresh(module, getFrame)
    local requestRefresh = Utils.makeEventDrivenRefresher(getFrame, function()
        module:Refresh()
    end)

    function module:RequestRefresh()
        requestRefresh()
    end
end

local function bindModuleToggleHide(module, uiController)
    function module:Toggle()
        return uiController:Toggle()
    end

    function module:Hide()
        return uiController:Hide()
    end
end

local function makeModuleFrameGetter(module, globalFrameName)
    local getGlobalFrame = Utils.makeFrameGetter(globalFrameName)
    return function()
        local frame = module.frame or getGlobalFrame()
        if frame and not module.frame then
            module.frame = frame
        end
        return frame
    end
end

-- =========== Raid Helpers Module  =========== --
-- Manages raid state, roster, boss kills, and loot logging.
do
    addon.Raid              = addon.Raid or {}
    local module            = addon.Raid
    -- ----- Internal state ----- --
    local inRaid            = false
    local numRaid           = 0
    local rosterVersion     = 0
    local GetLootMethod     = GetLootMethod
    local GetRaidRosterInfo = GetRaidRosterInfo
    local UnitIsUnit        = UnitIsUnit

    -- ----- Logger Functions ----- --

    -- Updates the current raid roster, adding new players and marking those who left.
    function module:UpdateRaidRoster()
        rosterVersion = rosterVersion + 1
        if not KRT_CurrentRaid then return end
        -- Cancel any pending roster update timer and clear the handle
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil

        if not addon.IsInRaid() then
            numRaid = 0
            addon:debug(Diag.D.LogRaidLeftGroupEndSession)
            module:End()
            addon.Master:PrepareDropDowns()
            return
        end

        local raid = KRT_Raids[KRT_CurrentRaid]
        if not raid then return end

        local realm = Utils.getRealmName()
        KRT_Players[realm] = KRT_Players[realm] or {}

        raid.players = raid.players or {}

        raid.playersByName = raid.playersByName or {}
        local playersByName = raid.playersByName

        local n = GetNumRaidMembers()

        -- Keep internal state consistent immediately
        numRaid = n

        if n == 0 then
            module:End()
            return
        end

        local seen = {}

        for i = 1, n do
            local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)

                local player = playersByName[name]
                local active = player and player.leave == nil

                if not active then
                    player = {
                        name     = name,
                        rank     = rank or 0,
                        subgroup = subgroup or 1,
                        class    = class or "UNKNOWN",
                        join     = Utils.getCurrentTime(),
                        leave    = nil,
                        count    = (player and player.count) or 0,
                    }
                else
                    player.rank     = rank or player.rank or 0
                    player.subgroup = subgroup or player.subgroup or 1
                    player.class    = class or player.class or "UNKNOWN"
                end

                -- IMPORTANT: ensure raid.players stays consistent even if the array was cleared/edited.
                module:AddPlayer(player)

                seen[name] = true

                -- IMPORTANT: overwrite always
                KRT_Players[realm][name] = {
                    name   = name,
                    level  = level or 0,
                    race   = race,
                    raceL  = raceL,
                    class  = class or "UNKNOWN",
                    classL = classL,
                    sex    = UnitSex(unitID) or 0,
                }
            end
        end

        -- Mark leavers
        for pname, p in pairs(playersByName) do
            if p.leave == nil and not seen[pname] then
                p.leave = Utils.getCurrentTime()
            end
        end

        addon:debug(Diag.D.LogRaidRosterUpdate:format(rosterVersion, n))
        addon.Master:PrepareDropDowns()
    end

    -- Creates a new raid log entry.
    function module:Create(zoneName, raidSize)
        if KRT_CurrentRaid then
            self:End()
        end
        if not addon.IsInRaid() then return end

        local num = GetNumRaidMembers()
        if num == 0 then return end

        numRaid = num

        local realm = Utils.getRealmName()
        KRT_Players[realm] = KRT_Players[realm] or {}
        local currentTime = Utils.getCurrentTime()

        local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if isDyn then
            instanceDiff = instanceDiff + (2 * dynDiff)
        end

        local raidInfo = {
            realm         = realm,
            zone          = zoneName,
            size          = raidSize,
            difficulty    = tonumber(instanceDiff) or nil,
            players       = {},
            playersByName = {},
            bossKills     = {},
            loot          = {},
            nextBossNid   = 1,
            nextLootNid   = 1,
            startTime     = currentTime,
            changes       = {},
        }

        for i = 1, num do
            local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)

                local p = {
                    name     = name,
                    rank     = rank or 0,
                    subgroup = subgroup or 1,
                    class    = class or "UNKNOWN",
                    join     = Utils.getCurrentTime(),
                    leave    = nil,
                    count    = 0,
                }

                tinsert(raidInfo.players, p)
                raidInfo.playersByName[name] = p

                -- Overwrite always
                KRT_Players[realm][name] = {
                    name   = name,
                    level  = level or 0,
                    race   = race,
                    raceL  = raceL,
                    class  = class or "UNKNOWN",
                    classL = classL,
                    sex    = UnitSex(unitID) or 0,
                }
            end
        end

        tinsert(KRT_Raids, raidInfo)
        KRT_CurrentRaid = #KRT_Raids

        addon:info(Diag.I.LogRaidCreated:format(
            KRT_CurrentRaid or -1,
            tostring(zoneName),
            tonumber(raidSize) or -1,
            #raidInfo.players
        ))

        Utils.triggerEvent("RaidCreate", KRT_CurrentRaid)

        -- One clean refresh shortly after: cancel existing timer then start a new one
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        module.updateRosterHandle = addon.NewTimer(2, function() module:UpdateRaidRoster() end)
    end

    -- ----- Stable ID helpers (bossNid / lootNid) ----- --
    -- NOTE: Fresh SavedVariables only (schema v2). No legacy migration is performed.

    function module:EnsureStableIds(raidNum)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        if not raid then return end

        raid.players = raid.players or {}
        raid.playersByName = raid.playersByName or {}
        raid.bossKills = raid.bossKills or {}
        raid.loot = raid.loot or {}

        if raid.nextBossNid == nil then raid.nextBossNid = 1 end
        if raid.nextLootNid == nil then raid.nextLootNid = 1 end
    end

    function module:GetBossByNid(bossNid, raidNum)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        if not raid or bossNid == nil then return nil end
        module:EnsureStableIds(raidNum)

        bossNid = tonumber(bossNid) or 0
        if bossNid <= 0 then return nil end

        local bosses = raid.bossKills
        for i = 1, #bosses do
            local b = bosses[i]
            if b and tonumber(b.bossNid) == bossNid then
                return b, i
            end
        end
        return nil
    end

    function module:GetLootByNid(lootNid, raidNum)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        if not raid or lootNid == nil then return nil end
        module:EnsureStableIds(raidNum)

        lootNid = tonumber(lootNid) or 0
        if lootNid <= 0 then return nil end

        local loot = raid.loot
        for i = 1, #loot do
            local l = loot[i]
            if l and tonumber(l.lootNid) == lootNid then
                return l, i
            end
        end
        return nil
    end

    -- Ends the current raid log entry, marking end time.
    function module:End()
        if not KRT_CurrentRaid then return end
        -- Stop any pending roster update when ending the raid
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        local currentTime = Utils.getCurrentTime()
        local raid = KRT_Raids[KRT_CurrentRaid]
        if raid then
            local duration = currentTime - (raid.startTime or currentTime)
            addon:info(Diag.I.LogRaidEnded:format(KRT_CurrentRaid or -1, tostring(raid.zone),
                tonumber(raid.size) or -1, raid.bossKills and #raid.bossKills or 0,
                raid.loot and #raid.loot or 0, duration))
        end
        for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
            if not v.leave then v.leave = currentTime end
        end
        KRT_Raids[KRT_CurrentRaid].endTime = currentTime
        KRT_CurrentRaid = nil
        KRT_LastBoss = nil
    end

    -- Checks the current raid status and creates a new session if needed.
    function module:Check(instanceName, instanceDiff)
        addon:debug(Diag.D.LogRaidCheck:format(tostring(instanceName), tostring(instanceDiff),
            tostring(KRT_CurrentRaid)))
        if not KRT_CurrentRaid then
            module:Create(instanceName, (instanceDiff % 2 == 0 and 25 or 10))
        end

        local current = KRT_Raids[KRT_CurrentRaid]
        if current then
            if current.zone == instanceName then
                if current.size == 10 and (instanceDiff % 2 == 0) then
                    addon:info(L.StrNewRaidSessionChange)
                    addon:debug(Diag.D.LogRaidSessionChange:format(tostring(instanceName), 25,
                        tonumber(instanceDiff) or -1))
                    module:Create(instanceName, 25)
                elseif current.size == 25 and (instanceDiff % 2 ~= 0) then
                    addon:info(L.StrNewRaidSessionChange)
                    addon:debug(Diag.D.LogRaidSessionChange:format(tostring(instanceName), 10,
                        tonumber(instanceDiff) or -1))
                    module:Create(instanceName, 10)
                end
            else
                -- Zone changed: start a new raid session
                addon:info(L.StrNewRaidSessionChange)
                local newSize = (instanceDiff % 2 == 0 and 25 or 10)
                addon:debug(Diag.D.LogRaidSessionChange:format(tostring(instanceName), newSize,
                    tonumber(instanceDiff) or -1))
                module:Create(instanceName, newSize)
            end
        elseif (instanceDiff % 2 == 0) then
            addon:info(L.StrNewRaidSessionChange)
            addon:debug(Diag.D.LogRaidSessionCreate:format(tostring(instanceName), 25,
                tonumber(instanceDiff) or -1))
            module:Create(instanceName, 25)
        elseif (instanceDiff % 2 ~= 0) then
            addon:info(L.StrNewRaidSessionChange)
            addon:debug(Diag.D.LogRaidSessionCreate:format(tostring(instanceName), 10,
                tonumber(instanceDiff) or -1))
            module:Create(instanceName, 10)
        end
    end

    -- Performs an initial raid check on player login.
    function module:FirstCheck()
        -- Cancel any pending first-check timer before starting a new one
        addon.CancelTimer(module.firstCheckHandle, true)
        module.firstCheckHandle = nil
        if not addon.IsInGroup() then return end

        if KRT_CurrentRaid and module:CheckPlayer(Utils.getPlayerName(), KRT_CurrentRaid) then
            -- Restart the roster update timer: cancel the old one and schedule a new one
            addon.CancelTimer(module.updateRosterHandle, true)
            module.updateRosterHandle = nil
            module.updateRosterHandle = addon.NewTimer(2, function() module:UpdateRaidRoster() end)
            return
        end

        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        addon:debug(Diag.D.LogRaidFirstCheck:format(tostring(addon.IsInGroup()), tostring(KRT_CurrentRaid ~= nil),
            tostring(instanceName), tostring(instanceType), tostring(instanceDiff)))
        if instanceType == "raid" then
            module:Check(instanceName, instanceDiff)
            return
        end
    end

    -- Adds a player to the raid log.
    function module:AddPlayer(t, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        if not raidNum or not t or not t.name then return end
        local raid = KRT_Raids[raidNum]
        raid.playersByName = raid.playersByName or {}
        local players = module:GetPlayers(raidNum)
        local found = false
        for i, p in ipairs(players) do
            if t.name == p.name then
                -- Preserve count if present
                t.count = t.count or p.count or 0
                raid.players[i] = t
                raid.playersByName[t.name] = t
                found = true
                break
            end
        end
        if not found then
            t.count = t.count or 0
            tinsert(raid.players, t)
            raid.playersByName[t.name] = t
            addon:trace(Diag.D.LogRaidPlayerJoin:format(tostring(t.name), tonumber(raidNum) or -1))
        else
            addon:trace(Diag.D.LogRaidPlayerRefresh:format(tostring(t.name), tonumber(raidNum) or -1))
        end
    end

    -- Adds a boss kill to the active raid log.
    function module:AddBoss(bossName, manDiff, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        if not raidNum or not bossName then
            addon:debug(Diag.D.LogBossAddSkipped:format(tostring(raidNum), tostring(bossName)))
            return
        end

        local raid = KRT_Raids[raidNum]
        if not raid then return end
        module:EnsureStableIds(raidNum)

        local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if manDiff then
            instanceDiff = (raid.size == 10) and 1 or 2
            if Utils.normalizeLower(manDiff, true) == "h" then instanceDiff = instanceDiff + 2 end
        elseif isDyn then
            instanceDiff = instanceDiff + (2 * dynDiff)
        end

        local players = {}
        for unit, owner in addon.UnitIterator(true) do
            if UnitIsConnected(unit) then
                local name = UnitName(unit)
                if name then
                    tinsert(players, name)
                end
            end
        end

        local currentTime = Utils.getCurrentTime()
        local bossNid = tonumber(raid.nextBossNid) or 1
        raid.nextBossNid = bossNid + 1

        local killInfo = {
            bossNid    = bossNid,
            name       = bossName,
            difficulty = instanceDiff,
            mode       = (instanceDiff == 3 or instanceDiff == 4) and "h" or "n",
            players    = players,
            time       = currentTime,
            hash       = Utils.encode(raidNum .. "|" .. bossName .. "|" .. bossNid),
        }

        tinsert(raid.bossKills, killInfo)
        KRT_LastBoss = bossNid
        addon:info(Diag.I.LogBossLogged:format(tostring(bossName), tonumber(instanceDiff) or -1,
            tonumber(raidNum) or -1, #players))
        addon:debug(Diag.D.LogBossLastBossHash:format(tonumber(KRT_LastBoss) or -1, tostring(killInfo.hash)))
    end

    -- Adds a loot item to the active raid log.
    function module:AddLoot(msg, rollType, rollValue)
        -- Master Loot / Loot chat parsing
        -- Supports both "...receives loot:" and "...receives item:" variants.
        local player, itemLink, count = addon.Deformat(msg, LOOT_ITEM_MULTIPLE)
        local itemCount = count or 1

        if not player then
            player, itemLink = addon.Deformat(msg, LOOT_ITEM)
            itemCount = 1
        end

        -- Self loot (no player name in the string)
        if not itemLink then
            local link
            link, count = addon.Deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
            if link then
                itemLink = link
                itemCount = count or 1
                player = Utils.getPlayerName()
            end
        end

        if not itemLink then
            local link = addon.Deformat(msg, LOOT_ITEM_SELF)
            if link then
                itemLink = link
                itemCount = 1
                player = Utils.getPlayerName()
            end
        end

        -- Other Loot Rolls
        if not player or not itemLink then
            itemLink = addon.Deformat(msg, LOOT_ROLL_YOU_WON)
            player = Utils.getPlayerName()
            itemCount = 1
        end
        if not itemLink then
            addon:debug(Diag.D.LogLootParseFailed:format(tostring(msg)))
            return
        end

        itemCount = tonumber(itemCount) or 1
        lootState.itemCount = itemCount

        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        itemId = tonumber(itemId)
        addon:trace(Diag.D.LogLootParsed:format(tostring(player), tostring(itemLink), itemCount))

        -- We don't proceed if lower than threshold or ignored.
        local lootThreshold = GetLootThreshold()
        if itemRarity and itemRarity < lootThreshold then
            addon:debug(Diag.D.LogLootIgnoredBelowThreshold:format(tostring(itemRarity),
                tonumber(lootThreshold) or -1, tostring(itemLink)))
            return
        end
        if itemId and addon.ignoredItems[itemId] then
            addon:debug(Diag.D.LogLootIgnoredItemId:format(tostring(itemId), tostring(itemLink)))
            return
        end

        if not KRT_LastBoss then
            addon:debug(Diag.D.LogBossNoContextTrash)
            self:AddBoss("_TrashMob_")
        end
        -- Award source detection:
        -- 1) If we have a pending award staged by this addon (AssignItem/TradeItem), consume it.
        -- 2) Otherwise, if THIS client is the master looter (Master Loot method), treat it as MANUAL
        --    (loot-window dropdown assignment or direct click-to-self).
        -- 3) Otherwise, fall back to the current roll type.
        if not rollType then
            local p = addon.Loot:ConsumePendingAward(itemLink, player, 5)
            if p then
                rollType = p.rollType
                rollValue = p.rollValue
            elseif self:IsMasterLooter() and not lootState.fromInventory then
                rollType  = rollTypes.MANUAL
                rollValue = 0

                -- Debug-only marker: helps verify why this loot was tagged as MANUAL.
                -- Only runs for Master Looter clients (by condition above).
                addon:debug(Diag.D.LogLootTaggedManual,
                    tostring(itemLink), tostring(player), tostring(lootState.currentRollType))
            else
                rollType = lootState.currentRollType
            end
        end

        if not rollValue then
            rollValue = addon.Rolls:HighestRoll() or 0
        end

        local raid = KRT_Raids[KRT_CurrentRaid]
        if not raid then return end
        module:EnsureStableIds(KRT_CurrentRaid)
        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local lootInfo = {
            itemId      = itemId,
            itemName    = itemName,
            itemString  = itemString,
            itemLink    = itemLink,
            itemRarity  = itemRarity,
            itemTexture = itemTexture,
            itemCount   = itemCount,
            looter      = player,
            rollType    = rollType,
            rollValue   = rollValue,
            lootNid     = lootNid,
            bossNid     = tonumber(KRT_LastBoss) or 0,
            time        = Utils.getCurrentTime(),
        }

        -- LootCounter (MS only): increment the winner's count when the loot is actually awarded.
        -- This runs off the authoritative LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event.
        if tonumber(rollType) == rollTypes.MAINSPEC then
            module:AddPlayerCount(player, itemCount, KRT_CurrentRaid)
        end

        tinsert(raid.loot, lootInfo)
        Utils.triggerEvent("RaidLootUpdate", KRT_CurrentRaid, lootInfo)
        addon:debug(Diag.D.LogLootLogged:format(tonumber(KRT_CurrentRaid) or -1, tostring(itemId),
            tostring(lootInfo.bossNid), tostring(player)))
    end

    -- ----- Player Count API ----- --

    -- Adds (or subtracts) from the per-raid player count.
    -- Used by LootCounter UI and MS auto-counting.
    -- Clamps to 0 (never negative).
    function module:AddPlayerCount(name, delta, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        if not raidNum or not name then return end

        delta = tonumber(delta) or 0
        if delta == 0 then return end

        -- Normalize/resolve name if possible.
        local ok, fixed = module:CheckPlayer(name, raidNum)
        if ok and fixed then
            name = fixed
        end

        -- Ensure the player exists in the raid log.
        if module:GetPlayerID(name, raidNum) == 0 then
            module:AddPlayer({
                name     = name,
                rank     = 0,
                subgroup = 1,
                class    = "UNKNOWN",
                join     = Utils.getCurrentTime(),
                leave    = nil,
                count    = 0,
            }, raidNum)
        end

        local current = module:GetPlayerCount(name, raidNum) or 0
        local nextVal = current + delta
        if nextVal < 0 then nextVal = 0 end
        module:SetPlayerCount(name, nextVal, raidNum)
    end

    function module:GetPlayerCount(name, raidNum)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        local players = raid and raid.players
        if not players then return 0 end
        for i, p in ipairs(players) do
            if p.name == name then
                local c = tonumber(p.count) or 0
                return c
            end
        end
        return 0
    end

    function module:SetPlayerCount(name, value, raidNum)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)

        value = tonumber(value) or 0
        -- Hard clamp: counts are always non-negative.
        if value < 0 then value = 0 end

        local players = raid and raid.players
        if not players then return end
        for i, p in ipairs(players) do
            if p.name == name then
                local old = tonumber(p.count) or 0
                if old ~= value then
                    p.count = value
                    Utils.triggerEvent("PlayerCountChanged", name, value, old, raidNum)
                else
                    p.count = value
                end
                return
            end
        end
    end

    function module:IncrementPlayerCount(name, raidNum)
        if module:GetPlayerID(name, raidNum) == 0 then
            addon:error(L.ErrCannotFindPlayer:format(name))
            return
        end

        local c = module:GetPlayerCount(name, raidNum)
        module:SetPlayerCount(name, c + 1, raidNum)
    end

    function module:DecrementPlayerCount(name, raidNum)
        if module:GetPlayerID(name, raidNum) == 0 then
            addon:error(L.ErrCannotFindPlayer:format(name))
            return
        end

        local c = module:GetPlayerCount(name, raidNum)
        if c <= 0 then
            -- Already at floor; keep it at 0 without spamming errors.
            module:SetPlayerCount(name, 0, raidNum)
            return
        end
        module:SetPlayerCount(name, c - 1, raidNum)
    end

    -- ----- Raid Functions ----- --

    -- Returns the number of members in the raid.
    function module:GetNumRaid()
        return numRaid
    end

    -- Returns raid size: 10 or 25.
    function module:GetRaidSize()
        local _, _, members = addon.GetGroupTypeAndCount()
        if members == 0 then return 0 end

        local diff = addon.Utils.getDifficulty()
        if diff then
            return (diff == 1 or diff == 3) and 10 or 25
        end

        return members > 20 and 25 or 10
    end

    -- Checks if a raid log is expired (older than the weekly reset).
    function module:Expired(rID)
        local raid, resolvedID = Utils.getRaid(rID)
        rID = resolvedID
        if not raid then
            return true
        end

        local startTime = raid.startTime
        local currentTime = Utils.getCurrentTime()
        local week = 604800 -- 7 days in seconds

        if KRT_NextReset and KRT_NextReset > currentTime then
            return startTime < (KRT_NextReset - week)
        end

        return currentTime >= startTime + week
    end

    -- Retrieves all loot for a given raid and optional boss number.
    function module:GetLoot(raidNum, bossNid)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        bossNid = tonumber(bossNid) or 0
        if not raid then
            return {}
        end
        module:EnsureStableIds(raidNum)

        local loot = raid.loot or {}
        if bossNid <= 0 then
            for _, v in ipairs(loot) do
                v.id = tonumber(v.lootNid) or v.id
            end
            return loot
        end

        local items = {}
        for _, v in ipairs(loot) do
            if tonumber(v.bossNid) == bossNid then
                v.id = tonumber(v.lootNid) or v.id
                tinsert(items, v)
            end
        end
        return items
    end

    -- Retrieves the position of a specific loot item within the raid's loot table.
    function module:GetLootID(itemID, raidNum, holderName)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        if not raid then return 0 end

        module:EnsureStableIds(raidNum)

        itemID = tonumber(itemID)
        if not itemID then return 0 end

        local bossNid = tonumber(KRT_LastBoss) or 0
        local loot = raid.loot or {}

        for i = #loot, 1, -1 do
            local v = loot[i]
            if v and tonumber(v.itemId) == itemID then
                if (not holderName or holderName == "" or v.looter == holderName) then
                    if bossNid <= 0 or tonumber(v.bossNid) == bossNid then
                        return tonumber(v.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    -- Retrieves all boss kills for a given raid.
    function module:GetBosses(raidNum, out)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        if not raid or not raid.bossKills then return {} end

        module:EnsureStableIds(raidNum)

        local bosses = out or {}
        if out then twipe(bosses) end

        for i = 1, #raid.bossKills do
            local boss = raid.bossKills[i]
            bosses[#bosses + 1] = {
                id   = tonumber(boss.bossNid) or i, -- stable selection id
                seq  = i,                           -- display order
                name = boss.name,
                time = boss.time,
                mode = boss.mode or ((boss.difficulty == 3 or boss.difficulty == 4) and "h" or "n"),
            }
        end

        return bosses
    end

    -- ----- Player Functions ----- --

    -- Returns players from the raid log. Can be filtered by boss kill.
    function module:GetPlayers(raidNum, bossNid, out)
        local raid

        raid, raidNum = Utils.getRaid(raidNum)
        if not raid then return {} end

        module:EnsureStableIds(raidNum)

        local raidPlayers = raid.players or {}
        for k, v in ipairs(raidPlayers) do
            v.id = k
        end

        bossNid = tonumber(bossNid) or 0
        if bossNid > 0 then
            local bossKill = module:GetBossByNid(bossNid, raidNum)
            if bossKill and bossKill.players then
                local players = out or {}
                if out then twipe(players) end
                local bossPlayers = bossKill.players
                for _, p in ipairs(raidPlayers) do
                    if tContains(bossPlayers, p.name) then
                        tinsert(players, p)
                    end
                end
                -- Caller releases when using a pooled table.
                return players
            end
        end

        return raidPlayers
    end

    -- Checks if a player is in the raid log.
    function module:CheckPlayer(name, raidNum)
        local found = false
        local players = module:GetPlayers(raidNum)
        local originalName = name
        if players ~= nil then
            name = Utils.normalizeName(name)
            for i, p in ipairs(players) do
                if name == p.name then
                    found = true
                    break
                elseif strlen(name) >= 5 and p.name:startsWith(name) then
                    name = p.name
                    found = true
                    break
                end
            end
        end
        return found, name
    end

    -- Returns the player's internal ID from the raid log.
    function module:GetPlayerID(name, raidNum)
        local id = 0
        raidNum = raidNum or KRT_CurrentRaid
        if raidNum and KRT_Raids[raidNum] then
            name = name or Utils.getPlayerName()
            local players = KRT_Raids[raidNum].players
            for i, p in ipairs(players) do
                if p.name == name then
                    id = i
                    break
                end
            end
        end
        return id
    end

    -- Gets a player's name by their internal ID.
    function module:GetPlayerName(id, raidNum)
        local name
        raidNum = raidNum or addon.Logger.selectedRaid or KRT_CurrentRaid
        if raidNum and KRT_Raids[raidNum] then
            for k, p in ipairs(KRT_Raids[raidNum].players) do
                if k == id then
                    name = p.name
                    break
                end
            end
        end
        return name
    end

    -- Returns a table of items looted by the selected player.
    function module:GetPlayerLoot(name, raidNum, bossNid)
        local items = {}
        local loot = module:GetLoot(raidNum, bossNid)
        local originalName = name
        name = (type(name) == "number") and module:GetPlayerName(name) or name
        for _, v in ipairs(loot) do
            if v.looter == name then
                -- Keep v.id stable (lootNid) as assigned by GetLoot()
                tinsert(items, v)
            end
        end
        return items
    end

    -- Gets a player's rank.
    function module:GetPlayerRank(name, raidNum)
        local raid = raidNum and KRT_Raids[raidNum]
        local players = raid and raid.players or {}
        local rank = 0
        local originalName = name
        name = name or Utils.getPlayerName() or UnitName("player")
        if #players == 0 then
            if addon.IsInGroup() then
                for unit in addon.UnitIterator(true) do
                    local pname = UnitName(unit)
                    if pname == name then
                        rank = Utils.getUnitRank(unit)
                        break
                    end
                end
            end
        else
            for i, p in ipairs(players) do
                if p.name == name then
                    rank = p.rank or 0
                    break
                end
            end
        end
        return rank
    end

    -- Gets a player's class from the saved players database.
    function module:GetPlayerClass(name)
        local class = "UNKNOWN"
        local realm = Utils.getRealmName()
        local resolvedName = name or Utils.getPlayerName()
        if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
            class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
        end
        return class
    end

    -- Gets a player's unit ID (e.g., "raid1").
    function module:GetUnitID(name)
        local id = "none"
        if not addon.IsInGroup() or not name then
            return id
        end
        for unit in addon.UnitIterator(true) do
            if UnitName(unit) == name then
                id = unit
                break
            end
        end
        return id
    end

    -- ----- Raid & Loot Status Checks ----- --

    -- Checks if the group is using the Master Looter system.
    function module:IsMasterLoot()
        local method = select(1, GetLootMethod())
        return (method == "master")
    end

    -- Checks if the player is the Master Looter.
    function module:IsMasterLooter()
        local method, partyMaster, raidMaster = GetLootMethod()
        if method ~= "master" then
            return false
        end
        if partyMaster then
            if partyMaster == 0 or UnitIsUnit("party" .. tostring(partyMaster), "player") then
                return true
            end
        end
        if raidMaster then
            if raidMaster == 0 or UnitIsUnit("raid" .. tostring(raidMaster), "player") then
                return true
            end
        end
        return false
    end

    -- Clears all raid target icons.
    function module:ClearRaidIcons()
        local players = module:GetPlayers()
        for i, p in ipairs(players) do
            SetRaidTarget("raid" .. tostring(i), 0)
        end
    end
end

-- =========== Chat Output Helpers  =========== --
do
    addon.Chat            = addon.Chat or {}
    local module          = addon.Chat
    -- ----- Internal state (non-exposed local variables) ----- --
    local output          = C.CHAT_OUTPUT_FORMAT
    local chatPrefix      = C.CHAT_PREFIX
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local prefixHex       = C.CHAT_PREFIX_HEX

    -- ----- Public module functions ----- --
    function module:Print(text, prefix)
        local msg = Utils.formatChatMessage(text, prefix or chatPrefixShort, output, prefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local ch = channel

        if not ch then
            local isCountdown = false
            do
                local seconds = addon.Deformat(text, L.ChatCountdownTic)
                isCountdown = (seconds ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)
            end

            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" then
                if isCountdown and addon.options.countdownSimpleRaidMsg then
                    ch = "RAID"
                elseif addon.options.useRaidWarning
                    and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
                    ch = "RAID_WARNING"
                else
                    ch = "RAID"
                end
            elseif groupType == "party" then
                ch = "PARTY"
            else
                ch = "SAY"
            end
        end
        Utils.chat(tostring(text), ch)
    end

    -- ----- Legacy helpers ----- --
    function addon:Announce(text, channel)
        module:Announce(text, channel)
    end
end

-- =========== Minimap Button Module  =========== --
do
    addon.Minimap = addon.Minimap or {}
    local module = addon.Minimap
    -- ----- Internal state (non-exposed local variables) ----- --
    local addonMenu
    local dragMode

    -- Cached math functions
    local abs, sqrt = math.abs, math.sqrt
    local cos, sin = math.cos, math.sin
    local rad, atan2, deg = math.rad, math.atan2, math.deg

    -- ----- Private helpers ----- --
    -- Menu definition for EasyMenu (built once).
    local minimapMenu = {
        { text = MASTER_LOOTER,    notCheckable = 1, func = function() addon.Master:Toggle() end },
        { text = L.StrLootCounter, notCheckable = 1, func = function() addon.LootCounter:Toggle() end },
        { text = L.StrLootLogger,  notCheckable = 1, func = function() addon.Logger:Toggle() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrClearIcons,  notCheckable = 1, func = function() addon.Raid:ClearRaidIcons() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = RAID_WARNING,     notCheckable = 1, func = function() addon.Warnings:Toggle() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrMSChanges,   notCheckable = 1, func = function() addon.Changes:Toggle() end },
        { text = L.BtnDemand,      notCheckable = 1, func = function() addon.Changes:Demand() end },
        { text = CHAT_ANNOUNCE,    notCheckable = 1, func = function() addon.Changes:Announce() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrLFMSpam,     notCheckable = 1, func = function() addon.Spammer:Toggle() end },
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

    -- ----- Public methods ----- --
    local function SetMinimapShown(show)
        Utils.setShown(KRT_MINIMAP_GUI, show)
    end

    function module:SetPos(angle)
        addon.options = addon.options or KRT_Options or {}
        angle = angle % 360
        addon.options.minimapPos = angle
        local r = rad(angle)
        KRT_MINIMAP_GUI:ClearAllPoints()
        KRT_MINIMAP_GUI:SetPoint("CENTER", cos(r) * 80, sin(r) * 80)
    end

    function module:OnLoad()
        addon.options = addon.options or KRT_Options or {}
        KRT_MINIMAP_GUI:SetUserPlaced(true)
        self:SetPos(addon.options.minimapPos or 325)
        SetMinimapShown(addon.options.minimapButton ~= false)
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
                addon.Config:Toggle()
            elseif button == "LeftButton" then
                ToggleMenu()
            end
        end)
        KRT_MINIMAP_GUI:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetText(
                addon.WrapTextInColorCode("Kader", Utils.normalizeHexColor(K_COLOR))
                .. " "
                .. addon.WrapTextInColorCode("Raid Tools", Utils.normalizeHexColor("aad4af37"))
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
        addon.options = addon.options or KRT_Options or {}
        addon.options.minimapButton = not addon.options.minimapButton
        SetMinimapShown(addon.options.minimapButton)
    end

    -- Hides the minimap button.
    function module:HideMinimapButton()
        return Utils.setShown(KRT_MINIMAP_GUI, false)
    end
end

-- =========== Rolls Helpers Module  =========== --
-- Manages roll tracking, sorting, and winner determination.
do
    addon.Rolls = addon.Rolls or {}
    local module = addon.Rolls
    -- Multi-selection context for manual multi-award winner picking (Master Loot window)
    local MS_CTX_ROLLS = "MLRollWinners"

    -- ---Internal state ----- --
    local state = {
        record       = false,
        canRoll      = true,
        warned       = false,
        rolled       = false,
        selected     = nil,
        selectedAuto = false,
        lastSortAsc  = nil,
        lastSortType = nil,
        rolls        = {},
        rerolled     = {},
        playerCounts = {},
        itemCounts   = nil,
        count        = 0,
        display      = nil,   -- compact list entries in current sort order
        displayNames = nil,   -- array of names in display order
        msPrefilled  = false, -- true after first Top-N prefill in multi-pick mode
    }
    local newItemCounts, delItemCounts
    if addon.TablePool then
        newItemCounts, delItemCounts = addon.TablePool("k")
    end
    state.itemCounts = newItemCounts and newItemCounts() or {}

    -- ----- Private helpers ----- --
    local function GetAllowedRolls(itemId, name)
        if not itemId or not name then return 1 end
        if lootState.currentRollType ~= rollTypes.RESERVED then
            return 1
        end
        local reserves = addon.Reserves:GetReserveCountForItem(itemId, name)
        return (reserves and reserves > 0) and reserves or 1
    end

    local function UpdateLocalRollState(itemId, name)
        if not itemId or not name then
            state.rolled = false
            return false
        end
        local allowed = GetAllowedRolls(itemId, name)
        local used = state.playerCounts[itemId] or 0
        state.rolled = used >= allowed
        return state.rolled
    end

    local function AcquireItemTracker(itemId)
        local tracker = state.itemCounts
        if not tracker[itemId] then
            tracker[itemId] = newItemCounts and newItemCounts() or {}
            -- Tracker tables are released via resetRolls() using delItemCounts(..., true)
        end
        return tracker[itemId]
    end

    local function PickBestReserved(itemId)
        if not itemId then return nil end
        local bestName, bestRoll, bestPlus = nil, nil, nil
        local wantLow = addon.options.sortAscending == true

        -- SR "Plus priority" is enabled only when the item has no multi-reserve entries.
        local usePlus = addon.Reserves
            and addon.Reserves.GetPlusForItem
            and addon.Reserves.GetImportMode
            and (addon.Reserves:IsPlusSystem())

        for _, entry in ipairs(state.rolls) do
            if module:IsReserved(itemId, entry.name) then
                local roll = entry.roll
                local plus = usePlus and (addon.Reserves:GetPlusForItem(itemId, entry.name) or 0) or 0

                if not bestName then
                    bestName, bestRoll, bestPlus = entry.name, roll, plus
                else
                    if usePlus and plus ~= bestPlus then
                        if plus > bestPlus then
                            bestName, bestRoll, bestPlus = entry.name, roll, plus
                        end
                    else
                        if wantLow then
                            if roll < bestRoll then
                                bestName, bestRoll, bestPlus = entry.name, roll, plus
                            end
                        else
                            if roll > bestRoll then
                                bestName, bestRoll, bestPlus = entry.name, roll, plus
                            end
                        end
                    end
                end
            end
        end

        return bestName, bestRoll
    end

    -- Factory to create a GetPlus function with its own cache for a specific itemId.
    local function MakePlusGetter(itemId)
        local plusCache = {}
        return function(name)
            local v = plusCache[name]
            if v == nil then
                v = (addon.Reserves and addon.Reserves.GetPlusForItem)
                    and (addon.Reserves:GetPlusForItem(itemId, name) or 0)
                    or 0
                plusCache[name] = v
            end
            return v
        end
    end

    -- Sorts rolls table + updates lootState.winner (top entry after sort).
    local function sortRolls(itemId)
        local rolls = state.rolls
        if #rolls == 0 then
            lootState.winner = nil
            lootState.rollWinner = nil
            addon:debug(Diag.D.LogRollsSortNoEntries)
            return
        end

        local isSR         = (lootState.currentRollType == rollTypes.RESERVED)
        local wantLow      = (addon.options.sortAscending == true)

        local plusPriority = isSR and itemId
            and addon.Reserves
            and addon.Reserves.GetPlusForItem
            and addon.Reserves.GetImportMode
            and (addon.Reserves:IsPlusSystem())

        local GetPlus      = MakePlusGetter(itemId)

        table.sort(rolls, function(a, b)
            -- SR: reserved first (session itemId)
            if isSR and itemId then
                local ar = module:IsReserved(itemId, a.name)
                local br = module:IsReserved(itemId, b.name)
                if ar ~= br then
                    return ar -- true first
                end

                -- SR + Plus priority (only when no multi-reserve exists for this item)
                if plusPriority and ar and br then
                    local ap = GetPlus(a.name)
                    local bp = GetPlus(b.name)
                    if ap ~= bp then
                        return ap > bp
                    end
                end
            end

            if a.roll ~= b.roll then
                return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
            end

            -- stable tie-breaker
            return tostring(a.name) < tostring(b.name)
        end)

        -- * top roll (always follows ascending/descending sort order)
        lootState.rollWinner = rolls[1].name

        -- Award target follows the top roll only when not manually selected
        if state.canRoll or state.selectedAuto or (lootState.winner == nil) then
            lootState.winner = lootState.rollWinner
            state.selectedAuto = true
        end

        state.lastSortAsc  = wantLow
        state.lastSortType = lootState.currentRollType
    end

    local function onRollButtonClick(self, button)
        -- Selection allowed only after the countdown has finished
        if state.canRoll then
            return
        end

        -- Lock selection while a multi-award sequence is running
        if lootState.multiAward and lootState.multiAward.active then
            addon:warn(Diag.W.ErrMLMultiAwardInProgress)
            return
        end

        local name = self.playerName
        if not name or name == "" then return end

        local itemCount = tonumber(lootState.itemCount) or 1
        if itemCount < 1 then itemCount = 1 end

        local ctrl = IsControlKeyDown()
        local pickMode = (not lootState.fromInventory) -- loot window (single and multi): CTRL-only winner picking

        -- Loot window: CTRL+Click toggles winners; regular click is "focus" (no side-effects).
        if pickMode then
            if not ctrl then
                state.selected = name
                state.selectedAuto = false
                module:FetchRolls()
                return
            end

            local maxSel = itemCount
            local display = state.display
            if display and maxSel > #display then
                maxSel = #display
            end
            if maxSel < 1 then maxSel = 1 end

            local isSel = Utils.multiSelectIsSelected(MS_CTX_ROLLS, name)
            local cur   = Utils.multiSelectCount(MS_CTX_ROLLS) or 0

            -- If capacity is 1, CTRL+Click on another player replaces the current selection (swap).
            if (not isSel) and cur >= maxSel then
                if maxSel == 1 then
                    Utils.multiSelectClear(MS_CTX_ROLLS)
                    Utils.multiSelectToggle(MS_CTX_ROLLS, name, true)
                else
                    addon:warn(Diag.W.ErrMLMultiSelectTooMany:format(maxSel))
                    return
                end
            else
                Utils.multiSelectToggle(MS_CTX_ROLLS, name, true)
            end

            -- Keep lootState.winner aligned with the current selection for single-award flows and UI state.
            local picked = module.GetSelectedWinnersOrdered and module:GetSelectedWinnersOrdered() or {}
            lootState.winner = (picked[1] and picked[1].name) or nil

            state.selected = name
            state.selectedAuto = false

            module:FetchRolls()
            -- NOTE: do not sync per-click in pick mode (avoids RAID/PARTY addon message spam)
            return
        end

        -- Inventory/trade: legacy single selection behavior.
        Utils.multiSelectClear(MS_CTX_ROLLS)

        lootState.winner = name
        state.selected = name
        state.selectedAuto = false

        module:FetchRolls()
        Utils.sync("KRT-RollWinner", name)
    end

    local function addRoll(name, roll, itemId)
        roll = tonumber(roll)
        state.count = state.count + 1
        lootState.rollsCount = lootState.rollsCount + 1

        local entry = {}
        entry.name = name
        entry.roll = roll
        entry.itemId = itemId
        state.rolls[state.count] = entry
        -- Roll entries are released via resetRolls().

        addon:debug(Diag.D.LogRollsAddEntry:format(name, roll, tostring(itemId)))
        if itemId then
            local tracker = AcquireItemTracker(itemId)
            tracker[name] = (tracker[name] or 0) + 1
        end

        Utils.triggerEvent("AddRoll", name, roll)
        sortRolls(itemId)
        module:FetchRolls()
    end

    local function resetRolls(rec)
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry then
                twipe(entry)
            end
        end
        twipe(state.rolls)
        twipe(state.rerolled)
        twipe(state.playerCounts)
        if delItemCounts then
            delItemCounts(state.itemCounts, true)
        end

        state.rolls = {}
        state.rerolled = {}
        state.playerCounts = {}
        state.itemCounts = newItemCounts and newItemCounts() or {}

        state.count, lootState.rollsCount = 0, 0
        state.selected, state.selectedAuto = nil, false
        state.rolled, state.warned = false, false
        state.lastSortAsc, state.lastSortType = nil, nil

        lootState.winner = nil
        lootState.rollWinner = nil
        lootState.itemTraded = 0
        lootState.rollStarted = false

        -- Clear any manual multi-winner selection (Master Loot window)
        state.msPrefilled = false
        Utils.multiSelectClear(MS_CTX_ROLLS)
        Utils.multiSelectSetAnchor(MS_CTX_ROLLS, nil)

        if rec == false then state.record = false end
    end

    -- ----- Public methods ----- --
    -- Initiates a /roll 1-100 for the player.
    function module:Roll(btn)
        local itemId = self:GetCurrentRollItemID()
        if not itemId then return end

        local name = Utils.getPlayerName()
        local allowed = GetAllowedRolls(itemId, name)

        state.playerCounts[itemId] = state.playerCounts[itemId] or 0
        if state.playerCounts[itemId] >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            addon:debug(Diag.D.LogRollsBlockedPlayer:format(name, state.playerCounts[itemId], allowed))
            return
        end

        RandomRoll(1, 100)
        state.playerCounts[itemId] = state.playerCounts[itemId] + 1
        UpdateLocalRollState(itemId, name)
        addon:debug(Diag.D.LogRollsPlayerRolled:format(name, itemId))
    end

    -- Returns the current roll session state.
    function module:RollStatus()
        local itemId = self:GetCurrentRollItemID()
        local name = Utils.getPlayerName()
        UpdateLocalRollState(itemId, name)
        return lootState.currentRollType, state.record, state.canRoll, state.rolled
    end

    -- Enables or disables the recording of rolls.
    function module:RecordRolls(bool)
        local on      = (bool == true)
        state.canRoll = on
        state.record  = on

        if on then
            state.warned = false

            -- Reset only if we are starting a clean session
            if state.count == 0 then
                state.selected = nil
                state.selectedAuto = true
                lootState.winner = nil
                lootState.rollWinner = nil
            end
        end

        addon:debug(Diag.D.LogRollsRecordState:format(tostring(bool)))
    end

    -- Intercepts system messages to detect player rolls.
    function module:CHAT_MSG_SYSTEM(msg)
        if not msg or not state.record then return end
        local player, roll, min, max = addon.Deformat(msg, RANDOM_ROLL_RESULT)
        if not player or not roll or min ~= 1 or max ~= 100 then return end

        if not state.canRoll then
            if not state.warned then
                addon:Announce(L.ChatCountdownBlock)
                state.warned = true
            end
            addon:debug(Diag.D.LogRollsCountdownBlocked)
            return
        end

        local itemId = self:GetCurrentRollItemID()
        if not itemId or lootState.lootCount == 0 then
            addon:warn(Diag.W.LogRollsMissingItem)
            return
        end

        local allowed = 1
        if lootState.currentRollType == rollTypes.RESERVED then
            local reserves = addon.Reserves:GetReserveCountForItem(itemId, player)
            allowed = reserves > 0 and reserves or 1
        end

        local tracker = AcquireItemTracker(itemId)
        local used = tracker[player] or 0
        if used >= allowed then
            if not tContains(state.rerolled, player) then
                Utils.whisper(player, L.ChatOnlyRollOnce)
                tinsert(state.rerolled, player)
            end
            addon:debug(Diag.D.LogRollsDeniedPlayer:format(player, used, allowed))
            return
        end

        addon:debug(Diag.D.LogRollsAcceptedPlayer:format(player, used + 1, allowed))
        addRoll(player, roll, itemId)
    end

    -- Returns the current table of rolls.
    function module:GetRolls()
        return state.rolls
    end

    -- Sets the flag indicating the player has rolled.
    function module:SetRolled()
        local itemId = self:GetCurrentRollItemID()
        local name = Utils.getPlayerName()
        UpdateLocalRollState(itemId, name)
    end

    -- Checks if a player has already used all their rolls for an item.
    function module:DidRoll(itemId, name)
        if not itemId then
            for i = 1, state.count do
                if state.rolls[i].name == name then return true end
            end
            return false
        end
        local tracker = AcquireItemTracker(itemId)
        local used = tracker[name] or 0
        local reserve = addon.Reserves:GetReserveCountForItem(itemId, name)
        local allowed = (lootState.currentRollType == rollTypes.RESERVED and reserve > 0) and reserve or 1
        return used >= allowed
    end

    -- Returns the highest roll value from the current winner.
    function module:HighestRoll()
        if not lootState.winner then return 0 end

        local winner = lootState.winner
        local wantLow = (addon.options.sortAscending == true)
        local best = nil

        -- Prefer rolls tied to the current session item when available.
        local sessionItemId = self:GetCurrentRollItemID()

        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry and entry.name == winner then
                if (not sessionItemId) or (not entry.itemId) or (entry.itemId == sessionItemId) then
                    if best == nil then
                        best = entry.roll
                    elseif wantLow then
                        if entry.roll < best then best = entry.roll end
                    else
                        if entry.roll > best then best = entry.roll end
                    end
                end
            end
        end

        return best or 0
    end

    -- Clears all roll-related state and UI elements.
    function module:ClearRolls(rec)
        local mf = (addon.Master and addon.Master.frame) or _G["KRTMaster"]
        local frameName = mf and mf:GetName() or nil
        resetRolls(rec)
        if frameName then
            local i, btn = 1, _G[frameName .. "PlayerBtn1"]
            while btn do
                btn:Hide()
                i = i + 1
                btn = _G[frameName .. "PlayerBtn" .. i]
            end
            addon.Raid:ClearRaidIcons()
        end
    end

    -- Gets the item ID of the item currently being rolled for.
    function module:GetCurrentRollItemID()
        local index = GetItemIndex()
        local item = GetItem and GetItem(index)
        local itemLink = item and item.itemLink
        if not itemLink then return nil end
        local itemId = Utils.getItemIdFromLink(itemLink)
        addon:debug(Diag.D.LogRollsCurrentItemId:format(tostring(itemId)))
        return itemId
    end

    -- Validates if a player can still roll for an item.
    function module:IsValidRoll(itemId, name)
        local tracker = AcquireItemTracker(itemId)
        local used = tracker[name] or 0
        local allowed = (lootState.currentRollType == rollTypes.RESERVED)
            and addon.Reserves:GetReserveCountForItem(itemId, name)
            or 1
        return used < allowed
    end

    -- Checks if a player has reserved the specified item.
    function module:IsReserved(itemId, name)
        return addon.Reserves:GetReserveCountForItem(itemId, name) > 0
    end

    -- Gets the number of reserves a player has used for an item.
    function module:GetUsedReserveCount(itemId, name)
        local tracker = AcquireItemTracker(itemId)
        return tracker[name] or 0
    end

    -- Gets the total number of reserves a player has for an item.
    function module:GetAllowedReserves(itemId, name)
        return addon.Reserves:GetReserveCountForItem(itemId, name)
    end

    -- Rebuilds the roll list UI and marks the top roller or selected winner.
    function module:FetchRolls()
        local mf = (addon.Master and addon.Master.frame) or _G["KRTMaster"]
        local frameName = mf and mf:GetName() or nil
        if not frameName then return end
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())

        local itemId = self:GetCurrentRollItemID()
        local isSR = lootState.currentRollType == rollTypes.RESERVED

        local plusPriority = isSR and itemId
            and addon.Reserves
            and addon.Reserves.GetPlusForItem
            and addon.Reserves.GetImportMode
            and (addon.Reserves:IsPlusSystem())

        local GetPlus = MakePlusGetter(itemId)

        local wantAsc = addon.options.sortAscending == true
        if state.lastSortAsc ~= wantAsc or state.lastSortType ~= lootState.currentRollType then
            sortRolls(itemId)
        end

        -- Build a compact display list: one row per player.
        -- If the player rolled multiple times (multi-reserve), keep only the best roll according to sort order.
        local wantLow = wantAsc
        local bestByName = {}
        local display = {}
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry then
                local name, roll = entry.name, entry.roll
                local best = bestByName[name]
                if not best then
                    best = { name = name, roll = roll }
                    bestByName[name] = best
                    display[#display + 1] = best
                else
                    if wantLow then
                        if roll < best.roll then best.roll = roll end
                    else
                        if roll > best.roll then best.roll = roll end
                    end
                end
            end
        end

        table.sort(display, function(a, b)
            -- SR: reserved first (session itemId)
            if isSR and itemId then
                local ar = module:IsReserved(itemId, a.name)
                local br = module:IsReserved(itemId, b.name)
                if ar ~= br then
                    return ar
                end

                -- SR + Plus priority (only when no multi-reserve exists for this item)
                if plusPriority and ar and br then
                    local ap = GetPlus(a.name)
                    local bp = GetPlus(b.name)
                    if ap ~= bp then
                        return ap > bp
                    end
                end
            end

            if a.roll ~= b.roll then
                return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
            end

            return tostring(a.name) < tostring(b.name)
        end)

        -- Cache current display order (used for manual multi-winner selection / shift-range).
        state.display = display
        state.displayNames = {}
        for i = 1, #display do
            local e = display[i]
            state.displayNames[i] = e and e.name or nil
        end

        -- Inventory/trade: keep legacy single-selection behavior.
        -- In loot window (pick mode) we support the same MultiSelect flow for both single and multi-copy items.
        if lootState.fromInventory then
            Utils.multiSelectClear(MS_CTX_ROLLS)
            Utils.multiSelectSetAnchor(MS_CTX_ROLLS, nil)
            state.msPrefilled = false
        end

        -- Top roll for UI star (compact list).
        local starTarget = display[1] and display[1].name or lootState.rollWinner

        -- Fallback (if for some reason it has not been set yet)
        if not starTarget then
            if isSR then
                local bestName = PickBestReserved(itemId)
                starTarget = bestName or lootState.winner
            else
                starTarget = lootState.winner
            end
        end

        local ma = lootState.multiAward
        local selectionAllowed = (state.canRoll == false) and not (ma and ma.active)
        local pickName = selectionAllowed and lootState.winner or nil

        -- highlight: durante CD = top roll; post-CD = pick (se esiste) altrimenti top roll
        local highlightTarget = selectionAllowed and (pickName or starTarget) or starTarget
        local available = tonumber(addon.Loot:GetCurrentItemCount()) or 1
        if available < 1 then available = 1 end
        local pickMode = selectionAllowed and (not lootState.fromInventory)

        -- Prefill MultiSelect with top-N winners (Top-N = ItemCount) in pick mode.
        -- This keeps the UI identical for single- and multi-copy loot: the addon always starts with an auto-selection.
        if pickMode then
            local n = tonumber(lootState.itemCount) or 1
            if n and n >= 1 and #display > 0 then
                if n > #display then n = #display end
                if (not state.msPrefilled) and (Utils.multiSelectCount(MS_CTX_ROLLS) or 0) == 0 then
                    for i = 1, n do
                        local e = display[i]
                        if e and e.name then
                            Utils.multiSelectToggle(MS_CTX_ROLLS, e.name, true)
                        end
                    end
                end
                state.msPrefilled = true
            end
        end

        local msCount = pickMode and (Utils.multiSelectCount(MS_CTX_ROLLS) or 0) or 0
        if msCount > 0 then
            -- In pick mode, persistent background highlight comes from MultiSelect.
            highlightTarget = nil
        end

        -- Star is a pure "top roll" indicator (UI hint), independent from manual MultiSelect winners.
        local starWinners = {}
        do
            local n = tonumber(lootState.itemCount) or 1
            if n < 1 then n = 1 end

            if display and #display > 0 then
                if n > #display then n = #display end
                for i = 1, n do
                    local e = display[i]
                    if e and e.name then
                        starWinners[e.name] = true
                    end
                end
            elseif starTarget then
                -- Fallback: keep at least the best known target.
                starWinners[starTarget] = true
            end
        end

        local starShown, totalHeight = false, 0
        for i = 1, #display do
            local entry = display[i]
            local name, roll = entry.name, entry.roll
            local btnName = frameName .. "PlayerBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")

            btn:SetID(i)
            btn:Show()
            btn.playerName = name

            -- enable click only after the countdown has finished
            btn:EnableMouse(selectionAllowed)

            Utils.ensureRowVisuals(btn)

            local nameStr, rollStr, counterStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"],
                _G[btnName .. "Counter"], _G[btnName .. "Star"]

            if nameStr and nameStr.SetVertexColor then
                local class = addon.Raid:GetPlayerClass(name)
                class = class and class:upper() or "UNKNOWN"
                if isSR and itemId and self:IsReserved(itemId, name) then
                    nameStr:SetVertexColor(0.4, 0.6, 1.0)
                else
                    local r, g, b = Utils.getClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
            end

            -- Pick mode: show current winners (MultiSelect) with > < (single and multi-copy loot).
            if pickMode and (msCount > 0) and Utils.multiSelectIsSelected(MS_CTX_ROLLS, name) then
                nameStr:SetText("> " .. name .. " <")
            else
                nameStr:SetText(name)
            end

            local isFocus = (highlightTarget and highlightTarget == name)
            local isSelected = (msCount > 0 and Utils.multiSelectIsSelected(MS_CTX_ROLLS, name))

            Utils.setRowSelected(btn, isSelected)
            Utils.setRowFocused(btn, isFocus)

            -- Roll value always in its own column
            if rollStr then
                rollStr:SetText(tostring(roll))
            end

            -- SR roll counter: show only (used/allowed) on the single compact row
            -- Optional: during MS rolls, show the player's positive MS loot count in the same column ("+N"), if enabled in config.
            if counterStr then
                if isSR and itemId and self:IsReserved(itemId, name) then
                    -- SR + Plus priority (only when no multi-reserve exists for this item)
                    if plusPriority then
                        local p = GetPlus(name)
                        if p and p > 0 then
                            counterStr:SetText(format("(P+%d)", p))
                        else
                            counterStr:SetText("")
                        end
                    else
                        local allowed = self:GetAllowedReserves(itemId, name)
                        if allowed and allowed > 1 then
                            local used = self:GetUsedReserveCount(itemId, name)
                            counterStr:SetText(format("(%d/%d)", used or 0, allowed))
                        else
                            counterStr:SetText("")
                        end
                    end
                else
                    if addon.options.showLootCounterDuringMSRoll == true
                        and lootState.currentRollType == rollTypes.MAINSPEC
                    then
                        local c = addon.Raid:GetPlayerCount(name, KRT_CurrentRaid) or 0
                        if c > 0 then
                            counterStr:SetText("+" .. c)
                        else
                            counterStr:SetText("")
                        end
                    else
                        counterStr:SetText("")
                    end
                end
            end

            local showStar
            if starWinners then
                showStar = (starWinners[name] == true)
            else
                -- Default: star marks only the top roll (compact list)
                showStar = (not starShown) and (starTarget ~= nil) and (name == starTarget)
            end
            Utils.showHide(star, showStar)
            if (not starWinners) and showStar then starShown = true end

            if not btn.krtHasOnClick then
                btn:SetScript("OnClick", onRollButtonClick)
                btn.krtHasOnClick = true
            end

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end

        -- Hide leftover buttons from previous renders.
        local j = #display + 1
        local btn = _G[frameName .. "PlayerBtn" .. j]
        while btn do
            btn:Hide()
            j = j + 1
            btn = _G[frameName .. "PlayerBtn" .. j]
        end

        if addon.Master and addon.Master.RequestRefresh then
            addon.Master:RequestRefresh()
        end
    end

    -- Returns selected winners (manual multi-pick) in current display order.
    -- Each entry is { name = <string>, roll = <number> }.
    function module:GetSelectedWinnersOrdered()
        local selected = {}
        local display = state.display
        if not display or #display == 0 then
            return selected
        end
        for i = 1, #display do
            local e = display[i]
            if e and e.name and Utils.multiSelectIsSelected(MS_CTX_ROLLS, e.name) then
                selected[#selected + 1] = { name = e.name, roll = tonumber(e.roll) or 0 }
            end
        end
        return selected
    end

    Utils.registerCallback("ConfigsortAscending", function(_, value)
        addon.Rolls:FetchRolls()
    end)
end

-- =========== Loot Helpers Module  =========== --
-- Manages the loot window items (fetching from loot/inventory).
do
    addon.Loot = addon.Loot or {}
    local module = addon.Loot
    local frameName

    local function GetMasterFrameName()
        if frameName then return frameName end
        local mf = (addon.Master and addon.Master.frame) or _G["KRTMaster"]
        if mf and addon.Master and not addon.Master.frame then addon.Master.frame = mf end
        if not mf then return nil end
        frameName = mf:GetName()
        return frameName
    end

    -- ----- Internal state ----- --
    local lootTable = {}

    -- ----- Private helpers ----- --
    local function BuildPendingAwardKey(itemLink, looter)
        return tostring(itemLink) .. "\001" .. tostring(looter)
    end

    -- ----- Pending award helpers (shared with Master/Raid flows) ----- --
    function module:QueuePendingAward(itemLink, looter, rollType, rollValue)
        if not itemLink or not looter then
            return
        end
        local key = BuildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if not list then
            list = {}
            lootState.pendingAwards[key] = list
        end
        list[#list + 1] = {
            itemLink  = itemLink,
            looter    = looter,
            rollType  = rollType,
            rollValue = rollValue,
            ts        = GetTime(),
        }
    end

    function module:ConsumePendingAward(itemLink, looter, maxAge)
        local key = BuildPendingAwardKey(itemLink, looter)
        local list = lootState.pendingAwards[key]
        if not list then
            return nil
        end
        local now = GetTime()
        for i = 1, #list do
            local p = list[i]
            if p and (now - (p.ts or 0)) <= maxAge then
                tremove(list, i)
                if #list == 0 then
                    lootState.pendingAwards[key] = nil
                end
                return p
            end
        end
        for i = #list, 1, -1 do
            local p = list[i]
            if not p or (now - (p.ts or 0)) > maxAge then
                tremove(list, i)
            end
        end
        if #list == 0 then
            lootState.pendingAwards[key] = nil
        end
        return nil
    end

    -- ----- Public methods ----- --

    -- Fetches items from the currently open loot window.
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = GetItemLink(lootState.currentItemIndex)
        end
        addon:trace(Diag.D.LogLootFetchStart:format(GetNumLootItems() or 0, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        local indexByItemKey = {}
        for i = 1, GetNumLootItems() do
            if LootSlotIsItem(i) then
                local itemLink = GetLootSlotLink(i)
                if itemLink then
                    local icon, name, quantity, quality = GetLootSlotInfo(i)
                    if GetItemFamily(itemLink) ~= 64 then
                        local key = Utils.getItemStringFromLink(itemLink) or itemLink
                        local existing = indexByItemKey[key]
                        if existing then
                            lootTable[existing].count = (lootTable[existing].count or 1) + 1
                        else
                            local before = lootState.lootCount
                            -- In loot window we treat each slot as one awardable copy (even if quantity > 1).
                            self:AddItem(itemLink, 1, name, quality, icon)
                            if lootState.lootCount > before then
                                indexByItemKey[key] = lootState.lootCount
                                local it = lootTable[lootState.lootCount]
                                if it then
                                    it.itemKey = key
                                end
                            end
                        end
                    end
                end
            end
        end

        lootState.currentItemIndex = 1
        if oldItem ~= nil then
            for t = 1, lootState.lootCount do
                if oldItem == GetItemLink(t) then
                    lootState.currentItemIndex = t
                    break
                end
            end
        end
        self:PrepareItem()
        if addon.Master and addon.Master.ResetItemCount then
            addon.Master:ResetItemCount()
        end
        addon:trace(Diag.D.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
    function module:AddItem(itemLink, itemCount, nameHint, rarityHint, textureHint, colorHint)
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

        -- Try to warm the item cache (doesn't guarantee immediate GetItemInfo).
        if (not itemName or not itemRarity or not itemTexture) and type(itemLink) == "string" then
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:SetHyperlink(itemLink)
            GameTooltip:Hide()
        end

        if not itemName then
            itemName = nameHint
            if not itemName and type(itemLink) == "string" then
                itemName = itemLink:match("%[(.-)%]")
            end
        end

        if not itemRarity then
            itemRarity = rarityHint
        end

        if not itemTexture then
            itemTexture = textureHint
        end

        -- Prefer: explicit hint > link color > rarity color table.
        local itemColor = colorHint
        if not itemColor and type(itemLink) == "string" then
            itemColor = itemLink:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
        end
        if not itemColor then
            local r = tonumber(itemRarity) or 1
            itemColor = itemColors[r + 1] or itemColors[2]
        end

        if not itemName then
            addon:debug(Diag.D.LogLootItemInfoMissing:format(tostring(itemLink)))
            itemName = tostring(itemLink)
        end

        itemTexture = itemTexture or C.RESERVES_ITEM_FALLBACK_ICON

        if lootState.fromInventory == false then
            local lootThreshold = GetLootThreshold() or 2
            local rarity = tonumber(itemRarity) or 1
            if rarity < lootThreshold then return end
            lootState.lootCount = lootState.lootCount + 1
        else
            lootState.lootCount = 1
            lootState.currentItemIndex = 1
        end
        lootTable[lootState.lootCount]             = {}
        lootTable[lootState.lootCount].itemName    = itemName
        lootTable[lootState.lootCount].itemColor   = itemColor
        lootTable[lootState.lootCount].itemLink    = itemLink
        lootTable[lootState.lootCount].itemTexture = itemTexture
        lootTable[lootState.lootCount].count       = itemCount or 1
    end

    -- Prepares the currently selected item for display.
    function module:PrepareItem()
        if ItemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    -- Sets the main item display in the UI.
    function module:SetItem(i)
        if i.itemName and i.itemLink and i.itemTexture and i.itemColor then
            frameName = GetMasterFrameName()
            if frameName == nil then return end

            local currentItemLink = _G[frameName .. "Name"]
            currentItemLink:SetText(addon.WrapTextInColorCode(
                i.itemName,
                Utils.normalizeHexColor(i.itemColor)
            ))

            local currentItemBtn = _G[frameName .. "ItemBtn"]
            currentItemBtn:SetNormalTexture(i.itemTexture)

            local options = addon.options or KRT_Options or {}
            if options.showTooltips then
                currentItemBtn.tooltip_item = i.itemLink
                addon:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
            end
            Utils.triggerEvent("SetItem", i.itemLink)
        end
    end

    -- Selects an item from the loot list by its index.
    function module:SelectItem(i)
        if ItemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
            if addon.Master and addon.Master.ResetItemCount then
                addon.Master:ResetItemCount()
            end
        end
    end

    -- Clears all loot from the table and resets the UI display.
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        frameName = GetMasterFrameName()
        if not frameName then return end
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        local itemBtn = _G[frameName .. "ItemBtn"]
        itemBtn.tooltip_item = nil
        GameTooltip:Hide()
        local mf = addon.Master and addon.Master.frame
        if mf and frameName == mf:GetName() then
            Utils.resetEditBox(_G[frameName .. "ItemCount"], true)
        end
    end

    -- Returns the table for the currently selected item.
    function GetItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    -- Returns the name of the currently selected item.
    function GetItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    -- Returns the link of the currently selected item.
    function GetItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    -- Returns the texture of the currently selected item.
    function GetItemTexture(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    function module:GetCurrentItemCount()
        if lootState.fromInventory then
            return itemInfo.count or lootState.itemCount or 1
        end
        local item = GetItem()
        local count = item and item.count
        if count and count > 0 then
            return count
        end
        return 1
    end

    -- Checks if a loot item exists at the given index.
    function ItemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    -- Checks if an item in the player's bags is soulbound.
    function ItemIsSoulbound(bag, slot)
        local tip = KRT_FakeTooltip or CreateFrame("GameTooltip", "KRT_FakeTooltip", nil, "GameTooltipTemplate")
        KRT_FakeTooltip = tip
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:SetBagItem(bag, slot)
        tip:Show()

        local num = tip:NumLines()
        for i = num, 1, -1 do
            local t = _G["KRT_FakeTooltipTextLeft" .. i]:GetText()
            if addon.Deformat(t, BIND_TRADE_TIME_REMAINING) ~= nil then
                return false
            elseif t == ITEM_SOULBOUND then
                return true
            end
        end

        tip:Hide()
        return false
    end
end

-- =========== Master Looter Frame Module  =========== --
do
    addon.Master = addon.Master or {}
    local module = addon.Master
    local frameName

    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame

    local getFrame = Utils.makeFrameGetter("KRTMaster")

    bindModuleRequestRefresh(module, getFrame)

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    local InitializeDropDowns, PrepareDropDowns, UpdateDropDowns
    local dropDownData, dropDownGroupData = {}, {}
    -- Ensure subgroup tables exist even when the Master UI hasn't been opened yet.
    for i = 1, 8 do dropDownData[i] = dropDownData[i] or {} end
    local dropDownFrameHolder, dropDownFrameBanker, dropDownFrameDisenchanter
    local dropDownsInitialized
    local dropDownDirty = true

    local selectionFrame, UpdateSelectionFrame

    local lastUIState = {
        buttons = {},
        texts = {},
        rollStatus = {},
    }
    local dirtyFlags = {
        itemCount = true,
        dropdowns = true,
        winner = true,
        rolls = true,
        buttons = true,
    }

    local countdownRun = false
    local countdownTicker
    local countdownEndTimer

    local AssignItem, TradeItem
    local screenshotWarn = false

    local announced = false
    local cachedRosterVersion
    local candidateCache = {
        itemLink = nil,
        indexByName = {},
    }

    -- ----- Private helpers ----- --
    local function SetItemCountValue(count, focus)
        local frame = getFrame()
        if not frame then return end
        frameName = frameName or frame:GetName()
        if not frameName or frameName ~= frame:GetName() then return end
        local itemCountBox = _G[frameName .. "ItemCount"]
        if not itemCountBox then return end
        count = tonumber(count) or 1
        if count < 1 then count = 1 end
        lootState.itemCount = count
        Utils.setEditBoxValue(itemCountBox, count, focus)
        lastUIState.itemCountText = tostring(count)
        dirtyFlags.itemCount = false
    end

    function module:ResetItemCount(focus)
        -- During multi-award from loot window we keep ItemCount stable (target N) to avoid
        -- mid-sequence clamping to the remaining copies.
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return
        end
        SetItemCountValue(addon.Loot:GetCurrentItemCount(), focus)
    end

    local function StopCountdown()
        -- Cancel active countdown timers and clear their handles
        addon.CancelTimer(countdownTicker, true)
        addon.CancelTimer(countdownEndTimer, true)
        countdownTicker = nil
        countdownEndTimer = nil
        countdownRun = false
    end

    local function ShouldAnnounceCountdownTick(remaining, duration)
        if remaining >= duration then
            return true
        end
        if remaining >= 10 then
            return (remaining % 10 == 0)
        end
        if remaining > 0 and remaining < 10 and remaining % 7 == 0 then
            return true
        end
        if remaining > 0 and remaining >= 5 and remaining % 5 == 0 then
            return true
        end
        return remaining > 0 and remaining <= 3
    end

    local function StartCountdown()
        StopCountdown()
        countdownRun = true
        local duration = addon.options.countdownDuration or 0
        local remaining = duration
        if ShouldAnnounceCountdownTick(remaining, duration) then
            addon:Announce(L.ChatCountdownTic:format(remaining))
        end
        countdownTicker = addon.NewTicker(1, function()
            remaining = remaining - 1
            if remaining > 0 then
                if ShouldAnnounceCountdownTick(remaining, duration) then
                    addon:Announce(L.ChatCountdownTic:format(remaining))
                end
            end
        end, duration)
        countdownEndTimer = addon.NewTimer(duration, function()
            if not countdownRun then return end
            StopCountdown()
            addon:Announce(L.ChatCountdownEnd)

            -- At zero: stop roll (enables selection in rolls) and refresh the UI
            addon.Rolls:RecordRolls(false)
            addon.Rolls:FetchRolls()
            module:RequestRefresh()
        end)
    end

    local function UpdateMasterButtonsIfChanged(state)
        local buttons = lastUIState.buttons
        local texts = lastUIState.texts

        local function UpdateEnabled(key, frame, enabled)
            if buttons[key] ~= enabled then
                Utils.enableDisable(frame, enabled)
                buttons[key] = enabled
            end
        end

        local function UpdateItemState(enabled)
            local itemBtn = _G[frameName .. "ItemBtn"]
            if itemBtn and buttons.itemBtn ~= enabled then
                Utils.enableDisable(itemBtn, enabled)
                local texture = itemBtn:GetNormalTexture()
                if texture and texture.SetDesaturated then
                    texture:SetDesaturated(not enabled)
                end
                buttons.itemBtn = enabled
            end
        end

        local function UpdateText(key, frame, text)
            if texts[key] ~= text then
                frame:SetText(text)
                texts[key] = text
            end
        end

        UpdateText("countdown", _G[frameName .. "CountdownBtn"], state.countdownText)
        UpdateText("award", _G[frameName .. "AwardBtn"], state.awardText)
        UpdateText("selectItem", _G[frameName .. "SelectItemBtn"], state.selectItemText)
        UpdateText("spamLoot", _G[frameName .. "SpamLootBtn"], state.spamLootText)

        UpdateEnabled("selectItem", _G[frameName .. "SelectItemBtn"], state.canSelectItem)
        UpdateEnabled("spamLoot", _G[frameName .. "SpamLootBtn"], state.canSpamLoot)
        UpdateEnabled("ms", _G[frameName .. "MSBtn"], state.canStartRolls)
        UpdateEnabled("os", _G[frameName .. "OSBtn"], state.canStartRolls)
        UpdateEnabled("sr", _G[frameName .. "SRBtn"], state.canStartSR)
        UpdateEnabled("free", _G[frameName .. "FreeBtn"], state.canStartRolls)
        UpdateEnabled("countdown", _G[frameName .. "CountdownBtn"], state.canCountdown)
        UpdateEnabled("hold", _G[frameName .. "HoldBtn"], state.canHold)
        UpdateEnabled("bank", _G[frameName .. "BankBtn"], state.canBank)
        UpdateEnabled("disenchant", _G[frameName .. "DisenchantBtn"], state.canDisenchant)
        UpdateEnabled("award", _G[frameName .. "AwardBtn"], state.canAward)
        UpdateText("reserveList", _G[frameName .. "ReserveListBtn"], state.reserveListText)
        UpdateEnabled("reserveList", _G[frameName .. "ReserveListBtn"], state.canReserveList)
        UpdateEnabled("roll", _G[frameName .. "RollBtn"], state.canRoll)
        UpdateEnabled("clear", _G[frameName .. "ClearBtn"], state.canClear)
        UpdateItemState(state.canChangeItem)
    end

    local function RefreshDropDowns(force)
        if not dropDownsInitialized then return end
        if not force and not dropDownDirty then return end
        UpdateDropDowns(dropDownFrameHolder)
        UpdateDropDowns(dropDownFrameBanker)
        UpdateDropDowns(dropDownFrameDisenchanter)
        dropDownDirty = false
        dirtyFlags.dropdowns = false
    end

    local function HookDropDownOpen(frame)
        if not frame then return end
        local button = _G[frame:GetName() .. "Button"]
        if button and not button._krtDropDownHook then
            button:HookScript("OnClick", function() RefreshDropDowns(true) end)
            button._krtDropDownHook = true
        end
    end

    local function BuildCandidateCache(itemLink)
        candidateCache.itemLink = itemLink
        twipe(candidateCache.indexByName)
        for p = 1, addon.GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                candidateCache.indexByName[candidate] = p
            end
        end
        addon:debug(Diag.D.LogMLCandidateCacheBuilt:format(tostring(itemLink),
            addon.tLength(candidateCache.indexByName)))
    end

    local function ResetTradeState()
        lootState.trader = nil
        lootState.winner = nil
        screenshotWarn = false
    end

    local function RegisterAwardedItem(count)
        local targetCount = tonumber(lootState.itemCount) or 1
        if targetCount < 1 then targetCount = 1 end
        local increment = tonumber(count) or 1
        if increment < 1 then increment = 1 end
        lootState.itemTraded = (lootState.itemTraded or 0) + increment
        if lootState.itemTraded >= targetCount then
            lootState.itemTraded = 0
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            return true
        end
        return false
    end

    -- ----- Public methods ----- --

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)
        -- Initialize ItemBtn scripts once (clean inventory drop support: click-to-drop).
        local itemBtn = _G[frameName .. "ItemBtn"]
        if itemBtn and not itemBtn.__krtMLInvDropInit then
            itemBtn.__krtMLInvDropInit = true
            itemBtn:RegisterForClicks("AnyUp")
            itemBtn:RegisterForDrag("LeftButton")

            -- Blizz-like gesture support:
            -- - Click while holding an item on the cursor
            -- - Drag&drop (release) an item onto the button
            local function TryAcceptFromCursor()
                if CursorHasItem and CursorHasItem() then
                    module:TryAcceptInventoryItemFromCursor()
                end
            end

            itemBtn:SetScript("OnClick", function(self, button)
                TryAcceptFromCursor()
            end)

            itemBtn:SetScript("OnReceiveDrag", function(self)
                TryAcceptFromCursor()
            end)
        end
        frame:SetScript("OnHide", function()
            if selectionFrame then selectionFrame:Hide() end
        end)
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    -- Button: Select/Remove Item
    function module:BtnSelectItem(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if countdownRun then return end
        lootState.multiAward = nil
        if lootState.fromInventory == true then
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            announced = false
            lootState.fromInventory = false
            itemInfo.count = 0
            itemInfo.isStack = nil
            itemInfo.bagID = nil
            itemInfo.slotID = nil
            if lootState.opened == true then addon.Loot:FetchLoot() end
        elseif selectionFrame then
            Utils.toggle(selectionFrame)
        end
        module:RequestRefresh()
    end

    -- Button: Spam Loot Links or Do Ready Check
    function module:BtnSpamLoot(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if lootState.fromInventory == true then
            addon:Announce(L.ChatReadyCheck)
            DoReadyCheck()
        else
            addon:Announce(L.ChatSpamLoot, "RAID")
            for i = 1, lootState.lootCount do
                local itemLink = GetItemLink(i)
                if itemLink then
                    local item = GetItem(i)
                    local count = item and item.count or 1
                    local suffix = (count and count > 1) and (" x" .. count) or ""
                    addon:Announce(i .. ". " .. itemLink .. suffix, "RAID")
                end
            end
        end
    end

    -- Button: Reserve List (contextual)
    function module:BtnReserveList(btn)
        if addon.Reserves:HasData() then
            addon.Reserves:Toggle()
        else
            addon.ReserveImport:Toggle()
        end
    end

    -- Button: Loot Counter
    function module:BtnLootCounter(btn)
        if addon.LootCounter and addon.LootCounter.Toggle then addon.LootCounter:Toggle() end
    end

    -- Generic function to announce a roll for the current item.
    local function AnnounceRoll(rollType, chatMsg)
        if lootState.lootCount >= 1 then
            announced = false
            lootState.currentRollType = rollType
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(true)
            lootState.rollStarted = true
            lootState.itemTraded = 0

            local itemLink = GetItemLink()
            local itemID = Utils.getItemIdFromLink(itemLink)
            local message = ""

            if rollType == rollTypes.RESERVED then
                -- Chat-safe: keep UI colors in the Reserve Frame, but do not send class color codes in chat.
                local srList = addon.Reserves:FormatReservedPlayersLine(itemID, false, false, false)
                local suff = addon.options.sortAscending and "Low" or "High"
                message = lootState.itemCount > 1
                    and L[chatMsg .. "Multiple" .. suff]:format(srList, itemLink, lootState.itemCount)
                    or L[chatMsg]:format(srList, itemLink)
            else
                local suff = addon.options.sortAscending and "Low" or "High"
                message = lootState.itemCount > 1
                    and L[chatMsg .. "Multiple" .. suff]:format(itemLink, lootState.itemCount)
                    or L[chatMsg]:format(itemLink)
            end

            addon:Announce(message)
            _G[frameName .. "ItemCount"]:ClearFocus()
            lootState.currentRollItem = addon.Raid:GetLootID(itemID)
            module:RequestRefresh()
        end
    end

    local function AssignToTarget(rollType, targetKey)
        if lootState.lootCount <= 0 or not lootState[targetKey] then return end
        countdownRun = false
        local itemLink = GetItemLink()
        if not itemLink then return end
        lootState.currentRollType = rollType
        local target = lootState[targetKey]
        local ok
        if lootState.fromInventory then
            ok = TradeItem(itemLink, target, rollType, 0)
        else
            ok = AssignItem(itemLink, target, rollType, 0)
        end
        if ok and not lootState.fromInventory then
            announced = false
            addon.Rolls:ClearRolls()
        end
        module:RequestRefresh()
        return ok
    end

    function module:BtnMS(btn)
        return AnnounceRoll(1, "ChatRollMS")
    end

    function module:BtnOS(btn)
        return AnnounceRoll(2, "ChatRollOS")
    end

    function module:BtnSR(btn)
        return AnnounceRoll(3, "ChatRollSR")
    end

    function module:BtnFree(btn)
        return AnnounceRoll(4, "ChatRollFree")
    end

    -- Button: Starts or stops the roll countdown.
    function module:BtnCountdown(btn)
        if countdownRun then
            addon.Rolls:RecordRolls(false)
            StopCountdown()
            addon.Rolls:FetchRolls()
            module:RequestRefresh()
        elseif not lootState.rollStarted then
            return
        else
            addon.Rolls:RecordRolls(true)
            announced = false
            StartCountdown()
            module:RequestRefresh()
        end
    end

    -- Button: Clear Rolls
    function module:BtnClear(btn)
        announced = false
        addon.Rolls:ClearRolls()
        module:RequestRefresh()
    end

    -- Button: Award/Trade
    function module:BtnAward(btn)
        if countdownRun then
            addon:warn(Diag.W.LogMLCountdownActive)
            return
        end
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            addon:warn(Diag.W.ErrMLMultiAwardInProgress)
            return
        end
        if lootState.lootCount <= 0 or lootState.rollsCount <= 0 then
            addon:debug(Diag.D.LogMLAwardBlocked:format(lootState.lootCount or 0, lootState.rollsCount or 0))
            return
        end
        if not lootState.winner then
            addon:warn(L.ErrNoWinnerSelected)
            return
        end
        countdownRun = false
        local itemLink = GetItemLink()
        addon:debug(Diag.D.LogMLAwardRequested:format(tostring(lootState.winner),
            tonumber(lootState.currentRollType) or -1, addon.Rolls:HighestRoll() or 0, tostring(itemLink)))
        local result
        if lootState.fromInventory == true then
            result = TradeItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
            module:ResetItemCount()
            module:RequestRefresh()
            return result
        end

        -- Loot window: support multi-award when ItemCount > 1 by consuming multiple identical copies
        -- (same itemString) sequentially on LOOT_SLOT_CLEARED.
        local target = tonumber(lootState.itemCount) or 1
        if target < 1 then target = 1 end
        local available = tonumber(addon.Loot:GetCurrentItemCount()) or 1
        if available < 1 then available = 1 end
        if target > available then target = available end
        if lootState.rollsCount and target > lootState.rollsCount then
            target = lootState.rollsCount
        end
        if available and available > 1 then
            local winners = {}

            -- Winners are taken from the current MultiSelect (CTRL+Click in roll list).
            -- In multi-copy mode, at least 1 winner must be selected; the addon awards exactly the selected count
            -- (clamped to the available copies).
            local selCount = Utils.multiSelectCount("MLRollWinners") or 0
            if selCount <= 0 then
                addon:warn(L.ErrNoWinnerSelected)
                module:ResetItemCount()
                return false
            end

            local awardCount = selCount
            if awardCount > target then awardCount = target end

            local picked = addon.Rolls.GetSelectedWinnersOrdered and addon.Rolls:GetSelectedWinnersOrdered() or {}
            if (not picked) or (#picked < awardCount) then
                addon:warn(Diag.W.ErrMLMultiSelectNotEnough:format(awardCount, picked and #picked or 0))
                module:ResetItemCount()
                return false
            end
            for i = 1, awardCount do
                local p = picked[i]
                if p and p.name then
                    winners[#winners + 1] = { name = p.name, roll = tonumber(p.roll) or 0 }
                end
            end

            -- Clear manual selection after capturing winners (prevents stale selection on next item).
            Utils.multiSelectClear("MLRollWinners")
            Utils.multiSelectSetAnchor("MLRollWinners", nil)
            if #winners <= 0 then
                addon:warn(L.ErrNoWinnerSelected)
                module:ResetItemCount()
                return false
            end

            -- Stabilize target count for the whole sequence and reflect the clamp in the UI.
            SetItemCountValue(#winners, false)

            lootState.multiAward = {
                active    = true,
                itemLink  = itemLink,
                itemKey   = Utils.getItemStringFromLink(itemLink) or itemLink,
                lastCount = available,
                rollType  = lootState.currentRollType,
                winners   = winners,
                pos       = 2, -- first award is immediate; the rest continues on LOOT_SLOT_CLEARED
                total     = #winners,
            }

            lootState.multiAward.announceOnWin = addon.options.announceOnWin and true or false
            lootState.multiAward.congratsSent = false

            -- Suppress per-copy ChatAward spam during multi-award; announce once on completion.
            announced = true
            -- First award immediately.
            lootState.winner = winners[1].name
            result = AssignItem(itemLink, winners[1].name, lootState.currentRollType, winners[1].roll)
            if result then
                RegisterAwardedItem(1)
                -- If this was the last copy for any reason, close the sequence now.
                if lootState.multiAward and lootState.multiAward.pos > lootState.multiAward.total then
                    local ma = lootState.multiAward
                    if ma and ma.announceOnWin and not ma.congratsSent then
                        local names = {}
                        for i = 1, (ma.total or (ma.winners and #ma.winners) or 0) do
                            local w = ma.winners and ma.winners[i]
                            if w and w.name then names[#names + 1] = w.name end
                        end
                        if #names > 0 then
                            if #names == 1 then
                                addon:Announce(L.ChatAward:format(names[1], ma.itemLink))
                            else
                                addon:Announce(L.ChatAwardMutiple:format(table.concat(names, ", "), ma.itemLink))
                            end
                        end
                        ma.congratsSent = true
                    end
                    lootState.multiAward = nil
                    announced = false
                    module:ResetItemCount()
                end
                module:RequestRefresh()
                return true
            end

            lootState.multiAward = nil
            announced = false
            module:ResetItemCount()
            module:RequestRefresh()
            return false
        end

        -- Single award (existing behavior): uses the currently selected winner.
        result = AssignItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
        if result then
            RegisterAwardedItem(1)
        end
        module:ResetItemCount()
        module:RequestRefresh()
        return result
    end

    -- Button: Hold item
    function module:BtnHold(btn)
        return AssignToTarget(rollTypes.HOLD, "holder")
    end

    -- Button: Bank item
    function module:BtnBank(btn)
        return AssignToTarget(rollTypes.BANK, "banker")
    end

    -- Button: Disenchant item
    function module:BtnDisenchant(btn)
        return AssignToTarget(rollTypes.DISENCHANT, "disenchanter")
    end

    -- Selects an item from the item selection frame.
    function module:BtnSelectedItem(btn)
        if not btn then return end
        local index = btn:GetID()
        if index ~= nil then
            announced = false
            selectionFrame:Hide()
            addon.Loot:SelectItem(index)
            module:ResetItemCount()
            module:RequestRefresh()
        end
    end

    -- Localizes UI frame elements.
    function LocalizeUIFrame()
        if localized then return end
        _G[frameName .. "ConfigBtn"]:SetText(L.BtnConfigure)
        _G[frameName .. "SelectItemBtn"]:SetText(L.BtnSelectItem)
        _G[frameName .. "SpamLootBtn"]:SetText(L.BtnSpamLoot)
        _G[frameName .. "MSBtn"]:SetText(L.BtnMS)
        _G[frameName .. "OSBtn"]:SetText(L.BtnOS)
        _G[frameName .. "SRBtn"]:SetText(L.BtnSR)
        _G[frameName .. "FreeBtn"]:SetText(L.BtnFree)
        _G[frameName .. "CountdownBtn"]:SetText(L.BtnCountdown)
        _G[frameName .. "AwardBtn"]:SetText(L.BtnAward)
        _G[frameName .. "RollBtn"]:SetText(L.BtnRoll)
        _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
        _G[frameName .. "HoldBtn"]:SetText(L.BtnHold)
        _G[frameName .. "BankBtn"]:SetText(L.BtnBank)
        _G[frameName .. "DisenchantBtn"]:SetText(L.BtnDisenchant)
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "RollsHeaderPlayer"]:SetText(L.StrPlayer)
        --_G[frameName .. "RollsHeaderCounter"]:SetText(L.StrCounter) -- (future use)
        _G[frameName .. "RollsHeaderRoll"]:SetText(L.StrRoll)
        _G[frameName .. "ReserveListBtn"]:SetText(L.BtnInsertList)
        _G[frameName .. "LootCounterBtn"]:SetText(L.BtnLootCounter)
        Utils.setFrameTitle(frameName, MASTER_LOOTER)

        local itemCountBox = _G[frameName .. "ItemCount"]
        if itemCountBox and not itemCountBox.__krtMLHooked then
            itemCountBox.__krtMLHooked = true
            itemCountBox:SetScript("OnTextChanged", function(self, isUserInput)
                if not isUserInput then return end
                announced = false
                dirtyFlags.itemCount = true
                dirtyFlags.buttons = true
                module:RequestRefresh()
            end)
            itemCountBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                announced = false
                dirtyFlags.itemCount = true
                dirtyFlags.buttons = true
                module:RequestRefresh()
            end)
            itemCountBox:SetScript("OnEditFocusLost", function(self)
                announced = false
                dirtyFlags.itemCount = true
                dirtyFlags.buttons = true
                module:RequestRefresh()
            end)
        end
        if next(dropDownData) == nil then
            for i = 1, 8 do dropDownData[i] = {} end
        end
        dropDownFrameHolder       = _G[frameName .. "HoldDropDown"]
        dropDownFrameBanker       = _G[frameName .. "BankDropDown"]
        dropDownFrameDisenchanter = _G[frameName .. "DisenchantDropDown"]
        PrepareDropDowns()
        UIDropDownMenu_Initialize(dropDownFrameHolder, InitializeDropDowns)
        UIDropDownMenu_Initialize(dropDownFrameBanker, InitializeDropDowns)
        UIDropDownMenu_Initialize(dropDownFrameDisenchanter, InitializeDropDowns)
        dropDownsInitialized = true
        HookDropDownOpen(dropDownFrameHolder)
        HookDropDownOpen(dropDownFrameBanker)
        HookDropDownOpen(dropDownFrameDisenchanter)
        RefreshDropDowns(true)
        localized = true
    end

    local function UpdateItemCountFromBox(itemCountBox)
        -- While a multi-award sequence is running from the loot window, ItemCount represents
        -- the target number of copies to distribute (not the remaining copies). Ignore edits.
        if lootState.multiAward and lootState.multiAward.active and not lootState.fromInventory then
            return
        end
        if not itemCountBox or not itemCountBox:IsVisible() then return end
        local rawCount = itemCountBox:GetText()
        if rawCount ~= lastUIState.itemCountText then
            lastUIState.itemCountText = rawCount
            dirtyFlags.itemCount = true
        end
        if dirtyFlags.itemCount then
            local count = tonumber(rawCount)
            if count and count > 0 then
                lootState.itemCount = count
                if lootState.fromInventory and itemInfo.count and itemInfo.count ~= lootState.itemCount then
                    if itemInfo.count < lootState.itemCount then
                        lootState.itemCount = itemInfo.count
                        itemCountBox:SetNumber(itemInfo.count)
                        lastUIState.itemCountText = tostring(itemInfo.count)
                    end
                end
            end
            dirtyFlags.itemCount = false
        end
    end

    local function UpdateRollStatusState()
        local rollType, record, canRoll, rolled = addon.Rolls:RollStatus()
        local rollStatus = lastUIState.rollStatus
        if rollStatus.record ~= record
            or rollStatus.canRoll ~= canRoll
            or rollStatus.rolled ~= rolled
            or rollStatus.rollType ~= rollType then
            rollStatus.record = record
            rollStatus.canRoll = canRoll
            rollStatus.rolled = rolled
            rollStatus.rollType = rollType
            dirtyFlags.rolls = true
            dirtyFlags.buttons = true
        end
        return record, canRoll, rolled
    end

    local function FlagButtonsOnChange(key, value)
        if lastUIState[key] ~= value then
            lastUIState[key] = value
            dirtyFlags.buttons = true
        end
    end
    -- Refreshes the UI once (event-driven; coalesced via module:RequestRefresh()).
    function UpdateUIFrame()
        LocalizeUIFrame()

        local itemCountBox = _G[frameName .. "ItemCount"]
        UpdateItemCountFromBox(itemCountBox)

        if dropDownDirty then
            dirtyFlags.dropdowns = true
        end

        local record, canRoll, rolled = UpdateRollStatusState()
        if lastUIState.rollsCount ~= lootState.rollsCount then
            lastUIState.rollsCount = lootState.rollsCount
            dirtyFlags.rolls = true
            dirtyFlags.buttons = true
        end

        if lastUIState.winner ~= lootState.winner then
            lastUIState.winner = lootState.winner
            dirtyFlags.winner = true
            dirtyFlags.buttons = true
        end

        FlagButtonsOnChange("lootCount", lootState.lootCount)
        FlagButtonsOnChange("fromInventory", lootState.fromInventory)
        FlagButtonsOnChange("holder", lootState.holder)
        FlagButtonsOnChange("banker", lootState.banker)
        FlagButtonsOnChange("disenchanter", lootState.disenchanter)

        local hasReserves = addon.Reserves:HasData()
        FlagButtonsOnChange("hasReserves", hasReserves)

        local hasItem = ItemExists()
        FlagButtonsOnChange("hasItem", hasItem)

        local itemId
        if hasItem then
            itemId = Utils.getItemIdFromLink(GetItemLink())
        end
        local hasItemReserves = itemId and addon.Reserves:HasItemReserves(itemId) or false
        FlagButtonsOnChange("hasItemReserves", hasItemReserves)
        FlagButtonsOnChange("countdownRun", countdownRun)

        local available = tonumber(addon.Loot:GetCurrentItemCount()) or 1
        if available < 1 then available = 1 end
        local pickMode = (not lootState.fromInventory)
        local msCount = pickMode and (Utils.multiSelectCount("MLRollWinners") or 0) or 0
        FlagButtonsOnChange("msCount", msCount)

        if dirtyFlags.buttons then
            UpdateMasterButtonsIfChanged({
                countdownText = countdownRun and L.BtnStop or L.BtnCountdown,
                awardText = lootState.fromInventory and TRADE or L.BtnAward,
                selectItemText = lootState.fromInventory and L.BtnRemoveItem or L.BtnSelectItem,
                spamLootText = lootState.fromInventory and READY_CHECK or L.BtnSpamLoot,
                canSelectItem = (lootState.lootCount > 1
                    or (lootState.fromInventory and lootState.lootCount >= 1)) and not countdownRun,
                canChangeItem = not countdownRun,
                canSpamLoot = lootState.lootCount >= 1,
                canStartRolls = lootState.lootCount >= 1,
                canStartSR = lootState.lootCount >= 1 and hasItemReserves,
                canCountdown = lootState.lootCount >= 1 and hasItem
                    and (lootState.rollStarted or countdownRun),
                canHold = lootState.lootCount >= 1 and lootState.holder,
                canBank = lootState.lootCount >= 1 and lootState.banker,
                canDisenchant = lootState.lootCount >= 1 and lootState.disenchanter,
                canAward = lootState.lootCount >= 1 and lootState.rollsCount >= 1 and not countdownRun and
                    (not pickMode or msCount > 0),
                reserveListText = hasReserves and L.BtnOpenList or L.BtnInsertList,
                canReserveList = true,
                canRoll = record and canRoll and rolled == false and countdownRun,
                canClear = lootState.rollsCount >= 1,
            })
            dirtyFlags.buttons = false
        end

        dirtyFlags.rolls = false
        dirtyFlags.winner = false
    end

    -- Initializes the dropdown menus for player selection.
    function InitializeDropDowns()
        if UIDROPDOWNMENU_MENU_LEVEL == 2 then
            local g = UIDROPDOWNMENU_MENU_VALUE
            local m = dropDownData[g]
            for key, value in pairs(m) do
                local info        = UIDropDownMenu_CreateInfo()
                info.hasArrow     = false
                info.notCheckable = 1
                info.text         = key
                info.func         = module.OnClickDropDown
                info.arg1         = UIDROPDOWNMENU_OPEN_MENU
                info.arg2         = key
                UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end
        if UIDROPDOWNMENU_MENU_LEVEL == 1 then
            for key, value in pairs(dropDownData) do
                if dropDownGroupData[key] == true then
                    local info        = UIDropDownMenu_CreateInfo()
                    info.hasArrow     = 1
                    info.notCheckable = 1
                    info.text         = GROUP .. " " .. key
                    info.value        = key
                    info.owner        = UIDROPDOWNMENU_OPEN_MENU
                    UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
                end
            end
        end
    end

    -- Prepares the data for the dropdowns by fetching the raid roster.
    function PrepareDropDowns()
        local rosterVersion = addon.Raid.GetRosterVersion and addon.Raid:GetRosterVersion() or nil
        if rosterVersion and cachedRosterVersion == rosterVersion then
            return
        end
        cachedRosterVersion = rosterVersion
        dropDownDirty = true
        dirtyFlags.dropdowns = true

        for i = 1, 8 do
            local t = dropDownData[i]
            if t then
                twipe(t)
            else
                t = {}
                dropDownData[i] = t
            end
        end

        dropDownGroupData = dropDownGroupData or {}
        twipe(dropDownGroupData)

        for unit, owner in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" then
                local subgroup = 1

                -- Se siamo in raid, ricava il subgroup reale
                local idx = tonumber(unit:match("^raid(%d+)$"))
                if idx then
                    subgroup = (select(3, GetRaidRosterInfo(idx))) or 1
                end

                dropDownData[subgroup] = dropDownData[subgroup] or {}
                dropDownData[subgroup][name] = name
                dropDownGroupData[subgroup] = true
            end
        end

        RefreshDropDowns(true)
    end

    module.PrepareDropDowns = PrepareDropDowns

    -- Dropdown field metadata: maps frame name suffixes to state keys (lazily bound at runtime).
    local function FindDropDownField(frameNameFull)
        if not frameNameFull then return nil end

        -- Match dropdown frame name to find the field type
        if frameNameFull == dropDownFrameHolder:GetName() then
            return { stateKey = "holder", raidKey = "holder", frame = dropDownFrameHolder }
        elseif frameNameFull == dropDownFrameBanker:GetName() then
            return { stateKey = "banker", raidKey = "banker", frame = dropDownFrameBanker }
        elseif frameNameFull == dropDownFrameDisenchanter:GetName() then
            return { stateKey = "disenchanter", raidKey = "disenchanter", frame = dropDownFrameDisenchanter }
        end
        return nil
    end

    -- OnClick handler for dropdown menu items (consolidated from 3 similar branches).
    function module:OnClickDropDown(owner, value)
        if not KRT_CurrentRaid then return end
        UIDropDownMenu_SetText(owner, value)
        UIDropDownMenu_SetSelectedValue(owner, value)

        local field = FindDropDownField(owner:GetName())
        if field then
            KRT_Raids[KRT_CurrentRaid][field.raidKey] = value
            lootState[field.stateKey] = value
        end

        dropDownDirty = true
        dirtyFlags.dropdowns = true
        dirtyFlags.buttons = true
        CloseDropDownMenus()
        module:RequestRefresh()
    end

    -- Updates the text of the dropdowns to reflect the current selection (consolidated from 3 similar branches).
    function UpdateDropDowns(frame)
        if not frame or not KRT_CurrentRaid then return end

        local field = FindDropDownField(frame:GetName())
        if not field then return end

        -- Sync state from raid data
        lootState[field.stateKey] = KRT_Raids[KRT_CurrentRaid][field.raidKey]

        -- Clear if unit is no longer in raid
        if lootState[field.stateKey] and addon.Raid:GetUnitID(lootState[field.stateKey]) == "none" then
            KRT_Raids[KRT_CurrentRaid][field.raidKey] = nil
            lootState[field.stateKey] = nil
        end

        -- Update UI if value is valid
        if lootState[field.stateKey] then
            UIDropDownMenu_SetText(field.frame, lootState[field.stateKey])
            UIDropDownMenu_SetSelectedValue(field.frame, lootState[field.stateKey])
            dirtyFlags.buttons = true
        end
    end

    -- Creates the item selection frame if it doesn't exist.
    local function CreateSelectionFrame()
        if selectionFrame == nil then
            local frame = getFrame()
            if not frame then return end
            selectionFrame = CreateFrame("Frame", nil, frame, "KRTSimpleFrameTemplate")
            selectionFrame:Hide()
        end
        local index = 1
        local btnName = frameName .. "ItemSelectionBtn" .. index
        local btn = _G[btnName]
        while btn ~= nil do
            btn:Hide()
            index = index + 1
            btnName = frameName .. "ItemSelectionBtn" .. index
            btn = _G[btnName]
        end
    end

    -- Updates the item selection frame with the current loot items.
    function UpdateSelectionFrame()
        CreateSelectionFrame()
        local height = 5
        for i = 1, lootState.lootCount do
            local btnName = frameName .. "ItemSelectionBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, selectionFrame, "KRTItemSelectionButton")
            btn:SetID(i)
            btn:Show()
            local itemName = GetItemName(i)
            local itemNameBtn = _G[btnName .. "Name"]
            local item = GetItem(i)
            local count = item and item.count or 1
            if count and count > 1 then
                itemNameBtn:SetText(itemName .. " x" .. count)
            else
                itemNameBtn:SetText(itemName)
            end
            local itemTexture = GetItemTexture(i)
            local itemTextureBtn = _G[btnName .. "Icon"]
            itemTextureBtn:SetTexture(itemTexture)
            btn:SetPoint("TOPLEFT", selectionFrame, "TOPLEFT", 0, -height)
            height = height + 37
        end
        selectionFrame:SetHeight(height)
        if lootState.lootCount <= 0 then
            selectionFrame:Hide()
        end
    end

    -- ----- Event Handlers & Callbacks ----- --

    local function ScanTradeableInventory(itemLink, itemId)
        if not itemLink and not itemId then return nil end
        local wantedKey = itemLink and (Utils.getItemStringFromLink(itemLink) or itemLink) or nil
        local wantedId = tonumber(itemId) or (itemLink and Utils.getItemIdFromLink(itemLink)) or nil
        local totalCount = 0
        local firstBag, firstSlot, firstSlotCount
        local hasMatch = false
        -- Backpack (0) + 4 bag slots (1..4) in WoW 3.3.5a.
        for bag = 0, 4 do
            local n = GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local key = Utils.getItemStringFromLink(link) or link
                    local linkId = Utils.getItemIdFromLink(link)
                    local matches = (wantedKey and key == wantedKey) or (wantedId and linkId == wantedId)
                    if matches then
                        hasMatch = true
                        if not ItemIsSoulbound(bag, slot) then
                            local _, count = GetContainerItemInfo(bag, slot)
                            local slotCount = tonumber(count) or 1
                            totalCount = totalCount + slotCount
                            if not firstBag then
                                firstBag = bag
                                firstSlot = slot
                                firstSlotCount = slotCount
                            end
                        end
                    end
                end
            end
        end
        return totalCount, firstBag, firstSlot, firstSlotCount, hasMatch
    end

    local function ApplyInventoryItem(itemLink, totalCount, inBag, inSlot, slotCount)
        if countdownRun then return false end
        if not itemLink then return false end
        local itemCount = tonumber(totalCount) or 1
        if itemCount < 1 then itemCount = 1 end

        -- Clear count:
        Utils.resetEditBox(_G[frameName .. "ItemCount"], true)

        lootState.fromInventory = true
        addon.Loot:AddItem(itemLink, itemCount)
        addon.Loot:PrepareItem()
        announced = false

        itemInfo.bagID = inBag
        itemInfo.slotID = inSlot
        itemInfo.count = itemCount
        itemInfo.isStack = (tonumber(slotCount) or 1) > 1

        module:ResetItemCount(true)
        ClearCursor()
        module:RequestRefresh()
        return true
    end

    -- Accept an item currently held on the cursor (bag click-pickup).
    -- This is triggered by ItemBtn's OnClick.
    function module:TryAcceptInventoryItemFromCursor()
        if countdownRun then return false end
        if not CursorHasItem or not CursorHasItem() then return false end

        local infoType, itemId, itemLink = GetCursorInfo()
        if infoType ~= "item" then return false end

        local totalCount, bag, slot, slotCount, hasMatch = ScanTradeableInventory(itemLink, itemId)
        if not totalCount or totalCount < 1 then
            local itemRef = tostring(itemLink or itemId or "unknown")
            if hasMatch then
                addon:warn(L.ErrMLInventorySoulbound:format(itemRef))
                addon:debug(Diag.D.LogMLInventorySoulbound:format(itemRef))
            else
                addon:warn(L.ErrMLInventoryItemMissing:format(itemRef))
            end
            ClearCursor()
            return true
        end

        if not itemLink and bag and slot then
            itemLink = GetContainerItemLink(bag, slot)
        end
        if not itemLink then
            addon:warn(L.ErrMLInventoryItemMissing:format(tostring(itemLink or itemId or "unknown")))
            ClearCursor()
            return true
        end

        return ApplyInventoryItem(itemLink, totalCount, bag, slot, slotCount)
    end

    -- LOOT_OPENED: Triggered when the loot window opens.
    function module:LOOT_OPENED()
        if addon.Raid:IsMasterLooter() then
            lootState.opened = true
            announced = false
            addon.Loot:FetchLoot()
            addon:trace(Diag.D.LogMLLootOpenedTrace:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory)))
            UpdateSelectionFrame()
            if not addon.Logger.container then
                addon.Logger.source = UnitName("target")
            end
            addon:debug(Diag.D.LogMLLootOpenedInfo:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory), tostring(UnitName("target"))))

            local shouldShow = (lootState.lootCount or 0) >= 1
            local frame = getFrame()
            if shouldShow and frame then
                -- Request while hidden to refresh immediately on OnShow (avoid an extra refresh).
                module:RequestRefresh()
                frame:Show()
            else
                -- Keep state dirty for the next time the frame is shown.
                module:RequestRefresh()
            end
        end
    end

    -- LOOT_CLOSED: Triggered when the loot window closes.
    function module:LOOT_CLOSED()
        if addon.Raid:IsMasterLooter() then
            addon:trace(Diag.D.LogMLLootClosed:format(tostring(lootState.opened), lootState.lootCount or 0))
            addon:trace(Diag.D.LogMLLootClosedCleanup)
            lootState.multiAward = nil
            announced = false
            -- Cancel any scheduled close timer and schedule a new one
            if lootState.closeTimer then
                addon.CancelTimer(lootState.closeTimer)
                lootState.closeTimer = nil
            end
            lootState.closeTimer = addon.NewTimer(0.1, function()
                lootState.closeTimer = nil
                lootState.opened = false
                lootState.pendingAwards = {}
                local frame = getFrame()
                if frame then frame:Hide() end
                addon.Loot:ClearLoot()
                addon.Rolls:ClearRolls()
                addon.Rolls:RecordRolls(false)
                module:RequestRefresh()
            end)
        end
    end

    -- LOOT_SLOT_CLEARED: Triggered when an item is looted.
    function module:LOOT_SLOT_CLEARED()
        if addon.Raid:IsMasterLooter() then
            addon.Loot:FetchLoot()
            addon:trace(Diag.D.LogMLLootSlotCleared:format(lootState.lootCount or 0))
            UpdateSelectionFrame()
            module:ResetItemCount()

            local frame = getFrame()
            local shouldShow = (lootState.lootCount or 0) >= 1
            if shouldShow then
                local wasShown = frame and frame:IsShown()
                if not wasShown then
                    -- Request while hidden to refresh immediately on OnShow (avoid an extra refresh).
                    module:RequestRefresh()
                    if frame then frame:Show() end
                else
                    module:RequestRefresh()
                end
            else
                if frame then frame:Hide() end
                addon:debug(Diag.D.LogMLLootWindowEmptied)
            end

            -- Continue a multi-award sequence (loot window only). We award one copy per LOOT_SLOT_CLEARED
            -- with a small delay to stay in sync with server/loot window refresh (and avoid lag spikes).
            local ma = lootState.multiAward
            if ma and ma.active and not lootState.fromInventory then
                -- Prevent double-scheduling if the loot window fires multiple clear events quickly.
                if ma.scheduled then
                    return
                end
                -- Gate: proceed only when the number of copies for this itemKey has decreased since last award.
                local currentCount = 0
                for i = 1, (lootState.lootCount or 0) do
                    local it = GetItem and GetItem(i)
                    if it and it.itemKey == ma.itemKey then
                        currentCount = tonumber(it.count) or 1
                        break
                    end
                end
                if ma.lastCount and currentCount >= ma.lastCount then
                    return
                end
                ma.lastCount = currentCount
                local idx = tonumber(ma.pos) or 1
                local entry = ma.winners and ma.winners[idx]
                if not entry then
                    lootState.multiAward = nil
                    announced = false
                    module:ResetItemCount()
                    module:RequestRefresh()
                    return
                end

                ma.scheduled = true
                local delay = tonumber(C.ML_MULTI_AWARD_DELAY) or 0
                if delay < 0 then delay = 0 end

                addon.After(delay, function()
                    local ma2 = lootState.multiAward
                    if not (ma2 and ma2.active and ma2.scheduled and not lootState.fromInventory) then
                        return
                    end
                    ma2.scheduled = false

                    local idx2 = tonumber(ma2.pos) or 1
                    local e2 = ma2.winners and ma2.winners[idx2]
                    if not e2 then
                        lootState.multiAward = nil
                        announced = false
                        module:ResetItemCount()
                        module:RequestRefresh()
                        return
                    end

                    -- Suppress per-copy ChatAward spam during multi-award; announce once on completion.
                    announced = true
                    lootState.winner = e2.name
                    lootState.currentRollType = ma2.rollType
                    module:RequestRefresh()

                    local ok = AssignItem(ma2.itemLink, e2.name, ma2.rollType, e2.roll)
                    if ok then
                        RegisterAwardedItem(1)
                        ma2.pos = idx2 + 1
                        if ma2.pos > (ma2.total or #ma2.winners) then
                            local ma = lootState.multiAward
                            if ma and ma.announceOnWin and not ma.congratsSent then
                                local names = {}
                                for i = 1, (ma.total or (ma.winners and #ma.winners) or 0) do
                                    local w = ma.winners and ma.winners[i]
                                    if w and w.name then names[#names + 1] = w.name end
                                end
                                if #names > 0 then
                                    if #names == 1 then
                                        addon:Announce(L.ChatAward:format(names[1], ma.itemLink))
                                    else
                                        addon:Announce(L.ChatAwardMutiple:format(table.concat(names, ", "), ma.itemLink))
                                    end
                                end
                                ma.congratsSent = true
                            end
                            lootState.multiAward = nil
                            announced = false
                            module:ResetItemCount()
                            module:RequestRefresh()
                        end
                    else
                        lootState.multiAward = nil
                        announced = false
                        module:ResetItemCount()
                        module:RequestRefresh()
                    end
                end)
            end
        end
    end

    function module:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
        addon:trace(Diag.D.LogTradeAcceptUpdate:format(tostring(lootState.trader), tostring(lootState.winner),
            tostring(tAccepted), tostring(pAccepted)))
        if lootState.trader and lootState.winner and lootState.trader ~= lootState.winner then
            if tAccepted == 1 and pAccepted == 1 then
                addon:debug(Diag.D.LogTradeCompleted:format(tostring(lootState.currentRollItem),
                    tostring(lootState.winner), tonumber(lootState.currentRollType) or -1,
                    addon.Rolls:HighestRoll()))
                if lootState.currentRollItem and lootState.currentRollItem > 0 then
                    local ok = addon.Logger.Loot:Log(lootState.currentRollItem, lootState.winner,
                        lootState.currentRollType, addon.Rolls:HighestRoll(), "TRADE_ACCEPT", KRT_CurrentRaid)

                    if not ok then
                        addon:error(Diag.E.LogTradeLoggerLogFailed:format(tostring(KRT_CurrentRaid),
                            tostring(lootState.currentRollItem), tostring(GetItemLink())))
                    end
                else
                    addon:warn(Diag.W.LogTradeCurrentRollItemMissing)
                end

                -- LootCounter (MS only): trade awards don't emit LOOT_ITEM for the winner.
                if tonumber(lootState.currentRollType) == rollTypes.MAINSPEC then
                    addon.Raid:AddPlayerCount(lootState.winner, 1, KRT_CurrentRaid)
                end

                local done = RegisterAwardedItem()
                ResetTradeState()
                if done then
                    addon.Loot:ClearLoot()
                    addon.Raid:ClearRaidIcons()
                end
                screenshotWarn = false
                module:RequestRefresh()
            end
        end
    end

    -- TRADE_CLOSED: trade window closed (completed or canceled)
    function module:TRADE_CLOSED()
        ResetTradeState("TRADE_CLOSED")
        module:RequestRefresh()
    end

    -- TRADE_REQUEST_CANCEL: trade request canceled before opening
    function module:TRADE_REQUEST_CANCEL()
        ResetTradeState("TRADE_REQUEST_CANCEL")
        module:RequestRefresh()
    end

    -- Assigns an item from the loot window to a player.
    function AssignItem(itemLink, playerName, rollType, rollValue)
        local itemIndex, tempItemLink
        local wantedKey = Utils.getItemStringFromLink(itemLink) or itemLink
        for i = 1, GetNumLootItems() do
            tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                itemIndex = i
                break
            end
            if wantedKey and tempItemLink then
                local tempKey = Utils.getItemStringFromLink(tempItemLink) or tempItemLink
                if tempKey == wantedKey then
                    itemIndex = i
                    break
                end
            end
        end
        if itemIndex == nil then
            addon:error(L.ErrCannotFindItem:format(itemLink))
            return false
        end

        if candidateCache.itemLink ~= itemLink then
            BuildCandidateCache(itemLink)
        end
        local candidateIndex = candidateCache.indexByName[playerName]
        if not candidateIndex then
            addon:debug(Diag.D.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            BuildCandidateCache(itemLink)
            candidateIndex = candidateCache.indexByName[playerName]
        end
        if candidateIndex then
            -- Mark this award as addon-driven so AddLoot() won't classify it as MANUAL
            addon.Loot:QueuePendingAward(itemLink, playerName, rollType, rollValue)
            GiveMasterLoot(itemIndex, candidateIndex)
            addon:debug(Diag.D.LogMLAwarded:format(tostring(itemLink), tostring(playerName),
                tonumber(rollType) or -1, tonumber(rollValue) or 0, tonumber(itemIndex) or -1,
                tonumber(candidateIndex) or -1))
            local output, whisper
            if rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE
                and addon.options.announceOnWin then
                output = L.ChatAward:format(playerName, itemLink)
            elseif rollType == rollTypes.HOLD and addon.options.announceOnHold then
                output = L.ChatHold:format(playerName, itemLink)
                if addon.options.lootWhispers then
                    whisper = L.WhisperHoldAssign:format(itemLink)
                end
            elseif rollType == rollTypes.BANK and addon.options.announceOnBank then
                output = L.ChatBank:format(playerName, itemLink)
                if addon.options.lootWhispers then
                    whisper = L.WhisperBankAssign:format(itemLink)
                end
            elseif rollType == rollTypes.DISENCHANT and addon.options.announceOnDisenchant then
                output = L.ChatDisenchant:format(itemLink, playerName)
                if addon.options.lootWhispers then
                    whisper = L.WhisperDisenchantAssign:format(itemLink)
                end
            end

            if output and not announced then
                addon:Announce(output)
                announced = true
            end
            if whisper then
                Utils.whisper(playerName, whisper)
            end
            -- IMPORTANT:
            -- Do NOT force-update an existing raid.loot entry here.
            -- For Master Loot awards from the loot window, the authoritative record is created by Raid:AddLoot()
            -- from the LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event, where we also apply the pending rollType/rollValue.
            --
            -- If multiple identical items are distributed across different roll types ("partial award" workflow),
            -- using a pre-resolved lootNid can overwrite previous entries because GetLootID() matches by itemId.
            -- Keeping the logging entirely event-driven avoids that class of data corruption.
            return true
        end
        addon:error(L.ErrCannotFindPlayer:format(playerName))
        return false
    end

    -- Trades an item from inventory to a player.
    function TradeItem(itemLink, playerName, rollType, rollValue)
        if itemLink ~= GetItemLink() then return end
        local isAwardRoll = (rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE)

        ResetTradeState("TRADE_START")

        lootState.trader = Utils.getPlayerName()
        lootState.winner = isAwardRoll and playerName or nil

        addon:debug(Diag.D.LogTradeStart:format(tostring(itemLink), tostring(lootState.trader),
            tostring(playerName), tonumber(rollType) or -1, tonumber(rollValue) or 0,
            lootState.itemCount or 1))

        -- Prepare initial output and whisper:
        local output, whisper
        local keep = not isAwardRoll

        if isAwardRoll and addon.options.announceOnWin then
            output = L.ChatAward:format(playerName, itemLink)
        elseif rollType == rollTypes.HOLD and addon.options.announceOnHold then
            output = L.ChatNoneRolledHold:format(itemLink, playerName)
        elseif rollType == rollTypes.BANK and addon.options.announceOnBank then
            output = L.ChatNoneRolledBank:format(itemLink, playerName)
        elseif rollType == rollTypes.DISENCHANT and addon.options.announceOnDisenchant then
            output = L.ChatNoneRolledDisenchant:format(itemLink, playerName)
        end

        -- Keeping the item:
        if keep then
            if rollType == rollTypes.HOLD then
                whisper = L.WhisperHoldTrade:format(itemLink)
            elseif rollType == rollTypes.BANK then
                whisper = L.WhisperBankTrade:format(itemLink)
            elseif rollType == rollTypes.DISENCHANT then
                whisper = L.WhisperDisenchantTrade:format(itemLink)
            end
            -- Multiple winners:
        elseif lootState.itemCount > 1 then
            -- Announce multiple winners
            addon.Raid:ClearRaidIcons()
            if lootState.trader ~= lootState.winner then
                SetRaidTarget(lootState.trader, 1)
            end
            local rolls = addon.Rolls:GetRolls()
            local winners = {}
            for i = 1, lootState.itemCount do
                if rolls[i] then
                    if rolls[i].name == lootState.trader then
                        if lootState.trader ~= lootState.winner then
                            tinsert(winners, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
                        else
                            tinsert(winners, rolls[i].name .. "(" .. rolls[i].roll .. ")")
                        end
                    else
                        SetRaidTarget(rolls[i].name, i + 1)
                        tinsert(winners, RAID_TARGET_MARKERS[i] .. " " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
                    end
                end
            end
            output = L.ChatTradeMutiple:format(tconcat(winners, ", "), lootState.trader)
            -- Trader is the winner:
        elseif lootState.trader == lootState.winner then
            -- Trader won, clear state
            addon:debug(Diag.D.LogTradeTraderKeeps:format(tostring(itemLink), tostring(playerName)))

            -- LootCounter (MS only): award is immediate (no trade window completion event).
            if tonumber(rollType) == rollTypes.MAINSPEC then
                addon.Raid:AddPlayerCount(playerName, 1, KRT_CurrentRaid)
            end

            local done = RegisterAwardedItem(lootState.itemCount)
            if done then
                addon.Loot:ClearLoot()
                addon.Raid:ClearRaidIcons()
            end
        else
            local unit = addon.Raid:GetUnitID(playerName)
            if unit ~= "none" and CheckInteractDistance(unit, 2) == 1 then
                -- Player is in range for trade
                local totalCount, bag, slot, slotCount = ScanTradeableInventory(itemLink,
                    Utils.getItemIdFromLink(itemLink))
                if bag and slot then
                    itemInfo.bagID = bag
                    itemInfo.slotID = slot
                    itemInfo.isStack = (tonumber(slotCount) or 1) > 1
                    itemInfo.count = totalCount or itemInfo.count
                else
                    addon:warn(L.ErrMLInventoryItemMissing:format(tostring(itemLink)))
                    return false
                end
                if itemInfo.isStack and not addon.options.ignoreStacks then
                    addon:debug(Diag.D.LogTradeStackBlocked:format(tostring(addon.options.ignoreStacks),
                        tostring(itemLink)))
                    addon:warn(L.ErrItemStack:format(itemLink))
                    return false
                end
                ClearCursor()
                PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
                if CursorHasItem() then
                    InitiateTrade(playerName)
                    addon:debug(Diag.D.LogTradeInitiated:format(tostring(itemLink), tostring(playerName)))
                    if addon.options.screenReminder and not screenshotWarn then
                        addon:warn(L.ErrScreenReminder)
                        screenshotWarn = true
                    end
                end
                -- Cannot trade the player?
            elseif unit ~= "none" then
                -- Player is out of range
                addon:warn(Diag.W.LogTradeDelayedOutOfRange:format(tostring(playerName), tostring(itemLink)))
                addon.Raid:ClearRaidIcons()
                SetRaidTarget(lootState.trader, 1)
                if isAwardRoll then SetRaidTarget(playerName, 4) end
                output = L.ChatTrade:format(playerName, itemLink)
            end
        end

        if not announced then
            if output then addon:Announce(output) end
            if whisper then
                if playerName == lootState.trader then
                    addon.Loot:ClearLoot()
                    addon.Rolls:ClearRolls()
                    addon.Rolls:RecordRolls(false)
                else
                    Utils.whisper(playerName, whisper)
                end
            end
            if rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE
                and playerName == lootState.trader then
                local ok = addon.Logger.Loot:Log(lootState.currentRollItem, lootState.trader, rollType, rollValue,
                    "TRADE_KEEP", KRT_CurrentRaid)
                if not ok then
                    addon:error(Diag.E.LogTradeKeepLoggerFailed:format(tostring(KRT_CurrentRaid),
                        tostring(lootState.currentRollItem), tostring(itemLink)))
                end
            end
            announced = true
        end
        return true
    end

    -- Register some callbacks:
    Utils.registerCallback("SetItem", function(f, itemLink)
        local oldItem = GetItemLink()
        if oldItem ~= itemLink then
            announced = false
        end
    end)

    -- Keep Master UI in sync when SoftRes data changes (import/clear), event-driven.
    Utils.registerCallback("ReservesDataChanged", function()
        module:RequestRefresh()
    end)
end

-- =========== Loot Counter Module  =========== --
-- Counter and display item distribution (MS wins).
do
    addon.LootCounter = addon.LootCounter or {}
    local module = addon.LootCounter

    -- ----- Internal state ----- --
    local frameName
    local rows, raidPlayers = {}, {}
    local twipe = twipe
    local scrollFrame, scrollChild, header
    local getFrame = Utils.makeFrameGetter("KRTLootCounterFrame")

    bindModuleRequestRefresh(module, getFrame)

    -- Single-line column header.
    local HEADER_HEIGHT = 18

    -- Layout constants (columns: Name | Count | Actions)
    local BTN_W, BTN_H = 20, 18
    local BTN_GAP = 2
    local COL_GAP = 8
    local ACTION_COL_W = (BTN_W * 3) + (BTN_GAP * 2) + 2 -- (+/-/R + gaps + right pad)
    local COUNT_COL_W = 40

    local function EnsureFrames()
        local frame = getFrame()
        if not frame then
            return false
        end

        frameName = frameName or (frame.GetName and frame:GetName()) or "KRTLootCounterFrame"
        scrollFrame = scrollFrame
            or frame.ScrollFrame
            or _G[frameName .. "ScrollFrame"]
            or _G["KRTLootCounterFrameScrollFrame"]

        scrollChild = scrollChild
            or (scrollFrame and scrollFrame.ScrollChild)
            or _G["KRTLootCounterFrameScrollFrameScrollChild"]

        if not frame._krtCounterInit then
            Utils.setFrameTitle(frameName, L.StrLootCounter)
            frame._krtCounterInit = true
        end

        return true
    end

    local function EnsureHeader()
        if header or not scrollChild then return end

        header = CreateFrame("Frame", nil, scrollChild)
        header:SetHeight(HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)

        -- Column labels: Player | Count | (blank actions column)
        -- Layout: actions anchored hard-right, count just to its left, name fills remaining space.
        header.action = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.action:SetPoint("RIGHT", header, "RIGHT", -2, 0)
        header.action:SetWidth(ACTION_COL_W)
        header.action:SetJustifyH("RIGHT")
        header.action:SetText("")

        header.count = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.count:SetPoint("RIGHT", header.action, "LEFT", -COL_GAP, 0)
        header.count:SetWidth(COUNT_COL_W)
        header.count:SetJustifyH("CENTER")
        header.count:SetText(L.StrCount)
        header.count:SetTextColor(0.5, 0.5, 0.5)

        header.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.name:SetPoint("LEFT", header, "LEFT", 0, 0)
        header.name:SetPoint("RIGHT", header.count, "LEFT", -COL_GAP, 0)
        header.name:SetJustifyH("LEFT")
        header.name:SetText(L.StrPlayer)
        header.name:SetTextColor(0.5, 0.5, 0.5)
    end

    local function GetCurrentRaidPlayers()
        twipe(raidPlayers)
        if not addon.IsInGroup() then
            return raidPlayers
        end

        for unit in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" then
                raidPlayers[#raidPlayers + 1] = name
            end
        end
        table.sort(raidPlayers)
        return raidPlayers
    end

    local function EnsureRow(i, rowHeight)
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(rowHeight)

            -- Actions container: hard-right, next to the scrollbar.
            row.actions = CreateFrame("Frame", nil, row)
            row.actions:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.actions:SetSize(ACTION_COL_W, rowHeight)

            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.count:SetPoint("RIGHT", row.actions, "LEFT", -COL_GAP, 0)
            row.count:SetWidth(COUNT_COL_W)
            row.count:SetJustifyH("CENTER")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.name:SetPoint("RIGHT", row.count, "LEFT", -COL_GAP, 0)
            row.name:SetJustifyH("LEFT")

            local function SetupTooltip(btn, text)
                if not text or text == "" then return end
                btn:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(text, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                btn:HookScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            local function MakeBtn(label, tip)
                local b = CreateFrame("Button", nil, row.actions, "KRTButtonTemplate")
                b:SetSize(BTN_W, BTN_H)
                b:SetText(label)
                SetupTooltip(b, tip)
                return b
            end

            row.reset = MakeBtn("R", L.TipLootCounterReset)
            row.minus = MakeBtn("-", L.TipLootCounterMinus)
            row.plus  = MakeBtn("+", L.TipLootCounterPlus)

            row.reset:SetPoint("RIGHT", row.actions, "RIGHT", 0, 0)
            row.minus:SetPoint("RIGHT", row.reset, "LEFT", -BTN_GAP, 0)
            row.plus:SetPoint("RIGHT", row.minus, "LEFT", -BTN_GAP, 0)

            row.plus:SetScript("OnClick", function()
                local n = row._playerName
                if n then
                    addon.Raid:AddPlayerCount(n, 1, KRT_CurrentRaid)
                    module:RequestRefresh()
                end
            end)
            row.minus:SetScript("OnClick", function()
                local n = row._playerName
                if n then
                    addon.Raid:AddPlayerCount(n, -1, KRT_CurrentRaid)
                    module:RequestRefresh()
                end
            end)
            row.reset:SetScript("OnClick", function()
                local n = row._playerName
                if n then
                    addon.Raid:SetPlayerCount(n, 0, KRT_CurrentRaid)
                    module:RequestRefresh()
                end
            end)

            rows[i] = row
        end
        return row
    end

    function module:OnLoad(frame)
        if frame then
            module.frame = frame
        end
        if not EnsureFrames() then return end

        local f = getFrame()
        if not f then return end

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(f)
    end

    function module:Refresh()
        if not EnsureFrames() then return end
        local frame = getFrame()
        if not frame or not scrollFrame or not scrollChild then return end

        EnsureHeader()

        local players = GetCurrentRaidPlayers()
        local numPlayers = #players
        local rowHeight = C.LOOT_COUNTER_ROW_HEIGHT

        local contentHeight = HEADER_HEIGHT + (numPlayers * rowHeight)
        local priorScroll = scrollFrame:GetVerticalScroll() or 0

        -- Ensure the scroll child has a valid size (UIPanelScrollFrameTemplate needs this)
        local contentW = scrollFrame:GetWidth() or 0
        local sb = scrollFrame.ScrollBar or (scrollFrame.GetName and _G[scrollFrame:GetName() .. "ScrollBar"]) or nil
        local sbw = (sb and sb.GetWidth and sb:GetWidth()) or 16
        if sbw <= 0 then sbw = 16 end
        contentW = math.max(1, contentW - sbw - 6)
        scrollChild:SetWidth(contentW)
        scrollChild:SetHeight(math.max(contentHeight, scrollFrame:GetHeight()))
        local maxScroll = contentHeight - scrollFrame:GetHeight()
        if maxScroll < 0 then maxScroll = 0 end
        if priorScroll > maxScroll then
            priorScroll = maxScroll
        end
        scrollFrame:SetVerticalScroll(priorScroll)
        if header then header:Show() end

        for i = 1, numPlayers do
            local name = players[i]

            -- Defensive: ensure the player exists in the active raid log.
            if addon.Raid:GetPlayerID(name, KRT_CurrentRaid) == 0 then
                addon.Raid:AddPlayer({
                    name     = name,
                    rank     = 0,
                    subgroup = 1,
                    class    = "UNKNOWN",
                    join     = Utils.getCurrentTime(),
                    leave    = nil,
                    count    = 0,
                }, KRT_CurrentRaid)
            end

            local row = EnsureRow(i, rowHeight)
            row:ClearAllPoints()
            local y = -(HEADER_HEIGHT + (i - 1) * rowHeight)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
            row._playerName = name

            if row._lastName ~= name then
                row.name:SetText(name)
                row._lastName = name
            end

            local class = addon.Raid:GetPlayerClass(name)
            if row._lastClass ~= class then
                local r, g, b = Utils.getClassColor(class)
                row.name:SetTextColor(r, g, b)
                row._lastClass = class
            end

            local cnt = addon.Raid:GetPlayerCount(name, KRT_CurrentRaid) or 0
            if row._lastCount ~= cnt then
                row.count:SetText(tostring(cnt))
                row._lastCount = cnt
            end
            row:Show()
        end

        for i = numPlayers + 1, #rows do
            if rows[i] then rows[i]:Hide() end
        end
    end

    -- ----- UI Window Management ----- --

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    -- Add a button to the master loot frame to open the loot counter UI.
    local function SetupMasterLootFrameHooks()
        local f = _G["KRTMasterLootFrame"]
        if f and not f.KRT_LootCounterBtn then
            local btn = CreateFrame("Button", nil, f, "KRTButtonTemplate")
            btn:SetSize(100, 24)
            btn:SetText(L.BtnLootCounter)
            btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -20)
            btn:SetScript("OnClick", function()
                module:Toggle()
            end)
            f.KRT_LootCounterBtn = btn

            f:HookScript("OnHide", function()
                module:Hide()
            end)
        end
    end
    hooksecurefunc(addon.Master, "OnLoad", SetupMasterLootFrameHooks)

    local function Request()
        -- Coalesced, event-driven refresh (safe even if frame is hidden/not yet created).
        module:RequestRefresh()
    end

    -- Refresh on roster updates (to keep list aligned).
    Utils.registerCallback("RaidRosterUpdate", Request)

    -- Refresh when counts actually change (MS loot award or manual +/-/reset).
    Utils.registerCallback("PlayerCountChanged", Request)

    -- New raid session: reset view.
    Utils.registerCallback("RaidCreate", Request)
end

-- =========== Reserves Module  =========== --
-- Manages item reserves, import, and display.
do
    addon.Reserves = addon.Reserves or {}
    local module = addon.Reserves
    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON

    -- ----- Internal state ----- --
    -- UI Elements
    local frameName
    local getFrame = Utils.makeFrameGetter("KRTReserveListFrame")
    local scrollFrame, scrollChild
    local reserveHeaders = {}
    local reserveItemRows, rowsByItemID = {}, {}

    -- State variables
    local localized = false
    local reservesData = {}
    local reservesByItemID = {}
    local reservesByItemPlayer = {}
    local playerItemsByName = {}
    local reservesDisplayList = {}
    local reservesDirty = false
    local importMode = nil -- 'multi' or 'plus'
    local pendingItemInfo = {}
    local pendingItemCount = 0
    local collapsedBossGroups = {}
    local grouped = {}

    -- ----- Private helpers ----- --

    local playerTextTemp = {}

    local function MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if not itemId then return nil end
        local pending = pendingItemInfo[itemId]
        if not pending then
            pending = {
                nameReady = false,
                iconReady = false,
                name = nil,
                link = nil,
                icon = nil,
            }
            pendingItemInfo[itemId] = pending
            pendingItemCount = pendingItemCount + 1
            addon:debug(Diag.D.LogReservesTrackPending:format(itemId, pendingItemCount))
        end
        if type(name) == "string" and name ~= "" then
            pending.name = name
        end
        if type(link) == "string" and link ~= "" then
            pending.link = link
        end
        if type(icon) == "string" and icon ~= "" then
            pending.icon = icon
        end
        if hasName then
            pending.nameReady = true
        end
        if hasIcon then
            pending.iconReady = true
        end
        return pending
    end

    local function GetPendingItemInfo(pending)
        if not pending then return nil end
        return pending.name, pending.link, pending.icon
    end

    local function CompletePendingItem(itemId)
        if not itemId or not pendingItemInfo[itemId] then return end
        pendingItemInfo[itemId] = nil
        if pendingItemCount > 0 then
            pendingItemCount = pendingItemCount - 1
        end
        addon:debug(Diag.D.LogReservesItemReady:format(itemId, pendingItemCount))
        if pendingItemCount == 0 then
            addon:debug(Diag.D.LogReservesPendingComplete)
            module:RequestRefresh()
        end
    end

    -- SoftRes exports class names like "Warrior", "Death Knight", etc.
    -- Normalize them to WoW class tokens (e.g. "WARRIOR", "DEATHKNIGHT") so we can use C.CLASS_COLORS.
    local function NormalizeClassToken(className)
        if not className then return nil end
        local token = tostring(className):upper()
        token = token:gsub("%s+", ""):gsub("%-", "")
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then return token end
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then return token end
        return nil
    end

    local function GetClassColorStr(className)
        local token = NormalizeClassToken(className) or "UNKNOWN"
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then
            return token, C.CLASS_COLORS[token]
        end
        local _, _, _, colorStr = addon.GetClassColor(token)
        return token, colorStr
    end

    local function ColorizeReserveName(itemId, playerName, className)
        if not playerName then return playerName end

        local cls = className
        if (not cls or cls == "") and itemId then
            local r = module:GetReserveEntryForItem(itemId, playerName)
            cls = r and r.class
        end
        if (not cls or cls == "") and addon.Raid and addon.Raid.GetPlayerClass then
            cls = addon.Raid:GetPlayerClass(playerName)
        end
        if not cls or cls == "" then return playerName end

        local _, colorStr = GetClassColorStr(cls)
        if colorStr and colorStr ~= "ffffffff" then
            return "|c" .. colorStr .. playerName .. "|r"
        end
        return playerName
    end

    local function AddReservePlayer(data, rOrName, countOverride)
        if not data.players then data.players = {} end
        if not data.playerCounts then data.playerCounts = {} end
        if not data.playerMeta then data.playerMeta = {} end

        local name, count, cls, plus
        if type(rOrName) == "table" then
            name = rOrName.player or "?"
            count = tonumber(rOrName.quantity) or 1
            cls = rOrName.class
            plus = tonumber(rOrName.plus) or 0
        else
            name = rOrName or "?"
            count = tonumber(countOverride) or 1
        end
        count = count or 1

        local existing = data.playerCounts[name]
        if existing then
            data.playerCounts[name] = existing + count
        else
            data.players[#data.players + 1] = name
            data.playerCounts[name] = count
        end

        local meta = data.playerMeta[name]
        if not meta then
            meta = { plus = 0, class = nil }
            data.playerMeta[name] = meta
        end
        if cls and cls ~= "" and (not meta.class or meta.class == "") then
            meta.class = cls
        end
        if plus and plus > (meta.plus or 0) then
            meta.plus = plus
        end
    end

    local function GetMetaForPlayer(metaByName, itemId, playerName)
        local meta = metaByName and metaByName[playerName]
        if meta and (meta.class or meta.plus) then return meta end

        -- Fallback: resolve from index (keeps compatibility even if meta isn't passed).
        if not meta then meta = { plus = 0, class = nil } end
        if itemId and playerName then
            local r = module:GetReserveEntryForItem(itemId, playerName)
            if r then
                if r.class and r.class ~= "" and (not meta.class or meta.class == "") then
                    meta.class = r.class
                end
                local p = tonumber(r.plus) or 0
                if p > (meta.plus or 0) then meta.plus = p end
            end
            if (not meta.class or meta.class == "") and addon.Raid and addon.Raid.GetPlayerClass then
                meta.class = addon.Raid:GetPlayerClass(playerName)
            end
        end
        return meta
    end

    -- Formats a single player token for display.
    -- useColor:
    --   true/nil -> UI rendering (class colors enabled)
    --   false    -> chat-safe rendering (no class color codes)
    local function FormatReservePlayerName(itemId, name, count, metaByName, useColor, showPlus, showMulti)
        local meta = GetMetaForPlayer(metaByName, itemId, name)
        local out
        if useColor == false then
            out = name
        else
            out = ColorizeReserveName(itemId, name, meta and meta.class)
        end

        if showMulti ~= false and module:IsMultiReserve() and count and count > 1 then
            out = out .. format(L.StrReserveCountSuffix, count)
        end

        if showPlus ~= false and module:IsPlusSystem() and itemId then
            local p = (meta and tonumber(meta.plus)) or module:GetPlusForItem(itemId, name) or 0
            if p and p > 0 then
                out = out .. format(" (P+%d)", p)
            end
        end

        return out
    end

    local function SortPlayersForDisplay(itemId, players, counts, metaByName)
        if not players then return end

        if module:IsPlusSystem() and itemId then
            table.sort(players, function(a, b)
                local am = GetMetaForPlayer(metaByName, itemId, a)
                local bm = GetMetaForPlayer(metaByName, itemId, b)
                local ap = (am and tonumber(am.plus)) or 0
                local bp = (bm and tonumber(bm.plus)) or 0
                if ap ~= bp then return ap > bp end
                return tostring(a) < tostring(b)
            end)
        elseif module:IsMultiReserve() and counts then
            -- Optional: show higher quantities first for readability.
            table.sort(players, function(a, b)
                local aq = counts[a] or 1
                local bq = counts[b] or 1
                if aq ~= bq then return aq > bq end
                return tostring(a) < tostring(b)
            end)
        end
    end

    local function BuildPlayerTokens(itemId, players, counts, metaByName, useColor, showPlus, showMulti)
        if not players then return {} end
        SortPlayersForDisplay(itemId, players, counts, metaByName)
        twipe(playerTextTemp)
        for i = 1, #players do
            local name = players[i]
            playerTextTemp[#playerTextTemp + 1] =
                FormatReservePlayerName(
                    itemId,
                    name,
                    counts and counts[name] or 1,
                    metaByName,
                    useColor,
                    showPlus,
                    showMulti
                )
        end
        return playerTextTemp
    end

    -- How many player tokens we show inline in the Reserve List row before truncating.
    -- Long lists are rendered in a dedicated tooltip on the players line.
    local RESERVE_ROW_MAX_PLAYERS_INLINE = 6

    local function FormatReservePlayerNameBase(itemId, name, metaByName)
        local meta = GetMetaForPlayer(metaByName, itemId, name)
        return ColorizeReserveName(itemId, name, meta and meta.class)
    end

    local function BuildPlayersTooltipLines(itemId, players, counts, metaByName, shownCount, hiddenCount)
        local lines = {}
        local total = players and #players or 0
        lines[#lines + 1] = format(L.StrReservesTooltipTotal, total)
        if hiddenCount and hiddenCount > 0 and shownCount and shownCount > 0 then
            lines[#lines + 1] = format(L.StrReservesTooltipShownHidden, shownCount, hiddenCount)
        end

        if not players or total == 0 then
            return lines
        end

        if module:IsPlusSystem() and itemId then
            -- Group by plus value (desc)
            local groups, keys = {}, {}
            for i = 1, #players do
                local name = players[i]
                local meta = GetMetaForPlayer(metaByName, itemId, name)
                local p = (meta and tonumber(meta.plus)) or 0
                if groups[p] == nil then
                    groups[p] = {}
                    keys[#keys + 1] = p
                end
                groups[p][#groups[p] + 1] = FormatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b) return a > b end)
            for i = 1, #keys do
                local p = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipPlus, p, tconcat(groups[p], ", "))
            end
        elseif module:IsMultiReserve() and counts then
            -- Group by quantity (desc)
            local groups, keys = {}, {}
            for i = 1, #players do
                local name = players[i]
                local q = counts[name] or 1
                if groups[q] == nil then
                    groups[q] = {}
                    keys[#keys + 1] = q
                end
                groups[q][#groups[q] + 1] = FormatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b) return a > b end)
            for i = 1, #keys do
                local q = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipQuantity, q, tconcat(groups[q], ", "))
            end
        else
            -- Fallback: just list names
            local names = {}
            for i = 1, #players do
                names[i] = FormatReservePlayerNameBase(itemId, players[i], metaByName)
            end
            lines[#lines + 1] = tconcat(names, ", ")
        end

        return lines
    end

    local function BuildPlayersText(itemId, players, counts, metaByName)
        if not players then return "", {}, "" end
        BuildPlayerTokens(itemId, players, counts, metaByName)
        local total = #playerTextTemp
        local shown = total
        if RESERVE_ROW_MAX_PLAYERS_INLINE and RESERVE_ROW_MAX_PLAYERS_INLINE > 0 then
            shown = math.min(total, RESERVE_ROW_MAX_PLAYERS_INLINE)
        end
        local hidden = total - shown
        local shortText = tconcat(playerTextTemp, ", ", 1, shown)
        if hidden > 0 then
            shortText = shortText .. format(L.StrReservesPlayersHiddenSuffix, hidden)
        end
        local fullText = tconcat(playerTextTemp, ", ")
        local tooltipLines = BuildPlayersTooltipLines(itemId, players, counts, metaByName, shown, hidden)
        return shortText, tooltipLines, fullText
    end

    local function GetReserveSource(source)
        if source and source ~= "" then
            return source
        end
        return L.StrUnknown
    end

    local function FormatReserveItemIdLabel(itemId)
        return format(L.StrReservesItemIdLabel, tostring(itemId or "?"))
    end

    local function FormatReserveDroppedBy(source)
        if not source or source == "" then return nil end
        return format(L.StrReservesTooltipDroppedBy, source)
    end

    local function FormatReserveItemFallback(itemId)
        return format(L.StrReservesItemFallback, tostring(itemId or "?"))
    end

    local function UpdateDisplayEntryForItem(itemId)
        if not itemId then return end
        reservesDirty = true

        local groupedBySource = {}
        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                if type(r) == "table" then
                    local source = GetReserveSource(r.source)
                    local bySource = groupedBySource[source]
                    if not bySource then
                        bySource = {}
                        groupedBySource[source] = bySource
                        if collapsedBossGroups[source] == nil then
                            collapsedBossGroups[source] = false
                        end
                    end
                    local data = bySource[itemId]
                    if not data then
                        data = {
                            itemId = itemId,
                            itemLink = r.itemLink,
                            itemName = r.itemName,
                            itemIcon = r.itemIcon,
                            source = source,
                            players = {},
                            playerCounts = {},
                            playerMeta = {},
                        }
                        bySource[itemId] = data
                    end
                    AddReservePlayer(data, r)
                end
            end
        end

        local existing = {}
        local remaining = {}
        for i = 1, #reservesDisplayList do
            local data = reservesDisplayList[i]
            if data and data.itemId == itemId then
                existing[#existing + 1] = data
            else
                remaining[#remaining + 1] = data
            end
        end

        local reused = 0
        for source, byQty in pairs(groupedBySource) do
            for _, data in pairs(byQty) do
                reused = reused + 1
                local target = existing[reused]
                if target then
                    target.itemId = itemId
                    target.itemLink = data.itemLink
                    target.itemName = data.itemName
                    target.itemIcon = data.itemIcon
                    target.source = source
                    target.players = target.players or {}
                    target.playerCounts = target.playerCounts or {}
                    target.playerMeta = target.playerMeta or {}
                    twipe(target.players)
                    twipe(target.playerCounts)
                    twipe(target.playerMeta)
                    for i = 1, #data.players do
                        local name = data.players[i]
                        target.players[i] = name
                        target.playerCounts[name] = data.playerCounts[name]
                    end
                    if data.playerMeta then
                        for n, m in pairs(data.playerMeta) do
                            local tm = target.playerMeta[n]
                            if not tm then
                                tm = {}; target.playerMeta[n] = tm
                            end
                            tm.plus = (m and tonumber(m.plus)) or 0
                            tm.class = m and m.class or tm.class
                        end
                    end
                    target.playersText, target.playersTooltipLines, target.playersTextFull = BuildPlayersText(itemId, target.players, target.playerCounts, target.playerMeta)
                    target.players = nil
                    target.playerCounts = nil
                    target.playerMeta = nil
                    remaining[#remaining + 1] = target
                else
                    data.playersText, data.playersTooltipLines, data.playersTextFull = BuildPlayersText(data.itemId, data.players, data.playerCounts, data.playerMeta)
                    data.players = nil
                    data.playerCounts = nil
                    data.playerMeta = nil
                    remaining[#remaining + 1] = data
                end
            end
        end

        twipe(reservesDisplayList)
        for i = 1, #remaining do
            reservesDisplayList[i] = remaining[i]
        end
    end

    local function RebuildIndex()
        twipe(reservesByItemID)
        twipe(reservesByItemPlayer)
        twipe(playerItemsByName)
        reservesDirty = true

        -- Build fast lookup indices
        for playerKey, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                local playerName = player.original or "?"
                local normalizedPlayer = Utils.normalizeLower(playerName, true) or playerKey
                playerItemsByName[normalizedPlayer] = playerItemsByName[normalizedPlayer] or {}

                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID then
                        r.player = r.player or playerName
                        local itemId = r.rawID

                        local list = reservesByItemID[itemId]
                        if not list then
                            list = {}
                            reservesByItemID[itemId] = list
                        end
                        list[#list + 1] = r

                        local byP = reservesByItemPlayer[itemId]
                        if not byP then
                            byP = {}
                            reservesByItemPlayer[itemId] = byP
                        end
                        byP[normalizedPlayer] = r
                        playerItemsByName[normalizedPlayer][itemId] = true
                    end
                end
            end
        end

        twipe(reservesDisplayList)
        twipe(grouped)
        for itemId, list in pairs(reservesByItemID) do
            if type(list) == "table" then
                for i = 1, #list do
                    local r = list[i]
                    if type(r) == "table" then
                        local source = GetReserveSource(r.source)

                        local bySource = grouped[source]
                        if not bySource then
                            bySource = {}
                            grouped[source] = bySource
                            if collapsedBossGroups[source] == nil then
                                collapsedBossGroups[source] = false
                            end
                        end

                        local data = bySource[itemId]
                        if not data then
                            data = {
                                itemId = itemId,
                                itemLink = r.itemLink,
                                itemName = r.itemName,
                                itemIcon = r.itemIcon,
                                source = source,
                                players = {},
                                playerCounts = {},
                                playerMeta = {},
                            }
                            bySource[itemId] = data
                        end

                        AddReservePlayer(data, r)
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, data in pairs(byItem) do
                data.playersText, data.playersTooltipLines, data.playersTextFull = BuildPlayersText(data.itemId, data.players, data.playerCounts, data.playerMeta)
                data.players = nil
                data.playerCounts = nil
                data.playerMeta = nil
                reservesDisplayList[#reservesDisplayList + 1] = data
            end
        end
    end

    local function SetupReserveRowTooltip(row)
        if not row then return end

        local function HideTooltip()
            GameTooltip:Hide()
        end

        local function ShowItemTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = row._itemLink
            if (not link or link == "") and row._itemId then
                link = "item:" .. tostring(row._itemId)
            end
            if link then
                GameTooltip:SetHyperlink(link)
            elseif row._tooltipTitle then
                GameTooltip:SetText(row._tooltipTitle, 1, 1, 1)
            end
            if row._tooltipSource then
                GameTooltip:AddLine(row._tooltipSource, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end

        local function ShowPlayersTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row._tooltipTitle or L.StrReservesTooltipTitle, 1, 1, 1)
            if row._tooltipSource then
                GameTooltip:AddLine(row._tooltipSource, 0.8, 0.8, 0.8)
            end
            local lines = row._playersTooltipLines
            if type(lines) == "table" then
                for i = 1, #lines do
                    GameTooltip:AddLine(lines[i], 0.9, 0.9, 0.9, true)
                end
            elseif row._playersTextFull and row._playersTextFull ~= "" then
                GameTooltip:AddLine(row._playersTextFull, 0.9, 0.9, 0.9, true)
            end
            GameTooltip:Show()
        end

        -- Icon = item tooltip (keeps the classic behavior)
        if row.iconBtn then
            row.iconBtn:SetScript("OnEnter", ShowItemTooltip)
            row.iconBtn:SetScript("OnLeave", HideTooltip)
        end

        -- Two tooltips (no XML changes):
        -- * Item tooltip on the TOP line (item name)
        -- * Full players list tooltip on the BOTTOM line (players)
        if row.textBlock then
            row.textBlock:EnableMouse(false)

            if not row._nameHotspot then
                local hs = CreateFrame("Button", nil, row.textBlock)
                hs:ClearAllPoints()
                hs:SetPoint("TOPLEFT", row.textBlock, "TOPLEFT", 0, 0)
                hs:SetHeight(16)
                hs:SetWidth(row.textBlock:GetWidth() > 0 and row.textBlock:GetWidth() or 200)
                hs:SetFrameLevel(row.textBlock:GetFrameLevel() + 2)
                hs:EnableMouse(true)
                hs:SetScript("OnEnter", ShowItemTooltip)
                hs:SetScript("OnLeave", HideTooltip)
                row._nameHotspot = hs
            end

            if not row._playersHotspot then
                local hs = CreateFrame("Button", nil, row.textBlock)
                hs:ClearAllPoints()
                hs:SetPoint("BOTTOMLEFT", row.textBlock, "BOTTOMLEFT", 0, 0)
                hs:SetHeight(16)
                hs:SetWidth(row.textBlock:GetWidth() > 0 and row.textBlock:GetWidth() or 200)
                hs:SetFrameLevel(row.textBlock:GetFrameLevel() + 2)
                hs:EnableMouse(true)
                hs:SetScript("OnEnter", ShowPlayersTooltip)
                hs:SetScript("OnLeave", HideTooltip)
                row._playersHotspot = hs
            end
        end
    end

    local function Clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    -- Limit the hover area (hotspots) to the actual rendered text width,
    -- instead of the full row width.
    local function UpdateReserveRowHotspots(row)
        if not row or not row.textBlock then return end
        local maxW = row.textBlock:GetWidth() or 0
        if maxW <= 0 then maxW = 200 end
        local pad = 8

        if row._nameHotspot and row.nameText then
            local t = row.nameText:GetText() or ""
            if t ~= "" then
                local w = row.nameText.GetStringWidth and row.nameText:GetStringWidth() or 0
                row._nameHotspot:SetWidth(Clamp(w + pad, 2, maxW))
                row._nameHotspot:EnableMouse(true)
            else
                row._nameHotspot:SetWidth(2)
                row._nameHotspot:EnableMouse(false)
            end
        end

        if row._playersHotspot and row.playerText then
            local t = row.playerText:GetText() or ""
            if t ~= "" then
                local w = row.playerText.GetStringWidth and row.playerText:GetStringWidth() or 0
                row._playersHotspot:SetWidth(Clamp(w + pad, 2, maxW))
                row._playersHotspot:EnableMouse(true)
            else
                row._playersHotspot:SetWidth(2)
                row._playersHotspot:EnableMouse(false)
            end
        end
    end

    local function ApplyReserveRowData(row, info, index)
        if not row or not info then return end
        row._itemId = info.itemId
        row._itemLink = info.itemLink
        row._itemName = info.itemName
        row._source = info.source
        row._tooltipTitle = info.itemLink or info.itemName or FormatReserveItemIdLabel(info.itemId)
        row._tooltipSource = FormatReserveDroppedBy(info.source)
        row._playersTooltipLines = info.playersTooltipLines
        row._playersTextFull = info.playersTextFull or info.playersText

        if row.background then
            row.background:SetVertexColor(index % 2 == 0 and 0.1 or 0, 0.1, 0.1, 0.3)
        end

        if row.iconTexture then
            local icon = info.itemIcon
            if not icon and info.itemId then
                local fetchedIcon = GetItemIcon(info.itemId)
                if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                    info.itemIcon = fetchedIcon
                    icon = fetchedIcon
                end
            end
            if type(icon) ~= "string" or icon == "" then
                icon = fallbackIcon
                info.itemIcon = icon
            end
            row.iconTexture:SetTexture(icon)
            row.iconTexture:Show()
        end

        if row.nameText then
            row.nameText:SetText(info.itemLink or info.itemName or FormatReserveItemFallback(info.itemId))
        end

        if row.playerText then
            row.playerText:SetText(info.playersText or "")
        end
        if row.quantityText then
            row.quantityText:Hide()
        end

        UpdateReserveRowHotspots(row)
    end

    local function ReserveHeaderOnClick(self)
        local source = self and self._source
        if not source then return end
        collapsedBossGroups[source] = not collapsedBossGroups[source]
        addon:debug(Diag.D.LogReservesToggleCollapse:format(source, tostring(collapsedBossGroups[source])))
        module:RequestRefresh()
    end

    -- ----- Public methods ----- --

    -- Local functions
    local LocalizeUIFrame
    local UpdateUIFrame
    local RenderReserveListUI

    -- ----- Saved Data Management ----- --

    function module:Save()
        RebuildIndex()
        addon:debug(Diag.D.LogReservesSaveEntries:format(addon.tLength(reservesData)))
        local saved = {}
        addon.tCopy(saved, reservesData)
        KRT_SavedReserves = saved
    end

    function module:Load()
        addon:debug(Diag.D.LogReservesLoadData:format(tostring(KRT_SavedReserves ~= nil)))
        twipe(reservesData)
        if KRT_SavedReserves then
            addon.tCopy(reservesData, KRT_SavedReserves)
        end

        -- Infer import mode from saved data when possible.
        -- If we detect any multi-item or quantity>1 entries, treat it as Multi-reserve.
        importMode = nil
        local inferred
        for _, p in pairs(reservesData) do
            if type(p) == "table" and type(p.reserves) == "table" then
                if #p.reserves > 1 then
                    inferred = "multi"
                    break
                end
                for i = 1, #p.reserves do
                    local r = p.reserves[i]
                    local qty = (type(r) == "table" and tonumber(r.quantity)) or 1
                    if qty and qty > 1 then
                        inferred = "multi"
                        break
                    end
                end
            end
            if inferred == "multi" then break end
        end
        if not inferred then
            local v = addon.options and addon.options.srImportMode
            inferred = (v == 1) and "plus" or "multi"
        end
        importMode = inferred

        RebuildIndex()
    end

    function module:ResetSaved()
        addon:debug(Diag.D.LogReservesResetSaved)
        KRT_SavedReserves = nil
        twipe(reservesData)
        RebuildIndex()
        self:Hide()
        self:RequestRefresh()
        Utils.triggerEvent("ReservesDataChanged", "clear")
        addon:info(L.StrReserveListCleared)
    end

    function module:HasData()
        return next(reservesData) ~= nil
    end

    function module:HasItemReserves(itemId)
        if not itemId then return false end
        local list = reservesByItemID[itemId]
        return type(list) == "table" and #list > 0
    end

    -- ----- UI Window Management ----- --

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function()
        addon:debug(Diag.D.LogReservesShowWindow)
        module:RequestRefresh()
    end)
    bindModuleToggleHide(module, uiController)

    function module:Hide()
        addon:debug(Diag.D.LogReservesHideWindow)
        return uiController:Hide()
    end

    function module:OnLoad(frame)
        addon:debug(Diag.D.LogReservesFrameLoaded)
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"]
        scrollChild = scrollFrame and scrollFrame.ScrollChild or _G["KRTReserveListFrameScrollChild"]

        local buttons = {
            CloseButton = "Hide",
            ClearButton = "ResetSaved",
            QueryButton = "QueryMissingItems",
        }
        for suff, method in pairs(buttons) do
            local btn = _G["KRTReserveListFrame" .. suff]
            if btn and self[method] then
                btn:SetScript("OnClick", function() self[method](self) end)
                addon:debug(Diag.D.LogReservesBindButton:format(suff, method))
            end
        end

        LocalizeUIFrame()

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:debug(Diag.D.LogReservesItemInfoReceived:format(itemId))
            local pending = pendingItemInfo[itemId]
            if not pending then return end

            local name, link, icon = GetPendingItemInfo(pending)
            local hasName = type(name) == "string" and name ~= ""
                and type(link) == "string" and link ~= ""
            local hasIcon = type(icon) == "string" and icon ~= ""

            if not hasName then
                local fetchedName, fetchedLink, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
                if type(fetchedName) == "string" and fetchedName ~= "" then
                    name = fetchedName
                end
                if type(fetchedLink) == "string" and fetchedLink ~= "" then
                    link = fetchedLink
                end
                if type(tex) == "string" and tex ~= "" then
                    icon = icon or tex
                end
            end

            if not hasIcon then
                local fetchedIcon = GetItemIcon(itemId)
                if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                    icon = fetchedIcon
                end
            end

            hasName = type(name) == "string" and name ~= ""
                and type(link) == "string" and link ~= ""
            hasIcon = type(icon) == "string" and icon ~= ""

            if hasName then
                addon:debug(Diag.D.LogReservesUpdateItemData:format(link))
                self:UpdateReserveItemData(itemId, name, link, icon)
            else
                addon:debug(Diag.D.LogReservesItemInfoMissing:format(itemId))
            end
            MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
            if hasName and hasIcon then
                addon:debug(Diag.D.LogSRItemInfoResolved:format(itemId, tostring(link)))
                CompletePendingItem(itemId)
            else
                addon:debug(Diag.D.LogReservesItemInfoPending:format(itemId))
                self:QueryItemInfo(itemId)
            end
        end)
    end

    -- ----- Localization and UI Update ----- --

    function LocalizeUIFrame()
        if localized then
            addon:debug(Diag.D.LogReservesUIAlreadyLocalized)
            return
        end
        if frameName then
            Utils.setFrameTitle(frameName, L.StrRaidReserves)
            addon:debug(Diag.D.LogReservesUILocalized:format(L.StrRaidReserves))
        end
        local clearButton = frameName and _G[frameName .. "ClearButton"]
        if clearButton then
            clearButton:SetText(L.BtnClearReserves)
        end
        local queryButton = frameName and _G[frameName .. "QueryButton"]
        if queryButton then
            queryButton:SetText(L.BtnQueryItem)
        end
        local closeButton = frameName and _G[frameName .. "CloseButton"]
        if closeButton then
            closeButton:SetText(L.BtnClose)
        end
        localized = true
    end

    -- Update UI Frame:
    function UpdateUIFrame()
        LocalizeUIFrame()
        local hasData = module:HasData()
        local clearButton = _G[frameName .. "ClearButton"]
        if clearButton then
            if hasData then
                clearButton:Show()
                Utils.enableDisable(clearButton, true)
            else
                clearButton:Hide()
            end
        end
        local queryButton = _G[frameName .. "QueryButton"]
        if queryButton then
            Utils.enableDisable(queryButton, hasData)
        end
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
        local frame = getFrame()
        if frame and RenderReserveListUI then
            RenderReserveListUI()
        end
    end

    bindModuleRequestRefresh(module, getFrame)

    -- ----- Reserve Data Handling ----- --

    function module:GetReserve(playerName)
        if type(playerName) ~= "string" then return nil end
        local player = Utils.normalizeLower(playerName)
        local reserve = reservesData[player]

        -- Log when the function is called and show the reserve for the player
        if reserve then
            addon:debug(Diag.D.LogReservesPlayerFound:format(playerName, tostring(reserve)))
        else
            addon:debug(Diag.D.LogReservesPlayerNotFound:format(playerName))
        end

        return reserve
    end

    -- Get all reserves:
    function module:GetAllReserves()
        addon:debug(Diag.D.LogReservesFetchAll:format(addon.tLength(reservesData)))
        return reservesData
    end

    -- Parse imported text (SoftRes CSV)
    -- mode: "multi" (multi-reserve enabled; Plus ignored) or "plus" (priority; requires 1 item per player)
    function module:GetImportMode()
        if importMode == nil then
            local v = addon.options and addon.options.srImportMode
            importMode = (v == 1) and "plus" or "multi"
        end
        return importMode
    end

    function module:IsPlusSystem()
        return self:GetImportMode() == "plus"
    end

    function module:IsMultiReserve()
        return self:GetImportMode() == "multi"
    end

    -- Strategy objects to keep Plus/Multi behaviors isolated.
    local importStrategies = {}

    local function cleanCSVField(field)
        if not field then return nil end
        return Utils.trimText(field:gsub('^"(.-)"$', '%1'), true)
    end

    local function splitCSVLine(line)
        local out, field = {}, ""
        local inQuotes = false
        local i = 1
        while i <= #line do
            local ch = line:sub(i, i)
            if ch == '"' then
                local nextCh = line:sub(i + 1, i + 1)
                if inQuotes and nextCh == '"' then
                    field = field .. '"'
                    i = i + 1
                else
                    inQuotes = not inQuotes
                end
            elseif ch == ',' and not inQuotes then
                out[#out + 1] = field
                field = ""
            else
                field = field .. ch
            end
            i = i + 1
        end
        out[#out + 1] = field
        return out
    end

    local function buildHeaderMap(fields)
        local map = {}
        for i = 1, #fields do
            local key = cleanCSVField(fields[i])
            if key and key ~= "" then
                map[Utils.normalizeLower(key)] = i
            end
        end
        -- Consider it a header only if it includes key columns.
        if map["itemid"] and map["name"] then
            return map, true
        end
        return map, false
    end

    local function getField(fields, headerMap, key, fallbackIndex)
        if headerMap and headerMap[key] then
            return fields[headerMap[key]]
        end
        return fields[fallbackIndex]
    end

    local function parseCSVRows(csv)
        local rows = {}
        local headerMap = nil
        local firstLine = true

        for line in csv:gmatch("[^\n]+") do
            line = line:gsub("\r$", "")
            if firstLine then
                firstLine = false
                local maybeHeader = splitCSVLine(line)
                local map, isHeader = buildHeaderMap(maybeHeader)
                if isHeader then
                    headerMap = map
                else
                    -- No header detected: treat first line as data
                    local fields     = maybeHeader

                    local itemIdStr  = cleanCSVField(getField(fields, headerMap, "itemid", 2))
                    local source     = cleanCSVField(getField(fields, headerMap, "from", 3))
                    local playerName = cleanCSVField(getField(fields, headerMap, "name", 4))
                    local class      = cleanCSVField(getField(fields, headerMap, "class", 5))
                    local spec       = cleanCSVField(getField(fields, headerMap, "spec", 6))
                    local note       = cleanCSVField(getField(fields, headerMap, "note", 7))
                    local plus       = cleanCSVField(getField(fields, headerMap, "plus", 8))

                    local itemId     = tonumber(itemIdStr)
                    local playerKey  = Utils.normalizeLower(playerName, true)
                    if itemId and playerKey then
                        rows[#rows + 1] = {
                            itemId = itemId,
                            player = playerName,
                            playerKey = playerKey,
                            source = source ~= "" and source or nil,
                            class = class ~= "" and class or nil,
                            spec = spec ~= "" and spec or nil,
                            note = note ~= "" and note or nil,
                            plus = tonumber(plus) or 0,
                        }
                    end
                end
            else
                local fields     = splitCSVLine(line)

                local itemIdStr  = cleanCSVField(getField(fields, headerMap, "itemid", 2))
                local source     = cleanCSVField(getField(fields, headerMap, "from", 3))
                local playerName = cleanCSVField(getField(fields, headerMap, "name", 4))
                local class      = cleanCSVField(getField(fields, headerMap, "class", 5))
                local spec       = cleanCSVField(getField(fields, headerMap, "spec", 6))
                local note       = cleanCSVField(getField(fields, headerMap, "note", 7))
                local plus       = cleanCSVField(getField(fields, headerMap, "plus", 8))

                local itemId     = tonumber(itemIdStr)
                local playerKey  = Utils.normalizeLower(playerName, true)

                if itemId and playerKey then
                    rows[#rows + 1] = {
                        itemId = itemId,
                        player = playerName,
                        playerKey = playerKey,
                        source = source ~= "" and source or nil,
                        class = class ~= "" and class or nil,
                        spec = spec ~= "" and spec or nil,
                        note = note ~= "" and note or nil,
                        plus = tonumber(plus) or 0,
                    }
                else
                    addon:debug(Diag.D.LogSRParseSkippedLine:format(tostring(line)))
                end
            end
        end

        return rows
    end
    local function validatePlusRows(rows)
        -- Plus System requires exactly 1 reserve entry per player (SoftRes set to 1 SR per player).
        -- If a player appears more than once (even for the same item), it means a multi-reserve CSV was pasted.
        local seen = {}
        for i = 1, #rows do
            local row = rows[i]
            local rec = seen[row.playerKey]
            if not rec then
                seen[row.playerKey] = { itemId = row.itemId, player = row.player, count = 1 }
            else
                rec.count = (rec.count or 1) + 1
                if rec.itemId ~= row.itemId then
                    return false, "CSV_WRONG_FOR_PLUS", {
                        player = row.player,
                        reason = "multi_item",
                        first = rec.itemId,
                        second = row.itemId,
                        count = rec.count,
                    }
                end
                return false, "CSV_WRONG_FOR_PLUS", {
                    player = row.player,
                    reason = "duplicate",
                    itemId = row.itemId,
                    count = rec.count,
                }
            end
        end
        return true
    end

    local function aggregateRows(rows, allowMulti)
        local newReservesData = {}
        local byItemPerPlayer = {}

        for i = 1, #rows do
            local row = rows[i]
            local pKey = row.playerKey

            local container = newReservesData[pKey]
            if not container then
                container = { original = row.player, reserves = {} }
                newReservesData[pKey] = container
                byItemPerPlayer[pKey] = {}
            end

            local idx = byItemPerPlayer[pKey]
            local entry = idx[row.itemId]
            if entry then
                if allowMulti then
                    entry.quantity = (tonumber(entry.quantity) or 1) + 1
                else
                    entry.quantity = 1
                end
                local p = tonumber(row.plus) or 0
                if p > (tonumber(entry.plus) or 0) then
                    entry.plus = p
                end
            else
                entry = {
                    rawID = row.itemId,
                    itemLink = nil,
                    itemName = nil,
                    itemIcon = nil,
                    quantity = 1,
                    class = row.class,
                    spec = row.spec,
                    note = row.note,
                    plus = tonumber(row.plus) or 0,
                    source = row.source,
                    player = row.player,
                }
                idx[row.itemId] = entry
                container.reserves[#container.reserves + 1] = entry
            end
        end

        return newReservesData
    end

    importStrategies.multi = {
        id = "multi",
        Validate = function(rows) return true end,
        Aggregate = function(rows) return aggregateRows(rows, true) end,
    }

    importStrategies.plus = {
        id = "plus",
        Validate = validatePlusRows,
        Aggregate = function(rows) return aggregateRows(rows, false) end,
    }

    function module:GetImportStrategy(mode)
        mode = (mode == "plus" or mode == "multi") and mode or self:GetImportMode()
        return importStrategies[mode] or importStrategies.multi
    end

    function module:ParseCSV(csv, mode)
        if type(csv) ~= "string" or not csv:match("%S") then
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return false, 0, "EMPTY"
        end

        mode = (mode == "plus" or mode == "multi") and mode or self:GetImportMode()
        local strat = self:GetImportStrategy(mode)

        addon:debug(Diag.D.LogReservesParseStart)

        -- Transactional parse: parse → validate → aggregate → commit.
        local rows = parseCSVRows(csv)
        if not rows or #rows == 0 then
            addon:warn(L.WarnNoValidRows)
            return false, 0, "NO_ROWS"
        end

        local ok, errCode, errData = strat.Validate(rows)
        if not ok then
            addon:debug(Diag.D.LogReservesImportWrongModePlus
                and Diag.D.LogReservesImportWrongModePlus:format(tostring(errData and errData.player))
                or ("Wrong CSV for Plus System: " .. tostring(errData and errData.player)))
            return false, 0, errCode or "CSV_INVALID", errData
        end

        local newReservesData = strat.Aggregate(rows)

        -- Commit
        reservesData = newReservesData
        importMode = mode
        self:Save()

        local nPlayers = addon.tLength(reservesData)
        addon:debug(Diag.D.LogReservesParseComplete:format(nPlayers))
        addon:info(format(L.SuccessReservesParsed, tostring(nPlayers)))
        self:RequestRefresh()
        Utils.triggerEvent("ReservesDataChanged", "import", nPlayers, mode)
        return true, nPlayers
    end

    -- ----- Item Info Querying ----- --
    function module:QueryItemInfo(itemId)
        if not itemId then return end
        addon:debug(Diag.D.LogReservesQueryItemInfo:format(itemId))
        local pending = pendingItemInfo[itemId]
        local name, link, icon = GetPendingItemInfo(pending)
        local hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        local hasIcon = type(icon) == "string" and icon ~= ""

        if not hasName then
            local fetchedName, fetchedLink, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
            if type(fetchedName) == "string" and fetchedName ~= "" then
                name = fetchedName
            end
            if type(fetchedLink) == "string" and fetchedLink ~= "" then
                link = fetchedLink
            end
            if type(tex) == "string" and tex ~= "" then
                icon = icon or tex
            end
        end

        if not hasIcon then
            local fetchedIcon = GetItemIcon(itemId)
            if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                icon = fetchedIcon
            end
        end

        hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        hasIcon = type(icon) == "string" and icon ~= ""
        if hasName then
            self:UpdateReserveItemData(itemId, name, link, icon)
        end
        MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if hasName and hasIcon then
            addon:debug(Diag.D.LogReservesItemInfoReady:format(itemId, name))
            CompletePendingItem(itemId)
            return true
        end

        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Hide()
        addon:debug(Diag.D.LogReservesItemInfoPendingQuery:format(itemId))
        return false
    end

    -- Query all missing items for reserves
    function module:QueryMissingItems(silent)
        local seen = {}
        local count = 0
        local updated = false
        addon:debug(Diag.D.LogReservesQueryMissingItems)
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for _, r in ipairs(player.reserves) do
                    local itemId = r.rawID
                    if itemId and not seen[itemId] and (not r.itemLink or not r.itemIcon) then
                        seen[itemId] = true
                        if not self:QueryItemInfo(itemId) then
                            count = count + 1
                        else
                            updated = true
                        end
                    end
                end
            end
        end
        if updated then
            self:RequestRefresh()
        end
        if not silent then
            if count > 0 then
                addon:info(L.MsgReserveItemsRequested, count)
            else
                addon:info(L.MsgReserveItemsReady)
            end
        end
        addon:debug(Diag.D.LogReservesMissingItems:format(count))
        addon:debug(Diag.D.LogSRQueryMissingItems:format(tostring(updated), count))
    end

    -- Update reserve item data
    function module:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        if not itemId then return end
        local icon = itemIcon
        if (type(icon) ~= "string" or icon == "") and itemName then
            icon = fallbackIcon
        end
        reservesDirty = true

        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                if type(r) == "table" and r.rawID == itemId then
                    r.itemName = itemName
                    r.itemLink = itemLink
                    r.itemIcon = icon
                end
            end
        else
            -- Fallback: scan all players (should be rare if index is up to date)
            for _, player in pairs(reservesData) do
                if type(player) == "table" and type(player.reserves) == "table" then
                    for i = 1, #player.reserves do
                        local r = player.reserves[i]
                        if type(r) == "table" and r.rawID == itemId then
                            r.itemName = itemName
                            r.itemLink = itemLink
                            r.itemIcon = icon
                        end
                    end
                end
            end
        end

        UpdateDisplayEntryForItem(itemId)

        local rows = rowsByItemID[itemId]
        if not rows then return end
        for i = 1, #rows do
            local row = rows[i]
            row._itemId = itemId
            row._itemLink = itemLink
            row._itemName = itemName
            row._tooltipTitle = itemLink or itemName or FormatReserveItemIdLabel(itemId)
            row._tooltipSource = FormatReserveDroppedBy(row._source)
            if row.iconTexture then
                local resolvedIcon = icon
                if type(resolvedIcon) ~= "string" or resolvedIcon == "" then
                    resolvedIcon = fallbackIcon
                end
                row.iconTexture:SetTexture(resolvedIcon)
                row.iconTexture:Show()
            end
            if row.nameText then
                row.nameText:SetText(itemLink or itemName or FormatReserveItemFallback(itemId))
            end
        end
    end

    -- Get reserve count for a specific item for a player
    function module:GetReserveCountForItem(itemId, playerName)
        local r = self:GetReserveEntryForItem(itemId, playerName)
        if not r then return 0 end
        return tonumber(r.quantity) or 1
    end

    -- Gets the reserve entry table for a specific item for a player (or nil).
    function module:GetReserveEntryForItem(itemId, playerName)
        if not itemId or not playerName then return nil end
        local playerKey = Utils.normalizeLower(playerName, true)
        if not playerKey then return nil end

        local byP = reservesByItemPlayer[itemId]
        if type(byP) == "table" then
            local r = byP[playerKey]
            if r then return r end
        end

        -- Fallback (should be rare if indices are up to date)
        local entry = reservesData[playerKey]
        if not entry then return nil end
        for _, r in ipairs(entry.reserves or {}) do
            if r and r.rawID == itemId then
                return r
            end
        end
        return nil
    end

    -- Gets the "Plus" value for a reserved item for a player (0 if missing).
    function module:GetPlusForItem(itemId, playerName)
        -- Plus values are meaningful only in Plus System mode.
        if self:GetImportMode() ~= "plus" then return 0 end
        local r = self:GetReserveEntryForItem(itemId, playerName)
        return (r and tonumber(r.plus)) or 0
    end

    -- Returns true if the item has any multi-reserve entry (quantity > 1).
    -- When true, SR "Plus priority" should be disabled for this item.
    function module:HasMultiReserveForItem(itemId)
        if self:GetImportMode() ~= "multi" then return false end
        if not itemId then return false end
        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                local qty = (type(r) == "table" and tonumber(r.quantity)) or 1
                if (qty or 1) > 1 then
                    return true
                end
            end
            return false
        end

        -- Fallback: scan all players (should be rare if index is up to date)
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID == itemId then
                        local qty = tonumber(r.quantity) or 1
                        if qty > 1 then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    -- ----- UI Display ----- --

    function RenderReserveListUI()
        local frame = getFrame()
        if not frame or not scrollChild then return end
        module.frame = frame

        -- Hide and clear old rows
        for i = 1, #reserveItemRows do
            reserveItemRows[i]:Hide()
        end
        twipe(reserveItemRows)
        twipe(rowsByItemID)

        -- Hide and clear old headers
        for i = 1, #reserveHeaders do
            reserveHeaders[i]:Hide()
        end
        twipe(reserveHeaders)

        if reservesDirty then
            table.sort(reservesDisplayList, function(a, b)
                if a.source ~= b.source then return a.source < b.source end
                if a.itemId ~= b.itemId then return a.itemId < b.itemId end
                return false
            end)
            reservesDirty = false
        end

        local rowHeight, yOffset = C.RESERVES_ROW_HEIGHT, 0
        local seenSources = {}
        local rowIndex = 0
        local headerIndex = 0

        for i = 1, #reservesDisplayList do
            local entry = reservesDisplayList[i]
            local source = entry.source

            if not seenSources[source] then
                seenSources[source] = true
                headerIndex = headerIndex + 1
                local header = module:CreateReserveHeader(scrollChild, source, yOffset, headerIndex)
                reserveHeaders[#reserveHeaders + 1] = header
                yOffset = yOffset + C.RESERVE_HEADER_HEIGHT
            end

            if not collapsedBossGroups[source] then
                rowIndex = rowIndex + 1
                local row = module:CreateReserveRow(scrollChild, entry, yOffset, rowIndex)
                reserveItemRows[#reserveItemRows + 1] = row
                yOffset = yOffset + rowHeight
            end
        end

        scrollChild:SetHeight(yOffset)
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
    end

    function module:CreateReserveHeader(parent, source, yOffset, index)
        local headerName = frameName .. "ReserveHeader" .. index
        local header = _G[headerName] or CreateFrame("Button", headerName, parent, "KRTReserveHeaderTemplate")
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        header._source = source
        if not header._initialized then
            header.label = _G[headerName .. "Label"]
            header:SetScript("OnClick", ReserveHeaderOnClick)
            header._initialized = true
        end
        if header.label then
            local prefix = collapsedBossGroups[source] and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or
                "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
            header.label:SetText(prefix .. source)
        end
        header:Show()
        return header
    end

    local function SetupReserveIcon(row)
        if not row or not row.iconTexture or not row.iconBtn then return end
        row.iconTexture:ClearAllPoints()
        row.iconTexture:SetPoint("TOPLEFT", row.iconBtn, "TOPLEFT", 2, -2)
        row.iconTexture:SetPoint("BOTTOMRIGHT", row.iconBtn, "BOTTOMRIGHT", -2, 2)
        row.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTexture:SetDrawLayer("OVERLAY")
    end

    -- Create a new row for displaying a reserve
    function module:CreateReserveRow(parent, info, yOffset, index)
        local rowName = frameName .. "ReserveRow" .. index
        local row = _G[rowName] or CreateFrame("Frame", rowName, parent, "KRTReserveRowTemplate")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        row._rawID = info.itemId
        if not row._initialized then
            row.background = _G[rowName .. "Background"]
            row.iconBtn = _G[rowName .. "IconBtn"]
            row.iconTexture = _G[rowName .. "IconBtnIconTexture"]
            row.textBlock = _G[rowName .. "TextBlock"]
            SetupReserveIcon(row)
            if row.textBlock and row.iconBtn then
                row.textBlock:SetFrameLevel(row.iconBtn:GetFrameLevel() + 1)
            end
            row.nameText = _G[rowName .. "TextBlockName"]
            row.sourceText = _G[rowName .. "TextBlockSource"]
            row.playerText = _G[rowName .. "TextBlockPlayers"]
            row.quantityText = _G[rowName .. "Quantity"]
            SetupReserveRowTooltip(row)
            if row.sourceText then
                row.sourceText:SetText("")
                row.sourceText:Hide()
            end
            row._initialized = true
        end
        ApplyReserveRowData(row, info, index)
        row:Show()
        rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
        tinsert(rowsByItemID[info.itemId], row)

        return row
    end

    -- ----- SR Announcement Formatting ----- --

    -- Returns a list of formatted player tokens for an item.
    -- useColor:
    --   true/nil -> UI rendering (class colors)
    --   false    -> chat-safe rendering (no class color codes)
    -- showPlus:
    --   true/nil -> include "(P+N)" when Plus System is enabled
    --   false    -> hide Plus suffixes from formatted player tokens
    -- showMulti:
    --   true/nil -> include "(xN)" when Multi-reserve is enabled
    --   false    -> hide multi-reserve count suffixes from player tokens
    function module:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        if not itemId then return {} end
        local list = reservesByItemID[itemId]
        if type(list) ~= "table" then return {} end

        -- Aggregate per player so we can apply sorting and reuse meta (class/plus).
        local data = { players = {}, playerCounts = {}, playerMeta = {} }
        for i = 1, #list do
            local r = list[i]
            if type(r) == "table" then
                AddReservePlayer(data, r)
            end
        end

        local tokens = BuildPlayerTokens(
            itemId,
            data.players,
            data.playerCounts,
            data.playerMeta,
            useColor,
            showPlus,
            showMulti
        )
        local out = {}
        for i = 1, #tokens do
            out[i] = tokens[i]
        end
        return out
    end

    -- Returns the formatted player list for an item (comma-separated).
    -- useColor, showPlus, and showMulti follow the same rules as GetPlayersForItem.
    function module:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti)
        addon:debug(Diag.D.LogReservesFormatPlayers:format(itemId))
        local list = self:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        -- Log the list of players found for the item
        addon:debug(Diag.D.LogReservesPlayersList:format(itemId, tconcat(list, ", ")))
        return #list > 0 and tconcat(list, ", ") or ""
    end
end

-- =========== Reserve Import Window Module  =========== --
-- Handles the CSV import dialog for Reserves.
do
    addon.ReserveImport = addon.ReserveImport or {}
    local module = addon.ReserveImport
    local getFrame = makeModuleFrameGetter(module, "KRTImportWindow")
    local localized = false
    -- Import mode slider: 0 = Multi-reserve, 1 = Plus System (priority)
    local MODE_MULTI, MODE_PLUS = 0, 1

    local function GetImportModeString()
        local v = addon.options and addon.options.srImportMode
        if v == MODE_PLUS then return "plus" end
        return "multi"
    end

    local function GetModeSlider()
        return _G["KRTImportWindowModeSlider"] or _G["KRTImportModeSlider"]
    end

    function module:SetImportMode(modeValue, suppressSlider)
        addon.options = addon.options or KRT_Options or {}
        addon.options.srImportMode = (modeValue == MODE_PLUS) and MODE_PLUS or MODE_MULTI
        if not suppressSlider then
            local s = GetModeSlider()
            if s and s.SetValue then
                s:SetValue(addon.options.srImportMode)
            end
        end
    end

    function module:OnModeSliderLoad(slider)
        if not slider then return end
        slider:SetMinMaxValues(MODE_MULTI, MODE_PLUS)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local low = _G[slider:GetName() .. "Low"]
        local high = _G[slider:GetName() .. "High"]
        local text = _G[slider:GetName() .. "Text"]
        if low then low:SetText(L.StrImportModeMulti or "Multi-reserve") end
        if high then high:SetText(L.StrImportModePlus or "Plus System") end
        if text then text:SetText(L.StrImportModeLabel or "") end

        addon.options = addon.options or KRT_Options or {}
        local v = addon.options.srImportMode
        if v ~= MODE_MULTI and v ~= MODE_PLUS then v = MODE_MULTI end
        slider:SetValue(v)
    end

    function module:OnModeSliderChanged(slider, value)
        if not slider then return end
        local v = tonumber(value) or MODE_MULTI
        if v >= 0.5 then v = MODE_PLUS else v = MODE_MULTI end
        module:SetImportMode(v, true)
    end

    -- Popup shown when Plus System is selected but CSV contains multi-item reserves per player.
    local function EnsureWrongCSVPopup()
        if StaticPopupDialogs and StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] then return end
        if not StaticPopupDialogs then return end

        StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] = {
            text = L.ErrCSVWrongForPlus
                or "Wrong CSV format for Plus System.\nThis CSV contains players with multiple reserved items.\nSwitch to Multi-reserve or check your SoftRes settings.",
            button1 = L.BtnSwitchToMulti or "Switch to Multi-reserve",
            button2 = L.BtnCancel or (L.BtnClose or "Cancel"),
            OnShow = function(self, data)
                if not self or not self.text then return end
                if type(data) == "table" and data.player then
                    local msg = L.ErrCSVWrongForPlusWithPlayer
                        or "Wrong CSV format for Plus System.\nPlayer '%s' has multiple reserved items.\nSwitch to Multi-reserve or check your SoftRes settings."
                    self.text:SetText(msg:format(tostring(data.player)))
                end
            end,
            OnAccept = function(self, data)
                if type(data) ~= "table" or type(data.csv) ~= "string" then return end
                module:SetImportMode(MODE_MULTI)

                -- Re-run import in multi mode (Plus ignored by definition).
                local ok, nPlayers = addon.Reserves:ParseCSV(data.csv, "multi")
                if ok then
                    module:Hide()
                    local rf = (addon.Reserves and addon.Reserves.frame) or _G["KRTReserveListFrame"]
                    if not (rf and rf.IsShown and rf:IsShown()) then
                        addon.Reserves:Toggle()
                    else
                        addon.Reserves:RequestRefresh()
                    end
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    local function LocalizeUIFrame()
        if localized then return end
        local frame = getFrame()
        if not frame then return end

        local confirmButton = _G["KRTImportConfirmButton"]
        if confirmButton then confirmButton:SetText(L.BtnImport) end
        local cancelButton = _G["KRTImportCancelButton"]
        if cancelButton then cancelButton:SetText(L.BtnClose) end

        Utils.setFrameTitle(frame, L.StrImportReservesTitle)
        local hint = _G["KRTImportWindowHint"]
        if hint then hint:SetText(L.StrImportReservesHint) end

        localized = true
    end

    function module:OnLoad(frame)
        module.frame = frame
        if frame then
            -- Drag registration kept in Lua (avoid template logic in XML).
            Utils.enableDrag(frame)

            frame:HookScript("OnShow", function() module:RequestRefresh() end)
        end
        module:RequestRefresh()
    end

    function module:Refresh()
        LocalizeUIFrame()
        local slider = GetModeSlider()
        if slider and slider.SetValue then
            addon.options = addon.options or KRT_Options or {}
            local v = addon.options.srImportMode
            if v ~= MODE_MULTI and v ~= MODE_PLUS then v = MODE_MULTI end
            slider:SetValue(v)
        end
        local status = _G["KRTImportWindowStatus"]
        if status and (status:GetText() == nil or status:GetText() == "") then
            status:SetText("")
        end
    end

    bindModuleRequestRefresh(module, getFrame)

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    function module:Toggle()
        local frame = getFrame()
        if not frame then
            addon:error(Diag.E.LogReservesImportWindowMissing)
            return
        end

        if frame:IsShown() then
            uiController:Hide()
            return
        end

        uiController:Show()

        Utils.resetEditBox(_G["KRTImportEditBox"])
        local editBox = _G["KRTImportEditBox"]
        if editBox then
            editBox:SetFocus()
            editBox:HighlightText()
        end
        local status = _G["KRTImportWindowStatus"]
        if status then status:SetText("") end
    end

    function module:ImportFromEditBox()
        local editBox = _G["KRTImportEditBox"]
        local status = _G["KRTImportWindowStatus"]
        if status then status:SetText("") end
        if not editBox then return false, 0 end

        local csv = editBox:GetText()
        if type(csv) ~= "string" or not csv:match("%S") then
            if status then
                status:SetText(L.ErrImportReservesEmpty or "Import failed: empty or invalid data.")
                status:SetTextColor(1, 0.2, 0.2)
            end
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return false, 0
        end

        addon:debug(Diag.D.LogSRImportRequested:format(#csv))
        EnsureWrongCSVPopup()
        local mode = GetImportModeString()
        local ok, nPlayers, errCode, errData = addon.Reserves:ParseCSV(csv, mode)
        if (not ok) and errCode == "CSV_WRONG_FOR_PLUS" then
            if status then
                status:SetText(L.ErrCSVWrongForPlusShort or "Wrong CSV format for Plus System.")
                status:SetTextColor(1, 0.2, 0.2)
            end
            local popupData = { csv = csv }
            if type(errData) == "table" then
                for k, v in pairs(errData) do
                    popupData[k] = v
                end
            end
            StaticPopup_Show("KRT_WRONG_CSV_FOR_PLUS", nil, nil, popupData)
            return false, 0
        end
        if ok then
            if status then
                status:SetText(string.format(L.SuccessReservesParsed, tostring(nPlayers)))
                status:SetTextColor(0.2, 1, 0.2)
            end
            module:Hide()
            local rf = (addon.Reserves and addon.Reserves.frame) or _G["KRTReserveListFrame"]
            if not (rf and rf.IsShown and rf:IsShown()) then
                addon.Reserves:Toggle()
            else
                addon.Reserves:RequestRefresh()
            end
            return true, nPlayers
        else
            if status then
                status:SetText(L.ErrImportReservesEmpty or "Import failed: empty or invalid data.")
                status:SetTextColor(1, 0.2, 0.2)
            end
            return false, 0
        end
    end
end

-- =========== Configuration Frame Module  =========== --
do
    addon.Config = addon.Config or {}
    local module = addon.Config
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTConfig")
    -- ----- Internal state ----- --
    local localized = false
    local configDirty = false

    -- Frame update
    local UpdateUIFrame
    local MIN_COUNTDOWN = 5
    local MAX_COUNTDOWN = 60

    -- ----- Private helpers ----- --
    local LocalizeUIFrame

    -- ----- Public methods ----- --

    -- Default options for the addon.
    local defaultOptions = {
        sortAscending               = false,
        useRaidWarning              = true,
        announceOnWin               = true,
        announceOnHold              = true,
        announceOnBank              = false,
        announceOnDisenchant        = false,
        lootWhispers                = false,
        screenReminder              = true,
        ignoreStacks                = false,
        showTooltips                = true,
        showLootCounterDuringMSRoll = false,
        minimapButton               = true,
        countdownSimpleRaidMsg      = false,
        countdownDuration           = 5,
        countdownRollsBlock         = true,
        srImportMode                = 0,
    }

    -- Creates a fresh options table seeded with defaults.
    -- Returns a new table populated with the values in defaultOptions. This helper
    -- avoids duplication between LoadDefaultOptions and LoadOptions when
    -- constructing the base options table.
    local function NewOptions()
        local options = {}
        addon.tCopy(options, defaultOptions)
        return options
    end

    -- Loads the default options into the settings table.
    local function LoadDefaultOptions()
        local options = NewOptions()
        KRT_Options = options
        addon.options = options
        configDirty = true
        module:RequestRefresh()
        addon:info(L.MsgDefaultsRestored)
    end

    -- Loads addon options from saved variables, filling in defaults.
    local function LoadOptions()
        local options = NewOptions()
        if KRT_Options then
            addon.tCopy(options, KRT_Options)
        end
        KRT_Options = options
        addon.options = options

        Utils.applyDebugSetting(addon.options.debug)
        configDirty = true
        module:RequestRefresh()

        if KRT_MINIMAP_GUI then
            addon.Minimap:SetPos(addon.options.minimapPos or 325)
            if addon.options.minimapButton then
                Utils.setShown(KRT_MINIMAP_GUI, true)
            else
                Utils.setShown(KRT_MINIMAP_GUI, false)
            end
        end
    end
    addon.LoadOptions = LoadOptions

    -- Public method to reset options to default.
    function module:Default()
        return LoadDefaultOptions()
    end

    -- OnLoad handler for the configuration frame.
    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        -- Localize once (no per-tick calls)
        LocalizeUIFrame()
        frame:HookScript("OnShow", function()
            configDirty = true
        end)
    end

    function module:InitCountdownSlider(slider)
        if not slider then return end
        local sliderName = slider:GetName()
        if not sliderName then return end
        local low = _G[sliderName .. "Low"]
        if low then
            low:SetText(tostring(MIN_COUNTDOWN))
        end
        local high = _G[sliderName .. "High"]
        if high then
            high:SetText(tostring(MAX_COUNTDOWN))
        end
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function()
        configDirty = true
        module:RequestRefresh()
    end)
    bindModuleToggleHide(module, uiController)

    -- OnClick handler for option controls.
    function module:OnClick(btn)
        if not btn then return end
        frameName = frameName or btn:GetParent():GetName()
        local value, name = nil, btn:GetName()

        if name ~= frameName .. "countdownDuration" then
            value = (btn:GetChecked() == 1) or false
            if name == frameName .. "minimapButton" then
                addon.Minimap:ToggleMinimapButton()
            end
        else
            value = btn:GetValue()
            _G[frameName .. "countdownDurationText"]:SetText(value)
        end

        name = strsub(name, strlen(frameName) + 1)
        Utils.triggerEvent("Config" .. name, value)
        KRT_Options[name] = value

        configDirty = true
        module:RequestRefresh()
    end

    -- Localizes UI elements.
    function LocalizeUIFrame()
        if localized then
            return
        end

        -- frameName must be ready here (OnLoad sets it before calling)
        _G[frameName .. "sortAscendingStr"]:SetText(L.StrConfigSortAscending)
        _G[frameName .. "useRaidWarningStr"]:SetText(L.StrConfigUseRaidWarning)
        _G[frameName .. "announceOnWinStr"]:SetText(L.StrConfigAnnounceOnWin)
        _G[frameName .. "announceOnHoldStr"]:SetText(L.StrConfigAnnounceOnHold)
        _G[frameName .. "announceOnBankStr"]:SetText(L.StrConfigAnnounceOnBank)
        _G[frameName .. "announceOnDisenchantStr"]:SetText(L.StrConfigAnnounceOnDisenchant)
        _G[frameName .. "lootWhispersStr"]:SetText(L.StrConfigLootWhisper)
        _G[frameName .. "countdownRollsBlockStr"]:SetText(L.StrConfigCountdownRollsBlock)
        _G[frameName .. "screenReminderStr"]:SetText(L.StrConfigScreenReminder)
        _G[frameName .. "ignoreStacksStr"]:SetText(L.StrConfigIgnoreStacks)
        _G[frameName .. "showTooltipsStr"]:SetText(L.StrConfigShowTooltips)
        _G[frameName .. "showLootCounterDuringMSRollStr"]:SetText(L.StrConfigShowLootCounterDuringMSRoll)
        _G[frameName .. "minimapButtonStr"]:SetText(L.StrConfigMinimapButton)
        _G[frameName .. "countdownDurationStr"]:SetText(L.StrConfigCountdownDuration)
        _G[frameName .. "countdownSimpleRaidMsgStr"]:SetText(L.StrConfigCountdownSimpleRaidMsg)

        Utils.setFrameTitle(frameName, SETTINGS)
        _G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
        _G[frameName .. "DefaultsBtn"]:SetText(L.BtnDefaults)
        _G[frameName .. "CloseBtn"]:SetText(L.BtnClose)
        _G[frameName .. "DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)

        localized = true
    end

    -- OnUpdate handler for the configuration frame.
    function UpdateUIFrame()
        if not configDirty then return end
        _G[frameName .. "sortAscending"]:SetChecked(addon.options.sortAscending == true)
        _G[frameName .. "useRaidWarning"]:SetChecked(addon.options.useRaidWarning == true)
        _G[frameName .. "announceOnWin"]:SetChecked(addon.options.announceOnWin == true)
        _G[frameName .. "announceOnHold"]:SetChecked(addon.options.announceOnHold == true)
        _G[frameName .. "announceOnBank"]:SetChecked(addon.options.announceOnBank == true)
        _G[frameName .. "announceOnDisenchant"]:SetChecked(addon.options.announceOnDisenchant == true)
        _G[frameName .. "lootWhispers"]:SetChecked(addon.options.lootWhispers == true)
        _G[frameName .. "countdownRollsBlock"]:SetChecked(addon.options.countdownRollsBlock == true)
        _G[frameName .. "screenReminder"]:SetChecked(addon.options.screenReminder == true)
        _G[frameName .. "ignoreStacks"]:SetChecked(addon.options.ignoreStacks == true)
        _G[frameName .. "showTooltips"]:SetChecked(addon.options.showTooltips == true)
        _G[frameName .. "showLootCounterDuringMSRoll"]:SetChecked(addon.options.showLootCounterDuringMSRoll == true)
        _G[frameName .. "minimapButton"]:SetChecked(addon.options.minimapButton == true)

        -- IMPORTANT: always update checked state (even if disabled)
        _G[frameName .. "countdownSimpleRaidMsg"]:SetChecked(addon.options.countdownSimpleRaidMsg == true)

        _G[frameName .. "countdownDuration"]:SetValue(addon.options.countdownDuration)
        _G[frameName .. "countdownDurationText"]:SetText(addon.options.countdownDuration)

        -- Dependency: if Use Raid Warnings is OFF, keep check state but grey out + disable.
        do
            local useRaidWarning = addon.options.useRaidWarning == true
            local countdownSimpleRaidMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
            local countdownSimpleRaidMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]

            if countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
                if useRaidWarning then
                    countdownSimpleRaidMsgBtn:Enable()
                    countdownSimpleRaidMsgStr:SetTextColor(
                        HIGHLIGHT_FONT_COLOR.r,
                        HIGHLIGHT_FONT_COLOR.g,
                        HIGHLIGHT_FONT_COLOR.b
                    )
                else
                    countdownSimpleRaidMsgBtn:Disable()
                    countdownSimpleRaidMsgStr:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end

        configDirty = false
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    bindModuleRequestRefresh(module, getFrame)
end

-- =========== Warnings Frame Module  =========== --
do
    addon.Warnings = addon.Warnings or {}
    local module = addon.Warnings
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTWarnings")
    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local fetched = false
    local warningsDirty = false

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local SaveWarning
    local isEdit = false

    local controller = Utils.makeListController {
        keyName = "WarningsList",
        poolTag = "warnings",
        _rowParts = { "ID", "Name" },

        getData = function(out)
            for i = 1, #KRT_Warnings do
                local w = KRT_Warnings[i]
                out[i] = { id = i, name = w and w.name or "" }
            end
        end,

        rowName = function(n, _, i) return n .. "WarningBtn" .. i end,
        rowTmpl = "KRTWarningButtonTemplate",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.ID:SetText(it.id)
            ui.Name:SetText(it.name)
        end),

        highlightId = function() return selectedID end,
    }

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)
        frame:HookScript("OnShow", function()
            warningsDirty = true
            lastSelectedID = false
        end)
        controller:OnLoad(frame)
    end

    -- Externally update frame:
    function module:Update()
        warningsDirty = true
        module:RequestRefresh()
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function()
        warningsDirty = true
        lastSelectedID = false
        module:RequestRefresh()
    end)
    bindModuleToggleHide(module, uiController)

    -- Warning selection:
    function module:Select(btn)
        if btn == nil or isEdit == true then return end
        local bName = btn:GetName()
        local wID = tonumber(_G[bName .. "ID"]:GetText())
        if KRT_Warnings[wID] == nil then return end
        if IsControlKeyDown() then
            selectedID = nil
            tempSelectedID = wID
            return self:Announce(tempSelectedID)
        end
        selectedID = (wID ~= selectedID) and wID or nil
        module:RequestRefresh()
    end

    -- Edit/Save warning:
    function module:Edit()
        local wName, wContent
        if selectedID ~= nil then
            local w = KRT_Warnings[selectedID]
            if w == nil then
                selectedID = nil
                return
            end
            if not isEdit and (tempName == "" and tempContent == "") then
                _G[frameName .. "Name"]:SetText(w.name)
                _G[frameName .. "Name"]:SetFocus()
                _G[frameName .. "Content"]:SetText(w.content)
                isEdit = true
                module:RequestRefresh()
                return
            end
        end
        wName    = _G[frameName .. "Name"]:GetText()
        wContent = _G[frameName .. "Content"]:GetText()
        return SaveWarning(wContent, wName, selectedID)
    end

    -- Delete Warning:
    function module:Delete(btn)
        if btn == nil or selectedID == nil then return end
        local oldWarnings = {}
        for i, w in ipairs(KRT_Warnings) do
            _G[frameName .. "WarningBtn" .. i]:Hide()
            if i ~= selectedID then
                tinsert(oldWarnings, w)
            end
        end
        twipe(KRT_Warnings)
        KRT_Warnings = oldWarnings
        local count = #KRT_Warnings
        if count <= 0 then
            selectedID = nil
        elseif count == 1 then
            selectedID = 1
        elseif selectedID > count then
            selectedID = selectedID - 1
        end
        warningsDirty = true
        module:RequestRefresh()
    end

    -- Announce Warning:
    function module:Announce(wID)
        if KRT_Warnings == nil then return end
        if wID == nil then
            wID = (selectedID ~= nil) and selectedID or tempSelectedID
        end
        if wID <= 0 or KRT_Warnings[wID] == nil then return end
        tempSelectedID = nil -- Always clear temporary selected id:
        return addon:Announce(KRT_Warnings[wID].content)
    end

    -- Cancel editing/adding:
    function module:Cancel()
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Content"])
        selectedID = nil
        tempSelectedID = nil
        isEdit = false
        module:RequestRefresh()
    end

    -- Localizing UI frame:
    function LocalizeUIFrame()
        if localized then return end
        _G[frameName .. "NameStr"]:SetText(L.StrName)
        _G[frameName .. "MessageStr"]:SetText(L.StrMessage)
        _G[frameName .. "EditBtn"]:SetText(L.BtnSave)
        _G[frameName .. "DeleteBtn"]:SetText(L.BtnDelete)
        _G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
        _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelpTitle)
        Utils.setFrameTitle(frameName, RAID_WARNING)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Content"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Content"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        _G[frameName .. "Content"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        localized = true
    end

    local function UpdateSelectionUI()
        if selectedID and KRT_Warnings[selectedID] then
            _G[frameName .. "OutputName"]:SetText(KRT_Warnings[selectedID].name)
            _G[frameName .. "OutputContent"]:SetText(KRT_Warnings[selectedID].content)
            _G[frameName .. "OutputContent"]:SetTextColor(1, 1, 1)
        else
            _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelpTitle)
            _G[frameName .. "OutputContent"]:SetText(L.StrWarningsHelpBody)
            _G[frameName .. "OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
        end
        lastSelectedID = selectedID
    end

    -- OnUpdate frame:
    function UpdateUIFrame()
        LocalizeUIFrame()
        if warningsDirty or not fetched then
            controller:Dirty()
            warningsDirty = false
            fetched = true
        end
        if selectedID ~= lastSelectedID then
            UpdateSelectionUI()
            controller:Touch()
        end
        tempName    = _G[frameName .. "Name"]:GetText()
        tempContent = _G[frameName .. "Content"]:GetText()
        Utils.enableDisable(_G[frameName .. "EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
        Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID ~= nil)
        Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID ~= nil)
        local editBtnMode = (tempName ~= "" or tempContent ~= "") or selectedID == nil
        if editBtnMode ~= lastEditBtnMode then
            Utils.setText(_G[frameName .. "EditBtn"], L.BtnSave, L.BtnEdit, editBtnMode)
            lastEditBtnMode = editBtnMode
        end
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    bindModuleRequestRefresh(module, getFrame)

    -- Saving a Warning:
    function SaveWarning(wContent, wName, wID)
        wID = wID and tonumber(wID) or 0
        wName = Utils.trimText(wName)
        wContent = Utils.trimText(wContent)
        if wName == "" then
            wName = (isEdit and wID > 0) and wID or (#KRT_Warnings + 1)
        end
        if wContent == "" then
            addon:error(L.StrWarningsError)
            return
        end
        if isEdit and wID > 0 and KRT_Warnings[wID] ~= nil then
            KRT_Warnings[wID].name = wName
            KRT_Warnings[wID].content = wContent
            isEdit = false
        else
            tinsert(KRT_Warnings, { name = wName, content = wContent })
        end
        module:Cancel()
        module:Update()
    end
end

-- =========== MS Changes Module  =========== --
do
    addon.Changes = addon.Changes or {}
    local module = addon.Changes
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTChanges")
    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local changesTable = {}
    local tmpNames = {}
    local SaveChanges, CancelChanges
    local fetched = false
    local changesDirty = false
    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode
    local lastAddBtnMode
    local isAdd = false
    local isEdit = false

    local controller = Utils.makeListController {
        keyName = "ChangesList",
        poolTag = "changes",
        _rowParts = { "Name", "Spec" },

        getData = function(out)
            local names = tmpNames
            if twipe then
                twipe(names)
            else
                for i = 1, #names do
                    names[i] = nil
                end
            end
            for name in pairs(changesTable) do
                names[#names + 1] = name
            end
            table.sort(names)
            for i = 1, #names do
                local name = names[i]
                out[i] = { id = i, name = name, spec = changesTable[name] }
            end
        end,

        rowName = function(n, it) return n .. "PlayerBtn" .. it.id end,
        rowTmpl = "KRTChangesButtonTemplate",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.Name:SetText(it.name)
            local class = addon.Raid:GetPlayerClass(it.name)
            local r, g, b = Utils.getClassColor(class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Spec:SetText(it.spec or L.StrNone)
        end),

        highlightFn = function(_, it) return it and it.name == selectedID end,
        highlightKey = function() return tostring(selectedID or "nil") end,
    }

    -- ----- Public methods ----- --

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)
        frame:HookScript("OnShow", function()
            changesDirty = true
            lastSelectedID = false
        end)
        controller:OnLoad(frame)
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function()
        changesDirty = true
        lastSelectedID = false
        module:RequestRefresh()
    end)

    -- Toggle frame visibility:
    function module:Toggle()
        CancelChanges()
        return uiController:Toggle()
    end

    -- Hide frame:
    function module:Hide()
        CancelChanges()
        return uiController:Hide()
    end

    -- Clear module:
    function module:Clear()
        if not KRT_CurrentRaid or changesTable == nil then return end
        for n in pairs(changesTable) do
            changesTable[n] = nil
        end
        CancelChanges()
        fetched = false
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    -- Selecting Player:
    function module:Select(btn)
        -- No selection.
        if not btn then return end
        local btnName = btn:GetName()
        local name = _G[btnName .. "Name"]:GetText()
        -- No ID set.
        if not name then return end
        -- Make sure the player exists in the raid:
        local found = true
        if not addon.Raid:CheckPlayer(name) then found = false end
        if not changesTable[name] then found = false end
        if not found then
            fetched = false
            changesDirty = true
            controller:Dirty()
            module:RequestRefresh()
            return
        end
        -- Quick announce?
        if IsControlKeyDown() then
            tempSelectedID = (name ~= selectedID) and name or nil
            self:Announce()
            return
        end
        -- Selection:
        selectedID = (name ~= selectedID) and name or nil
        isAdd = false
        isEdit = false
        module:RequestRefresh()
    end

    -- Add / Delete:
    function module:Add(btn)
        if not KRT_CurrentRaid or not btn then return end
        if not selectedID then
            btn:Hide()
            _G[frameName .. "Name"]:Show()
            _G[frameName .. "Name"]:SetFocus()
            isAdd = true
            module:RequestRefresh()
        elseif changesTable[selectedID] then
            changesTable[selectedID] = nil
            CancelChanges()
            fetched = false
            changesDirty = true
            controller:Dirty()
            module:RequestRefresh()
        end
    end

    -- Edit / Save
    function module:Edit()
        if not KRT_CurrentRaid then return end
        if not selectedID or isEdit then
            local name = _G[frameName .. "Name"]:GetText()
            local spec = _G[frameName .. "Spec"]:GetText()
            SaveChanges(name, spec)
        elseif changesTable[selectedID] then
            _G[frameName .. "Name"]:SetText(selectedID)
            _G[frameName .. "Spec"]:SetText(changesTable[selectedID])
            _G[frameName .. "Spec"]:Show()
            _G[frameName .. "Spec"]:SetFocus()
            isAdd = false
            isEdit = true
            module:RequestRefresh()
        end
    end

    -- Remove player's change:
    function module:Delete(name)
        if not KRT_CurrentRaid or not name then return end
        KRT_Raids[KRT_CurrentRaid].changes[name] = nil
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    Utils.registerCallback("RaidLeave", function(e, name)
        module:Delete(name)
        CancelChanges()
    end)

    -- Ask For module:
    function module:Demand()
        if not KRT_CurrentRaid then return end
        addon:Announce(L.StrChangesDemand)
    end

    -- Spam module:
    function module:Announce()
        if not KRT_CurrentRaid then return end
        -- In case of a reload/relog and the frame wasn't loaded
        if not fetched or not next(changesTable) then
            InitChangesTable()
        end
        local count = addon.tLength(changesTable)
        local msg
        if count == 0 then
            if tempSelectedID then
                tempSelectedID = nil
                return
            end
            msg = L.StrChangesAnnounceNone
        elseif selectedID or tempSelectedID then
            local name = tempSelectedID and tempSelectedID or selectedID
            if tempSelectedID ~= nil then tempSelectedID = nil end
            if not changesTable[name] then return end
            msg = format(L.StrChangesAnnounceOne, name, changesTable[name])
        else
            msg = L.StrChangesAnnounce
            local names = tmpNames
            if twipe then
                twipe(names)
            else
                for i = 1, #names do
                    names[i] = nil
                end
            end
            for n in pairs(changesTable) do
                names[#names + 1] = n
            end
            table.sort(names)
            for i = 1, #names do
                local n = names[i]
                msg = msg .. " " .. n .. "=" .. tostring(changesTable[n])
                if i < #names then msg = msg .. " /" end
            end
        end
        addon:Announce(msg)
    end

    -- Localize UI Frame:
    function LocalizeUIFrame()
        if localized then return end
        _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
        _G[frameName .. "AddBtn"]:SetText(L.BtnAdd)
        _G[frameName .. "EditBtn"]:SetText(L.BtnEdit)
        _G[frameName .. "DemandBtn"]:SetText(L.BtnDemand)
        _G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
        Utils.setFrameTitle(frameName, L.StrChanges)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Spec"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Spec"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Name"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        _G[frameName .. "Spec"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        localized = true
    end

    -- OnUpdate frame:
    function UpdateUIFrame()
        LocalizeUIFrame()
        if changesDirty or not fetched then
            InitChangesTable()
            controller:Dirty()
            changesDirty = false
            fetched = true
        end
        local count = addon.tLength(changesTable)
        if count <= 0 then
            tempSelectedID = nil
            selectedID = nil
        end
        if selectedID ~= lastSelectedID then
            lastSelectedID = selectedID
            controller:Touch()
        end
        Utils.showHide(_G[frameName .. "Name"], (isEdit or isAdd))
        Utils.showHide(_G[frameName .. "Spec"], (isEdit or isAdd))
        Utils.enableDisable(_G[frameName .. "EditBtn"], (selectedID or isEdit or isAdd))
        local editBtnMode = isAdd or (selectedID and isEdit)
        if editBtnMode ~= lastEditBtnMode then
            Utils.setText(_G[frameName .. "EditBtn"], L.BtnSave, L.BtnEdit, editBtnMode)
            lastEditBtnMode = editBtnMode
        end
        local addBtnMode = (not selectedID and not isEdit and not isAdd)
        if addBtnMode ~= lastAddBtnMode then
            Utils.setText(_G[frameName .. "AddBtn"], L.BtnAdd, L.BtnDelete, addBtnMode)
            lastAddBtnMode = addBtnMode
        end
        Utils.showHide(_G[frameName .. "AddBtn"], (not isEdit and not isAdd))
        Utils.enableDisable(_G[frameName .. "ClearBtn"], count > 0)
        Utils.enableDisable(_G[frameName .. "AnnounceBtn"], count > 0)
        Utils.enableDisable(_G[frameName .. "AddBtn"], KRT_CurrentRaid)
        Utils.enableDisable(_G[frameName .. "DemandBtn"], KRT_CurrentRaid)
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    bindModuleRequestRefresh(module, getFrame)

    -- Initialize changes table:
    function InitChangesTable()
        addon:debug(Diag.D.LogChangesInitTable)
        if not KRT_CurrentRaid then
            changesTable = {}
            return
        end
        local raid = KRT_Raids[KRT_CurrentRaid]
        raid.changes = raid.changes or {}
        changesTable = raid.changes
    end

    -- Save module:
    function SaveChanges(name, spec)
        if not KRT_CurrentRaid or not name then return end
        name = Utils.normalizeName(name)
        spec = Utils.normalizeName(spec)
        -- Is the player in the raid?
        local found
        found, name = addon.Raid:CheckPlayer(name)
        if not found then
            addon:error(format((name == "" and L.ErrChangesNoPlayer or L.ErrCannotFindPlayer), name))
            return
        end
        changesTable[name] = (spec == "") and nil or spec
        CancelChanges()
        fetched = false
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    -- Cancel all actions:
    function CancelChanges()
        isAdd = false
        isEdit = false
        selectedID = nil
        tempSelectedID = nil
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Spec"])
        module:RequestRefresh()
    end
end

-- =========== LFM Spam Module  =========== --
do
    addon.Spammer = addon.Spammer or {}
    local module = addon.Spammer
    -- ----- Internal state ----- --
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTSpammer")
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    -- Defaults / constants
    local DEFAULT_DURATION_STR = "60"
    local DEFAULT_DURATION_NUM = 60
    local DEFAULT_OUTPUT = "LFM"

    -- Runtime state
    local loaded = false

    -- Duration kept as string for coherence with EditBox/SV
    local duration = DEFAULT_DURATION_STR

    local finalOutput = DEFAULT_OUTPUT

    local ticking = false
    local paused = false
    local countdownTicker
    local countdownRemaining = 0

    local inputsLocked = false
    local previewDirty = true

    local inputFields = {
        "Name",
        "Duration",
        "Tank",
        "TankClass",
        "Healer",
        "HealerClass",
        "Melee",
        "MeleeClass",
        "Ranged",
        "RangedClass",
        "Message",
    }

    local resetFields = {
        "Name",
        "Tank",
        "TankClass",
        "Healer",
        "HealerClass",
        "Melee",
        "MeleeClass",
        "Ranged",
        "RangedClass",
        "Message",
    }

    local previewFields = {
        { key = "name",        box = "Name" },
        { key = "tank",        box = "Tank",       number = true },
        { key = "tankClass",   box = "TankClass" },
        { key = "healer",      box = "Healer",     number = true },
        { key = "healerClass", box = "HealerClass" },
        { key = "melee",       box = "Melee",      number = true },
        { key = "meleeClass",  box = "MeleeClass" },
        { key = "ranged",      box = "Ranged",     number = true },
        { key = "rangedClass", box = "RangedClass" },
        { key = "message",     box = "Message" },
    }

    local lastControls = {
        locked = nil,
        canStart = nil,
        btnLabel = nil,
        isStop = nil,
    }

    local lastState = {
        name = nil,
        tank = 0,
        tankClass = nil,
        healer = 0,
        healerClass = nil,
        melee = 0,
        meleeClass = nil,
        ranged = 0,
        rangedClass = nil,
        message = nil,
        duration = nil, -- string
    }
    -- Forward declarations
    local RenderPreview
    local StartSpamCycle
    local StopSpamCycle
    local UpdateControls
    local BuildOutput
    local UpdateTickDisplay
    local SetInputsLocked
    local GetValidDuration

    -- Small helpers
    local function ResetLastState()
        lastState.name = nil
        lastState.tank = 0
        lastState.tankClass = nil
        lastState.healer = 0
        lastState.healerClass = nil
        lastState.melee = 0
        lastState.meleeClass = nil
        lastState.ranged = 0
        lastState.rangedClass = nil
        lastState.message = nil
        lastState.duration = nil
    end

    local function SetCheckbox(suffix, checked)
        local chk = _G[frameName .. suffix]
        if chk and chk.SetChecked then
            chk:SetChecked(checked and true or false)
        end
    end

    local function ResetAllChannelCheckboxes()
        for i = 1, 8 do
            SetCheckbox("Chat" .. i, false)
        end
        SetCheckbox("ChatGuild", false)
        SetCheckbox("ChatYell", false)
    end

    -- Deterministic: sync Duration immediately from UI/SV (no waiting for preview tick)
    local function SyncDurationNow()
        local value
        local frame = getFrame()

        if frame and frame:IsShown() then
            local box = _G[frameName .. "Duration"]
            if box then
                value = box:GetText()
                if value == "" then
                    value = DEFAULT_DURATION_STR
                    box:SetText(value)
                end
                value = tostring(value)
            end
        end

        if not value or value == "" then
            value = (KRT_Spammer and KRT_Spammer.Duration) or DEFAULT_DURATION_STR
            value = tostring(value)
        end

        duration = value
        lastState.duration = value
        KRT_Spammer.Duration = value
    end

    -- Deterministic: ensure preview/output is computed before Start/Resume
    local function EnsureReadyForStart()
        SyncDurationNow()

        local frame = getFrame()
        if frame and frame:IsShown() then
            if previewDirty or not finalOutput or finalOutput == "" then
                RenderPreview()
                previewDirty = false
            end
        end
    end

    local function ResetLengthUI()
        local frame = getFrame()
        if not frame then return end
        local len = strlen(DEFAULT_OUTPUT)
        local lenStr = len .. "/255"

        local out = _G[frameName .. "Output"]
        if out then out:SetText(DEFAULT_OUTPUT) end

        local lengthText = _G[frameName .. "Length"]
        if lengthText then
            lengthText:SetText(lenStr)
            lengthText:SetTextColor(0.5, 0.5, 0.5)
        end

        local msg = _G[frameName .. "Message"]
        if msg and msg.SetMaxLetters then
            msg:SetMaxLetters(255)
        end
    end

    -- OnLoad frame
    function module:OnLoad(frame)
        if not frame then return end

        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        -- Localize once (not per tick)
        LocalizeUIFrame()

        frame:SetScript("OnShow", function()
            module:RequestRefresh()
        end)

        if frame:IsShown() then
            module:RequestRefresh()
        end
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    -- Save (EditBox / Checkbox)
    function module:Save(box)
        if not box then return end

        local boxName = box:GetName()
        local target = gsub(boxName, frameName, "")

        if find(target, "Chat") then
            KRT_Spammer.Channels = KRT_Spammer.Channels or {}

            local channel = gsub(target, "Chat", "")
            local id = tonumber(channel) or select(1, GetChannelName(channel))
            channel = (id and id > 0) and id or channel

            -- FIX: GetChecked can be true/false or 1/0
            local checked = box:GetChecked()
            checked = (checked == true or checked == 1)

            local existed = tContains(KRT_Spammer.Channels, channel)
            if checked and not existed then
                tinsert(KRT_Spammer.Channels, channel)
            elseif not checked and existed then
                local i = addon.tIndexOf(KRT_Spammer.Channels, channel)
                while i do
                    tremove(KRT_Spammer.Channels, i)
                    i = addon.tIndexOf(KRT_Spammer.Channels, channel)
                end
            end
        else
            local value = Utils.trimText(box:GetText())
            value = (value == "") and nil or value
            KRT_Spammer[target] = value
            box:ClearFocus()
        end

        loaded = false
        previewDirty = true
        module:RequestRefresh()
    end

    -- Start/Stop/Pause
    function module:Start()
        EnsureReadyForStart()

        if addon.WithinRange(strlen(finalOutput), 4, 255) then
            if paused then
                paused = false
                SetInputsLocked(true)
                StartSpamCycle(false)
            elseif ticking then
                ticking = false
                paused = false
                StopSpamCycle(true)
                SetInputsLocked(false)
            else
                ticking = true
                paused = false
                SetInputsLocked(true)
                StartSpamCycle(true)
            end
            module:RequestRefresh()
        end
    end

    function module:Stop()
        ticking = false
        paused = false
        StopSpamCycle(true)
        SetInputsLocked(false)
        module:RequestRefresh()
    end

    function module:Pause()
        if not ticking or paused then return end
        paused = true
        StopSpamCycle(false)
        SetInputsLocked(false)
        module:RequestRefresh()
    end

    -- Spam
    function module:Spam()
        if strlen(finalOutput) > 255 then
            addon:error(L.StrSpammerErrLength)
            ticking = false
            return
        end

        local chList = KRT_Spammer.Channels or {}

        -- CHANGE: fallback SAY (not YELL)
        if #chList <= 0 then
            Utils.chat(tostring(finalOutput), "SAY", nil, nil, true)
            return
        end

        for _, c in ipairs(chList) do
            if type(c) == "number" then
                Utils.chat(tostring(finalOutput), "CHANNEL", nil, c, true)
            else
                Utils.chat(tostring(finalOutput), upper(c), nil, nil, true)
            end
        end
    end

    -- Tab
    function module:Tab(a, b)
        local target
        if IsShiftKeyDown() and _G[frameName .. b] ~= nil then
            target = _G[frameName .. b]
        elseif _G[frameName .. a] ~= nil then
            target = _G[frameName .. a]
        end
        if target then target:SetFocus() end
    end

    -- Clear
    function module:Clear()
        for k, _ in pairs(KRT_Spammer) do
            if k ~= "Channels" then
                KRT_Spammer[k] = nil
            end
        end

        finalOutput = DEFAULT_OUTPUT
        ResetLastState()

        module:Stop()

        for _, field in ipairs(resetFields) do
            Utils.resetEditBox(_G[frameName .. field])
        end

        local durationBox = _G[frameName .. "Duration"]
        KRT_Spammer.Duration = DEFAULT_DURATION_STR
        duration = DEFAULT_DURATION_STR

        if durationBox then
            Utils.resetEditBox(durationBox)
            durationBox:SetText(DEFAULT_DURATION_STR)
        end

        loaded = false
        previewDirty = true

        -- FIX: reset UI immediately (len/255 included)
        ResetLengthUI()
        UpdateControls()
    end

    -- Localize UI
    function LocalizeUIFrame()
        if localized then return end

        _G[frameName .. "NameStr"]:SetText(L.StrRaid)
        _G[frameName .. "DurationStr"]:SetText(L.StrDuration)
        _G[frameName .. "Tick"]:SetText("")
        _G[frameName .. "CompStr"]:SetText(L.StrSpammerCompStr)
        _G[frameName .. "NeedStr"]:SetText(L.StrSpammerNeedStr)
        _G[frameName .. "ClassStr"]:SetText(L.StrClass)
        _G[frameName .. "TanksStr"]:SetText(L.StrTank)
        _G[frameName .. "HealersStr"]:SetText(L.StrHealer)
        _G[frameName .. "MeleesStr"]:SetText(L.StrMelee)
        _G[frameName .. "RangedStr"]:SetText(L.StrRanged)
        _G[frameName .. "MessageStr"]:SetText(L.StrSpammerMessageStr)
        _G[frameName .. "ChannelsStr"]:SetText(L.StrChannels)
        for i = 1, 8 do
            local label = _G[frameName .. "Channel" .. i .. "Str"]
            if label then
                label:SetText(tostring(i))
            end
        end
        _G[frameName .. "ChannelGuildStr"]:SetText(L.StrGuild)
        _G[frameName .. "ChannelYellStr"]:SetText(L.StrYell)
        _G[frameName .. "PreviewStr"]:SetText(L.StrSpammerPreviewStr)
        _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
        _G[frameName .. "StartBtn"]:SetText(L.BtnStart)

        Utils.setFrameTitle(frameName, L.StrSpammer)
        _G[frameName .. "StartBtn"]:SetScript("OnClick", module.Start)

        local durationBox = _G[frameName .. "Duration"]
        durationBox.tooltip_title = AUCTION_DURATION
        addon:SetTooltip(durationBox, L.StrSpammerDurationHelp)

        local messageBox = _G[frameName .. "Message"]
        messageBox.tooltip_title = L.StrMessage
        addon:SetTooltip(messageBox, {
            L.StrSpammerMessageHelp1,
            L.StrSpammerMessageHelp2,
            L.StrSpammerMessageHelp3,
        })

        local function setupEditBox(target)
            local box = _G[frameName .. target]
            if not box then return end

            box:SetScript("OnEditFocusGained", function()
                if ticking and not paused then
                    module:Pause()
                end
            end)

            box:SetScript("OnTextChanged", function(_, isUserInput)
                if inputsLocked then return end
                if isUserInput then
                    previewDirty = true
                    module:RequestRefresh()
                end
            end)

            box:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            box:SetScript("OnEditFocusLost", function(self)
                module:Save(self)
            end)
        end

        for _, f in ipairs(inputFields) do
            setupEditBox(f)
        end

        -- Initialize default UI length once
        ResetLengthUI()

        localized = true
    end

    -- Tick display
    function UpdateTickDisplay()
        if countdownRemaining > 0 then
            _G[frameName .. "Tick"]:SetText(countdownRemaining)
        else
            _G[frameName .. "Tick"]:SetText("")
        end
    end

    -- Lock/unlock inputs
    function SetInputsLocked(locked)
        if inputsLocked == locked then return end
        inputsLocked = locked

        local alpha = locked and 0.7 or 1.0

        local function setEditBoxState(box, enabled)
            if not box then return end
            if box.SetEnabled then
                box:SetEnabled(enabled)
            elseif enabled and box.Enable then
                box:Enable()
            elseif not enabled and box.Disable then
                box:Disable()
            end
        end

        for _, field in ipairs(inputFields) do
            local box = _G[frameName .. field]
            if box then
                setEditBoxState(box, not locked)
                box:SetAlpha(alpha)
                if locked then
                    box:ClearFocus()
                end
            end
        end

        for i = 1, 8 do
            Utils.enableDisable(_G[frameName .. "Chat" .. i], not locked)
        end
        Utils.enableDisable(_G[frameName .. "ChatGuild"], not locked)
        Utils.enableDisable(_G[frameName .. "ChatYell"], not locked)
        Utils.enableDisable(_G[frameName .. "ClearBtn"], not locked)
    end

    -- Spam cycle
    function StopSpamCycle(resetCountdown)
        -- Stop and clear the spam ticker
        addon.CancelTimer(countdownTicker, true)
        countdownTicker = nil

        if resetCountdown then
            countdownRemaining = 0
        end

        UpdateTickDisplay()
    end

    function GetValidDuration()
        local value = tonumber(duration)
        if not value or value <= 0 then
            value = DEFAULT_DURATION_NUM
        end
        return value
    end

    function StartSpamCycle(resetCountdown)
        StopSpamCycle(false)

        local d = GetValidDuration()
        if resetCountdown or countdownRemaining <= 0 then
            countdownRemaining = d
        end

        UpdateTickDisplay()

        countdownTicker = addon.NewTicker(1, function()
            if not ticking or paused then return end

            countdownRemaining = countdownRemaining - 1
            if countdownRemaining <= 0 then
                module:Spam()
                countdownRemaining = GetValidDuration()
            end

            UpdateTickDisplay()
        end)
    end

    -- Build output
    function BuildOutput()
        local outBuf = { DEFAULT_OUTPUT }

        local name = lastState.name or ""
        if name ~= "" then
            outBuf[#outBuf + 1] = " "
            outBuf[#outBuf + 1] = name
        end

        local needParts = {}
        local function addNeed(n, label, class)
            n = tonumber(n) or 0
            if n > 0 then
                local s = n .. " " .. label
                if class and class ~= "" then
                    s = s .. " (" .. class .. ")"
                end
                needParts[#needParts + 1] = s
            end
        end

        addNeed(lastState.tank, "Tank", lastState.tankClass)
        addNeed(lastState.healer, "Healer", lastState.healerClass)
        addNeed(lastState.melee, "Melee", lastState.meleeClass)
        addNeed(lastState.ranged, "Ranged", lastState.rangedClass)

        if #needParts > 0 then
            outBuf[#outBuf + 1] = " - Need "
            outBuf[#outBuf + 1] = tconcat(needParts, ", ")
        end

        if lastState.message and lastState.message ~= "" then
            outBuf[#outBuf + 1] = " - "
            outBuf[#outBuf + 1] = Utils.findAchievement(lastState.message)
        end

        local temp = tconcat(outBuf)

        if temp ~= DEFAULT_OUTPUT then
            local total =
                (tonumber(lastState.tank) or 0) +
                (tonumber(lastState.healer) or 0) +
                (tonumber(lastState.melee) or 0) +
                (tonumber(lastState.ranged) or 0)

            local is25 = (name ~= "" and name:match("%f[%d]25%f[%D]")) ~= nil
            local max = is25 and 25 or 10
            temp = temp .. " (" .. (max - total) .. "/" .. max .. ")"
        end

        return temp
    end

    -- Controls update
    function UpdateControls()
        local locked = ticking and not paused
        local canStart = (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255)
        local btnLabel = paused and L.BtnResume or L.BtnStop
        local isStop = ticking == true

        if lastControls.locked == locked and
            lastControls.canStart == canStart and
            lastControls.btnLabel == btnLabel and
            lastControls.isStop == isStop then
            return
        end

        local frame = getFrame()
        if frame then
            SetInputsLocked(locked)
        end

        Utils.setText(_G[frameName .. "StartBtn"], btnLabel, L.BtnStart, isStop)
        Utils.enableDisable(_G[frameName .. "StartBtn"], canStart)

        lastControls.locked = locked
        lastControls.canStart = canStart
        lastControls.btnLabel = btnLabel
        lastControls.isStop = isStop
    end

    -- Preview render
    function RenderPreview()
        local frame = getFrame()
        if not frame or not frame:IsShown() then return end

        local changed = false

        for _, field in ipairs(previewFields) do
            local box = _G[frameName .. field.box]
            local value
            if field.number then
                value = tonumber(box:GetText()) or 0
            else
                value = Utils.trimText(box:GetText())
            end

            if lastState[field.key] ~= value then
                lastState[field.key] = value
                changed = true
            end
        end

        local durationBox = _G[frameName .. "Duration"]
        local durationValue = durationBox and durationBox:GetText() or ""
        if durationValue == "" then
            durationValue = DEFAULT_DURATION_STR
            if durationBox then durationBox:SetText(durationValue) end
        end

        if lastState.duration ~= durationValue then
            lastState.duration = durationValue
            changed = true
        end

        if changed then
            finalOutput = BuildOutput()

            local out = _G[frameName .. "Output"]
            if out then out:SetText(finalOutput) end

            local len = strlen(finalOutput)
            local lenText = _G[frameName .. "Length"]
            if lenText then
                lenText:SetText(len .. "/255")
                if finalOutput == DEFAULT_OUTPUT then
                    lenText:SetTextColor(0.5, 0.5, 0.5)
                elseif len <= 255 then
                    lenText:SetTextColor(0.0, 1.0, 0.0)
                else
                    lenText:SetTextColor(1.0, 0.0, 0.0)
                end
            end

            local msg = _G[frameName .. "Message"]
            if msg and msg.SetMaxLetters then
                if len <= 255 then
                    msg:SetMaxLetters(255)
                else
                    local messageValue = lastState.message or ""
                    msg:SetMaxLetters(strlen(messageValue) - 1)
                end
            end
        end

        duration = lastState.duration or DEFAULT_DURATION_STR
        KRT_Spammer.Duration = duration

        UpdateControls()
    end

    -- UI update tick
    function UpdateUIFrame()
        local frame = getFrame()
        if not (frame and frame:IsShown()) then
            return
        end

        if not loaded then
            KRT_Spammer.Duration = KRT_Spammer.Duration or DEFAULT_DURATION_STR

            ResetAllChannelCheckboxes()

            for k, v in pairs(KRT_Spammer) do
                if k == "Channels" then
                    for i, c in ipairs(v) do
                        local id = tonumber(c) or select(1, GetChannelName(c))
                        id = (id and id > 0) and id or c
                        v[i] = id
                        SetCheckbox("Chat" .. id, true)
                    end
                elseif _G[frameName .. k] then
                    _G[frameName .. k]:SetText(v)
                end
            end

            loaded = true
            previewDirty = true
        end

        if ticking and not paused then
            UpdateControls()
            UpdateTickDisplay()
            return
        end

        if previewDirty then
            RenderPreview()
            previewDirty = false
        else
            UpdateControls()
            UpdateTickDisplay()
        end
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    bindModuleRequestRefresh(module, getFrame)
end

-- =========== Logger Frame =========== --
-- Shown loot logger for raids
do
    addon.Logger   = addon.Logger or {}
    local module   = addon.Logger
    local frameName

    local getFrame = Utils.makeFrameGetter("KRTLogger")
    -- module: stable-ID data helpers (fresh SavedVariables only; no legacy migration)
    module.Store   = module.Store or {}
    module.View    = module.View or {}
    module.Actions = module.Actions or {}

    local Store    = module.Store
    local View     = module.View
    local Actions  = module.Actions

    -- Ensure the raid table has the schema v2 fields required by the module.
    -- This does NOT migrate legacy structures; it only initializes missing fields for fresh SV.
    function Store:EnsureRaid(raid)
        if not raid then return end
        raid.players       = raid.players or {}
        raid.bossKills     = raid.bossKills or {}
        raid.loot          = raid.loot or {}
        raid.nextBossNid   = raid.nextBossNid or 1
        raid.nextLootNid   = raid.nextLootNid or 1

        -- Runtime-only indexes (not persisted).
        raid._bossIdxByNid = raid._bossIdxByNid or nil
        raid._lootIdxByNid = raid._lootIdxByNid or nil
    end

    function Store:GetRaid(rID)
        local raid = rID and KRT_Raids[rID] or nil
        if raid then self:EnsureRaid(raid) end
        return raid
    end

    function Store:InvalidateIndexes(raid)
        if not raid then return end
        raid._bossIdxByNid = nil
        raid._lootIdxByNid = nil
    end

    local function normalizeNid(v)
        return tonumber(v) or v
    end

    local function buildIndex(raid, listField, idField, cacheField)
        local list = raid[listField] or {}
        local m = {}
        for i = 1, #list do
            local e = list[i]
            local id = e and e[idField]
            if id ~= nil then
                m[normalizeNid(id)] = i
            end
        end
        raid[cacheField] = m
    end

    local function getIndexedPositionByNid(raid, queryNid, listField, idField, cacheField)
        if not (raid and queryNid) then return nil end

        local normalizedNid = normalizeNid(queryNid)
        if not raid[cacheField] then
            buildIndex(raid, listField, idField, cacheField)
        end

        local idx = raid[cacheField][normalizedNid]
        if not idx then
            -- Raid changed since last build (new entry added / list changed)
            buildIndex(raid, listField, idField, cacheField)
            idx = raid[cacheField][normalizedNid]
        end
        return idx
    end

    function Store:BossIdx(raid, bossNid)
        return getIndexedPositionByNid(raid, bossNid, "bossKills", "bossNid", "_bossIdxByNid")
    end

    function Store:LootIdx(raid, lootNid)
        return getIndexedPositionByNid(raid, lootNid, "loot", "lootNid", "_lootIdxByNid")
    end

    function Store:GetBoss(raid, bossNid)
        local idx = self:BossIdx(raid, bossNid)
        return idx and raid.bossKills[idx] or nil, idx
    end

    function Store:GetLoot(raid, lootNid)
        local idx = self:LootIdx(raid, lootNid)
        return idx and raid.loot[idx] or nil, idx
    end

    function Store:FindRaidPlayerByNormName(raid, normalizedLower)
        if not (raid and normalizedLower) then return nil end
        local players = raid.players or {}
        for i = 1, #players do
            local p = players[i]
            if p and p.name and Utils.normalizeLower(p.name) == normalizedLower then
                return p.name, i, p
            end
        end
        return nil
    end

    function View:GetBossModeLabel(bossData)
        if not bossData then return "?" end
        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        return (mode == "h") and "H" or "N"
    end

    function View:BuildRows(out, list, pred, map)
        if not out then return end
        twipe(out)
        if not list then return end
        local n = 0
        for i = 1, #list do
            local e = list[i]
            if (not pred) or pred(e, i) then
                n = n + 1
                out[n] = map(e, i, n)
            end
        end
    end

    function View:FillBossList(out, raid)
        self:BuildRows(out, raid and raid.bossKills, nil, function(boss, i)
            local it = {}
            it.id = tonumber(boss and boss.bossNid) or (boss and boss.bossNid) or i -- stable nid for highlight/selection
            it.seq = i                                                              -- display-only (rescales after deletions)
            it.name = boss and boss.name or ""
            it.time = boss and boss.time or time()
            it.timeFmt = date("%H:%M", it.time)
            it.mode = self:GetBossModeLabel(boss)
            return it
        end)
    end

    function View:FillRaidAttendeesList(out, raid)
        self:BuildRows(out, raid and raid.players, nil, function(p, i)
            local it = {}
            it.id = i
            it.name = p.name
            it.class = p.class
            it.join = p.join
            it.leave = p.leave
            it.joinFmt = p.join and date("%H:%M", p.join) or ""
            it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
            return it
        end)
    end

    function View:FillBossAttendeesList(out, raid, bossNid)
        if not out then return end
        twipe(out)
        if not (raid and bossNid) then return end
        local bossKill = Store:GetBoss(raid, bossNid)
        if not (bossKill and bossKill.players and raid.players) then return end

        -- Build a set for O(1) membership checks.
        local set = {}
        for i = 1, #bossKill.players do
            local name = bossKill.players[i]
            if name then set[name] = true end
        end

        local n = 0
        for i = 1, #raid.players do
            local p = raid.players[i]
            if p and p.name and set[p.name] then
                n = n + 1
                local it = {}
                it.id = i -- IMPORTANT: stable reference into raid.players (used for delete)
                it.name = p.name
                it.class = p.class
                out[n] = it
            end
        end
    end

    function View:FillLootList(out, raid, bossNid, playerName)
        local bossFilter = tonumber(bossNid) or bossNid
        self:BuildRows(out, raid and raid.loot,
            function(v)
                if not v then return false end
                local okBoss = (not bossFilter) or (bossFilter <= 0) or (tonumber(v.bossNid) == bossFilter)
                local okPlayer = (not playerName) or (v.looter == playerName)
                return okBoss and okPlayer
            end,
            function(v)
                local it = {}
                it.id = v.lootNid
                it.itemId = v.itemId
                it.itemName = v.itemName
                it.itemRarity = v.itemRarity
                it.itemTexture = v.itemTexture
                it.itemLink = v.itemLink
                it.bossNid = v.bossNid
                it.looter = v.looter
                it.rollType = tonumber(v.rollType) or 0
                it.rollValue = v.rollValue
                it.time = v.time or time()
                it.timeFmt = date("%H:%M", it.time)
                return it
            end
        )
    end

    function Actions:RemoveAll(list, value)
        if not (list and value) then return end
        local i = addon.tIndexOf(list, value)
        while i do
            tremove(list, i)
            i = addon.tIndexOf(list, value)
        end
    end

    function Actions:Commit(raid, opts)
        if not raid then return end
        opts = opts or {}

        if opts.invalidate ~= false then
            Store:InvalidateIndexes(raid)
        end

        local log = addon.Logger
        if not log then return end

        local changedBoss, changedPlayer, changedBossPlayer, changedItem = false, false, false, false

        local function clearBossSelection()
            if log.selectedBoss ~= nil then changedBoss = true end
            if log.selectedBossPlayer ~= nil then changedBossPlayer = true end
            if log.selectedItem ~= nil then changedItem = true end
            log.selectedBoss = nil
            log.selectedBossPlayer = nil
            log.selectedItem = nil
        end

        -- Validate boss selection (bossNid)
        if log.selectedBoss then
            local bossKill = Store:GetBoss(raid, log.selectedBoss)
            if not bossKill then
                clearBossSelection()
            end
        else
            -- No boss selected: dependent selections must be cleared
            if log.selectedBossPlayer ~= nil then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
            if log.selectedItem ~= nil then
                log.selectedItem = nil
                changedItem = true
            end
        end

        -- Validate loot selection (lootNid)
        if log.selectedItem then
            local lootEntry = Store:GetLoot(raid, log.selectedItem)
            if not lootEntry then
                log.selectedItem = nil
                changedItem = true
            end
        end

        -- Validate player selections (raid.players index)
        if opts.clearPlayers then
            if log.selectedPlayer ~= nil then
                log.selectedPlayer = nil
                changedPlayer = true
            end
            if log.selectedBossPlayer ~= nil then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
        else
            if log.selectedPlayer and (not raid.players or not raid.players[log.selectedPlayer]) then
                log.selectedPlayer = nil
                changedPlayer = true
            end
            if log.selectedBossPlayer and (not raid.players or not raid.players[log.selectedBossPlayer]) then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
        end

        if changedBoss then Utils.triggerEvent("LoggerSelectBoss", log.selectedBoss) end
        if changedPlayer then Utils.triggerEvent("LoggerSelectPlayer", log.selectedPlayer) end
        if changedBossPlayer then Utils.triggerEvent("LoggerSelectBossPlayer", log.selectedBossPlayer) end
        if changedItem then Utils.triggerEvent("LoggerSelectItem", log.selectedItem) end
    end

    function Actions:DeleteBoss(rID, bossNid)
        local raid = Store:GetRaid(rID)
        if not (raid and bossNid) then return 0 end

        local _, bossIndex = Store:GetBoss(raid, bossNid)
        if not bossIndex then return 0 end

        local removed = 0
        for i = #raid.loot, 1, -1 do
            local l = raid.loot[i]
            if l and tonumber(l.bossNid) == tonumber(bossNid) then
                tremove(raid.loot, i)
                removed = removed + 1
            end
        end

        tremove(raid.bossKills, bossIndex)
        self:Commit(raid)

        if KRT_CurrentRaid == rID and tonumber(KRT_LastBoss) == tonumber(bossNid) then
            KRT_LastBoss = nil
        end

        return removed
    end

    function Actions:DeleteLoot(rID, lootNid)
        local raid = Store:GetRaid(rID)
        if not (raid and lootNid) then return false end
        local _, lootIndex = Store:GetLoot(raid, lootNid)
        if not lootIndex then return false end
        tremove(raid.loot, lootIndex)
        self:Commit(raid)
        return true
    end

    -- Bulk delete: removes multiple loot entries (by nid) with a single Commit()
    -- Returns: number of removed entries
    function Actions:DeleteLootMany(rID, lootNids)
        local raid = Store:GetRaid(rID)
        if not (raid and lootNids and raid.loot) then return 0 end

        local set = {}
        for i = 1, #lootNids do
            local k = lootNids[i]
            if k ~= nil then
                local nk = tonumber(k) or k
                set[nk] = true
            end
        end

        local removed = 0
        for i = #raid.loot, 1, -1 do
            local l = raid.loot[i]
            local nid = l and (tonumber(l.lootNid) or l.lootNid)
            if nid ~= nil and set[nid] then
                tremove(raid.loot, i)
                removed = removed + 1
            end
        end

        if removed > 0 then
            self:Commit(raid)
        end
        return removed
    end

    function Actions:DeleteBossAttendee(rID, bossNid, playerIdx)
        local raid = Store:GetRaid(rID)
        if not (raid and bossNid and playerIdx) then return false end
        local bossKill = Store:GetBoss(raid, bossNid)
        if not (bossKill and bossKill.players and raid.players and raid.players[playerIdx]) then return false end
        local name = raid.players[playerIdx].name
        if not name then return false end
        self:RemoveAll(bossKill.players, name)
        return true
    end

    function Actions:DeleteRaidAttendee(rID, playerIdx)
        local raid = Store:GetRaid(rID)
        if not (raid and raid.players and raid.players[playerIdx]) then return false end

        local name = raid.players[playerIdx].name

        -- Keep playersByName consistent: mark this record as inactive so UpdateRaidRoster()
        -- can safely rebuild raid.players when needed (e.g. after manual roster edits).
        if name and raid.playersByName and raid.playersByName[name] then
            local p = raid.playersByName[name]
            if p and p.leave == nil then
                p.leave = Utils.getCurrentTime()
            end
        end

        tremove(raid.players, playerIdx)

        -- Remove from all boss attendee lists.
        if name and raid.bossKills then
            for _, boss in ipairs(raid.bossKills) do
                if boss and boss.players then
                    self:RemoveAll(boss.players, name)
                end
            end
        end

        -- Remove loot won by removed player.
        if name and raid.loot then
            for i = #raid.loot, 1, -1 do
                if raid.loot[i] and raid.loot[i].looter == name then
                    tremove(raid.loot, i)
                end
            end
        end

        self:Commit(raid, { clearPlayers = true })
        return true
    end

    -- Bulk delete: removes multiple raid attendees (by playerIdx) with a single Commit()
    -- Returns: number of removed attendees
    function Actions:DeleteRaidAttendeeMany(rID, playerIdxs)
        local raid = Store:GetRaid(rID)
        if not (raid and raid.players and playerIdxs and #playerIdxs > 0) then return 0 end

        -- Normalize + sort descending (indices shift on removal).
        local ids = {}
        local seen = {}
        for i = 1, #playerIdxs do
            local v = tonumber(playerIdxs[i]) or playerIdxs[i]
            if v and not seen[v] then
                seen[v] = true
                tinsert(ids, v)
            end
        end
        table.sort(ids, function(a, b) return a > b end)

        -- Collect names + remove players from raid.players.
        local removedNames = {}
        local removed = 0
        for i = 1, #ids do
            local idx = ids[i]
            local p = raid.players[idx]
            if p and p.name then
                removedNames[p.name] = true
                tremove(raid.players, idx)
                removed = removed + 1
            end
        end

        if removed == 0 then return 0 end

        -- Keep playersByName consistent: mark removed names as inactive so UpdateRaidRoster()
        -- can re-add current raid members after manual roster edits.
        if raid.playersByName then
            local now = Utils.getCurrentTime()
            for n, _ in pairs(removedNames) do
                local p = raid.playersByName[n]
                if p and p.leave == nil then
                    p.leave = now
                end
            end
        end

        -- Remove from all boss attendee lists.
        if raid.bossKills then
            for _, boss in ipairs(raid.bossKills) do
                if boss and boss.players then
                    for j = #boss.players, 1, -1 do
                        if removedNames[boss.players[j]] then
                            tremove(boss.players, j)
                        end
                    end
                end
            end
        end

        -- Remove loot won by removed players.
        if raid.loot then
            for j = #raid.loot, 1, -1 do
                if raid.loot[j] and removedNames[raid.loot[j].looter] then
                    tremove(raid.loot, j)
                end
            end
        end

        self:Commit(raid, { clearPlayers = true })
        return removed
    end

    function Actions:DeleteRaid(rID)
        local sel = tonumber(rID)
        if not sel or not KRT_Raids[sel] then return false end

        if KRT_CurrentRaid and KRT_CurrentRaid == sel then
            addon:error(L.ErrCannotDeleteRaid)
            return false
        end

        tremove(KRT_Raids, sel)

        if KRT_CurrentRaid and KRT_CurrentRaid > sel then
            KRT_CurrentRaid = KRT_CurrentRaid - 1
        end

        return true
    end

    function Actions:SetCurrentRaid(rID)
        local sel = tonumber(rID)
        local raid = sel and KRT_Raids[sel] or nil
        if not (sel and raid) then return false end

        -- This is meant to fix duplicate raid creation while actively raiding.
        if not addon.IsInRaid() then
            addon:error(L.ErrCannotSetCurrentNotInRaid)
            return false
        end

        local instanceName, instanceType, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if isDyn then
            instanceDiff = instanceDiff + (2 * dynDiff)
        end
        if instanceType ~= "raid" then
            addon:error(L.ErrCannotSetCurrentNotInInstance)
            return false
        end
        if raid.zone and raid.zone ~= instanceName then
            addon:error(L.ErrCannotSetCurrentZoneMismatch)
            return false
        end

        local raidDiff = tonumber(raid.difficulty)
        local curDiff = tonumber(instanceDiff)
        if not (raidDiff and curDiff and raidDiff == curDiff) then
            addon:error(L.ErrCannotSetCurrentRaidDifficulty)
            return false
        end

        local raidSize = tonumber(raid.size)
        local groupSize = addon.Raid:GetRaidSize()
        if not raidSize or raidSize ~= groupSize then
            addon:error(L.ErrCannotSetCurrentRaidSize)
            return false
        end

        if addon.Raid:Expired(sel) then
            addon:error(L.ErrCannotSetCurrentRaidReset)
            return false
        end

        KRT_CurrentRaid = sel
        KRT_LastBoss = nil

        -- Sync roster/dropdowns immediately so subsequent logging targets the selected raid.
        addon.Raid:UpdateRaidRoster()

        addon:info(L.LogRaidSetCurrent:format(sel, tostring(raid.zone), raidSize))
        return true
    end

    -- Upsert boss kill (edit if bossNid provided, otherwise append new boss kill).
    -- Returns bossNid on success, nil on failure.
    function Actions:UpsertBossKill(rID, bossNid, name, ts, mode)
        local raid = Store:GetRaid(rID)
        if not raid then return nil end

        name = Utils.trimText(name or "")
        mode = Utils.normalizeLower(mode or "n")
        ts = tonumber(ts) or time()

        if bossNid then
            local bossKill = Store:GetBoss(raid, bossNid)
            if not bossKill then
                addon:error(L.ErrAttendeesInvalidRaidBoss)
                return nil
            end
            bossKill.name = name
            bossKill.time = ts
            bossKill.mode = (mode == "h") and "h" or "n"
            -- keep existing players/hash; hash is stable per nid
            self:Commit(raid, { invalidate = false })
            return bossKill.bossNid
        end

        local newNid = tonumber(raid.nextBossNid) or 1
        raid.nextBossNid = newNid + 1

        tinsert(raid.bossKills, {
            bossNid = newNid,
            name = name,
            time = ts,
            mode = (mode == "h") and "h" or "n",
            players = {},
            hash = Utils.encode(rID .. "|" .. name .. "|" .. newNid),
        })

        self:Commit(raid)
        return newNid
    end

    -- Add existing raid player to the selected boss attendees list.
    -- nameRaw is matched (case-insensitive) against raid.players[].name.
    function Actions:AddBossAttendee(rID, bossNid, nameRaw)
        local name = Utils.trimText(nameRaw or "")
        local normalizedName = Utils.normalizeLower(name)
        if normalizedName == "" then
            addon:error(L.ErrAttendeesInvalidName)
            return false
        end

        local raid = (rID and bossNid) and Store:GetRaid(rID) or nil
        if not (raid and bossNid) then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return false
        end

        local bossKill = Store:GetBoss(raid, bossNid)
        if not bossKill then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return false
        end

        bossKill.players = bossKill.players or {}
        for _, n in ipairs(bossKill.players) do
            if Utils.normalizeLower(n) == normalizedName then
                addon:error(L.ErrAttendeesPlayerExists)
                return false
            end
        end

        local playerName = Store:FindRaidPlayerByNormName(raid, normalizedName)
        if playerName then
            tinsert(bossKill.players, playerName)
            addon:info(L.StrAttendeesAddSuccess)
            self:Commit(raid, { invalidate = false })
            return true
        end

        addon:error(L.ErrAttendeesInvalidName)
        return false
    end

    module.selectedRaid = nil
    module.selectedBoss = nil
    module.selectedPlayer = nil
    module.selectedBossPlayer = nil
    module.selectedItem = nil

    -- Multi-select context keys (runtime-only)
    -- NOTE: selection state lives in Utils.lua and is keyed by these context strings.
    module._msRaidCtx = module._msRaidCtx or "LoggerRaids"
    module._msBossCtx = module._msBossCtx or "LoggerBosses"
    module._msBossAttCtx = module._msBossAttCtx or "LoggerBossAttendees"
    module._msRaidAttCtx = module._msRaidAttCtx or "LoggerRaidAttendees"
    module._msLootCtx = module._msLootCtx or "LoggerLoot"

    local MS_CTX_RAID = module._msRaidCtx
    local MS_CTX_BOSS = module._msBossCtx
    local MS_CTX_BOSSATT = module._msBossAttCtx
    local MS_CTX_RAIDATT = module._msRaidAttCtx
    local MS_CTX_LOOT = module._msLootCtx

    -- Clears selections that depend on the currently focused raid (boss/player/loot panels).
    -- Intentionally does NOT clear the raid selection itself.
    local function clearSelections()
        module.selectedBoss = nil
        module.selectedPlayer = nil
        module.selectedBossPlayer = nil
        module.selectedItem = nil
        Utils.multiSelectClear(MS_CTX_BOSS)
        Utils.multiSelectClear(MS_CTX_BOSSATT)
        Utils.multiSelectClear(MS_CTX_RAIDATT)
        Utils.multiSelectClear(MS_CTX_LOOT)
    end

    -- Logger helpers: resolve current raid/boss/loot and run raid actions with a single refresh.
    function module:NeedRaid()
        local rID = module.selectedRaid
        local raid = rID and Store:GetRaid(rID) or nil
        return raid, rID
    end

    function module:NeedBoss(raid)
        raid = raid or (select(1, module:NeedRaid()))
        if not raid then return nil end
        local bNid = module.selectedBoss
        if not bNid then return nil end
        return Store:GetBoss(raid, bNid)
    end

    function module:NeedLoot(raid)
        raid = raid or (select(1, module:NeedRaid()))
        if not raid then return nil end
        local lNid = module.selectedItem
        if not lNid then return nil end
        return Store:GetLoot(raid, lNid)
    end

    function module:Run(fn, refreshEvent)
        local raid, rID = module:NeedRaid()
        if not raid then return end
        fn(raid, rID)
        if refreshEvent ~= false then
            Utils.triggerEvent(refreshEvent or "LoggerSelectRaid", module.selectedRaid)
        end
    end

    function module:ResetSelections()
        clearSelections()
    end

    function module:OnLoad(frame)
        if not frame then return end
        module.frame = frame
        frameName = frame:GetName()
        Utils.setFrameTitle(frameName, L.StrLootLogger)

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        frame:SetScript("OnShow", function()
            if not module.selectedRaid then
                module.selectedRaid = KRT_CurrentRaid
            end
            clearSelections()
            Utils.triggerEvent("LoggerSelectRaid", module.selectedRaid)
        end)

        frame:SetScript("OnHide", function()
            module.selectedRaid = KRT_CurrentRaid
            clearSelections()
        end)
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    function module:Hide()
        module.selectedRaid = KRT_CurrentRaid
        clearSelections()
        return uiController:Hide()
    end

    function module:Refresh()
        local frame = getFrame()
        if not frame then return end
        if not module.selectedRaid then
            module.selectedRaid = KRT_CurrentRaid
        end
        clearSelections()
        Utils.triggerEvent("LoggerSelectRaid", module.selectedRaid)
    end

    bindModuleRequestRefresh(module, getFrame)

    -- Selectors
    function module:SelectRaid(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedRaid

        local action, count
        if isRange then
            local ordered = addon.Logger.Raids and addon.Logger.Raids._ctrl and addon.Logger.Raids._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_RAID, ordered, id, isMulti)
            -- SHIFT range always sets the focused row to the click target.
            module.selectedRaid = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_RAID, id, isMulti, true)

            -- Keep a single "focused" raid for the dependent panels (Boss / Attendees / Loot).
            if action == "SINGLE_DESELECT" then
                module.selectedRaid = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedRaid == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_RAID)
                    module.selectedRaid = sel[1] or nil
                end
            else
                module.selectedRaid = id
            end

            -- Range anchor (OS-like): update on non-shift clicks only.
            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_RAID, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_RAID, nil)
            end
        end

        if addon and addon.options and addon.options.debug and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickRaid)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedRaid)
                ))
        end

        -- If the focused raid changed, reset dependent selections (boss/player/loot panels).
        if prevFocus ~= module.selectedRaid then
            clearSelections()
        end

        Utils.triggerEvent("LoggerSelectRaid", module.selectedRaid)
    end

    function module:SelectBoss(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedBoss

        local action, count
        if isRange then
            local ordered = addon.Logger.Boss and addon.Logger.Boss._ctrl and addon.Logger.Boss._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_BOSS, ordered, id, isMulti)
            module.selectedBoss = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_BOSS, id, isMulti, true)

            -- Keep a single "focused" boss for dependent panels (BossAttendees / Loot).
            if action == "SINGLE_DESELECT" then
                module.selectedBoss = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedBoss == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_BOSS)
                    module.selectedBoss = sel[1] or nil
                end
            else
                module.selectedBoss = id
            end

            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_BOSS, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_BOSS, nil)
            end
        end

        if addon and addon.options and addon.options.debug and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickBoss)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedBoss)
                ))
        end

        -- If the focused boss changed, reset boss-attendees + loot selection (filters changed).
        if prevFocus ~= module.selectedBoss then
            module.selectedBossPlayer = nil
            Utils.multiSelectClear(MS_CTX_BOSSATT)

            module.selectedItem = nil
            Utils.multiSelectClear(MS_CTX_LOOT)

            Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
            Utils.triggerEvent("LoggerSelectBossPlayer", module.selectedBossPlayer)
        end

        Utils.triggerEvent("LoggerSelectBoss", module.selectedBoss)
    end

    -- Player filter: only one active at a time
    function module:SelectBossPlayer(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedBossPlayer

        -- Mutual exclusion: selecting a boss-attendee filter clears the raid-attendee filter (and its multi-select).
        module.selectedPlayer = nil
        Utils.multiSelectClear(MS_CTX_RAIDATT)

        local action, count
        if isRange then
            local ordered = addon.Logger.BossAttendees and addon.Logger.BossAttendees._ctrl and
                addon.Logger.BossAttendees._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_BOSSATT, ordered, id, isMulti)
            module.selectedBossPlayer = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_BOSSATT, id, isMulti, true)

            -- Keep a single "focused" boss-attendee for loot filtering.
            if action == "SINGLE_DESELECT" then
                module.selectedBossPlayer = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedBossPlayer == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_BOSSATT)
                    module.selectedBossPlayer = sel[1] or nil
                end
            else
                module.selectedBossPlayer = id
            end

            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_BOSSATT, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_BOSSATT, nil)
            end
        end

        if addon and addon.options and addon.options.debug and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickBossAttendees)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedBossPlayer)
                ))
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedBossPlayer then
            module.selectedItem = nil
            Utils.multiSelectClear(MS_CTX_LOOT)
            Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
        end

        Utils.triggerEvent("LoggerSelectBossPlayer", module.selectedBossPlayer)
        Utils.triggerEvent("LoggerSelectPlayer", module.selectedPlayer)
    end

    function module:SelectPlayer(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedPlayer

        -- Mutual exclusion: selecting a raid-attendee filter clears the boss-attendee filter (and its multi-select).
        module.selectedBossPlayer = nil
        Utils.multiSelectClear(MS_CTX_BOSSATT)

        local action, count
        if isRange then
            local ordered = addon.Logger.RaidAttendees and addon.Logger.RaidAttendees._ctrl and
                addon.Logger.RaidAttendees._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_RAIDATT, ordered, id, isMulti)
            module.selectedPlayer = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_RAIDATT, id, isMulti, true)

            -- Keep a single "focused" raid-attendee for loot filtering.
            if action == "SINGLE_DESELECT" then
                module.selectedPlayer = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedPlayer == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_RAIDATT)
                    module.selectedPlayer = sel[1] or nil
                end
            else
                module.selectedPlayer = id
            end

            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_RAIDATT, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_RAIDATT, nil)
            end
        end

        if addon and addon.options and addon.options.debug and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickRaidAttendees)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedPlayer)
                ))
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedPlayer then
            module.selectedItem = nil
            Utils.multiSelectClear(MS_CTX_LOOT)
            Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
        end

        Utils.triggerEvent("LoggerSelectPlayer", module.selectedPlayer)
        Utils.triggerEvent("LoggerSelectBossPlayer", module.selectedBossPlayer)
    end

    -- Item: left select, right menu
    do
        local function openItemMenu()
            local f = _G.KRTLoggerItemMenuFrame
                or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")

            EasyMenu({
                { text = L.StrEditItemLooter,    func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER") end },
                { text = L.StrEditItemRollType,  func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_ROLL") end },
                { text = L.StrEditItemRollValue, func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE") end },
            }, f, "cursor", 0, 0, "MENU")
        end

        function module:SelectItem(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then return end

            -- NOTE: Multi-select is maintained in Utils.lua (context = MS_CTX_LOOT).
            if button == "LeftButton" then
                local isMulti = IsControlKeyDown and IsControlKeyDown() or false
                local isRange = IsShiftKeyDown and IsShiftKeyDown() or false

                local action, count
                if isRange then
                    local ordered = addon.Logger.Loot and addon.Logger.Loot._ctrl and addon.Logger.Loot._ctrl.data or nil
                    action, count = Utils.multiSelectRange(MS_CTX_LOOT, ordered, id, isMulti)
                    module.selectedItem = id
                else
                    action, count = Utils.multiSelectToggle(MS_CTX_LOOT, id, isMulti, true)

                    -- Keep a single "focused" item for context menu / edit popups.
                    if action == "SINGLE_DESELECT" then
                        module.selectedItem = nil
                    elseif action == "TOGGLE_OFF" then
                        if module.selectedItem == id then
                            local sel = Utils.multiSelectGetSelected(MS_CTX_LOOT)
                            module.selectedItem = sel[1] or nil
                        end
                        -- If we toggled OFF a non-focused item, keep current focus.
                    else
                        module.selectedItem = id
                    end

                    if (tonumber(count) or 0) > 0 then
                        Utils.multiSelectSetAnchor(MS_CTX_LOOT, id)
                    else
                        Utils.multiSelectSetAnchor(MS_CTX_LOOT, nil)
                    end
                end

                if addon and addon.options and addon.options.debug and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickLoot)
                        :format(
                            tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                            tostring(module.selectedItem)
                        ))
                end

                Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
            elseif button == "RightButton" then
                -- Context menu works on a single focused row.
                local action, count = Utils.multiSelectToggle(MS_CTX_LOOT, id, false)
                module.selectedItem = id

                if addon and addon.options and addon.options.debug and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickContextMenu):format(
                        tostring(id), tostring(action), tonumber(count) or 0
                    ))
                end

                Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
                openItemMenu()
            end
        end

        -- Hover sync: keep selection highlight persistent, while leaving hover highlight to the default Button highlight.
        function module:OnLootRowEnter(row)
            -- No-op: persistent selection is rendered via overlay textures (Utils.setRowSelected/Focused).
            -- Leave native hover highlight behavior intact.
        end

        function module:OnLootRowLeave(row)
            -- No-op: persistent selection is rendered via overlay textures.
        end

        local function findLoggerPlayer(normalizedName, raid, bossKill)
            if raid and raid.players then
                for _, p in ipairs(raid.players) do
                    if normalizedName == Utils.normalizeLower(p.name) then
                        return p.name
                    end
                end
            end
            if bossKill and bossKill.players then
                for _, name in ipairs(bossKill.players) do
                    if normalizedName == Utils.normalizeLower(name) then
                        return name
                    end
                end
            end
        end

        local function isValidRollType(rollType)
            for _, value in pairs(rollTypes) do
                if rollType == value then
                    return true
                end
            end
            return false
        end

        local function validateRollType(_, text)
            local value = text and tonumber(text)
            if not value or not isValidRollType(value) then
                addon:error(L.ErrLoggerInvalidRollType)
                return false
            end
            return true, value
        end

        local function validateRollValue(_, text)
            local value = text and tonumber(text)
            if not value or value < 0 then
                addon:error(L.ErrLoggerInvalidRollValue)
                return false
            end
            return true, value
        end

        Utils.makeEditBoxPopup("KRTLOGGER_ITEM_EDIT_WINNER", L.StrEditItemLooterHelp,
            function(self, text)
                local rawText = Utils.trimText(text)
                local name = Utils.normalizeLower(rawText)
                if not name or name == "" then
                    addon:error(L.ErrLoggerWinnerEmpty)
                    return
                end
                local raid = Store:GetRaid(self.raidId)
                if not raid then
                    addon:error(L.ErrLoggerInvalidRaid)
                    return
                end

                local loot = Store:GetLoot(raid, self.itemId)
                if not loot then
                    addon:error(L.ErrLoggerInvalidItem)
                    return
                end

                local bossKill = (loot.bossNid and raid) and Store:GetBoss(raid, loot.bossNid) or nil
                local winner = findLoggerPlayer(name, raid, bossKill)
                if not winner then
                    addon:error(L.ErrLoggerWinnerNotFound:format(rawText))
                    return
                end

                addon.Logger.Loot:Log(self.itemId, winner, nil, nil, "LOGGER_EDIT_WINNER")
            end,
            function(self)
                self.raidId = addon.Logger.selectedRaid
                self.itemId = addon.Logger.selectedItem
            end
        )

        Utils.makeEditBoxPopup("KRTLOGGER_ITEM_EDIT_ROLL", L.StrEditItemRollTypeHelp,
            function(self, text)
                addon.Logger.Loot:Log(self.itemId, nil, text, nil, "LOGGER_EDIT_ROLLTYPE")
            end,
            function(self) self.itemId = addon.Logger.selectedItem end,
            validateRollType
        )

        Utils.makeEditBoxPopup("KRTLOGGER_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp,
            function(self, text)
                addon.Logger.Loot:Log(self.itemId, nil, nil, text, "LOGGER_EDIT_ROLLVALUE")
            end,
            function(self) self.itemId = addon.Logger.selectedItem end,
            validateRollValue
        )
    end
end

-- Raids List
do
    addon.Logger.Raids = addon.Logger.Raids or {}
    local Raids = addon.Logger.Raids
    local controller = Utils.makeListController {
        keyName = "RaidsList",
        poolTag = "logger-raids",
        _rowParts = { "ID", "Date", "Zone", "Size" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidsList) end
            _G[n .. "HeaderNum"]:SetText(L.StrNumber)
            _G[n .. "HeaderDate"]:SetText(L.StrDate)
            _G[n .. "HeaderZone"]:SetText(L.StrZone)
            _G[n .. "HeaderSize"]:SetText(L.StrSize)
            _G[n .. "CurrentBtn"]:SetText(L.StrSetCurrent)
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
            addon:SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)
            _G[n .. "ExportBtn"]:Disable() -- non implementato
        end,

        getData = function(out)
            for i = 1, #KRT_Raids do
                local r = KRT_Raids[i]
                local it = {}
                it.id = i
                it.zone = r.zone
                it.size = r.size
                it.difficulty = tonumber(r.difficulty)
                local mode = it.difficulty and ((it.difficulty == 3 or it.difficulty == 4) and "H" or "N") or "?"
                it.sizeLabel = tostring(it.size or "") .. mode
                it.date = r.startTime
                it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "RaidBtn" .. i end,
        rowTmpl = "KRTLoggerRaidButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.ID:SetText(it.seq or it.id)
            ui.Date:SetText(it.dateFmt)
            ui.Zone:SetText(it.zone)
            ui.Size:SetText(it.sizeLabel or it.size)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msRaidCtx, id) end,
        focusId = function() return addon.Logger.selectedRaid end,
        focusKey = function() return tostring(addon.Logger.selectedRaid or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msRaidCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msRaidCtx),
                Utils.multiSelectCount(addon.Logger._msRaidCtx))
        end,

        postUpdate = function(n)
            local sel = addon.Logger.selectedRaid
            local raid = sel and KRT_Raids[sel] or nil

            local canSetCurrent = false
            if sel and raid and sel ~= KRT_CurrentRaid then
                -- This button is intended to resolve duplicate raid creation while actively raiding.
                if not addon.IsInRaid() then
                    canSetCurrent = false
                elseif addon.Raid:Expired(sel) then
                    canSetCurrent = false
                else
                    local instanceName, instanceType, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
                    if isDyn then
                        instanceDiff = instanceDiff + (2 * dynDiff)
                    end
                    if instanceType == "raid" then
                        local raidSize = tonumber(raid.size)
                        local groupSize = addon.Raid:GetRaidSize()
                        local zoneOk = (not raid.zone) or (raid.zone == instanceName)
                        local raidDiff = tonumber(raid.difficulty)
                        local curDiff = tonumber(instanceDiff)
                        local diffOk = raidDiff and curDiff and (raidDiff == curDiff)
                        canSetCurrent = zoneOk and raidSize and (raidSize == groupSize) and diffOk
                    end
                end
            end

            Utils.enableDisable(_G[n .. "CurrentBtn"], canSetCurrent)

            local ctx = addon.Logger._msRaidCtx
            local selCount = Utils.multiSelectCount(ctx)
            local canDelete = (selCount and selCount > 0) or false
            if canDelete and KRT_CurrentRaid then
                local ids = Utils.multiSelectGetSelected(ctx)
                for i = 1, #ids do
                    if tonumber(ids[i]) == tonumber(KRT_CurrentRaid) then
                        canDelete = false
                        break
                    end
                end
            end
            local delBtn = _G[n .. "DeleteBtn"]
            Utils.setButtonCount(delBtn, L.BtnDelete, selCount)
            Utils.enableDisable(delBtn, canDelete)
        end,

        sorters = {
            id = function(a, b, asc)
                return asc and ((a.seq or a.id) < (b.seq or b.id)) or
                    ((a.seq or a.id) > (b.seq or b.id))
            end,
            date = function(a, b, asc) return asc and (a.date < b.date) or (a.date > b.date) end,
            zone = function(a, b, asc) return asc and (a.zone < b.zone) or (a.zone > b.zone) end,
            size = function(a, b, asc) return asc and (a.size < b.size) or (a.size > b.size) end,
        },
    }

    Raids._ctrl = controller
    Utils.bindListController(Raids, controller)

    function Raids:SetCurrent(btn)
        if not btn then return end
        local sel = addon.Logger.selectedRaid
        if not sel then return end
        if addon.Logger.Actions:SetCurrentRaid(sel) then
            -- Context change: clear dependent selections and redraw all module panels.
            addon.Logger.selectedRaid = sel
            addon.Logger:ResetSelections()
            Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
        end
    end

    do
        local function DeleteRaids()
            local ctx = addon.Logger._msRaidCtx
            local ids = Utils.multiSelectGetSelected(ctx)
            if not (ids and #ids > 0) then return end

            -- Safety: never delete the current raid
            if KRT_CurrentRaid then
                for i = 1, #ids do
                    if tonumber(ids[i]) == tonumber(KRT_CurrentRaid) then
                        return
                    end
                end
            end

            -- Deleting by index: sort descending to avoid shifting issues.
            table.sort(ids, function(a, b) return (tonumber(a) or a) > (tonumber(b) or b) end)

            local prevFocus = addon.Logger.selectedRaid
            local removed = 0
            for i = 1, #ids do
                if addon.Logger.Actions:DeleteRaid(ids[i]) then
                    removed = removed + 1
                end
            end

            Utils.multiSelectClear(ctx)

            local n = KRT_Raids and #KRT_Raids or 0
            local newFocus = nil
            if n > 0 then
                local base = tonumber(prevFocus) or n
                if base > n then base = n end
                if base < 1 then base = 1 end
                newFocus = base
            end

            addon.Logger.selectedRaid = newFocus
            addon.Logger:ResetSelections()
            controller:Dirty()
            Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
        end

        function Raids:Delete(btn)
            local ctx = addon.Logger._msRaidCtx
            if btn and Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaids)
    end

    Utils.registerCallback("RaidCreate", function(_, num)
        -- Context change: selecting a different raid must clear dependent selections.
        addon.Logger.selectedRaid = tonumber(num)
        addon.Logger:ResetSelections()
        controller:Dirty()
        Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
    end)

    Utils.registerCallback("LoggerSelectRaid", function() controller:Touch() end)
end

-- Boss List
do
    addon.Logger.Boss = addon.Logger.Boss or {}
    local Boss = addon.Logger.Boss
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "BossList",
        poolTag = "logger-bosses",
        _rowParts = { "ID", "Name", "Time", "Mode" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBosses) end
            _G[n .. "HeaderNum"]:SetText(L.StrNumber)
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
            _G[n .. "HeaderMode"]:SetText(L.StrMode)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
            _G[n .. "DeleteBtn"]:SetText(L.BtnDelete)
        end,

        getData = function(out)
            local raid = addon.Logger:NeedRaid()
            if not raid then return end
            View:FillBossList(out, raid)
        end,

        rowName = function(n, _, i) return n .. "BossBtn" .. i end,
        rowTmpl = "KRTLoggerBossButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            -- Display a sequential number that rescales after deletions.
            -- Keep it.id as the stable bossNid for selection/highlight.
            ui.ID:SetText(it.seq)
            ui.Name:SetText(it.name)
            ui.Time:SetText(it.timeFmt)
            ui.Mode:SetText(it.mode)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msBossCtx, id) end,
        focusId = function() return addon.Logger.selectedBoss end,
        focusKey = function() return tostring(addon.Logger.selectedBoss or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msBossCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msBossCtx),
                Utils.multiSelectCount(addon.Logger._msBossCtx))
        end,

        postUpdate = function(n)
            local hasRaid = addon.Logger.selectedRaid
            local hasBoss = addon.Logger.selectedBoss
            Utils.enableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            Utils.enableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            local bossSelCount = Utils.multiSelectCount(addon.Logger._msBossCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            Utils.setButtonCount(delBtn, L.BtnDelete, bossSelCount)
            Utils.enableDisable(delBtn, (bossSelCount and bossSelCount > 0) or false)
        end,

        sorters = {
            -- Sort by the displayed sequential number, not the stable nid.
            id = function(a, b, asc) return asc and (a.seq < b.seq) or (a.seq > b.seq) end,
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
            mode = function(a, b, asc) return asc and (a.mode < b.mode) or (a.mode > b.mode) end,
        },
    }

    Boss._ctrl = controller
    Utils.bindListController(Boss, controller)

    function Boss:Add() addon.Logger.BossBox:Toggle() end

    function Boss:Edit() if addon.Logger.selectedBoss then addon.Logger.BossBox:Fill() end end

    do
        local function DeleteBosses()
            addon.Logger:Run(function(_, rID)
                local ctx = addon.Logger._msBossCtx
                local ids = Utils.multiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then return end

                for i = 1, #ids do
                    local bNid = ids[i]
                    local lootRemoved = Actions:DeleteBoss(rID, bNid)
                    addon:debug(Diag.D.LogLoggerBossLootRemoved, rID, tonumber(bNid) or -1, lootRemoved)
                end

                -- Clear boss-related selections (filters changed / deleted)
                Utils.multiSelectClear(ctx)
                addon.Logger.selectedBoss = nil

                addon.Logger.selectedBossPlayer = nil
                Utils.multiSelectClear(addon.Logger._msBossAttCtx)

                addon.Logger.selectedItem = nil
                Utils.multiSelectClear(addon.Logger._msLootCtx)
            end)
        end

        function Boss:Delete()
            local ctx = addon.Logger._msBossCtx
            if Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBosses)
    end

    function Boss:GetName(bossNid, raidId)
        local rID = raidId or addon.Logger.selectedRaid
        if not rID or not KRT_Raids[rID] then return "" end
        bossNid = bossNid or addon.Logger.selectedBoss
        if not bossNid then return "" end

        local raid = Store:GetRaid(rID)
        local boss = raid and Store:GetBoss(raid, bossNid) or nil
        return boss and boss.name or ""
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBoss", function() controller:Touch() end)
end

-- Boss Attendees List
do
    addon.Logger.BossAttendees = addon.Logger.BossAttendees or {}
    local BossAtt = addon.Logger.BossAttendees
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBossAttendees) end
            local add = _G[n .. "AddBtn"]; if add then add:SetText(L.BtnAdd) end
            local rm = _G[n .. "RemoveBtn"]; if rm then rm:SetText(L.BtnRemove) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            local bID = addon.Logger.selectedBoss
            local raid = (rID and bID) and Store:GetRaid(rID) or nil
            if not (raid and bID) then return end
            View:FillBossAttendeesList(out, raid, bID)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerBossAttendeeButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            local r, g, b = Utils.getClassColor(it.class)
            ui.Name:SetText(it.name)
            ui.Name:SetVertexColor(r, g, b)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msBossAttCtx, id) end,
        focusId = function() return addon.Logger.selectedBossPlayer end,
        focusKey = function() return tostring(addon.Logger.selectedBossPlayer or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msBossAttCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msBossAttCtx),
                Utils.multiSelectCount(addon.Logger._msBossAttCtx))
        end,

        postUpdate = function(n)
            local bSel = addon.Logger.selectedBoss
            local pSel = addon.Logger.selectedBossPlayer
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            local attSelCount = Utils.multiSelectCount(addon.Logger._msBossAttCtx)
            if addBtn then
                Utils.enableDisable(addBtn, bSel and ((attSelCount or 0) == 0))
            end
            if removeBtn then
                Utils.setButtonCount(removeBtn, L.BtnRemove, attSelCount)
                Utils.enableDisable(removeBtn, bSel and ((attSelCount or 0) > 0))
            end
        end,

        sorters = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
        },
    }

    BossAtt._ctrl = controller
    Utils.bindListController(BossAtt, controller)

    function BossAtt:Add() addon.Logger.AttendeesBox:Toggle() end

    do
        local function DeleteAttendees()
            addon.Logger:Run(function(_, rID)
                local bNid = addon.Logger.selectedBoss
                local ctx = addon.Logger._msBossAttCtx
                local ids = Utils.multiSelectGetSelected(ctx)
                if not (bNid and ids and #ids > 0) then return end

                for i = 1, #ids do
                    Actions:DeleteBossAttendee(rID, bNid, ids[i])
                end

                Utils.multiSelectClear(ctx)
                addon.Logger.selectedBossPlayer = nil
            end)
        end

        function BossAtt:Delete()
            local ctx = addon.Logger._msBossAttCtx
            if Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendees)
    end

    Utils.registerCallbacks({ "LoggerSelectRaid", "LoggerSelectBoss" }, function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBossPlayer", function() controller:Touch() end)
end

-- Raid Attendees List
do
    addon.Logger.RaidAttendees = addon.Logger.RaidAttendees or {}
    local RaidAtt = addon.Logger.RaidAttendees
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "RaidAttendeesList",
        poolTag = "logger-raid-attendees",
        _rowParts = { "Name", "Join", "Leave" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidAttendees) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                addBtn:SetText(L.BtnUpdate)
                local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
                addBtn:Disable() -- enabled in postUpdate when applicable
            end
        end,

        getData = function(out)
            local raid = addon.Logger:NeedRaid()
            if not raid then return end
            View:FillRaidAttendeesList(out, raid)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerRaidAttendeeButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.Name:SetText(it.name)
            local r, g, b = Utils.getClassColor(it.class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Join:SetText(it.joinFmt)
            ui.Leave:SetText(it.leaveFmt)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msRaidAttCtx, id) end,
        focusId = function() return addon.Logger.selectedPlayer end,
        focusKey = function() return tostring(addon.Logger.selectedPlayer or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msRaidAttCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msRaidAttCtx),
                Utils.multiSelectCount(addon.Logger._msRaidAttCtx))
        end,

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            if deleteBtn then
                local attSelCount = Utils.multiSelectCount(addon.Logger._msRaidAttCtx)
                Utils.setButtonCount(deleteBtn, L.BtnDelete, attSelCount)
                Utils.enableDisable(deleteBtn, (attSelCount and attSelCount > 0) or false)
            end

            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                -- Update is only meaningful for the current raid session while actively raiding.
                local can = addon.IsInRaid() and KRT_CurrentRaid and addon.Logger.selectedRaid
                    and (tonumber(KRT_CurrentRaid) == tonumber(addon.Logger.selectedRaid))
                Utils.enableDisable(addBtn, can)
            end
        end,

        sorters = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            join = function(a, b, asc) return asc and (a.join < b.join) or (a.join > b.join) end,
            leave = function(a, b, asc)
                local A = a.leave or (asc and math.huge or -math.huge)
                local B = b.leave or (asc and math.huge or -math.huge)
                return asc and (A < B) or (A > B)
            end,
        },
    }

    RaidAtt._ctrl = controller
    Utils.bindListController(RaidAtt, controller)

    -- Update raid roster from the live in-game raid roster (current raid only).
    -- Bound to the "Add" button in the RaidAttendees frame (repurposed as Update).
    function RaidAtt:Add()
        addon.Logger:Run(function(_, rID)
            local sel = tonumber(rID)
            if not sel then return end

            if not addon.IsInRaid() then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotInRaid)
                return
            end

            if not (KRT_CurrentRaid and tonumber(KRT_CurrentRaid) == sel) then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotCurrent)
                return
            end

            -- Update the roster from the live in-game raid roster.
            addon.Raid:UpdateRaidRoster()

            -- Clear selections that depend on raid.players indices.
            Utils.multiSelectClear(addon.Logger._msRaidAttCtx)
            Utils.multiSelectClear(addon.Logger._msBossAttCtx)
            Utils.multiSelectClear(addon.Logger._msLootCtx)
            addon.Logger.selectedPlayer = nil
            addon.Logger.selectedBossPlayer = nil
            addon.Logger.selectedItem = nil

            controller:Dirty()
        end)
    end

    do
        local function DeleteAttendees()
            addon.Logger:Run(function(_, rID)
                local ctx = addon.Logger._msRaidAttCtx
                local ids = Utils.multiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then return end

                local removed = Actions:DeleteRaidAttendeeMany(rID, ids)
                if removed and removed > 0 then
                    Utils.multiSelectClear(ctx)
                    addon.Logger.selectedPlayer = nil

                    -- Indices shifted: clear boss-attendees selection too (it is indexed by raid.players).
                    addon.Logger.selectedBossPlayer = nil
                    Utils.multiSelectClear(addon.Logger._msBossAttCtx)

                    -- Filters changed: reset loot selection.
                    addon.Logger.selectedItem = nil
                    Utils.multiSelectClear(addon.Logger._msLootCtx)
                end
            end)
        end

        function RaidAtt:Delete()
            local ctx = addon.Logger._msRaidAttCtx
            if Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendees)
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectPlayer", function() controller:Touch() end)
end

-- Loot List (filters by selected boss and player)
do
    addon.Logger.Loot = addon.Logger.Loot or {}
    local Loot = addon.Logger.Loot
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidLoot) end
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            _G[n .. "ClearBtn"]:SetText(L.BtnClear)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            _G[n .. "HeaderItem"]:SetText(L.StrItem)
            _G[n .. "HeaderSource"]:SetText(L.StrSource)
            _G[n .. "HeaderWinner"]:SetText(L.StrWinner)
            _G[n .. "HeaderType"]:SetText(L.StrType)
            _G[n .. "HeaderRoll"]:SetText(L.StrRoll)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)

            -- Disabled until implemented
            _G[n .. "ExportBtn"]:Disable()
            _G[n .. "ClearBtn"]:Disable()
            _G[n .. "AddBtn"]:Disable()
            local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
            _G[n .. "EditBtn"]:Disable()
        end,

        getData = function(out)
            local raid = addon.Logger:NeedRaid()
            if not raid then return end

            local bID = addon.Logger.selectedBoss
            local pID = addon.Logger.selectedBossPlayer or addon.Logger.selectedPlayer
            local pName = (pID and raid.players and raid.players[pID] and raid.players[pID].name) or nil

            View:FillLootList(out, raid, bID, pName)
        end,

        rowName = function(n, _, i) return n .. "ItemBtn" .. i end,
        rowTmpl = "KRTLoggerLootButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            -- Preserve the original item link on the row for tooltips.
            row._itemLink = it.itemLink
            local nameText = it.itemLink or it.itemName or ("[Item " .. (it.itemId or "?") .. "]")
            if it.itemLink then
                ui.Name:SetText(nameText)
            else
                ui.Name:SetText(addon.WrapTextInColorCode(
                    nameText,
                    Utils.normalizeHexColor(itemColors[(it.itemRarity or 1) + 1])
                ))
            end

            local selectedBoss = addon.Logger.selectedBoss
            if selectedBoss and tonumber(it.bossNid) == tonumber(selectedBoss) then
                ui.Source:SetText("")
            else
                ui.Source:SetText(addon.Logger.Boss:GetName(it.bossNid, addon.Logger.selectedRaid))
            end

            local r, g, b = Utils.getClassColor(addon.Raid:GetPlayerClass(it.looter))
            ui.Winner:SetText(it.looter)
            ui.Winner:SetVertexColor(r, g, b)

            local rt = tonumber(it.rollType) or 0
            it.rollType = rt
            ui.Type:SetText(lootTypesColored[rt] or lootTypesColored[4])
            ui.Roll:SetText(it.rollValue or 0)
            ui.Time:SetText(it.timeFmt)

            local icon = it.itemTexture
            if not icon and it.itemId then
                icon = GetItemIcon(it.itemId)
            end
            if not icon then
                icon = C.RESERVES_ITEM_FALLBACK_ICON
            end
            ui.ItemIconTexture:SetTexture(icon)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msLootCtx, id) end,
        focusId = function() return addon.Logger.selectedItem end,
        focusKey = function() return tostring(addon.Logger.selectedItem or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msLootCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msLootCtx),
                Utils.multiSelectCount(addon.Logger._msLootCtx))
        end,

        postUpdate = function(n)
            local lootSelCount = Utils.multiSelectCount(addon.Logger._msLootCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            Utils.setButtonCount(delBtn, L.BtnDelete, lootSelCount)
            Utils.enableDisable(delBtn, (lootSelCount or 0) > 0)
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
            source = function(a, b, asc)
                return asc and ((tonumber(a.bossNid) or 0) < (tonumber(b.bossNid) or 0)) or
                    ((tonumber(a.bossNid) or 0) > (tonumber(b.bossNid) or 0))
            end,
            winner = function(a, b, asc) return asc and (a.looter < b.looter) or (a.looter > b.looter) end,
            type = function(a, b, asc) return asc and (a.rollType < b.rollType) or (a.rollType > b.rollType) end,
            roll = function(a, b, asc)
                local A = a.rollValue or 0
                local B = b.rollValue or 0
                return asc and (A < B) or (A > B)
            end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
        },
    }

    Loot._ctrl = controller
    Utils.bindListController(Loot, controller)

    function Loot:OnEnter(widget)
        if not widget then return end
        local row = (widget.IsObjectType and widget:IsObjectType("Button")) and widget
            or (widget.GetParent and widget:GetParent()) or widget
        if not (row and row.GetID) then return end

        local link = row._itemLink
        if not link then return end

        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
    end

    do
        local function DeleteItem()
            addon.Logger:Run(function(_, rID)
                local ctx = addon.Logger._msLootCtx
                local selected = Utils.multiSelectGetSelected(ctx)
                if not selected or #selected == 0 then return end

                local removed = Actions:DeleteLootMany(rID, selected)
                if removed > 0 then
                    Utils.multiSelectClear(ctx)
                    addon.Logger.selectedItem = nil
                    Utils.triggerEvent("LoggerSelectItem", addon.Logger.selectedItem)

                    if addon and addon.options and addon.options.debug and addon.debug then
                        addon:debug((Diag.D.LogLoggerSelectDeleteItems):format(removed))
                    end
                end
            end)
        end

        function Loot:Delete()
            if Utils.multiSelectCount(addon.Logger._msLootCtx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ITEM")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ITEM", L.StrConfirmDeleteItem, DeleteItem)
    end

    function Loot:Log(itemID, looter, rollType, rollValue, source, raidIDOverride)
        local raidID
        if raidIDOverride then
            raidID = raidIDOverride
        else
            -- If the module window is open and browsing an old raid, selectedRaid may differ from KRT_CurrentRaid.
            -- Runtime sources must always write into the CURRENT raid session, while module UI edits target selectedRaid.
            local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
            if isLoggerSource then
                raidID = addon.Logger.selectedRaid or KRT_CurrentRaid
            else
                raidID = KRT_CurrentRaid or addon.Logger.selectedRaid
            end
        end
        addon:trace(Diag.D.LogLoggerLootLogAttempt:format(tostring(source), tostring(raidID), tostring(itemID),
            tostring(looter), tostring(rollType), tostring(rollValue), tostring(KRT_LastBoss)))
        if not raidID or not KRT_Raids[raidID] then
            addon:error(Diag.E.LogLoggerNoRaidSession:format(tostring(raidID), tostring(itemID)))
            return false
        end

        local raid = KRT_Raids[raidID]
        Store:EnsureRaid(raid)
        local lootCount = raid.loot and #raid.loot or 0
        local it = Store:GetLoot(raid, itemID)
        if not it then
            addon:error(Diag.E.LogLoggerItemNotFound:format(raidID, tostring(itemID), lootCount))
            return false
        end

        if not looter or looter == "" then
            addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        if rollType == nil then
            addon:warn(Diag.W.LogLoggerRollTypeNil:format(raidID, tostring(itemID), tostring(looter)))
        end

        addon:debug(Diag.D.LogLoggerLootBefore:format(raidID, tostring(itemID), tostring(it.itemLink),
            tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))
        if it.looter and it.looter ~= "" and looter and looter ~= "" and it.looter ~= looter then
            addon:warn(Diag.W.LogLoggerLootOverwrite:format(raidID, tostring(itemID), tostring(it.itemLink),
                tostring(it.looter), tostring(looter)))
        end

        local expectedLooter
        local expectedRollType
        local expectedRollValue
        if looter and looter ~= "" then
            it.looter = looter
            expectedLooter = looter
        end
        if tonumber(rollType) then
            it.rollType = tonumber(rollType)
            expectedRollType = tonumber(rollType)
        end
        if tonumber(rollValue) then
            it.rollValue = tonumber(rollValue)
            expectedRollValue = tonumber(rollValue)
        end

        controller:Dirty()
        addon:debug(Diag.D.LogLoggerLootRecorded:format(tostring(source), raidID, tostring(itemID),
            tostring(it.itemLink), tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))

        local ok = true
        if expectedLooter and it.looter ~= expectedLooter then ok = false end
        if expectedRollType and it.rollType ~= expectedRollType then ok = false end
        if expectedRollValue and it.rollValue ~= expectedRollValue then ok = false end
        if not ok then
            addon:error(Diag.E.LogLoggerVerifyFailed:format(raidID, tostring(itemID), tostring(it.looter),
                tostring(it.rollType), tostring(it.rollValue)))
            return false
        end

        addon:debug(Diag.D.LogLoggerVerified:format(raidID, tostring(itemID)))
        if not KRT_LastBoss then
            addon:debug(Diag.D.LogLoggerRecordedNoBossContext:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        return true
    end

    local function Reset() controller:Dirty() end
    Utils.registerCallbacks(
        { "LoggerSelectRaid", "LoggerSelectBoss", "LoggerSelectPlayer", "LoggerSelectBossPlayer",
            "RaidLootUpdate" },
        Reset
    )
    Utils.registerCallback("LoggerSelectItem", function() controller:Touch() end)
end

-- module: Add/Edit Boss Popup  (Patch #1 - normalize to time/mode)
do
    addon.Logger.BossBox = addon.Logger.BossBox or {}
    local Box = addon.Logger.BossBox
    local Store = addon.Logger.Store

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        frame:SetScript("OnShow", function()
            self:UpdateUIFrame()
        end)
        frame:SetScript("OnHide", function() self:CancelAddEdit() end)
        local nameStr = _G[frameName .. "NameStr"]
        if nameStr then
            nameStr:SetText(L.StrName)
        end
        local diffStr = _G[frameName .. "DifficultyStr"]
        if diffStr then
            diffStr:SetText(L.StrDifficulty)
        end
        local timeStr = _G[frameName .. "TimeStr"]
        if timeStr then
            timeStr:SetText(L.StrTime)
        end
        local saveBtn = _G[frameName .. "SaveBtn"]
        if saveBtn then
            saveBtn:SetText(L.BtnSave)
        end
        local cancelBtn = _G[frameName .. "CancelBtn"]
        if cancelBtn then
            cancelBtn:SetText(L.BtnCancel)
        end
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Hide()
        local f = _G[frameName]
        Utils.setShown(f, false)
    end

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    function Box:Fill()
        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        if not (rID and bID) then return end

        raidData = Store:GetRaid(rID)
        if not raidData then return end

        bossData = Store:GetBoss(raidData, bID)
        if not bossData then return end

        _G[frameName .. "Name"]:SetText(bossData.name or "")

        local bossTime = bossData.time or time()
        local d = date("*t", bossTime)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        _G[frameName .. "Time"]:SetText(("%02d:%02d"):format(tempDate.hour, tempDate.min))

        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        _G[frameName .. "Difficulty"]:SetText((mode == "h") and "h" or "n")

        editBossNid = bossData and bossData.bossNid or nil
        isEdit = true
        self:Toggle()
    end

    function Box:Save()
        local rID = addon.Logger.selectedRaid
        if not rID then return end

        local name = Utils.trimText(_G[frameName .. "Name"]:GetText())
        local modeT = Utils.normalizeLower(_G[frameName .. "Difficulty"]:GetText())
        local bTime = Utils.trimText(_G[frameName .. "Time"]:GetText())

        name = (name == "") and "_TrashMob_" or name
        if name ~= "_TrashMob_" and (modeT ~= "h" and modeT ~= "n") then
            addon:error(L.ErrBossDifficulty)
            return
        end

        local h, m = bTime:match("^(%d+):(%d+)$")
        h, m = tonumber(h), tonumber(m)
        if not (h and m and addon.WithinRange(h, 0, 23) and addon.WithinRange(m, 0, 59)) then
            addon:error(L.ErrBossTime)
            return
        end

        local _, month, day, year = CalendarGetDate()
        local killDate = { day = day, month = month, year = year, hour = h, min = m }
        local mode = (modeT == "h") and "h" or "n"

        local bossNid = isEdit and editBossNid or nil
        local savedNid = addon.Logger.Actions:UpsertBossKill(rID, bossNid, name, time(killDate), mode)
        if not savedNid then return end

        self:Hide()
        addon.Logger:ResetSelections()
        Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
    end

    function Box:CancelAddEdit()
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Difficulty"])
        Utils.resetEditBox(_G[frameName .. "Time"])
        isEdit, raidData, bossData, editBossNid = false, {}, {}, nil
        twipe(tempDate)
    end

    function Box:UpdateUIFrame()
        if not localized then
            addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
            localized = true
        end
        Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
    end
end

-- module: Add Attendee Popup
do
    addon.Logger.AttendeesBox = addon.Logger.AttendeesBox or {}
    local Box = addon.Logger.AttendeesBox
    local Store = addon.Logger.Store

    local frameName

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        frame:SetScript("OnShow", function()
            Utils.resetEditBox(_G[frameName .. "Name"])
        end)
        frame:SetScript("OnHide", function()
            Utils.resetEditBox(_G[frameName .. "Name"])
        end)
        local title = _G[frameName .. "Title"]
        if title then
            title:SetText(L.StrAddPlayer)
        end
        local nameStr = _G[frameName .. "NameStr"]
        if nameStr then
            nameStr:SetText(L.StrName)
        end
        local addBtn = _G[frameName .. "AddBtn"]
        if addBtn then
            addBtn:SetText(L.BtnAdd)
        end
        local cancelBtn = _G[frameName .. "CancelBtn"]
        if cancelBtn then
            cancelBtn:SetText(L.BtnCancel)
        end
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Save()
        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        local name = Utils.trimText(_G[frameName .. "Name"]:GetText())
        if addon.Logger.Actions:AddBossAttendee(rID, bID, name) then
            self:Toggle()
            Utils.triggerEvent("LoggerSelectBoss", addon.Logger.selectedBoss)
        end
    end
end

-- =========== Slash Commands  =========== --
do
    addon.Slash = addon.Slash or {}
    local module = addon.Slash
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
            if addon.ReserveImport and addon.ReserveImport.Toggle then addon.ReserveImport:Toggle() end
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
    self:RAID_ROSTER_UPDATE()
end

-- RAID_ROSTER_UPDATE: Updates the raid roster when it changes.
function addon:RAID_ROSTER_UPDATE()
    addon.Raid:UpdateRaidRoster()
    -- Broadcast a normalized roster-change event for UI modules.
    Utils.triggerEvent("RaidRosterUpdate")
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
    local text, boss = ...
    if L.BossYells[text] and KRT_CurrentRaid then
        addon:trace(Diag.D.LogBossYellMatched:format(tostring(text), tostring(L.BossYells[text])))
        self.Raid:AddBoss(L.BossYells[text])
    end
end

-- COMBAT_LOG_EVENT_UNFILTERED: Logs a boss kill when a boss unit dies.
function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
    if not KRT_CurrentRaid then return end

    -- 3.3.5a base params (8):
    -- timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags
    local _, subEvent, _, _, _, destGUID, destName, destFlags = ...
    if subEvent ~= "UNIT_DIED" then return end
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
