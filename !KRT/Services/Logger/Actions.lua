-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Strings = feature.Strings
local Base64 = feature.Base64
local Database = feature.Database
local Services = feature.Services
local LootSourceCandidates = feature.LootSourceCandidates

local tinsert = table.insert
local tremove = table.remove
local ipairs = ipairs
local pairs, type = pairs, type
local tonumber, tostring = tonumber, tostring
local format = string.format
local lower = string.lower
local abs = math.abs
local time = time
local EPIC_ITEM_RARITY = 4
local RAW_QUERY_OPTS = { raw = true }
local ITEM_LINK_RARITIES = {
    ff9d9d9d = 0,
    ffffffff = 1,
    ff1eff00 = 2,
    ff0070dd = 3,
    ffa335ee = 4,
    ffff8000 = 5,
    ffe6cc80 = 6,
    ffe5cc80 = 6,
}

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Logger", "Actions")
local Logger = Services.Logger
local Actions = Logger.Actions
local Store = Logger.Store
local Helpers = Logger.Helpers
local LootSources = feature.LootSources

local commitRaidSelections
local resolveLoggerLootEntry
local applyLoggerLootMutation
local verifyLoggerLootMutation
local trimText
local hasRaidData
local getCurrentRaidNid
local restoreCurrentRaidIndex
local findBossByNid
local findBossByName
local findBossBySourceNpcId
local shouldRebuildLootSource
local resolveLootSource
local findOrCreateStaticSourceBoss
local applyStaticLootSource
local playerExists
local scanRaidHistory

-- ----- Private helpers ----- --

trimText = function(value)
    if Strings.TrimText then
        return Strings.TrimText(value or "")
    end
    return Strings.NormalizeName(value) or ""
end

local function removeFromList(list, value)
    if not (list and value) then
        return
    end
    local i = addon.tIndexOf(list, value)
    while i do
        tremove(list, i)
        i = addon.tIndexOf(list, value)
    end
end

local function hasTableEntries(value)
    if type(value) ~= "table" then
        return false
    end
    return next(value) ~= nil
end

local function countTableEntries(value)
    if type(value) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function getRaidFirstTime(raid)
    local best
    local bosses = raid and raid.bossKills or {}
    for i = 1, #bosses do
        local ts = tonumber(bosses[i] and bosses[i].time)
        if ts and ts > 0 and (not best or ts < best) then
            best = ts
        end
    end
    local lootRows = raid and raid.loot or {}
    for i = 1, #lootRows do
        local ts = tonumber(lootRows[i] and lootRows[i].time)
        if ts and ts > 0 and (not best or ts < best) then
            best = ts
        end
    end
    return best or 0
end

hasRaidData = function(raid)
    if type(raid) ~= "table" then
        return false
    end
    return hasTableEntries(raid.players) or hasTableEntries(raid.bossKills) or hasTableEntries(raid.loot) or hasTableEntries(raid.attendance) or hasTableEntries(raid.changes)
end

local function getLootRarity(loot)
    if type(loot) ~= "table" then
        return nil
    end
    local rarity = tonumber(loot.itemRarity or loot.itemQuality or loot.quality or loot.rarity)
    if rarity then
        return rarity
    end
    local color = type(loot.itemLink) == "string" and loot.itemLink:match("|c(%x%x%x%x%x%x%x%x)|Hitem:") or nil
    if color then
        return ITEM_LINK_RARITIES[lower(color)]
    end
    return nil
end

local function isNonEpicLoot(loot)
    local rarity = getLootRarity(loot)
    return rarity ~= nil and rarity < EPIC_ITEM_RARITY
end

local function removeNonEpicLoot(raid)
    local lootRows = type(raid) == "table" and raid.loot or nil
    if type(lootRows) ~= "table" then
        return 0
    end
    local removed = 0
    for i = #lootRows, 1, -1 do
        if isNonEpicLoot(lootRows[i]) then
            tremove(lootRows, i)
            removed = removed + 1
        end
    end
    return removed
end

local function isRaidWithoutBossEncounter(raid)
    return hasRaidData(raid) and countTableEntries(raid and raid.bossKills) <= 0
end

playerExists = function(raid, playerNid)
    local queryNid = tonumber(playerNid)
    if not (raid and queryNid and queryNid > 0) then
        return false
    end
    local players = raid.players or {}
    for i = 1, #players do
        if tonumber(players[i] and players[i].playerNid) == queryNid then
            return true
        end
    end
    return false
end

