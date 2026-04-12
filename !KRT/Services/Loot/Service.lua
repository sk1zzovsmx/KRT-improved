-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag

local Events = feature.Events or addon.Events
local C = feature.C
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Item = feature.Item or addon.Item
local Strings = feature.Strings or addon.Strings
local Time = feature.Time or addon.Time
local IgnoredItems = feature.IgnoredItems or addon.IgnoredItems or {}

local Services = feature.Services or addon.Services

local itemColors = feature.itemColors

local InternalEvents = Events.Internal

local lootState = feature.lootState
local itemInfo = feature.itemInfo
local raidState = feature.raidState
local rollTypes = feature.rollTypes

lootState.lootCount = tonumber(lootState.lootCount) or 0
lootState.currentItemIndex = tonumber(lootState.currentItemIndex) or 0
lootState.currentRollType = tonumber(lootState.currentRollType) or lootState.currentRollType
lootState.currentRollItem = tonumber(lootState.currentRollItem) or 0
lootState.selectedItemCount = tonumber(lootState.selectedItemCount) or 1
lootState.pendingAwards = lootState.pendingAwards or {}
if lootState.opened == nil then
    lootState.opened = false
end
if lootState.fromInventory == nil then
    lootState.fromInventory = false
end

local itemExists, itemIsSoulbound, getItem
local getItemName, getItemLink, getItemTexture

local tinsert, twipe = table.insert, table.wipe
local type = type
local strmatch = string.match

local tostring, tonumber = tostring, tonumber
local PENDING_AWARD_TTL_SECONDS = tonumber(C.PENDING_AWARD_TTL_SECONDS) or 8
local GROUP_LOOT_PENDING_AWARD_TTL_SECONDS = tonumber(C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS) or 60
local BOSS_EVENT_CONTEXT_TTL_SECONDS = tonumber(C.BOSS_EVENT_CONTEXT_TTL_SECONDS) or 30

