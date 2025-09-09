--[[
    KRT.lua
    - Main addon file for Kader Raid Tools (KRT).
    - Handles core logic, event registration, and module initialization.
]]

local addonName, addon                  = ...
local L                                 = addon.L
local Utils                             = addon.Utils

local ITEM_LINK_PATTERN =
    "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?" ..
    "(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?"

local _G                                = _G
_G["KRT"]                               = addon

---============================================================================
-- Saved Variables
-- These variables are persisted across sessions for the addon.
---============================================================================

KRT_Options                             = KRT_Options or {}
KRT_Raids                               = KRT_Raids or {}
KRT_Players                             = KRT_Players or {}
KRT_Warnings                            = KRT_Warnings or {}
KRT_ExportString                        = KRT_ExportString or "$I,$N,$S,$W,$T,$R,$H:$M,$d/$m/$y"
KRT_Spammer                             = KRT_Spammer or {}
KRT_CurrentRaid                         = KRT_CurrentRaid or nil
KRT_LastBoss                            = KRT_LastBoss or nil
KRT_NextReset                           = KRT_NextReset or 0
KRT_SavedReserves                       = KRT_SavedReserves or {}
KRT_PlayerCounts                        = KRT_PlayerCounts or {}

---============================================================================
-- External Libraries / Bootstrap
---============================================================================
local LibStub = _G.LibStub
if LibStub then
    addon.Compat   = LibStub("LibCompat-1.0",   true)
    addon.BossIDs  = LibStub("LibBossIDs-1.0",  true)
    addon.Logger   = LibStub("LibLogger-1.0",   true)
    addon.Deformat = LibStub("LibDeformat-3.0", true)
    addon.CallbackHandler = LibStub("CallbackHandler-1.0", true)

    if addon.Compat and addon.Compat.Embed then
        addon.Compat:Embed(addon) -- mixin: After, UnitIterator, GetCreatureId, etc.
    end
    if addon.Logger and addon.Logger.Embed then
        addon.Logger:Embed(addon)
    end
end

-- Alias locali (safe e veloci)
local IsInRaid      = addon.IsInRaid
local UnitIterator  = addon.UnitIterator
local After         = addon.After
local GetCreatureId = addon.GetCreatureId

function addon:Debug(level, fmt, ...)
    if not self.Logger then return end
    local lv = type(level) == "string" and level:upper()
    local fn = (lv == "ERROR" and self.error)
              or (lv == "WARN" and self.warn)
              or (lv == "DEBUG" and self.debug)
              or self.info
    if fn then fn(self, fmt, ...) end
    if self.Debugger and self.Debugger.AddMessage and self.logLevels and self.logLevel then
        local lvl = self.logLevels[lv] or self.logLevels.INFO
        if lvl <= self.logLevel then
            local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
            self.Debugger:AddMessage(msg)
        end
    end
end

-- SavedVariables for log level (fallback INFO)
KRT_Debug = KRT_Debug or {}
do
    local INFO = (addon.Logger and addon.Logger.logLevels and addon.Logger.logLevels.INFO) or 2
    KRT_Debug.level = KRT_Debug.level or INFO
    if addon.SetLogLevel then
        local lv = KRT_Debug.level
        if KRT_Options and KRT_Options.debug and addon.Logger and addon.Logger.logLevels then
            lv = addon.Logger.logLevels.DEBUG or lv
        end
        addon:SetLogLevel(lv)
    end
    if addon.SetPerformanceMode then
        addon:SetPerformanceMode(true)
    end
end

---============================================================================
-- Debugger Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Debugger = addon.Debugger or {}
    local module = addon.Debugger

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local debugFrame, msgFrame

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------
    function module:OnLoad(frame)
        if not frame then return end
        debugFrame = frame
        msgFrame = _G[frame:GetName() .. "ScrollFrame"]
    end

    function module:AddMessage(msg, r, g, b)
        if msgFrame then
            msgFrame:AddMessage(tostring(msg), r or 1, g or 1, b or 1)
        end
    end

    function module:Clear()
        if msgFrame then msgFrame:Clear() end
    end

    function module:Toggle()
        if not debugFrame then return end
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

-- Addon UI Frames
local mainFrame                         = CreateFrame("Frame")
local UIMaster, UIConfig, UISpammer, UIChanges, UIWarnings
local UIHistory, UIHistoryItemBox
-- local UIHistoryBossBox, UIHistoryPlayerBox
local _

-- Local Variables
local unitName                          = UnitName("player")

-- Rolls & Loot
local trader, winner
local holder, banker, disenchanter
local lootOpened                        = false
local lootCloseTimer
local currentRollType                   = 4
local currentRollItem                   = 0
local fromInventory                     = false
local itemInfo                          = {}
local lootCount                         = 0
local rollsCount                        = 0
local itemCount                         = 1
local itemTraded                        = 0

-- Function placeholders for loot helpers
local ItemExists, ItemIsSoulbound, GetItem
local GetItemIndex, GetItemName, GetItemLink, GetItemTexture

---============================================================================
-- Constants & Static Data
---============================================================================

-- Roll Types Enum
local rollTypes                         = {
    MAINSPEC   = 1,
    OFFSPEC    = 2,
    RESERVED   = 3,
    FREE       = 4,
    BANK       = 5,
    DISENCHANT = 6,
    HOLD       = 7,
    DKP        = 8
}

-- Roll Type Display Text
local lootTypesText                     = {
    L.BtnMS,
    L.BtnOS,
    L.BtnSR,
    L.BtnFree,
    L.BtnBank,
    L.BtnDisenchant,
    L.BtnHold
}

-- Roll Type Colored Display Text
local lootTypesColored                  = {
    Utils.wrapTextInColorCode(L.BtnMS, GREEN_FONT_COLOR_CODE:sub(3)),
    Utils.wrapTextInColorCode(L.BtnOS, LIGHTYELLOW_FONT_COLOR_CODE:sub(3)),
    Utils.wrapTextInColorCode(L.BtnSR, "ffa335ee"),
    Utils.wrapTextInColorCode(L.BtnFree, NORMAL_FONT_COLOR_CODE:sub(3)),
    Utils.wrapTextInColorCode(L.BtnBank, ORANGE_FONT_COLOR_CODE:sub(3)),
    Utils.wrapTextInColorCode(L.BtnDisenchant, RED_FONT_COLOR_CODE:sub(3)),
    Utils.wrapTextInColorCode(L.BtnHold, HIGHLIGHT_FONT_COLOR_CODE:sub(3)),
    Utils.wrapTextInColorCode("DKP", GREEN_FONT_COLOR_CODE:sub(3)),
}

-- Item Quality Colors
local itemColors                        = {
    [1] = "ff9d9d9d", -- Poor
    [2] = "ffffffff", -- Common
    [3] = "ff1eff00", -- Uncommon
    [4] = "ff0070dd", -- Rare
    [5] = "ffa335ee", -- Epic
    [6] = "ffff8000", -- Legendary
    [7] = "ffe6cc80", -- Artifact / Heirloom
}

-- Class Colors
local CLASS_COLORS                      = {
    ["UNKNOWN"]     = "ffffffff",
    ["DEATHKNIGHT"] = "ffc41f3b",
    ["DRUID"]       = "ffff7d0a",
    ["HUNTER"]      = "ffabd473",
    ["MAGE"]        = "ff40c7eb",
    ["PALADIN"]     = "fff58cba",
    ["PRIEST"]      = "ffffffff",
    ["ROGUE"]       = "fffff569",
    ["SHAMAN"]      = "ff0070de",
    ["WARLOCK"]     = "ff8787ed",
    ["WARRIOR"]     = "ffc79c6e",
}

-- Raid Target Markers
local RAID_TARGET_MARKERS               = {
    "{circle}",
    "{diamond}",
    "{triangle}",
    "{moon}",
    "{square}",
    "{cross}",
    "{skull}"
}

-- Shared Frame Title String
local titleString                       = "|cfff58cbaK|r|caaf49141RT|r : %s"

---============================================================================
-- Cached Functions & Libraries
---============================================================================

