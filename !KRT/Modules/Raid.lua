local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local ITEM_LINK_PATTERN = C.ITEM_LINK_PATTERN
local rollTypes = C.rollTypes
addon.State = addon.State or {}
local coreState = addon.State
coreState.loot = coreState.loot or {}
local lootState = coreState.loot

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
