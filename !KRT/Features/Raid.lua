--[[
    Features/Raid.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local C = feature.C

local tContains = feature.tContains

local ITEM_LINK_PATTERN = feature.ITEM_LINK_PATTERN
local rollTypes = feature.rollTypes

local lootState = feature.lootState

local tinsert, twipe = table.insert, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select
local strlen = string.len

local tostring, tonumber = tostring, tonumber
local UnitRace, UnitSex = UnitRace, UnitSex

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

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --
    -- ----- Logger Functions ----- --

    function module:GetRosterVersion()
        return rosterVersion
    end

    -- Updates the current raid roster, adding new players and marking those who left.
    -- Returns true only when roster data actually changed.
    function module:UpdateRaidRoster()
        if not KRT_CurrentRaid then return false end
        -- Cancel any pending roster update timer and clear the handle
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil

        local changed = false

        if not addon.IsInRaid() then
            changed = true
            numRaid = 0
            addon:debug(Diag.D.LogRaidLeftGroupEndSession)
            module:End()
            if changed then
                rosterVersion = rosterVersion + 1
            end
            if changed and addon.Master and addon.Master.PrepareDropDowns then
                addon.Master:PrepareDropDowns()
            end
            return changed
        end

        local raid = KRT_Raids[KRT_CurrentRaid]
        if not raid then return false end

        local realm = Utils.getRealmName()
        KRT_Players[realm] = KRT_Players[realm] or {}

        raid.players = raid.players or {}

        raid.playersByName = raid.playersByName or {}
        local playersByName = raid.playersByName

        local prevNumRaid = numRaid
        local n = GetNumRaidMembers()

        -- Keep internal state consistent immediately
        numRaid = n
        if n ~= prevNumRaid then
            changed = true
        end

        if n == 0 then
            changed = true
            module:End()
            rosterVersion = rosterVersion + 1
            if addon.Master and addon.Master.PrepareDropDowns then
                addon.Master:PrepareDropDowns()
            end
            return changed
        end

        local seen = {}
        local now = Utils.getCurrentTime()

        for i = 1, n do
            local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)

                local player = playersByName[name]
                local active = player and player.leave == nil

                if not active then
                    changed = true
                    player = {
                        name     = name,
                        rank     = rank or 0,
                        subgroup = subgroup or 1,
                        class    = class or "UNKNOWN",
                        join     = now,
                        leave    = nil,
                        count    = (player and player.count) or 0,
                    }
                else
                    local newRank = rank or player.rank or 0
                    local newSubgroup = subgroup or player.subgroup or 1
                    local newClass = class or player.class or "UNKNOWN"

                    if player.rank ~= newRank
                        or player.subgroup ~= newSubgroup
                        or player.class ~= newClass then
                        changed = true
                    end

                    player.rank = newRank
                    player.subgroup = newSubgroup
                    player.class = newClass
                end

                -- IMPORTANT: ensure raid.players stays consistent even if the array was cleared/edited.
                module:AddPlayer(player)

                seen[name] = true

                local known = KRT_Players[realm][name]
                local newLevel = level or 0
                local newClass = class or "UNKNOWN"
                local newSex = UnitSex(unitID) or 0
                if not known
                    or known.level ~= newLevel
                    or known.race ~= race
                    or known.raceL ~= raceL
                    or known.class ~= newClass
                    or known.classL ~= classL
                    or known.sex ~= newSex then
                    changed = true
                end

                -- Keep identity stable to avoid per-update table churn on roster bursts.
                if not known then
                    known = {}
                    KRT_Players[realm][name] = known
                end
                known.name = name
                known.level = newLevel
                known.race = race
                known.raceL = raceL
                known.class = newClass
                known.classL = classL
                known.sex = newSex
            end
        end

        -- Mark leavers
        for pname, p in pairs(playersByName) do
            if p.leave == nil and not seen[pname] then
                p.leave = now
                changed = true
            end
        end

        if changed then
            rosterVersion = rosterVersion + 1
            addon:debug(Diag.D.LogRaidRosterUpdate:format(rosterVersion, n))
            if addon.Master and addon.Master.PrepareDropDowns then
                addon.Master:PrepareDropDowns()
            end
        end
        return changed
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
        -- New session context: force version-gated roster consumers (e.g. Master dropdowns) to rebuild.
        rosterVersion = rosterVersion + 1

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
