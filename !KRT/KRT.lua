--[[
    KRT.lua
    - Main addon file for Kader Raid Tools (KRT).
    - Handles core logic, event registration, and module initialization.
]]

local addonName, addon = ...
addon                  = addon or {}
addon.name             = addon.name or addonName
local L                = addon.L
local Utils            = addon.Utils
local C                = addon.C

local _G               = _G
_G["KRT"]              = addon


---============================================================================
-- Costants
---============================================================================

local ITEM_LINK_PATTERN   = C.ITEM_LINK_PATTERN
local rollTypes           = C.rollTypes
local lootTypesText       = C.lootTypesText
local lootTypesColored    = C.lootTypesColored
local itemColors          = C.itemColors
local RAID_TARGET_MARKERS = C.RAID_TARGET_MARKERS
local K_COLOR             = C.K_COLOR
local RT_COLOR            = C.RT_COLOR

---============================================================================
-- Saved Variables
-- These variables are persisted across sessions for the addon.
---============================================================================

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

---============================================================================
-- External Libraries / Bootstrap
---============================================================================
local Compat              = LibStub("LibCompat-1.0")
addon.Compat              = Compat
addon.BossIDs             = LibStub("LibBossIDs-1.0")
addon.Debugger            = LibStub("LibLogger-1.0")
addon.Deformat            = LibStub("LibDeformat-3.0")
addon.CallbackHandler     = LibStub("CallbackHandler-1.0")

Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
addon.Debugger:Embed(addon)

-- Alias locali (safe e veloci)
local UnitIsGroupLeader    = addon.UnitIsGroupLeader
local UnitIsGroupAssistant = addon.UnitIsGroupAssistant
local tContains            = _G.tContains

do
    local lv = addon.Debugger.logLevels.INFO
    if KRT_Options and KRT_Options.debug then
        lv = addon.Debugger.logLevels.DEBUG
    end
    addon:SetLogLevel(lv)
    addon:SetPerformanceMode(true)
end

---============================================================================
-- Core Addon Frames & Locals
---============================================================================

-- Centralised addon state
addon.State                = addon.State or {}
local coreState            = addon.State

coreState.frames           = coreState.frames or {}
local Frames               = coreState.frames
Frames.main                = Frames.main or CreateFrame("Frame")

-- Addon UI Frames
local mainFrame            = Frames.main
local UIMaster, UIConfig, UISpammer, UIChanges, UIWarnings, UILogger, UILoggerItemBox

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

local itemInfo = lootState.itemInfo

-- Function placeholders for loot helpers
local ItemExists, ItemIsSoulbound, GetItem
local GetItemIndex, GetItemName, GetItemLink, GetItemTexture

function GetItemIndex()
    return lootState.currentItemIndex
end

---============================================================================
-- Cached Functions & Libraries
---============================================================================

local tinsert, tremove, tconcat, twipe  = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local format, find, strlen              = string.format, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber                = tostring, tonumber
local UnitRace, UnitSex, GetRealmName   = UnitRace, UnitSex, GetRealmName

---============================================================================
-- Event System (WoW API events)
-- Clean frame-based dispatcher (NO CallbackHandler here)
---============================================================================
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
                    addon:error("Event handler failed event=%s err=%s", tostring(e), tostring(err))
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

