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
local function TGet(tag)
    if Utils.Table and Utils.Table.get then
        return Utils.Table.get(tag)
    end
    return {}
end

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
local titleString         = C.titleString

---============================================================================
-- Saved Variables
-- These variables are persisted across sessions for the addon.
---============================================================================

KRT_Options               = KRT_Options or {}
KRT_Options.schemaVersion = KRT_Options.schemaVersion or 1
KRT_Options.migrations    = KRT_Options.migrations or {}
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
local Compat              = addon:GetLib("LibCompat-1.0")
addon.Compat              = Compat
addon.BossIDs             = addon:GetLib("LibBossIDs-1.0", true)
addon.Logger              = addon:GetLib("LibLogger-1.0", true)
addon.Deformat            = addon:GetLib("LibDeformat-3.0", true)
addon.CallbackHandler     = addon:GetLib("CallbackHandler-1.0", true)

Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
addon.Logger:Embed(addon)
Utils.bindCompat(addon)
Utils.bindLogger(addon)

-- Alias locali (safe e veloci)
local IsInRaid             = addon.IsInRaid
local IsInGroup            = addon.IsInGroup
local UnitIterator         = addon.UnitIterator
local UnitIsGroupLeader    = addon.UnitIsGroupLeader
local UnitIsGroupAssistant = addon.UnitIsGroupAssistant
local tLength              = addon.tLength
local tCopy                = addon.tCopy
local tIndexOf             = addon.tIndexOf
local tContains            = _G.tContains

-- SavedVariables for log level (fallback INFO)
KRT_Debug = KRT_Debug or {}
do
    local INFO = addon.Logger.logLevels.INFO
    KRT_Debug.level = KRT_Debug.level or INFO
    local lv = KRT_Debug.level
    if KRT_Options and KRT_Options.debug then
        lv = addon.Logger.logLevels.DEBUG
    end
    addon:SetLogLevel(lv)
    addon:SetPerformanceMode(true)
end

---============================================================================
-- Debugger Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Debugger = {}
    local module = addon.Debugger

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local debugFrame, msgFrame

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------
    function module:OnLoad(frame)
        debugFrame = frame
        msgFrame = _G[frame:GetName() .. "ScrollFrame"]
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    end

    function module:OnScrollLoad(frame)
        if not frame then return end
        frame:SetJustifyH("LEFT")
        frame:SetFading(false)
        frame:SetMaxLines(500)
    end

    function module:AddMessage(msg, r, g, b)
        if not msgFrame or not msg then return end
        msgFrame:AddMessage(msg, r, g, b)
    end

    function module:Clear()
        if not msgFrame then return end
        msgFrame:Clear()
    end

    function module:Toggle()
        if debugFrame:IsShown() then
            debugFrame:Hide()
        else
            debugFrame:Show()
        end
    end
end

---============================================================================
-- Core Addon Frames & Locals
---============================================================================

-- Centralised addon state
addon.State      = addon.State or {}
local coreState  = addon.State

coreState.frames = coreState.frames or {}
local Frames     = coreState.frames
Frames.main      = Frames.main or CreateFrame("Frame")

-- Addon UI Frames
local mainFrame  = Frames.main
local UIMaster, UIConfig, UISpammer, UIChanges, UIWarnings, UIHistory, UIHistoryItemBox

-- Player info helper
coreState.player = coreState.player or {}
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
local format, match, find, strlen       = string.format, string.match, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber, ucfirst       = tostring, tonumber, _G.string.ucfirst
local UnitRace, UnitSex, GetRealmName   = UnitRace, UnitSex, GetRealmName