getCurrentRaidNid = function(raidStore)
    local currentRaid = Database.GetCurrentRaid and Database.GetCurrentRaid() or nil
    if not currentRaid then
        return nil
    end
    if Database.GetRaidNidById then
        return Database.GetRaidNidById(currentRaid)
    end
    if raidStore and raidStore.GetRaidNidByIndex then
        return raidStore:GetRaidNidByIndex(currentRaid)
    end
    return nil
end

restoreCurrentRaidIndex = function(raidStore, currentRaidNid)
    if not Database.SetCurrentRaid then
        return
    end
    if not currentRaidNid then
        Database.SetCurrentRaid(nil)
        if Database.SetLastBoss then
            Database.SetLastBoss(nil)
        end
        return
    end

    local currentRaidId
    if Database.GetRaidIdByNid then
        currentRaidId = Database.GetRaidIdByNid(currentRaidNid)
    elseif raidStore and raidStore.GetRaidIndexByNid then
        currentRaidId = raidStore:GetRaidIndexByNid(currentRaidNid)
    end
    Database.SetCurrentRaid(currentRaidId)
    if not currentRaidId and Database.SetLastBoss then
        Database.SetLastBoss(nil)
    end
end

local RaidQueries = Database.GetRaidQueries and Database.GetRaidQueries() or nil

local function getRaidQueries()
    if not RaidQueries and Database.GetRaidQueries then
        RaidQueries = Database.GetRaidQueries()
    end
    return RaidQueries
end

findBossByNid = function(raid, bossNid, opts)
    local queries = getRaidQueries()
    if queries and queries.FindBossByNid then
        return queries:FindBossByNid(raid, bossNid, opts)
    end
    return nil
end

findBossByName = function(raid, bossName, opts)
    local queries = getRaidQueries()
    if queries and queries.FindBossByName then
        return queries:FindBossByName(raid, bossName, opts)
    end
    return nil
end

findBossBySourceNpcId = function(raid, sourceNpcId, opts)
    local queries = getRaidQueries()
    if queries and queries.FindBossBySourceNpcId then
        return queries:FindBossBySourceNpcId(raid, sourceNpcId, opts)
    end
    return nil
end

local function findBossBySourceKey(raid, sourceKey, opts)
    local queries = getRaidQueries()
    if queries and queries.FindBossBySourceKey then
        return queries:FindBossBySourceKey(raid, sourceKey, opts)
    end
    return nil
end

shouldRebuildLootSource = function(raid, loot)
    if type(loot) ~= "table" then
        return false
    end

    local boss = findBossByNid(raid, loot.bossNid)
    local sourceName = boss and trimText(boss.name or boss.boss) or ""
    return sourceName == ""
end

resolveLootSource = function(raid, loot)
    local resolver = LootSources
    if type(resolver) ~= "table" or type(resolver.FindSource) ~= "function" then
        return nil
    end

    local itemId = tonumber(loot and loot.itemId)
    if not itemId or itemId <= 0 then
        return nil
    end

    local context = {
        raid = raid and raid.zone or nil,
        zoneName = raid and raid.zone or nil,
        instanceName = raid and raid.zone or nil,
        raidSize = tonumber(raid and raid.size) or 0,
        difficulty = tonumber(raid and raid.difficulty) or 0,
    }
    local source = resolver.FindSource(itemId, context)
    if type(source) ~= "table" or source.reason == "missing" or source.reason == "ambiguous" then
        return nil
    end
    return source
end

findOrCreateStaticSourceBoss = function(raid, raidIndex, source, sourceTime)
    if type(raid) ~= "table" or type(source) ~= "table" then
        return 0, false
    end

    local sourceKind = source.kind
    local sourceNpcId = tonumber(source.npcId) or 0
    local sourceName = trimText(source.npcName)
    if sourceName == "" then
        return 0, false
    end
    if sourceKind ~= "shared" and sourceNpcId <= 0 then
        return 0, false
    end

    local sourceKey = trimText(source.sourceKey)
    local existingBoss = (sourceKind ~= "shared" and findBossBySourceKey(raid, sourceKey)) or findBossBySourceNpcId(raid, sourceNpcId) or findBossByName(raid, sourceName)
    local existingBossNid = tonumber(existingBoss and existingBoss.bossNid) or 0
    if existingBossNid > 0 then
        return existingBossNid, false
    end

    if Database.EnsureRaidSchema then
        Database.EnsureRaidSchema(raid)
    end
    raid.bossKills = raid.bossKills or {}

    local bossNid = tonumber(raid.nextBossNid) or 1
    raid.nextBossNid = bossNid + 1

    local difficulty = tonumber(raid.difficulty) or 0
    local hashPrefix = tonumber(raid.raidNid) or tonumber(raidIndex) or 0
    tinsert(raid.bossKills, {
        bossNid = bossNid,
        name = sourceName,
        sourceNpcId = sourceNpcId,
        sourceKind = sourceKind,
        sourceKey = sourceKind ~= "shared" and sourceKey ~= "" and sourceKey or nil,
        source = "LootSources",
        difficulty = difficulty,
        mode = (difficulty == 3 or difficulty == 4) and "h" or "n",
        players = {},
        time = tonumber(sourceTime) or time(),
        hash = Base64.Encode(tostring(hashPrefix) .. "|" .. sourceName .. "|" .. tostring(bossNid)),
    })
    return bossNid, true
