-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core
local Strings = feature.Strings or addon.Strings
local Item = feature.Item or addon.Item

local rollTypes = feature.rollTypes

local type = type
local tostring, tonumber = tostring, tonumber

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --

    -- ----- Private helpers ----- --
    local findRaidPlayerByNid = assert(module._FindRaidPlayerByNid, "Missing Raid._FindRaidPlayerByNid")

    local function buildHeldLootItemQuery(itemLink)
        if not itemLink then
            return nil
        end

        return {
            itemString = Item.GetItemStringFromLink(itemLink),
            itemId = tonumber(Item.GetItemIdFromLink(itemLink)) or 0,
            itemLink = itemLink,
        }
    end

    local function matchesHeldLootItem(entry, query, allowDirectLinkMatch)
        if type(entry) ~= "table" or type(query) ~= "table" then
            return false
        end

        local queryItemKey = query.itemString or query.itemLink
        local entryItemKey = entry.itemString or entry.itemLink
        if queryItemKey and entryItemKey and queryItemKey == entryItemKey then
            return true
        end
        if query.itemId > 0 and tonumber(entry.itemId) == query.itemId then
            return true
        end
        if allowDirectLinkMatch and entry.itemLink and entry.itemLink == query.itemLink then
            return true
        end
        return false
    end

    local function resolveLootLooterName(raid, loot)
        if type(loot) ~= "table" then
            return nil
        end
        local looterNid = tonumber(loot.looterNid)
        if looterNid and looterNid > 0 then
            local player = findRaidPlayerByNid(raid, looterNid)
            if player and player.name then
                return player.name
            end
        end
        return nil
    end

    -- ----- Public methods ----- --
    function module:GetLootByNid(lootNid, raidNum)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or lootNid == nil then
            return nil
        end
        Core.EnsureRaidSchema(raid)

        lootNid = tonumber(lootNid) or 0
        if lootNid <= 0 then
            return nil
        end

        local loot = raid.loot
        for i = 1, #loot do
            local l = loot[i]
            if l and tonumber(l.lootNid) == lootNid then
                return l, i
            end
        end
        return nil
    end

    -- Retrieves the position of a specific loot item within the raid's loot table.
    function module:GetLootID(itemID, raidNum, holderName, bossNid)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        itemID = tonumber(itemID)
        if not itemID then
            return 0
        end

        local queryBossNid = tonumber(bossNid) or 0
        local loot = raid.loot or {}

        for i = #loot, 1, -1 do
            local v = loot[i]
            if v and tonumber(v.itemId) == itemID then
                local winnerName = resolveLootLooterName(raid, v)
                if not holderName or holderName == "" or winnerName == holderName then
                    if queryBossNid <= 0 or tonumber(v.bossNid) == queryBossNid then
                        return tonumber(v.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    function module:MatchHeldInventoryLoot(entry, raidNum, itemLink, holderName)
        if type(entry) ~= "table" or tonumber(entry.rollType) ~= rollTypes.HOLD or not itemLink then
            return false
        end

        raidNum = raidNum or Core.GetCurrentRaid()

        local query = buildHeldLootItemQuery(itemLink)
        if not matchesHeldLootItem(entry, query, false) then
            return false
        end

        local resolvedHolder = Strings.NormalizeName(holderName or Core.GetPlayerName(), true)
        if not resolvedHolder or resolvedHolder == "" then
            return true
        end

        local holderNid = module:GetPlayerID(resolvedHolder, raidNum)
        if holderNid > 0 then
            return tonumber(entry.looterNid) == holderNid
        end
        return true
    end

    function module:ResolveHeldLootNid(itemLink, preferredLootNid, holderName, raidNum)
        if not itemLink then
            return 0
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        if not raidNum then
            return 0
        end

        local preferred = tonumber(preferredLootNid) or 0
        if preferred > 0 then
            local entry = module:GetLootByNid(preferred, raidNum)
            if module:MatchHeldInventoryLoot(entry, raidNum, itemLink, holderName) then
                return preferred
            end
        end

        return tonumber(module:GetHeldLootNid(itemLink, raidNum, holderName, 0)) or 0
    end

    function module:GetHeldLootNid(itemLink, raidNum, holderName, bossNid)
        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid or not itemLink then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        local query = buildHeldLootItemQuery(itemLink)
        local queryBossNid = tonumber(bossNid) or 0

        local loot = raid.loot or {}
        for i = #loot, 1, -1 do
            local entry = loot[i]
            if entry and tonumber(entry.rollType) == rollTypes.HOLD then
                local winnerName = resolveLootLooterName(raid, entry)
                if (not holderName or holderName == "" or winnerName == holderName) and (queryBossNid <= 0 or tonumber(entry.bossNid) == queryBossNid) then
                    if matchesHeldLootItem(entry, query, true) then
                        return tonumber(entry.lootNid) or 0
                    end
                end
            end
        end
        return 0
    end

    function module:GetLootNidByRollSessionId(rollSessionId, raidNum, holderName, bossNid)
        local sessionId = rollSessionId and tostring(rollSessionId) or nil
        if not sessionId or sessionId == "" then
            return 0
        end

        raidNum = raidNum or Core.GetCurrentRaid()
        local raid = Core.EnsureRaidById(raidNum)
        if not raid then
            return 0
        end

        Core.EnsureRaidSchema(raid)
        holderName = Strings.NormalizeName(holderName, true)

        local queryBossNid = tonumber(bossNid) or 0
        local loot = raid.loot or {}
        for i = #loot, 1, -1 do
            local entry = loot[i]
            if entry and tostring(entry.rollSessionId or "") == sessionId then
                local winnerName = resolveLootLooterName(raid, entry)
                if (not holderName or holderName == "" or winnerName == holderName) and (queryBossNid <= 0 or tonumber(entry.bossNid) == queryBossNid) then
                    return tonumber(entry.lootNid) or 0
                end
            end
        end
        return 0
    end
end