---============================================================================
-- Event System
-- Manages WoW API event registration for the addon.
---============================================================================
do
    local events

    local function OnEvent(_, e, ...)
        if e == "ADDON_LOADED" then
            addon.LoadOptions()
        end
        if events then
            events:Fire(e, ...)
        else
            local func = addon[e]
            if type(func) == "function" then
                func(addon, ...)
            end
        end
    end

    local function InitEventFallback()
        mainFrame:SetScript("OnEvent", OnEvent)
        mainFrame:RegisterEvent("ADDON_LOADED")
        function addon:RegisterEvent(e)
            mainFrame:RegisterEvent(e)
        end

        function addon:UnregisterEvent(e)
            mainFrame:UnregisterEvent(e)
        end

        function addon:UnregisterAllEvents()
            mainFrame:UnregisterAllEvents()
        end
    end

    local CB = addon.CallbackHandler
    if CB then
        local function OnUsed(_, _, e) mainFrame:RegisterEvent(e) end
        local function OnUnused(_, _, e) mainFrame:UnregisterEvent(e) end
        events = CB:New(addon, "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", OnUsed, OnUnused)
        mainFrame:SetScript("OnEvent", OnEvent)
        mainFrame:RegisterEvent("ADDON_LOADED")
        addon:RegisterEvent("ADDON_LOADED", function(...) addon:ADDON_LOADED(...) end)
    end

    if not CB then InitEventFallback() end
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
    -- History Functions
    --------------------------------------------------------------------------

    --
    -- Updates the current raid roster, adding new players and marking those who left.
    --
    function module:UpdateRaidRoster()
        rosterVersion = rosterVersion + 1
        if not KRT_CurrentRaid then return end
        Utils.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        if not IsInGroup() then
            numRaid = 0
            module:End()
            addon.Master:PrepareDropDowns()
            return
        end

        local realm = Utils.getRealmName()
        KRT_Players[realm] = KRT_Players[realm] or {}
        local raid = KRT_Raids[KRT_CurrentRaid]
        raid.playersByName = raid.playersByName or {}
        local playersByName = raid.playersByName
        for unit in UnitIterator(true) do
            local name = UnitName(unit)
            if name then
                local rank, subgroup, level, classL, class = Utils.getRaidRosterData(unit)
                local player = playersByName[name]
                local raceL, race = UnitRace(unit)
                inRaid = player and player.leave == nil
                if not inRaid then
                    local toRaid = {
                        name     = name,
                        rank     = rank,
                        subgroup = subgroup,
                        class    = class or "UNKNOWN",
                        join     = Utils.getCurrentTime(),
                        leave    = nil,
                        count    = 0, -- <--- Inizializza count!
                    }
                    module:AddPlayer(toRaid)
                    player = toRaid
                end

                player.seen = true

                if not KRT_Players[realm][name] then
                    KRT_Players[realm][name] = {
                        name   = name,
                        level  = level,
                        race   = race,
                        raceL  = raceL,
                        class  = class or "UNKNOWN",
                        classL = classL,
                        sex    = UnitSex(unit),
                    }
                end
            end
        end

        numRaid = tLength(playersByName)
        if numRaid == 0 then
            module:End()
            return
        end

        -- Mark players who have left
        for name, v in pairs(playersByName) do
            if not v.seen and v.leave == nil then
                v.leave = Utils.getCurrentTime()
            end
            v.seen = nil
        end
        addon.Master:PrepareDropDowns()
    end

    function module:GetRosterVersion()
        return rosterVersion
    end

    --
    -- Creates a new raid log entry.
    --
    function module:Create(zoneName, raidSize)
        if KRT_CurrentRaid then
            self:End()
        end
        if not IsInRaid() then return end

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

        for unit in UnitIterator(true) do
            local name = UnitName(unit)
            if name then
                local rank, subgroup, level, classL, class = Utils.getRaidRosterData(unit)
                local raceL, race = UnitRace(unit)
                local p           = {
                    name     = name,
                    rank     = rank,
                    subgroup = subgroup,
                    class    = class or "UNKNOWN",
                    join     = Utils.getCurrentTime(),
                    leave    = nil,
                    count    = 0, -- Initialize loot count
                }
                tinsert(raidInfo.players, p)
                raidInfo.playersByName[name] = p
                KRT_Players[realm][name] = {
                    name   = name,
                    level  = level,
                    race   = race,
                    raceL  = raceL,
                    class  = class or "UNKNOWN",
                    classL = classL,
                    sex    = UnitSex(unit),
                }
            end
        end

        tinsert(KRT_Raids, raidInfo)
        KRT_CurrentRaid = #KRT_Raids
        Utils.triggerEvent("RaidCreate", KRT_CurrentRaid)
        Utils.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = Utils.After(3, function() module:UpdateRaidRoster() end)
    end

    --
    -- Ends the current raid log entry, marking end time.
    --
    function module:End()
        if not KRT_CurrentRaid then return end
        Utils.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        local currentTime = Utils.getCurrentTime()
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
        if not KRT_CurrentRaid then
            module:Create(instanceName, (instanceDiff % 2 == 0 and 25 or 10))
        end

        local current = KRT_Raids[KRT_CurrentRaid]
        if current then
            if current.zone == instanceName then
                if current.size == 10 and (instanceDiff % 2 == 0) then
                    addon:info(L.StrNewRaidSessionChange)
                    module:Create(instanceName, 25)
                elseif current.size == 25 and (instanceDiff % 2 ~= 0) then
                    addon:info(L.StrNewRaidSessionChange)
                    module:Create(instanceName, 10)
                end
            end
        elseif (instanceDiff % 2 == 0) then
            addon:info(L.StrNewRaidSessionChange)
            module:Create(instanceName, 25)
        elseif (instanceDiff % 2 ~= 0) then
            addon:info(L.StrNewRaidSessionChange)
            module:Create(instanceName, 10)
        end
    end

    --
    -- Performs an initial raid check on player login.
    --
    function module:FirstCheck()
        if module.firstCheckHandle then
            Utils.CancelTimer(module.firstCheckHandle, true)
            module.firstCheckHandle = nil
        end
        if not IsInGroup() then return end

        if KRT_CurrentRaid and module:CheckPlayer(Utils.getPlayerName(), KRT_CurrentRaid) then
            Utils.CancelTimer(module.updateRosterHandle, true)
            module.updateRosterHandle = Utils.After(2, function() module:UpdateRaidRoster() end)
            return
        end

        local instanceName, instanceType, instanceDiff = GetInstanceInfo()
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
        end
    end

    --
    -- Adds a boss kill to the active raid log.
    --
    function module:AddBoss(bossName, manDiff, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        if not raidNum or not bossName then return end

        local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if manDiff then
            instanceDiff = (KRT_Raids[raidNum].size == 10) and 1 or 2
            if lower(manDiff) == "h" then instanceDiff = instanceDiff + 2 end
        elseif isDyn then
            instanceDiff = instanceDiff + (2 * dynDiff)
        end
        local players = {}
        for unit in UnitIterator(true) do
            if UnitIsConnected(unit) then -- track only online players
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
    end

    --
    -- Adds a loot item to the active raid log.
    --
    function module:AddLoot(msg, rollType, rollValue)
        -- Master Loot
        local player, itemLink, count = addon.Deformat(msg, LOOT_ITEM_MULTIPLE)
        local itemCount = count or 1
        if not player then
            player, itemLink = addon.Deformat(msg, LOOT_ITEM)
            itemCount = 1
        end
        if not player then
            local link
            link, count = addon.Deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
            if link then
                itemLink = link
                itemCount = count or 1
            end
            player = Utils.getPlayerName()
        end
        if not itemLink then
            itemLink = addon.Deformat(msg, LOOT_ITEM_SELF)
            itemCount = 1
        end

        -- Other Loot Rolls
        if not player or not itemLink then
            itemLink = addon.Deformat(msg, LOOT_ROLL_YOU_WON)
            player = Utils.getPlayerName()
            itemCount = 1
        end
        if not itemLink then return end

        itemCount = tonumber(itemCount) or 1
        lootState.itemCount = itemCount

        local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local _, _, _, _, itemId = string.find(itemLink, ITEM_LINK_PATTERN)
        itemId = tonumber(itemId)

        -- We don't proceed if lower than threshold or ignored.
        local lootThreshold = GetLootThreshold()
        if itemRarity and itemRarity < lootThreshold then return end
        if itemId and addon.ignoredItems[itemId] then return end

        if not KRT_LastBoss then
            self:AddBoss("_TrashMob_")
        end

        if not rollType then rollType = lootState.currentRollType end
        if not rollValue then rollValue = addon.Rolls:HighestRoll() end

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
        if not IsInRaid() then return 0 end
        local diff = addon.GetRaidDifficulty()
        if diff then
            return (diff == 1 or diff == 3) and 10 or 25
        end
        local members = addon.GetNumGroupMembers()
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
    function module:GetBosses(raidNum)
        local bosses = {}
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
        return bosses
    end

    --------------------------------------------------------------------------
    -- Player Functions
    --------------------------------------------------------------------------

    --
    -- Returns players from the raid log. Can be filtered by boss kill.
    --
    function module:GetPlayers(raidNum, bossNum)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = raidNum and KRT_Raids[raidNum]
        if not raid then return {} end

        local raidPlayers = raid.players or {}
        for k, v in ipairs(raidPlayers) do
            v.id = k
        end

        if bossNum and raid.bossKills[bossNum] then
            local players = {}
            local bossPlayers = raid.bossKills[bossNum].players
            for i, p in ipairs(raidPlayers) do
                if tContains(bossPlayers, p.name) then
                    tinsert(players, p)
                end
            end
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
            name = ucfirst(name:trim())
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
        raidNum = raidNum or addon.History.selectedRaid or KRT_CurrentRaid
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
            if IsInGroup() then
                for unit in UnitIterator(true) do
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
        if not IsInGroup() or not name then
            return id
        end
        for unit in UnitIterator(true) do
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
    -- 4. “Private” (local) functions
    -------------------------------------------------------
    local function PreparePrint(text, prefix)
        prefix = prefix or chatPrefixShort
        if prefixHex then
            prefix = addon.WrapTextInColorCode(prefix, Utils.normalizeHexColor(prefixHex))
        end
        return format(output, prefix, tostring(text))
    end

    -------------------------------------------------------
    -- 5. Public module functions
    -------------------------------------------------------
    function module:Print(text, prefix)
        local msg = PreparePrint(text, prefix)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end

    function module:Announce(text, channel)
        local ch = channel

        if not ch then
            local isCountdown = false
            do
                local ticPat = L.ChatCountdownTic:gsub("%%d", "%%d+")
                isCountdown = (find(text, ticPat) ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)
            end

            if IsInRaid() then
                if isCountdown and addon.options.countdownSimpleRaidMsg then
                    ch = "RAID"
                else
                    if addon.options.useRaidWarning then
                        local isLead = UnitIsGroupLeader("player") or IsRaidLeader()
                        local isAssist = UnitIsGroupAssistant("player") or IsRaidOfficer()
                        if isLead or isAssist then
                            ch = "RAID_WARNING"
                        else
                            ch = "RAID"
                        end
                    else
                        ch = "RAID"
                    end
                end
            elseif IsInGroup() then
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
    function addon:Print(text, prefix)
        module:Print(text, prefix)
    end

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
            wipe(info)
            info.text = text
            info.notCheckable = 1
            info.func = func
            UIDropDownMenu_AddButton(info, level)
        end

        local function AddMenuTitle(level, text)
            wipe(info)
            info.isTitle = 1
            info.text = text
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
        end

        local function AddMenuSeparator(level)
            wipe(info)
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
                -- Toggle loot history frame:
                AddMenuButton(level, L.StrLootHistory, function() addon.History:Toggle() end)
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
        if show then
            KRT_MINIMAP_GUI:Show()
        else
            KRT_MINIMAP_GUI:Hide()
        end
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
        self.options.minimapButton = not self.options.minimapButton
        SetMinimapShown(self.options.minimapButton)
    end

    -- Hides the minimap button.
    function module:HideMinimapButton()
        return KRT_MINIMAP_GUI:Hide()
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
        rolls        = {},
        rerolled     = {},
        playerCounts = {},
        itemCounts   = {},
        count        = 0,
    }

    -------------------------------------------------------
    -- 3. Private helpers
    -------------------------------------------------------
    local function sortRolls()
        local rolls = state.rolls
        if #rolls == 0 then
            lootState.winner = nil
            addon:Debug("DEBUG", "SortRolls: no entries")
            return
        end

        table.sort(rolls, function(a, b)
            return addon.options.sortAscending and a.roll < b.roll or a.roll > b.roll
        end)
        lootState.winner = rolls[1].name
        addon:Debug("DEBUG", "SortRolls: winner=%s roll=%d", lootState.winner, rolls[1].roll)
    end

    local function onRollButtonClick(self)
        state.selected = self.playerName
        module:FetchRolls()
    end

    local function addRoll(name, roll, itemId)
        roll = tonumber(roll)
        state.count = state.count + 1
        lootState.rollsCount = lootState.rollsCount + 1
        state.rolls[state.count] = { name = name, roll = roll, itemId = itemId }
        addon:Debug("DEBUG", "AddRoll: name=%s roll=%d item=%s", name, roll, tostring(itemId))

        if itemId then
            local tracker = state.itemCounts
            tracker[itemId] = tracker[itemId] or {}
            tracker[itemId][name] = (tracker[itemId][name] or 0) + 1
        end

        Utils.triggerEvent("AddRoll", name, roll)
        sortRolls()

        if not state.selected then
            local targetItem = itemId or module:GetCurrentRollItemID()
            if lootState.currentRollType == rollTypes.RESERVED then
                local top, best = -1, nil
                for _, r in ipairs(state.rolls) do
                    if module:IsReserved(targetItem, r.name) and r.roll > top then
                        top, best = r.roll, r.name
                    end
                end
                state.selected = best
            else
                state.selected = lootState.winner
            end
            addon:Debug("DEBUG", "Auto-selected player=%s", tostring(state.selected))
        end

        module:FetchRolls()
    end

    local function resetRolls(rec)
        state.rolls, state.rerolled, state.itemCounts = {}, {}, {}
        state.playerCounts, state.count, lootState.rollsCount = {}, 0, 0
        state.selected, state.rolled, state.warned = nil, false, false
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
            allowed = addon.Reserves:GetReserveCountForItem(itemId, name)
        end

        state.playerCounts[itemId] = state.playerCounts[itemId] or 0
        if state.playerCounts[itemId] >= allowed then
            addon:info(L.ChatOnlyRollOnce)
            addon:Debug("DEBUG", "Roll blocked for %s (%d/%d)", name, state.playerCounts[itemId], allowed)
            return
        end

        RandomRoll(1, 100)
        state.playerCounts[itemId] = state.playerCounts[itemId] + 1
        addon:Debug("DEBUG", "Player %s rolled for item %d", name, itemId)
    end

    -- Returns the current roll session state.
    function module:RollStatus()
        return lootState.currentRollType, state.record, state.canRoll, state.rolled
    end

    -- Enables or disables the recording of rolls.
    function module:RecordRolls(bool)
        state.canRoll, state.record = bool == true, bool == true
        addon:Debug("DEBUG", "RecordRolls: %s", tostring(bool))
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
            addon:Debug("DEBUG", "Roll blocked: countdown active")
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

        local tracker = state.itemCounts
        tracker[itemId] = tracker[itemId] or {}
        local used = tracker[itemId][player] or 0
        if used >= allowed then
            if not tContains(state.rerolled, player) then
                Utils.whisper(player, L.ChatOnlyRollOnce)
                tinsert(state.rerolled, player)
            end
            addon:Debug("DEBUG", "Roll denied: %s (%d/%d)", player, used, allowed)
            return
        end

        addon:Debug("DEBUG", "Roll accepted: %s (%d/%d)", player, used + 1, allowed)
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
        local tracker = state.itemCounts
        tracker[itemId] = tracker[itemId] or {}
        local used = tracker[itemId][name] or 0
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
        local itemId = tonumber(string.match(itemLink, "item:(%d+)"))
        addon:Debug("DEBUG", "GetCurrentRollItemID: %s", tostring(itemId))
        return itemId
    end

    -- Validates if a player can still roll for an item.
    function module:IsValidRoll(itemId, name)
        local tracker = state.itemCounts
        tracker[itemId] = tracker[itemId] or {}
        local used = tracker[itemId][name] or 0
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
        local tracker = state.itemCounts
        tracker[itemId] = tracker[itemId] or {}
        return tracker[itemId][name] or 0
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
        local starTarget = state.selected

        if not starTarget then
            if isSR then
                local top, best = -1, nil
                for _, entry in ipairs(state.rolls) do
                    if module:IsReserved(itemId, entry.name) and entry.roll > top then
                        top, best = entry.roll, entry.name
                    end
                end
                starTarget = best or lootState.winner
            else
                starTarget = lootState.winner
            end
        end

        local starShown, totalHeight = false, 0
        for i = 1, state.count do
            local entry = state.rolls[i]
            local name, roll = entry.name, entry.roll
            local btnName = frameName .. "PlayerBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")

            btn:SetID(i)
            btn:Show()
            btn.playerName = name

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
                    local r, g, b = addon.GetClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
            end

            if state.selected == name then
                nameStr:SetText("> " .. name .. " <")
                btn.selectedBackground:Show()
            else
                nameStr:SetText(name)
                btn.selectedBackground:Hide()
            end

            if isSR and self:IsReserved(itemId, name) then
                local count = self:GetAllowedReserves(itemId, name)
                local used = self:GetUsedReserveCount(itemId, name)
                rollStr:SetText(count > 1 and format("%d (%d/%d)", roll, used, count) or tostring(roll))
            else
                rollStr:SetText(roll)
            end

            local showStar = not starShown and name == starTarget
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
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        for i = 1, GetNumLootItems() do
            if LootSlotIsItem(i) then
                local itemLink = GetLootSlotLink(i)
                if GetItemFamily(itemLink) ~= 64 then -- no DE mat!
                    self:AddItem(itemLink)
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
    end

    --
    -- Adds an item to the loot table.
    --
    function module:AddItem(itemLink)
        local itemName, _, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType,
        itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemLink)

        if not itemName or not itemRarity then
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:SetHyperlink(itemLink)
            GameTooltip:Hide()
            addon:Debug("DEBUG", "Item info not available yet, deferring.")
            return
        end

        if lootState.fromInventory == false then
            local lootThreshold = GetLootThreshold()
            if itemRarity < lootThreshold then return end
            lootState.lootCount = lootState.lootCount + 1
        else
            lootState.lootCount = 1
            lootState.currentItemIndex = 1
        end
        lootTable[lootState.lootCount]             = {}
        lootTable[lootState.lootCount].itemName    = itemName
        lootTable[lootState.lootCount].itemColor   = itemColors[itemRarity + 1]
        lootTable[lootState.lootCount].itemLink    = itemLink
        lootTable[lootState.lootCount].itemTexture = itemTexture
        Utils.triggerEvent("AddItem", itemLink)
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

            if self.options.showTooltips then
                currentItemBtn.tooltip_item = i.itemLink
                self:SetTooltip(currentItemBtn, nil, "ANCHOR_CURSOR")
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
            _G[frameName .. "ItemCount"]:SetText("")
            _G[frameName .. "ItemCount"]:ClearFocus()
            _G[frameName .. "ItemCount"]:Hide()
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
    local countdownStart, countdownPos = 0, 0
    local ceil = math.ceil

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
    local function UpdateMasterButtonsIfChanged(state)
        local buttons = lastUIState.buttons
        local texts = lastUIState.texts

        local function UpdateEnabled(key, frame, enabled)
            if buttons[key] ~= enabled then
                Utils.enableDisable(frame, enabled)
                buttons[key] = enabled
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
        for p = 1, addon.Raid:GetNumRaid() do
            local candidate = GetMasterLootCandidate(p)
            if candidate and candidate ~= "" then
                candidateCache.indexByName[candidate] = p
            end
        end
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
        if lootState.fromInventory == true then
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            announced = false
            lootState.fromInventory = false
            if lootState.opened == true then addon.Loot:FetchLoot() end
        elseif selectionFrame then
            selectionFrame:SetShown(not selectionFrame:IsVisible())
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

            local itemLink = GetItemLink()
            local itemID = tonumber(string.match(itemLink or "", "item:(%d+)"))
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
            countdownRun = false
        else
            addon.Rolls:RecordRolls(true)
            announced = false
            countdownRun = true
            countdownStart = GetTime()
            countdownPos = addon.options.countdownDuration + 1
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
        if lootState.lootCount <= 0 or lootState.rollsCount <= 0 then
            addon:Debug("DEBUG", "Cannot award, lootCount=%d, rollsCount=%d", lootState.lootCount or 0,
                lootState.rollsCount or 0)
            return
        end
        if not lootState.winner then
            addon:warn(L.ErrNoWinnerSelected)
            return
        end
        countdownRun = false
        local itemLink = GetItemLink()
        _G[frameName .. "ItemCount"]:ClearFocus()
        if lootState.fromInventory == true then
            return TradeItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
        end
        return AssignItem(itemLink, lootState.winner, lootState.currentRollType, addon.Rolls:HighestRoll())
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
        local player = raw:gsub("^%s*>%s*(.-)%s*<%s*$", "%1"):trim()
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
        _G[frameName .. "Title"]:SetText(format(titleString, MASTER_LOOTER))
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

    --
    -- OnUpdate handler for the frame, updates UI elements periodically.
    --
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            local itemCountBox = _G[frameName .. "ItemCount"]
            if itemCountBox and itemCountBox:IsVisible() then
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

            if dropDownDirty then
                dirtyFlags.dropdowns = true
            end

            -- Countdown Logic
            if countdownRun == true then
                local tick = ceil(addon.options.countdownDuration - GetTime() + countdownStart)
                local i = countdownPos - 1
                while i >= tick do
                    if i >= addon.options.countdownDuration then
                        addon:Announce(L.ChatCountdownTic:format(i))
                    elseif i >= 10 then
                        if i % 10 == 0 then
                            addon:Announce(L.ChatCountdownTic:format(i))
                        end
                    elseif (
                            (i > 0 and i < 10 and i % 7 == 0) or
                            (i > 0 and i >= 5 and i % 5 == 0) or
                            (i > 0 and i <= 3)
                        ) then
                        addon:Announce(L.ChatCountdownTic:format(i))
                    end
                    i = i - 1
                end
                countdownPos = tick
                if countdownPos == 0 then
                    countdownRun = false
                    countdownPos = 0
                    addon:Announce(L.ChatCountdownEnd)
                    if addon.options.countdownRollsBlock then
                        addon.Rolls:RecordRolls(false)
                    end
                end
            end

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

            if lastUIState.lootCount ~= lootState.lootCount then
                lastUIState.lootCount = lootState.lootCount
                dirtyFlags.buttons = true
            end

            if lastUIState.fromInventory ~= lootState.fromInventory then
                lastUIState.fromInventory = lootState.fromInventory
                dirtyFlags.buttons = true
            end

            local hasReserves = addon.Reserves:HasData()
            if lastUIState.hasReserves ~= hasReserves then
                lastUIState.hasReserves = hasReserves
                dirtyFlags.buttons = true
            end

            local hasItem = ItemExists()
            if lastUIState.hasItem ~= hasItem then
                lastUIState.hasItem = hasItem
                dirtyFlags.buttons = true
            end

            if lastUIState.countdownRun ~= countdownRun then
                lastUIState.countdownRun = countdownRun
                dirtyFlags.buttons = true
            end

            if dirtyFlags.buttons then
                UpdateMasterButtonsIfChanged({
                    countdownText = countdownRun and L.BtnStop or L.BtnCountdown,
                    awardText = lootState.fromInventory and TRADE or L.BtnAward,
                    selectItemText = lootState.fromInventory and L.BtnRemoveItem or L.BtnSelectItem,
                    spamLootText = lootState.fromInventory and READY_CHECK or L.BtnSpamLoot,
                    canSelectItem = lootState.lootCount > 1
                        or (lootState.fromInventory and lootState.lootCount >= 1),
                    canSpamLoot = lootState.lootCount >= 1,
                    canStartRolls = lootState.lootCount >= 1,
                    canStartSR = lootState.lootCount >= 1 and hasReserves,
                    canCountdown = lootState.lootCount >= 1 and hasItem,
                    canHold = lootState.lootCount >= 1,
                    canBank = lootState.lootCount >= 1,
                    canDisenchant = lootState.lootCount >= 1,
                    canAward = lootState.lootCount >= 1 and lootState.rollsCount >= 1,
                    canOpenReserves = hasReserves,
                    canImportReserves = not hasReserves,
                    canRoll = record and canRoll and rolled == false,
                    canClear = lootState.rollsCount >= 1,
                })
                dirtyFlags.buttons = false
            end

            dirtyFlags.rolls = false
            dirtyFlags.winner = false
        end
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
            dropDownData[i] = twipe(dropDownData[i])
        end
        dropDownGroupData = twipe(dropDownGroupData)
        for unit in UnitIterator() do
            local name = UnitName(unit)
            local _, subgroup = Utils.getRaidRosterData(unit)
            if name then
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
        lootState.itemCount = count or lootState.itemCount or 1
        _G[frameName .. "ItemBtn"]:SetScript("OnClick", function(self)
            if not ItemIsSoulbound(inBag, inSlot) then
                -- Clear count:
                _G[frameName .. "ItemCount"]:SetText("")
                _G[frameName .. "ItemCount"]:ClearFocus()
                _G[frameName .. "ItemCount"]:Hide()

                lootState.fromInventory = true
                addon.Loot:AddItem(itemLink)
                addon.Loot:PrepareItem()
                announced        = false
                -- self.History:SetSource("inventory")
                itemInfo.bagID   = inBag
                itemInfo.slotID  = inSlot
                itemInfo.count   = GetItemCount(itemLink)
                itemInfo.isStack = (lootState.itemCount > 1)
                if itemInfo.count >= 1 then
                    lootState.itemCount = itemInfo.count
                    _G[frameName .. "ItemCount"]:SetText(itemInfo.count)
                    _G[frameName .. "ItemCount"]:Show()
                    _G[frameName .. "ItemCount"]:SetFocus()
                end
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
            UpdateSelectionFrame()
            if lootState.lootCount >= 1 then UIMaster:Show() end
            if not addon.History.container then
                addon.History.source = UnitName("target")
            end
        end
    end

    --
    -- LOOT_CLOSED: Triggered when the loot window closes.
    --
    function module:LOOT_CLOSED()
        if addon.Raid:IsMasterLooter() then
            if lootState.closeTimer then
                Utils.CancelTimer(lootState.closeTimer)
                lootState.closeTimer = nil
            end
            lootState.closeTimer = Utils.After(0.1, function()
                lootState.closeTimer = nil
                lootState.opened = false
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
            UpdateSelectionFrame()
            if lootState.lootCount >= 1 then
                UIMaster:Show()
            else
                UIMaster:Hide()
            end
        end
    end

    --
    -- TRADE_ACCEPT_UPDATE: Triggered during a trade.
    --
    function module:TRADE_ACCEPT_UPDATE(tAccepted, pAccepted)
        if lootState.itemCount == 1 and lootState.trader and lootState.winner and lootState.trader ~= lootState.winner then
            if tAccepted == 1 and pAccepted == 1 then
                addon.History.Loot:Log(lootState.currentRollItem, lootState.winner, lootState.currentRollType,
                    addon.Rolls:HighestRoll())
                lootState.trader = nil
                lootState.winner = nil
                addon.Loot:ClearLoot()
                addon.Rolls:ClearRolls()
                addon.Rolls:RecordRolls(false)
                screenshotWarn = false
            end
        end
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
            BuildCandidateCache(itemLink)
            candidateIndex = candidateCache.indexByName[playerName]
        end
        if candidateIndex then
            GiveMasterLoot(itemIndex, candidateIndex)
            local output, whisper
            if rollType <= 4 and addon.options.announceOnWin then
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
            addon.History.Loot:Log(lootState.currentRollItem, playerName, rollType, rollValue)
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
        lootState.trader = Utils.getPlayerName()

        -- Prepare initial output and whisper:
        local output, whisper
        local keep = true
        if rollType <= 4 and addon.options.announceOnWin then
            output = L.ChatAward:format(playerName, itemLink)
            keep = false
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
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls(false)
            addon.Raid:ClearRaidIcons()
        else
            local unit = addon.Raid:GetUnitID(playerName)
            if unit ~= "none" and CheckInteractDistance(unit, 2) == 1 then
                -- Player is in range for trade
                if itemInfo.isStack and not addon.options.ignoreStacks then
                    addon:warn(L.ErrItemStack:format(itemLink))
                    return false
                end
                ClearCursor()
                PickupContainerItem(itemInfo.bagID, itemInfo.slotID)
                if CursorHasItem() then
                    InitiateTrade(playerName)
                    if addon.options.screenReminder and not screenshotWarn then
                        addon:warn(L.ErrScreenReminder)
                        screenshotWarn = true
                    end
                end
                -- Cannot trade the player?
            elseif unit ~= "none" then
                -- Player is out of range
                addon.Raid:ClearRaidIcons()
                SetRaidTarget(lootState.trader, 1)
                if lootState.winner then SetRaidTarget(lootState.winner, 4) end
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
            if rollType <= rollTypes.FREE and playerName == lootState.trader then
                addon.History.Loot:Log(lootState.currentRollItem, lootState.trader, rollType, rollValue)
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

-- ==================== Loot Counter (Reworked: Style & Logic) ==================== --
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
            countsTicker = Utils.NewTicker(C.LOOT_COUNTER_TICK_INTERVAL, TickCounts)
        end
    end

    local function StopCountsTicker()
        if countsTicker then
            Utils.CancelTimer(countsTicker, true)
            countsTicker = nil
        end
    end

    -- Helper to ensure frames exist
    local function EnsureFrames()
        countsFrame = countsFrame or _G["KRTLootCounterFrame"]
        scrollChild = scrollChild or _G["KRTLootCounterFrameScrollFrameScrollChild"]
        if countsFrame and not countsFrame._krtCounterHook then
            local title = _G["KRTLootCounterFrameTitle"]
            if title then
                title:SetText(format(titleString, L.StrLootCounter))
                title:Show()
            end
            countsFrame:SetScript("OnShow", StartCountsTicker)
            countsFrame:SetScript("OnHide", StopCountsTicker)
            countsFrame._krtCounterHook = true
        end
    end

    -- Return sorted array of player names currently in the raid.
    local function GetCurrentRaidPlayers()
        twipe(raidPlayers)
        if not IsInGroup() then
            return raidPlayers
        end
        for unit in UnitIterator(true) do
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
                countsFrame:Hide()
            else
                RequestCountsUpdate()
                countsFrame:Show()
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
                    countsFrame:Hide()
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

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    -- UI Elements
    local frameName
    local reserveListFrame, scrollFrame, scrollChild
    local reserveItemRows, rowsByItemID = {}, {}

    -- State variables
    local localized = false
    local updateInterval = C.UPDATE_INTERVAL_RESERVES
    local reservesData = {}
    local reservesByItemID = {}
    local reservesDisplayList = {}
    local reservesDirty = false
    local pendingItemInfo = {}
    local collapsedBossGroups = {}
    local itemFallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON
    local grouped = {}

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

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
                    local qty = r.quantity or 1
                    local bySource = groupedBySource[source]
                    if not bySource then
                        bySource = {}
                        groupedBySource[source] = bySource
                        if collapsedBossGroups[source] == nil then
                            collapsedBossGroups[source] = false
                        end
                    end
                    local data = bySource[qty]
                    if not data then
                        data = {
                            itemId = itemId,
                            quantity = qty,
                            itemLink = r.itemLink,
                            itemName = r.itemName,
                            itemIcon = r.itemIcon,
                            source = source,
                            players = {},
                        }
                        bySource[qty] = data
                    end
                    data.players[#data.players + 1] = r.player or "?"
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
                    target.quantity = data.quantity
                    target.itemLink = data.itemLink
                    target.itemName = data.itemName
                    target.itemIcon = data.itemIcon
                    target.source = source
                    target.players = target.players or {}
                    twipe(target.players)
                    for i = 1, #data.players do
                        target.players[i] = data.players[i]
                    end
                    target.playersText = tconcat(target.players, ", ")
                    target.players = nil
                    remaining[#remaining + 1] = target
                else
                    data.playersText = tconcat(data.players, ", ")
                    data.players = nil
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
                        local qty = r.quantity or 1

                        local bySource = grouped[source]
                        if not bySource then
                            bySource = {}
                            grouped[source] = bySource
                            if collapsedBossGroups[source] == nil then
                                collapsedBossGroups[source] = false
                            end
                        end

                        local byItem = bySource[itemId]
                        if not byItem then
                            byItem = {}
                            bySource[itemId] = byItem
                        end

                        local data = byItem[qty]
                        if not data then
                            data = {
                                itemId = itemId,
                                quantity = qty,
                                itemLink = r.itemLink,
                                itemName = r.itemName,
                                itemIcon = r.itemIcon,
                                source = source,
                                players = {},
                            }
                            byItem[qty] = data
                        end

                        data.players[#data.players + 1] = r.player or "?"
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, byQty in pairs(byItem) do
                for _, data in pairs(byQty) do
                    data.playersText = tconcat(data.players, ", ")
                    data.players = nil
                    reservesDisplayList[#reservesDisplayList + 1] = data
                end
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
            icon = icon or itemFallbackIcon
            if type(icon) ~= "string" or icon == "" then icon = itemFallbackIcon end
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
            if info.quantity and info.quantity > 1 then
                row.quantityText:SetText(info.quantity .. "x")
                row.quantityText:Show()
            else
                row.quantityText:Hide()
            end
        end
    end

    local function ReserveHeaderOnClick(self)
        local source = self and self._source
        if not source then return end
        collapsedBossGroups[source] = not collapsedBossGroups[source]
        addon:Debug("DEBUG", "Toggling collapse state for source: %s to %s", source,
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
        addon:Debug("DEBUG", "Saving reserves data. Entries: %d", tLength(reservesData))
        local saved = {}
        tCopy(saved, reservesData)
        KRT_SavedReserves = saved
        local savedByItem = {}
        tCopy(savedByItem, reservesByItemID)
        KRT_SavedReserves.reservesByItemID = savedByItem
    end

    function module:Load()
        addon:Debug("DEBUG", "Loading reserves. Data exists: %s", tostring(KRT_SavedReserves ~= nil))
        twipe(reservesData)
        if KRT_SavedReserves then
            tCopy(reservesData, KRT_SavedReserves, "reservesByItemID")
        end
        RebuildIndex()
    end

    function module:ResetSaved()
        addon:Debug("DEBUG", "Resetting saved reserves data.")
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

    --------------------------------------------------------------------------
    -- UI Window Management
    --------------------------------------------------------------------------

    function module:ShowWindow()
        if not reserveListFrame then
            addon:error("Reserve List frame not available.")
            return
        end
        addon:Debug("DEBUG", "Showing reserve list window.")
        reserveListFrame:Show()
    end

    function module:CloseWindow()
        addon:Debug("DEBUG", "Closing reserve list window.")
        if reserveListFrame then reserveListFrame:Hide() end
    end

    function module:ShowImportBox()
        addon:Debug("DEBUG", "Opening import reserves box.")
        local frame = _G["KRTImportWindow"]
        if not frame then
            addon:error("KRTImportWindow not found.")
            return
        end
        frame:Show()
        if _G["KRTImportEditBox"] then
            _G["KRTImportEditBox"]:SetText("")
        end
        _G[frame:GetName() .. "Title"]:SetText(format(titleString, L.StrImportReservesTitle))
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
            self:ParseCSV(csv)
        end
        self:CloseImportWindow()
    end

    function module:OnLoad(frame)
        addon:Debug("DEBUG", "Reserves frame loaded.")
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
                addon:Debug("DEBUG", "Button '%s' assigned to '%s'", suff, method)
            end
        end

        LocalizeUIFrame()

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:Debug("DEBUG", "GET_ITEM_INFO_RECEIVED for itemId %d", itemId)
            if pendingItemInfo[itemId] then
                local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
                if name then
                    addon:Debug("DEBUG", "Updating reserve data for item: %s", link)
                    self:UpdateReserveItemData(itemId, name, link, tex)
                    pendingItemInfo[itemId] = nil
                else
                    addon:Debug("DEBUG", "Item info still missing for itemId %d", itemId)
                end
            end
        end)
    end

    --------------------------------------------------------------------------
    -- Localization and UI Update
    --------------------------------------------------------------------------

    function LocalizeUIFrame()
        if localized then
            addon:Debug("DEBUG", "UI already localized.")
            return
        end
        if frameName then
            _G[frameName .. "Title"]:SetText(format(titleString, L.StrRaidReserves))
            addon:Debug("DEBUG", "UI localized: %s", L.StrRaidReserves)
        end
        localized = true
    end

    -- Update UI Frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if not frameName then return end
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            local hasData = module:HasData()
            local clearButton = _G[frameName .. "ClearButton"]
            if clearButton then
                Utils.enableDisable(clearButton, hasData)
            end
            local queryButton = _G[frameName .. "QueryButton"]
            if queryButton then
                Utils.enableDisable(queryButton, hasData)
            end
        end
    end

    --------------------------------------------------------------------------
    -- Reserve Data Handling
    --------------------------------------------------------------------------

    function module:GetReserve(playerName)
        if type(playerName) ~= "string" then return nil end
        local player = playerName:lower():trim()
        local reserve = reservesData[player]

        -- Log when the function is called and show the reserve for the player
        if reserve then
            addon:Debug("DEBUG", "Found reserve for player: %s, Reserve data: %s", playerName, tostring(reserve))
        else
            addon:Debug("DEBUG", "No reserve found for player: %s", playerName)
        end

        return reserve
    end

    -- Get all reserves:
    function module:GetAllReserves()
        addon:Debug("DEBUG", "Fetching all reserves. Total players with reserves: %d", tLength(reservesData))
        return reservesData
    end

    -- Parse imported text
    function module:ParseCSV(csv)
        if type(csv) ~= "string" or not csv:match("%S") then
            addon:error("Import failed: empty or invalid data.")
            return
        end

        addon:Debug("DEBUG", "Starting to parse CSV data.")
        twipe(reservesData)
        twipe(reservesByItemID)
        reservesDirty = true

        local function cleanCSVField(field)
            if not field then return nil end
            return field:gsub('^"(.-)"$', '%1'):trim()
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
                local normalized = playerName and playerName:lower():trim()

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
                end
            end
        end

        RebuildIndex()
        addon:Debug("DEBUG", "Finished parsing CSV data. Total players with reserves: %d", tLength(reservesData))
        self:RefreshWindow()
        self:Save()
    end

    --------------------------------------------------------------------------
    -- Item Info Querying
    --------------------------------------------------------------------------

    function module:QueryItemInfo(itemId)
        if not itemId then return end
        addon:Debug("DEBUG", "Querying info for itemId: %d", itemId)
        local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
        if name and link and tex then
            self:UpdateReserveItemData(itemId, name, link, tex)
            addon:Debug("DEBUG", "Successfully queried info for itemId: %d, Item Name: %s", itemId, name)
            return true
        else
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            GameTooltip:SetHyperlink("item:" .. itemId)
            GameTooltip:Hide()
            pendingItemInfo[itemId] = true
            addon:Debug("DEBUG", "Failed to query info for itemId: %d", itemId)
            return false
        end
    end

    -- Query all missing items for reserves
    function module:QueryMissingItems()
        local count = 0
        addon:Debug("DEBUG", "Querying missing items in reserves.")
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for _, r in ipairs(player.reserves) do
                    if not r.itemLink or not r.itemIcon then
                        if not self:QueryItemInfo(r.rawID) then
                            count = count + 1
                        end
                    end
                end
            end
        end
        addon:info(count > 0 and ("Requested info for " .. count .. " missing items.") or
            "All item infos are available.")
        addon:Debug("DEBUG", "Total missing items requested: %d", count)
    end

    -- Update reserve item data
    function module:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        if not itemId then return end
        local icon = itemIcon or itemFallbackIcon
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
                if type(icon) ~= "string" or icon == "" then icon = itemFallbackIcon end
                row.iconTexture:SetTexture(icon)
                row.iconTexture:Show()
            end
            if row.nameText then
                row.nameText:SetText(itemLink or itemName or ("Item ID: " .. itemId))
            end
        end
    end

    -- Get reserve count for a specific item for a player
    function module:GetReserveCountForItem(itemId, playerName)
        local normalized = playerName and playerName:lower()
        local entry = reservesData[normalized]
        if not entry then return 0 end
        addon:Debug("DEBUG", "Checking reserve count for itemId: %d for player: %s", itemId, playerName)
        for _, r in ipairs(entry.reserves or {}) do
            if r.rawID == itemId then
                addon:Debug("DEBUG", "Found reserve for itemId: %d, player: %s, quantity: %d", itemId, playerName,
                    r.quantity)
                return r.quantity or 1
            end
        end
        addon:Debug("DEBUG", "No reserve found for itemId: %d, player: %s", itemId, playerName)
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

        if reservesDirty then
            table.sort(reservesDisplayList, function(a, b)
                if a.source ~= b.source then return a.source < b.source end
                if a.itemId ~= b.itemId then return a.itemId < b.itemId end
                return a.quantity < b.quantity
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
                reserveItemRows[#reserveItemRows + 1] = header
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
        row.iconTexture:SetDrawLayer("ARTWORK")
        row.iconBtn:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        local normal = row.iconBtn:GetNormalTexture()
        if normal then
            normal:SetAllPoints(row.iconBtn)
        end
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
            SetupReserveIcon(row)
            row.nameText = _G[rowName .. "Name"]
            row.sourceText = _G[rowName .. "Source"]
            row.playerText = _G[rowName .. "Players"]
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
            players[#players + 1] = (qty > 1 and ("(" .. qty .. "x)" .. name)) or name
        end
        return players
    end

    function module:FormatReservedPlayersLine(itemId)
        addon:Debug("DEBUG", "Formatting reserved players line for itemId: %d", itemId)
        local list = self:GetPlayersForItem(itemId)
        -- Log the list of players found for the item
        addon:Debug("DEBUG", "Players for itemId %d: %s", itemId, table.concat(list, ", "))
        return #list > 0 and table.concat(list, ", ") or ""
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
    local lastUseRaidWarning

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
        schemaVersion         = 1,
        migrations            = {},
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
        minimapPos             = 325,
        debug                  = false,
        chatThrottle           = 2,
        lfmPeriod              = 45,
        countdownSimpleRaidMsg = false,
        countdownDuration      = 5,
        countdownRollsBlock    = true,
    }

    --
    -- Loads the default options into the settings table.
    --
    local function LoadDefaultOptions()
        local options = {}
        tCopy(options, defaultOptions)
        KRT_Options = options
        addon.options = options
        configDirty = true
        addon:info("Default options have been restored.")
    end

    --
    -- Loads addon options from saved variables, filling in defaults.
    --
    local function LoadOptions()
        local options = {}
        tCopy(options, defaultOptions)
        if KRT_Options then
            tCopy(options, KRT_Options)
        end
        KRT_Options = options
        addon.options = options

        -- Ensure dependent options are consistent
        if not addon.options.useRaidWarning then
            addon.options.countdownSimpleRaidMsg = false
        end

        Utils.applyDebugSetting(addon.options.debug)
        configDirty = true

        if KRT_MINIMAP_GUI then
            addon.Minimap:SetPos(addon.options.minimapPos or 325)
            if addon.options.minimapButton then
                KRT_MINIMAP_GUI:Show()
            else
                KRT_MINIMAP_GUI:Hide()
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

        if name == "useRaidWarning" and not value then
            KRT_Options.countdownSimpleRaidMsg = false
        end

        configDirty = true
    end

    --
    -- Localizes UI elements.
    --
    function LocalizeUIFrame()
        if localized then
            return
        end
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
        _G[frameName .. "Title"]:SetText(format(titleString, SETTINGS))
        _G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
        _G[frameName .. "DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)
        localized = true
    end

    --
    -- OnUpdate handler for the configuration frame.
    --
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if configDirty and Utils.throttle(self, frameName, updateInterval, elapsed) then
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
            _G[frameName .. "countdownDuration"]:SetValue(addon.options.countdownDuration)
            _G[frameName .. "countdownDurationText"]:SetText(addon.options.countdownDuration)

            -- Handle dependent options
            local useRaidWarningBtn = _G[frameName .. "useRaidWarning"]
            local countdownSimpleRaidMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
            local countdownSimpleRaidMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]

            if useRaidWarningBtn and countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
                if lastUseRaidWarning ~= addon.options.useRaidWarning then
                    if not useRaidWarningBtn:GetChecked() then
                        countdownSimpleRaidMsgBtn:SetChecked(addon.options.countdownSimpleRaidMsg)
                        countdownSimpleRaidMsgBtn:Disable()
                        countdownSimpleRaidMsgStr:SetTextColor(0.5, 0.5, 0.5)
                    else
                        countdownSimpleRaidMsgBtn:Enable()
                        countdownSimpleRaidMsgStr:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g,
                            HIGHLIGHT_FONT_COLOR.b)
                        countdownSimpleRaidMsgBtn:SetChecked(addon.options.countdownSimpleRaidMsg)
                    end
                    lastUseRaidWarning = addon.options.useRaidWarning
                end
            end
            configDirty = false
        end
    end
end

-- ==================== Warnings Frame ==================== --

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
        _G[frameName .. "Name"]:SetText("")
        _G[frameName .. "Name"]:ClearFocus()
        _G[frameName .. "Content"]:SetText("")
        _G[frameName .. "Content"]:ClearFocus()
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
            _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelp)
        end
        _G[frameName .. "Title"]:SetText(format(titleString, RAID_WARNING))
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
            _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelp)
            _G[frameName .. "OutputContent"]:SetText(L.StrWarningsHelp)
            _G[frameName .. "OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
        end
        lastSelectedID = selectedID
    end

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
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
        end
    end

    -- Saving a Warning:
    function SaveWarning(wContent, wName, wID)
        wID = wID and tonumber(wID) or 0
        wName = tostring(wName):trim()
        wContent = tostring(wContent):trim()
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
        _G[frameName .. "Name"]:SetText("")
        _G[frameName .. "Name"]:ClearFocus()
        _G[frameName .. "Content"]:SetText("")
        _G[frameName .. "Content"]:ClearFocus()
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

-- ==================== MS Changes Frame ==================== --

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
        local count = tLength(changesTable)
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
        _G[frameName .. "Title"]:SetText(format(titleString, L.StrChanges))
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Spec"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Spec"]:SetScript("OnEscapePressed", CancelChanges)
        localized = true
    end

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            if changesDirty or not fetched then
                InitChangesTable()
                FetchChanges()
                changesDirty = false
            end
            local count = tLength(changesTable)
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
        end
    end

    -- Initialize changes table:
    function InitChangesTable()
        addon:Debug("DEBUG", "Initializing changes table.")
        changesTable = KRT_CurrentRaid and KRT_Raids[KRT_CurrentRaid].changes or {}
    end

    -- Fetch All module:
    function FetchChanges()
        addon:Debug("DEBUG", "Fetching all changes.")
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
            local r, g, b = addon.GetClassColor(class)
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
        name = ucfirst(name:trim())
        spec = ucfirst(spec:trim())
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
        _G[frameName .. "Name"]:SetText("")
        _G[frameName .. "Name"]:ClearFocus()
        _G[frameName .. "Spec"]:SetText("")
        _G[frameName .. "Spec"]:ClearFocus()
    end
end

-- ==================== LFM Spam Frame ==================== --

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

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    local loaded = false

    local duration = (KRT_Options and KRT_Options.lfmPeriod) or 60
    local output = "LFM"
    local finalOutput = ""
    local length = 0
    local channels = {}

    local ticking = false
    local paused = false
    local tickStart, tickPos = 0, 0

    local ceil = math.ceil
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
        duration = nil,
    }

    local StartTicker
    local StopTicker
    local RenderPreview
    local UpdateSpamTimer
    local UpdateControls
    local BuildOutput

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UISpammer = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnShow", function()
            StartTicker()
        end)
        frame:SetScript("OnHide", function()
            if not ticking then
                StopTicker()
            end
        end)
        if UISpammer:IsShown() or ticking then
            StartTicker()
        end
    end

    -- Toggle frame visibility:
    function module:Toggle()
        Utils.toggle(UISpammer)
    end

    -- Hide frame:
    function module:Hide()
        Utils.hideFrame(UISpammer)
    end

    -- Save edit box:-
    function module:Save(box)
        if not box then return end
        local boxName = box:GetName()
        local target = gsub(boxName, frameName, "")
        if find(target, "Chat") then
            KRT_Spammer.Channels = KRT_Spammer.Channels or {}
            local channel = gsub(target, "Chat", "")
            local id = tonumber(channel) or select(1, GetChannelName(channel))
            channel = (id and id > 0) and id or channel
            local checked = (box:GetChecked() == 1)
            local existed = tContains(KRT_Spammer.Channels, channel)
            if checked and not existed then
                tinsert(KRT_Spammer.Channels, channel)
            elseif not checked and existed then
                local i = tIndexOf(KRT_Spammer.Channels, channel)
                while i do
                    tremove(KRT_Spammer.Channels, i)
                    i = tIndexOf(KRT_Spammer.Channels, channel)
                end
            end
        else
            local value = box:GetText():trim()
            value = (value == "") and nil or value
            KRT_Spammer[target] = value
            box:ClearFocus()
            if ticking and paused then paused = false end
        end
        loaded = false
    end

    -- Start spamming:
    function module:Start()
        if strlen(finalOutput) > 3 and strlen(finalOutput) <= 255 then
            if paused then
                paused = false
            elseif ticking then
                ticking = false
            else
                tickStart = GetTime()
                duration = tonumber(duration) or addon.options.lfmPeriod
                tickPos = (duration >= 1 and duration or addon.options.lfmPeriod) + 1
                ticking = true
                StartTicker()
                -- module:Spam()
            end
        end
    end

    -- Stop spamming:
    function module:Stop()
        _G[frameName .. "Tick"]:SetText(duration or 0)
        ticking = false
        paused = false
        if UISpammer and not UISpammer:IsShown() then
            StopTicker()
        end
    end

    -- Pausing spammer
    function module:Pause()
        paused = true
    end

    -- Send spam message:
    function module:Spam()
        if strlen(finalOutput) > 255 then
            addon:error(L.StrSpammerErrLength)
            ticking = false
            return
        end
        if #channels <= 0 then
            Utils.chat(tostring(finalOutput), "YELL", nil, nil, true)
            return
        end
        for i, c in ipairs(channels) do
            if type(c) == "number" then
                Utils.chat(tostring(finalOutput), "CHANNEL", nil, c, true)
            else
                Utils.chat(tostring(finalOutput), upper(c), nil, nil, true)
            end
        end
    end

    -- Tab move between edit boxes:
    function module:Tab(a, b)
        local target
        if IsShiftKeyDown() and _G[frameName .. b] ~= nil then
            target = _G[frameName .. b]
        elseif _G[frameName .. a] ~= nil then
            target = _G[frameName .. a]
        end
        if target then target:SetFocus() end
    end

    -- Clears Data
    function module:Clear()
        for k, _ in pairs(KRT_Spammer) do
            if k ~= "Channels" and k ~= "Duration" then
                KRT_Spammer[k] = nil
            end
        end
        output, finalOutput = "LFM", ""
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
        module:Stop()
        _G[frameName .. "Name"]:SetText("")
        _G[frameName .. "Tank"]:SetText("")
        _G[frameName .. "TankClass"]:SetText("")
        _G[frameName .. "Healer"]:SetText("")
        _G[frameName .. "HealerClass"]:SetText("")
        _G[frameName .. "Melee"]:SetText("")
        _G[frameName .. "MeleeClass"]:SetText("")
        _G[frameName .. "Ranged"]:SetText("")
        _G[frameName .. "RangedClass"]:SetText("")
        _G[frameName .. "Message"]:SetText("")
    end

    -- Localizing ui frame:
    function LocalizeUIFrame()
        if localized then return end
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            _G[frameName .. "CompStr"]:SetText(L.StrSpammerCompStr)
            _G[frameName .. "NeedStr"]:SetText(L.StrSpammerNeedStr)
            _G[frameName .. "MessageStr"]:SetText(L.StrSpammerMessageStr)
            _G[frameName .. "PreviewStr"]:SetText(L.StrSpammerPreviewStr)
        end
        _G[frameName .. "Title"]:SetText(format(titleString, L.StrSpammer))
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

        localized = true
    end

    function StartTicker()
        if updateTicker then return end
        updateTicker = Utils.NewTicker(updateInterval, function()
            if UISpammer then
                UpdateUIFrame(UISpammer, updateInterval)
            end
        end)
    end

    function StopTicker()
        if not updateTicker then return end
        Utils.CancelTimer(updateTicker, true)
        updateTicker = nil
    end

    function BuildOutput()
        local temp = output
        if lastState.name ~= "" then temp = temp .. " " .. lastState.name end
        if lastState.tank > 0 or lastState.healer > 0 or lastState.melee > 0 or lastState.ranged > 0 then
            temp = temp .. " - Need"
            if lastState.tank > 0 then
                temp = temp .. ", " .. lastState.tank .. " Tank"
                if lastState.tankClass ~= "" then temp = temp .. " (" .. lastState.tankClass .. ")" end
            end
            if lastState.healer > 0 then
                temp = temp .. ", " .. lastState.healer .. " Healer"
                if lastState.healerClass ~= "" then temp = temp .. " (" .. lastState.healerClass .. ")" end
            end
            if lastState.melee > 0 then
                temp = temp .. ", " .. lastState.melee .. " Melee"
                if lastState.meleeClass ~= "" then temp = temp .. " (" .. lastState.meleeClass .. ")" end
            end
            if lastState.ranged > 0 then
                temp = temp .. ", " .. lastState.ranged .. " Ranged"
                if lastState.rangedClass ~= "" then temp = temp .. " (" .. lastState.rangedClass .. ")" end
            end
        end
        if lastState.message ~= "" then
            temp = temp .. " - " .. Utils.findAchievement(lastState.message)
        end
        if temp ~= "LFM" then
            local total = lastState.tank + lastState.healer + lastState.melee + lastState.ranged
            local max = lastState.name:find("25") and 25 or 10
            temp = temp .. " (" .. max - (total or 0) .. "/" .. max .. ")"
        end
        return temp
    end

    function UpdateControls()
        Utils.setText(
            _G[frameName .. "StartBtn"],
            (paused and L.BtnResume or L.BtnStop),
            START,
            ticking == true
        )
        Utils.enableDisable(
            _G[frameName .. "StartBtn"],
            (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255)
        )
    end

    function RenderPreview()
        if not UISpammer or not UISpammer:IsShown() then return end

        channels = KRT_Spammer.Channels or {}

        local changed = false
        local nameValue = _G[frameName .. "Name"]:GetText():trim()
        if lastState.name ~= nameValue then
            lastState.name = nameValue
            changed = true
        end

        local tankValue = tonumber(_G[frameName .. "Tank"]:GetText()) or 0
        if lastState.tank ~= tankValue then
            lastState.tank = tankValue
            changed = true
        end

        local tankClassValue = _G[frameName .. "TankClass"]:GetText():trim()
        if lastState.tankClass ~= tankClassValue then
            lastState.tankClass = tankClassValue
            changed = true
        end

        local healerValue = tonumber(_G[frameName .. "Healer"]:GetText()) or 0
        if lastState.healer ~= healerValue then
            lastState.healer = healerValue
            changed = true
        end

        local healerClassValue = _G[frameName .. "HealerClass"]:GetText():trim()
        if lastState.healerClass ~= healerClassValue then
            lastState.healerClass = healerClassValue
            changed = true
        end

        local meleeValue = tonumber(_G[frameName .. "Melee"]:GetText()) or 0
        if lastState.melee ~= meleeValue then
            lastState.melee = meleeValue
            changed = true
        end

        local meleeClassValue = _G[frameName .. "MeleeClass"]:GetText():trim()
        if lastState.meleeClass ~= meleeClassValue then
            lastState.meleeClass = meleeClassValue
            changed = true
        end

        local rangedValue = tonumber(_G[frameName .. "Ranged"]:GetText()) or 0
        if lastState.ranged ~= rangedValue then
            lastState.ranged = rangedValue
            changed = true
        end

        local rangedClassValue = _G[frameName .. "RangedClass"]:GetText():trim()
        if lastState.rangedClass ~= rangedClassValue then
            lastState.rangedClass = rangedClassValue
            changed = true
        end

        local messageValue = _G[frameName .. "Message"]:GetText():trim()
        if lastState.message ~= messageValue then
            lastState.message = messageValue
            changed = true
        end

        local durationValue = _G[frameName .. "Duration"]:GetText()
        if durationValue == "" then
            durationValue = addon.options.lfmPeriod
            _G[frameName .. "Duration"]:SetText(durationValue)
        end
        if lastState.duration ~= durationValue then
            lastState.duration = durationValue
            changed = true
        end

        if changed then
            local temp = BuildOutput()
            finalOutput = temp

            if temp ~= "LFM" then
                _G[frameName .. "Output"]:SetText(temp)
                length = strlen(temp)
                _G[frameName .. "Length"]:SetText(length .. "/255")

                if length <= 0 then
                    _G[frameName .. "Length"]:SetTextColor(0.5, 0.5, 0.5)
                elseif length <= 255 then
                    _G[frameName .. "Length"]:SetTextColor(0.0, 1.0, 0.0)
                    _G[frameName .. "Message"]:SetMaxLetters(255)
                else
                    _G[frameName .. "Message"]:SetMaxLetters(strlen(messageValue) - 1)
                    _G[frameName .. "Length"]:SetTextColor(1.0, 0.0, 0.0)
                end
            else
                _G[frameName .. "Output"]:SetText(temp)
            end
        end

        duration = lastState.duration
        UpdateControls()
    end

    function UpdateSpamTimer()
        if not ticking or paused then return end
        local count = ceil(duration - GetTime() + tickStart)
        local i = tickPos - 1
        while i >= count do
            _G[frameName .. "Tick"]:SetText(i)
            i = i - 1
        end
        tickPos = count
        if tickPos < 0 then tickPos = 0 end
        if tickPos == 0 then
            _G[frameName .. "Tick"]:SetText("")
            module:Spam()
            ticking = false
            module:Start()
        end
    end

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if not addon.options then
            if addon.LoadOptions then
                addon.LoadOptions()
            end
            if not addon.options then
                if self then
                    self:SetScript("OnUpdate", nil)
                end
                return
            end
        end
        if not (UISpammer and (UISpammer:IsShown() or ticking)) then
            StopTicker()
            return
        end
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            if not loaded then
                KRT_Spammer.Duration = KRT_Spammer.Duration or addon.options.lfmPeriod
                for k, v in pairs(KRT_Spammer) do
                    if k == "Channels" then
                        for i, c in ipairs(v) do
                            local id = tonumber(c) or select(1, GetChannelName(c))
                            id = (id and id > 0) and id or c
                            v[i] = id
                            _G[frameName .. "Chat" .. id]:SetChecked()
                        end
                    elseif _G[frameName .. k] then
                        _G[frameName .. k]:SetText(v)
                    end
                end
                loaded = true
            end
            RenderPreview()
            UpdateSpamTimer()
        end
    end

end

-- ============================================================================
-- History (Main) - stato + selettori
-- ============================================================================
do
    addon.History                                                         = addon.History or {}
    local module                                                          = addon.History
    local L                                                               = addon.L

    local frameName

    module.selectedRaid, module.selectedBoss                              = nil, nil
    module.selectedPlayer, module.selectedBossPlayer, module.selectedItem = nil, nil, nil

    function module:ResetSelections()
        module.selectedBoss       = nil
        module.selectedPlayer     = nil
        module.selectedBossPlayer = nil
        module.selectedItem       = nil
    end

    local function makeSelector(field, ev)
        return function(_, btn)
            local id = btn and btn.GetID and btn:GetID()
            module[field] = (id and id ~= module[field]) and id or nil
            Utils.triggerEvent(ev, module[field])
        end
    end

    function module:OnLoad(frame)
        UIHistory, frameName = frame, frame:GetName()
        frame:RegisterForDrag("LeftButton")
        _G[frameName .. "Title"]:SetText(format(titleString, L.StrLootHistory))

        frame:SetScript("OnShow", function()
            if not module.selectedRaid then
                module.selectedRaid = KRT_CurrentRaid
            end
            module:ResetSelections()
            Utils.triggerEvent("HistorySelectRaid", module.selectedRaid)
        end)

        frame:SetScript("OnHide", function()
            module.selectedRaid = KRT_CurrentRaid
            module:ResetSelections()
        end)
    end

    function module:Toggle() Utils.toggle(UIHistory) end

    function module:Hide()
        module.selectedRaid = KRT_CurrentRaid
        module:ResetSelections()
        Utils.showHide(UIHistory, false)
    end

    -- Selectors
    module.SelectRaid = makeSelector("selectedRaid", "HistorySelectRaid")
    module.SelectBoss = makeSelector("selectedBoss", "HistorySelectBoss")

    -- Player filter: only one active at a time
    function module:SelectBossPlayer(btn)
        local id = btn and btn.GetID and btn:GetID()
        module.selectedBossPlayer = (id and id ~= module.selectedBossPlayer) and id or nil
        module.selectedPlayer = nil
        Utils.triggerEvent("HistorySelectBossPlayer", module.selectedBossPlayer)
        Utils.triggerEvent("HistorySelectPlayer", module.selectedPlayer)
    end

    function module:SelectPlayer(btn)
        local id = btn and btn.GetID and btn:GetID()
        module.selectedPlayer = (id and id ~= module.selectedPlayer) and id or nil
        module.selectedBossPlayer = nil
        Utils.triggerEvent("HistorySelectPlayer", module.selectedPlayer)
        Utils.triggerEvent("HistorySelectBossPlayer", module.selectedBossPlayer)
    end

    -- Item: left select, right menu
    do
        local function openItemMenu()
            local f = _G.KRTHistoryItemMenuFrame or
                CreateFrame("Frame", "KRTHistoryItemMenuFrame", UIParent, "UIDropDownMenuTemplate")

            EasyMenu({
                { text = L.StrEditItemLooter,    func = function() StaticPopup_Show("KRTHISTORY_ITEM_EDIT_WINNER") end },
                { text = L.StrEditItemRollType,  func = function() StaticPopup_Show("KRTHISTORY_ITEM_EDIT_ROLL") end },
                { text = L.StrEditItemRollValue, func = function() StaticPopup_Show("KRTHISTORY_ITEM_EDIT_VALUE") end },
            }, f, "cursor", 0, 0, "MENU")
        end

        function module:SelectItem(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then return end

            if button == "LeftButton" then
                module.selectedItem = (id ~= module.selectedItem) and id or nil
                Utils.triggerEvent("HistorySelectItem", module.selectedItem)
            elseif button == "RightButton" then
                module.selectedItem = id
                Utils.triggerEvent("HistorySelectItem", module.selectedItem)
                openItemMenu()
            end
        end

        Utils.makeEditBoxPopup("KRTHISTORY_ITEM_EDIT_WINNER", L.StrEditItemLooterHelp,
            function(self, text)
                local name = (text or ""):trim():lower()
                local raid = KRT_Raids[self.raidId]
                if not (raid and raid.players) then return end

                for _, p in ipairs(raid.players) do
                    if name == p.name:lower() then
                        addon.History.Loot:Log(self.itemId, p.name)
                        return
                    end
                end
            end,
            function(self)
                self.raidId = addon.History.selectedRaid
                self.itemId = addon.History.selectedItem
            end
        )

        Utils.makeEditBoxPopup("KRTHISTORY_ITEM_EDIT_ROLL", L.StrEditItemRollTypeHelp,
            function(self, text)
                addon.History.Loot:Log(self.itemId, nil, tonumber(text))
            end,
            function(self) self.itemId = addon.History.selectedItem end
        )

        Utils.makeEditBoxPopup("KRTHISTORY_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp,
            function(self, text)
                addon.History.Loot:Log(self.itemId, nil, nil, tonumber(text))
            end,
            function(self) self.itemId = addon.History.selectedItem end
        )
    end

    Utils.registerCallback("HistorySelectRaid", function()
        module:ResetSelections()
    end)
end

-- ============================================================================
-- Raids List (allineata agli XML)
-- ============================================================================
do
    addon.History.Raids = addon.History.Raids or {}
    local Raids         = addon.History.Raids
    local L             = addon.L

    local controller    = Utils.makeListController {
        keyName     = "RaidsList",
        poolTag     = "history-raids",
        _rowParts   = { "ID", "Date", "Zone", "Size" },

        localize    = function(n)
            _G[n .. "Title"]:SetText(L.StrRaidsList)
            _G[n .. "HeaderDate"]:SetText(L.StrDate)
            _G[n .. "HeaderSize"]:SetText(L.StrSize)
            _G[n .. "CurrentBtn"]:SetText(L.StrSetCurrent)
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            addon:SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)
            _G[n .. "ExportBtn"]:Disable() -- non implementato
        end,

        getData     = function(out)
            for i = 1, #KRT_Raids do
                local r    = KRT_Raids[i]
                local it   = TGet("history-raids")
                it.id      = i
                it.zone    = r.zone
                it.size    = r.size
                it.date    = r.startTime
                it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                out[i]     = it
            end
        end,

        rowName     = function(n, _, i) return n .. "RaidBtn" .. i end,
        rowTmpl     = "KRTHistoryRaidButton",

        drawRow     = (function()
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

        highlightId = function() return addon.History.selectedRaid end,

        postUpdate  = function(n)
            local sel = addon.History.selectedRaid
            local canSetCurrent = sel
                and sel ~= KRT_CurrentRaid
                and not addon.Raid:Expired(sel)
                and addon.Raid:GetRaidSize() == KRT_Raids[sel].size

            Utils.enableDisable(_G[n .. "CurrentBtn"], canSetCurrent)
            Utils.enableDisable(_G[n .. "DeleteBtn"], (sel ~= KRT_CurrentRaid))
        end,

        sorters     = {
            id   = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            date = function(a, b, asc) return asc and (a.date < b.date) or (a.date > b.date) end,
            zone = function(a, b, asc) return asc and (a.zone < b.zone) or (a.zone > b.zone) end,
            size = function(a, b, asc) return asc and (a.size < b.size) or (a.size > b.size) end,
        },
    }

    Utils.bindListController(Raids, controller)

    function Raids:SetCurrent(btn)
        local sel = addon.History.selectedRaid
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
            local sel = addon.History.selectedRaid
            if not (sel and KRT_Raids[sel]) then return end
            if KRT_CurrentRaid and KRT_CurrentRaid == sel then
                addon:error(L.ErrCannotDeleteRaid)
                return
            end

            tremove(KRT_Raids, sel)
            if KRT_CurrentRaid and KRT_CurrentRaid > sel then
                KRT_CurrentRaid = KRT_CurrentRaid - 1
            end

            addon.History.selectedRaid = nil
            controller:Dirty()
        end

        function Raids:Delete(btn)
            if btn and addon.History.selectedRaid ~= nil then
                StaticPopup_Show("KRTHISTORY_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTHISTORY_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaid)
    end

    Utils.registerCallback("RaidCreate", function(_, num)
        addon.History.selectedRaid = tonumber(num)
        controller:Dirty()
    end)

    Utils.registerCallback("HistorySelectRaid", function() controller:Touch() end)
end

-- ============================================================================
-- Boss List
-- ============================================================================
do
    addon.History.Boss = addon.History.Boss or {}
    local Boss         = addon.History.Boss
    local L            = addon.L

    local controller   = Utils.makeListController {
        keyName     = "BossList",
        poolTag     = "history-bosses",
        _rowParts   = { "ID", "Name", "Time", "Mode" },

        localize    = function(n)
            _G[n .. "Title"]:SetText(L.StrBosses)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
        end,

        getData     = function(out)
            local rID = addon.History.selectedRaid
            if not rID then return end

            local src = addon.Raid:GetBosses(rID) or {}
            for i = 1, #src do
                local b    = src[i]
                local it   = TGet("history-bosses")
                it.id      = b.id
                it.name    = b.name
                it.time    = b.time
                it.mode    = b.mode
                it.timeFmt = date("%H:%M", b.time)
                out[i]     = it
            end
        end,

        rowName     = function(n, _, i) return n .. "BossBtn" .. i end,
        rowTmpl     = "KRTHistoryBossButton",

        drawRow     = (function()
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

        highlightId = function() return addon.History.selectedBoss end,

        postUpdate  = function(n)
            local hasRaid = addon.History.selectedRaid
            local hasBoss = addon.History.selectedBoss
            Utils.enableDisable(_G[n .. "AddBtn"], hasRaid)
            Utils.enableDisable(_G[n .. "EditBtn"], hasBoss)
            Utils.enableDisable(_G[n .. "DeleteBtn"], hasBoss)
        end,

        sorters     = {
            id   = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
            mode = function(a, b, asc) return asc and (a.mode < b.mode) or (a.mode > b.mode) end,
        },
    }

    Utils.bindListController(Boss, controller)

    function Boss:Add() addon.History.BossBox:Toggle() end

    function Boss:Edit() if addon.History.selectedBoss then addon.History.BossBox:Fill() end end

    do
        local function DeleteBoss()
            local rID, bID = addon.History.selectedRaid, addon.History.selectedBoss
            if not (rID and bID) then return end
            local raid = KRT_Raids[rID]
            if not (raid and raid.bossKills and raid.bossKills[bID]) then return end

            -- Elimina loot del boss rimosso e riallinea gli indici per le successive
            for i = #raid.loot, 1, -1 do
                local bn = tonumber(raid.loot[i].bossNum)
                if bn then
                    if bn == bID then
                        tremove(raid.loot, i)
                    elseif bn > bID then
                        raid.loot[i].bossNum = bn - 1
                    end
                end
            end

            -- Rimuovi il boss dalla lista
            tremove(raid.bossKills, bID)

            addon.History.selectedBoss = nil
            Utils.triggerEvent("HistorySelectRaid", addon.History.selectedRaid)
        end

        function Boss:Delete()
            if addon.History.selectedBoss then
                StaticPopup_Show("KRTHISTORY_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTHISTORY_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBoss)
    end

    function Boss:GetName(bossNum, raidNum)
        local raid = KRT_Raids[raidNum or KRT_CurrentRaid]
        local name = L.StrUnknown
        if raid and raid.bossKills and raid.bossKills[bossNum] then
            name = raid.bossKills[bossNum].name
            if name == "_TrashMob_" then name = L.StrTrashMob end
        end
        return name
    end

    Utils.registerCallback("HistorySelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("HistorySelectBoss", function() controller:Touch() end)
end

-- ============================================================================
-- Boss Attendees List
-- ============================================================================
do
    addon.History.BossAttendees = addon.History.BossAttendees or {}
    local M                     = addon.History.BossAttendees
    local L                     = addon.L

    local controller            = Utils.makeListController {
        keyName     = "BossAttendees",
        poolTag     = "history-boss-attendees",
        _rowParts   = { "Name" },

        localize    = function(n)
            _G[n .. "Title"]:SetText(L.StrBossAttendees)
        end,

        getData     = function(out)
            local rID = addon.History.selectedRaid
            local bID = addon.History.selectedBoss
            if not (rID and bID) then return end

            local src = addon.Raid:GetPlayers(rID, bID) or {}
            for i = 1, #src do
                local p  = src[i]
                local it = TGet("history-boss-attendees")
                it.id    = p.id
                it.name  = p.name
                it.class = p.class
                out[i]   = it
            end
        end,

        rowName     = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl     = "KRTHistoryBossAttendeeButton",

        drawRow     = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.Name:SetText(it.name)
                local r, g, b = addon.GetClassColor(it.class)
                ui.Name:SetVertexColor(r, g, b)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.History.selectedBossPlayer end,

        postUpdate  = function(n)
            local bSel = addon.History.selectedBoss
            local pSel = addon.History.selectedBossPlayer
            Utils.enableDisable(_G[n .. "AddBtn"], bSel and not pSel)
            Utils.enableDisable(_G[n .. "RemoveBtn"], bSel and pSel)
        end,

        sorters     = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
        },
    }

    Utils.bindListController(M, controller)

    function M:Add() addon.History.AttendeesBox:Toggle() end

    do
        local function DeleteAttendee()
            local rID = addon.History.selectedRaid
            local bID = addon.History.selectedBoss
            local pID = addon.History.selectedBossPlayer
            if not (rID and bID and pID) then return end

            local raid = KRT_Raids[rID]
            if not (raid and raid.bossKills and raid.bossKills[bID]) then return end

            local name = addon.Raid:GetPlayerName(pID, rID)
            local list = raid.bossKills[bID].players
            local i = tIndexOf(list, name)
            while i do
                tremove(list, i)
                i = tIndexOf(list, name)
            end

            addon.History.selectedBossPlayer = nil
            controller:Dirty()
        end

        function M:Delete()
            if addon.History.selectedBossPlayer then
                StaticPopup_Show("KRTHISTORY_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTHISTORY_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallbacks({ "HistorySelectRaid", "HistorySelectBoss" }, function() controller:Dirty() end)
    Utils.registerCallback("HistorySelectBossPlayer", function() controller:Touch() end)
end

-- ============================================================================
-- Raid Attendees List
-- ============================================================================
do
    addon.History.RaidAttendees = addon.History.RaidAttendees or {}
    local M                     = addon.History.RaidAttendees
    local L                     = addon.L

    local controller            = Utils.makeListController {
        keyName     = "RaidAttendees",
        poolTag     = "history-raid-attendees",
        _rowParts   = { "Name", "Join", "Leave" },

        localize    = function(n)
            _G[n .. "Title"]:SetText(L.StrRaidAttendees)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            -- Add non implementato (per ora)
            _G[n .. "AddBtn"]:Disable()
        end,

        getData     = function(out)
            local rID = addon.History.selectedRaid
            if not rID then return end

            local src = addon.Raid:GetPlayers(rID) or {}
            for i = 1, #src do
                local p     = src[i]
                local it    = TGet("history-raid-attendees")
                it.id       = p.id
                it.name     = p.name
                it.class    = p.class
                it.join     = p.join
                it.leave    = p.leave
                it.joinFmt  = date("%H:%M", p.join)
                it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
                out[i]      = it
            end
        end,

        rowName     = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl     = "KRTHistoryRaidAttendeeButton",

        drawRow     = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.Name:SetText(it.name)
                local r, g, b = addon.GetClassColor(it.class)
                ui.Name:SetVertexColor(r, g, b)
                ui.Join:SetText(it.joinFmt)
                ui.Leave:SetText(it.leaveFmt)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.History.selectedPlayer end,

        postUpdate  = function(n)
            Utils.enableDisable(_G[n .. "DeleteBtn"], addon.History.selectedPlayer ~= nil)
        end,

        sorters     = {
            name  = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            join  = function(a, b, asc) return asc and (a.join < b.join) or (a.join > b.join) end,
            leave = function(a, b, asc)
                local A = a.leave or (asc and math.huge or -math.huge)
                local B = b.leave or (asc and math.huge or -math.huge)
                return asc and (A < B) or (A > B)
            end,
        },
    }

    Utils.bindListController(M, controller)

    do
        local function DeleteAttendee()
            local rID, pID = addon.History.selectedRaid, addon.History.selectedPlayer
            if not (rID and pID) then return end

            local raid = KRT_Raids[rID]
            if not (raid and raid.players and raid.players[pID]) then return end

            local name = raid.players[pID].name
            tremove(raid.players, pID)

            for _, boss in ipairs(raid.bossKills) do
                local i = tIndexOf(boss.players, name)
                while i do
                    tremove(boss.players, i)
                    i = tIndexOf(boss.players, name)
                end
            end

            for i = #raid.loot, 1, -1 do
                if raid.loot[i].looter == name then
                    tremove(raid.loot, i)
                end
            end

            addon.History.selectedPlayer = nil
            controller:Dirty()
        end

        function M:Delete()
            if addon.History.selectedPlayer then
                StaticPopup_Show("KRTHISTORY_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTHISTORY_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallback("HistorySelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("HistorySelectPlayer", function() controller:Touch() end)
end

-- ============================================================================
-- Loot List
-- ============================================================================
do
    addon.History.Loot = addon.History.Loot or {}
    local module       = addon.History.Loot
    local L            = addon.L

    local controller   = Utils.makeListController {
        keyName     = "LootList",
        poolTag     = "history-loot",
        _rowParts   = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" },

        localize    = function(n)
            _G[n .. "Title"]:SetText(L.StrRaidLoot)
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

        getData     = function(out)
            local rID = addon.History.selectedRaid
            if not rID then return end

            local loot  = addon.Raid:GetLoot(rID) or {}

            local bID   = addon.History.selectedBoss
            local pID   = addon.History.selectedBossPlayer or addon.History.selectedPlayer
            local pName = pID and addon.Raid:GetPlayerName(pID, rID) or nil

            local n     = 0
            for i = 1, #loot do
                local v = loot[i]
                if (not bID or bID <= 0 or v.bossNum == bID) and (not pName or v.looter == pName) then
                    n              = n + 1
                    local it       = TGet("history-loot")
                    it.id          = v.id
                    it.itemId      = v.itemId
                    it.itemName    = v.itemName
                    it.itemRarity  = v.itemRarity
                    it.itemTexture = v.itemTexture
                    it.itemLink    = v.itemLink
                    it.bossNum     = v.bossNum
                    it.looter      = v.looter
                    it.rollType    = v.rollType
                    it.rollValue   = v.rollValue
                    it.time        = v.time
                    it.timeFmt     = date("%H:%M", v.time)
                    out[n]         = it
                end
            end
        end,

        rowName     = function(n, _, i) return n .. "ItemBtn" .. i end,
        rowTmpl     = "KRTHistoryLootButton",

        drawRow     = (function()
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
                local selectedBoss = addon.History.selectedBoss
                if selectedBoss and v.bossNum == selectedBoss then
                    ui.Source:SetText("")
                else
                    ui.Source:SetText(addon.History.Boss:GetName(v.bossNum, addon.History.selectedRaid))
                end

                local r, g, b = addon.GetClassColor(addon.Raid:GetPlayerClass(v.looter))
                ui.Winner:SetText(v.looter)
                ui.Winner:SetVertexColor(r, g, b)

                ui.Type:SetText(lootTypesColored[v.rollType] or lootTypesColored[4])
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

        highlightId = function() return addon.History.selectedItem end,

        postUpdate  = function(n)
            Utils.enableDisable(_G[n .. "DeleteBtn"], addon.History.selectedItem ~= nil)
        end,

        sorters     = {
            id     = function(a, b, asc) return asc and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
            source = function(a, b, asc) return asc and (a.bossNum < b.bossNum) or (a.bossNum > b.bossNum) end,
            winner = function(a, b, asc) return asc and (a.looter < b.looter) or (a.looter > b.looter) end,
            type   = function(a, b, asc) return asc and (a.rollType < b.rollType) or (a.rollType > b.rollType) end,
            roll   = function(a, b, asc)
                local A = a.rollValue or 0
                local B = b.rollValue or 0
                return asc and (A < B) or (A > B)
            end,
            time   = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
        },
    }

    Utils.bindListController(module, controller)

    function module:OnEnter(widget)
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
            local rID, iID = addon.History.selectedRaid, addon.History.selectedItem
            if rID and KRT_Raids[rID] and iID then
                tremove(KRT_Raids[rID].loot, iID)
                addon.History.selectedItem = nil
                controller:Dirty()
            end
        end

        function module:Delete()
            if addon.History.selectedItem then
                StaticPopup_Show("KRTHISTORY_DELETE_ITEM")
            end
        end

        controller._makeConfirmPopup("KRTHISTORY_DELETE_ITEM", L.StrConfirmDeleteItem, DeleteItem)
    end

    function module:Log(itemID, looter, rollType, rollValue)
        local raidID = addon.History.selectedRaid or KRT_CurrentRaid
        if not raidID or not KRT_Raids[raidID] then return end

        local it = KRT_Raids[raidID].loot[itemID]
        if not it then return end

        if looter and looter ~= "" then it.looter = looter end
        if tonumber(rollType) then it.rollType = tonumber(rollType) end
        if tonumber(rollValue) then it.rollValue = tonumber(rollValue) end

        controller:Dirty()
    end

    local function Reset() controller:Dirty() end
    Utils.registerCallbacks(
        { "HistorySelectRaid", "HistorySelectBoss", "HistorySelectPlayer", "HistorySelectBossPlayer" },
        Reset
    )
    Utils.registerCallback("HistorySelectItem", function() controller:Touch() end)
end

-- ============================================================================
-- History: Add/Edit Boss Popup  (Patch #1 — uniforma a time/mode)
-- ============================================================================
do
    addon.History.BossBox              = addon.History.BossBox or {}
    local Box                          = addon.History.BossBox
    local L                            = addon.L

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}
    local updateInterval               = C.UPDATE_INTERVAL_HISTORY

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
        if f and f:IsShown() then f:Hide() end
    end

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    function Box:Fill()
        local rID, bID = addon.History.selectedRaid, addon.History.selectedBoss
        if not (rID and bID) then return end

        raidData = KRT_Raids[rID]
        if not raidData then return end

        bossData = raidData.bossKills[bID]
        if not bossData then return end

        _G[frameName .. "Name"]:SetText(bossData.name or "")

        local bossTime = bossData.time or bossData.date or time()
        local d        = date("*t", bossTime)
        tempDate       = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
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
        local rID = addon.History.selectedRaid
        if not rID then return end

        local name  = (_G[frameName .. "Name"]:GetText() or ""):trim()
        local modeT = strlower((_G[frameName .. "Difficulty"]:GetText() or ""):trim())
        local bTime = (_G[frameName .. "Time"]:GetText() or ""):trim()

        name        = (name == "") and "_TrashMob_" or name
        if name ~= "_TrashMob_" and (modeT ~= "h" and modeT ~= "n") then
            addon:error(L.ErrBossDifficulty)
            return
        end

        local h, m = bTime:match("^(%d+):(%d+)$")
        h, m = tonumber(h), tonumber(m)
        if not (h and m and h >= 0 and h <= 23 and m >= 0 and m <= 59) then
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
                name    = name,
                time    = time(killDate),
                mode    = mode,
                players = {},
            })
        end

        self:Hide()
        Utils.triggerEvent("HistorySelectRaid", addon.History.selectedRaid)
    end

    function Box:CancelAddEdit()
        _G[frameName .. "Name"]:SetText("")
        _G[frameName .. "Difficulty"]:SetText("")
        _G[frameName .. "Time"]:SetText("")
        isEdit, raidData, bossData = false, {}, {}
        wipe(tempDate)
    end

    function Box:UpdateUIFrame(frame, elapsed)
        if not localized then
            addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
            localized = true
        end
        if Utils.throttle(frame, frameName, updateInterval, elapsed) then
            Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
        end
    end
end

-- ============================================================================
-- History: Add Attendee Popup
-- ============================================================================
do
    addon.History.AttendeesBox = addon.History.AttendeesBox or {}
    local Box                  = addon.History.AttendeesBox
    local L                    = addon.L

    local frameName

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnShow", function()
            local e = _G[frameName .. "Name"]
            e:SetText("")
            e:SetFocus()
        end)
        frame:SetScript("OnHide", function()
            local e = _G[frameName .. "Name"]
            e:SetText("")
            e:ClearFocus()
        end)
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Save()
        local name = (_G[frameName .. "Name"]:GetText() or ""):trim()
        if name == "" then
            addon:error(L.ErrAttendeesInvalidName)
            return
        end

        local rID, bID = addon.History.selectedRaid, addon.History.selectedBoss
        if not (rID and bID and KRT_Raids[rID]) then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return
        end

        local bossKill = KRT_Raids[rID].bossKills[bID]
        for _, n in ipairs(bossKill.players) do
            if n:lower() == name:lower() then
                addon:error(L.ErrAttendeesPlayerExists)
                return
            end
        end

        for _, p in ipairs(KRT_Raids[rID].players) do
            if name:lower() == p.name:lower() then
                tinsert(bossKill.players, p.name)
                addon:info(L.StrAttendeesAddSuccess)
                self:Toggle()
                Utils.triggerEvent("HistorySelectBoss", addon.History.selectedBoss)
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
    local cmdHistory = { "history", "log", "logger" }
    local cmdDebug = { "debug", "dbg", "debugger" }
    local cmdLoot = { "loot", "ml", "master" }
    local cmdReserves = { "res", "reserves", "reserve" }
    local cmdChat = { "chat", "throttle", "chatthrottle" }
    local cmdMinimap = { "minimap", "mm" }

    local helpString = "%s: %s"
    local function printHelp(cmd, desc)
        print(helpString:format(addon.WrapTextInColorCode(cmd, Utils.normalizeHexColor(RT_COLOR)), desc))
    end

    local function showHelp()
        addon:info(format(L.StrCmdCommands, "krt"), "KRT")
        printHelp("config", L.StrCmdConfig)
        printHelp("lfm", L.StrCmdGrouper)
        printHelp("ach", L.StrCmdAchiev)
        printHelp("changes", L.StrCmdChanges)
        printHelp("warnings", L.StrCmdWarnings)
        printHelp("history", L.StrCmdHistory)
        printHelp("reserves", L.StrCmdReserves)
    end

    local function splitArgs(msg)
        msg = (msg or ""):trim()
        local cmd, rest = msg:match("^(%S+)%s*(.-)$")
        return (cmd or ""):lower(), (rest or ""):trim()
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
        local cmd, rest = splitArgs(msg)
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
        local subCmd, arg = splitArgs(rest)
        if subCmd == "" then subCmd = nil end

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
                addon:info("Current log level: %s", name or tostring(lvl))
                return
            end

            local lv = tonumber(arg)
            if not lv and addon.logLevels then
                lv = addon.logLevels[upper(arg)]
            end
            if lv then
                addon:SetLogLevel(lv)
                KRT_Debug.level = lv
                addon:info("Log level set to [%s]", arg)
            else
                addon:warn("Unknown log level: %s", arg)
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

    registerAliases(cmdChat, function(rest)
        local val = tonumber(rest)
        if val then
            addon.options.chatThrottle = val
            addon:info(L.MsgChatThrottleSet, val)
        else
            addon:info(L.MsgChatThrottleSet, addon.options.chatThrottle)
        end
    end)

    registerAliases(cmdMinimap, function(rest)
        local sub, arg = splitArgs(rest)
        if sub == "on" then
            addon.options.minimapButton = true
            if KRT_MINIMAP_GUI then KRT_MINIMAP_GUI:Show() end
        elseif sub == "off" then
            addon.options.minimapButton = false
            if KRT_MINIMAP_GUI then KRT_MINIMAP_GUI:Hide() end
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
        local sub = splitArgs(rest)
        if sub == "reset" then
            addon.Config:Default()
        else
            addon.Config:Toggle()
        end
    end)

    registerAliases(cmdWarnings, function(rest)
        local sub = splitArgs(rest)
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
        local sub = splitArgs(rest)
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

    registerAliases(cmdHistory, function(rest)
        local sub = splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.History:Toggle()
        end
    end)

    registerAliases(cmdLoot, function(rest)
        local sub = splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" then
            addon.Master:Toggle()
        end
    end)

    registerAliases(cmdReserves, function(rest)
        local sub = splitArgs(rest)
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
        local sub, arg = splitArgs(rest)
        if not sub or sub == "" or sub == "toggle" or sub == "show" then
            addon.Spammer:Toggle()
        elseif sub == "start" then
            addon.Spammer:Start()
        elseif sub == "stop" then
            addon.Spammer:Stop()
        elseif sub == "period" then
            if arg and arg ~= "" then
                local v = tonumber(arg)
                if v then
                    addon.options.lfmPeriod = v
                    addon:info(L.MsgLFMPeriodSet, v)
                end
            else
                addon:info(L.MsgLFMPeriodSet, addon.options.lfmPeriod)
            end
        else
            addon:info(format(L.StrCmdCommands, "krt pug"), "KRT")
            printHelp("toggle", L.StrCmdToggle)
            printHelp("start", L.StrCmdLFMStart)
            printHelp("stop", L.StrCmdLFMStop)
            printHelp("period", L.StrCmdLFMPeriod)
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
}

--
-- ADDON_LOADED: Initializes the addon after loading.
--
function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    addon.LoadOptions()
    for event, handler in pairs(addonEvents) do
        local method = handler
        self:RegisterEvent(event, function(...)
            self[method](self, ...)
        end)
    end
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
    if L.RaidZones[instanceName] ~= nil then
        Utils.After(3, function()
            addon.Raid:Check(instanceName, instanceDiff)
        end)
    end
end

--
-- PLAYER_ENTERING_WORLD: Performs initial checks when the player logs in.
--
function addon:PLAYER_ENTERING_WORLD()
    mainFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local module = self.Raid
    Utils.CancelTimer(module.firstCheckHandle, true)
    module.firstCheckHandle = Utils.After(3, function() module:FirstCheck() end)
end

--
-- CHAT_MSG_LOOT: Adds looted items to the raid log.
--
function addon:CHAT_MSG_LOOT(msg)
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

-- Master looter events
do
    local forward = {
        ITEM_LOCKED = "ITEM_LOCKED",
        LOOT_OPENED = "LOOT_OPENED",
        LOOT_CLOSED = "LOOT_CLOSED",
        LOOT_SLOT_CLEARED = "LOOT_SLOT_CLEARED",
        TRADE_ACCEPT_UPDATE = "TRADE_ACCEPT_UPDATE",
    }
    for e, m in pairs(forward) do
        local method = m
        addon[e] = function(_, ...)
            addon.Master[method](addon.Master, ...)
        end
    end
end

--
-- CHAT_MSG_MONSTER_YELL: Logs a boss kill based on specific boss yells.
--
function addon:CHAT_MSG_MONSTER_YELL(...)
    local text, boss = ...
    if L.BossYells[text] and KRT_CurrentRaid then
        self.Raid:AddBoss(L.BossYells[text])
    end
end

--
-- COMBAT_LOG_EVENT_UNFILTERED: Logs a boss kill when a boss unit dies.
--
function addon:COMBAT_LOG_EVENT_UNFILTERED(...)
    local _, event, _, _, _, destGUID = ...
    if not KRT_CurrentRaid then return end
    if event == "UNIT_DIED" then
        local class, unit = addon.GetClassFromGUID(destGUID, "player")
        if unit then return end
        class = class or "UNKNOWN"
        local npcId = addon.GetCreatureId(destGUID)
        local boss = addon.BossIDs:GetBossName(npcId)
        if boss then
            self.Raid:AddBoss(boss)
        end
    end
end