end

applyStaticLootSource = function(loot, source, bossNid)
    local sourceName = trimText(source.npcName)
    loot.bossNid = bossNid
    loot.lootSource = {
        kind = source.kind,
        bossNid = bossNid,
        sourceNpcId = tonumber(source.npcId) or 0,
        sourceName = sourceName,
        sourceKey = trimText(source.sourceKey) ~= "" and trimText(source.sourceKey) or nil,
    }
    if source.kind == "shared" then
        loot.lootSource.sourceName = "Shared"
        loot.lootSource.candidates = LootSourceCandidates.Copy(source.candidates)
    end
end

local function scanRaidPlayers(raid, result)
    local seenNames = {}
    local playersWithLoot = {}
    local lootRows = raid.loot or {}

    for i = 1, #lootRows do
        local looterNid = tonumber(lootRows[i] and lootRows[i].looterNid) or 0
        if looterNid > 0 then
            playersWithLoot[looterNid] = true
        end
    end

    local players = raid.players or {}
    for i = 1, #players do
        local player = players[i]
        local playerNid = tonumber(player and player.playerNid) or 0
        local playerName = trimText(player and player.name)
        if playerNid > 0 and not playersWithLoot[playerNid] then
            result.playersWithoutLoot = result.playersWithoutLoot + 1
        end
        if playerName ~= "" then
            local key = lower(playerName)
            local existing = seenNames[key]
            if existing and existing ~= playerName then
                result.playerNameConflicts = result.playerNameConflicts + 1
            elseif not existing then
                seenNames[key] = playerName
            end
        end
    end
end

local function scanRaidBosses(raid, result)
    local lootByBoss = {}
    local lootRows = raid.loot or {}
    for i = 1, #lootRows do
        local bossNid = tonumber(lootRows[i] and lootRows[i].bossNid) or 0
        if bossNid > 0 then
            lootByBoss[bossNid] = true
        end
    end

    local bosses = raid.bossKills or {}
    for i = 1, #bosses do
        local bossNid = tonumber(bosses[i] and bosses[i].bossNid) or 0
        if bossNid > 0 and not lootByBoss[bossNid] then
            result.bossesWithoutLoot = result.bossesWithoutLoot + 1
        end
    end
end

local function scanRaidLoot(raid, result)
    local lootRows = raid.loot or {}
    for i = 1, #lootRows do
        local loot = lootRows[i]
        if type(loot) == "table" then
            result.lootRows = result.lootRows + 1
            if isNonEpicLoot(loot) then
                result.nonEpicLoot = result.nonEpicLoot + 1
            end
            local bossNid = tonumber(loot.bossNid) or 0
            if bossNid <= 0 then
                result.missingSources = result.missingSources + 1
            elseif not findBossByNid(raid, bossNid, RAW_QUERY_OPTS) then
                result.invalidSources = result.invalidSources + 1
            end

            local looterNid = tonumber(loot.looterNid) or 0
            if looterNid > 0 and not playerExists(raid, looterNid) then
                result.orphanLoot = result.orphanLoot + 1
            end
        end
    end
end

local function scanRaidAttendance(raid, result)
    local attendance = raid.attendance or {}
    for _, row in pairs(attendance) do
        local playerNid = tonumber(row and row.playerNid) or tonumber(row and row.nid) or 0
        if playerNid > 0 and not playerExists(raid, playerNid) then
            result.orphanAttendance = result.orphanAttendance + 1
        end
    end
end

