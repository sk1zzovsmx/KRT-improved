--[[
    Features/Raid.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local Core = feature.Core

local tContains = feature.tContains

local ITEM_LINK_PATTERN = feature.ITEM_LINK_PATTERN
local rollTypes = feature.rollTypes

local lootState = feature.lootState

local tinsert, twipe = table.insert, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select
local strlen = string.len
local strmatch = string.match

local tostring, tonumber = tostring, tonumber
local UnitRace, UnitSex = UnitRace, UnitSex

-- =========== Raid Helpers Module  =========== --
-- Manages raid state, roster, boss kills, and loot logging.
do
    addon.Raid              = addon.Raid or {}
    local module            = addon.Raid
    -- ----- Internal state ----- --
    local numRaid           = 0
    local rosterVersion     = 0
    local GetLootMethod     = GetLootMethod
    local GetRaidRosterInfo = GetRaidRosterInfo
    local UnitIsUnit        = UnitIsUnit
    local liveUnitsByName   = {}
    local liveNamesByUnit   = {}
    local pendingUnits      = {}

    local UNKNOWN_OBJECT = UNKNOWNOBJECT
    local UNKNOWN_BEING = UKNOWNBEING
    local RETRY_DELAY_SECONDS = 1
    local RETRY_MAX_ATTEMPTS = 5

    -- ----- Private helpers ----- --
    local function IsUnknownName(name)
        return (not name) or name == "" or name == UNKNOWN_OBJECT or name == UNKNOWN_BEING
    end

    local function ResetLiveUnitCaches()
        twipe(liveUnitsByName)
        twipe(liveNamesByUnit)
    end

    local function ResetPendingUnitRetry()
        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = nil
        twipe(pendingUnits)
    end

    local function MarkPendingUnit(unitID)
        local tries = tonumber(pendingUnits[unitID]) or 0
        if tries < RETRY_MAX_ATTEMPTS then
            pendingUnits[unitID] = tries + 1
        end
    end

    local function TrimPendingUnits(maxRaidSize)
        for unitID in pairs(pendingUnits) do
            local idx = tonumber(strmatch(unitID, "^raid(%d+)$")) or 0
            if idx <= 0 or idx > maxRaidSize then
                pendingUnits[unitID] = nil
            end
        end
    end

    local function HasRetryablePendingUnits()
        for _, tries in pairs(pendingUnits) do
            if (tonumber(tries) or 0) < RETRY_MAX_ATTEMPTS then
                return true
            end
        end
        return false
    end

    local function SchedulePendingUnitRetry()
        if not HasRetryablePendingUnits() then
            return
        end

        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = addon.NewTimer(RETRY_DELAY_SECONDS, function()
            module.pendingUnitRetryHandle = nil
            if not addon.IsInRaid() then return end
            addon:RAID_ROSTER_UPDATE(true)
        end)
    end

    local function FinalizeRosterDelta(delta)
        if #delta.joined == 0 then delta.joined = nil end
        if #delta.updated == 0 then delta.updated = nil end
        if #delta.left == 0 then delta.left = nil end
        if #delta.unresolved == 0 then delta.unresolved = nil end
        if delta.joined or delta.updated or delta.left or delta.unresolved then
            return delta
        end
        return nil
    end

    -- ----- Public methods ----- --
    -- ----- Logger Functions ----- --

    function module:GetRosterVersion()
        return rosterVersion
    end

    -- Updates the current raid roster, adding new players and marking those who left.
    -- Returns rosterChanged, delta where delta contains joined/updated/left/unresolved lists.
    function module:UpdateRaidRoster()
        if not KRT_CurrentRaid then
            ResetPendingUnitRetry()
            ResetLiveUnitCaches()
            return false
        end
        -- Cancel any pending roster update timer and clear the handle
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil

        local rosterChanged = false
        local delta = {
            joined = {},
            updated = {},
            left = {},
            unresolved = {},
        }

        if not addon.IsInRaid() then
            rosterChanged = true
            numRaid = 0
            addon:debug(Diag.D.LogRaidLeftGroupEndSession)
            ResetPendingUnitRetry()
            ResetLiveUnitCaches()
            module:End()
            if rosterChanged then
                rosterVersion = rosterVersion + 1
            end
            if rosterChanged and addon.Master and addon.Master.PrepareDropDowns then
                addon.Master:PrepareDropDowns()
            end
            return rosterChanged
        end

        local raid = Core.ensureRaidById(KRT_CurrentRaid)
        if not raid then return false end

        local realm = Utils.getRealmName()
        KRT_Players[realm] = KRT_Players[realm] or {}
        local playersByName = raid._playersByName

        local prevNumRaid = numRaid
        local n = GetNumRaidMembers()

        -- Keep internal state consistent immediately
        numRaid = n
        if n ~= prevNumRaid then
            rosterChanged = true
        end

        if n == 0 then
            rosterChanged = true
            ResetPendingUnitRetry()
            ResetLiveUnitCaches()
            module:End()
            rosterVersion = rosterVersion + 1
            if addon.Master and addon.Master.PrepareDropDowns then
                addon.Master:PrepareDropDowns()
            end
            return rosterChanged
        end

        local prevUnitsByName = liveUnitsByName
        local prevNamesByUnit = liveNamesByUnit
        local nextUnitsByName = {}
        local nextNamesByUnit = {}
        local seen = {}
        local now = Utils.getCurrentTime()
        local hasUnknownUnits = false

        for i = 1, n do
            local unitID = "raid" .. tostring(i)
            local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
            if IsUnknownName(name) then
                hasUnknownUnits = true
                MarkPendingUnit(unitID)
                local prevName = prevNamesByUnit[unitID]
                if prevName and not nextUnitsByName[prevName] then
                    seen[prevName] = true
                    nextUnitsByName[prevName] = unitID
                    nextNamesByUnit[unitID] = prevName
                end
                tinsert(delta.unresolved, { unitID = unitID, name = prevName })
            else
                pendingUnits[unitID] = nil
                nextUnitsByName[name] = unitID
                nextNamesByUnit[unitID] = name

                local raceL, race = UnitRace(unitID)
                local oldUnitID = prevUnitsByName[name]
                local prevPlayer = playersByName[name]
                local active = prevPlayer and prevPlayer.leave == nil
                local player = prevPlayer

                if not active then
                    rosterChanged = true
                    local newRank = rank or (prevPlayer and prevPlayer.rank) or 0
                    local newSubgroup = subgroup or (prevPlayer and prevPlayer.subgroup) or 1
                    local newClass = class or (prevPlayer and prevPlayer.class) or "UNKNOWN"
                    player = {
                        playerNid = prevPlayer and prevPlayer.playerNid or nil,
                        name     = name,
                        rank     = newRank,
                        subgroup = newSubgroup,
                        class    = newClass,
                        join     = now,
                        leave    = nil,
                        count    = (prevPlayer and prevPlayer.count) or 0,
                    }
                    tinsert(delta.joined, {
                        name = name,
                        unitID = unitID,
                        rank = newRank,
                        subgroup = newSubgroup,
                        class = newClass,
                    })
                else
                    local oldRank = player.rank or 0
                    local oldSubgroup = player.subgroup or 1
                    local oldClass = player.class or "UNKNOWN"
                    local newRank = rank or oldRank
                    local newSubgroup = subgroup or oldSubgroup
                    local newClass = class or oldClass
                    local fieldChanged = (oldRank ~= newRank)
                        or (oldSubgroup ~= newSubgroup)
                        or (oldClass ~= newClass)
                    local unitChanged = oldUnitID and (oldUnitID ~= unitID)

                    if fieldChanged or unitChanged then
                        rosterChanged = true
                        tinsert(delta.updated, {
                            name = name,
                            oldUnitID = oldUnitID,
                            unitID = unitID,
                            oldRank = oldRank,
                            rank = newRank,
                            oldSubgroup = oldSubgroup,
                            subgroup = newSubgroup,
                            oldClass = oldClass,
                            class = newClass,
                        })
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
                    -- Profile metadata changed only; this should not force full roster consumers to refresh.
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

        TrimPendingUnits(n)
        liveUnitsByName = nextUnitsByName
        liveNamesByUnit = nextNamesByUnit

        -- Mark leavers
        for pname, p in pairs(playersByName) do
            if p.leave == nil and not seen[pname] then
                p.leave = now
                rosterChanged = true
                tinsert(delta.left, {
                    name = pname,
                    unitID = prevUnitsByName[pname],
                    rank = p.rank or 0,
                    subgroup = p.subgroup or 1,
                    class = p.class or "UNKNOWN",
                })
            end
        end

        if hasUnknownUnits then
            SchedulePendingUnitRetry()
        else
            ResetPendingUnitRetry()
        end

        delta = FinalizeRosterDelta(delta)

        if rosterChanged then
            rosterVersion = rosterVersion + 1
            addon:debug(Diag.D.LogRaidRosterUpdate:format(rosterVersion, n))
            if addon.Master and addon.Master.PrepareDropDowns then
                addon.Master:PrepareDropDowns()
            end
        end
        return rosterChanged, delta
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

        local raidInfo = Core.createRaidRecord({
            realm = realm,
            zone = zoneName,
            size = raidSize,
            difficulty = tonumber(instanceDiff) or nil,
            startTime = currentTime,
        })

        for i = 1, num do
            local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
            if name then
                local unitID = "raid" .. tostring(i)
                local raceL, race = UnitRace(unitID)

                local p = {
                    playerNid = raidInfo.nextPlayerNid,
                    name     = name,
                    rank     = rank or 0,
                    subgroup = subgroup or 1,
                    class    = class or "UNKNOWN",
                    join     = Utils.getCurrentTime(),
                    leave    = nil,
                    count    = 0,
                }
                raidInfo.nextPlayerNid = (tonumber(raidInfo.nextPlayerNid) or 1) + 1

                tinsert(raidInfo.players, p)

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
        ResetPendingUnitRetry()
        ResetLiveUnitCaches()

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
    -- NOTE: Fresh SavedVariables only. Schema is normalized by Core.ensureRaidSchema().

    function module:EnsureStableIds(raidNum)
        local raid = Core.ensureRaidById(raidNum)
        if not raid then return end
        Core.ensureRaidSchema(raid)
    end

    function module:GetBossByNid(bossNid, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid or bossNid == nil then return nil end
        Core.ensureRaidSchema(raid)

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
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid or lootNid == nil then return nil end
        Core.ensureRaidSchema(raid)

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
        addon.CancelTimer(module.pendingUnitRetryHandle, true)
        module.pendingUnitRetryHandle = nil
        twipe(pendingUnits)
        ResetLiveUnitCaches()
        if not KRT_CurrentRaid then return end
        -- Stop any pending roster update when ending the raid
        addon.CancelTimer(module.updateRosterHandle, true)
        module.updateRosterHandle = nil
        local currentTime = Utils.getCurrentTime()
        local raid = Core.ensureRaidById(KRT_CurrentRaid)
        if raid then
            local duration = currentTime - (raid.startTime or currentTime)
            addon:info(Diag.I.LogRaidEnded:format(KRT_CurrentRaid or -1, tostring(raid.zone),
                tonumber(raid.size) or -1, raid.bossKills and #raid.bossKills or 0,
                raid.loot and #raid.loot or 0, duration))

            for _, v in pairs(raid.players) do
                if not v.leave then v.leave = currentTime end
            end
            raid.endTime = currentTime
        end
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

        local current = Core.ensureRaidById(KRT_CurrentRaid)
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
        local raid = Core.ensureRaidById(raidNum)
        if not raid then return end
        Core.ensureRaidSchema(raid)

        local players = module:GetPlayers(raidNum)
        local found = false
        local nextPlayerNid = tonumber(raid.nextPlayerNid) or 1

        for i, p in ipairs(players) do
            if t.name == p.name then
                -- Preserve count if present
                t.count = t.count or p.count or 0
                t.playerNid = tonumber(t.playerNid) or tonumber(p.playerNid) or nextPlayerNid
                if tonumber(t.playerNid) >= nextPlayerNid then
                    raid.nextPlayerNid = tonumber(t.playerNid) + 1
                end
                raid.players[i] = t
                found = true
                break
            end
        end

        if not found then
            t.count = t.count or 0
            t.playerNid = tonumber(t.playerNid) or nextPlayerNid
            raid.nextPlayerNid = tonumber(t.playerNid) + 1
            tinsert(raid.players, t)
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

        local raid = Core.ensureRaidById(raidNum)
        if not raid then return end
        Core.ensureRaidSchema(raid)

        local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if manDiff then
            instanceDiff = (raid.size == 10) and 1 or 2
            if Utils.normalizeLower(manDiff, true) == "h" then instanceDiff = instanceDiff + 2 end
        elseif isDyn then
            instanceDiff = instanceDiff + (2 * dynDiff)
        end

        local players = {}
        for unit in addon.UnitIterator(true) do
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

        local raid = Core.ensureRaidById(KRT_CurrentRaid)
        if not raid then return end
        Core.ensureRaidSchema(raid)
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

    local function findRaidPlayerByNid(raid, playerNid)
        local nid = tonumber(playerNid)
        if not nid or nid <= 0 then
            return nil
        end

        local players = raid and raid.players or {}
        for i = #players, 1, -1 do
            local p = players[i]
            if p and tonumber(p.playerNid) == nid then
                return p
            end
        end
        return nil
    end

    function module:GetPlayerCountByNid(playerNid, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid then return 0 end
        Core.ensureRaidSchema(raid)

        local player = findRaidPlayerByNid(raid, playerNid)
        if not player then return 0 end
        return tonumber(player.count) or 0
    end

    function module:SetPlayerCountByNid(playerNid, value, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid then return end
        Core.ensureRaidSchema(raid)

        local player = findRaidPlayerByNid(raid, playerNid)
        if not player then return end

        value = tonumber(value) or 0
        -- Hard clamp: counts are always non-negative.
        if value < 0 then value = 0 end

        local old = tonumber(player.count) or 0
        player.count = value

        if old ~= value then
            Utils.triggerEvent("PlayerCountChanged", player.name, value, old, raidNum)
        end
    end

    function module:AddPlayerCountByNid(playerNid, delta, raidNum)
        raidNum = raidNum or KRT_CurrentRaid
        if not raidNum then return end

        delta = tonumber(delta) or 0
        if delta == 0 then return end

        local current = module:GetPlayerCountByNid(playerNid, raidNum) or 0
        local nextVal = current + delta
        if nextVal < 0 then nextVal = 0 end

        module:SetPlayerCountByNid(playerNid, nextVal, raidNum)
    end

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
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then
            module:AddPlayer({
                name     = name,
                rank     = 0,
                subgroup = 1,
                class    = "UNKNOWN",
                join     = Utils.getCurrentTime(),
                leave    = nil,
                count    = 0,
            }, raidNum)
            playerNid = module:GetPlayerID(name, raidNum)
        end

        if playerNid == 0 then
            return
        end

        module:AddPlayerCountByNid(playerNid, delta, raidNum)
    end

    function module:GetPlayerCount(name, raidNum)
        if not name then return 0 end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then return 0 end
        return module:GetPlayerCountByNid(playerNid, raidNum)
    end

    function module:SetPlayerCount(name, value, raidNum)
        if not name then return end
        local playerNid = module:GetPlayerID(name, raidNum)
        if playerNid == 0 then return end
        module:SetPlayerCountByNid(playerNid, value, raidNum)
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
        local raid = Core.ensureRaidById(rID)
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
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        bossNid = tonumber(bossNid) or 0
        if not raid then
            return {}
        end
        Core.ensureRaidSchema(raid)

        local loot = raid.loot or {}
        if bossNid <= 0 then
            return loot
        end

        local items = {}
        for _, v in ipairs(loot) do
            if tonumber(v.bossNid) == bossNid then
                tinsert(items, v)
            end
        end
        return items
    end

    -- Retrieves the position of a specific loot item within the raid's loot table.
    function module:GetLootID(itemID, raidNum, holderName)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid then return 0 end

        Core.ensureRaidSchema(raid)

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
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid or not raid.bossKills then return {} end

        Core.ensureRaidSchema(raid)

        local bosses = out or {}
        if out then twipe(bosses) end

        for i = 1, #raid.bossKills do
            local boss = raid.bossKills[i]
            bosses[#bosses + 1] = {
                id   = tonumber(boss.bossNid), -- stable selection id
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
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        if not raid then return {} end

        Core.ensureRaidSchema(raid)

        local raidPlayers = raid.players or {}

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

    -- Returns LootCounter rows from canonical raid data (unique by player name).
    function module:GetLootCounterRows(raidNum, out)
        raidNum = raidNum or KRT_CurrentRaid
        local raid = Core.ensureRaidById(raidNum)
        local rows = out or {}
        if out then twipe(rows) end
        if not raid or not raid.players then
            return rows
        end

        Core.ensureRaidSchema(raid)

        local seenByName = {}
        for i = #raid.players, 1, -1 do
            local p = raid.players[i]
            if p and p.name and not seenByName[p.name] then
                seenByName[p.name] = true
                rows[#rows + 1] = {
                    playerNid = tonumber(p.playerNid),
                    name = p.name,
                    class = p.class,
                    count = tonumber(p.count) or 0,
                }
            end
        end

        table.sort(rows, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        return rows
    end

    -- Checks if a player is in the raid log.
    function module:CheckPlayer(name, raidNum)
        local found = false
        local players = module:GetPlayers(raidNum)
        if players ~= nil then
            name = Utils.normalizeName(name)
            for _, p in ipairs(players) do
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

    -- Returns the player's stable ID (playerNid) from the raid log.
    function module:GetPlayerID(name, raidNum)
        local playerNid = 0
        raidNum = raidNum or KRT_CurrentRaid
        local raid = raidNum and Core.ensureRaidById(raidNum)
        if raid then
            name = name or Utils.getPlayerName()
            local players = raid.players or {}
            for i = #players, 1, -1 do
                local p = players[i]
                if p and p.name == name then
                    playerNid = tonumber(p.playerNid) or 0
                    break
                end
            end
        end
        return playerNid
    end

    -- Gets a player's name by stable ID (playerNid).
    function module:GetPlayerName(id, raidNum)
        local name
        raidNum = raidNum or addon.Logger.selectedRaid or KRT_CurrentRaid
        local raid = raidNum and Core.ensureRaidById(raidNum)
        if raid then
            local qid = tonumber(id) or id
            local players = raid.players or {}
            for i = 1, #players do
                local p = players[i]
                local pid = p and (tonumber(p.playerNid) or p.playerNid)
                if pid == qid then
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
        name = (type(name) == "number") and module:GetPlayerName(name, raidNum) or name
        for _, v in ipairs(loot) do
            if v.looter == name then
                tinsert(items, v)
            end
        end
        return items
    end

    -- Gets a player's rank.
    function module:GetPlayerRank(name, raidNum)
        local raid = raidNum and Core.ensureRaidById(raidNum)
        local players = raid and raid.players or {}
        local rank = 0
        name = name or Utils.getPlayerName() or UnitName("player")
        if #players == 0 then
            if addon.IsInGroup() then
                local unit = module:GetUnitID(name)
                if unit and unit ~= "none" then
                    rank = Utils.getUnitRank(unit) or 0
                end
            end
        else
            for _, p in ipairs(players) do
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
        if not addon.IsInGroup() or not name then
            return "none"
        end

        name = Utils.normalizeName(name)
        local cachedUnit = liveUnitsByName[name]
        if cachedUnit then
            if UnitExists(cachedUnit) and UnitName(cachedUnit) == name then
                return cachedUnit
            end
            liveUnitsByName[name] = nil
            if liveNamesByUnit[cachedUnit] == name then
                liveNamesByUnit[cachedUnit] = nil
            end
        end

        for unit in addon.UnitIterator(true) do
            local unitName = UnitName(unit)
            if unitName then
                unitName = Utils.normalizeName(unitName)
                liveUnitsByName[unitName] = unit
                liveNamesByUnit[unit] = unitName
                if unitName == name then
                    return unit
                end
            end
        end
        return "none"
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
        for i = 1, #players do
            SetRaidTarget("raid" .. tostring(i), 0)
        end
    end
end