local tinsert, tremove, tconcat, twipe  = table.insert, table.remove, table.concat, table.wipe
local pairs, ipairs, type, select, next = pairs, ipairs, type, select, next
local format, match, find, strlen       = string.format, string.match, string.find, string.len
local strsub, gsub, lower, upper        = string.sub, string.gsub, string.lower, string.upper
local tostring, tonumber, ucfirst       = tostring, tonumber, _G.string.ucfirst
local UnitRace, UnitSex, GetRealmName   = UnitRace, UnitSex, GetRealmName
local GetNumRaidMembers, GetNumPartyMembers = GetNumRaidMembers, GetNumPartyMembers

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
        addon:RegisterEvent("ADDON_LOADED")
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
    addon.Raid = addon.Raid or {}
    local module = addon.Raid
    local L = addon.L

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local inRaid             = false
    local numRaid            = 0
    local GetLootMethod      = GetLootMethod
    local GetRaidRosterInfo  = GetRaidRosterInfo

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
        if not KRT_CurrentRaid then return end
        local count = IsInRaid() and GetNumRaidMembers() or GetNumPartyMembers()
        numRaid = count
        if numRaid == 0 then
            module:End()
            return
        end

        local realm = GetRealmName() or UNKNOWN
        KRT_Players[realm] = KRT_Players[realm] or {}
        local raid = KRT_Raids[KRT_CurrentRaid]
        raid.playersByName = raid.playersByName or {}
        local playersByName = raid.playersByName
        for unit in UnitIterator(true) do
            local name = UnitName(unit)
            if name then
                local index = UnitInRaid(unit)
                local rank, subgroup
                if index then
                    _, rank, subgroup = GetRaidRosterInfo(index)
                end
                if addon.UnitIsGroupLeader and addon.UnitIsGroupLeader(unit) then
                    rank = 2
                elseif addon.UnitIsGroupAssistant and addon.UnitIsGroupAssistant(unit) then
                    rank = 1
                end
                rank = rank or 0
                subgroup = subgroup or 1
                local level = UnitLevel(unit)
                local classL, class = UnitClass(unit)
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

        -- Mark players who have left
        for name, v in pairs(playersByName) do
            if not v.seen and v.leave == nil then
                v.leave = Utils.getCurrentTime()
            end
            v.seen = nil
        end
        Utils.unschedule(module.UpdateRaidRoster)
    end

    --
    -- Creates a new raid log entry.
    --
    function module:Create(zoneName, raidSize)
        if KRT_CurrentRaid then
            self:End()
        end
        if not IsInRaid() then return end
        local numRaid = GetNumRaidMembers()
        if numRaid == 0 then return end

        local realm = GetRealmName() or UNKNOWN
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

        for i = 1, numRaid do
            local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)
                local p = {
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
                    sex    = UnitSex(unitID),
                }
            end
        end

        tinsert(KRT_Raids, raidInfo)
        KRT_CurrentRaid = #KRT_Raids
        Utils.triggerEvent("RaidCreate", KRT_CurrentRaid)
        Utils.schedule(3, module.UpdateRaidRoster)
    end

    --
    -- Ends the current raid log entry, marking end time.
    --
    function module:End()
        if not KRT_CurrentRaid then return end
        Utils.unschedule(module.UpdateRaidRoster)
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
            Utils.unschedule(module.firstCheckHandle)
            module.firstCheckHandle = nil
        end
        local count = IsInRaid() and GetNumRaidMembers() or GetNumPartyMembers()
        if count == 0 then return end

        if KRT_CurrentRaid and module:CheckPlayer(unitName, KRT_CurrentRaid) then
            Utils.schedule(2, module.UpdateRaidRoster)
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
        local player, itemLink, itemCount = addon.Deformat(msg, LOOT_ITEM_MULTIPLE)
        if not player then
            itemCount = 1
            player, itemLink = addon.Deformat(msg, LOOT_ITEM)
        end
        if not player then
            player = unitName
            itemLink, itemCount = addon.Deformat(msg, msg, LOOT_ITEM_SELF_MULTIPLE)
        end
        if not itemLink then
            itemCount = 1
            itemLink = addon.Deformat(msg, LOOT_ITEM_SELF)
        end

        -- Other Loot Rolls
        if not player or not itemLink then
            itemCount = 1
            player, itemLink = addon.Deformat(msg, LOOT_ROLL_YOU_WON)
            if not itemLink then
                player = unitName
                itemLink = addon.Deformat(msg, LOOT_ROLL_YOU_WON)
            end
        end
        if not itemLink then return end
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

        if not rollType then rollType = currentRollType end
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
        local players = module:GetPlayers(raidNum)
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
        local size = 0
        if IsInRaid() then
            local diff = GetRaidDifficulty()
            size = (diff == 1 or diff == 3) and 10 or 25
        end
        return size
    end

    --
    -- Returns the RGB color values for a given class name.
    --
    function module:GetClassColor(name)
        return Utils.getClassColor(name)
    end

    --
    -- Checks if a raid log is expired (older than the weekly reset).
    --
    function module:Expired(rID)
        rID = rID or KRT_CurrentRaid
        if not rID or not KRT_Raids[rID] then
            return true
        end

        local currentTime = Utils.getCurrentTime()
        local startTime = KRT_Raids[rID].startTime
        local validDuration = (currentTime + KRT_NextReset) - startTime

        local isExpired = validDuration >= 604800 -- 7 days in seconds
        return isExpired
    end

    --
    -- Retrieves all loot for a given raid and optional boss number.
    --
    function module:GetLoot(raidNum, bossNum)
        local items = {}
        raidNum = raidNum or KRT_CurrentRaid
        bossNum = bossNum or 0
        if not raidNum or not KRT_Raids[raidNum] then
            return items
        end
        local loot = KRT_Raids[raidNum].loot
        local total = 0
        if tonumber(bossNum) <= 0 then
            -- Get all loot
            for k, v in ipairs(loot) do
                local info = v
                info.id = k
                tinsert(items, info)
                total = total + 1
            end
        elseif KRT_Raids[raidNum].bossKills[bossNum] then
            -- Get loot for a specific boss
            for k, v in ipairs(loot) do
                if v.bossNum == bossNum then
                    local info = v
                    info.id = k
                    tinsert(items, info)
                    total = total + 1
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
        holderName = holderName or unitName
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
        local players = {}
        if raidNum and KRT_Raids[raidNum] then
            for k, v in ipairs(KRT_Raids[raidNum].players) do
                local info = v
                v.id = k
                tinsert(players, info)
            end
            -- players = KRT_Raids[raidNum].players
            if bossNum and KRT_Raids[raidNum].bossKills[bossNum] then
                local _players = {}
                for i, p in ipairs(players) do
                    if Utils.checkEntry(KRT_Raids[raidNum]["bossKills"][bossNum]["players"], p.name) then
                        tinsert(_players, p)
                    end
                end
                return _players
            end
        end
        return players
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
            name = name or unitName
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
        for k, v in ipairs(loot) do
            if v.looter == name then
                local info = v
                info.id = k
                tinsert(items, info)
            end
        end
        return items
    end

    --
    -- Gets a player's rank.
    --
    function module:GetPlayerRank(name, raidNum)
        local players = module:GetPlayers(raidNum)
        local rank = 0
        local originalName = name
        name = name or unitName or UnitName("player")
        if next(players) == nil then
            if IsInRaid() then
                numRaid = GetNumRaidMembers()
                for i = 1, numRaid do
                    local pname, prank = GetRaidRosterInfo(i)
                    if pname == name then
                        rank = prank
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
        local realm = GetRealmName() or UNKNOWN
        local resolvedName = name or unitName
        if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
            class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
        end
        return class
    end

    --
    -- Gets a player's unit ID (e.g., "raid1").
    --
    function module:GetUnitID(name)
        local players = module:GetPlayers()
        local id = "none"
        local resolvedName = name
        if players then
            for i, p in ipairs(players) do
                if p.name == name then
                    id = "raid" .. tostring(i)
                    break
                end
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
        local method, partyID = GetLootMethod()
        local isML = (partyID and partyID == 0)
        return isML
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
    -- Output strings:
    local output          = "%s: %s"
    local chatPrefix      = "Kader Raid Tools"
    local chatPrefixShort = "KRT"
    local prefixHex       = Utils.rgbToHex(245/255, 140/255, 186/255)

    --
    -- Prepares the final output string with a prefix.
    --
    local function PreparePrint(text, prefix)
        prefix = prefix or chatPrefixShort
        if prefixHex then
            prefix = Utils.wrapTextInColorCode(prefix, prefixHex)
        end
        return format(output, prefix, tostring(text))
    end

    --
    -- Prints a message to the chat frame.
    --
    function addon:Print(text, prefix)
        local msg = PreparePrint(text, prefix)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end

    --
    -- Sends an announcement to the appropriate channel (Raid, Party, etc.).
    --
    function addon:Announce(text, channel)
        local originalChannel = channel
        if not channel then
            -- Switch to raid channel if we're in a raid:
            if IsInRaid() then
                -- Check for countdown messages
                local countdownTicPattern = L.ChatCountdownTic:gsub("%%d", "%%d+")
                local isCountdownMessage = text:find(countdownTicPattern) or text:find(L.ChatCountdownEnd)

                if isCountdownMessage then
                    -- If it's a countdown message:
                    if addon.options.countdownSimpleRaidMsg then
                        channel = "RAID" -- Force RAID if countdownSimpleRaidMsg is true
                        -- Use RAID_WARNING if leader/officer AND useRaidWarning is true
                    elseif addon.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer()) then
                        channel = "RAID_WARNING"
                    else
                        channel = "RAID" -- Fallback
                    end
                else
                    if addon.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer()) then
                        channel = "RAID_WARNING"
                    else
                        channel = "RAID" -- Fallback
                    end
                end

                -- Switch to party mode if we're in a group:
            elseif self:IsInGroup() then
                channel = "PARTY"

                -- Switch to alone mode
            else
                channel = "SAY" -- Fallback for solo
            end
        end
        Utils.chat(tostring(text), channel)
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
        addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
        addonMenu.displayMode = "MENU"
        addonMenu.initialize = function(self, level)
            if not level then return end
            wipe(info)
            if level == 1 then
                -- Toggle master loot frame:
                info.text = MASTER_LOOTER
                info.notCheckable = 1
                info.func = function() addon.Master:Toggle() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Toggle raid warnings frame:
                info.text = RAID_WARNING
                info.notCheckable = 1
                info.func = function() addon.Warnings:Toggle() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Toggle loot history frame:
                info.text = L.StrLootHistory
                info.notCheckable = 1
                info.func = function() addon.History:Toggle() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Separator:
                info.disabled = 1
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Clear raid icons:
                info.text = L.StrClearIcons
                info.notCheckable = 1
                info.func = function() addon.Raid:ClearRaidIcons() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Separator:
                info.disabled = 1
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- MS changes header:
                info.isTitle = 1
                info.text = L.StrMSChanges
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                info.notCheckable = 1
                -- Toggle MS Changes frame:
                info.text = L.BtnConfigure
                info.notCheckable = 1
                info.func = function() addon.Changes:Toggle() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Ask for MS changes:
                info.text = L.BtnDemand
                info.notCheckable = 1
                info.func = function() addon.Changes:Demand() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Spam ms changes:
                info.text = CHAT_ANNOUNCE
                info.notCheckable = 1
                info.func = function() addon.Changes:Announce() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                info.disabled = 1
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
                -- Toggle lfm spammer frame:
                info.text = L.StrLFMSpam
                info.notCheckable = 1
                info.func = function() addon.Spammer:Toggle() end
                UIDropDownMenu_AddButton(info, level)
                wipe(info)
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
            -- Circular drag mode
            centerX, centerY = abs(x), abs(y)
            centerX = (centerX / sqrt(centerX ^ 2 + centerY ^ 2)) * 80
            centerY = (centerY / sqrt(centerX ^ 2 + centerY ^ 2)) * 80
            centerX = x < 0 and -centerX or centerX
            centerY = y < 0 and -centerY or centerY
            self:ClearAllPoints()
            self:SetPoint("CENTER", centerX, centerY)
        end
    end

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------
    function module:SetPos(angle)
        angle = angle % 360
        addon.options.minimapPos = angle
        local r = rad(angle)
        KRT_MINIMAP_GUI:ClearAllPoints()
        KRT_MINIMAP_GUI:SetPoint("CENTER", cos(r) * 80, sin(r) * 80)
    end

    function module:OnLoad(btn)
        if not btn then return end
        addon.options = addon.options or KRT_Options or {}
        KRT_MINIMAP_GUI:SetUserPlaced(true)
        self:SetPos(addon.options.minimapPos or 325)
        if not addon.options.minimapButton then KRT_MINIMAP_GUI:Hide() end
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
            local mx, my = Minimap:GetCenter()
            local bx, by = self:GetCenter()
            module:SetPos(deg(atan2(by - my, bx - mx)))
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
            GameTooltip:SetText("|cfff58cbaKader|r |caad4af37Raid Tools|r")
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
        if self.options.minimapButton then
            KRT_MINIMAP_GUI:Show()
        else
            KRT_MINIMAP_GUI:Hide()
        end
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
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local record, canRoll, warned = false, true, false
    local playerRollTracker, rollsTable, rerolled, itemRollTracker = {}, {}, {}, {}
    local selectedPlayer = nil

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    -- Sorts the rollsTable either ascending or descending.
    local function SortRolls()
        if rollsTable ~= nil then
            table.sort(rollsTable, function(a, b)
                if addon.options.sortAscending then
                    return a.roll < b.roll
                end
                return a.roll > b.roll
            end)
            winner = rollsTable[1].name
            addon:Debug("DEBUG", "Sorted rolls; current winner: %s with roll: %d", winner, rollsTable[1].roll)
        end
    end

    -- Adds a player's roll to the tracking tables.
    local function AddRoll(name, roll, itemId)
        roll = tonumber(roll)
        rollsCount = rollsCount + 1
        rollsTable[rollsCount] = { name = name, roll = roll, itemId = itemId }
        addon:Debug("DEBUG", "AddRoll: name=%s, roll=%d, itemId=%s", tostring(name), roll, tostring(itemId))

        if itemId then
            itemRollTracker[itemId] = itemRollTracker[itemId] or {}
            itemRollTracker[itemId][name] = (itemRollTracker[itemId][name] or 0) + 1
            addon:Debug("DEBUG", "Updated itemRollTracker: itemId=%d, player=%s, count=%d", itemId, name,
                itemRollTracker[itemId][name])
        end

        Utils.triggerEvent("AddRoll", name, roll)
        SortRolls()

        -- Auto-select winner if none is manually selected
        if not selectedPlayer then
            local resolvedItemId = itemId or module:GetCurrentRollItemID()
            if currentRollType == rollTypes.RESERVED then
                local topRoll = -1
                for _, entry in ipairs(rollsTable) do
                    if module:IsReserved(resolvedItemId, entry.name) and entry.roll > topRoll then
                        topRoll = entry.roll
                        selectedPlayer = entry.name
                    end
                end
                addon:Debug("DEBUG", "Reserved roll: auto-selected player=%s", tostring(selectedPlayer))
            else
                selectedPlayer = winner
                addon:Debug("DEBUG", "Free roll: auto-selected player=%s", tostring(selectedPlayer))
            end
        end
        module:FetchRolls()
    end

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------
    -- Initiates a /roll 1-100 for the player.
    function module:Roll(btn)
        local itemId = self:GetCurrentRollItemID()
        if not itemId then return end

        playerRollTracker[itemId] = playerRollTracker[itemId] or 0
        local name = UnitName("player")
        local allowed = 1

        if currentRollType == rollTypes.RESERVED then
            allowed = addon.Reserves:GetReserveCountForItem(itemId, name)
        end

        if playerRollTracker[itemId] >= allowed then
            addon:Debug("DEBUG", "Roll blocked for %s (max %d rolls reached for itemId=%d)", name, allowed, itemId)
            addon:info(L.ChatOnlyRollOnce)
            return
        end

        addon:Debug("DEBUG", "Rolling for itemId=%d (player=%s)", itemId, name)
        RandomRoll(1, 100)
        playerRollTracker[itemId] = playerRollTracker[itemId] + 1
    end

    -- Returns the current roll session state.
    function module:RollStatus()
        addon:Debug("DEBUG", "RollStatus queried: type=%s, record=%s, canRoll=%s, rolled=%s", tostring(currentRollType),
            tostring(record), tostring(canRoll), tostring(rolled))
        return currentRollType, record, canRoll, rolled
    end

    --
    -- Enables or disables the recording of rolls.
    --
    function module:RecordRolls(bool)
        canRoll, record = bool == true, bool == true
        addon:Debug("DEBUG", "RecordRolls: %s", tostring(bool))
    end

    --
    -- Intercepts system messages to detect player rolls.
    --
    function module:CHAT_MSG_SYSTEM(msg)
        if not msg or not record then return end
        local player, roll, min, max = addon.Deformat(msg, RANDOM_ROLL_RESULT)
        if player and roll and min == 1 and max == 100 then
            addon:Debug("DEBUG", "Detected roll message: %s rolled %d (range %d-%d)", player, roll, min, max)

            if not canRoll then
                if not warned then
                    self:Announce(L.ChatCountdownBlock)
                    warned = true
                    addon:Debug("DEBUG", "Roll blocked: countdown active")
                end
                return
            end

            local itemId = self:GetCurrentRollItemID()
            if not itemId or lootCount == 0 then
                addon:error("Item ID missing or loot table not ready – roll will be ignored.")
                addon:Debug("DEBUG", "Roll ignored: missing itemId or lootCount = 0")
                return
            end

            local allowed = 1
            if currentRollType == rollTypes.RESERVED then
                local playerReserves = addon.Reserves:GetReserveCountForItem(itemId, player)
                allowed = playerReserves > 0 and playerReserves or 1
            end

            itemRollTracker[itemId] = itemRollTracker[itemId] or {}
            local used = itemRollTracker[itemId][player] or 0

            if used >= allowed then
                if not Utils.checkEntry(rerolled, player) then
                    Utils.whisper(player, L.ChatOnlyRollOnce)
                    tinsert(rerolled, player)
                    addon:Debug("DEBUG", "Roll denied: %s exceeded allowed rolls for item %d", player, itemId)
                end
                return
            end

            addon:Debug("DEBUG", "Roll accepted: %s (%d/%d) for item %d", player, used + 1, allowed, itemId)
            AddRoll(player, roll, itemId)
        end
    end

    --
    -- Returns the current table of rolls.
    --
    function module:GetRolls()
        addon:Debug("DEBUG", "GetRolls called; count: %d", #rollsTable)
        return rollsTable
    end

    --
    -- Sets the flag indicating the player has rolled.
    --
    function module:SetRolled()
        rolled = true
        addon:Debug("DEBUG", "SetRolled: rolled flag set to true")
    end

    --
    -- Checks if a player has already used all their rolls for an item.
    --
    function module:DidRoll(itemId, name)
        if not itemId then
            for i = 1, rollsCount do
                if rollsTable[i].name == name then
                    addon:Debug("DEBUG", "DidRoll: %s has rolled (no itemId specified)", name)
                    return true
                end
            end
            addon:Debug("DEBUG", "DidRoll: %s has NOT rolled (no itemId specified)", name)
            return false
        end

        itemRollTracker[itemId] = itemRollTracker[itemId] or {}
        local used = itemRollTracker[itemId][name] or 0
        local reserve = addon.Reserves:GetReserveCountForItem(itemId, name)
        local allowed = (currentRollType == rollTypes.RESERVED and reserve > 0) and reserve or 1
        local result = used >= allowed
        addon:Debug("DEBUG", "DidRoll: name=%s, itemId=%d, used=%d, allowed=%d, result=%s", name, itemId, used, allowed,
            tostring(result))
        return result
    end

    --
    -- Returns the highest roll value from the current winner.
    --
    function module:HighestRoll()
        for i = 1, rollsCount do
            if rollsTable[i].name == winner then
                addon:Debug("DEBUG", "HighestRoll: %s rolled %d", winner, rollsTable[i].roll)
                return rollsTable[i].roll
            end
        end
        return 0
    end

    --
    -- Clears all roll-related state and UI elements.
    --
    function module:ClearRolls(rec)
        frameName = frameName or Utils.getFrameName()
        if not frameName then return end
        rollsTable, rerolled, itemRollTracker = {}, {}, {}
        playerRollTracker, rolled, warned, rollsCount = {}, false, false, 0
        selectedPlayer = nil
        if rec == false then record = false end

        local i = 1
        local btn = _G[frameName .. "PlayerBtn" .. i]
        while btn do
            btn:Hide()
            i = i + 1
            btn = _G[frameName .. "PlayerBtn" .. i]
        end

        addon.Raid:ClearRaidIcons()
    end

    --
    -- Gets the item ID of the item currently being rolled for.
    --
    function module:GetCurrentRollItemID()
        local index = GetItemIndex and GetItemIndex() or 1
        local item = GetItem and GetItem(index)
        local itemLink = item and item.itemLink
        if not itemLink then
            addon:Debug("DEBUG", "GetCurrentRollItemID: No itemLink found at index %d", index)
            return nil
        end
        local itemId = tonumber(string.match(itemLink, "item:(%d+)"))
        addon:Debug("DEBUG", "GetCurrentRollItemID: Found itemId %d", itemId)
        return itemId
    end

    --
    -- Validates if a player can still roll for an item.
    --
    function module:IsValidRoll(itemId, name)
        itemRollTracker[itemId] = itemRollTracker[itemId] or {}
        local used = itemRollTracker[itemId][name] or 0
        local allowed = (currentRollType == rollTypes.RESERVED)
            and addon.Reserves:GetReserveCountForItem(itemId, name)
            or 1
        local result = used < allowed
        addon:Debug("DEBUG", "IsValidRoll: %s on item %d: used=%d, allowed=%d, valid=%s", name, itemId, used, allowed,
            tostring(result))
        return result
    end

    --
    -- Checks if a player has reserved the specified item.
    --
    function module:IsReserved(itemId, name)
        local reserved = addon.Reserves:GetReserveCountForItem(itemId, name) > 0
        addon:Debug("DEBUG", "IsReserved: %s for item %d => %s", name, itemId, tostring(reserved))
        return reserved
    end

    --
    -- Gets the number of reserves a player has used for an item.
    --
    function module:GetUsedReserveCount(itemId, name)
        itemRollTracker[itemId] = itemRollTracker[itemId] or {}
        local count = itemRollTracker[itemId][name] or 0
        addon:Debug("DEBUG", "GetUsedReserveCount: %s on item %d => %d", name, itemId, count)
        return count
    end

    --
    -- Gets the total number of reserves a player has for an item.
    --
    function module:GetAllowedReserves(itemId, name)
        local count = addon.Reserves:GetReserveCountForItem(itemId, name)
        addon:Debug("DEBUG", "GetAllowedReserves: %s for item %d => %d", name, itemId, count)
        return count
    end

    --
    -- Rebuilds the roll list UI and marks the top roller or selected winner.
    --
    function module:FetchRolls()
        local frameName = Utils.getFrameName()
        addon:Debug("DEBUG", "FetchRolls called; frameName: %s", frameName)
        local scrollFrame = _G[frameName .. "ScrollFrame"]
        local scrollChild = _G[frameName .. "ScrollFrameScrollChild"]
        scrollChild:SetHeight(scrollFrame:GetHeight())
        scrollChild:SetWidth(scrollFrame:GetWidth())

        local itemId = self:GetCurrentRollItemID()
        local isSR = currentRollType == rollTypes.RESERVED
        addon:Debug("DEBUG", "Current itemId: %s, SR mode: %s", tostring(itemId), tostring(isSR))

        local starTarget = selectedPlayer
        if not starTarget then
            if isSR then
                local topRoll = -1
                for _, entry in ipairs(rollsTable) do
                    local name, roll = entry.name, entry.roll
                    if module:IsReserved(itemId, name) and roll > topRoll then
                        topRoll = roll
                        starTarget = name
                    end
                end
                addon:Debug("DEBUG", "Top SR roll by: %s", tostring(starTarget))
            else
                starTarget = winner
                addon:Debug("DEBUG", "Top roll winner: %s", tostring(starTarget))
            end
        end

        local starShown = false
        local totalHeight = 0
        for i = 1, rollsCount do
            local entry = rollsTable[i]
            local name, roll = entry.name, entry.roll
            local btnName = frameName .. "PlayerBtn" .. i
            local btn = _G[btnName] or CreateFrame("Button", btnName, scrollChild, "KRTSelectPlayerTemplate")

            btn:SetID(i)
            btn:Show()

            if not btn.selectedBackground then
                btn.selectedBackground = btn:CreateTexture("KRTSelectedHighlight", "ARTWORK")
                btn.selectedBackground:SetAllPoints()
                btn.selectedBackground:SetTexture(1, 0.8, 0, 0.1)
                btn.selectedBackground:Hide()
            end

            local nameStr, rollStr, star = _G[btnName .. "Name"], _G[btnName .. "Roll"], _G[btnName .. "Star"]

            if nameStr and nameStr.SetVertexColor then
                local _, class = UnitClass(name)
                class = class and class:upper() or "UNKNOWN"
                if isSR and self:IsReserved(itemId, name) then
                    nameStr:SetVertexColor(0.4, 0.6, 1.0)
                else
                    local r, g, b = addon.Raid:GetClassColor(class)
                    nameStr:SetVertexColor(r, g, b)
                end
            end

            if selectedPlayer == name then
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
            if showStar then
                addon:Debug("DEBUG", "Star assigned to: %s", name)
                starShown = true
            end

            btn:SetScript("OnClick", function()
                selectedPlayer = name
                module:FetchRolls()
            end)

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
        addon:Debug("DEBUG", "FetchRolls completed. Total entries: %d", rollsCount)
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
    local currentItemIndex = 0

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
        if lootCount >= 1 then
            oldItem = GetItemLink(currentItemIndex)
        end
        lootOpened = true
        fromInventory = false
        self:ClearLoot()

        for i = 1, GetNumLootItems() do
            if LootSlotIsItem(i) then
                local itemLink = GetLootSlotLink(i)
                if GetItemFamily(itemLink) ~= 64 then -- no DE mat!
                    self:AddItem(itemLink)
                end
            end
        end

        currentItemIndex = 1
        if oldItem ~= nil then
            for t = 1, lootCount do
                if oldItem == GetItemLink(t) then
                    currentItemIndex = t
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

        if fromInventory == false then
            local lootThreshold = GetLootThreshold()
            if itemRarity < lootThreshold then return end
            lootCount = lootCount + 1
        else
            lootCount = 1
            currentItemIndex = 1
        end
        lootTable[lootCount]             = {}
        lootTable[lootCount].itemName    = itemName
        lootTable[lootCount].itemColor   = itemColors[itemRarity + 1]
        lootTable[lootCount].itemLink    = itemLink
        lootTable[lootCount].itemTexture = itemTexture
        Utils.triggerEvent("AddItem", itemLink)
    end

    --
    -- Prepares the currently selected item for display.
    --
    function module:PrepareItem()
        if ItemExists(currentItemIndex) then
            self:SetItem(lootTable[currentItemIndex])
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
            currentItemLink:SetText(Utils.wrapTextInColorCode(i.itemName, i.itemColor))

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
            currentItemIndex = i
            self:PrepareItem()
        end
    end

    --
    -- Clears all loot from the table and resets the UI display.
    --
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootCount = 0
        frameName = frameName or Utils.getFrameName()
        _G[frameName .. "Name"]:SetText(L.StrNoItemSelected)
        _G[frameName .. "ItemBtn"]:SetNormalTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        if frameName == UIMaster:GetName() then
            _G[frameName .. "ItemCount"]:SetText("")
            _G[frameName .. "ItemCount"]:ClearFocus()
            _G[frameName .. "ItemCount"]:Hide()
        end
    end

    --
    -- Returns the index of the currently selected item.
    --
    function GetItemIndex()
        return currentItemIndex
    end

    --
    -- Returns the table for the currently selected item.
    --
    function GetItem(i)
        i = i or currentItemIndex
        return lootTable[i]
    end

    --
    -- Returns the name of the currently selected item.
    --
    function GetItemName(i)
        i = i or currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    --
    -- Returns the link of the currently selected item.
    --
    function GetItemLink(i)
        i = i or currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    --
    -- Returns the texture of the currently selected item.
    --
    function GetItemTexture(i)
        i = i or currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    --
    -- Checks if a loot item exists at the given index.
    --
    function ItemExists(i)
        i = i or currentItemIndex
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
    local updateInterval = 0.05

    local InitializeDropDowns, PrepareDropDowns, UpdateDropDowns
    local dropDownData, dropDownGroupData = {}, {}
    local dropDownFrameHolder, dropDownFrameBanker, dropDownFrameDisenchanter
    local dropDownsInitialized

    local selectionFrame, UpdateSelectionFrame

    local countdownRun = false
    local countdownStart, countdownPos = 0, 0

    local AssignItem, TradeItem
    local screenshotWarn = false

    local announced = false

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

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
        if UIMaster and UIMaster:IsShown() then
            UIMaster:Hide()
        end
    end

    --
    -- Button: Select/Remove Item
    --
    function module:BtnSelectItem(btn)
        if btn == nil or lootCount <= 0 then return end
        if fromInventory == true then
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(false)
            announced = false
            fromInventory = false
            if lootOpened == true then addon.Loot:FetchLoot() end
        elseif selectionFrame then
            selectionFrame:SetShown(not selectionFrame:IsVisible())
        end
    end

    --
    -- Button: Spam Loot Links or Do Ready Check
    --
    function module:BtnSpamLoot(btn)
        if btn == nil or lootCount <= 0 then return end
        if fromInventory == true then
            addon:Announce(L.ChatReadyCheck)
            DoReadyCheck()
        else
            addon:Announce(L.ChatSpamLoot, "RAID")
            for i = 1, lootCount do
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
        if lootCount >= 1 then
            announced = false
            currentRollType = rollType
            addon.Rolls:ClearRolls()
            addon.Rolls:RecordRolls(true)

            local itemLink = GetItemLink()
            local itemID = tonumber(string.match(itemLink or "", "item:(%d+)"))
            local message = ""

            if rollType == rollTypes.RESERVED and addon.Reserves and addon.Reserves.FormatReservedPlayersLine then
                local srList = addon.Reserves:FormatReservedPlayersLine(itemID)
                local suff = addon.options.sortAscending and "Low" or "High"
                message = itemCount > 1
                    and L[chatMsg .. "Multiple" .. suff]:format(srList, itemLink, itemCount)
                    or L[chatMsg]:format(srList, itemLink)
            else
                local suff = addon.options.sortAscending and "Low" or "High"
                message = itemCount > 1
                    and L[chatMsg .. "Multiple" .. suff]:format(itemLink, itemCount)
                    or L[chatMsg]:format(itemLink)
            end

            addon:Announce(message)
            _G[frameName .. "ItemCount"]:ClearFocus()
            currentRollItem = addon.Raid:GetLootID(itemID)
        end
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
        if lootCount <= 0 or rollsCount <= 0 then
            addon:Debug("DEBUG", "Cannot award, lootCount=%d, rollsCount=%d", lootCount or 0, rollsCount or 0)
            return
        end
        countdownRun = false
        local itemLink = GetItemLink()
        _G[frameName .. "ItemCount"]:ClearFocus()
        if fromInventory == true then
            return TradeItem(itemLink, winner, currentRollType, addon.Rolls:HighestRoll())
        end
        return AssignItem(itemLink, winner, currentRollType, addon.Rolls:HighestRoll())
    end

    --
    -- Button: Hold item
    --
    function module:BtnHold(btn)
        if lootCount <= 0 or holder == nil then return end
        countdownRun = false
        local itemLink = GetItemLink()
        if itemLink == nil then return end
        currentRollType = rollTypes.hold
        if fromInventory == true then
            return TradeItem(itemLink, holder, rollTypes.hold, 0)
        end
        return AssignItem(itemLink, holder, rollTypes.hold, 0)
    end

    --
    -- Button: Bank item
    --
    function module:BtnBank(btn)
        if lootCount <= 0 or banker == nil then return end
        countdownRun = false
        local itemLink = GetItemLink()
        if itemLink == nil then return end
        currentRollType = rollTypes.bank
        if fromInventory == true then
            return TradeItem(itemLink, banker, rollTypes.bank, 0)
        end
        return AssignItem(itemLink, banker, rollTypes.bank, 0)
    end

    --
    -- Button: Disenchant item
    --
    function module:BtnDisenchant(btn)
        if lootCount <= 0 or disenchanter == nil then return end
        countdownRun = false
        local itemLink = GetItemLink()
        if itemLink == nil then return end
        currentRollType = rollTypes.disenchant
        if fromInventory == true then
            return TradeItem(itemLink, disenchanter, rollTypes.disenchant, 0)
        end
        return AssignItem(itemLink, disenchanter, rollTypes.disenchant, 0)
    end

    --
    -- Selects a winner from the roll list.
    --
    function module:SelectWinner(btn)
        if not btn then return end
        local btnName = btn:GetName()
        local player = _G[btnName .. "Name"]:GetText()
        if player ~= nil then
            if IsControlKeyDown() then
                local roll = _G[btnName .. "Roll"]:GetText()
                addon:Announce(format(L.ChatPlayerRolled, player, roll))
                return
            end
            winner = player:trim()
            addon.Rolls:FetchRolls()
            Utils.sync("KRT-RollWinner", player)
        end
        if itemCount == 1 then announced = false end
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
            _G[frameName .. "ImportReservesBtn"]:SetText(L.BtnImportReserves)
        end
        _G[frameName .. "Title"]:SetText(format(titleString, MASTER_LOOTER))
        _G[frameName .. "ItemCount"]:SetScript("OnTextChanged", function(self)
            announced = false
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
        localized = true
    end

    --
    -- OnUpdate handler for the frame, updates UI elements periodically.
    --
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            itemCount = _G[frameName .. "ItemCount"]:GetNumber()
            if itemInfo.count and itemInfo.count ~= itemCount then
                if itemInfo.count < itemCount then
                    itemCount = itemInfo.count
                    _G[frameName .. "ItemCount"]:SetNumber(itemInfo.count)
                end
            end

            -- Dropdown Updates
            UpdateDropDowns(dropDownFrameHolder)
            UpdateDropDowns(dropDownFrameBanker)
            UpdateDropDowns(dropDownFrameDisenchanter)

            -- Button State Updates
            Utils.setText(_G[frameName .. "CountdownBtn"], L.BtnStop, L.BtnCountdown, countdownRun == true)
            Utils.setText(_G[frameName .. "AwardBtn"], TRADE, L.BtnAward, fromInventory == true)
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

            -- Enable/Disable Buttons
            Utils.enableDisable(_G[frameName .. "SelectItemBtn"], lootCount > 1 or (fromInventory and lootCount >= 1))
            Utils.enableDisable(_G[frameName .. "SpamLootBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "MSBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "OSBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "SRBtn"], lootCount >= 1 and addon.Reserves:HasData())
            Utils.enableDisable(_G[frameName .. "FreeBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "CountdownBtn"], lootCount >= 1 and ItemExists())
            Utils.enableDisable(_G[frameName .. "HoldBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "BankBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "DisenchantBtn"], lootCount >= 1)
            Utils.enableDisable(_G[frameName .. "AwardBtn"], (lootCount >= 1 and rollsCount >= 1))
            Utils.enableDisable(_G[frameName .. "OpenReservesBtn"], addon.Reserves:HasData())
            Utils.enableDisable(_G[frameName .. "ImportReservesBtn"], not addon.Reserves:HasData())

            local rollType, record, canRoll, rolled = addon.Rolls:RollStatus()
            Utils.enableDisable(_G[frameName .. "RollBtn"], record and canRoll and rolled == false)
            Utils.enableDisable(_G[frameName .. "ClearBtn"], rollsCount >= 1)

            Utils.setText(_G[frameName .. "SelectItemBtn"], L.BtnRemoveItem, L.BtnSelectItem, fromInventory)
            Utils.setText(_G[frameName .. "SpamLootBtn"], READY_CHECK, L.BtnSpamLoot, fromInventory)
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
        for i = 1, 8 do
            dropDownData[i] = twipe(dropDownData[i])
        end
        dropDownGroupData = twipe(dropDownGroupData)
        for p = 1, GetRealNumRaidMembers() do
            local name, _, subgroup = GetRaidRosterInfo(p)
            if name then
                dropDownData[subgroup][name] = name
                dropDownGroupData[subgroup] = true
            end
        end
    end

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
        elseif name == dropDownFrameBanker:GetName() then
            KRT_Raids[KRT_CurrentRaid].banker = value
        elseif name == dropDownFrameDisenchanter:GetName() then
            KRT_Raids[KRT_CurrentRaid].disenchanter = value
        end
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
            holder = KRT_Raids[KRT_CurrentRaid].holder
            if holder and addon.Raid:GetUnitID(holder) == "none" then
                KRT_Raids[KRT_CurrentRaid].holder = nil
                holder = nil
            end
            if holder then
                UIDropDownMenu_SetText(dropDownFrameHolder, holder)
                UIDropDownMenu_SetSelectedValue(dropDownFrameHolder, holder)
            end
            -- Update loot banker:
        elseif name == dropDownFrameBanker:GetName() then
            banker = KRT_Raids[KRT_CurrentRaid].banker
            if banker and addon.Raid:GetUnitID(banker) == "none" then
                KRT_Raids[KRT_CurrentRaid].banker = nil
                banker = nil
            end
            if banker then
                UIDropDownMenu_SetText(dropDownFrameBanker, banker)
                UIDropDownMenu_SetSelectedValue(dropDownFrameBanker, banker)
            end
            -- Update loot disenchanter:
        elseif name == dropDownFrameDisenchanter:GetName() then
            disenchanter = KRT_Raids[KRT_CurrentRaid].disenchanter
            if disenchanter and addon.Raid:GetUnitID(disenchanter) == "none" then
                KRT_Raids[KRT_CurrentRaid].disenchanter = nil
                disenchanter = nil
            end
            if disenchanter then
                UIDropDownMenu_SetText(dropDownFrameDisenchanter, disenchanter)
                UIDropDownMenu_SetSelectedValue(dropDownFrameDisenchanter, disenchanter)
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
        for i = 1, lootCount do
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
        if lootCount <= 0 then
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
        local itemTexture, itemCount, locked, quality, _, _, itemLink = GetContainerItemInfo(inBag, inSlot)
        if not itemLink or not itemTexture then return end
        _G[frameName .. "ItemBtn"]:SetScript("OnClick", function(self)
            if not ItemIsSoulbound(inBag, inSlot) then
                -- Clear count:
                _G[frameName .. "ItemCount"]:SetText("")
                _G[frameName .. "ItemCount"]:ClearFocus()
                _G[frameName .. "ItemCount"]:Hide()

                fromInventory = true
                addon.Loot:AddItem(itemLink)
                addon.Loot:PrepareItem()
                announced        = false
                -- self.History:SetSource("inventory")
                itemInfo.bagID   = inBag
                itemInfo.slotID  = inSlot
                itemInfo.count   = GetItemCount(itemLink)
                itemInfo.isStack = (itemCount > 1)
                if itemInfo.count >= 1 then
                    itemCount = itemInfo.count
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
            lootOpened = true
            announced = false
            addon.Loot:FetchLoot()
            UpdateSelectionFrame()
            if lootCount >= 1 then UIMaster:Show() end
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
            if lootCloseTimer then
                Utils.CancelTimer(lootCloseTimer)
                lootCloseTimer = nil
            end
            lootCloseTimer = Utils.after(0.1, function()
                lootCloseTimer = nil
                lootOpened = false
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
            if lootCount >= 1 then
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
        if itemCount == 1 and trader and winner and trader ~= winner then
            if tAccepted == 1 and pAccepted == 1 then
                addon.History.Loot:Log(currentRollItem, winner, currentRollType, addon.Rolls:HighestRoll())
                trader = nil
                winner = nil
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

        for p = 1, 40 do
            if GetMasterLootCandidate(p) == playerName then
                GiveMasterLoot(itemIndex, p)
                local output, whisper
                if rollType <= 4 and addon.options.announceOnWin then
                    output = L.ChatAward:format(playerName, itemLink)
                elseif rollType == rollTypes.hold and addon.options.announceOnHold then
                    output = L.ChatHold:format(playerName, itemLink)
                    if addon.options.lootWhispers then
                        whisper = L.WhisperHoldAssign:format(itemLink)
                    end
                elseif rollType == rollTypes.bank and addon.options.announceOnBank then
                    output = L.ChatBank:format(playerName, itemLink)
                    if addon.options.lootWhispers then
                        whisper = L.WhisperBankAssign:format(itemLink)
                    end
                elseif rollType == rollTypes.disenchant and addon.options.announceOnDisenchant then
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
                addon.History.Loot:Log(currentRollItem, playerName, rollType, rollValue)
                return true
            end
        end
        addon:error(L.ErrCannotFindPlayer:format(playerName))
        return false
    end

    --
    -- Trades an item from inventory to a player.
    --
    function TradeItem(itemLink, playerName, rollType, rollValue)
        if itemLink ~= GetItemLink() then return end
        trader = unitName

        -- Prepare initial output and whisper:
        local output, whisper
        local keep = true
        if rollType <= 4 and addon.options.announceOnWin then
            output = L.ChatAward:format(playerName, itemLink)
            keep = false
        elseif rollType == rollTypes.hold and addon.options.announceOnHold then
            output = L.ChatNoneRolledHold:format(itemLink, playerName)
        elseif rollType == rollTypes.bank and addon.options.announceOnBank then
            output = L.ChatNoneRolledBank:format(itemLink, playerName)
        elseif rollType == rollTypes.disenchant and addon.options.announceOnDisenchant then
            output = L.ChatNoneRolledDisenchant:format(itemLink, playerName)
        end

        -- Keeping the item:
        if keep then
            if rollType == rollTypes.hold then
                whisper = L.WhisperHoldTrade:format(itemLink)
            elseif rollType == rollTypes.bank then
                whisper = L.WhisperBankTrade:format(itemLink)
            elseif rollType == rollTypes.disenchant then
                whisper = L.WhisperDisenchantTrade:format(itemLink)
            end
            -- Multiple winners:
        elseif itemCount > 1 then
            -- Announce multiple winners
            addon.Raid:ClearRaidIcons()
            SetRaidTarget(trader, 1)
            local rolls = addon.Rolls:GetRolls()
            local winners = {}
            for i = 1, itemCount do
                if rolls[i] then
                    if rolls[i].name == trader then
                        tinsert(winners, "{star} " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
                    else
                        SetRaidTarget(rolls[i].name, i + 1)
                        tinsert(winners, RAID_TARGET_MARKERS[i] .. " " .. rolls[i].name .. "(" .. rolls[i].roll .. ")")
                    end
                end
            end
            output = L.ChatTradeMutiple:format(tconcat(winners, ", "), trader)
            -- Trader is the winner:
        elseif trader == winner then
            -- Trader won, clear state
            addon.Loot:ClearLoot()
            addon.Rolls:ClearRolls(false)
            addon.Raid:ClearRaidIcons()
        elseif CheckInteractDistance(playerName, 2) == 1 then
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
        elseif addon.Raid:GetUnitID(playerName) ~= "none" then
            -- Player is out of range
            addon.Raid:ClearRaidIcons()
            SetRaidTarget(trader, 1)
            SetRaidTarget(winner, 4)
            output = L.ChatTrade:format(playerName, itemLink)
        end

        if not announced then
            if output then addon:Announce(output) end
            if whisper then
                if playerName == trader then
                    addon.Loot:ClearLoot()
                    addon.Rolls:ClearRolls()
                    addon.Rolls:RecordRolls(false)
                else
                    Utils.whisper(playerName, whisper)
                end
            end
            if rollType <= rollTypes.free and playerName == trader then
                addon.History.Loot:Log(currentRollItem, trader, rollType, rollValue)
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
    local wipe = wipe or table.wipe
    local countsFrame, scrollChild, needsUpdate = nil, nil, false
    
    local function RequestCountsUpdate()
        needsUpdate = true
    end

    -- Helper to ensure frames exist
    local function EnsureFrames()
        countsFrame = countsFrame or _G["KRTLootCounterFrame"]
        scrollChild = scrollChild or _G["KRTLootCounterFrameScrollFrameScrollChild"]
        if countsFrame and not countsFrame._krtCounterHook then
            countsFrame:SetScript("OnUpdate", function()
                if needsUpdate and Utils.throttleKey("LootCounter", 0.1) then
                    needsUpdate = false
                    addon.Master:UpdateCountsFrame()
                end
            end)
            countsFrame._krtCounterHook = true
        end
    end

    -- Return sorted array of player names currently in the raid.
    local function GetCurrentRaidPlayers()
        wipe(raidPlayers)
        if not IsInRaid() then
            return raidPlayers
        end
        local count = GetNumRaidMembers()
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
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
        local rowHeight = 25
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
            btn:SetText("Loot Counter")
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
    local updateInterval = 0.5
    local reservesData = {}
    local reservesByItemID = {}
    local pendingItemInfo = {}
    local collapsedBossGroups = {}

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

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
        addon:Debug("DEBUG", "Saving reserves data. Entries: %d", Utils.tableLen(reservesData))
        KRT_SavedReserves = table.deepCopy(reservesData)
        KRT_SavedReserves.reservesByItemID = table.deepCopy(reservesByItemID)
    end

    function module:Load()
        addon:Debug("DEBUG", "Loading reserves. Data exists: %s", tostring(KRT_SavedReserves ~= nil))
        if KRT_SavedReserves then
            reservesData = table.deepCopy(KRT_SavedReserves)
            reservesByItemID = table.deepCopy(KRT_SavedReserves.reservesByItemID or {})
        else
            reservesData = {}
            reservesByItemID = {}
        end
    end

    function module:ResetSaved()
        addon:Debug("DEBUG", "Resetting saved reserves data.")
        KRT_SavedReserves = nil
        wipe(reservesData)
        wipe(reservesByItemID)
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
        addon:Debug("DEBUG", "UpdateUIFrame called with elapsed time: %.2f", elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            addon:Debug("DEBUG", "Periodic check passed for %s", frameName)
            local clearButton = _G[frameName .. "ClearButton"]
            if clearButton then
                local hasData = module:HasData()
                Utils.enableDisable(clearButton, hasData)
                addon:Debug("DEBUG", "ClearButton %s (HasData: %s)", hasData and "enabled" or "disabled", hasData)
            end

            local queryButton = _G[frameName .. "QueryButton"]
            if queryButton then
                local hasData = module:HasData()
                Utils.enableDisable(queryButton, hasData)
                addon:Debug("DEBUG", "QueryButton %s (HasData: %s)", hasData and "enabled" or "disabled", hasData)
            end
        end
    end

    --------------------------------------------------------------------------
    -- Reserve Data Handling
    --------------------------------------------------------------------------

    function module:GetReserve(playerName)
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
        addon:Debug("DEBUG", "Fetching all reserves. Total players with reserves: %d", Utils.tableLen(reservesData))
        return reservesData
    end

    -- Parse imported text
    function module:ParseCSV(csv)
        addon:Debug("DEBUG", "Starting to parse CSV data.")
        wipe(reservesData)
        wipe(reservesByItemID)

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

                -- Clean CSV field
                itemIdStr                                                       = cleanCSVField(itemIdStr)
                source                                                          = cleanCSVField(source)
                playerName                                                      = cleanCSVField(playerName)
                class                                                           = cleanCSVField(class)
                spec                                                            = cleanCSVField(spec)
                note                                                            = cleanCSVField(note)
                plus                                                            = cleanCSVField(plus)

                local itemId                                                    = tonumber(itemIdStr)
                local normalized                                                = playerName and
                    playerName:lower():trim()

                if normalized and itemId then
                    -- Log the player being processed
                    addon:Debug("DEBUG", "Processing player: %s, Item ID: %d", playerName, itemId)
                    reservesData[normalized] = reservesData[normalized] or {
                        original = playerName,
                        reserves = {}
                    }

                    local found = false
                    for _, entry in ipairs(reservesData[normalized].reserves) do
                        if entry.rawID == itemId then
                            entry.quantity = (entry.quantity or 1) + 1
                            found = true
                            addon:Debug("DEBUG", "Updated quantity for player %s, item ID %d. New quantity: %d",
                                playerName, itemId, entry.quantity)
                            break
                        end
                    end

                    if not found then
                        local entry = {
                            rawID    = itemId,
                            itemLink = nil,
                            itemName = nil,
                            itemIcon = nil,
                            quantity = 1,
                            class    = class ~= "" and class or nil,
                            note     = note ~= "" and note or nil,
                            plus     = tonumber(plus) or 0,
                            source   = source ~= "" and source or nil
                        }
                        tinsert(reservesData[normalized].reserves, entry)
                        reservesByItemID[itemId] = reservesByItemID[itemId] or {}
                        tinsert(reservesByItemID[itemId], entry)
                        -- Log new reserve entry added
                        addon:Debug("DEBUG", "Added new reserve entry for player %s, item ID %d", playerName, itemId)
                    end
                end
            end
        end
        -- Log when the CSV parsing is completed
        addon:Debug("DEBUG", "Finished parsing CSV data. Total reserves processed: %d", Utils.tableLen(reservesData))
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
        addon:Debug("DEBUG", "Updating reserve item data for itemId: %d", itemId)
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for _, r in ipairs(player.reserves or {}) do
                    if r.rawID == itemId then
                        r.itemName = itemName
                        r.itemLink = itemLink
                        r.itemIcon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
                        addon:Debug("DEBUG", "Updated reserve data for player: %s, itemId: %d", player.original, itemId)
                    end
                end
            end
        end

        local rows = rowsByItemID[itemId]
        if not rows then return end
        for _, row in ipairs(rows) do
            local icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
            row.icon:SetTexture(icon)

            if row.quantityText then
                if row.quantityText:GetText() and row.quantityText:GetText():match("^%d+x$") then
                    row.quantityText:SetText(row.quantityText:GetText()) -- Preserve format
                end
            end

            local tooltipText = itemLink or itemName or ("Item ID: " .. itemId)
            row.nameText:SetText(tooltipText)

            row.iconBtn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row.iconBtn, "ANCHOR_RIGHT")
                if itemLink then
                    GameTooltip:SetHyperlink(itemLink)
                else
                    GameTooltip:SetText("Item ID: " .. itemId, 1, 1, 1)
                end
                GameTooltip:Show()
            end)
            row.iconBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
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
        addon:Debug("DEBUG", "Refreshing reserve window.")
        if not reserveListFrame or not scrollChild then return end

        -- Hide and clear old rows
        for _, row in ipairs(reserveItemRows) do row:Hide() end
        wipe(reserveItemRows)
        wipe(rowsByItemID)

        -- Group reserves by item source, ID, and quantity
        local grouped = {}
        for _, player in pairs(reservesData) do
            for _, r in ipairs(player.reserves or {}) do
                local key = (r.source or "Unknown") .. "||" .. r.rawID .. "||" .. (r.quantity or 1)
                grouped[key] = grouped[key] or {
                    itemId = r.rawID,
                    quantity = r.quantity or 1,
                    itemLink = r.itemLink,
                    itemName = r.itemName,
                    itemIcon = r.itemIcon,
                    source = r.source or "Unknown",
                    players = {}
                }
                tinsert(grouped[key].players, player.original)
            end
        end

        -- Sort the grouped reserves
        local displayList = {}
        for _, data in pairs(grouped) do
            tinsert(displayList, data)
        end
        table.sort(displayList, function(a, b)
            if a.source ~= b.source then return a.source < b.source end
            if a.itemId ~= b.itemId then return a.itemId < b.itemId end
            return a.quantity < b.quantity
        end)

        local rowHeight, yOffset = 34, 0
        local seenSources = {}

        -- Create headers and reserve rows
        for index, entry in ipairs(displayList) do
            local source = entry.source

            -- Log for new source groups
            if not seenSources[source] then
                seenSources[source] = true
                addon:Debug("DEBUG", "New source found: %s", source)
                if collapsedBossGroups[source] == nil then
                    collapsedBossGroups[source] = false
                end

                local headerBtn = CreateFrame("Button", nil, scrollChild)
                headerBtn:SetSize(320, 28)
                headerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

                local fullLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fullLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
                fullLabel:SetTextColor(1, 0.82, 0)
                local prefix = collapsedBossGroups[source] and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or
                    "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
                fullLabel:SetText(prefix .. source)
                fullLabel:SetPoint("CENTER", headerBtn, "CENTER", 0, 0)

                local leftLine = headerBtn:CreateTexture(nil, "ARTWORK")
                leftLine:SetTexture("Interface\\Buttons\\WHITE8x8")
                leftLine:SetVertexColor(1, 1, 1, 0.3)
                leftLine:SetHeight(1)
                leftLine:SetPoint("RIGHT", fullLabel, "LEFT", -6, 0)
                leftLine:SetPoint("LEFT", headerBtn, "LEFT", 4, 0)

                local rightLine = headerBtn:CreateTexture(nil, "ARTWORK")
                rightLine:SetTexture("Interface\\Buttons\\WHITE8x8")
                rightLine:SetVertexColor(1, 1, 1, 0.3)
                rightLine:SetHeight(1)
                rightLine:SetPoint("LEFT", fullLabel, "RIGHT", 6, 0)
                rightLine:SetPoint("RIGHT", headerBtn, "RIGHT", -4, 0)

                -- Click toggle
                headerBtn:SetScript("OnClick", function()
                    collapsedBossGroups[source] = not collapsedBossGroups[source]
                    addon:Debug("DEBUG", "Toggling collapse state for source: %s to %s", source,
                        tostring(collapsedBossGroups[source]))
                    module:RefreshWindow()
                end)

                tinsert(reserveItemRows, headerBtn)
                yOffset = yOffset + 24
            end

            -- Log for rows that are added
            if not collapsedBossGroups[source] then
                addon:Debug("DEBUG", "Adding row for itemId: %d, source: %s", entry.itemId, source)
                local row = module:CreateReserveRow(scrollChild, entry, yOffset, index)
                tinsert(reserveItemRows, row)
                yOffset = yOffset + rowHeight
            end
        end

        -- Update the scrollable area
        scrollChild:SetHeight(yOffset)
        scrollFrame:SetVerticalScroll(0)
    end

    -- Create a new row for displaying a reserve
    function module:CreateReserveRow(parent, info, yOffset, index)
        addon:Debug("DEBUG", "Creating reserve row for itemId: %d", info.itemId)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(320, 34)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        row._rawID = info.itemId

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(index % 2 == 0 and 0.1 or 0, 0.1, 0.1, 0.3)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)

        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetAllPoints(icon)

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
        nameText:SetText(info.itemLink or info.itemName or ("[Item " .. info.itemId .. "]"))

        local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        playerText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        playerText:SetText(table.concat(info.players or {}, ", "))

        local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        quantityText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
        quantityText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        quantityText:SetTextColor(1, 1, 1)

        if info.quantity and info.quantity > 1 then
            quantityText:SetText(info.quantity .. "x")
            quantityText:Show()
        else
            quantityText:Hide()
        end

        icon:SetTexture(info.itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

        iconBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(iconBtn, "ANCHOR_RIGHT")
            if info.itemLink then
                GameTooltip:SetHyperlink(info.itemLink)
            else
                GameTooltip:SetText("Item ID: " .. info.itemId, 1, 1, 1)
            end
            if info.source then
                GameTooltip:AddLine("Dropped by: " .. info.source, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)

        iconBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row.icon = icon
        row.iconBtn = iconBtn
        row.nameText = nameText
        row.quantityText = quantityText

        row:Show()
        rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
        tinsert(rowsByItemID[info.itemId], row)

        return row
    end

    --------------------------------------------------------------------------
    -- SR Announcement Formatting
    --------------------------------------------------------------------------

    function module:GetPlayersForItem(itemId)
        addon:Debug("DEBUG", "Getting players for itemId: %d", itemId)
        local players = {}
        -- Loop through each player and their reserves
        for _, player in pairs(reservesData or {}) do
            for _, r in ipairs(player.reserves or {}) do
                if r.rawID == itemId then
                    local qty = r.quantity or 1
                    local display = qty > 1 and ("(" .. qty .. "x)" .. player.original) or player.original
                    tinsert(players, display)
                    -- Log when a player is added for an item
                    addon:Debug("DEBUG", "Added player %s with quantity %d for itemId %d", player.original, qty, itemId)
                    break
                end
            end
        end
        addon:Debug("DEBUG", "Returning %d players for itemId %d", #players, itemId)
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

    -- Frame update
    local UpdateUIFrame
    local updateInterval = 0.1

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
        for k, v in pairs(defaultOptions) do
            KRT_Options[k] = v
        end
        addon:info("Default options have been restored.")
    end

    --
    -- Loads addon options from saved variables, filling in defaults.
    --
    local function LoadOptions()
        addon.options = KRT_Options
        Utils.fillTable(addon.options, defaultOptions)

        -- Ensure dependent options are consistent
        if not addon.options.useRaidWarning then
            addon.options.countdownSimpleRaidMsg = false
        end

        if addon.options.debug and addon.SetLogLevel and addon.Logger and addon.Logger.logLevels then
            addon:SetLogLevel(addon.Logger.logLevels.DEBUG)
        elseif addon.SetLogLevel then
            addon:SetLogLevel(KRT_Debug.level)
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
        Utils.toggle(UIConfig)
    end

    --
    -- Hides the configuration frame.
    --
    function module:Hide()
        if UIConfig and UIConfig:IsShown() then
            UIConfig:Hide()
        end
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
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
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
            end
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
    local updateInterval = 0.1

    local FetchWarnings
    local fetched = false

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    local selectedID, tempSelectedID

    local tempName, tempContent
    local SaveWarning
    local isEdit = false

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UIWarnings = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Externally update frame:
    function module:Update()
        return FetchWarnings()
    end

    -- Toggle frame visibility:
    function module:Toggle()
        Utils.toggle(UIWarnings)
    end

    -- Hide frame:
    function module:Hide()
        if UIWarnings and UIWarnings:IsShown() then
            UIWarnings:Hide()
        end
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
        FetchWarnings()
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

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            if fetched == false then FetchWarnings() end
            if #KRT_Warnings > 0 then
                for i = 1, #KRT_Warnings do
                    if selectedID == i and _G[frameName .. "WarningBtn" .. i] then
                        _G[frameName .. "WarningBtn" .. i]:LockHighlight()
                        _G[frameName .. "OutputName"]:SetText(KRT_Warnings[selectedID].name)
                        _G[frameName .. "OutputContent"]:SetText(KRT_Warnings[selectedID].content)
                        _G[frameName .. "OutputContent"]:SetTextColor(1, 1, 1)
                    else
                        _G[frameName .. "WarningBtn" .. i]:UnlockHighlight()
                    end
                end
            end
            if selectedID == nil then
                _G[frameName .. "OutputName"]:SetText(L.StrWarningsHelp)
                _G[frameName .. "OutputContent"]:SetText(L.StrWarningsHelp)
                _G[frameName .. "OutputContent"]:SetTextColor(0.5, 0.5, 0.5)
            end
            tempName    = _G[frameName .. "Name"]:GetText()
            tempContent = _G[frameName .. "Content"]:GetText()
            Utils.enableDisable(_G[frameName .. "EditBtn"], (tempName ~= "" or tempContent ~= "") or selectedID ~= nil)
            Utils.enableDisable(_G[frameName .. "DeleteBtn"], selectedID ~= nil)
            Utils.enableDisable(_G[frameName .. "AnnounceBtn"], selectedID ~= nil)
            Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit,
                (tempName ~= "" or tempContent ~= "") or selectedID == nil)
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
    local updateInterval = 0.1

    local changesTable = {}
    local FetchChanges, SaveChanges, CancelChanges
    local fetched = false
    local selectedID, tempSelectedID
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
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Toggle frame visibility:
    function module:Toggle()
        CancelChanges()
        Utils.toggle(UIChanges)
    end

    -- Hide frame:
    function module:Hide()
        if UIChanges and UIChanges:IsShown() then
            CancelChanges()
            UIChanges:Hide()
        end
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
            FetchChanges()
        end
        local count = Utils.tableLen(changesTable)
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
            if not fetched then
                InitChangesTable()
                FetchChanges()
            end
            local count = Utils.tableLen(changesTable)
            if count > 0 then
                for n, s in pairs(changesTable) do
                    if selectedID == n and _G[frameName .. "PlayerBtn" .. n] then
                        _G[frameName .. "PlayerBtn" .. n]:LockHighlight()
                    elseif _G[frameName .. "PlayerBtn" .. n] ~= nil then
                        _G[frameName .. "PlayerBtn" .. n]:UnlockHighlight()
                    end
                end
            else
                tempSelectedID = nil
                selectedID = nil
            end
            Utils.showHide(_G[frameName .. "Name"], (isEdit or isAdd))
            Utils.showHide(_G[frameName .. "Spec"], (isEdit or isAdd))
            Utils.enableDisable(_G[frameName .. "EditBtn"], (selectedID or isEdit or isAdd))
            Utils.setText(_G[frameName .. "EditBtn"], SAVE, L.BtnEdit, isAdd or (selectedID and isEdit))
            Utils.setText(_G[frameName .. "AddBtn"], ADD, DELETE, (not selectedID and not isEdit and not isAdd))
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
            local r, g, b = addon.Raid:GetClassColor(class)
            name:SetVertexColor(r, g, b)
            _G[btnName .. "Spec"]:SetText(c)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            totalHeight = totalHeight + btn:GetHeight()
        end
        fetched = true
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
    local spamFrame = CreateFrame("Frame")
    local frameName

    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local updateInterval = 0.05

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    local FindAchievement

    local loaded = false

    local name, tankClass, healerClass, meleeClass, rangedClass
    local duration = (KRT_Options and KRT_Options.lfmPeriod) or 60
    local tank = 0
    local healer = 0
    local melee = 0
    local ranged = 0
    local message, output = nil, "LFM"
    local finalOutput = ""
    local length = 0
    local channels = {}

    local ticking = false
    local paused = false
    local tickStart, tickPos = 0, 0

    local ceil = math.ceil

    -- OnLoad frame:
    function module:OnLoad(frame)
        if not frame then return end
        UISpammer = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    -- Toggle frame visibility:
    function module:Toggle()
        Utils.toggle(UISpammer)
    end

    -- Hide frame:
    function module:Hide()
        if UISpammer and UISpammer:IsShown() then
            UISpammer:Hide()
        end
    end

    -- Save edit box:-
    function module:Save(box)
        if not box then return end
        local boxName = box:GetName()
        local target = gsub(boxName, frameName, "")
        if find(target, "Chat") then
            KRT_Spammer.Channels = KRT_Spammer.Channels or {}
            local channel = gsub(target, "Chat", "")
            local checked = (box:GetChecked() == 1)
            local existed = Utils.checkEntry(KRT_Spammer.Channels, channel)
            if checked and not existed then
                tinsert(KRT_Spammer.Channels, channel)
            elseif not checked and existed then
                Utils.removeEntry(KRT_Spammer.Channels, channel)
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
                -- module:Spam()
            end
        end
    end

    -- Stop spamming:
    function module:Stop()
        _G[frameName .. "Tick"]:SetText(duration or 0)
        ticking = false
        paused = false
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
            if c == "Guild" or c == "Yell" then
                Utils.chat(tostring(finalOutput), upper(c), nil, nil, true)
            else
                Utils.chat(tostring(finalOutput), "CHANNEL", nil, c, true)
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
        message, output, finalOutput = nil, "LFM", ""
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

    -- OnUpdate frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        if Utils.throttle(self, frameName, updateInterval, elapsed) then
            if not loaded then
                KRT_Spammer.Duration = KRT_Spammer.Duration or addon.options.lfmPeriod
                for k, v in pairs(KRT_Spammer) do
                    if k == "Channels" then
                        for i, c in ipairs(v) do
                            _G[frameName .. "Chat" .. c]:SetChecked()
                        end
                    elseif _G[frameName .. k] then
                        _G[frameName .. k]:SetText(v)
                    end
                end
                loaded = true
            end

            -- We build the message only if the frame is shown
            if UISpammer:IsShown() then
                channels    = KRT_Spammer.Channels or {}
                name        = _G[frameName .. "Name"]:GetText():trim()
                tank        = tonumber(_G[frameName .. "Tank"]:GetText()) or 0
                tankClass   = _G[frameName .. "TankClass"]:GetText():trim()
                healer      = tonumber(_G[frameName .. "Healer"]:GetText()) or 0
                healerClass = _G[frameName .. "HealerClass"]:GetText():trim()
                melee       = tonumber(_G[frameName .. "Melee"]:GetText()) or 0
                meleeClass  = _G[frameName .. "MeleeClass"]:GetText():trim()
                ranged      = tonumber(_G[frameName .. "Ranged"]:GetText()) or 0
                rangedClass = _G[frameName .. "RangedClass"]:GetText():trim()
                message     = _G[frameName .. "Message"]:GetText():trim()

                local temp  = output
                if string.trim(name) ~= "" then temp = temp .. " " .. name end
                if tank > 0 or healer > 0 or melee > 0 or ranged > 0 then
                    temp = temp .. " - Need"
                    if tank > 0 then
                        temp = temp .. ", " .. tank .. " Tank"
                        if tankClass ~= "" then temp = temp .. " (" .. tankClass .. ")" end
                    end
                    if healer > 0 then
                        temp = temp .. ", " .. healer .. " Healer"
                        if healerClass ~= "" then temp = temp .. " (" .. healerClass .. ")" end
                    end
                    if melee > 0 then
                        temp = temp .. ", " .. melee .. " Melee"
                        if meleeClass ~= "" then temp = temp .. " (" .. meleeClass .. ")" end
                    end
                    if ranged > 0 then
                        temp = temp .. ", " .. ranged .. " Ranged"
                        if rangedClass ~= "" then temp = temp .. " (" .. rangedClass .. ")" end
                    end
                end
                if message ~= "" then
                    temp = temp .. " - " .. FindAchievement(message)
                end

                if temp ~= "LFM" then
                    local total = tank + healer + melee + ranged
                    local max = name:find("25") and 25 or 10
                    temp = temp .. " (" .. max - (total or 0) .. "/" .. max .. ")"

                    _G[frameName .. "Output"]:SetText(temp)
                    length = strlen(temp)
                    _G[frameName .. "Length"]:SetText(length .. "/255")

                    if length <= 0 then
                        _G[frameName .. "Length"]:SetTextColor(0.5, 0.5, 0.5)
                    elseif length <= 255 then
                        _G[frameName .. "Length"]:SetTextColor(0.0, 1.0, 0.0)
                        _G[frameName .. "Message"]:SetMaxLetters(255)
                    else
                        _G[frameName .. "Message"]:SetMaxLetters(strlen(message) - 1)
                        _G[frameName .. "Length"]:SetTextColor(1.0, 0.0, 0.0)
                    end
                else
                    _G[frameName .. "Output"]:SetText(temp)
                end

                -- Set set duration:
                duration = _G[frameName .. "Duration"]:GetText()
                if duration == "" then
                    duration = addon.options.lfmPeriod
                    _G[frameName .. "Duration"]:SetText(duration)
                end
                finalOutput = temp
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

            if ticking then
                if not paused then
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
            end
        end
    end

    function FindAchievement(inp)
        local out = inp:trim()
        if out and out ~= "" and find(out, "%{%d*%}") then
            local b, e = find(out, "%{%d*%}")
            local id = strsub(out, b + 1, e - 1)
            if not id or id == "" or not GetAchievementLink(id) then
                link = "[" .. id .. "]"
            else
                link = GetAchievementLink(id)
            end
            out = strsub(out, 0, b - 1) .. link .. strsub(out, e + 1)
        end
        return out
    end

    -- To spam even if the frame is closed:
    spamFrame:SetScript("OnUpdate", function(self, elapsed)
        if UISpammer then UpdateUIFrame(UISpammer, elapsed) end
    end)
end

-- Lightweight LFM scheduler
do
    local U = addon.Utils
    local S = addon.Spammer
    local running

    local function Send(msg)
        if U.throttleKey("lfm_msg", _G.KRT_Options.chatThrottle or 2.0) then
            SendChatMessage(msg, IsInRaid() and "RAID" or "GUILD")
        end
    end

    local function Tick()
        if not running then return end
        local msg = addon.L.LFM_TEMPLATE or "[KRT] LFM: {raid} {roles} {time}"
        local raidName = GetRealZoneText() or "Raid"
        local text = msg:gsub("{raid}", raidName):gsub("{roles}", "T/H/D"):gsub("{time}", date("%H:%M"))
        Send(text)
        U.scheduleDelay(_G.KRT_Options.lfmPeriod or 45, Tick)
    end

    function S:Init() end

    function S:Start()
        if running then return end
        running = true
        Tick()
        addon.History.Loot:Log("LFM started")
    end

    function S:Stop()
        running = false
        addon.History.Loot:Log("LFM stopped")
    end

    function S:Toggle()
        if running then
            S:Stop()
        else
            S:Start()
        end
    end
end

-- ==================== Tooltips ==================== --
do
    local colors = HIGHLIGHT_FONT_COLOR

    -- Show the tooltip:
    local function ShowTooltip(frame)
        -- Is the anchor manually set?
        if not frame.tooltip_anchor then
            GameTooltip_SetDefaultAnchor(GameTooltip, frame)
        else
            GameTooltip:SetOwner(frame, frame.tooltip_anchor)
        end

        -- Do we have a title?
        if frame.tooltip_title then
            GameTooltip:SetText(frame.tooltip_title)
        end

        -- Do We have a text?
        if frame.tooltip_text then
            if type(frame.tooltip_text) == "string" then
                GameTooltip:AddLine(frame.tooltip_text, colors.r, colors.g, colors.b, true)
            elseif type(frame.tooltip_text) == "table" then
                for _, l in ipairs(frame.tooltip_text) do
                    GameTooltip:AddLine(l, colors.r, colors.g, colors.b, true)
                end
            end
        end

        -- Do we have an item tooltip?
        if frame.tooltip_item then
            GameTooltip:SetHyperlink(frame.tooltip_item)
        end

        GameTooltip:Show()
    end

    -- Hides the tooltip:
    local function HideTooltip()
        GameTooltip:Hide()
    end

    -- Sets addon tooltips scripts:
    function addon:SetTooltip(frame, text, anchor, title)
        -- No frame no blame...
        if not frame then return end
        -- Prepare the text
        frame.tooltip_text = text and text or frame.tooltip_text
        frame.tooltip_anchor = anchor and anchor or frame.tooltip_anchor
        frame.tooltip_title = title and title or frame.tooltip_title
        -- No title or text? nothing to do...
        if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then return end
        frame:SetScript("OnEnter", ShowTooltip)
        frame:SetScript("OnLeave", HideTooltip)
    end
end

-- ============================================================================
-- Helper locali per liste History (ottimizzato)
-- ============================================================================
local MakeListController

-- Local alias
local _G          = _G
local CreateFrame = CreateFrame
local wipe        = table.wipe
local math_max    = math.max

-- toggle campo selezionato + evento
local function selectAndTrigger(ns, field, id, event)
    ns[field] = (id ~= ns[field]) and id or nil
    Utils.triggerEvent(event, id)
    return ns[field]
end

-- popup di conferma compatto
local function makeConfirmPopup(key, text, onAccept, cancels)
    StaticPopupDialogs[key] = {
        text         = text,
        button1      = L.BtnOK,
        button2      = CANCEL,
        OnAccept     = onAccept,
        cancels      = cancels or key,
        timeout      = 0,
        whileDead    = 1,
        hideOnEscape = 1,
    }
end

-- cache dei child più usati per ridurre _G[...] ripetuti
local function CacheParts(row, name, parts)
    if row._p then return row._p end
    local p = {}
    for i = 1, #parts do
        p[parts[i]] = _G[name .. parts[i]]
    end
    row._p = p
    return p
end

-- Controller liste con pooling righe e highlight differito
local function MakeListController(cfg)
        -- cfg: keyName, updateInterval, localize(frameName), getData()->array
        --      rowName(frameName,item,index)->"PrefixBtn"..index, rowTmpl, drawRow(btnName,item,scrollChild,scrollW)
        --      highlightId()->id|nil, postUpdate(frameName)
        --      sorters = { key = function(a,b,asc) return cond end, ... }
        local self = {
            frameName  = nil,
            fetched    = false,
            localized  = false,
            data       = {},
            _asc       = false,
            _rows      = {},   -- pool ordinato per indice
            _rowByName = {},   -- cache name->frame
            _lastHL    = nil,  -- ultimo id evidenziato
            _active    = true, -- aggiorna solo se visibile
            _lastWidth = nil,
        }

        local function acquireRow(name, parent, tmpl)
            local row = self._rowByName[name]
            if row then
                row:Show()
                return row
            end
            row = CreateFrame("Button", name, parent, tmpl)
            self._rowByName[name] = row
            return row
        end

        local function hideExtraRows(fromIndex)
            for i = fromIndex, #self._rows do
                local r = self._rows[i]
                if r then r:Hide() end
            end
        end

        function self:OnLoad(frame)
            if not frame then return end
            self.frameName = frame:GetName()

            frame:SetScript("OnShow", function() self._active = true end)
            frame:SetScript("OnHide", function() self._active = false end)

            frame:SetScript("OnUpdate", function(f, elapsed) self:UpdateUIFrame(f, elapsed) end)
        end

        function self:UpdateUIFrame(frame, elapsed)
            if not self.frameName or not self._active then return end

            if not self.localized and cfg.localize then
                cfg.localize(self.frameName)
                self.localized = true
            end

            if not Utils.throttle(frame, self.frameName .. (cfg.keyName or ""), cfg.updateInterval, elapsed) then
                return
            end

            if not self.fetched then
                if cfg.getData then cfg.getData(self.data) end
                self:Fetch()
            end

            -- Highlight solo se cambia il selezionato
            if cfg.highlightId then
                local sel = cfg.highlightId()
                if sel ~= self._lastHL then
                    self._lastHL = sel
                    for i = 1, #self.data do
                        local it  = self.data[i]
                        local row = self._rows[i]
                        if row then
                            Utils.toggleHighlight(row, sel ~= nil and it.id == sel)
                        end
                    end
                end
            end

            if cfg.postUpdate then cfg.postUpdate(self.frameName) end
        end

        function self:Fetch()
            local n = self.frameName
            if not n then return end

            local sf = _G[n .. "ScrollFrame"]
            local sc = _G[n .. "ScrollFrameScrollChild"]
            if not (sf and sc) then return end

            local scrollW = sf:GetWidth()
            self._lastWidth = scrollW

            local totalH = 0
            sc:SetHeight(sf:GetHeight())

            local count = #self.data
            for i = 1, count do
                local it      = self.data[i]
                local btnName = cfg.rowName(n, it, i)
                local row     = self._rows[i]

                if not row or row:GetName() ~= btnName then
                    row = acquireRow(btnName, sc, cfg.rowTmpl)
                    self._rows[i] = row
                end

                row:SetID(it.id)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -totalH)
                row:SetWidth(scrollW - 20)

                local rH = cfg.drawRow(btnName, it, sc, scrollW, CacheParts, row)
                local usedH = rH or row:GetHeight() or 20
                totalH = totalH + usedH

                row:Show()
            end

            hideExtraRows(count + 1)
            sc:SetHeight(math_max(totalH, sf:GetHeight()))

            self._lastHL = nil
            self.fetched = true
        end

        function self:Dirty() self.fetched = false end

        function self:Sort(key)
            local cmp = cfg.sorters and cfg.sorters[key]
            if not cmp or #self.data <= 1 then return end
            self._asc = not self._asc
            table.sort(self.data, function(a, b) return cmp(a, b, self._asc) end)
            self.fetched = true
            self:Fetch()
        end

        -- Esponi tool locali
        self._selectAndTrigger = selectAndTrigger
        self._makeConfirmPopup = makeConfirmPopup

        return self
    end

-- ============================================================================
-- Loot History Frame (Main)
-- ============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.History = addon.History or {}
    local module = addon.History
    local L = addon.L

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local frameName, localized, updateInterval = nil, false, 0.05

    module.selectedRaid, module.selectedBoss = nil, nil
    module.selectedPlayer, module.selectedBossPlayer, module.selectedItem = nil, nil, nil

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    function module:OnLoad(frame)
        if not frame then return end
        UIHistory, frameName = frame, frame:GetName() -- UIHistory globale per XML
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", function(self, elapsed)
            if not localized then
                _G[frameName .. "Title"]:SetText(string.format(titleString, L.StrLootHistory))
                localized = true
            end
            if Utils.throttle(self, frameName, updateInterval, elapsed) and module.selectedRaid == nil then
                module.selectedRaid = KRT_CurrentRaid
            end
        end)
        frame:SetScript("OnHide", function()
            module.selectedRaid, module.selectedBoss, module.selectedPlayer, module.selectedItem =
                KRT_CurrentRaid, nil, nil, nil
        end)
    end

    function module:Toggle() Utils.toggle(UIHistory) end

    function module:Hide()
        if not UIHistory then return end
        module.selectedRaid, module.selectedBoss, module.selectedPlayer, module.selectedItem =
            KRT_CurrentRaid, nil, nil, nil
        Utils.showHide(UIHistory, false)
    end

    -- selettori (toggle + evento)
    local function sel(field, id, ev)
        addon.History[field] = (id ~= addon.History[field]) and id or nil
        Utils.triggerEvent(ev, id)
    end
    -- select a raid and notify listeners
    function module:SelectRaid(btn)
        if btn then
            sel("selectedRaid", btn:GetID(), "HistorySelectRaid")
        end
    end

    -- select a boss and notify listeners
    function module:SelectBoss(btn)
        if btn then
            sel("selectedBoss", btn:GetID(), "HistorySelectBoss")
        end
    end

    -- select a player within a boss kill
    function module:SelectBossPlayer(btn)
        if btn then
            sel("selectedBossPlayer", btn:GetID(), "HistorySelectBossPlayer")
        end
    end

    -- select a player and notify listeners
    function module:SelectPlayer(btn)
        if btn then
            sel("selectedPlayer", btn:GetID(), "HistorySelectPlayer")
        end
    end

    do -- Item: sinistro seleziona, destro menu
        local function openItemMenu()
            if not addon.History.selectedItem then return end
            local f = _G.KRTHistoryItemMenuFrame or
                CreateFrame("Frame", "KRTHistoryItemMenuFrame", UIParent, "UIDropDownMenuTemplate")
            EasyMenu({
                {
                    text = L.StrEditItemLooter,
                    func = function()
                        StaticPopup_Show("KRTHISTORY_ITEM_EDIT_WINNER")
                    end
                },
                {
                    text = L.StrEditItemRollType,
                    func = function()
                        StaticPopup_Show("KRTHISTORY_ITEM_EDIT_ROLL")
                    end
                },
                {
                    text = L.StrEditItemRollValue,
                    func = function()
                        StaticPopup_Show("KRTHISTORY_ITEM_EDIT_VALUE")
                    end
                },
            }, f, "cursor", 0, 0, "MENU")
        end
        function module:SelectItem(btn, button)
            if not btn then return end
            if button == "LeftButton" then
                sel("selectedItem", btn:GetID(), "HistorySelectItem")
            elseif button == "RightButton" then
                addon.History.selectedItem = btn:GetID()
                openItemMenu()
            end
        end

        StaticPopupDialogs["KRTHISTORY_ITEM_EDIT_WINNER"] = {
            text = L.StrEditItemLooterHelp,
            button1 = SAVE,
            button2 = CANCEL,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            hasEditBox = 1,
            cancels = "KRTHISTORY_ITEM_EDIT_WINNER",
            OnShow = function(self)
                self.raidId = addon.History.selectedRaid; self.itemId = addon.History.selectedItem
            end,
            OnHide = function(self)
                self.raidId = nil; self.itemId = nil
            end,
            OnAccept = function(self)
                local name = self.editBox:GetText():trim()
                if name ~= "" and self.raidId and KRT_Raids[self.raidId] then
                    for _, p in ipairs(KRT_Raids[self.raidId].players) do
                        if name:lower() == p.name:lower() then
                            addon.History.Loot:Log(self.itemId, p.name); addon.History.Loot:Fetch(); break
                        end
                    end
                end
                self.editBox:SetText(""); self.editBox:ClearFocus(); self:Hide()
            end,
        }
        StaticPopupDialogs["KRTHISTORY_ITEM_EDIT_ROLL"] = {
            text = L.StrEditItemRollTypeHelp,
            button1 = SAVE,
            button2 = CANCEL,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            hasEditBox = 1,
            cancels = "KRTHISTORY_ITEM_EDIT_ROLL",
            OnShow = function(self) self.itemId = addon.History.selectedItem end,
            OnHide = function(self) self.itemId = nil end,
            OnAccept = function(self)
                local rt = self.editBox:GetNumber(); if rt > 0 and rt <= 7 then
                    addon.History.Loot:Log(self.itemId, nil, rt); addon.History.Loot:Fetch()
                end
            end,
        }
        StaticPopupDialogs["KRTHISTORY_ITEM_EDIT_VALUE"] = {
            text = L.StrEditItemRollValueHelp,
            button1 = SAVE,
            button2 = CANCEL,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            hasEditBox = 1,
            cancels = "KRTHISTORY_ITEM_EDIT_VALUE",
            OnShow = function(self) self.itemId = addon.History.selectedItem end,
            OnHide = function(self) self.itemId = nil end,
            OnAccept = function(self)
                local v = self.editBox:GetNumber(); if v ~= nil then
                    addon.History.Loot:Log(self.itemId, nil, nil, v); addon.History.Loot:Fetch()
                end
            end,
        }
    end

    Utils.registerCallback("HistorySelectRaid", function()
        addon.History.selectedBoss, addon.History.selectedPlayer, addon.History.selectedItem = nil, nil, nil
    end)
end

-- ============================================================================
-- module: Raids List
-- ============================================================================
do
    addon.History.Raids = addon.History.Raids or {}
    local Raids = addon.History.Raids

    local controller = MakeListController{
        keyName        = "RaidsList",
        updateInterval = 0.075,

        localize       = function(n)
            if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
                _G[n .. "Title"]:SetText(L.StrRaidsList)
                _G[n .. "HeaderDate"]:SetText(L.StrDate)
                _G[n .. "HeaderSize"]:SetText(L.StrSize)
                _G[n .. "CurrentBtn"]:SetText(L.StrSetCurrent)
                _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            end
            _G[n .. "ExportBtn"]:Disable() -- FIXME
            addon:SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)
        end,

        -- Preformat date una volta sola
        getData        = function(out)
            local count = #KRT_Raids
            for i = 1, count do
                local r = KRT_Raids[i]
                local it = out[i] or Utils.acquireTable()
                it.id      = i
                it.zone    = r.zone
                it.size    = r.size
                it.date    = r.startTime
                it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                out[i] = it
            end
            for i = count + 1, #out do
                Utils.releaseTable(out[i])
                out[i] = nil
            end
        end,

        rowName        = function(n, it, i) return n .. "RaidBtn" .. i end,
        rowTmpl        = "KRTHistoryRaidButton",

        -- Altezza riga costante (cache dal template alla 1a chiamata)
        drawRow        = (function()
            local ROW_H
            local parts = { "ID", "Date", "Zone", "Size" }
            return function(btn, it, sc, w, CacheParts, row)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = CacheParts(row, btn, parts)
                ui.ID:SetText(it.id)
                ui.Date:SetText(it.dateFmt)
                ui.Zone:SetText(it.zone)
                ui.Size:SetText(it.size)
                return ROW_H
            end
        end)(),

        highlightId    = function() return addon.History.selectedRaid end,

        postUpdate     = function(n)
            local sel = addon.History.selectedRaid
            local canSetCurrent = sel and sel ~= KRT_CurrentRaid and not addon.Raid:Expired(sel) and
                addon.Raid:GetRaidSize() == KRT_Raids[sel].size
            Utils.enableDisable(_G[n .. "CurrentBtn"], canSetCurrent)
            Utils.enableDisable(_G[n .. "DeleteBtn"], (sel ~= KRT_CurrentRaid))
        end,

        sorters        = {
            id   = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            date = function(a, b, asc) return asc and (a.date < b.date) or (a.date > b.date) end,
            zone = function(a, b, asc) return asc and (a.zone < b.zone) or (a.zone > b.zone) end,
            size = function(a, b, asc) return asc and (a.size < b.size) or (a.size > b.size) end,
        },
    }

    function Raids:OnLoad(frame) controller:OnLoad(frame) end

    function Raids:Fetch() controller:Fetch() end

    function Raids:Sort(t) controller:Sort(t) end

    function Raids:SetCurrent(btn)
        local sel = addon.History.selectedRaid
        if not (btn and sel and KRT_Raids[sel]) then return end
        if KRT_Raids[sel].size ~= addon.Raid:GetRaidSize() then
            addon:error(L.ErrCannotSetCurrentRaidSize); return
        end
        if addon.Raid:Expired(sel) then
            addon:error(L.ErrCannotSetCurrentRaidReset); return
        end
        KRT_CurrentRaid = sel
    end

    do
        local function DeleteRaid()
            local sel = addon.History.selectedRaid
            if not (sel and KRT_Raids[sel]) then return end
            if KRT_CurrentRaid and KRT_CurrentRaid == sel then
                addon:error(L.ErrCannotDeleteRaid); return
            end
            tremove(KRT_Raids, sel)
            if KRT_CurrentRaid and KRT_CurrentRaid > sel then KRT_CurrentRaid = KRT_CurrentRaid - 1 end
            local n = controller.frameName
            if n and _G[n .. "RaidBtn" .. sel] then _G[n .. "RaidBtn" .. sel]:Hide() end
            addon.History.selectedRaid = nil
            controller:Dirty()
        end
        function Raids:Delete(btn)
            if btn and addon.History.selectedRaid ~= nil then
                StaticPopup_Show("KRTHISTORY_DELETE_RAID")
            end
        end

        (controller._makeConfirmPopup)("KRTHISTORY_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaid)
    end

    Utils.registerCallback("RaidCreate", function(_, num)
        addon.History.selectedRaid = tonumber(num)
        controller:Dirty()
    end)
end

-- ============================================================================
-- module: Boss List
-- ============================================================================
do
    addon.History.Boss = addon.History.Boss or {}
    local Boss = addon.History.Boss

    local controller = MakeListController{
        keyName        = "BossList",
        updateInterval = 0.075,

        localize       = function(n)
            _G[n .. "Title"]:SetText(L.StrBosses)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
        end,

        -- Copia e preformat time (senza toccare i campi usati per sort)
        getData        = function(out)
            local src = addon.Raid:GetBosses(addon.History.selectedRaid) or {}
            for i = 1, #src do
                local b = src[i]
                local it = out[i] or Utils.acquireTable()
                it.id      = b.id
                it.name    = b.name
                it.time    = b.time
                it.mode    = b.mode
                it.timeFmt = date("%H:%M", b.time)
                out[i] = it
            end
            for i = #src + 1, #out do
                Utils.releaseTable(out[i])
                out[i] = nil
            end
            table.sort(out, function(a, b) return a.id > b.id end)
        end,

        rowName        = function(n, it, i) return n .. "BossBtn" .. i end,
        rowTmpl        = "KRTHistoryBossButton",

        drawRow        = (function()
            local ROW_H
            local parts = { "ID", "Name", "Time", "Mode" }
            return function(btn, it, sc, w, CacheParts, row)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = CacheParts(row, btn, parts)
                ui.ID:SetText(it.id)
                ui.Name:SetText(it.name)
                ui.Time:SetText(it.timeFmt)
                ui.Mode:SetText(it.mode)
                return ROW_H
            end
        end)(),

        highlightId    = function() return addon.History.selectedBoss end,

        postUpdate     = function(n)
            local hasRaid = addon.History.selectedRaid
            local hasBoss = addon.History.selectedBoss
            Utils.enableDisable(_G[n .. "AddBtn"], hasRaid)
            Utils.enableDisable(_G[n .. "EditBtn"], hasBoss)
            Utils.enableDisable(_G[n .. "DeleteBtn"], hasBoss)
        end,

        sorters        = {
            id   = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
            mode = function(a, b, asc) return asc and (a.mode < b.mode) or (a.mode > b.mode) end,
        },
    }

    function Boss:OnLoad(frame) controller:OnLoad(frame) end

    function Boss:Fetch() controller:Fetch() end

    function Boss:Sort(t) controller:Sort(t) end

    function Boss:Add() addon.History.BossBox:Toggle() end

    function Boss:Edit() if addon.History.selectedBoss then addon.History.BossBox:Fill() end end

    do
        local function DeleteBoss()
            local rID, bID = addon.History.selectedRaid, addon.History.selectedBoss
            if not (rID and bID) then return end
            local raid = KRT_Raids[rID]; if not (raid and raid.bossKills[bID]) then return end
            tremove(raid.bossKills, bID)
            for i = #raid.loot, 1, -1 do if raid.loot[i].bossNum == bID then tremove(raid.loot, i) end end
            controller:Dirty()
        end
        function Boss:Delete() if addon.History.selectedBoss then StaticPopup_Show("KRTHISTORY_DELETE_BOSS") end end

        (controller._makeConfirmPopup)("KRTHISTORY_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBoss)
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
end

-- ============================================================================
-- module: Boss Attendees List
-- ============================================================================
do
    addon.History.BossAttendees = addon.History.BossAttendees or {}
    local M = addon.History.BossAttendees

    local controller = MakeListController{
        keyName        = "BossAttendees",
        updateInterval = 0.075,

        localize       = function(n) _G[n .. "Title"]:SetText(L.StrBossAttendees) end,

        getData        = function(out)
            if not addon.History.selectedBoss then
                for i = #out, 1, -1 do Utils.releaseTable(out[i]); out[i] = nil end
                return
            end
            local src = addon.Raid:GetPlayers(addon.History.selectedRaid, addon.History.selectedBoss) or {}
            for i = 1, #src do
                local p = src[i]
                local it = out[i] or Utils.acquireTable()
                it.id    = p.id
                it.name  = p.name
                it.class = p.class
                out[i] = it
            end
            for i = #src + 1, #out do
                Utils.releaseTable(out[i])
                out[i] = nil
            end
        end,

        rowName        = function(n, it, i) return n .. "PlayerBtn" .. i end,
        rowTmpl        = "KRTHistoryBossAttendeeButton",

        drawRow        = (function()
            local ROW_H
            local parts = { "Name" }
            return function(btn, it, sc, w, CacheParts, row)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = CacheParts(row, btn, parts)
                ui.Name:SetText(it.name)
                local r, g, b = addon.Raid:GetClassColor(it.class)
                ui.Name:SetVertexColor(r, g, b)
                return ROW_H
            end
        end)(),

        highlightId    = function() return addon.History.selectedBossPlayer end,

        postUpdate     = function(n)
            local bSel = addon.History.selectedBoss
            local pSel = addon.History.selectedBossPlayer
            Utils.enableDisable(_G[n .. "AddBtn"], bSel and not pSel)
            Utils.enableDisable(_G[n .. "RemoveBtn"], bSel and pSel)
        end,

        sorters        = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
        },
    }

    -- initialize the attendees controller
    function M:OnLoad(frame)
        controller:OnLoad(frame)
    end

    -- fetch attendees data
    function M:Fetch()
        controller:Fetch()
    end

    -- sort attendees list
    function M:Sort(t)
        controller:Sort(t)
    end

    -- toggle add attendee dialog
    function M:Add()
        addon.History.AttendeesBox:Toggle()
    end

    do
        local function DeleteAttendee()
            local rID = addon.History.selectedRaid
            local bID = addon.History.selectedBoss
            local pID = addon.History.selectedBossPlayer
            if not (rID and bID and pID) then return end
            local raid = KRT_Raids[rID]; if not (raid and raid.bossKills[bID]) then return end
            local name = addon.Raid:GetPlayerName(pID, rID)
            Utils.removeEntry(raid.bossKills[bID].players, name)
            controller:Dirty()
        end
        -- ask for confirmation before deleting an attendee
        function M:Delete()
            if addon.History.selectedBossPlayer then
                StaticPopup_Show("KRTHISTORY_DELETE_ATTENDEE")
            end
        end

        (controller._makeConfirmPopup)("KRTHISTORY_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    local function Reset() controller:Dirty() end
    Utils.registerCallback("HistorySelectRaid", Reset)
    Utils.registerCallback("HistorySelectBoss", Reset)
end

-- ============================================================================
-- module: Raid Attendees List
-- ============================================================================
do
    addon.History.RaidAttendees = addon.History.RaidAttendees or {}
    local M = addon.History.RaidAttendees

    local controller = MakeListController{
        keyName        = "RaidAttendees",
        updateInterval = 0.075,

        localize       = function(n)
            _G[n .. "Title"]:SetText(L.StrRaidAttendees)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            -- FIXME: riattivare quando implementato
            _G[n .. "AddBtn"]:Disable(); _G[n .. "DeleteBtn"]:Disable()
        end,

        -- Preformat join/leave per la UI
        getData        = function(out)
            local src = addon.Raid:GetPlayers(addon.History.selectedRaid) or {}
            for i = 1, #src do
                local p = src[i]
                local it = out[i] or Utils.acquireTable()
                it.id       = p.id
                it.name     = p.name
                it.class    = p.class
                it.join     = p.join
                it.leave    = p.leave
                it.joinFmt  = date("%H:%M", p.join)
                it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
                out[i] = it
            end
            for i = #src + 1, #out do
                Utils.releaseTable(out[i])
                out[i] = nil
            end
        end,

        rowName        = function(n, it, i) return n .. "PlayerBtn" .. i end,
        rowTmpl        = "KRTHistoryRaidAttendeeButton",

        drawRow        = (function()
            local ROW_H
            local parts = { "Name", "Join", "Leave" }
            return function(btn, it, sc, w, CacheParts, row)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = CacheParts(row, btn, parts)
                ui.Name:SetText(it.name)
                local r, g, b = addon.Raid:GetClassColor(it.class); ui.Name:SetVertexColor(r, g, b)
                ui.Join:SetText(it.joinFmt)
                ui.Leave:SetText(it.leaveFmt)
                return ROW_H
            end
        end)(),

        highlightId    = function() return addon.History.selectedPlayer end,

        sorters        = {
            name  = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            join  = function(a, b, asc) return asc and (a.join < b.join) or (a.join > b.join) end,
            leave = function(a, b, asc)
                local A = a.leave or (asc and math.huge or -math.huge)
                local B = b.leave or (asc and math.huge or -math.huge)
                return asc and (A < B) or (A > B)
            end,
        },
    }

    function M:OnLoad(frame) controller:OnLoad(frame) end

    function M:Fetch() controller:Fetch() end

    function M:Sort(t) controller:Sort(t) end

    do
        local function DeleteAttendee()
            local rID, pID = addon.History.selectedRaid, addon.History.selectedPlayer
            if not (rID and pID) then return end
            local raid = KRT_Raids[rID]; if not (raid and raid.players[pID]) then return end
            local name = raid.players[pID].name
            tremove(raid.players, pID)
            for _, boss in ipairs(raid.bossKills) do Utils.removeEntry(boss.players, name) end
            for i = #raid.loot, 1, -1 do if raid.loot[i].looter == name then tremove(raid.loot, i) end end
            controller:Dirty()
        end
        function M:Delete()
            if addon.History.selectedPlayer then
                StaticPopup_Show("KRTHISTORY_DELETE_RAIDATTENDEE")
            end
        end

        (controller._makeConfirmPopup)("KRTHISTORY_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallback("HistorySelectRaid", function() controller:Dirty() end)
end

-- ============================================================================
-- module: Loot List
-- ============================================================================
do
    addon.History.Loot = addon.History.Loot or {}
    local module = addon.History.Loot

    local raidLoot = {} -- cache per tooltip OnEnter (lista completa del raid)

    local controller = MakeListController{
        keyName        = "LootList",
        updateInterval = 0.075,

        localize       = function(n)
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
            -- FIXME: disabilitati finché non implementati
            _G[n .. "ExportBtn"]:Disable(); _G[n .. "ClearBtn"]:Disable(); _G[n .. "AddBtn"]:Disable(); _G
                [n .. "EditBtn"]:Disable()
        end,

        -- Preformat time per la UI (mantieni i campi numerici per sort/logica)
        getData        = function(out)
            raidLoot = addon.Raid:GetLoot(addon.History.selectedRaid) or {}

            local pID = addon.History.selectedPlayer
            local data
            if pID then
                data = addon.Raid:GetPlayerLoot(pID, addon.History.selectedRaid, addon.History.selectedBoss) or {}
            else
                data = addon.Raid:GetLoot(addon.History.selectedRaid, addon.History.selectedBoss) or {}
            end

            for i = 1, #data do
                local v = data[i]
                local it = out[i] or Utils.acquireTable()
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
                out[i] = it
            end
            for i = #data + 1, #out do
                Utils.releaseTable(out[i])
                out[i] = nil
            end
        end,

        rowName        = function(n, it, i) return n .. "ItemBtn" .. i end,
        rowTmpl        = "KRTHistoryLootButton",

        drawRow        = (function()
            local ROW_H
            local parts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" }
            return function(btn, v, sc, w, CacheParts, row)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = CacheParts(row, btn, parts)

                ui.Name:SetText(Utils.wrapTextInColorCode(v.itemName, itemColors[v.itemRarity + 1]))
                ui.Source:SetText(addon.History.Boss:GetName(v.bossNum, addon.History.selectedRaid))

                local r, g, b = addon.Raid:GetClassColor(addon.Raid:GetPlayerClass(v.looter))
                ui.Winner:SetText(v.looter); ui.Winner:SetVertexColor(r, g, b)

                ui.Type:SetText(lootTypesColored[v.rollType] or lootTypesColored[4])
                ui.Roll:SetText(v.rollValue or 0)
                ui.Time:SetText(v.timeFmt)
                ui.ItemIconTexture:SetTexture(v.itemTexture)

                return ROW_H
            end
        end)(),

        highlightId    = function() return addon.History.selectedItem end,

        postUpdate     = function(n)
            Utils.enableDisable(_G[n .. "DeleteBtn"], addon.History.selectedItem)
        end,

        sorters        = {
            id     = function(a, b, asc) return asc and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
            source = function(a, b, asc) return asc and (a.bossNum < b.bossNum) or (a.bossNum > b.bossNum) end,
            winner = function(a, b, asc) return asc and (a.looter < b.looter) or (a.looter > b.looter) end,
            type   = function(a, b, asc) return asc and (a.rollType < b.rollType) or (a.rollType > b.rollType) end,
            roll   = function(a, b, asc)
                local A = a.rollValue or 0; local B = b.rollValue or 0; return asc and (A < B) or (A > B)
            end,
            time   = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
        },
    }

    function module:OnLoad(frame) controller:OnLoad(frame) end

    function module:Fetch() controller:Fetch() end

    function module:Sort(t) controller:Sort(t) end

    function module:OnEnter(btn)
        if not btn then return end
        local id = btn:GetParent():GetID()
        if not raidLoot[id] then return end
        GameTooltip:SetOwner(btn, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(raidLoot[id].itemLink)
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
        function module:Delete() if addon.History.selectedItem then StaticPopup_Show("KRTHISTORY_DELETE_ITEM") end end

        (controller._makeConfirmPopup)("KRTHISTORY_DELETE_ITEM", L.StrConfirmDeleteItem, DeleteItem)
    end

    function module:Log(itemID, looter, rollType, rollValue)
        local raidID = addon.History and addon.History.selectedRaid or KRT_CurrentRaid
        if not raidID or not KRT_Raids[raidID] then return end
        local it = KRT_Raids[raidID].loot[itemID]; if not it then return end
        if looter and looter ~= "" then it.looter = looter end
        if tonumber(rollType) then it.rollType = tonumber(rollType) end
        if tonumber(rollValue) then it.rollValue = tonumber(rollValue) end
        controller:Dirty()
    end

    local function Reset() controller:Dirty() end
    Utils.registerCallback("HistorySelectRaid", Reset)
    Utils.registerCallback("HistorySelectBoss", Reset)
    Utils.registerCallback("HistorySelectPlayer", Reset)
end

-- ============================================================================
-- module: Add/Edit Boss Popup
-- ============================================================================
do
    addon.History.BossBox = addon.History.BossBox or {}
    local Box = addon.History.BossBox

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}
    local updateInterval = 0.1

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", function(_, elapsed) self:UpdateUIFrame(_, elapsed) end)
        frame:SetScript("OnHide", function() self:CancelAddEdit() end)
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Hide()
        local f = _G[frameName]; if f and f:IsShown() then f:Hide() end
    end

    function Box:Fill()
        local rID, bID = addon.History.selectedRaid, addon.History.selectedBoss
        if not (rID and bID) then return end
        raidData = KRT_Raids[rID]; if not raidData then return end
        bossData = raidData.bossKills[bID]; if not bossData then return end

        _G[frameName .. "Name"]:SetText(bossData.name)
        local d = date("*t", bossData.date)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        _G[frameName .. "Time"]:SetText(string.format("%02d:%02d", tempDate.hour, tempDate.min))
        _G[frameName .. "Difficulty"]:SetText((bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n")

        isEdit = true
        self:Toggle()
    end

    function Box:Save()
        local rID = addon.History.selectedRaid; if not rID then return end
        local name  = _G[frameName .. "Name"]:GetText():trim()
        local diff  = string.lower(_G[frameName .. "Difficulty"]:GetText():trim())
        local bTime = _G[frameName .. "Time"]:GetText():trim()

        name        = (name == "") and "_TrashMob_" or name
        if name ~= "_TrashMob_" and (diff ~= "h" and diff ~= "n") then
            addon:error(L.ErrBossDifficulty); return
        end

        local h, m = bTime:match("(%d+):(%d+)"); h, m = tonumber(h), tonumber(m)
        if not (h and m) then
            addon:error(L.ErrBossTime); return
        end

        local difficulty = (KRT_Raids[rID].size == 10) and 1 or 2
        if diff == "h" then difficulty = difficulty + 2 end

        local _, month, day, year = CalendarGetDate()
        local killDate = { day = day, month = month, year = year, hour = h, min = m }

        if isEdit and bossData then
            bossData.name, bossData.date, bossData.difficulty = name, time(killDate), difficulty
        else
            tinsert(KRT_Raids[rID].bossKills,
                { name = name, date = time(killDate), difficulty = difficulty, players = {} })
        end

        self:Hide()
        Utils.triggerEvent("HistorySelectRaid")
    end

    function Box:CancelAddEdit()
        _G[frameName .. "Name"]:SetText("")
        _G[frameName .. "Difficulty"]:SetText("")
        _G[frameName .. "Time"]:SetText("")
        isEdit, raidData, bossData = false, {}, {}
        table.wipe(tempDate)
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
-- module: Add Attendee Popup
-- ============================================================================
do
    addon.History.AttendeesBox = addon.History.AttendeesBox or {}
    local Box = addon.History.AttendeesBox

    local frameName

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnShow", function()
            local e = _G[frameName .. "Name"]; e:SetText(""); e:SetFocus()
        end)
        frame:SetScript("OnHide", function()
            local e = _G[frameName .. "Name"]; e:SetText(""); e:ClearFocus()
        end)
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Save()
        local name = _G[frameName .. "Name"]:GetText():trim()
        if name == "" then
            addon:error(L.ErrAttendeesInvalidName); return
        end

        local rID, bID = addon.History.selectedRaid, addon.History.selectedBoss
        if not (rID and bID and KRT_Raids[rID]) then
            addon:error(L.ErrAttendeesInvalidRaidBoss); return
        end

        local bossKill = KRT_Raids[rID].bossKills[bID]
        for _, n in ipairs(bossKill.players) do
            if n:lower() == name:lower() then
                addon:error(L.ErrAttendeesPlayerExists); return
            end
        end

        for _, p in ipairs(KRT_Raids[rID].players) do
            if name:lower() == p.name:lower() then
                addon:info(L.StrAttendeesAddSuccess)
                tinsert(bossKill.players, p.name)
                self:Toggle()
                addon.History.BossAttendees:Fetch()
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
    -- Valid subcommands for each feature
    local cmdAchiev   = { "ach", "achi", "achiev", "achievement" }
    local cmdLFM      = { "pug", "lfm", "group", "grouper" }
    local cmdConfig   = { "config", "conf", "options", "opt" }
    local cmdChanges  = { "ms", "changes", "mschanges" }
    local cmdWarnings = { "warning", "warnings", "warn", "rw" }
    local cmdHistory  = { "history", "log", "logger" }
    local cmdDebug    = { "debug", "dbg", "debugger" }
    local cmdLoot     = { "loot", "ml", "master" }
    local cmdReserves = { "res", "reserves", "reserve" }
    local cmdChat     = { "chat", "throttle", "chatthrottle" }
    local cmdMinimap  = { "minimap", "mm" }

    local helpString  = "|caaf49141%s|r: %s"

    local function HandleSlashCmd(cmd)
        if not cmd or cmd == "" then return end

        if cmd == "show" or cmd == "toggle" then
            addon.Master:Toggle()
            return
        end

        local cmd1, cmd2, cmd3 = strsplit(" ", cmd, 3)

        -- ==== Debug ====
        if Utils.checkEntry(cmdDebug, cmd1) then
            local subCmd = cmd2 and cmd2:lower()

            if subCmd == "level" or subCmd == "lvl" then
                if not cmd3 then
                    local lvl = addon.GetLogLevel and addon:GetLogLevel()
                    local name
                    for k, v in pairs(addon.logLevels or {}) do
                        if v == lvl then
                            name = k
                            break
                        end
                    end
                    addon:info("Current log level: %s", name or tostring(lvl))
                else
                    local lv = tonumber(cmd3)
                    if not lv and addon.logLevels then
                        lv = addon.logLevels[cmd3:upper()]
                    end
                    if lv then
                        addon:SetLogLevel(lv)
                        KRT_Debug.level = lv
                        addon:info("Log level set to [%s]", cmd3)
                    else
                        addon:warn("Unknown log level: %s", cmd3)
                    end
                end
            else
                if subCmd == "on" then
                    addon.options.debug = true
                elseif subCmd == "off" then
                    addon.options.debug = false
                else
                    addon.options.debug = not addon.options.debug
                end
                if addon.options.debug and addon.Logger and addon.Logger.logLevels then
                    addon:SetLogLevel(addon.Logger.logLevels.DEBUG)
                    addon:info(L.MsgDebugOn)
                else
                    addon:SetLogLevel(KRT_Debug.level)
                    addon:info(L.MsgDebugOff)
                end
            end

            -- ==== Chat Throttle ====
        elseif Utils.checkEntry(cmdChat, cmd1) then
            local val = tonumber(cmd2)
            if val then
                addon.options.chatThrottle = val
                addon:info(L.MsgChatThrottleSet, val)
            else
                addon:info(L.MsgChatThrottleSet, addon.options.chatThrottle)
            end

            -- ==== Minimap ====
        elseif Utils.checkEntry(cmdMinimap, cmd1) then
            local sub = cmd2 and cmd2:lower()
            if sub == "on" then
                addon.options.minimapButton = true
                if KRT_MINIMAP_GUI then KRT_MINIMAP_GUI:Show() end
            elseif sub == "off" then
                addon.options.minimapButton = false
                if KRT_MINIMAP_GUI then KRT_MINIMAP_GUI:Hide() end
            elseif sub == "pos" and cmd3 then
                local angle = tonumber(cmd3)
                if angle then
                    addon.Minimap:SetPos(angle)
                    addon:info(L.MsgMinimapPosSet, angle)
                end
            elseif sub == "pos" then
                addon:info(L.MsgMinimapPosSet, addon.options.minimapPos)
            else
                addon:info(format(L.StrCmdCommands, "krt minimap"), "KRT")
                print(helpString:format("on", L.StrCmdToggle))
                print(helpString:format("off", L.StrCmdToggle))
                print(helpString:format("pos <deg>", L.StrCmdMinimapPos))
            end

            -- ==== Achievement Link ====
        elseif Utils.checkEntry(cmdAchiev, cmd1) and find(cmd, "achievement:%d*:") then
            local from, to = string.find(cmd, "achievement%:%d*%:")
            local id = string.sub(cmd, from + 12, to - 1)
            from, to = string.find(cmd, "%|cffffff00%|Hachievement%:.*%]%|h%|r")
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
                addon:info(format(L.StrCmdCommands, "krt rw"), "KRT")
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
                addon:info(format(L.StrCmdCommands, "krt ms"), "KRT")
                print(helpString:format("toggle", L.StrCmdToggle))
                print(helpString:format("demand", L.StrCmdChangesDemand))
                print(helpString:format("announce", L.StrCmdChangesAnnounce))
            end

            -- ==== Loot History ====
        elseif Utils.checkEntry(cmdHistory, cmd1) then
            if not cmd2 or cmd2 == "" or cmd2 == "toggle" then
                addon.History:Toggle()
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
                addon:info(format(L.StrCmdCommands, "krt res"), "KRT")
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
            elseif cmd2 == "period" then
                if cmd3 then
                    local v = tonumber(cmd3)
                    if v then
                        addon.options.lfmPeriod = v
                        addon:info(L.MsgLFMPeriodSet, v)
                    end
                else
                    addon:info(L.MsgLFMPeriodSet, addon.options.lfmPeriod)
                end
            else
                addon:info(format(L.StrCmdCommands, "krt pug"), "KRT")
                print(helpString:format("toggle", L.StrCmdToggle))
                print(helpString:format("start", L.StrCmdLFMStart))
                print(helpString:format("stop", L.StrCmdLFMStop))
                print(helpString:format("period", L.StrCmdLFMPeriod))
            end

            -- ==== Help fallback ====
        else
            addon:info(format(L.StrCmdCommands, "krt"), "KRT")
            print(helpString:format("config", L.StrCmdConfig))
            print(helpString:format("lfm", L.StrCmdGrouper))
            print(helpString:format("ach", L.StrCmdAchiev))
            print(helpString:format("changes", L.StrCmdChanges))
            print(helpString:format("warnings", L.StrCmdWarnings))
            print(helpString:format("history", L.StrCmdHistory))
            print(helpString:format("reserves", L.StrCmdReserves))
        end
    end

    -- Register slash commands
    SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
    SlashCmdList["KRT"] = HandleSlashCmd

    SLASH_KRTCOUNTS1 = "/krtcounts"
    SlashCmdList["KRTCOUNTS"] = function()
        addon.Master:ToggleCountsFrame() -- Loot Counter is not yet refactored.
    end
end

---============================================================================
-- Main Event Handlers
---============================================================================

--
-- ADDON_LOADED: Initializes the addon after loading.
--
function addon:ADDON_LOADED(name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    addon.LoadOptions()
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("CHAT_MSG_LOOT")
    self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    self:RegisterEvent("RAID_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("RAID_INSTANCE_WELCOME")
    -- Master Looter Events
    self:RegisterEvent("ITEM_LOCKED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_SLOT_CLEARED")
    self:RegisterEvent("TRADE_ACCEPT_UPDATE")
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
        Utils.schedule(3, function()
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
    module.firstCheckHandle = Utils.schedule(3, module.FirstCheck, module)
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

--
-- ITEM_LOCKED: Forwards item lock events to the Master module.
--
function addon:ITEM_LOCKED(...)
    addon.Master:ITEM_LOCKED(...)
end

--
-- LOOT_OPENED: Forwards loot window opening to the Master module.
--
function addon:LOOT_OPENED(...)
    addon.Master:LOOT_OPENED(...)
end

--
-- LOOT_CLOSED: Forwards loot window closing to the Master module.
--
function addon:LOOT_CLOSED(...)
    addon.Master:LOOT_CLOSED(...)
end

--
-- LOOT_SLOT_CLEARED: Forwards cleared loot slots to the Master module.
--
function addon:LOOT_SLOT_CLEARED(...)
    addon.Master:LOOT_SLOT_CLEARED(...)
end

--
-- TRADE_ACCEPT_UPDATE: Forwards trade acceptance updates to the Master module.
--
function addon:TRADE_ACCEPT_UPDATE(...)
    addon.Master:TRADE_ACCEPT_UPDATE(...)
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
    local _, event, _, _, _, destGUID, destName = ...
    if not KRT_CurrentRaid then return end
    if event == "UNIT_DIED" then
        local npcID = Utils.getNpcId(destGUID)
        if addon.BossIDs.BossIDs[npcID] then
            self.Raid:AddBoss(destName)
        end
    end
end