local function countDuplicateRaidCandidates(raids)
    local count = 0
    for i = 1, #raids do
        local left = raids[i]
        if hasRaidData(left) then
            local leftTime = getRaidFirstTime(left)
            for j = i + 1, #raids do
                local right = raids[j]
                if
                    hasRaidData(right)
                    and trimText(left.zone) == trimText(right.zone)
                    and (tonumber(left.size) or 0) == (tonumber(right.size) or 0)
                    and (tonumber(left.difficulty) or 0) == (tonumber(right.difficulty) or 0)
                then
                    local rightTime = getRaidFirstTime(right)
                    if leftTime <= 0 or rightTime <= 0 or abs(leftTime - rightTime) <= 1800 then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

scanRaidHistory = function()
    local requiredMethods = { "GetRawRaids" }
    local raidStore = Database.GetRaidStoreOrNil and Database.GetRaidStoreOrNil("Logger.Actions.GetRaidHistoryScan", requiredMethods) or nil
    local raids = raidStore and raidStore:GetRawRaids() or nil
    local result = {
        raids = 0,
        emptyRaids = 0,
        raidsWithoutBosses = 0,
        lootRows = 0,
        nonEpicLoot = 0,
        missingSources = 0,
        invalidSources = 0,
        orphanLoot = 0,
        orphanAttendance = 0,
        playersWithoutLoot = 0,
        bossesWithoutLoot = 0,
        playerNameConflicts = 0,
        duplicateRaidCandidates = 0,
    }
    if type(raids) ~= "table" then
        return result
    end

    result.raids = #raids
    for i = 1, #raids do
        local raid = raids[i]
        if type(raid) == "table" then
            if not hasRaidData(raid) then
                result.emptyRaids = result.emptyRaids + 1
            end
            if isRaidWithoutBossEncounter(raid) then
                result.raidsWithoutBosses = result.raidsWithoutBosses + 1
            end
            scanRaidPlayers(raid, result)
            scanRaidBosses(raid, result)
            scanRaidLoot(raid, result)
            scanRaidAttendance(raid, result)
        end
    end
    result.duplicateRaidCandidates = countDuplicateRaidCandidates(raids)
    return result
end

-- ----- Public methods ----- --

commitRaidSelections = function(raid, opts)
    if not raid then
        return
    end
    opts = opts or {}

    -- Rebuild canonical raid schema/runtime indexes after in-place mutations.
    Database.EnsureRaidSchema(raid)

    if opts.invalidate ~= false then
        Store._InvalidateIndexes(raid)
    end

    local log = type(opts.selectionState) == "table" and opts.selectionState or nil
    if not log then
        return
    end

    local changedBoss, changedPlayer, changedBossPlayer, changedItem = false, false, false, false

    local function clearBossSelection()
        if log.selectedBoss ~= nil then
            changedBoss = true
        end
        if log.selectedBossPlayer ~= nil then
            changedBossPlayer = true
        end
        if log.selectedItem ~= nil then
            changedItem = true
        end
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

    -- Validate player selections (playerNid).
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
        if log.selectedPlayer and not Store:GetPlayer(raid, log.selectedPlayer) then
            log.selectedPlayer = nil
            changedPlayer = true
        end
        if log.selectedBossPlayer and not Store:GetPlayer(raid, log.selectedBossPlayer) then
            log.selectedBossPlayer = nil
            changedBossPlayer = true
        end
    end

    local triggerSelectionEvent = opts.triggerSelectionEvent
    if type(triggerSelectionEvent) == "function" then
        if changedBoss then
            triggerSelectionEvent(log, "selectedBoss")
        end
        if changedPlayer then
            triggerSelectionEvent(log, "selectedPlayer")
        end
        if changedBossPlayer then
            triggerSelectionEvent(log, "selectedBossPlayer")
        end
        if changedItem then
            triggerSelectionEvent(log, "selectedItem")
        end
    end
end

resolveLoggerLootEntry = function(raidID, lootNid)
    local raid = Store:GetRaid(raidID)
    if not raid then
        addon:error(Diag.E.LogLoggerNoRaidSession:format(tostring(raidID), tostring(lootNid)))
        return nil, nil
    end

    local lootCount = raid.loot and #raid.loot or 0
    local it = Store:GetLoot(raid, lootNid)
    if not it then
        local rawItemMatch, rawItemMatches = Helpers.FindLootByItemId(raid, lootNid)
        if rawItemMatch and addon.error then
            addon:error(Diag.E.LogLoggerLootNidExpected:format(tostring(raidID), tostring(lootNid), tostring(rawItemMatch.itemLink), tonumber(rawItemMatches) or 0))
        end
        addon:error(Diag.E.LogLoggerItemNotFound:format(raidID, tostring(lootNid), lootCount))
        return nil, nil
    end

    return raid, it