---============================================================================
-- Raid Helpers Module
-- Manages raid state, roster, boss kills, and loot logging.
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Raid              = addon.Raid or {}
    local module            = addon.Raid
    local L                 = addon.L

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local inRaid            = false
    local numRaid           = 0
    local rosterVersion     = 0
    local GetLootMethod     = GetLootMethod
    local GetRaidRosterInfo = GetRaidRosterInfo
    local UnitIsUnit        = UnitIsUnit

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    --------------------------------------------------------------------------
    -- Logger Functions
    --------------------------------------------------------------------------

    --
    -- Updates the current raid roster, adding new players and marking those who left.
    --
    function module:UpdateRaidRoster()
        rosterVersion = rosterVersion + 1
        if not KRT_CurrentRaid then return end
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil

        if not addon.IsInRaid() then
            numRaid = 0
            addon:info(L.LogRaidLeftGroupEndSession)
            module:End()
            addon.Master:PrepareDropDowns()
            return
        end

        local raid = KRT_Raids[KRT_CurrentRaid]
        if not raid then return end

        local realm = Utils.getRealmName()
        KRT_Players[realm] = KRT_Players[realm] or {}

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
                    local toRaid = {
                        name     = name,
                        rank     = rank or 0,
                        subgroup = subgroup or 1,
                        class    = class or "UNKNOWN",
                        join     = Utils.getCurrentTime(),
                        leave    = nil,
                        count    = (player and player.count) or 0,
                    }
                    module:AddPlayer(toRaid)
                    player = toRaid
                else
                    player.rank     = rank or player.rank or 0
                    player.subgroup = subgroup or player.subgroup or 1
                    player.class    = class or player.class or "UNKNOWN"
                end

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

        addon:debug(L.LogRaidRosterUpdate:format(rosterVersion, n))
        addon.Master:PrepareDropDowns()
    end

    --
    -- Creates a new raid log entry.
    --
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

        local raidInfo = {
            realm         = realm,
            zone          = zoneName,
            size          = raidSize,
            players       = {},
            playersByName = {},
            bossKills     = {},
            loot          = {},
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

        addon:info(L.LogRaidCreated:format(
            KRT_CurrentRaid or -1,
            tostring(zoneName),
            tonumber(raidSize) or -1,
            #raidInfo.players
        ))

        Utils.triggerEvent("RaidCreate", KRT_CurrentRaid)

        -- One clean refresh shortly after
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = addon.After(2, function() module:UpdateRaidRoster() end)
    end

    --
    -- Ends the current raid log entry, marking end time.
    --
    function module:End()
        if not KRT_CurrentRaid then return end
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        local currentTime = Utils.getCurrentTime()
        local raid = KRT_Raids[KRT_CurrentRaid]
        if raid then
            local duration = currentTime - (raid.startTime or currentTime)
            addon:info(L.LogRaidEnded:format(KRT_CurrentRaid or -1, tostring(raid.zone),
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

    --
    -- Checks the current raid status and creates a new session if needed.
    --
    function module:Check(instanceName, instanceDiff)
        addon:debug(L.LogRaidCheck:format(tostring(instanceName), tostring(instanceDiff),
            tostring(KRT_CurrentRaid)))
        if not KRT_CurrentRaid then
            module:Create(instanceName, (instanceDiff % 2 == 0 and 25 or 10))
        end

        local current = KRT_Raids[KRT_CurrentRaid]
        if current then
            if current.zone == instanceName then
                if current.size == 10 and (instanceDiff % 2 == 0) then
                    addon:info(L.StrNewRaidSessionChange)
                    addon:info(L.LogRaidSessionChange:format(tostring(instanceName), 25,
                        tonumber(instanceDiff) or -1))
                    module:Create(instanceName, 25)
                elseif current.size == 25 and (instanceDiff % 2 ~= 0) then
                    addon:info(L.StrNewRaidSessionChange)
                    addon:info(L.LogRaidSessionChange:format(tostring(instanceName), 10,
                        tonumber(instanceDiff) or -1))
                    module:Create(instanceName, 10)
                end
            end
        elseif (instanceDiff % 2 == 0) then
            addon:info(L.StrNewRaidSessionChange)
            addon:info(L.LogRaidSessionCreate:format(tostring(instanceName), 25,
                tonumber(instanceDiff) or -1))
            module:Create(instanceName, 25)
        elseif (instanceDiff % 2 ~= 0) then
            addon:info(L.StrNewRaidSessionChange)
            addon:info(L.LogRaidSessionCreate:format(tostring(instanceName), 10,
                tonumber(instanceDiff) or -1))
            module:Create(instanceName, 10)
        end
    end

    --
    -- Performs an initial raid check on player login.
    --
    function module:FirstCheck()
        if module.firstCheckHandle then
            addon.CancelTimer(module.firstCheckHandle, true)
            module.firstCheckHandle = nil
        end
        if not addon.IsInGroup() then return end

        if KRT_CurrentRaid and module:CheckPlayer(Utils.getPlayerName(), KRT_CurrentRaid) then
            addon.CancelTimer(module.updateRosterHandle, true)
            module.updateRosterHandle = addon.After(2, function() module:UpdateRaidRoster() end)
            return
        end

        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
        addon:debug(L.LogRaidFirstCheck:format(tostring(addon.IsInGroup()), tostring(KRT_CurrentRaid ~= nil),
            tostring(instanceName), tostring(instanceType), tostring(instanceDiff)))
        if instanceType == "raid" then
            module:Check(instanceName, instanceDiff)
            return
        end
    end

    --
    -- Adds a player to the raid log.
    --
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
            addon:trace(L.LogRaidPlayerJoin:format(tostring(t.name), tonumber(raidNum) or -1))
        else
            addon:trace(L.LogRaidPlayerRefresh:format(tostring(t.name), tonumber(raidNum) or -1))
        end
    end

    --
    -- Adds a boss kill to the active raid log.
    --
    function module:AddBoss(bossName, manDiff, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        if not raidNum or not bossName then
            addon:warn(L.LogBossAddSkipped:format(tostring(raidNum), tostring(bossName)))
            return
        end

        local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if manDiff then
            instanceDiff = (KRT_Raids[raidNum].size == 10) and 1 or 2
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
        local killInfo = {
            name       = bossName,
            difficulty = instanceDiff,
            players    = players,
            date       = currentTime,
            hash       = Utils.encode(raidNum .. "|" .. bossName .. "|" .. (KRT_LastBoss or "0"))
        }
        tinsert(KRT_Raids[raidNum].bossKills, killInfo)
        KRT_LastBoss = #KRT_Raids[raidNum].bossKills
        addon:info(L.LogBossLogged:format(tostring(bossName), tonumber(instanceDiff) or -1,
            tonumber(raidNum) or -1, #players))
        addon:debug(L.LogBossLastBossHash:format(tonumber(KRT_LastBoss) or -1, tostring(killInfo.hash)))
    end

    --
    -- Adds a loot item to the active raid log.
    --
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
            if (not link) and _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE then
                link, count = addon.Deformat(msg, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
            end
            if link then
                itemLink = link
                itemCount = count or 1
                player = Utils.getPlayerName()
            end
        end

        if not itemLink then
            local link = addon.Deformat(msg, LOOT_ITEM_SELF)
            if (not link) and _G.LOOT_ITEM_PUSHED_SELF then
                link = addon.Deformat(msg, LOOT_ITEM_PUSHED_SELF)
            end
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
            addon:warn(L.LogLootParseFailed:format(tostring(msg)))
            return
        end

        itemCount = tonumber(itemCount) or 1
        lootState.itemCount = itemCount

        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        itemId = tonumber(itemId)
        addon:trace(L.LogLootParsed:format(tostring(player), tostring(itemLink), itemCount))

        -- We don't proceed if lower than threshold or ignored.
        local lootThreshold = GetLootThreshold()
        if itemRarity and itemRarity < lootThreshold then
            addon:debug(L.LogLootIgnoredBelowThreshold:format(tostring(itemRarity),
                tonumber(lootThreshold) or -1, tostring(itemLink)))
            return
        end
        if itemId and addon.ignoredItems[itemId] then
            addon:debug(L.LogLootIgnoredItemId:format(tostring(itemId), tostring(itemLink)))
            return
        end

        if not KRT_LastBoss then
            addon:info(L.LogBossNoContextTrash)
            self:AddBoss("_TrashMob_")
        end
        -- Award source detection:
        -- 1) If we have a pendingAward staged by this addon (AssignItem/TradeItem), consume it.
        -- 2) Otherwise, if THIS client is the master looter (Master Loot method), treat it as MANUAL
        --    (loot-window dropdown assignment or direct click-to-self).
        -- 3) Otherwise, fall back to the current roll type.
        if not rollType then
            local p = lootState.pendingAward
            if p
                and p.itemLink == itemLink
                and p.looter == player
                and (GetTime() - (p.ts or 0)) <= 5
            then
                rollType               = p.rollType
                rollValue              = p.rollValue
                lootState.pendingAward = nil
            elseif self:IsMasterLooter() and not lootState.fromInventory then
                rollType  = rollTypes.MANUAL
                rollValue = 0

                -- Debug-only marker: helps verify why this loot was tagged as MANUAL.
                -- Only runs for Master Looter clients (by condition above).
                addon:debug(
                    "Loot: tagged MANUAL (no matching pending award) item=%s -> %s (lastRollType=%s, pending=%s).",
                    tostring(itemLink), tostring(player), tostring(lootState.currentRollType),
                    p and (tostring(p.itemLink) .. " -> " .. tostring(p.looter)) or "nil")
            else
                rollType = lootState.currentRollType
            end
        end

        if not rollValue then
            rollValue = addon.Rolls:HighestRoll() or 0
        end

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
            bossNum     = KRT_LastBoss,
            time        = Utils.getCurrentTime(),
        }
        tinsert(KRT_Raids[KRT_CurrentRaid].loot, lootInfo)
        Utils.triggerEvent("RaidLootUpdate", KRT_CurrentRaid, lootInfo)
        addon:debug(L.LogLootLogged:format(tonumber(KRT_CurrentRaid) or -1, tostring(itemId),
            tostring(KRT_LastBoss), tostring(player)))
    end

    --------------------------------------------------------------------------
    -- Player Count API
    --------------------------------------------------------------------------

    function module:GetPlayerCount(name, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = raidNum and KRT_Raids[raidNum]
        local players = raid and raid.players
        if not players then return 0 end
        for i, p in ipairs(players) do
            if p.name == name then
                return p.count or 0
            end
        end
        return 0
    end

    function module:SetPlayerCount(name, value, raidNum)
        raidNum = raidNum or KRT_CurrentRaid

        -- Prevent setting a negative count
        if value < 0 then
            addon:error(L.ErrPlayerCountBelowZero:format(name))
            return
        end

        local players = KRT_Raids[raidNum] and KRT_Raids[raidNum].players
        if not players then return end
        for i, p in ipairs(players) do
            if p.name == name then
                p.count = value
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
            addon:error(L.ErrPlayerCountBelowZero:format(name))
            return
        end
        module:SetPlayerCount(name, c - 1, raidNum)
    end

    --------------------------------------------------------------------------
    -- Raid Functions
    --------------------------------------------------------------------------

    --
    -- Returns the number of members in the raid.
    --
    function module:GetNumRaid()
        return numRaid
    end

    --
    -- Returns raid size: 10 or 25.
    --
    function module:GetRaidSize()
        local _, _, members = addon.GetGroupTypeAndCount()
        if members == 0 then return 0 end

        local diff = addon.Utils.getDifficulty()
        if diff then
            return (diff == 1 or diff == 3) and 10 or 25
        end

        return members > 20 and 25 or 10
    end

    --
    -- Checks if a raid log is expired (older than the weekly reset).
    --
    function module:Expired(rID)
        rID = rID or KRT_CurrentRaid
        local raid = rID and KRT_Raids[rID]
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

    --
    -- Retrieves all loot for a given raid and optional boss number.
    --
    function module:GetLoot(raidNum, bossNum)
        raidNum = raidNum or KRT_CurrentRaid
        bossNum = bossNum or 0
        local raid = raidNum and KRT_Raids[raidNum]
        if not raid then
            return {}
        end
        local loot = raid.loot
        if tonumber(bossNum) <= 0 then
            for k, v in ipairs(loot) do
                v.id = k
            end
            return loot
        end

        local items = {}
        if raid.bossKills[bossNum] then
            -- Get loot for a specific boss
            for k, v in ipairs(loot) do
                if v.bossNum == bossNum then
                    v.id = k
                    tinsert(items, v)
                end
            end
        end
        return items
    end

    --
    -- Retrieves the position of a specific loot item within the raid's loot table.
    --
    function module:GetLootID(itemID, raidNum, holderName)
        local pos = 0
        local loot = self:GetLoot(raidNum)
        holderName = holderName or Utils.getPlayerName()
        itemID = tonumber(itemID)
        for k, v in ipairs(loot) do
            if v.itemId == itemID and v.looter == holderName then
                pos = k
                break
            end
        end
        return pos
    end

    --
    -- Retrieves all boss kills for a given raid.
    --
    function module:GetBosses(raidNum, out)
        local bosses = out or {}
        if out then twipe(bosses) end
        raidNum = raidNum or KRT_CurrentRaid
        if raidNum and KRT_Raids[raidNum] then
            local kills = KRT_Raids[raidNum].bossKills
            for i, b in ipairs(kills) do
                local info = {
                    id = i,
                    difficulty = b.difficulty,
                    time = b.date,
                    hash = b.hash or "0",
                }
                if b.name == "_TrashMob_" then
                    info.name = L.StrTrashMob
                    info.mode = ""
                else
                    info.name = b.name
                    info.mode = (b.difficulty == 3 or b.difficulty == 4) and PLAYER_DIFFICULTY2 or PLAYER_DIFFICULTY1
                end
                tinsert(bosses, info)
            end
        end
        -- Caller releases when using a pooled table.
        return bosses
    end

    --------------------------------------------------------------------------
    -- Player Functions
    --------------------------------------------------------------------------

    --
    -- Returns players from the raid log. Can be filtered by boss kill.
    --
    function module:GetPlayers(raidNum, bossNum, out)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = raidNum and KRT_Raids[raidNum]
        if not raid then return {} end

        local raidPlayers = raid.players or {}
        for k, v in ipairs(raidPlayers) do
            v.id = k
        end

        if bossNum and raid.bossKills[bossNum] then
            local players = out or {}
            if out then twipe(players) end
            local bossPlayers = raid.bossKills[bossNum].players
            for i, p in ipairs(raidPlayers) do
                if tContains(bossPlayers, p.name) then
                    tinsert(players, p)
                end
            end
            -- Caller releases when using a pooled table.
            return players
        end

        return raidPlayers
    end

    --
    -- Checks if a player is in the raid log.
    --
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

    --
    -- Returns the player's internal ID from the raid log.
    --
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

    --
    -- Gets a player's name by their internal ID.
    --
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

    --
    -- Returns a table of items looted by the selected player.
    --
    function module:GetPlayerLoot(name, raidNum, bossNum)
        local items = {}
        local loot = module:GetLoot(raidNum, bossNum)
        local originalName = name
        name = (type(name) == "number") and module:GetPlayerName(name) or name
        for _, v in ipairs(loot) do
            if v.looter == name then
                -- Keep v.id as the original index assigned by GetLoot()
                tinsert(items, v)
            end
        end
        return items
    end

    --
    -- Gets a player's rank.
    --
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

    --
    -- Gets a player's class from the saved players database.
    --
    function module:GetPlayerClass(name)
        local class = "UNKNOWN"
        local realm = Utils.getRealmName()
        local resolvedName = name or Utils.getPlayerName()
        if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
            class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
        end
        return class
    end

    --
    -- Gets a player's unit ID (e.g., "raid1").
    --
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

    --------------------------------------------------------------------------
    -- Raid & Loot Status Checks
    --------------------------------------------------------------------------

    --
    -- Checks if the group is using the Master Looter system.
    --
    function module:IsMasterLoot()
        local method = select(1, GetLootMethod())
        return (method == "master")
    end

    --
    -- Checks if the player is the Master Looter.
    --
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

    --
    -- Clears all raid target icons.
    --
    function module:ClearRaidIcons()
        local players = module:GetPlayers()
        for i, p in ipairs(players) do
            SetRaidTarget("raid" .. tostring(i), 0)
        end
    end
end

---============================================================================
-- Chat Output Helpers
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Chat            = addon.Chat or {}
    local module          = addon.Chat
    local L               = addon.L

    -------------------------------------------------------
    -- 3. Internal state (non-exposed local variables)
    -------------------------------------------------------
    local output          = C.CHAT_OUTPUT_FORMAT
    local chatPrefix      = C.CHAT_PREFIX
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local prefixHex       = C.CHAT_PREFIX_HEX

    -------------------------------------------------------
    -- 5. Public module functions
    -------------------------------------------------------
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

    -------------------------------------------------------
    -- 6. Legacy helpers
    -------------------------------------------------------
    function addon:Announce(text, channel)
        module:Announce(text, channel)
    end
end

---============================================================================
-- Minimap Button Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Minimap = addon.Minimap or {}
    local module = addon.Minimap
    local L = addon.L

    -------------------------------------------------------
    -- 3. Internal state (non-exposed local variables)
    -------------------------------------------------------
    local addonMenu
    local dragMode

    -- Cached math functions
    local abs, sqrt = math.abs, math.sqrt
    local cos, sin = math.cos, math.sin
    local rad, atan2, deg = math.rad, math.atan2, math.deg

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    -- Initializes and opens the right-click menu for the minimap button.
    local function OpenMenu()
        local info = {}
        local function AddMenuButton(level, text, func)
            twipe(info)
            info.text = text
            info.notCheckable = 1
            info.func = func
            UIDropDownMenu_AddButton(info, level)
        end

        local function AddMenuTitle(level, text)
            twipe(info)
            info.isTitle = 1
            info.text = text
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
        end

        local function AddMenuSeparator(level)
            twipe(info)
            info.disabled = 1
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
        end

        addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
        addonMenu.displayMode = "MENU"
        addonMenu.initialize = function(self, level)
            if level == 1 then
                -- Toggle master loot frame:
                AddMenuButton(level, MASTER_LOOTER, function() addon.Master:Toggle() end)
                -- Toggle raid warnings frame:
                AddMenuButton(level, RAID_WARNING, function() addon.Warnings:Toggle() end)
                -- Toggle loot logger frame:
                AddMenuButton(level, L.StrLootLogger, function() addon.Logger:Toggle() end)
                -- Separator:
                AddMenuSeparator(level)
                -- Clear raid icons:
                AddMenuButton(level, L.StrClearIcons, function() addon.Raid:ClearRaidIcons() end)
                -- Separator:
                AddMenuSeparator(level)
                -- MS changes header:
                AddMenuTitle(level, L.StrMSChanges)
                -- Toggle MS Changes frame:
                AddMenuButton(level, L.BtnConfigure, function() addon.Changes:Toggle() end)
                -- Ask for MS changes:
                AddMenuButton(level, L.BtnDemand, function() addon.Changes:Demand() end)
                -- Spam ms changes:
                AddMenuButton(level, CHAT_ANNOUNCE, function() addon.Changes:Announce() end)
                AddMenuSeparator(level)
                -- Toggle lfm spammer frame:
                AddMenuButton(level, L.StrLFMSpam, function() addon.Spammer:Toggle() end)
            end
        end
        ToggleDropDownMenu(1, nil, addonMenu, KRT_MINIMAP_GUI, 0, 0)
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

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------
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
                OpenMenu()
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

---============================================================================
-- Rolls Helpers Module
-- Manages roll tracking, sorting, and winner determination.
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Rolls = addon.Rolls or {}
    local module = addon.Rolls
    local L = addon.L

    -------------------------------------------------------
    -- 2. Internal state
    -------------------------------------------------------
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
    }
    local newItemCounts, delItemCounts = addon.TablePool and addon.TablePool("k")
    state.itemCounts = newItemCounts and newItemCounts() or {}

    -------------------------------------------------------
    -- 3. Private helpers
    -------------------------------------------------------
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
        local bestName, bestRoll = nil, nil
        local wantLow = addon.options.sortAscending == true

        for _, entry in ipairs(state.rolls) do
            if module:IsReserved(itemId, entry.name) then
                if not bestName then
                    bestName, bestRoll = entry.name, entry.roll
                elseif wantLow then
                    if entry.roll < bestRoll then
                        bestName, bestRoll = entry.name, entry.roll
                    end
                else
                    if entry.roll > bestRoll then
                        bestName, bestRoll = entry.name, entry.roll
                    end
                end
            end
        end

        return bestName, bestRoll
    end

    -- Returns the "real" winner for UI (top roll, with SR priority if active).
    local function GetEffectiveWinner(itemId)
        if lootState.currentRollType == rollTypes.RESERVED then
            return PickBestReserved(itemId) or lootState.winner
        end
        return lootState.winner
    end

    -- Sorts rolls table + updates lootState.winner (top entry after sort).
    local function sortRolls(itemId)
        local rolls = state.rolls
        if #rolls == 0 then
            lootState.winner = nil
            lootState.rollWinner = nil
            addon:debug("Rolls: sort no entries.")
            return
        end

        local isSR    = (lootState.currentRollType == rollTypes.RESERVED)
        local wantLow = (addon.options.sortAscending == true)

        table.sort(rolls, function(a, b)
            -- SR: reserved first (session itemId)
            if isSR and itemId then
                local ar = module:IsReserved(itemId, a.name)
                local br = module:IsReserved(itemId, b.name)
                if ar ~= br then
                    return ar -- true first
                end
            end

            if a.roll ~= b.roll then
                return wantLow and (a.roll < b.roll) or (a.roll > b.roll)
            end

            -- tie-breaker stabile
            return tostring(a.name) < tostring(b.name)
        end)

        -- ⭐ top roll (segue SEMPRE Asc/Desc)
        lootState.rollWinner = rolls[1].name

        -- award target segue top roll solo se non è manuale
        if state.canRoll or state.selectedAuto or (lootState.winner == nil) then
            lootState.winner = lootState.rollWinner
            state.selectedAuto = true
        end

        state.lastSortAsc  = wantLow
        state.lastSortType = lootState.currentRollType
    end

    local function onRollButtonClick(self)
        -- ✅ Selezione SOLO a countdown finito
        if state.canRoll then
            return
        end

        local name = self.playerName
        if not name or name == "" then return end

        -- ✅ award target = selezione manuale
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

        addon:debug("Rolls: add name=%s roll=%d item=%s.", name, roll, tostring(itemId))
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

        if rec == false then state.record = false end
    end

    -------------------------------------------------------
    -- 4. Public methods
    -------------------------------------------------------
    -- Initiates a /roll 1-100 for the player.
    function module:Roll(btn)
        local itemId = self:GetCurrentRollItemID()
        if not itemId then return end

        local name = Utils.getPlayerName()
        local allowed = 1
        if lootState.currentRollType == rollTypes.RESERVED then
            local reserve = addon.Reserves:GetReserveCountForItem(itemId, name)
            allowed = (reserve > 0) and reserve or 1
        end

        state.playerCounts[itemId] = state.playerCounts[itemId] or 0
        if state.playerCounts[itemId] >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            addon:debug("Rolls: blocked player=%s (%d/%d).", name, state.playerCounts[itemId], allowed)
            return
        end

        RandomRoll(1, 100)
        state.rolled = true
        state.playerCounts[itemId] = state.playerCounts[itemId] + 1
        addon:debug("Rolls: player=%s item=%d.", name, itemId)
    end

    -- Returns the current roll session state.
    function module:RollStatus()
        return lootState.currentRollType, state.record, state.canRoll, state.rolled
    end

    -- Enables or disables the recording of rolls.
    function module:RecordRolls(bool)
        local on      = (bool == true)
        state.canRoll = on
        state.record  = on

        if on then
            state.warned = false

            -- reset SOLO se stiamo iniziando una sessione “pulita”
            if state.count == 0 then
                state.selected = nil
                state.selectedAuto = true
                lootState.winner = nil
                lootState.rollWinner = nil
            end
        end

        addon:debug("Rolls: record=%s.", tostring(bool))
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
            addon:debug("Rolls: blocked countdown active.")
            return
        end

        local itemId = self:GetCurrentRollItemID()
        if not itemId or lootState.lootCount == 0 then
            addon:error("Item ID missing or loot table not ready – roll ignored.")
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
            addon:debug("Rolls: denied player=%s (%d/%d).", player, used, allowed)
            return
        end

        addon:debug("Rolls: accepted player=%s (%d/%d).", player, used + 1, allowed)
        addRoll(player, roll, itemId)
    end

    -- Returns the current table of rolls.
    function module:GetRolls()
        return state.rolls
    end

    -- Sets the flag indicating the player has rolled.
    function module:SetRolled()
        state.rolled = true
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
        for i = 1, state.count do
            local entry = state.rolls[i]
            if entry.name == lootState.winner then return entry.roll end
        end
        return 0
    end

    -- Clears all roll-related state and UI elements.
    function module:ClearRolls(rec)
        local frameName = Utils.getFrameName()
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
        addon:debug("Rolls: current itemId=%s.", tostring(itemId))
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
        local frameName = Utils.getFrameName()
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())

        local itemId = self:GetCurrentRollItemID()
        local isSR = lootState.currentRollType == rollTypes.RESERVED

        local wantAsc = addon.options.sortAscending == true
        if state.lastSortAsc ~= wantAsc or state.lastSortType ~= lootState.currentRollType then
            sortRolls(itemId)
        end

        -- top roll
        local starTarget = lootState.rollWinner

        -- fallback (se per qualche motivo non è ancora valorizzato)
        if not starTarget then
            if isSR then
                local bestName = PickBestReserved(itemId)
                starTarget = bestName or lootState.winner
            else
                starTarget = lootState.winner
            end
        end

        local selectionAllowed = (state.canRoll == false)
        local pickName = selectionAllowed and lootState.winner or nil

        -- highlight: durante CD = top roll; post-CD = pick (se esiste) altrimenti top roll
        local highlightTarget = selectionAllowed and (pickName or starTarget) or starTarget

        local starShown, totalHeight = false, 0
        for i = 1, state.count do
            local entry = state.rolls[i]
            local name, roll = entry.name, entry.roll
            local btnName = frameName .. "PlayerBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")

            btn:SetID(i)
            btn:Show()
            btn.playerName = name

            -- click solo post-CD
            btn:EnableMouse(selectionAllowed)

            if not btn.selectedBackground then
                btn.selectedBackground = btn:CreateTexture("KRTSelectedHighlight", "ARTWORK")
                btn.selectedBackground:SetAllPoints()
                btn.selectedBackground:SetTexture(1, 0.8, 0, 0.1)
                btn.selectedBackground:Hide()
            end

            local nameStr, rollStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"], _G[btnName .. "Star"]

            if nameStr and nameStr.SetVertexColor then
                local class = addon.Raid:GetPlayerClass(name)
                class = class and class:upper() or "UNKNOWN"
                if isSR and self:IsReserved(itemId, name) then
                    nameStr:SetVertexColor(0.4, 0.6, 1.0)
                else
                    local r, g, b = Utils.getClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
            end

            -- > < SOLO se manuale (cioè: post-CD e selectedAuto=false)
            if selectionAllowed and (state.selectedAuto == false) and pickName and pickName == name then
                nameStr:SetText("> " .. name .. " <")
            else
                nameStr:SetText(name)
            end

            if highlightTarget and highlightTarget == name then
                btn.selectedBackground:Show()
            else
                btn.selectedBackground:Hide()
            end

            if isSR and self:IsReserved(itemId, name) then
                local count = self:GetAllowedReserves(itemId, name)
                local used = self:GetUsedReserveCount(itemId, name)
                rollStr:SetText(count > 1 and format("%d (%d/%d)", roll, used, count) or tostring(roll))
            else
                rollStr:SetText(roll)
            end

            -- ⭐ STAR sempre top roll (rollWinner)
            local showStar = (not starShown) and (starTarget ~= nil) and (name == starTarget)
            Utils.showHide(star, showStar)
            if showStar then starShown = true end

            if not btn.krtHasOnClick then
                btn:SetScript("OnClick", onRollButtonClick)
                btn.krtHasOnClick = true
            end

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
    end

    Utils.registerCallback("ConfigsortAscending", function(_, value)
        addon.Rolls:FetchRolls()
    end)
end

---============================================================================
-- Loot Helpers Module
-- Manages the loot window items (fetching from loot/inventory).
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Loot = addon.Loot or {}
    local module = addon.Loot
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local lootTable = {}

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    --
    -- Fetches items from the currently open loot window.
    --
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = GetItemLink(lootState.currentItemIndex)
        end
        addon:trace(L.LogLootFetchStart:format(GetNumLootItems() or 0, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        for i = 1, GetNumLootItems() do
            if LootSlotIsItem(i) then
                local itemLink = GetLootSlotLink(i)
                if itemLink then
                    local icon, name, quantity, quality = GetLootSlotInfo(i)
                    if GetItemFamily(itemLink) ~= 64 then
                        self:AddItem(itemLink, quantity, name, quality, icon)
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
        addon:trace(L.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    --
    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
    --
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
            addon:warn(L.LogLootItemInfoMissing:format(tostring(itemLink)))
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

    --
    -- Prepares the currently selected item for display.
    --
    function module:PrepareItem()
        if ItemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    --
    -- Sets the main item display in the UI.
    --
    function module:SetItem(i)
        if i.itemName and i.itemLink and i.itemTexture and i.itemColor then
            frameName = frameName or Utils.getFrameName()
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

    --
    -- Selects an item from the loot list by its index.
    --
    function module:SelectItem(i)
        if ItemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
            if addon.Master and addon.Master.ResetItemCount then
                addon.Master:ResetItemCount()
            end
        end
    end

    --
    -- Clears all loot from the table and resets the UI display.
    --
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        frameName = frameName or Utils.getFrameName()
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        if frameName == UIMaster:GetName() then
            Utils.resetEditBox(_G[frameName .. "ItemCount"], true)
        end
    end

    -- Returns the table for the currently selected item.
    --
    function GetItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    --
    -- Returns the name of the currently selected item.
    --
    function GetItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    --
    -- Returns the link of the currently selected item.
    --
    function GetItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    --
    -- Returns the texture of the currently selected item.
    --
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

    --
    -- Checks if a loot item exists at the given index.
    --
    function ItemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    --
    -- Checks if an item in the player's bags is soulbound.
    --
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

---============================================================================
-- Master Looter Frame Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Master = addon.Master or {}
    local module = addon.Master
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_MASTER

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

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    local function SetItemCountValue(count, focus)
        frameName = frameName or Utils.getFrameName()
        if not frameName or frameName ~= UIMaster:GetName() then return end
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
        SetItemCountValue(addon.Loot:GetCurrentItemCount(), focus)
    end

    local function StopCountdown()
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
        countdownEndTimer = addon.After(duration, function()
            if not countdownRun then return end
            StopCountdown()
            addon:Announce(L.ChatCountdownEnd)

            -- ✅ a 0: stop roll (abilita selezione in Rolls) + refresh UI
            addon.Rolls:RecordRolls(false)
            addon.Rolls:FetchRolls()
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
        UpdateEnabled("openReserves", _G[frameName .. "OpenReservesBtn"], state.canOpenReserves)
        UpdateEnabled("importReserves", _G[frameName .. "ImportReservesBtn"], state.canImportReserves)
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
        addon:debug(L.LogMLCandidateCacheBuilt:format(tostring(itemLink),
            addon.tLength(candidateCache.indexByName)))
    end

    local function ResetTradeState()
        lootState.trader = nil
        lootState.winner = nil
        screenshotWarn = false
    end

    local function RegisterAwardedItem()
        local targetCount = tonumber(lootState.itemCount) or 1
        if targetCount < 1 then targetCount = 1 end
        lootState.itemTraded = (lootState.itemTraded or 0) + 1
        if lootState.itemTraded >= targetCount then
            lootState.itemTraded = 0
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            return true
        end
        return false
    end



    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIMaster = frame
        addon.UIMaster = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", UpdateUIFrame)
        frame:SetScript("OnHide", function()
            if selectionFrame then selectionFrame:Hide() end
        end)
    end

    --
    -- Toggles the visibility of the Master Looter frame.
    --
    function module:Toggle()
        Utils.toggle(UIMaster)
    end

    --
    -- Hides the Master Looter frame.
    --
    function module:Hide()
        Utils.hideFrame(UIMaster)
    end

    --
    -- Button: Select/Remove Item
    --
    function module:BtnSelectItem(btn)
        if btn == nil or lootState.lootCount <= 0 then return end
        if countdownRun then return end
        if lootState.fromInventory == true then
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            announced = false
            lootState.fromInventory = false
            if lootState.opened == true then addon.Loot:FetchLoot() end
        elseif selectionFrame then
            Utils.toggle(selectionFrame)
        end
    end

    --
    -- Button: Spam Loot Links or Do Ready Check
    --
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
                    addon:Announce(i .. ". " .. itemLink, "RAID")
                end
            end
        end
    end

    --
    -- Button: Open Reserves List
    --
    function module:BtnOpenReserves(btn)
        addon.Reserves:ShowWindow()
    end

    --
    -- Button: Import Reserves
    --
    function module:BtnImportReserves(btn)
        addon.Reserves:ShowImportBox()
    end

    --
    -- Generic function to announce a roll for the current item.
    --
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
                local srList = addon.Reserves:FormatReservedPlayersLine(itemID)
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
        end
    end

    local function AssignToTarget(rollType, targetKey)
        if lootState.lootCount <= 0 or not lootState[targetKey] then return end
        countdownRun = false
        local itemLink = GetItemLink()
        if not itemLink then return end
        lootState.currentRollType = rollType
        local target = lootState[targetKey]
        if lootState.fromInventory then
            return TradeItem(itemLink, target, rollType, 0)
        end
        return AssignItem(itemLink, target, rollType, 0)
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

    --
    -- Button: Starts or stops the roll countdown.
    --
    function module:BtnCountdown(btn)
        if countdownRun then
            addon.Rolls:RecordRolls(false)
            StopCountdown()
            addon.Rolls:FetchRolls()
        elseif not lootState.rollStarted then
            return
        else
            addon.Rolls:RecordRolls(true)
            announced = false
            StartCountdown()
        end
    end

    --
    -- Button: Clear Rolls
    --
    function module:BtnClear(btn)
        announced = false
        return addon.Rolls:ClearRolls()
    end

    --
    -- Button: Award/Trade
    --
    function module:BtnAward(btn)
        if countdownRun then
            addon:warn("Countdown ancora attivo: attendi la fine (0) prima di assegnare.")
            return
        end
        if lootState.lootCount <= 0 or lootState.rollsCount <= 0 then
            addon:debug("Award: blocked lootCount=%d rollsCount=%d.", lootState.lootCount or 0,
                lootState.rollsCount or 0)
            return
        end
        if not lootState.winner then
            addon:warn(L.ErrNoWinnerSelected)
            return
        end
        countdownRun = false
        local itemLink = GetItemLink()
        addon:info(L.LogMLAwardRequested:format(tostring(lootState.winner),
            tonumber(lootState.currentRollType) or -1, addon.Rolls:HighestRoll() or 0, tostring(itemLink)))
        local result
        if lootState.fromInventory == true then
            result = TradeItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
        else
            result = AssignItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
            if result then
                RegisterAwardedItem()
            end
        end
        module:ResetItemCount()
        return result
    end

    --
    -- Button: Hold item
    --
    function module:BtnHold(btn)
        return AssignToTarget(rollTypes.HOLD, "holder")
    end

    --
    -- Button: Bank item
    --
    function module:BtnBank(btn)
        return AssignToTarget(rollTypes.BANK, "banker")
    end

    --
    -- Button: Disenchant item
    --
    function module:BtnDisenchant(btn)
        return AssignToTarget(rollTypes.DISENCHANT, "disenchanter")
    end

    --
    -- Selects a winner from the roll list.
    --
    function module:SelectWinner(btn)
        if not btn then return end
        local btnName = btn:GetName()
        local raw = btn.playerName or _G[btnName .. "Name"]:GetText() or ""
        local player = Utils.trimText(raw:gsub("^%s*>%s*(.-)%s*<%s*$", "%1"))
        if player ~= "" then
            if IsControlKeyDown() then
                local roll = _G[btnName .. "Roll"]:GetText()
                addon:Announce(format(L.ChatPlayerRolled, player, roll))
                return
            end
            lootState.winner = player
            addon.Rolls:FetchRolls()
            Utils.sync("KRT-RollWinner", player)
        end
        if lootState.itemCount == 1 then announced = false end
    end

    --
    -- Selects an item from the item selection frame.
    --
    function module:BtnSelectedItem(btn)
        if not btn then return end
        local index = btn:GetID()
        if index ~= nil then
            announced = false
            selectionFrame:Hide()
            addon.Loot:SelectItem(index)
            module:ResetItemCount()
        end
    end

    --
    -- Localizes UI frame elements.
    --
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
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
            _G[frameName .. "RollsHeaderRoll"]:SetText(L.StrRoll)
            _G[frameName .. "OpenReservesBtn"]:SetText(L.BtnOpenReserves)
            _G[frameName .. "RaidListBtn"]:SetText(L.BtnRaidList)
            _G[frameName .. "ImportReservesBtn"]:SetText(L.BtnImportReserves)
        end
        Utils.setFrameTitle(frameName, MASTER_LOOTER)
        _G[frameName .. "ItemCount"]:SetScript("OnTextChanged", function(self)
            announced = false
            dirtyFlags.itemCount = true
        end)
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
                if itemInfo.count and itemInfo.count ~= lootState.itemCount then
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

    --
    -- OnUpdate handler for the frame, updates UI elements periodically.
    --
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
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

            if dirtyFlags.buttons then
                UpdateMasterButtonsIfChanged({
                    countdownText = countdownRun and L.BtnStop or L.BtnCountdown,
                    awardText = lootState.fromInventory and TRADE or L.BtnAward,
                    selectItemText = lootState.fromInventory and L.BtnRemoveItem or L.BtnSelectItem,
                    spamLootText = lootState.fromInventory and READY_CHECK or L.BtnSpamLoot,
                    canSelectItem = (lootState.lootCount > 1
                        or (lootState.fromInventory and lootState.lootCount >= 1)) and not countdownRun,
                    canChangeItem = hasItem and not countdownRun,
                    canSpamLoot = lootState.lootCount >= 1,
                    canStartRolls = lootState.lootCount >= 1,
                    canStartSR = lootState.lootCount >= 1 and hasItemReserves,
                    canCountdown = lootState.lootCount >= 1 and hasItem
                        and (lootState.rollStarted or countdownRun),
                    canHold = lootState.lootCount >= 1 and lootState.holder,
                    canBank = lootState.lootCount >= 1 and lootState.banker,
                    canDisenchant = lootState.lootCount >= 1 and lootState.disenchanter,
                    canAward = lootState.lootCount >= 1 and lootState.rollsCount >= 1 and not countdownRun,
                    canOpenReserves = hasReserves,
                    canImportReserves = not hasReserves,
                    canRoll = record and canRoll and rolled == false and countdownRun,
                    canClear = lootState.rollsCount >= 1,
                })
                dirtyFlags.buttons = false
            end

            dirtyFlags.rolls = false
            dirtyFlags.winner = false
        end)
    end

    --
    -- Initializes the dropdown menus for player selection.
    --
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

    --
    -- Prepares the data for the dropdowns by fetching the raid roster.
    --
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

    --
    -- OnClick handler for dropdown menu items.
    --
    function module:OnClickDropDown(owner, value)
        if not KRT_CurrentRaid then return end
        UIDropDownMenu_SetText(owner, value)
        UIDropDownMenu_SetSelectedValue(owner, value)
        local name = owner:GetName()
        if name == dropDownFrameHolder:GetName() then
            KRT_Raids[KRT_CurrentRaid].holder = value
            lootState.holder = value
        elseif name == dropDownFrameBanker:GetName() then
            KRT_Raids[KRT_CurrentRaid].banker = value
            lootState.banker = value
        elseif name == dropDownFrameDisenchanter:GetName() then
            KRT_Raids[KRT_CurrentRaid].disenchanter = value
            lootState.disenchanter = value
        end
        dropDownDirty = true
        dirtyFlags.dropdowns = true
        dirtyFlags.buttons = true
        CloseDropDownMenus()
    end

    --
    -- Updates the text of the dropdowns to reflect the current selection.
    --
    function UpdateDropDowns(frame)
        if not frame or not KRT_CurrentRaid then return end
        local name = frame:GetName()
        -- Update loot holder:
        if name == dropDownFrameHolder:GetName() then
            lootState.holder = KRT_Raids[KRT_CurrentRaid].holder
            if lootState.holder and addon.Raid:GetUnitID(lootState.holder) == "none" then
                KRT_Raids[KRT_CurrentRaid].holder = nil
                lootState.holder = nil
            end
            if lootState.holder then
                UIDropDownMenu_SetText(dropDownFrameHolder, lootState.holder)
                UIDropDownMenu_SetSelectedValue(dropDownFrameHolder, lootState.holder)
                dirtyFlags.buttons = true
            end
            -- Update loot banker:
        elseif name == dropDownFrameBanker:GetName() then
            lootState.banker = KRT_Raids[KRT_CurrentRaid].banker
            if lootState.banker and addon.Raid:GetUnitID(lootState.banker) == "none" then
                KRT_Raids[KRT_CurrentRaid].banker = nil
                lootState.banker = nil
            end
            if lootState.banker then
                UIDropDownMenu_SetText(dropDownFrameBanker, lootState.banker)
                UIDropDownMenu_SetSelectedValue(dropDownFrameBanker, lootState.banker)
                dirtyFlags.buttons = true
            end
            -- Update loot disenchanter:
        elseif name == dropDownFrameDisenchanter:GetName() then
            lootState.disenchanter = KRT_Raids[KRT_CurrentRaid].disenchanter
            if lootState.disenchanter and addon.Raid:GetUnitID(lootState.disenchanter) == "none" then
                KRT_Raids[KRT_CurrentRaid].disenchanter = nil
                lootState.disenchanter = nil
            end
            if lootState.disenchanter then
                UIDropDownMenu_SetText(dropDownFrameDisenchanter, lootState.disenchanter)
                UIDropDownMenu_SetSelectedValue(dropDownFrameDisenchanter, lootState.disenchanter)
                dirtyFlags.buttons = true
            end
        end
    end

    --
    -- Creates the item selection frame if it doesn't exist.
    --
    local function CreateSelectionFrame()
        if selectionFrame == nil then
            selectionFrame = CreateFrame("Frame", nil, UIMaster, "KRTSimpleFrameTemplate")
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

    --
    -- Updates the item selection frame with the current loot items.
    --
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
            itemNameBtn:SetText(itemName)
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

    --------------------------------------------------------------------------
    -- Event Handlers & Callbacks
    --------------------------------------------------------------------------

    --
    -- ITEM_LOCKED: Triggered when an item is picked up from inventory.
    --
    function module:ITEM_LOCKED(inBag, inSlot)
        if not inBag or not inSlot then return end
        local itemTexture, count, locked, quality, _, _, itemLink = GetContainerItemInfo(inBag, inSlot)
        if not itemLink or not itemTexture then return end
        addon:trace(L.LogMLItemLocked:format(tostring(inBag), tostring(inSlot), tostring(itemLink),
            tostring(count), tostring(ItemIsSoulbound(inBag, inSlot))))
        lootState.itemCount = count or lootState.itemCount or 1
        _G[frameName .. "ItemBtn"]:SetScript("OnClick", function(self)
            if countdownRun then
                return
            end
            if not ItemIsSoulbound(inBag, inSlot) then
                -- Clear count:
                Utils.resetEditBox(_G[frameName .. "ItemCount"], true)

                lootState.fromInventory = true
                addon.Loot:AddItem(itemLink, count)
                addon.Loot:PrepareItem()
                announced        = false
                -- self.Logger:SetSource("inventory")
                itemInfo.bagID   = inBag
                itemInfo.slotID  = inSlot
                itemInfo.count   = count or 1
                itemInfo.isStack = (itemInfo.count > 1)
                module:ResetItemCount(true)
            else
                addon:warn(L.LogMLInventorySoulbound:format(tostring(itemLink)))
            end
            ClearCursor()
        end)
    end

    --
    -- LOOT_OPENED: Triggered when the loot window opens.
    --
    function module:LOOT_OPENED()
        if addon.Raid:IsMasterLooter() then
            lootState.opened = true
            announced = false
            addon.Loot:FetchLoot()
            addon:trace(L.LogMLLootOpenedTrace:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory)))
            UpdateSelectionFrame()
            if lootState.lootCount >= 1 then UIMaster:Show() end
            if not addon.Logger.container then
                addon.Logger.source = UnitName("target")
            end
            addon:info(L.LogMLLootOpenedInfo:format(lootState.lootCount or 0,
                tostring(lootState.fromInventory), tostring(UnitName("target"))))
        end
    end

    --
    -- LOOT_CLOSED: Triggered when the loot window closes.
    --
    function module:LOOT_CLOSED()
        if addon.Raid:IsMasterLooter() then
            addon:trace(L.LogMLLootClosed:format(tostring(lootState.opened), lootState.lootCount or 0))
            addon:trace(L.LogMLLootClosedCleanup)
            if lootState.closeTimer then
                addon.CancelTimer(lootState.closeTimer)
                lootState.closeTimer = nil
            end
            lootState.closeTimer = addon.After(0.1, function()
                lootState.closeTimer = nil
                lootState.opened = false
                lootState.pendingAward = nil
                UIMaster:Hide()
                addon.Loot:ClearLoot()
                addon.Rolls:ClearRolls()
                addon.Rolls:RecordRolls(false)
            end)
        end
    end

    --
    -- LOOT_SLOT_CLEARED: Triggered when an item is looted.
    --
    function module:LOOT_SLOT_CLEARED()
        if addon.Raid:IsMasterLooter() then
            addon.Loot:FetchLoot()
            addon:trace(L.LogMLLootSlotCleared:format(lootState.lootCount or 0))
            UpdateSelectionFrame()
            if lootState.lootCount >= 1 then
                UIMaster:Show()
            else
                UIMaster:Hide()
                addon:info(L.LogMLLootWindowEmptied)
            end
            module:ResetItemCount()
        end
    end

    --
    -- TRADE_ACCEPT_UPDATE: Triggered during a trade.
    --
    function module:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
        addon:trace(L.LogTradeAcceptUpdate:format(tostring(lootState.trader), tostring(lootState.winner),
            tostring(tAccepted), tostring(pAccepted)))
        if lootState.trader and lootState.winner and lootState.trader ~= lootState.winner then
            if tAccepted == 1 and pAccepted == 1 then
                addon:info(L.LogTradeCompleted:format(tostring(lootState.currentRollItem),
                    tostring(lootState.winner), tonumber(lootState.currentRollType) or -1,
                    addon.Rolls:HighestRoll()))
                if lootState.currentRollItem and lootState.currentRollItem > 0 then
                    local ok = addon.Logger.Loot:Log(lootState.currentRollItem, lootState.winner,
                        lootState.currentRollType, addon.Rolls:HighestRoll(), "TRADE_ACCEPT", KRT_CurrentRaid)

                    if not ok then
                        addon:error(L.LogTradeLoggerLogFailed:format(tostring(KRT_CurrentRaid),
                            tostring(lootState.currentRollItem), tostring(GetItemLink())))
                    end
                else
                    addon:warn("Trade: currentRollItem missing; cannot update loot entry.")
                end
                local done = RegisterAwardedItem()
                ResetTradeState()
                if done then
                    addon.Loot:ClearLoot()
                    addon.Raid:ClearRaidIcons()
                end
                screenshotWarn = false
            end
        end
    end

    --
    -- TRADE_CLOSED: trade window closed (completed or canceled)
    --
    function module:TRADE_CLOSED()
        ResetTradeState("TRADE_CLOSED")
    end

    --
    -- TRADE_REQUEST_CANCEL: trade request canceled before opening
    --
    function module:TRADE_REQUEST_CANCEL()
        ResetTradeState("TRADE_REQUEST_CANCEL")
    end

    --
    -- Assigns an item from the loot window to a player.
    --
    function AssignItem(itemLink, playerName, rollType, rollValue)
        local itemIndex, tempItemLink
        for i = 1, GetNumLootItems() do
            tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                itemIndex = i
                break
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
            addon:debug(L.LogMLCandidateCacheMiss:format(tostring(itemLink), tostring(playerName)))
            BuildCandidateCache(itemLink)
            candidateIndex = candidateCache.indexByName[playerName]
        end
        if candidateIndex then
            -- Mark this award as addon-driven so AddLoot() won't classify it as MANUAL
            lootState.pendingAward = {
                itemLink  = itemLink,
                looter    = playerName,
                rollType  = rollType,
                rollValue = rollValue,
                ts        = GetTime(),
            }
            GiveMasterLoot(itemIndex, candidateIndex)
            addon:info(L.LogMLAwarded:format(tostring(itemLink), tostring(playerName),
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
            if lootState.currentRollItem and lootState.currentRollItem > 0 then
                local ok = addon.Logger.Loot:Log(lootState.currentRollItem, playerName, rollType, rollValue, "ML_AWARD",
                    KRT_CurrentRaid)
                if not ok then
                    addon:error(L.LogMLAwardLoggerFailed:format(tostring(KRT_CurrentRaid),
                        tostring(lootState.currentRollItem), tostring(itemLink)))
                end
            end
            return true
        end
        addon:error(L.ErrCannotFindPlayer:format(playerName))
        return false
    end

    --
    -- Trades an item from inventory to a player.
    --
    function TradeItem(itemLink, playerName, rollType, rollValue)
        if itemLink ~= GetItemLink() then return end
        local isAwardRoll = (rollType and rollType >= rollTypes.MAINSPEC and rollType <= rollTypes.FREE)

        ResetTradeState("TRADE_START")

        lootState.trader = Utils.getPlayerName()
        lootState.winner = isAwardRoll and playerName or nil

        addon:info(L.LogTradeStart:format(tostring(itemLink), tostring(lootState.trader),
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
            SetRaidTarget(lootState.trader, 1)
            local rolls = addon.Rolls:GetRolls()
            local winners = {}
            for i = 1, lootState.itemCount do
                if rolls[i] then
                    if rolls[i].name == lootState.trader then
                        tinsert(winners, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
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
            addon:info(L.LogTradeTraderKeeps:format(tostring(itemLink), tostring(playerName)))
            local done = RegisterAwardedItem()
            if done then
                addon.Loot:ClearLoot()
                addon.Raid:ClearRaidIcons()
            end
        else
            local unit = addon.Raid:GetUnitID(playerName)
            if unit ~= "none" and CheckInteractDistance(unit, 2) == 1 then
                -- Player is in range for trade
                if itemInfo.isStack and not addon.options.ignoreStacks then
                    addon:warn(L.LogTradeStackBlocked:format(tostring(addon.options.ignoreStacks),
                        tostring(itemLink)))
                    addon:warn(L.ErrItemStack:format(itemLink))
                    return false
                end
                ClearCursor()
                PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
                if CursorHasItem() then
                    InitiateTrade(playerName)
                    addon:info(L.LogTradeInitiated:format(tostring(itemLink), tostring(playerName)))
                    if addon.options.screenReminder and not screenshotWarn then
                        addon:warn(L.ErrScreenReminder)
                        screenshotWarn = true
                    end
                end
                -- Cannot trade the player?
            elseif unit ~= "none" then
                -- Player is out of range
                addon:warn(L.LogTradeDelayedOutOfRange:format(tostring(playerName), tostring(itemLink)))
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
                    addon:error(L.LogTradeKeepLoggerFailed:format(tostring(KRT_CurrentRaid),
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
end

---============================================================================
-- Loot Counter Module
-- Counter and display item distribution.
---============================================================================
do
    local module = addon.Master

    local rows, raidPlayers = {}, {}
    local twipe = twipe
    local countsFrame, scrollChild, needsUpdate, countsTicker = nil, nil, false, nil

    local function RequestCountsUpdate()
        needsUpdate = true
    end

    local function TickCounts()
        if needsUpdate then
            needsUpdate = false
            addon.Master:UpdateCountsFrame()
        end
    end

    local function StartCountsTicker()
        if not countsTicker then
            countsTicker = addon.NewTicker(C.LOOT_COUNTER_TICK_INTERVAL, TickCounts)
        end
    end

    local function StopCountsTicker()
        if countsTicker then
            addon.CancelTimer(countsTicker, true)
            countsTicker = nil
        end
    end

    -- Helper to ensure frames exist
    local function EnsureFrames()
        countsFrame = countsFrame or _G["KRTLootCounterFrame"]
        scrollChild = scrollChild or _G["KRTLootCounterFrameScrollFrameScrollChild"]
        if countsFrame and not countsFrame._krtCounterHook then
            local title = _G["KRTLootCounterFrameTitle"]
            Utils.setFrameTitle("KRTLootCounterFrame", L.StrLootCounter)
            if title then title:Show() end
            countsFrame:SetScript("OnShow", StartCountsTicker)
            countsFrame:SetScript("OnHide", StopCountsTicker)
            countsFrame._krtCounterHook = true
        end
    end

    -- Return sorted array of player names currently in the raid.
    local function GetCurrentRaidPlayers()
        twipe(raidPlayers)
        if not addon.IsInGroup() then
            return raidPlayers
        end
        for unit, owner in addon.UnitIterator(true) do
            local name = UnitName(unit)
            if name and name ~= "" then
                raidPlayers[#raidPlayers + 1] = name
                if KRT_PlayerCounts[name] == nil then
                    KRT_PlayerCounts[name] = 0
                end
            end
        end
        table.sort(raidPlayers)
        return raidPlayers
    end

    -- Show or hide the loot counter frame.
    function module:ToggleCountsFrame()
        EnsureFrames()
        if countsFrame then
            if countsFrame:IsShown() then
                Utils.setShown(countsFrame, false)
            else
                RequestCountsUpdate()
                Utils.setShown(countsFrame, true)
            end
        end
    end

    -- Update the loot counter UI with current player counts.
    function module:UpdateCountsFrame()
        EnsureFrames()
        if not countsFrame or not scrollChild then return end

        local players = GetCurrentRaidPlayers()
        local numPlayers = #players
        local rowHeight = C.LOOT_COUNTER_ROW_HEIGHT
        local counts = KRT_PlayerCounts

        scrollChild:SetHeight(numPlayers * rowHeight)

        -- Create/reuse rows for each player
        for i = 1, numPlayers do
            local name = players[i]
            local row  = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, scrollChild)
                row:SetSize(160, 24)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)

                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.name:SetPoint("LEFT", row, "LEFT", 0, 0)

                row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.count:SetPoint("LEFT", row.name, "RIGHT", 10, 0)

                row.plus = CreateFrame("Button", nil, row, "KRTButtonTemplate")
                row.plus:SetSize(22, 22)
                row.plus:SetText("+")
                row.plus:SetPoint("LEFT", row.count, "RIGHT", 5, 0)

                row.minus = CreateFrame("Button", nil, row, "KRTButtonTemplate")
                row.minus:SetSize(22, 22)
                row.minus:SetText("-")
                row.minus:SetPoint("LEFT", row.plus, "RIGHT", 2, 0)

                row.plus:SetScript("OnClick", function()
                    local n = row._playerName
                    if n then
                        counts[n] = (counts[n] or 0) + 1
                        RequestCountsUpdate()
                    end
                end)
                row.minus:SetScript("OnClick", function()
                    local n = row._playerName
                    if n then
                        local c = (counts[n] or 0) - 1
                        counts[n] = c > 0 and c or 0
                        RequestCountsUpdate()
                    end
                end)

                rows[i] = row
            else
                -- Move if needed (in case of roster change)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            end

            row._playerName = name
            row.name:SetText(name)
            row.count:SetText(tostring(counts[name] or 0))
            row:Show()
        end

        -- Hide extra rows not needed
        for i = numPlayers + 1, #rows do
            if rows[i] then rows[i]:Hide() end
        end
    end

    -- Add a button to the master loot frame to open the loot counter UI
    -------------------------------------------------------
    -- Event hooks
    -------------------------------------------------------
    local function SetupMasterLootFrameHooks()
        local f = _G["KRTMasterLootFrame"]
        if f and not f.KRT_LootCounterBtn then
            local btn = CreateFrame("Button", nil, f, "KRTButtonTemplate")
            btn:SetSize(100, 24)
            btn:SetText(L.BtnLootCounter)
            btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -20)
            btn:SetScript("OnClick", function()
                addon.Master:ToggleCountsFrame()
            end)
            f.KRT_LootCounterBtn = btn

            f:HookScript("OnHide", function()
                if countsFrame and countsFrame:IsShown() then
                    Utils.setShown(countsFrame, false)
                end
            end)
        end
    end
    hooksecurefunc(addon.Master, "OnLoad", SetupMasterLootFrameHooks)
end

---============================================================================
-- Reserves Module
-- Manages item reserves, import, and display.
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Reserves = addon.Reserves or {}
    local module = addon.Reserves
    local L = addon.L
    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    -- UI Elements
    local frameName
    local reserveListFrame, scrollFrame, scrollChild
    local reserveHeaders = {}
    local reserveItemRows, rowsByItemID = {}, {}

    -- State variables
    local localized = false
    local updateInterval = C.UPDATE_INTERVAL_RESERVES
    local reservesData = {}
    local reservesByItemID = {}
    local reservesDisplayList = {}
    local reservesDirty = false
    local pendingItemInfo = {}
    local pendingItemCount = 0
    local collapsedBossGroups = {}
    local grouped = {}

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    local playerTextTemp = {}

    local function MarkPendingItem(itemId, hasName, hasIcon)
        if not itemId then return nil end
        local pending = pendingItemInfo[itemId]
        if not pending then
            pending = {
                nameReady = false,
                iconReady = false
            }
            pendingItemInfo[itemId] = pending
            pendingItemCount = pendingItemCount + 1
            addon:debug("Reserves: track pending itemId=%d pending=%d.", itemId, pendingItemCount)
        end
        if hasName then
            pending.nameReady = true
        end
        if hasIcon then
            pending.iconReady = true
        end
        return pending
    end

    local function CompletePendingItem(itemId)
        if not itemId or not pendingItemInfo[itemId] then return end
        pendingItemInfo[itemId] = nil
        if pendingItemCount > 0 then
            pendingItemCount = pendingItemCount - 1
        end
        addon:debug("Reserves: item ready itemId=%d pending=%d.", itemId, pendingItemCount)
        if pendingItemCount == 0 then
            addon:debug("Reserves: pending item info complete.")
            if reserveListFrame and reserveListFrame:IsShown() then
                module:RefreshWindow()
            end
        end
    end

    local function FormatReservePlayerName(name, count)
        if count and count > 1 then
            return name .. format(L.StrReserveCountSuffix, count)
        end
        return name
    end

    local function AddReservePlayer(data, name, count)
        if not data.players then data.players = {} end
        if not data.playerCounts then data.playerCounts = {} end
        local existing = data.playerCounts[name]
        if existing then
            data.playerCounts[name] = existing + (count or 1)
        else
            data.players[#data.players + 1] = name
            data.playerCounts[name] = count or 1
        end
    end

    local function BuildPlayersText(players, counts)
        if not players then return "" end
        twipe(playerTextTemp)
        for i = 1, #players do
            local name = players[i]
            playerTextTemp[#playerTextTemp + 1] = FormatReservePlayerName(name, counts and counts[name] or 1)
        end
        return tconcat(playerTextTemp, ", ")
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
                    local source = r.source or "Unknown"
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
                        }
                        bySource[itemId] = data
                    end
                    AddReservePlayer(data, r.player or "?", r.quantity or 1)
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
                    twipe(target.players)
                    twipe(target.playerCounts)
                    for i = 1, #data.players do
                        local name = data.players[i]
                        target.players[i] = name
                        target.playerCounts[name] = data.playerCounts[name]
                    end
                    target.playersText = BuildPlayersText(target.players, target.playerCounts)
                    target.players = nil
                    target.playerCounts = nil
                    remaining[#remaining + 1] = target
                else
                    data.playersText = BuildPlayersText(data.players, data.playerCounts)
                    data.players = nil
                    data.playerCounts = nil
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
        reservesDirty = true
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                local playerName = player.original or "?"
                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID then
                        r.player = r.player or playerName
                        local list = reservesByItemID[r.rawID]
                        if not list then
                            list = {}
                            reservesByItemID[r.rawID] = list
                        end
                        list[#list + 1] = r
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
                        local source = r.source or "Unknown"

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
                            }
                            bySource[itemId] = data
                        end

                        AddReservePlayer(data, r.player or "?", r.quantity or 1)
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, data in pairs(byItem) do
                data.playersText = BuildPlayersText(data.players, data.playerCounts)
                data.players = nil
                data.playerCounts = nil
                reservesDisplayList[#reservesDisplayList + 1] = data
            end
        end
    end

    local function SetupReserveRowTooltip(row)
        if not row or not row.iconBtn then return end
        row.iconBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row.iconBtn, "ANCHOR_RIGHT")
            if row._itemLink then
                GameTooltip:SetHyperlink(row._tooltipTitle)
            elseif row._tooltipTitle then
                GameTooltip:SetText(row._tooltipTitle, 1, 1, 1)
            end
            if row._tooltipSource then
                GameTooltip:AddLine(row._tooltipSource, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        row.iconBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local function ApplyReserveRowData(row, info, index)
        if not row or not info then return end
        row._itemId = info.itemId
        row._itemLink = info.itemLink
        row._itemName = info.itemName
        row._source = info.source
        row._tooltipTitle = info.itemLink or info.itemName or ("Item ID: " .. (info.itemId or "?"))
        row._tooltipSource = info.source and ("Dropped by: " .. info.source) or nil

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
            row.nameText:SetText(info.itemLink or info.itemName or ("[Item " .. info.itemId .. "]"))
        end

        if row.playerText then
            row.playerText:SetText(info.playersText or "")
        end
        if row.quantityText then
            row.quantityText:Hide()
        end
    end

    local function ReserveHeaderOnClick(self)
        local source = self and self._source
        if not source then return end
        collapsedBossGroups[source] = not collapsedBossGroups[source]
        addon:debug("Reserves: toggle collapse source=%s state=%s.", source,
            tostring(collapsedBossGroups[source]))
        module:RefreshWindow()
    end

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    -- Local functions
    local LocalizeUIFrame
    local UpdateUIFrame

    --------------------------------------------------------------------------
    -- Saved Data Management
    --------------------------------------------------------------------------

    function module:Save()
        RebuildIndex()
        addon:debug("Reserves: save entries=%d.", addon.tLength(reservesData))
        local saved = {}
        addon.tCopy(saved, reservesData)
        KRT_SavedReserves = saved
    end

    function module:Load()
        addon:debug("Reserves: load data=%s.", tostring(KRT_SavedReserves ~= nil))
        twipe(reservesData)
        if KRT_SavedReserves then
            addon.tCopy(reservesData, KRT_SavedReserves)
        end
        RebuildIndex()
    end

    function module:ResetSaved()
        addon:debug("Reserves: reset saved data.")
        KRT_SavedReserves = nil
        twipe(reservesData)
        twipe(reservesByItemID)
        twipe(reservesDisplayList)
        reservesDirty = true
        self:RefreshWindow()
        self:CloseWindow()
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

    --------------------------------------------------------------------------
    -- UI Window Management
    --------------------------------------------------------------------------

    function module:ShowWindow()
        if not reserveListFrame then
            addon:error("Reserve List frame not available.")
            return
        end
        addon:debug("Reserves: show list window.")
        reserveListFrame:Show()
        self:RefreshWindow()
    end

    function module:CloseWindow()
        addon:debug("Reserves: hide list window.")
        if reserveListFrame then reserveListFrame:Hide() end
    end

    function module:ShowImportBox()
        addon:debug("Reserves: open import window.")
        local frame = _G["KRTImportWindow"]
        if not frame then
            addon:error("KRTImportWindow not found.")
            return
        end
        frame:Show()
        Utils.resetEditBox(_G["KRTImportEditBox"])
        Utils.setFrameTitle(frame, L.StrImportReservesTitle)
    end

    function module:CloseImportWindow()
        local frame = _G["KRTImportWindow"]
        if frame then
            frame:Hide()
        end
    end

    function module:ImportFromEditBox()
        local editBox = _G["KRTImportEditBox"]
        if not editBox then return end
        local csv = editBox:GetText()
        if csv and csv ~= "" then
            addon:info(L.LogSRImportRequested:format(#csv))
            self:ParseCSV(csv)
        end
        self:CloseImportWindow()
    end

    function module:OnLoad(frame)
        addon:debug("Reserves: frame loaded.")
        reserveListFrame = frame
        frameName = frame:GetName()

        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetScript("OnUpdate", UpdateUIFrame)

        scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"]
        scrollChild = scrollFrame and scrollFrame.ScrollChild or _G["KRTReserveListFrameScrollChild"]

        local buttons = {
            CloseButton = "CloseWindow",
            ClearButton = "ResetSaved",
            QueryButton = "QueryMissingItems",
        }
        for suff, method in pairs(buttons) do
            local btn = _G["KRTReserveListFrame" .. suff]
            if btn and self[method] then
                btn:SetScript("OnClick", function() self[method](self) end)
                addon:debug("Reserves: bind button=%s action=%s.", suff, method)
            end
        end

        LocalizeUIFrame()

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:debug("Reserves: item info received itemId=%d.", itemId)
            if pendingItemInfo[itemId] then
                local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
                local icon = tex
                if type(icon) ~= "string" or icon == "" then
                    icon = GetItemIcon(itemId)
                end
                local hasName = type(name) == "string" and name ~= ""
                    and type(link) == "string" and link ~= ""
                local hasIcon = type(icon) == "string" and icon ~= ""
                if hasName then
                    addon:debug("Reserves: update item data %s.", link)
                    self:UpdateReserveItemData(itemId, name, link, icon)
                else
                    addon:debug("Reserves: item info missing itemId=%d.", itemId)
                end
                MarkPendingItem(itemId, hasName, hasIcon)
                if hasName and hasIcon then
                    addon:info(L.LogSRItemInfoResolved:format(itemId, tostring(link)))
                    CompletePendingItem(itemId)
                else
                    addon:debug("Reserves: item info still pending itemId=%d.", itemId)
                    self:QueryItemInfo(itemId)
                end
            end
        end)
    end

    --------------------------------------------------------------------------
    -- Localization and UI Update
    --------------------------------------------------------------------------

    function LocalizeUIFrame()
        if localized then
            addon:debug("Reserves: UI already localized.")
            return
        end
        if frameName then
            Utils.setFrameTitle(frameName, L.StrRaidReserves)
            addon:debug("Reserves: UI localized %s.", L.StrRaidReserves)
        end
        localized = true
    end

    -- Update UI Frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
            local hasData = module:HasData()
            local clearButton = _G[frameName .. "ClearButton"]
            if clearButton then
                Utils.enableDisable(clearButton, hasData)
            end
            local queryButton = _G[frameName .. "QueryButton"]
            if queryButton then
                Utils.enableDisable(queryButton, hasData)
            end
        end)
    end

    --------------------------------------------------------------------------
    -- Reserve Data Handling
    --------------------------------------------------------------------------

    function module:GetReserve(playerName)
        if type(playerName) ~= "string" then return nil end
        local player = Utils.normalizeLower(playerName)
        local reserve = reservesData[player]

        -- Log when the function is called and show the reserve for the player
        if reserve then
            addon:debug("Reserves: player found %s data=%s.", playerName, tostring(reserve))
        else
            addon:debug("Reserves: player not found %s.", playerName)
        end

        return reserve
    end

    -- Get all reserves:
    function module:GetAllReserves()
        addon:debug("Reserves: fetch all players=%d.", addon.tLength(reservesData))
        return reservesData
    end

    -- Parse imported text
    function module:ParseCSV(csv)
        if type(csv) ~= "string" or not csv:match("%S") then
            addon:error("Import failed: empty or invalid data.")
            return
        end

        addon:debug("Reserves: parse CSV start.")
        twipe(reservesData)
        twipe(reservesByItemID)
        reservesDirty = true

        local function cleanCSVField(field)
            if not field then return nil end
            return Utils.trimText(field:gsub('^"(.-)"$', '%1'), true)
        end

        local firstLine = true
        for line in csv:gmatch("[^\r\n]+") do
            if firstLine then
                firstLine = false
            else
                local _, itemIdStr, source, playerName, class, spec, note, plus = line:match(
                    '^"?(.-)"?,(.-),(.-),(.-),(.-),(.-),(.-),(.-)')

                itemIdStr = cleanCSVField(itemIdStr)
                source = cleanCSVField(source)
                playerName = cleanCSVField(playerName)
                class = cleanCSVField(class)
                spec = cleanCSVField(spec)
                note = cleanCSVField(note)
                plus = cleanCSVField(plus)

                local itemId = tonumber(itemIdStr)
                local normalized = Utils.normalizeLower(playerName, true)

                if normalized and itemId then
                    reservesData[normalized] = reservesData[normalized] or {
                        original = playerName,
                        reserves = {}
                    }

                    local list = reservesData[normalized].reserves
                    local found = false
                    for i = 1, #list do
                        local entry = list[i]
                        if entry and entry.rawID == itemId then
                            entry.quantity = (entry.quantity or 1) + 1
                            found = true
                            break
                        end
                    end

                    if not found then
                        list[#list + 1] = {
                            rawID = itemId,
                            itemLink = nil,
                            itemName = nil,
                            itemIcon = nil,
                            quantity = 1,
                            class = class ~= "" and class or nil,
                            spec = spec ~= "" and spec or nil,
                            note = note ~= "" and note or nil,
                            plus = tonumber(plus) or 0,
                            source = source ~= "" and source or nil,
                            player = playerName
                        }
                    end
                else
                    addon:warn(L.LogSRParseSkippedLine:format(tostring(line)))
                end
            end
        end

        RebuildIndex()
        addon:debug("Reserves: parse CSV complete players=%d.", addon.tLength(reservesData))
        addon:info(L.LogSRImportComplete:format(addon.tLength(reservesData)))
        self:RefreshWindow()
        self:Save()
    end

    --------------------------------------------------------------------------
    -- Item Info Querying
    --------------------------------------------------------------------------

    function module:QueryItemInfo(itemId)
        if not itemId then return end
        addon:debug("Reserves: query item info itemId=%d.", itemId)
        local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
        local icon = tex
        if type(icon) ~= "string" or icon == "" then
            icon = GetItemIcon(itemId)
        end
        local hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        local hasIcon = type(icon) == "string" and icon ~= ""
        if hasName then
            self:UpdateReserveItemData(itemId, name, link, icon)
        end
        MarkPendingItem(itemId, hasName, hasIcon)
        if hasName and hasIcon then
            addon:debug("Reserves: item info ready itemId=%d name=%s.", itemId, name)
            CompletePendingItem(itemId)
            return true
        end

        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Hide()
        addon:debug("Reserves: item info pending itemId=%d.", itemId)
        return false
    end

    -- Query all missing items for reserves
    function module:QueryMissingItems(silent)
        local seen = {}
        local count = 0
        local updated = false
        addon:debug("Reserves: query missing items.")
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
        if updated and reserveListFrame and reserveListFrame:IsShown() then
            self:RefreshWindow()
        end
        if not silent then
            if count > 0 then
                addon:info(L.MsgReserveItemsRequested, count)
            else
                addon:info(L.MsgReserveItemsReady)
            end
        end
        addon:debug("Reserves: missing items requested=%d.", count)
        addon:debug(L.LogSRQueryMissingItems:format(tostring(updated), count))
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
            row._tooltipTitle = itemLink or itemName or ("Item ID: " .. itemId)
            row._tooltipSource = row._source and ("Dropped by: " .. row._source) or nil
            if row.iconTexture then
                local resolvedIcon = icon
                if type(resolvedIcon) ~= "string" or resolvedIcon == "" then
                    resolvedIcon = fallbackIcon
                end
                row.iconTexture:SetTexture(resolvedIcon)
                row.iconTexture:Show()
            end
            if row.nameText then
                row.nameText:SetText(itemLink or itemName or ("Item ID: " .. itemId))
            end
        end
    end

    -- Get reserve count for a specific item for a player
    function module:GetReserveCountForItem(itemId, playerName)
        local normalized = Utils.normalizeLower(playerName, true)
        local entry = reservesData[normalized]
        if not entry then return 0 end
        addon:debug("Reserves: check count itemId=%d player=%s.", itemId, playerName)
        for _, r in ipairs(entry.reserves or {}) do
            if r.rawID == itemId then
                addon:debug("Reserves: found itemId=%d player=%s qty=%d.", itemId, playerName,
                    r.quantity)
                return r.quantity or 1
            end
        end
        addon:debug("Reserves: none itemId=%d player=%s.", itemId, playerName)
        return 0
    end

    --------------------------------------------------------------------------
    -- UI Display
    --------------------------------------------------------------------------

    function module:RefreshWindow()
        if not reserveListFrame or not scrollChild then return end

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

    --------------------------------------------------------------------------
    -- SR Announcement Formatting
    --------------------------------------------------------------------------

    function module:GetPlayersForItem(itemId)
        if not itemId then return {} end
        local list = reservesByItemID[itemId]
        if type(list) ~= "table" then return {} end

        local players = {}
        for i = 1, #list do
            local r = list[i]
            local qty = (type(r) == "table" and r.quantity) or 1
            qty = qty or 1
            local name = (type(r) == "table" and r.player) or "?"
            players[#players + 1] = FormatReservePlayerName(name, qty)
        end
        return players
    end

    function module:FormatReservedPlayersLine(itemId)
        addon:debug("Reserves: format players itemId=%d.", itemId)
        local list = self:GetPlayersForItem(itemId)
        -- Log the list of players found for the item
        addon:debug("Reserves: players itemId=%d list=%s.", itemId, tconcat(list, ", "))
        return #list > 0 and tconcat(list, ", ") or ""
    end
end

---============================================================================
-- Configuration Frame Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Config = addon.Config or {}
    local module = addon.Config
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local localized = false
    local configDirty = false

    -- Frame update
    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_CONFIG

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    local LocalizeUIFrame

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    --
    -- Default options for the addon.
    --
    local defaultOptions = {
        sortAscending          = false,
        useRaidWarning         = true,
        announceOnWin          = true,
        announceOnHold         = true,
        announceOnBank         = false,
        announceOnDisenchant   = false,
        lootWhispers           = false,
        screenReminder         = true,
        ignoreStacks           = false,
        showTooltips           = true,
        minimapButton          = true,
        countdownSimpleRaidMsg = false,
        countdownDuration      = 5,
        countdownRollsBlock    = true,
    }

    --
    -- Loads the default options into the settings table.
    --
    local function LoadDefaultOptions()
        local options = {}
        addon.tCopy(options, defaultOptions)
        KRT_Options = options
        addon.options = options
        configDirty = true
        addon:info(L.MsgDefaultsRestored)
    end

    --
    -- Loads addon options from saved variables, filling in defaults.
    --
    local function LoadOptions()
        local options = {}
        addon.tCopy(options, defaultOptions)
        if KRT_Options then
            addon.tCopy(options, KRT_Options)
        end
        KRT_Options = options
        addon.options = options

        Utils.applyDebugSetting(addon.options.debug)
        configDirty = true

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

    --
    -- Public method to reset options to default.
    --
    function module:Default()
        return LoadDefaultOptions()
    end

    --
    -- OnLoad handler for the configuration frame.
    --
    function module:OnLoad(frame)
        if not frame then return end
        UIConfig = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")

        -- Localize once (no per-tick calls)
        LocalizeUIFrame()

        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    --
    -- Toggles the visibility of the configuration frame.
    --
    function module:Toggle()
        local wasShown = UIConfig and UIConfig:IsShown()
        Utils.toggle(UIConfig)
        if UIConfig and UIConfig:IsShown() and not wasShown then
            configDirty = true
        end
    end

    --
    -- Hides the configuration frame.
    --
    function module:Hide()
        Utils.hideFrame(UIConfig)
    end

    --
    -- OnClick handler for option controls.
    --
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
    end

    --
    -- Localizes UI elements.
    --
    function LocalizeUIFrame()
        if localized then
            return
        end

        -- frameName must be ready here (OnLoad sets it before calling)
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
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
            _G[frameName .. "minimapButtonStr"]:SetText(L.StrConfigMinimapButton)
            _G[frameName .. "countdownDurationStr"]:SetText(L.StrConfigCountdownDuration)
            _G[frameName .. "countdownSimpleRaidMsgStr"]:SetText(L.StrConfigCountdownSimpleRaidMsg)
        end

        Utils.setFrameTitle(frameName, SETTINGS)
        _G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
        _G[frameName .. "DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)

        localized = true
    end

    --
    -- OnUpdate handler for the configuration frame.
    --
    function UpdateUIFrame(self, elapsed)
        if configDirty then
            Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
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
            end)
        end
    end
end

---============================================================================
-- Warnings Frame Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Warnings = addon.Warnings or {}
    local module = addon.Warnings
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_WARNINGS

    local FetchWarnings
    local fetched = false
    local warningsDirty = false

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode

    local tempName, tempContent
    local SaveWarning
    local isEdit = false

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIWarnings = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:HookScript("OnShow", function()
            warningsDirty = true
            lastSelectedID = false
        end)
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Externally update frame:
    function module:Update()
        warningsDirty = true
    end

    -- Toggle frame visibility:
    function module:Toggle()
        Utils.toggle(UIWarnings)
    end

    -- Hide frame:
    function module:Hide()
        Utils.hideFrame(UIWarnings)
    end

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
    end

    -- Localizing UI frame:
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            _G[frameName .. "MessageStr"]:SetText(L.StrMessage)
            _G[frameName .. "EditBtn"]:SetText(SAVE)
            _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelpTitle)
        end
        Utils.setFrameTitle(frameName, RAID_WARNING)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Content"]:SetScript("OnEscapePressed", module.Cancel)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Content"]:SetScript("OnEnterPressed", module.Edit)
        localized = true
    end

    local function UpdateSelectionUI()
        if lastSelectedID and _G[frameName .. "WarningBtn" .. lastSelectedID] then
            _G[frameName .. "WarningBtn" .. lastSelectedID]:UnlockHighlight()
        end
        if selectedID and KRT_Warnings[selectedID] then
            local btn = _G[frameName .. "WarningBtn" .. selectedID]
            if btn then
                btn:LockHighlight()
            end
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
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
            if warningsDirty or not fetched then
                FetchWarnings()
                warningsDirty = false
            end
            if selectedID ~= lastSelectedID then
                UpdateSelectionUI()
            end
            tempName    = _G[frameName .. "Name"]:GetText()
            tempContent = _G[frameName .. "Content"]:GetText()
            Utils.enableDisable(_G[frameName .. "EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
            Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID ~= nil)
            Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID ~= nil)
            local editBtnMode = (tempName ~= "" or tempContent ~= "") or selectedID == nil
            if editBtnMode ~= lastEditBtnMode then
                Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, editBtnMode)
                lastEditBtnMode = editBtnMode
            end
        end)
    end

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

    -- Fetch module:
    function FetchWarnings()
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        local totalHeight = 0
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())
        for i, w in pairs(KRT_Warnings) do
            local btnName = frameName .. "WarningBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTWarningButtonTemplate")
            btn:Show()
            local ID = _G[btnName .. "ID"]
            ID:SetText(i)
            local wName = _G[btnName .. "Name"]
            wName:SetText(w.name)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
        fetched = true
        lastSelectedID = false
    end
end

---============================================================================
-- MS Changes Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Changes = addon.Changes or {}
    local module = addon.Changes
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_CHANGES

    local changesTable = {}
    local FetchChanges, SaveChanges, CancelChanges
    local fetched = false
    local changesDirty = false
    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode
    local lastAddBtnMode
    local isAdd = false
    local isEdit = false

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIChanges = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:HookScript("OnShow", function()
            changesDirty = true
            lastSelectedID = false
        end)
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Toggle frame visibility:
    function module:Toggle()
        CancelChanges()
        Utils.toggle(UIChanges)
    end

    -- Hide frame:
    function module:Hide()
        Utils.hideFrame(UIChanges, CancelChanges)
    end

    -- Clear module:
    function module:Clear()
        if not KRT_CurrentRaid or changesTable == nil then return end
        for n, p in pairs(changesTable) do
            changesTable[n] = nil
            if _G[frameName .. "PlayerBtn" .. n] then
                _G[frameName .. "PlayerBtn" .. n]:Hide()
            end
        end
        CancelChanges()
        fetched = false
        changesDirty = true
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
            if _G[frameName .. "PlayerBtn" .. name] then
                _G[frameName .. "PlayerBtn" .. name]:Hide()
            end
            fetched = false
            changesDirty = true
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
    end

    -- Add / Delete:
    function module:Add(btn)
        if not KRT_CurrentRaid or not btn then return end
        if not selectedID then
            btn:Hide()
            _G[frameName .. "Name"]:Show()
            _G[frameName .. "Name"]:SetFocus()
            isAdd = true
        elseif changesTable[selectedID] then
            changesTable[selectedID] = nil
            if _G[frameName .. "PlayerBtn" .. selectedID] then
                _G[frameName .. "PlayerBtn" .. selectedID]:Hide()
            end
            CancelChanges()
            fetched = false
            changesDirty = true
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
        end
    end

    -- Remove player's change:
    function module:Delete(name)
        if not KRT_CurrentRaid or not name then return end
        KRT_Raids[KRT_CurrentRaid].changes[name] = nil
        if _G[frameName .. "PlayerBtn" .. name] then
            _G[frameName .. "PlayerBtn" .. name]:Hide()
        end
        changesDirty = true
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
        if not fetched or #changesTable == 0 then
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
            local i = count
            for n, c in pairs(changesTable) do
                msg = msg .. " " .. n .. "=" .. c
                i = i - 1
                if i > 0 then msg = msg .. " /" end
            end
        end
        addon:Announce(msg)
    end

    -- Localize UI Frame:
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
            _G[frameName .. "AddBtn"]:SetText(ADD)
            _G[frameName .. "EditBtn"]:SetText(L.BtnEdit)
            _G[frameName .. "DemandBtn"]:SetText(L.BtnDemand)
            _G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
        end
        Utils.setFrameTitle(frameName, L.StrChanges)
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Spec"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Spec"]:SetScript("OnEscapePressed", CancelChanges)
        localized = true
    end

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
            if changesDirty or not fetched then
                InitChangesTable()
                FetchChanges()
                changesDirty = false
            end
            local count = addon.tLength(changesTable)
            if count > 0 then
            else
                tempSelectedID = nil
                selectedID = nil
            end
            if selectedID ~= lastSelectedID then
                if lastSelectedID and _G[frameName .. "PlayerBtn" .. lastSelectedID] then
                    _G[frameName .. "PlayerBtn" .. lastSelectedID]:UnlockHighlight()
                end
                if selectedID and _G[frameName .. "PlayerBtn" .. selectedID] then
                    _G[frameName .. "PlayerBtn" .. selectedID]:LockHighlight()
                end
                lastSelectedID = selectedID
            end
            Utils.showHide(_G[frameName .. "Name"], (isEdit or isAdd))
            Utils.showHide(_G[frameName .. "Spec"], (isEdit or isAdd))
            Utils.enableDisable(_G[frameName .. "EditBtn"], (selectedID or isEdit or isAdd))
            local editBtnMode = isAdd or (selectedID and isEdit)
            if editBtnMode ~= lastEditBtnMode then
                Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, editBtnMode)
                lastEditBtnMode = editBtnMode
            end
            local addBtnMode = (not selectedID and not isEdit and not isAdd)
            if addBtnMode ~= lastAddBtnMode then
                Utils.setText(_G[frameName .. "AddBtn"], ADD, DELETE, addBtnMode)
                lastAddBtnMode = addBtnMode
            end
            Utils.showHide(_G[frameName .. "AddBtn"], (not isEdit and not isAdd))
            Utils.enableDisable(_G[frameName .. "ClearBtn"], count > 0)
            Utils.enableDisable(_G[frameName .. "AnnounceBtn"], count > 0)
            Utils.enableDisable(_G[frameName .. "AddBtn"], KRT_CurrentRaid)
            Utils.enableDisable(_G[frameName .. "DemandBtn"], KRT_CurrentRaid)
        end)
    end

    -- Initialize changes table:
    function InitChangesTable()
        addon:debug("Changes: init table.")
        changesTable = KRT_CurrentRaid and KRT_Raids[KRT_CurrentRaid].changes or {}
    end

    -- Fetch All module:
    function FetchChanges()
        addon:debug("Changes: fetch all.")
        if not KRT_CurrentRaid then return end
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        local totalHeight = 0
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())
        for n, c in pairs(changesTable) do
            local btnName = frameName .. "PlayerBtn" .. n
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTChangesButtonTemplate")
            btn:Show()
            local name = _G[btnName .. "Name"]
            name:SetText(n)
            local class = addon.Raid:GetPlayerClass(n)
            local r, g, b = Utils.getClassColor(class)
            name:SetVertexColor(r, g, b)
            _G[btnName .. "Spec"]:SetText(c)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
        fetched = true
        lastSelectedID = false
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
    end

    -- Cancel all actions:
    function CancelChanges()
        isAdd = false
        isEdit = false
        selectedID = nil
        tempSelectedID = nil
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Spec"])
    end
end

---============================================================================
-- LFM Spam Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Spammer = addon.Spammer or {}
    local module = addon.Spammer
    local L = addon.L

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local frameName

    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_SPAMMER
    local updateTicker

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
    local StartTicker
    local StopTicker
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

        if UISpammer and UISpammer:IsShown() then
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

        if UISpammer and UISpammer:IsShown() then
            if previewDirty or not finalOutput or finalOutput == "" then
                RenderPreview()
                previewDirty = false
            end
        end
    end

    local function ResetLengthUI()
        if not UISpammer then return end
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

        UISpammer = frame
        frameName = frame:GetName()

        -- Localize once (not per tick)
        LocalizeUIFrame()

        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnShow", StartTicker)
        frame:SetScript("OnHide", StopTicker)

        if frame:IsShown() then
            StartTicker()
        end
    end

    -- Toggle/Hide
    function module:Toggle()
        Utils.toggle(UISpammer)
    end

    function module:Hide()
        Utils.hideFrame(UISpammer)
    end

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
                StartTicker()
                StartSpamCycle(true)
            end
            UpdateControls()
        end
    end

    function module:Stop()
        ticking = false
        paused = false
        StopSpamCycle(true)
        SetInputsLocked(false)

        if UISpammer and not UISpammer:IsShown() then
            StopTicker()
        end

        UpdateControls()
    end

    function module:Pause()
        if not ticking or paused then return end
        paused = true
        StopSpamCycle(false)
        SetInputsLocked(false)
        UpdateControls()
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

        -- Keep your current behavior (no "point 2")
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            _G[frameName .. "CompStr"]:SetText(L.StrSpammerCompStr)
            _G[frameName .. "NeedStr"]:SetText(L.StrSpammerNeedStr)
            _G[frameName .. "MessageStr"]:SetText(L.StrSpammerMessageStr)
            _G[frameName .. "PreviewStr"]:SetText(L.StrSpammerPreviewStr)
        end

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
                end
            end)

            box:SetScript("OnEnterPressed", function(self)
                module:Save(self)
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

    -- UI ticker
    function StartTicker()
        if updateTicker then return end

        local interval = tonumber(updateInterval) or 0.05
        updateTicker = addon.NewTicker(interval, function()
            if UISpammer then
                UpdateUIFrame(UISpammer, interval)
            end
        end)
    end

    function StopTicker()
        if not updateTicker then return end
        addon.CancelTimer(updateTicker, true)
        updateTicker = nil
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

        if UISpammer then
            SetInputsLocked(locked)
        end

        Utils.setText(_G[frameName .. "StartBtn"], btnLabel, START, isStop)
        Utils.enableDisable(_G[frameName .. "StartBtn"], canStart)

        lastControls.locked = locked
        lastControls.canStart = canStart
        lastControls.btnLabel = btnLabel
        lastControls.isStop = isStop
    end

    -- Preview render
    function RenderPreview()
        if not UISpammer or not UISpammer:IsShown() then return end

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
    function UpdateUIFrame(self, elapsed)
        if not (UISpammer and UISpammer:IsShown()) then
            StopTicker()
            return
        end

        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
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
        end)
    end