-- =========== Loot Helpers Module  =========== --
-- Manages the loot window items (fetching from loot/inventory).
do
    addon.Services.Loot = addon.Services.Loot or {}
    local module = addon.Services.Loot
    local PendingAwards = assert(module._PendingAwards, "Loot pending-award helpers are not initialized")
    local PassiveGroupLoot = assert(module._PassiveGroupLoot, "Loot passive group-loot helpers are not initialized")
    local Tracking = assert(module._Tracking, "Loot tracking helpers are not initialized")
    local ContextHelpers = assert(module._Context or addon.Core._LootContext, "Loot context helpers are not initialized")
    local resolveRaidRecord = assert(ContextHelpers.ResolveRaidRecord, "Missing LootContext.ResolveRaidRecord")

    -- ----- Internal state ----- --
    local lootTable = {}
    local cacheWarmQueue = {}
    local cacheWarmQueued = {}
    local cacheWarmHead = 1
    local cacheWarmHandle
    local CACHE_WARM_DELAY_SECONDS = 0.05

    -- ----- Private helpers ----- --
    local scheduleCacheWarm

    local function warmItemCacheNow(itemLink)
        local probe = Item or addon.Item
        if probe and probe.WarmItemCache then
            probe.WarmItemCache(itemLink)
        end
    end

    local function resetCacheWarmQueue()
        twipe(cacheWarmQueue)
        twipe(cacheWarmQueued)
        cacheWarmHead = 1
    end

    local function processCacheWarmQueue()
        cacheWarmHandle = nil

        local itemLink = cacheWarmQueue[cacheWarmHead]
        if not itemLink then
            resetCacheWarmQueue()
            return
        end

        cacheWarmQueue[cacheWarmHead] = nil
        cacheWarmHead = cacheWarmHead + 1
        cacheWarmQueued[itemLink] = nil
        warmItemCacheNow(itemLink)

        if cacheWarmQueue[cacheWarmHead] then
            scheduleCacheWarm()
        else
            resetCacheWarmQueue()
        end
    end

    scheduleCacheWarm = function()
        if cacheWarmHandle or type(addon.NewTimer) ~= "function" then
            return
        end
        cacheWarmHandle = addon.NewTimer(CACHE_WARM_DELAY_SECONDS, processCacheWarmQueue)
    end

    local function warmItemCache(itemLink)
        if type(itemLink) ~= "string" or itemLink == "" then
            return
        end
        if cacheWarmQueued[itemLink] then
            return
        end
        if type(addon.NewTimer) ~= "function" then
            warmItemCacheNow(itemLink)
            return
        end

        cacheWarmQueued[itemLink] = true
        cacheWarmQueue[#cacheWarmQueue + 1] = itemLink
        scheduleCacheWarm()
    end

    local function isBagItemSoulbound(bag, slot)
        local probe = Item or addon.Item
        if probe and probe.IsBagItemSoulbound then
            return probe.IsBagItemSoulbound(bag, slot)
        end
        return false
    end

    local function resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        local session = lootState.rollSession
        if type(session) ~= "table" then
            return nil
        end
        local sessionId = session.id
        if not sessionId or sessionId == "" then
            return nil
        end

        local sessionItemId = tonumber(session.itemId)
        local parsedItemId = tonumber(itemId)
        if sessionItemId and parsedItemId and sessionItemId == parsedItemId then
            return tostring(sessionId)
        end

        local sessionKey = session.itemKey
        if sessionKey and itemString and sessionKey == itemString then
            return tostring(sessionId)
        end
        if sessionKey and itemLink and sessionKey == itemLink then
            return tostring(sessionId)
        end
        return nil
    end

    local function bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        local resolvedLootNid = tonumber(lootNid)
        local session = lootState.rollSession
        if not resolvedLootNid or resolvedLootNid <= 0 or type(session) ~= "table" then
            return
        end

        local sessionId = session.id and tostring(session.id) or nil
        local matchedSessionId = rollSessionId and tostring(rollSessionId) or nil
        if not matchedSessionId then
            matchedSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end
        if not sessionId or matchedSessionId ~= sessionId then
            return
        end

        session.lootNid = resolvedLootNid
        lootState.currentRollItem = resolvedLootNid
    end

    local function invalidateRaidRuntime(raid)
        if Core and Core.StripRuntimeRaidCaches then
            Core.StripRuntimeRaidCaches(raid)
            return
        end
        if type(raid) == "table" then
            raid._runtime = nil
        end
    end

    local function getLootItemKey(loot)
        if type(loot) ~= "table" then
            return nil
        end
        if type(loot.itemString) == "string" and loot.itemString ~= "" then
            return loot.itemString
        end
        return PassiveGroupLoot.GetPassiveLootRollItemKey(loot.itemLink)
    end

    local function resolveLootLooterName(raidNum, loot)
        if type(loot) ~= "table" then
            return nil
        end

        local looterNid = tonumber(loot.looterNid)
        if not looterNid or looterNid <= 0 then
            return nil
        end

        local raidService = Services.Raid
        if raidService then
            return raidService:GetPlayerName(looterNid, raidNum)
        end
        return nil
    end

    local function findUpgradeablePassiveLootEntry(raid, raidNum, itemLink, looter, rollSessionId)
        if type(raid) ~= "table" or not itemLink or not looter then
            return nil
        end

        local targetItemKey = PassiveGroupLoot.GetPassiveLootRollItemKey(itemLink)
        local targetLooter = Strings.NormalizeName(looter, true) or looter
        local targetSessionId = rollSessionId and tostring(rollSessionId) or nil
        local currentTime = tonumber(Time.GetCurrentTime()) or 0
        local uniqueMatch = nil
        local sessionlessMatch = nil
        local lootList = raid.loot or {}

        for i = #lootList, 1, -1 do
            local loot = lootList[i]
            local lootTime = tonumber(loot and loot.time) or 0
            if currentTime > 0 and lootTime > 0 and (currentTime - lootTime) > GROUP_LOOT_PENDING_AWARD_TTL_SECONDS then
                break
            end

            if loot and getLootItemKey(loot) == targetItemKey then
                local lootLooter = resolveLootLooterName(raidNum, loot)
                if lootLooter == targetLooter and (tonumber(loot.rollValue) or 0) <= 0 then
                    local lootSessionId = loot.rollSessionId and tostring(loot.rollSessionId) or nil
                    if targetSessionId and targetSessionId ~= "" then
                        if lootSessionId == targetSessionId then
                            return loot
                        end
                        if not lootSessionId or lootSessionId == "" then
                            if sessionlessMatch then
                                sessionlessMatch = false
                            else
                                sessionlessMatch = loot
                            end
                        end
                    else
                        if uniqueMatch then
                            return nil
                        end
                        uniqueMatch = loot
                    end
                end
            end
        end

        if targetSessionId and type(sessionlessMatch) == "table" then
            return sessionlessMatch
        end

        return uniqueMatch
    end

    local function addLootWindowSlot(indexByItemKey, slot)
        if not LootSlotIsItem(slot) then
            return
        end

        local itemLink = GetLootSlotLink(slot)
        if not itemLink or GetItemFamily(itemLink) == 64 then
            return
        end

        local key = Item.GetItemStringFromLink(itemLink) or itemLink
        local existing = indexByItemKey[key]
        if existing then
            lootTable[existing].count = (lootTable[existing].count or 1) + 1
            return
        end

        local icon, name, _, quality = GetLootSlotInfo(slot)
        local before = lootState.lootCount
        module:AddItem(itemLink, 1, name, quality, icon)
        if lootState.lootCount > before then
            indexByItemKey[key] = lootState.lootCount
            local item = lootTable[lootState.lootCount]
            if item then
                item.itemKey = key
            end
        end
    end

    local function findTrackedLootItemIndex(itemLink)
        if not itemLink then
            return nil
        end

        for i = 1, lootState.lootCount do
            local item = lootTable[i]
            if item and item.itemLink == itemLink then
                return i
            end
        end
        return nil
    end

    local function findLootSlotIndex(itemLink)
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        local wantedId = Item.GetItemIdFromLink(itemLink)
        for i = 1, GetNumLootItems() do
            local tempItemLink = GetLootSlotLink(i)
            if tempItemLink == itemLink then
                return i
            end
            if wantedKey and tempItemLink then
                local tempKey = Item.GetItemStringFromLink(tempItemLink) or tempItemLink
                if tempKey == wantedKey then
                    return i
                end
            end
            if wantedId and tempItemLink then
                local tempItemId = Item.GetItemIdFromLink(tempItemLink)
                if tempItemId and tempItemId == wantedId then
                    return i
                end
            end
        end
        return nil
    end

    local function scanTradeableInventory(itemLink, itemId)
        if not itemLink and not itemId then
            return nil
        end

        local wantedKey = itemLink and (Item.GetItemStringFromLink(itemLink) or itemLink) or nil
        local wantedId = tonumber(itemId) or (itemLink and Item.GetItemIdFromLink(itemLink)) or nil
        local totalCount = 0
        local firstBag, firstSlot, firstSlotCount
        local hasMatch = false

        for bag = 0, 4 do
            local n = GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local key = Item.GetItemStringFromLink(link) or link
                    local linkId = Item.GetItemIdFromLink(link)
                    local matches = (wantedKey and key == wantedKey) or (wantedId and linkId == wantedId)
                    if matches then
                        hasMatch = true
                        if not itemIsSoulbound(bag, slot) then
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

    local function resolveTradeableInventoryItem(itemLink, cachedBag, cachedSlot, selectedItemCount)
        local totalCount, bag, slot, slotCount
        local usedFastPath = false
        local wantedKey = Item.GetItemStringFromLink(itemLink) or itemLink
        local wantedId = Item.GetItemIdFromLink(itemLink)

        cachedBag = tonumber(cachedBag)
        cachedSlot = tonumber(cachedSlot)

        if cachedBag and cachedSlot then
            local cachedLink = GetContainerItemLink(cachedBag, cachedSlot)
            if cachedLink then
                local cachedKey = Item.GetItemStringFromLink(cachedLink) or cachedLink
                local cachedId = Item.GetItemIdFromLink(cachedLink)
                local sameItem = (wantedKey and cachedKey == wantedKey) or (wantedId and cachedId == wantedId)
                if sameItem and not itemIsSoulbound(cachedBag, cachedSlot) then
                    local _, count = GetContainerItemInfo(cachedBag, cachedSlot)
                    bag = cachedBag
                    slot = cachedSlot
                    slotCount = tonumber(count) or 1
                    usedFastPath = true
                end
            end
        end

        if not (bag and slot) then
            totalCount, bag, slot, slotCount = scanTradeableInventory(itemLink, wantedId)
        elseif usedFastPath then
            if (tonumber(selectedItemCount) or 1) > 1 then
                totalCount = scanTradeableInventory(itemLink, wantedId)
            else
                totalCount = tonumber(slotCount) or 1
            end
        end

        if not (bag and slot) then
            return nil
        end

        return {
            bag = bag,
            slot = slot,
            slotCount = tonumber(slotCount) or 1,
            totalCount = tonumber(totalCount) or tonumber(slotCount) or 1,
        }
    end

    local function parseLootChatMessage(msg, rollType, rollValue)
        -- Parse loot chat variants ("receives loot" and "receives item").
        local player, itemLink, count = addon.Deformat(msg, LOOT_ITEM_MULTIPLE)
        local itemCount = count or 1

        if not player then
            player, itemLink = addon.Deformat(msg, LOOT_ITEM)
            itemCount = 1
        end

        -- Self loot path (no player name in the string).
        if not itemLink then
            local link
            link, count = addon.Deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
            if link then
                itemLink = link
                itemCount = count or 1
                player = Core.GetPlayerName()
            end
        end

        if not itemLink then
            local link = addon.Deformat(msg, LOOT_ITEM_SELF)
            if link then
                itemLink = link
                itemCount = 1
                player = Core.GetPlayerName()
            end
        end

        -- Fallback for alternate loot-roll chat formats.
        if not player or not itemLink then
            local resolvedRollType, resolvedRollValue
            player, itemLink, resolvedRollType, resolvedRollValue = PassiveGroupLoot.ParseGroupLootWinner(msg)
            if itemLink then
                itemCount = 1
                rollType = rollType or resolvedRollType
                if rollValue == nil then
                    rollValue = resolvedRollValue
                end
            end
        end

        if not itemLink then
            return nil, nil, nil, rollType, rollValue
        end

        return Strings.NormalizeName(player, true) or player, tonumber(itemCount) or 1, itemLink, rollType, rollValue
    end

    local function getLootItemDetails(itemLink)
        local itemString = Item.GetItemStringFromLink(itemLink)
        local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
        local itemId = Item.GetItemIdFromLink(itemLink)
        return itemString, itemName, itemRarity, itemTexture, tonumber(itemId)
    end

    local function shouldSkipLootEntry(itemRarity, itemId, itemLink)
        -- Ignore low-rarity and explicitly ignored items.
        local lootThreshold = GetLootThreshold()
        if itemRarity and itemRarity < lootThreshold then
            addon:debug(Diag.D.LogLootIgnoredBelowThreshold:format(tostring(itemRarity), tonumber(lootThreshold) or -1, tostring(itemLink)))
            return true
        end
        if itemId and module:IsIgnoredItem(itemId) then
            addon:debug(Diag.D.LogLootIgnoredItemId:format(tostring(itemId), tostring(itemLink)))
            return true
        end
        return false
    end

    local function resolveLootRollOutcome(itemLink, itemString, itemId, player, rollType, rollValue)
        local passiveGroupLoot = PassiveGroupLoot.IsPassiveGroupLootMethod()
        local preferredRollSessionId = nil
        if not passiveGroupLoot then
            preferredRollSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end

        local rollSessionId
        local outcome = {
            consumedPendingAward = false,
            matchedPassiveRoll = false,
        }
        local pendingAwardTtl = passiveGroupLoot and GROUP_LOOT_PENDING_AWARD_TTL_SECONDS or PENDING_AWARD_TTL_SECONDS
        -- In ML mode, block stale GL:* pending awards only when the current item
        -- maps to an active roll session. Without a preferred session, keep GL
        -- pending lookup enabled to preserve passive Group Loot logging in mixed
        -- transition windows (Group Loot -> ML).
        local allowGroupLootPendingAwards = passiveGroupLoot or not preferredRollSessionId
        local pendingAward = module:RemovePendingAward(itemLink, player, pendingAwardTtl, preferredRollSessionId, passiveGroupLoot, allowGroupLootPendingAwards)
        if pendingAward then
            if not rollType then
                rollType = pendingAward.rollType
            end
            if rollValue == nil then
                rollValue = pendingAward.rollValue
            elseif passiveGroupLoot then
                local currentRollValue = tonumber(rollValue) or 0
                local pendingRollValue = tonumber(pendingAward.rollValue) or 0
                if currentRollValue <= 0 and pendingRollValue > 0 then
                    rollValue = pendingAward.rollValue
                end
            end
            if rollValue == nil then
                rollValue = pendingAward.rollValue
            end
            rollSessionId = pendingAward.rollSessionId and tostring(pendingAward.rollSessionId) or nil
            outcome.consumedPendingAward = true
        end

        if not rollSessionId then
            if passiveGroupLoot then
                local passiveRoll = PassiveGroupLoot.GetPassiveLootRollEntry(itemLink)
                rollSessionId = passiveRoll and passiveRoll.sessionId or nil
                outcome.matchedPassiveRoll = passiveRoll ~= nil
            else
                rollSessionId = preferredRollSessionId
            end
        end

        -- Resolve award source: pending award/group-loot choice -> manual ML tag -> current roll type.
        if not rollType then
            local raidService = Services.Raid
            local isMasterLooter = raidService and raidService:IsMasterLooter()
            if isMasterLooter and not lootState.fromInventory then
                rollType = rollTypes.MANUAL
                rollValue = 0

                -- Debug marker for manual-tagged loot.
                addon:debug(Diag.D.LogLootTaggedManual, tostring(itemLink), tostring(player), tostring(lootState.currentRollType))
            else
                rollType = lootState.currentRollType
            end
        end

        if not rollSessionId then
            rollSessionId = resolveRollSessionIdForLoot(itemLink, itemString, itemId)
        end

        if not rollValue then
            local services = addon.Services
            local rollsService = services and services.Rolls or nil
            rollValue = rollsService and rollsService:HighestRoll() or 0
        end

        return rollType, rollValue, rollSessionId, outcome
    end

    local function resolveBossNidForLoot(raid, raidNum, rollSessionId, passiveGroupLoot, now)
        local raidService = Services.Raid
        if not raidService then
            return 0
        end
        local ttlSeconds = passiveGroupLoot and GROUP_LOOT_PENDING_AWARD_TTL_SECONDS or BOSS_EVENT_CONTEXT_TTL_SECONDS
        local allowLootWindowContext = lootState.opened == true and lootState.fromInventory ~= true
        return tonumber(raidService:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, {
            now = tonumber(now) or Time.GetCurrentTime(),
            allowContextRecovery = not passiveGroupLoot,
            allowLootWindowContext = allowLootWindowContext,
            allowTrashFallback = true,
            ttlSeconds = ttlSeconds,
        })) or 0
    end

    local function copyLootSourceForRecord(raidService, raidNum, bossNid)
        if not (raidService and raidService.GetActiveLootSource) then
            return nil
        end
        return raidService:GetActiveLootSource(raidNum, bossNid)
    end

    local function buildLootRecord(
        raid,
        itemId,
        itemName,
        itemString,
        itemLink,
        itemRarity,
        itemTexture,
        itemCount,
        looterNid,
        rollType,
        rollValue,
        rollSessionId,
        bossNid,
        lootSource
    )
        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local lootInfo = {
            itemId = itemId,
            itemName = itemName,
            itemString = itemString,
            itemLink = itemLink,
            itemRarity = itemRarity,
            itemTexture = itemTexture,
            itemCount = itemCount,
            looterNid = (looterNid > 0) and looterNid or nil,
            rollType = rollType,
            rollValue = rollValue,
            rollSessionId = rollSessionId,
            lootNid = lootNid,
            bossNid = tonumber(bossNid) or 0,
            time = Time.GetCurrentTime(),
            lootSource = lootSource,
        }

        return lootInfo, lootNid
    end

    -- ----- Public methods ----- --

    -- Structured runtime snapshot for debug/export callers.
    function module:GetTrackingSnapshot(raidNum)
        return Tracking.GetSnapshot(raidNum, lootTable, findLootSlotIndex)
    end

    function module:UpgradeLoggedPassiveLootRoll(itemLink, looter, rollType, rollValue, rollSessionId)
        local resolvedRollValue = tonumber(rollValue) or 0
        local currentRaidId, raid = resolveRaidRecord()
        if resolvedRollValue <= 0 or not currentRaidId then
            return false
        end

        if not raid then
            return false
        end

        local loot = findUpgradeablePassiveLootEntry(raid, currentRaidId, itemLink, looter, rollSessionId)
        if not loot then
            return false
        end

        loot.rollType = rollType or loot.rollType
        loot.rollValue = resolvedRollValue
        if rollSessionId and (not loot.rollSessionId or loot.rollSessionId == "") then
            loot.rollSessionId = tostring(rollSessionId)
        end

        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(loot.lootNid, loot.rollSessionId, loot.itemId, loot.itemString, loot.itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, currentRaidId, loot)
        return true
    end

    function module:IsIgnoredItem(itemId)
        if type(IgnoredItems.Contains) ~= "function" then
            return false
        end
        return IgnoredItems.Contains(itemId)
    end

    -- Adds a loot item to the active raid log.
    function module:AddLoot(msg, rollType, rollValue)
        local player
        local itemCount
        local itemLink
        player, itemCount, itemLink, rollType, rollValue = parseLootChatMessage(msg, rollType, rollValue)
        if not itemLink then
            addon:debug(Diag.D.LogLootParseFailed:format(tostring(msg)))
            return
        end

        local itemString, itemName, itemRarity, itemTexture, itemId = getLootItemDetails(itemLink)
        addon:trace(Diag.D.LogLootParsed:format(tostring(player), tostring(itemLink), itemCount))

        if shouldSkipLootEntry(itemRarity, itemId, itemLink) then
            return
        end
        raidState.lastLootCount = itemCount

        local currentRaidId, raid = resolveRaidRecord()
        if not raid then
            return
        end

        local passiveGroupLoot = PassiveGroupLoot.IsPassiveGroupLootMethod()
        local isPassiveWinnerMessage = PassiveGroupLoot.IsPassiveLootWinnerMessage(msg)
        local rollSessionId
        local rollOutcome
        rollType, rollValue, rollSessionId, rollOutcome = resolveLootRollOutcome(itemLink, itemString, itemId, player, rollType, rollValue)

        if passiveGroupLoot and not (rollOutcome and rollOutcome.consumedPendingAward) then
            local alreadyLogged = PassiveGroupLoot.HasLoggedPassiveLoot(itemLink, player, rollSessionId)
            if alreadyLogged then
                return
            end
        end

        local currentTime = Time.GetCurrentTime()
        local raidService = Services.Raid
        local bossNid = resolveBossNidForLoot(raid, currentRaidId, rollSessionId, passiveGroupLoot, currentTime)
        local lootSource = copyLootSourceForRecord(raidService, currentRaidId, bossNid)
        if bossNid <= 0 then
            addon:debug(Diag.D.LogBossNoContextTrash)
        end

        local looterNid = 0
        if raidService then
            looterNid, player = raidService:EnsureRaidPlayerNid(player, currentRaidId)
        end

        local lootInfo, lootNid =
            buildLootRecord(raid, itemId, itemName, itemString, itemLink, itemRarity, itemTexture, itemCount, looterNid, rollType, rollValue, rollSessionId, bossNid, lootSource)

        -- LootCounter (MS only): increment the winner's count when the loot is actually awarded.
        -- This runs off the authoritative LOOT_ITEM / LOOT_ITEM_MULTIPLE chat event.
        if tonumber(rollType) == rollTypes.MAINSPEC and raidService then
            raidService:AddPlayerCount(player, itemCount, currentRaidId)
        end

        if passiveGroupLoot and isPassiveWinnerMessage then
            PassiveGroupLoot.RememberLoggedPassiveLoot(itemLink, player, rollSessionId)
        end

        tinsert(raid.loot, lootInfo)
        if lootState.opened == true and lootState.fromInventory ~= true and raidService and raidService._ConsumeLootWindowItemContext then
            raidService:_ConsumeLootWindowItemContext(itemLink)
        end
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        PassiveGroupLoot.ConsumePassiveLootRollEntry(rollSessionId)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, currentRaidId, lootInfo)
        addon:debug(Diag.D.LogLootLogged:format(tonumber(currentRaidId) or -1, tostring(itemId), tostring(lootInfo.bossNid), tostring(player)))
    end

    -- Creates a local raid loot entry for inventory-trade awards when no reliable loot context exists.
    function module:LogTradeOnlyLoot(itemLink, looter, rollType, rollValue, itemCount, source, raidNum, bossNid, rollSessionId)
        local resolvedRaidNum, raid = resolveRaidRecord(raidNum)
        raidNum = resolvedRaidNum
        if not raidNum or not itemLink or not looter or looter == "" then
            return 0
        end
        looter = Strings.NormalizeName(looter, true) or looter

        if not raid then
            return 0
        end

        local raidService = Services.Raid
        local looterNid = 0
        if raidService then
            looterNid, looter = raidService:EnsureRaidPlayerNid(looter, raidNum)
        end

        local count = tonumber(itemCount) or 1
        if count < 1 then
            count = 1
        end

        local itemString, itemName, itemRarity, itemTexture, itemId = getLootItemDetails(itemLink)
        if not itemName then
            itemName = strmatch(itemLink, "%[(.-)%]") or tostring(itemLink)
        end

        local lootNid = tonumber(raid.nextLootNid) or 1
        raid.nextLootNid = lootNid + 1

        local currentTime = Time.GetCurrentTime()
        local resolvedBossNid = tonumber(bossNid) or 0
        if resolvedBossNid <= 0 and raidService then
            resolvedBossNid = raidService:FindOrCreateBossNidForLoot(raid, raidNum, rollSessionId, {
                now = currentTime,
                allowContextRecovery = false,
                allowTrashFallback = true,
                ttlSeconds = GROUP_LOOT_PENDING_AWARD_TTL_SECONDS,
            })
        end
        local lootSource = copyLootSourceForRecord(raidService, raidNum, resolvedBossNid)

        local lootInfo = {
            itemId = itemId,
            itemName = itemName,
            itemString = itemString,
            itemLink = itemLink,
            itemRarity = itemRarity,
            itemTexture = itemTexture,
            itemCount = count,
            looterNid = (looterNid > 0) and looterNid or nil,
            rollType = tonumber(rollType),
            rollValue = tonumber(rollValue) or 0,
            rollSessionId = rollSessionId and tostring(rollSessionId) or nil,
            lootNid = lootNid,
            bossNid = resolvedBossNid,
            time = currentTime,
            source = source or "TRADE_ONLY",
            lootSource = lootSource,
        }

        tinsert(raid.loot, lootInfo)
        invalidateRaidRuntime(raid)
        bindLootNidToRollSession(lootNid, rollSessionId, itemId, itemString, itemLink)
        Bus.TriggerEvent(InternalEvents.RaidLootUpdate, raidNum, lootInfo)
        addon:debug(Diag.D.LogLootTradeOnlyLogged:format(tonumber(raidNum) or -1, tostring(itemId), tostring(lootNid), tostring(looter), count, tostring(lootInfo.source)))
        return lootNid
    end

    function module:AddPassiveLootRoll(rollId, rollTime)
        return PassiveGroupLoot.AddPassiveLootRoll(self, rollId, rollTime)
    end

    function module:AddGroupLootMessage(msg)
        return PassiveGroupLoot.AddGroupLootMessage(self, msg)
    end

    -- Pending award helpers (shared with Master/Raid flows).
    function module:AddPendingAward(itemLink, looter, rollType, rollValue, rollSessionId, expiresAt)
        return PendingAwards.Add(itemLink, looter, rollType, rollValue, rollSessionId, expiresAt)
    end

    function module:RemovePendingAward(itemLink, looter, maxAge, rollSessionId, preferResolvedValue, allowGroupLootPendingAwards)
        return PendingAwards.Remove(itemLink, looter, maxAge, rollSessionId, preferResolvedValue, allowGroupLootPendingAwards)
    end

    function module:RefreshPendingAward(itemLink, looter, maxAge, rollSessionId, expiresAt)
        return PendingAwards.Refresh(itemLink, looter, maxAge, rollSessionId, expiresAt)
    end

    function module:PurgePendingAwards(maxAge)
        return PendingAwards.Purge(maxAge)
    end

    -- Fetches items from the currently open loot window.
    function module:FetchLoot()
        local oldItem
        if lootState.lootCount >= 1 then
            oldItem = getItemLink(lootState.currentItemIndex)
        end
        local lootItemCount = GetNumLootItems() or 0
        addon:trace(Diag.D.LogLootFetchStart:format(lootItemCount, lootState.currentItemIndex or 0))
        lootState.opened = true
        lootState.fromInventory = false
        self:ClearLoot()

        local indexByItemKey = {}
        for i = 1, lootItemCount do
            -- In loot window we treat each slot as one awardable copy (even if quantity > 1).
            addLootWindowSlot(indexByItemKey, i)
        end

        lootState.currentItemIndex = findTrackedLootItemIndex(oldItem) or 1
        self:PrepareItem()
        addon:trace(Diag.D.LogLootFetchDone:format(lootState.lootCount or 0, lootState.currentItemIndex or 0))
    end

    -- Adds an item to the loot table.
    -- Note: in 3.3.5a GetItemInfo can be nil for uncached items; we fall back to
    -- loot-slot data and the itemLink itself so Master Loot UI + Spam Loot keep working.
    -- When caller-supplied hints are available (loot window path), skip the blocking
    -- GetItemInfo call and warm the cache asynchronously to avoid micro-freezes.
    function module:AddItem(itemLink, itemCount, nameHint, rarityHint, textureHint, colorHint)
        local itemName, itemRarity, itemTexture
        local hasHints = nameHint and rarityHint and textureHint

        if hasHints then
            -- Loot-window path: slot data is already available, avoid blocking query.
            itemName = nameHint
            itemRarity = rarityHint
            itemTexture = textureHint
            -- Warm the item cache so subsequent GetItemInfo calls (tooltip, export)
            -- will resolve instantly without blocking the main thread.
            if type(itemLink) == "string" then
                warmItemCache(itemLink)
            end
        else
            -- Non-loot-window path (inventory, manual add): call GetItemInfo directly.
            local giiName, _, giiRarity, _, _, _, _, _, _, giiTexture = GetItemInfo(itemLink)
            itemName = giiName
            itemRarity = giiRarity
            itemTexture = giiTexture

            if (not itemName or not itemRarity or not itemTexture) and type(itemLink) == "string" then
                warmItemCache(itemLink)
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
            if rarity < lootThreshold then
                return
            end
            lootState.lootCount = lootState.lootCount + 1
        else
            lootState.lootCount = 1
            lootState.currentItemIndex = 1
        end
        lootTable[lootState.lootCount] = {}
        lootTable[lootState.lootCount].itemName = itemName
        lootTable[lootState.lootCount].itemColor = itemColor
        lootTable[lootState.lootCount].itemLink = itemLink
        lootTable[lootState.lootCount].itemTexture = itemTexture
        lootTable[lootState.lootCount].count = itemCount or 1
    end

    -- Prepares the currently selected item for display.
    function module:PrepareItem()
        if itemExists(lootState.currentItemIndex) then
            self:SetItem(lootTable[lootState.currentItemIndex])
        end
    end

    -- Sets the main item display in the UI.
    function module:SetItem(i)
        if not i then
            Bus.TriggerEvent(InternalEvents.SetItem, nil, nil)
            return
        end
        if not (i.itemName and i.itemLink and i.itemTexture and i.itemColor) then
            return
        end
        Bus.TriggerEvent(InternalEvents.SetItem, i.itemLink, i)
    end

    -- Selects an item from the loot list by its index.
    function module:SelectItem(i)
        if itemExists(i) then
            lootState.currentItemIndex = i
            self:PrepareItem()
        end
    end

    -- Clears all loot from the table and resets the UI display.
    function module:ClearLoot()
        lootTable = twipe(lootTable)
        lootState.lootCount = 0
        Bus.TriggerEvent(InternalEvents.SetItem, nil, nil)
    end

    -- Returns the table for the currently selected item.
    function getItem(i)
        i = i or lootState.currentItemIndex
        return lootTable[i]
    end

    -- Returns the name of the currently selected item.
    function getItemName(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemName or nil
    end

    -- Returns the link of the currently selected item.
    function getItemLink(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemLink or nil
    end

    -- Returns the texture of the currently selected item.
    function getItemTexture(i)
        i = i or lootState.currentItemIndex
        return lootTable[i] and lootTable[i].itemTexture or nil
    end

    function module:GetCurrentItemCount()
        if lootState.fromInventory then
            return itemInfo.count or lootState.selectedItemCount or 1
        end
        local item = getItem()
        local count = item and item.count
        if count and count > 0 then
            return count
        end
        return 1
    end

    function module:GetLootWindowItems()
        local items = {}
        for i = 1, lootState.lootCount do
            local item = lootTable[i]
            if item and item.itemLink then
                items[#items + 1] = {
                    itemKey = item.itemKey or (Item.GetItemStringFromLink(item.itemLink) or item.itemLink),
                    count = tonumber(item.count) or 1,
                }
            end
        end
        return items
    end

    -- Checks if a loot item exists at the given index.
    function itemExists(i)
        i = i or lootState.currentItemIndex
        return (lootTable[i] ~= nil)
    end

    -- Checks if an item in the player's bags is soulbound.
    function itemIsSoulbound(bag, slot)
        return isBagItemSoulbound(bag, slot)
    end

    -- Cross-module bridge for split files (Rolls/Master).
    module.WarmItemCache = warmItemCache
    module.IsBagItemSoulbound = isBagItemSoulbound
    module.GetItem = getItem
    module.GetItemName = getItemName
    module.GetItemLink = getItemLink
    module.GetItemTexture = getItemTexture
    module.ItemExists = itemExists
    module.ItemIsSoulbound = itemIsSoulbound
    function module.FindLootSlotIndex(selfOrItemLink, maybeItemLink)
        local itemLink = maybeItemLink ~= nil and maybeItemLink or selfOrItemLink
        return findLootSlotIndex(itemLink)
    end

    function module.FindTradeableInventoryMatch(selfOrItemLink, arg2, arg3)
        local itemLink, itemId
        if type(selfOrItemLink) == "table" then
            itemLink = arg2
            itemId = arg3
        else
            itemLink = selfOrItemLink
            itemId = arg2
        end
        return scanTradeableInventory(itemLink, itemId)
    end

    function module.FindTradeableInventoryItem(selfOrItemLink, arg2, arg3, arg4, arg5)
        local itemLink, cachedBag, cachedSlot, selectedItemCount
        if type(selfOrItemLink) == "table" then
            itemLink = arg2
            cachedBag = arg3
            cachedSlot = arg4
            selectedItemCount = arg5
        else
            itemLink = selfOrItemLink
            cachedBag = arg2
            cachedSlot = arg3
            selectedItemCount = arg4
        end
        return resolveTradeableInventoryItem(itemLink, cachedBag, cachedSlot, selectedItemCount)
    end
end