end

applyLoggerLootMutation = function(raid, it, raidID, lootNid, looter, rollType, rollValue)
    if not looter or looter == "" then
        addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(lootNid), tostring(it.itemLink)))
    end
    if rollType == nil then
        addon:warn(Diag.W.LogLoggerRollTypeNil:format(raidID, tostring(lootNid), tostring(looter)))
    end

    local currentLooterName = Store._ResolveLootLooterName(raid, it)
    if addon.hasDebug then
        addon:debug(Diag.D.LogLoggerLootBefore:format(raidID, tostring(lootNid), tostring(it.itemLink), tostring(currentLooterName), tostring(it.rollType), tostring(it.rollValue)))
    end
    if currentLooterName and currentLooterName ~= "" and looter and looter ~= "" and currentLooterName ~= looter then
        addon:warn(Diag.W.LogLoggerLootOverwrite:format(raidID, tostring(lootNid), tostring(it.itemLink), tostring(currentLooterName), tostring(looter)))
    end

    local expectedLooterNid
    local expectedRollType
    local expectedRollValue
    if looter and looter ~= "" then
        local looterNid = Store._ResolveLootLooterNid(raid, looter)
        if not looterNid then
            addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(lootNid), tostring(it.itemLink)))
            return false, nil, nil, nil
        end
        it.looterNid = looterNid
        it.looter = nil
        expectedLooterNid = looterNid
    end
    if tonumber(rollType) then
        it.rollType = tonumber(rollType)
        expectedRollType = tonumber(rollType)
    end
    if tonumber(rollValue) then
        it.rollValue = tonumber(rollValue)
        expectedRollValue = tonumber(rollValue)
    end

    return true, expectedLooterNid, expectedRollType, expectedRollValue
end

verifyLoggerLootMutation = function(raidID, lootNid, it, recordedLooterName, expectedLooterNid, expectedRollType, expectedRollValue)
    local ok = true
    if expectedLooterNid and tonumber(it.looterNid) ~= expectedLooterNid then
        ok = false
    end
    if expectedRollType and it.rollType ~= expectedRollType then
        ok = false
    end
    if expectedRollValue and it.rollValue ~= expectedRollValue then
        ok = false
    end
    if not ok then
        addon:error(Diag.E.LogLoggerVerifyFailed:format(raidID, tostring(lootNid), tostring(recordedLooterName), tostring(it.rollType), tostring(it.rollValue)))
        return false
    end

    if addon.hasDebug then
        addon:debug(Diag.D.LogLoggerVerified:format(raidID, tostring(lootNid)))
        if not Database.GetLastBoss() then
            addon:debug(Diag.D.LogLoggerRecordedNoBossContext:format(raidID, tostring(lootNid), tostring(it.itemLink)))
        end
    end
    return true
end

function Actions:SetLootEntry(raidID, lootNid, looter, rollType, rollValue, source)
    if addon.hasTrace then
        addon:trace(
            Diag.D.LogLoggerLootLogAttempt:format(
                tostring(source),
                tostring(raidID),
                tostring(lootNid),
                tostring(looter),
                tostring(rollType),
                tostring(rollValue),
                tostring(Database.GetLastBoss())
            )
        )
    end

    local raid, it = resolveLoggerLootEntry(raidID, lootNid)
    if not raid then
        return false
    end

    local ok, expectedLooterNid, expectedRollType, expectedRollValue = applyLoggerLootMutation(raid, it, raidID, lootNid, looter, rollType, rollValue)
    if not ok then
        return false
    end

    local recordedLooterName = Store._ResolveLootLooterName(raid, it)
    if addon.hasDebug then
        addon:debug(
            Diag.D.LogLoggerLootRecorded:format(
                tostring(source),
                raidID,
                tostring(lootNid),
                tostring(it.itemLink),
                tostring(recordedLooterName),
                tostring(it.rollType),
                tostring(it.rollValue)
            )
        )
    end

    return verifyLoggerLootMutation(raidID, lootNid, it, recordedLooterName, expectedLooterNid, expectedRollType, expectedRollValue)
end