end

-- ============================================================================
-- Logger Frame
-- Shown loot logger for raids
-- ============================================================================
do
    addon.Logger = addon.Logger or {}
    local Logger = addon.Logger
    local L = addon.L

    local frameName

    Logger.selectedRaid = nil
    Logger.selectedBoss = nil
    Logger.selectedPlayer = nil
    Logger.selectedBossPlayer = nil
    Logger.selectedItem = nil

    local function clearSelections()
        Logger.selectedBoss = nil
        Logger.selectedPlayer = nil
        Logger.selectedBossPlayer = nil
        Logger.selectedItem = nil
    end

    local function toggleSelection(field, id, eventName)
        Logger[field] = (id and id ~= Logger[field]) and id or nil
        if eventName then
            Utils.triggerEvent(eventName, Logger[field])
        end
    end

    function Logger:ResetSelections()
        clearSelections()
    end

    function Logger:OnLoad(frame)
        UILogger, frameName = frame, frame:GetName()
        frame:RegisterForDrag("LeftButton")
        Utils.setFrameTitle(frameName, L.StrLootLogger)

        frame:SetScript("OnShow", function()
            if not Logger.selectedRaid then
                Logger.selectedRaid = KRT_CurrentRaid
            end
            clearSelections()
            Utils.triggerEvent("LoggerSelectRaid", Logger.selectedRaid)
        end)

        frame:SetScript("OnHide", function()
            Logger.selectedRaid = KRT_CurrentRaid
            clearSelections()
        end)
    end

    function Logger:Toggle() Utils.toggle(UILogger) end

    function Logger:Hide()
        Logger.selectedRaid = KRT_CurrentRaid
        clearSelections()
        Utils.showHide(UILogger, false)
    end

    -- Selectors
    function Logger:SelectRaid(btn)
        local id = btn and btn.GetID and btn:GetID()
        Logger.selectedRaid = (id and id ~= Logger.selectedRaid) and id or nil
        clearSelections()
        Utils.triggerEvent("LoggerSelectRaid", Logger.selectedRaid)
    end

    function Logger:SelectBoss(btn)
        local id = btn and btn.GetID and btn:GetID()
        toggleSelection("selectedBoss", id, "LoggerSelectBoss")
    end

    -- Player filter: only one active at a time
    function Logger:SelectBossPlayer(btn)
        local id = btn and btn.GetID and btn:GetID()
        Logger.selectedPlayer = nil
        toggleSelection("selectedBossPlayer", id, "LoggerSelectBossPlayer")
        Utils.triggerEvent("LoggerSelectPlayer", Logger.selectedPlayer)
    end

    function Logger:SelectPlayer(btn)
        local id = btn and btn.GetID and btn:GetID()
        Logger.selectedBossPlayer = nil
        toggleSelection("selectedPlayer", id, "LoggerSelectPlayer")
        Utils.triggerEvent("LoggerSelectBossPlayer", Logger.selectedBossPlayer)
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

        function Logger:SelectItem(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then return end

            if button == "LeftButton" then
                toggleSelection("selectedItem", id, "LoggerSelectItem")
            elseif button == "RightButton" then
                Logger.selectedItem = id
                Utils.triggerEvent("LoggerSelectItem", Logger.selectedItem)
                openItemMenu()
            end
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

                local raid = KRT_Raids[self.raidId]
                if not raid then
                    addon:error(L.ErrLoggerInvalidRaid)
                    return
                end

                local loot = raid.loot and raid.loot[self.itemId]
                if not loot then
                    addon:error(L.ErrLoggerInvalidItem)
                    return
                end

                local bossKill = raid.bossKills and raid.bossKills[loot.bossNum]
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

-- ============================================================================
-- Logger list controller helpers (Logger-only)
-- ============================================================================
local makeLoggerListController
local bindLoggerListController

do
    local CreateFrame = CreateFrame
    local math_max = math.max

    function makeLoggerListController(cfg)
        local self = {
            frameName = nil,
            data = {},
            _rows = {},
            _rowByName = {},
            _asc = false,
            _lastHL = nil,
            _active = false,
            _localized = false,
            _lastWidth = nil,
            _dirty = true,
        }

        local defer = CreateFrame("Frame")
        defer:Hide()

        local function buildRowParts(btnName, row)
            if cfg._rowParts and not row._p then
                local p = {}
                for i = 1, #cfg._rowParts do
                    local part = cfg._rowParts[i]
                    p[part] = _G[btnName .. part]
                end
                row._p = p
            end
        end

        local function acquireRow(btnName, parent)
            local row = self._rowByName[btnName]
            if row then
                row:Show()
                return row
            end

            row = CreateFrame("Button", btnName, parent, cfg.rowTmpl)
            self._rowByName[btnName] = row
            buildRowParts(btnName, row)
            return row
        end

        local function releaseData()
            for i = 1, #self.data do
                twipe(self.data[i])
            end
            twipe(self.data)
        end

        local function refreshData()
            releaseData()
            if cfg.getData then
                cfg.getData(self.data)
            end
        end

        local function ensureLocalized()
            if not self._localized and cfg.localize then
                cfg.localize(self.frameName)
                self._localized = true
            end
        end

        local function setActive(active)
            self._active = active
            if self._active then
                ensureLocalized()
                -- Reset one-shot diagnostics each time the list becomes active (OnShow).
                self._loggedFetch = nil
                self._loggedWidgets = nil
                self._warnW0 = nil
                self._missingScroll = nil
                self:Dirty()
                return
            end
            releaseData()
            for i = 1, #self._rows do
                local row = self._rows[i]
                if row then row:Hide() end
            end
            self._lastHL = nil
        end

        local function applyHighlight()
            if not cfg.highlightId then return end
            local sel = cfg.highlightId()
            if sel == self._lastHL then return end
            self._lastHL = sel
            for i = 1, #self.data do
                local it = self.data[i]
                local row = self._rows[i]
                if row then
                    Utils.toggleHighlight(row, sel ~= nil and it.id == sel)
                end
            end
        end

        local function postUpdate()
            if cfg.postUpdate then
                cfg.postUpdate(self.frameName)
            end
        end

        function self:Touch()
            defer:Show()
        end

        function self:Dirty()
            self._dirty = true
            defer:Show()
        end

        local function runUpdate()
            if not self._active or not self.frameName then return end

            if self._dirty then
                refreshData()
                local okFetch = self:Fetch()
                -- If Fetch() returns false we defer until the frame has a real size.
                if okFetch ~= false then
                    self._dirty = false
                end
            end

            applyHighlight()
            postUpdate()
        end

        defer:SetScript("OnUpdate", function(f)
            f:Hide()
            local ok, err = pcall(runUpdate)
            if not ok then
                -- If the user has script errors disabled, this still surfaces the problem in chat.
                if err ~= self._lastErr then
                    self._lastErr = err
                    addon:error(L.LogLoggerUIError:format(tostring(cfg.keyName or "?"), tostring(err)))
                end
            end
        end)

        function self:OnLoad(frame)
            if not frame then return end
            self.frameName = frame:GetName()

            frame:SetScript("OnShow", function()
                if not self._shownOnce then
                    self._shownOnce = true
                    addon:debug(L.LogLoggerUIShow:format(tostring(cfg.keyName or "?"), tostring(self.frameName)))
                end
                setActive(true)
                if not self._loggedWidgets then
                    self._loggedWidgets = true
                    local n = self.frameName
                    local sf = n and _G[n .. "ScrollFrame"]
                    local sc = n and _G[n .. "ScrollFrameScrollChild"]
                    addon:debug(L.LogLoggerUIWidgets:format(
                        tostring(cfg.keyName or "?"),
                        tostring(sf), tostring(sc),
                        sf and (sf:GetWidth() or 0) or 0,
                        sf and (sf:GetHeight() or 0) or 0,
                        sc and (sc:GetWidth() or 0) or 0,
                        sc and (sc:GetHeight() or 0) or 0
                    ))
                end
            end)

            frame:SetScript("OnHide", function()
                setActive(false)
            end)

            if frame:IsShown() then
                setActive(true)
            end
        end

        function self:Fetch()
            local n = self.frameName
            if not n then return end

            local sf = _G[n .. "ScrollFrame"]
            local sc = _G[n .. "ScrollFrameScrollChild"]
            if not (sf and sc) then
                if not self._missingScroll then
                    self._missingScroll = true
                    addon:warn(L.LogLoggerUIMissingWidgets:format(tostring(cfg.keyName or "?"), tostring(n)))
                end
                return
            end

            local scrollW = sf:GetWidth() or 0
            local widthChanged = (self._lastWidth ~= scrollW)
            self._lastWidth = scrollW

            -- Defer draw until the ScrollFrame has a real size (first OnShow can report 0).
            if scrollW < 10 then
                if not self._warnW0 then
                    self._warnW0 = true
                    addon:debug(L.LogLoggerUIDeferLayout:format(tostring(cfg.keyName or "?"), scrollW))
                end
                defer:Show()
                return false
            end
            if (sc:GetWidth() or 0) < 10 then
                sc:SetWidth(scrollW)
            end

            -- One-time diagnostics per list to help debug "empty/blank" frames.
            if not self._loggedFetch then
                self._loggedFetch = true
                addon:debug(L.LogLoggerUIFetch:format(
                    tostring(cfg.keyName or "?"),
                    #self.data,
                    sf:GetWidth() or 0, sf:GetHeight() or 0,
                    sc:GetWidth() or 0, sc:GetHeight() or 0,
                    (_G[n] and _G[n]:GetWidth() or 0),
                    (_G[n] and _G[n]:GetHeight() or 0)
                ))
            end

            local totalH = 0
            local count = #self.data

            for i = 1, count do
                local it = self.data[i]
                local btnName = cfg.rowName(n, it, i)

                local row = self._rows[i]
                if not row or row:GetName() ~= btnName then
                    row = acquireRow(btnName, sc)
                    self._rows[i] = row
                end

                row:SetID(it.id)
                row:ClearAllPoints()
                -- Stretch the row to the scrollchild width.
                -- (Avoid relying on GetWidth() being valid on the first OnShow frame.)
                row:SetPoint("TOPLEFT", 0, -totalH)
                row:SetPoint("TOPRIGHT", -20, -totalH)

                local rH = cfg.drawRow(row, it)
                local usedH = rH or row:GetHeight() or 20
                totalH = totalH + usedH

                row:Show()
            end

            for i = count + 1, #self._rows do
                local r = self._rows[i]
                if r then r:Hide() end
            end

            sc:SetHeight(math_max(totalH, sf:GetHeight()))
            if sf.UpdateScrollChildRect then
                sf:UpdateScrollChildRect()
            end
            self._lastHL = nil
        end

        function self:Sort(key)
            local cmp = cfg.sorters and cfg.sorters[key]
            if not cmp or #self.data <= 1 then return end
            self._asc = not self._asc
            table.sort(self.data, function(a, b) return cmp(a, b, self._asc) end)
            self:Fetch()
            applyHighlight()
            postUpdate()
        end

        self._makeConfirmPopup = Utils.makeConfirmPopup

        return self
    end

    function bindLoggerListController(module, controller)
        module.OnLoad = function(_, frame) controller:OnLoad(frame) end
        module.Fetch = function() controller:Fetch() end
        module.Sort = function(_, t) controller:Sort(t) end
    end
end

-- ============================================================================
-- Raids List
-- ============================================================================
do
    addon.Logger.Raids = addon.Logger.Raids or {}
    local Raids = addon.Logger.Raids
    local L = addon.L

    local controller = makeLoggerListController {
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
                it.date = r.startTime
                it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "RaidBtn" .. i end,
        rowTmpl = "KRTLoggerRaidButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.ID:SetText(it.id)
                ui.Date:SetText(it.dateFmt)
                ui.Zone:SetText(it.zone)
                ui.Size:SetText(it.size)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedRaid end,

        postUpdate = function(n)
            local sel = addon.Logger.selectedRaid
            local canSetCurrent = sel
                and sel ~= KRT_CurrentRaid
                and not addon.Raid:Expired(sel)
                and addon.Raid:GetRaidSize() == KRT_Raids[sel].size

            Utils.enableDisable(_G[n .. "CurrentBtn"], canSetCurrent)
            Utils.enableDisable(_G[n .. "DeleteBtn"], (sel ~= KRT_CurrentRaid))
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            date = function(a, b, asc) return asc and (a.date < b.date) or (a.date > b.date) end,
            zone = function(a, b, asc) return asc and (a.zone < b.zone) or (a.zone > b.zone) end,
            size = function(a, b, asc) return asc and (a.size < b.size) or (a.size > b.size) end,
        },
    }

    bindLoggerListController(Raids, controller)

    function Raids:SetCurrent(btn)
        local sel = addon.Logger.selectedRaid
        if not (btn and sel and KRT_Raids[sel]) then return end

        if KRT_Raids[sel].size ~= addon.Raid:GetRaidSize() then
            addon:error(L.ErrCannotSetCurrentRaidSize)
            return
        end
        if addon.Raid:Expired(sel) then
            addon:error(L.ErrCannotSetCurrentRaidReset)
            return
        end
        KRT_CurrentRaid = sel
        controller:Touch()
    end

    do
        local function DeleteRaid()
            local sel = addon.Logger.selectedRaid
            if not (sel and KRT_Raids[sel]) then return end
            if KRT_CurrentRaid and KRT_CurrentRaid == sel then
                addon:error(L.ErrCannotDeleteRaid)
                return
            end

            tremove(KRT_Raids, sel)
            if KRT_CurrentRaid and KRT_CurrentRaid > sel then
                KRT_CurrentRaid = KRT_CurrentRaid - 1
            end

            addon.Logger.selectedRaid = nil
            controller:Dirty()
        end

        function Raids:Delete(btn)
            if btn and addon.Logger.selectedRaid ~= nil then
                StaticPopup_Show("KRTLOGGER_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaid)
    end

    Utils.registerCallback("RaidCreate", function(_, num)
        addon.Logger.selectedRaid = tonumber(num)
        controller:Dirty()
    end)

    Utils.registerCallback("LoggerSelectRaid", function() controller:Touch() end)
end

-- ============================================================================
-- Boss List
-- ============================================================================
do
    addon.Logger.Boss = addon.Logger.Boss or {}
    local Boss = addon.Logger.Boss
    local L = addon.L

    local function getBossModeLabel(bossData)
        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        return (mode == "h") and "H" or "N"
    end

    local controller = makeLoggerListController {
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
            _G[n .. "DeleteBtn"]:SetText(L.BtnDelete)
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            if not rID then return end

            local raid = KRT_Raids[rID]
            if not raid or not raid.bossKills then return end

            for i = 1, #raid.bossKills do
                local boss = raid.bossKills[i]
                local it = {}
                it.id = i
                it.name = boss.name
                it.time = boss.time or boss.date
                it.timeFmt = date("%H:%M", it.time or time())
                it.mode = getBossModeLabel(boss)
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "BossBtn" .. i end,
        rowTmpl = "KRTLoggerBossButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.ID:SetText(it.id)
                ui.Name:SetText(it.name)
                ui.Time:SetText(it.timeFmt)
                ui.Mode:SetText(it.mode)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedBoss end,

        postUpdate = function(n)
            local hasRaid = addon.Logger.selectedRaid
            local hasBoss = addon.Logger.selectedBoss
            Utils.enableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            Utils.enableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            Utils.enableDisable(_G[n .. "DeleteBtn"], hasBoss ~= nil)
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
            mode = function(a, b, asc) return asc and (a.mode < b.mode) or (a.mode > b.mode) end,
        },
    }

    bindLoggerListController(Boss, controller)

    function Boss:Add() addon.Logger.BossBox:Toggle() end

    function Boss:Edit() if addon.Logger.selectedBoss then addon.Logger.BossBox:Fill() end end

    do
        local function DeleteBoss()
            local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
            if not (rID and bID and KRT_Raids[rID]) then return end

            local lootRemoved = 0
            local raid = KRT_Raids[rID]
            local loot = raid.loot or {}
            for i = #loot, 1, -1 do
                if loot[i].bossNum == bID then
                    tremove(loot, i)
                    lootRemoved = lootRemoved + 1
                end
            end

            tremove(raid.bossKills, bID)
            addon:info(L.LogLoggerBossLootRemoved, rID, bID, lootRemoved)

            addon.Logger.selectedBoss = nil
            addon.Logger:ResetSelections()
            Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
        end

        function Boss:Delete()
            if addon.Logger.selectedBoss then
                StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBoss)
    end

    function Boss:GetName(bossId, raidId)
        local rID = raidId or addon.Logger.selectedRaid
        if not rID or not bossId or not KRT_Raids[rID] then return "" end
        local boss = KRT_Raids[rID].bossKills[bossId]
        return boss and boss.name or ""
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBoss", function() controller:Touch() end)
end