function Actions:ResolveLootEditWinner(raidID, lootNid, rawText)
    local text = trimText(rawText)
    local normalizedName = Strings.NormalizeLower(text)
    if not normalizedName or normalizedName == "" then
        return nil, L.ErrLoggerWinnerEmpty
    end

    local raid = Store:GetRaid(raidID)
    if not raid then
        return nil, L.ErrLoggerInvalidRaid
    end

    local loot = Store:GetLoot(raid, lootNid)
    if not loot then
        return nil, L.ErrLoggerInvalidItem
    end

    local bossKill = (loot.bossNid and raid) and Store:GetBoss(raid, loot.bossNid) or nil
    local winner = Helpers.FindLoggerPlayer(normalizedName, raid, bossKill)
    if not winner then
        return nil, L.ErrLoggerWinnerNotFound:format(text)
    end

    return winner
end

function Actions:DeleteBoss(rID, bossNid, opts)
    local raid = Store:GetRaid(rID)
    if not (raid and bossNid) then
        return 0
    end

    local _, bossIndex = Store:GetBoss(raid, bossNid)
    if not bossIndex then
        return 0
    end

    local removed = 0
    for i = #raid.loot, 1, -1 do
        local l = raid.loot[i]
        if l and tonumber(l.bossNid) == tonumber(bossNid) then
            tremove(raid.loot, i)
            removed = removed + 1
        end
    end

    tremove(raid.bossKills, bossIndex)
    commitRaidSelections(raid, opts)

    if Database.GetCurrentRaid() == rID and tonumber(Database.GetLastBoss()) == tonumber(bossNid) then
        Database.SetLastBoss(nil)
    end

    return removed
end

-- Bulk delete: removes multiple loot entries (by nid) with a single Commit()
-- Returns: number of removed entries
function Actions:DeleteLootMany(rID, lootNids, opts)
    local raid = Store:GetRaid(rID)
    if not (raid and lootNids and raid.loot) then
        return 0
    end

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
        commitRaidSelections(raid, opts)
    end
    return removed
end

function Actions:DeleteBossAttendee(rID, bossNid, playerNid)
    local raid = Store:GetRaid(rID)
    if not (raid and bossNid and playerNid) then
        return false
    end
    local bossKill = Store:GetBoss(raid, bossNid)
    if not (bossKill and bossKill.players and raid.players) then
        return false
    end
    local queryNid = tonumber(playerNid)
    if not queryNid or queryNid <= 0 then
        return false
    end
    removeFromList(bossKill.players, queryNid)
    return true
end

-- Bulk delete: removes multiple raid attendees (by playerNid) with a single Commit()
-- Returns: number of removed attendees
function Actions:DeleteRaidAttendeeMany(rID, playerNids, opts)
    local raid = Store:GetRaid(rID)
    if not (raid and raid.players and playerNids and #playerNids > 0) then
        return 0
    end

    -- Normalize NIDs to indices, then sort descending (indices shift on removal).
    local ids = {}
    local seen = {}
    for i = 1, #playerNids do
        local nid = tonumber(playerNids[i]) or playerNids[i]
        if nid ~= nil then
            local _, idx = Store:GetPlayer(raid, nid)
            if idx and not seen[idx] then
                seen[idx] = true
                tinsert(ids, idx)
            end
        end
    end
    table.sort(ids, function(a, b)
        return a > b
    end)

    -- Collect removed NIDs + remove players from raid.players.
    local removedNids = {}
    local removed = 0
    for i = 1, #ids do
        local idx = ids[i]
        local p = raid.players[idx]
        local playerNid2 = p and tonumber(p.playerNid)
        if playerNid2 and playerNid2 > 0 then
            removedNids[playerNid2] = true
            tremove(raid.players, idx)
            removed = removed + 1
        end
    end

    if removed == 0 then
        return 0
    end

    -- Remove from all boss attendee lists.
    if raid.bossKills then
        for _, boss in ipairs(raid.bossKills) do
            if boss and boss.players then
                for j = #boss.players, 1, -1 do
                    local attendeeNid = tonumber(boss.players[j])
                    if attendeeNid and removedNids[attendeeNid] then
                        tremove(boss.players, j)
                    end
                end
            end
        end
    end

    -- Remove loot won by removed players.
    if raid.loot then
        for j = #raid.loot, 1, -1 do
            local loot = raid.loot[j]
            local looterNid = loot and tonumber(loot.looterNid) or nil
            if looterNid and removedNids[looterNid] then
                tremove(raid.loot, j)
            end
        end
    end

    opts = opts or {}
    opts.clearPlayers = true
    commitRaidSelections(raid, opts)
    return removed
end

function Actions:DeleteRaid(rID)
    local sel = tonumber(rID)
    local raid = sel and Database.EnsureRaidById(sel) or nil
    if not raid then
        return false
    end

    if Database.GetCurrentRaid() and Database.GetCurrentRaid() == sel then
        addon:error(L.ErrCannotDeleteRaid)
        return false
    end

    local raidStore = Database.GetRaidStoreOrNil("Logger.Actions.DeleteRaid", { "DeleteRaid" })
    local removedIdx = sel
    if raidStore then
        local deleted, idx = raidStore:DeleteRaid(raid.raidNid)
        if not deleted then
            return false
        end
        removedIdx = idx or removedIdx
    else
        return false
    end

    if Database.GetCurrentRaid() and Database.GetCurrentRaid() > removedIdx then
        Database.SetCurrentRaid(Database.GetCurrentRaid() - 1)
    end

    return true
end

function Actions:DeleteRaidByNid(raidNid)
    local nid = tonumber(raidNid)
    if not nid then
        return false
    end
    local raid, sel = Database.EnsureRaidByNid(nid)
    if not (raid and sel) then
        return false
    end

    local currentRaidNid = Database.GetRaidNidById(Database.GetCurrentRaid())
    if currentRaidNid and tonumber(currentRaidNid) == nid then
        addon:error(L.ErrCannotDeleteRaid)
        return false
    end

    local raidStore = Database.GetRaidStoreOrNil("Logger.Actions.DeleteRaidByNid", { "DeleteRaid" })
    local removedIdx = sel
    if raidStore then
        local deleted, idx = raidStore:DeleteRaid(nid)
        if not deleted then
            return false
        end
        removedIdx = idx or removedIdx
    else
        return false
    end

    if Database.GetCurrentRaid() and Database.GetCurrentRaid() > removedIdx then
        Database.SetCurrentRaid(Database.GetCurrentRaid() - 1)
    end

    return true
end

function Actions:PurgeRaidHistory()
    local requiredMethods = { "GetRawRaids", "GetAllRaids" }
    local raidStore = Database.GetRaidStoreOrNil and Database.GetRaidStoreOrNil("Logger.Actions.PurgeRaidHistory", requiredMethods) or nil
    local raids = raidStore and raidStore:GetRawRaids() or nil
    local removed = type(raids) == "table" and #raids or 0
    if raids then
        for i = #raids, 1, -1 do
            tremove(raids, i)
        end
        raidStore:GetAllRaids()
    end

    if Database.SetCurrentRaid then
        Database.SetCurrentRaid(nil)
    end
    if Database.SetLastBoss then
        Database.SetLastBoss(nil)
    end

    return {
        removed = removed,
    }
end

function Actions:DeleteEmptyRaids()
    local result = self:RemoveRaidHistoryEntries({
        emptyRaids = true,
    })
    return {
        removed = tonumber(result and result.emptyRaids) or 0,
    }
end

function Actions:RemoveRaidHistoryEntries(options)
    options = (type(options) == "table") and options or {}
    local requiredMethods = { "GetRawRaids", "GetAllRaids" }
    local raidStore = Database.GetRaidStoreOrNil and Database.GetRaidStoreOrNil("Logger.Actions.RemoveRaidHistoryEntries", requiredMethods) or nil
    local raids = raidStore and raidStore:GetRawRaids() or nil
    local result = {
        emptyRaids = 0,
        nonEpicLoot = 0,
        noBossEncounter = 0,
        raidsRemoved = 0,
        lootRemoved = 0,
    }
    if type(raids) ~= "table" then
        return result
    end

    local currentRaidNid = getCurrentRaidNid(raidStore)
    local cleanEmptyRaids = options.emptyRaids == true
    local cleanNonEpicLoot = options.nonEpicLoot == true
    local cleanNoBossEncounter = options.noBossEncounter == true
    for i = #raids, 1, -1 do
        local raid = raids[i]
        if cleanEmptyRaids and not hasRaidData(raid) then
            tremove(raids, i)
            result.emptyRaids = result.emptyRaids + 1
            result.raidsRemoved = result.raidsRemoved + 1
        elseif cleanNoBossEncounter and isRaidWithoutBossEncounter(raid) then
            tremove(raids, i)
            result.noBossEncounter = result.noBossEncounter + 1
            result.raidsRemoved = result.raidsRemoved + 1
        elseif cleanNonEpicLoot then
            local removedLoot = removeNonEpicLoot(raid)
            result.nonEpicLoot = result.nonEpicLoot + removedLoot
            result.lootRemoved = result.lootRemoved + removedLoot
        end
    end

    raidStore:GetAllRaids()
    restoreCurrentRaidIndex(raidStore, currentRaidNid)

    return result
end

function Actions:EnsureLootSources()
    local requiredMethods = { "GetAllRaids" }
    local raidStore = Database.GetRaidStoreOrNil and Database.GetRaidStoreOrNil("Logger.Actions.EnsureLootSources", requiredMethods) or nil
    local raids = raidStore and raidStore:GetAllRaids() or nil
    local result = {
        raids = 0,
        scanned = 0,
        repaired = 0,
        bossesCreated = 0,
        unresolved = 0,
    }
    if type(raids) ~= "table" then
        return result
    end

    for raidIndex = 1, #raids do
        local raid = raids[raidIndex]
        if type(raid) == "table" then
            result.raids = result.raids + 1
            local changed = false
            local lootRows = raid.loot or {}
            for lootIndex = 1, #lootRows do
                local loot = lootRows[lootIndex]
                if type(loot) == "table" then
                    result.scanned = result.scanned + 1
                    if shouldRebuildLootSource(raid, loot) then
                        local source = resolveLootSource(raid, loot)
                        local bossNid, created = findOrCreateStaticSourceBoss(raid, raidIndex, source, loot.time)
                        if bossNid > 0 then
                            applyStaticLootSource(loot, source, bossNid)
                            result.repaired = result.repaired + 1
                            if created then
                                result.bossesCreated = result.bossesCreated + 1
                            end
                            changed = true
                        else
                            result.unresolved = result.unresolved + 1
                        end
                    end
                end
            end
            if changed then
                if Database.EnsureRaidSchema then
                    Database.EnsureRaidSchema(raid)
                end
                Store._InvalidateIndexes(raid)
            end
        end
    end

    return result
end

function Actions:GetRaidHistoryScan()
    return scanRaidHistory()
end

function Actions:SetCurrentRaid(rID)
    local sel = tonumber(rID)
    local raid = sel and Database.EnsureRaidById(sel) or nil
    if not (sel and raid) then
        return false
    end

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
    local groupSize = Services.Raid:GetRaidSize()
    if not raidSize or raidSize ~= groupSize then
        addon:error(L.ErrCannotSetCurrentRaidSize)
        return false
    end

    if Services.Raid:IsRaidExpired(sel) then
        addon:error(L.ErrCannotSetCurrentRaidReset)
        return false
    end

    Database.SetCurrentRaid(sel)
    Database.SetLastBoss(nil)

    -- Sync roster/dropdowns immediately so subsequent logging targets the selected raid.
    Services.Raid:UpdateRaidRoster()

    addon:info(L.LogRaidSetCurrent:format(sel, tostring(raid.zone), raidSize))
    return true
end

-- Upsert boss kill (edit if bossNid provided, otherwise append new boss kill).
-- Returns bossNid on success, nil on failure.
function Actions:UpsertBossKill(rID, bossNid, name, ts, mode, opts)
    local raid = Store:GetRaid(rID)
    if not raid then
        return nil
    end

    name = Strings.TrimText(name or "")
    mode = Strings.NormalizeLower(mode or "n")
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
        opts = opts or {}
        opts.invalidate = false
        commitRaidSelections(raid, opts)
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
        hash = Base64.Encode(rID .. "|" .. name .. "|" .. newNid),
    })

    commitRaidSelections(raid, opts)
    return newNid
end

-- Add existing raid player to the selected boss attendees list.
-- nameRaw is matched (case-insensitive) against raid.players[].name.
function Actions:AddBossAttendee(rID, bossNid, nameRaw, opts)
    local name = Strings.TrimText(nameRaw or "")
    local normalizedName = Strings.NormalizeLower(name)
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
    local playerName, _, player = Store:FindRaidPlayerByNormName(raid, normalizedName)
    local playerNid = tonumber(player and player.playerNid)
    if not (playerName and playerNid and playerNid > 0) then
        addon:error(L.ErrAttendeesInvalidName)
        return false
    end

    for i = 1, #bossKill.players do
        if tonumber(bossKill.players[i]) == playerNid then
            addon:error(L.ErrAttendeesPlayerExists)
            return false
        end
    end

    tinsert(bossKill.players, playerNid)
    addon:info(L.StrAttendeesAddSuccess)
    opts = opts or {}
    opts.invalidate = false
    commitRaidSelections(raid, opts)
    return true
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Logger/Actions", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/Base64",
            "Database/DBRaidQueries",
            "Services/Logger/Store",
            "Services/Logger/Helpers",
        },
    })
    registry.SetLoaded("Services/Logger/Actions")
end