-- ============================================================================
-- Boss Attendees List
-- ============================================================================
do
    addon.Logger.BossAttendees = addon.Logger.BossAttendees or {}
    local BossAtt = addon.Logger.BossAttendees
    local L = addon.L

    local controller = makeLoggerListController {
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBossAttendees) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            local bID = addon.Logger.selectedBoss
            if not (rID and bID) then return end

            local src = addon.Raid:GetPlayers(rID, bID, {})
            for i = 1, #src do
                local p = src[i]
                local it = {}
                it.id = p.id
                it.name = p.name
                it.class = p.class
                out[i] = it
            end
            twipe(src)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerBossAttendeeButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                local r, g, b = Utils.getClassColor(it.class)
                ui.Name:SetText(it.name)
                ui.Name:SetVertexColor(r, g, b)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedBossPlayer end,

        postUpdate = function(n)
            local bSel = addon.Logger.selectedBoss
            local pSel = addon.Logger.selectedBossPlayer
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            if addBtn then
                Utils.enableDisable(addBtn, bSel and not pSel)
            end
            if removeBtn then
                Utils.enableDisable(removeBtn, bSel and pSel)
            end
        end,

        sorters = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
        },
    }

    bindLoggerListController(BossAtt, controller)

    function BossAtt:Add() addon.Logger.AttendeesBox:Toggle() end

    do
        local function DeleteAttendee()
            local rID = addon.Logger.selectedRaid
            local bID = addon.Logger.selectedBoss
            local pID = addon.Logger.selectedBossPlayer
            if not (rID and bID and pID) then return end

            local raid = KRT_Raids[rID]
            if not (raid and raid.bossKills and raid.bossKills[bID]) then return end

            local name = addon.Raid:GetPlayerName(pID, rID)
            local list = raid.bossKills[bID].players
            local i = addon.tIndexOf(list, name)
            while i do
                tremove(list, i)
                i = addon.tIndexOf(list, name)
            end

            addon.Logger.selectedBossPlayer = nil
            controller:Dirty()
        end

        function BossAtt:Delete()
            if addon.Logger.selectedBossPlayer then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallbacks({ "LoggerSelectRaid", "LoggerSelectBoss" }, function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBossPlayer", function() controller:Touch() end)
end

-- ============================================================================
-- Raid Attendees List
-- ============================================================================
do
    addon.Logger.RaidAttendees = addon.Logger.RaidAttendees or {}
    local RaidAtt = addon.Logger.RaidAttendees
    local L = addon.L

    local controller = makeLoggerListController {
        keyName = "RaidAttendeesList",
        poolTag = "logger-raid-attendees",
        _rowParts = { "Name", "Join", "Leave" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidAttendees) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            _G[n .. "AddBtn"]:Disable()
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            if not rID then return end

            local src = addon.Raid:GetPlayers(rID) or {}
            for i = 1, #src do
                local p = src[i]
                local it = {}
                it.id = p.id
                it.name = p.name
                it.class = p.class
                it.join = p.join
                it.leave = p.leave
                it.joinFmt = date("%H:%M", p.join)
                it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerRaidAttendeeButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.Name:SetText(it.name)
                local r, g, b = Utils.getClassColor(it.class)
                ui.Name:SetVertexColor(r, g, b)
                ui.Join:SetText(it.joinFmt)
                ui.Leave:SetText(it.leaveFmt)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedPlayer end,

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            if deleteBtn then
                Utils.enableDisable(deleteBtn, addon.Logger.selectedPlayer ~= nil)
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

    bindLoggerListController(RaidAtt, controller)

    do
        local function DeleteAttendee()
            local rID, pID = addon.Logger.selectedRaid, addon.Logger.selectedPlayer
            if not (rID and pID) then return end

            local raid = KRT_Raids[rID]
            if not (raid and raid.players and raid.players[pID]) then return end

            local name = raid.players[pID].name
            tremove(raid.players, pID)

            for _, boss in ipairs(raid.bossKills) do
                local i = addon.tIndexOf(boss.players, name)
                while i do
                    tremove(boss.players, i)
                    i = addon.tIndexOf(boss.players, name)
                end
            end

            for i = #raid.loot, 1, -1 do
                if raid.loot[i].looter == name then
                    tremove(raid.loot, i)
                end
            end

            addon.Logger.selectedPlayer = nil
            controller:Dirty()
        end

        function RaidAtt:Delete()
            if addon.Logger.selectedPlayer then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectPlayer", function() controller:Touch() end)
end

-- ============================================================================
-- Loot List (filters by selected boss and player)
-- ============================================================================
do
    addon.Logger.Loot = addon.Logger.Loot or {}
    local Loot = addon.Logger.Loot
    local L = addon.L

    local function isLootFromBoss(entry, bossId)
        return not bossId or bossId <= 0 or entry.bossNum == bossId
    end

    local function isLootByPlayer(entry, playerName)
        return not playerName or entry.looter == playerName
    end

    local function passesFilters(entry, bossId, playerName)
        return isLootFromBoss(entry, bossId) and isLootByPlayer(entry, playerName)
    end

    local controller = makeLoggerListController {
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidLoot) end
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            _G[n .. "ClearBtn"]:SetText(L.BtnClear)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            _G[n .. "HeaderItem"]:SetText(L.StrItem)
            _G[n .. "HeaderSource"]:SetText(L.StrSource)
            _G[n .. "HeaderWinner"]:SetText(L.StrWinner)
            _G[n .. "HeaderType"]:SetText(L.StrType)
            _G[n .. "HeaderRoll"]:SetText(L.StrRoll)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)

            -- disabilitati finché non implementati
            _G[n .. "ExportBtn"]:Disable()
            _G[n .. "ClearBtn"]:Disable()
            _G[n .. "AddBtn"]:Disable()
            _G[n .. "EditBtn"]:Disable()
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            if not rID then return end

            local loot = addon.Raid:GetLoot(rID) or {}

            local bID = addon.Logger.selectedBoss
            local pID = addon.Logger.selectedBossPlayer or addon.Logger.selectedPlayer
            local pName = pID and addon.Raid:GetPlayerName(pID, rID) or nil

            local n = 0
            for i = 1, #loot do
                local v = loot[i]
                if passesFilters(v, bID, pName) then
                    n = n + 1
                    local it = {}
                    it.id = v.id
                    it.itemId = v.itemId
                    it.itemName = v.itemName
                    it.itemRarity = v.itemRarity
                    it.itemTexture = v.itemTexture
                    it.itemLink = v.itemLink
                    it.bossNum = v.bossNum
                    it.looter = v.looter
                    it.rollType = tonumber(v.rollType) or 0
                    it.rollValue = v.rollValue
                    it.time = v.time
                    it.timeFmt = date("%H:%M", v.time)
                    out[n] = it
                end
            end
        end,

        rowName = function(n, _, i) return n .. "ItemBtn" .. i end,
        rowTmpl = "KRTLoggerLootButton",

        drawRow = (function()
            local ROW_H
            return function(row, v)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p

                row._itemLink = v.itemLink
                local nameText = v.itemLink or v.itemName or ("[Item " .. (v.itemId or "?") .. "]")
                if v.itemLink then
                    ui.Name:SetText(nameText)
                else
                    ui.Name:SetText(addon.WrapTextInColorCode(
                        nameText,
                        Utils.normalizeHexColor(itemColors[(v.itemRarity or 1) + 1])
                    ))
                end

                local selectedBoss = addon.Logger.selectedBoss
                if selectedBoss and v.bossNum == selectedBoss then
                    ui.Source:SetText("")
                else
                    ui.Source:SetText(addon.Logger.Boss:GetName(v.bossNum, addon.Logger.selectedRaid))
                end

                local r, g, b = Utils.getClassColor(addon.Raid:GetPlayerClass(v.looter))
                ui.Winner:SetText(v.looter)
                ui.Winner:SetVertexColor(r, g, b)

                local rt = tonumber(v.rollType) or 0
                v.rollType = rt
                ui.Type:SetText(lootTypesColored[rt] or lootTypesColored[4])
                ui.Roll:SetText(v.rollValue or 0)
                ui.Time:SetText(v.timeFmt)

                local icon = v.itemTexture
                if not icon and v.itemId then
                    icon = GetItemIcon(v.itemId)
                end
                if not icon then
                    icon = C.RESERVES_ITEM_FALLBACK_ICON
                end
                ui.ItemIconTexture:SetTexture(icon)

                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedItem end,

        postUpdate = function(n)
            Utils.enableDisable(_G[n .. "DeleteBtn"], addon.Logger.selectedItem ~= nil)
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
            source = function(a, b, asc) return asc and (a.bossNum < b.bossNum) or (a.bossNum > b.bossNum) end,
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

    bindLoggerListController(Loot, controller)

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
            local rID, iID = addon.Logger.selectedRaid, addon.Logger.selectedItem
            if rID and KRT_Raids[rID] and iID then
                tremove(KRT_Raids[rID].loot, iID)
                addon.Logger.selectedItem = nil
                controller:Dirty()
            end
        end

        function Loot:Delete()
            if addon.Logger.selectedItem then
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
            -- If the Logger window is open and browsing an old raid, selectedRaid may differ from KRT_CurrentRaid.
            -- Runtime sources must always write into the CURRENT raid session, while Logger UI edits target selectedRaid.
            local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
            if isLoggerSource then
                raidID = addon.Logger.selectedRaid or KRT_CurrentRaid
            else
                raidID = KRT_CurrentRaid or addon.Logger.selectedRaid
            end
        end
        addon:trace(L.LogLoggerLootLogAttempt:format(tostring(source), tostring(raidID), tostring(itemID),
            tostring(looter), tostring(rollType), tostring(rollValue), tostring(KRT_LastBoss)))
        if not raidID or not KRT_Raids[raidID] then
            addon:error(L.LogLoggerNoRaidSession:format(tostring(raidID), tostring(itemID)))
            return false
        end

        local raid = KRT_Raids[raidID]
        local lootCount = raid.loot and #raid.loot or 0
        local it = raid.loot[itemID]
        if not it then
            addon:error(L.LogLoggerItemNotFound:format(raidID, tostring(itemID), lootCount))
            return false
        end

        if not looter or looter == "" then
            addon:warn(L.LogLoggerLooterEmpty:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        if rollType == nil then
            addon:warn(L.LogLoggerRollTypeNil:format(raidID, tostring(itemID), tostring(looter)))
        end

        addon:debug(L.LogLoggerLootBefore:format(raidID, tostring(itemID), tostring(it.itemLink),
            tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))
        if it.looter and it.looter ~= "" and looter and looter ~= "" and it.looter ~= looter then
            addon:warn(L.LogLoggerLootOverwrite:format(raidID, tostring(itemID), tostring(it.itemLink),
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
        addon:info(L.LogLoggerLootRecorded:format(tostring(source), raidID, tostring(itemID),
            tostring(it.itemLink), tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))

        local ok = true
        if expectedLooter and it.looter ~= expectedLooter then ok = false end
        if expectedRollType and it.rollType ~= expectedRollType then ok = false end
        if expectedRollValue and it.rollValue ~= expectedRollValue then ok = false end
        if not ok then
            addon:error(L.LogLoggerVerifyFailed:format(raidID, tostring(itemID), tostring(it.looter),
                tostring(it.rollType), tostring(it.rollValue)))
            return false
        end

        addon:debug(L.LogLoggerVerified:format(raidID, tostring(itemID)))
        if not KRT_LastBoss then
            addon:info(L.LogLoggerRecordedNoBossContext:format(raidID, tostring(itemID), tostring(it.itemLink)))
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

-- ============================================================================
-- Logger: Add/Edit Boss Popup  (Patch #1 — uniforma a time/mode)
-- ============================================================================
do
    addon.Logger.BossBox = addon.Logger.BossBox or {}
    local Box = addon.Logger.BossBox
    local L = addon.L

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}
    local updateInterval = C.UPDATE_INTERVAL_LOGGER

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", function(_, elapsed) self:UpdateUIFrame(_, elapsed) end)
        frame:SetScript("OnHide", function() self:CancelAddEdit() end)
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

        raidData = KRT_Raids[rID]
        if not raidData then return end

        bossData = raidData.bossKills[bID]
        if not bossData then return end

        _G[frameName .. "Name"]:SetText(bossData.name or "")

        local bossTime = bossData.time or bossData.date or time()
        local d = date("*t", bossTime)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        _G[frameName .. "Time"]:SetText(("%02d:%02d"):format(tempDate.hour, tempDate.min))

        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        _G[frameName .. "Difficulty"]:SetText((mode == "h") and "h" or "n")

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

        if isEdit and bossData then
            bossData.name = name
            bossData.time = time(killDate)
            bossData.mode = mode
        else
            tinsert(KRT_Raids[rID].bossKills, {
                name = name,
                time = time(killDate),
                mode = mode,
                players = {},
            })
        end

        self:Hide()
        addon.Logger:ResetSelections()
        Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
    end

    function Box:CancelAddEdit()
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Difficulty"])
        Utils.resetEditBox(_G[frameName .. "Time"])
        isEdit, raidData, bossData = false, {}, {}
        twipe(tempDate)
    end

    function Box:UpdateUIFrame(frame, elapsed)
        if not localized then
            addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
            localized = true
        end
        Utils.throttledUIUpdate(frame, frameName, updateInterval, elapsed, function()
            Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
        end)
    end
end

-- ============================================================================
-- Logger: Add Attendee Popup
-- ============================================================================
do
    addon.Logger.AttendeesBox = addon.Logger.AttendeesBox or {}
    local Box = addon.Logger.AttendeesBox
    local L = addon.L

    local frameName

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnShow", function()
            Utils.resetEditBox(_G[frameName .. "Name"])
        end)
        frame:SetScript("OnHide", function()
            Utils.resetEditBox(_G[frameName .. "Name"])
        end)
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Save()
        local name = Utils.trimText(_G[frameName .. "Name"]:GetText())
        local normalizedName = Utils.normalizeLower(name)
        if normalizedName == "" then
            addon:error(L.ErrAttendeesInvalidName)
            return
        end

        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        if not (rID and bID and KRT_Raids[rID]) then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return
        end

        local bossKill = KRT_Raids[rID].bossKills[bID]
        for _, n in ipairs(bossKill.players) do
            if Utils.normalizeLower(n) == normalizedName then
                addon:error(L.ErrAttendeesPlayerExists)
                return
            end
        end

        for _, p in ipairs(KRT_Raids[rID].players) do
            if normalizedName == Utils.normalizeLower(p.name) then
                tinsert(bossKill.players, p.name)
                addon:info(L.StrAttendeesAddSuccess)
                self:Toggle()
                Utils.triggerEvent("LoggerSelectBoss", addon.Logger.selectedBoss)
                return
            end
        end

        addon:error(L.ErrAttendeesInvalidName)
    end
end
---============================================================================
-- Slash Commands
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

---============================================================================
-- Main Event Handlers
---============================================================================

local addonEvents = {
    CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM",
    CHAT_MSG_LOOT = "CHAT_MSG_LOOT",
    CHAT_MSG_MONSTER_YELL = "CHAT_MSG_MONSTER_YELL",
    RAID_ROSTER_UPDATE = "RAID_ROSTER_UPDATE",
    PLAYER_ENTERING_WORLD = "PLAYER_ENTERING_WORLD",
    COMBAT_LOG_EVENT_UNFILTERED = "COMBAT_LOG_EVENT_UNFILTERED",
    RAID_INSTANCE_WELCOME = "RAID_INSTANCE_WELCOME",
    ITEM_LOCKED = "ITEM_LOCKED",
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
        ITEM_LOCKED = "ITEM_LOCKED",
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

--
-- ADDON_LOADED: Initializes the addon after loading.
--
function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    addon.BUILD = addon.BUILD or "fixed4-2026-01-06"
    local lvl = addon.GetLogLevel and addon:GetLogLevel()
    addon:info(L.LogCoreLoaded:format(tostring(GetAddOnMetadata(addonName, "Version")),
        tostring(lvl), tostring(true)))
    addon:info(L.LogCoreBuild:format(tostring(addon.BUILD)))
    addon.LoadOptions()
    addon.Reserves:Load()
    for event in pairs(addonEvents) do
        self:RegisterEvent(event)
    end
    addon:debug(L.LogCoreEventsRegistered:format(addon.tLength(addonEvents)))
    self:RAID_ROSTER_UPDATE()
end

--
-- RAID_ROSTER_UPDATE: Updates the raid roster when it changes.
--
function addon:RAID_ROSTER_UPDATE()
    addon.Raid:UpdateRaidRoster()
end

--
-- RAID_INSTANCE_WELCOME: Triggered when entering a raid instance.
--
function addon:RAID_INSTANCE_WELCOME(...)
    local instanceName, instanceType, instanceDiff = GetInstanceInfo()
    _, KRT_NextReset = ...
    addon:trace(L.LogRaidInstanceWelcome:format(tostring(instanceName), tostring(instanceType),
        tostring(instanceDiff), tostring(KRT_NextReset)))
    if instanceType == "raid" and not L.RaidZones[instanceName] then
        addon:warn(L.LogRaidUnmappedZone:format(tostring(instanceName), tostring(instanceDiff)))
    end
    if L.RaidZones[instanceName] ~= nil then
        addon:info(L.LogRaidInstanceRecognized:format(tostring(instanceName), tostring(instanceDiff)))
        addon.After(3, function()
            addon.Raid:Check(instanceName, instanceDiff)
        end)
    end
end

--
-- PLAYER_ENTERING_WORLD: Performs initial checks when the player logs in.
--
function addon:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local module = self.Raid
    addon:trace(L.LogCorePlayerEnteringWorld)
    addon.CancelTimer(module.firstCheckHandle, true)
    module.firstCheckHandle = addon.After(3, function() module:FirstCheck() end)
end

--
-- CHAT_MSG_LOOT: Adds looted items to the raid log.
--
function addon:CHAT_MSG_LOOT(msg)
    addon:trace(L.LogLootChatMsgLootRaw:format(tostring(msg)))
    if KRT_CurrentRaid then
        self.Raid:AddLoot(msg)
    end
end

--
-- CHAT_MSG_SYSTEM: Forwards roll messages to the Rolls module.
--
function addon:CHAT_MSG_SYSTEM(msg)
    addon.Rolls:CHAT_MSG_SYSTEM(msg)
end

--
-- CHAT_MSG_MONSTER_YELL: Logs a boss kill based on specific boss yells.
--
function addon:CHAT_MSG_MONSTER_YELL(...)
    local text, boss = ...
    if L.BossYells[text] and KRT_CurrentRaid then
        addon:trace(L.LogBossYellMatched:format(tostring(text), tostring(L.BossYells[text])))
        self.Raid:AddBoss(L.BossYells[text])
    end
end

--
-- COMBAT_LOG_EVENT_UNFILTERED: Logs a boss kill when a boss unit dies.
--
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
        addon:trace(L.LogBossUnitDiedMatched:format(tonumber(npcId) or -1, tostring(boss)))
        self.Raid:AddBoss(boss)
    end
end
