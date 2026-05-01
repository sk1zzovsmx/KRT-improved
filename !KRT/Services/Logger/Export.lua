-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.Services.Logger.Export
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core

local tostring, tonumber, type = tostring, tonumber, type
local date = date

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Logger", "Export")
local Export = addon.Services.Logger.Export
local Store = addon.Services.Logger.Store

local HEADER_LOOT = {
    "raidNid",
    "raidDate",
    "zone",
    "size",
    "difficulty",
    "bossNid",
    "boss",
    "bossTime",
    "lootNid",
    "itemId",
    "itemName",
    "winner",
    "class",
    "rollType",
    "rollValue",
    "lootTime",
}

local HEADER_RAID_ATTENDANCE = {
    "raidNid",
    "raidDate",
    "zone",
    "size",
    "difficulty",
    "playerNid",
    "player",
    "class",
    "join",
    "leave",
    "attendanceSeconds",
    "onlineSeconds",
    "offlineSeconds",
    "segmentCount",
}

-- ----- Private helpers ----- --
local function getRaidQueries()
    if Core.GetRaidQueries then
        return Core.GetRaidQueries()
    end
    return nil
end

local function normalizeContext(context)
    return type(context) == "table" and context or {}
end

local function formatTimestamp(timestamp)
    local resolvedTimestamp = tonumber(timestamp) or 0
    if resolvedTimestamp <= 0 then
        return ""
    end
    return date("%Y-%m-%d %H:%M:%S", resolvedTimestamp)
end

local function encodeCSVField(value)
    if value == nil then
        return ""
    end

    local text = tostring(value)
    if text:find('[",\r\n]') then
        text = text:gsub('"', '""')
        return '"' .. text .. '"'
    end
    return text
end

local function appendCSVLine(lines, fields)
    local encoded = {}
    for i = 1, #fields do
        encoded[i] = encodeCSVField(fields[i])
    end
    lines[#lines + 1] = table.concat(encoded, ",")
end

local function buildCSV(header, rows)
    local lines = {}
    appendCSVLine(lines, header)
    for i = 1, #rows do
        appendCSVLine(lines, rows[i])
    end
    return table.concat(lines, "\n")
end

local function getRaidNid(raid)
    return tonumber(raid and raid.raidNid) or ""
end

local function getRaidDate(raid)
    return formatTimestamp(raid and raid.startTime)
end

local function getRaidZone(raid)
    return raid and raid.zone or ""
end

local function getRaidSize(raid)
    return tonumber(raid and raid.size) or ""
end

local function getRaidDifficulty(raid)
    return tonumber(raid and raid.difficulty) or ""
end

local function getSelectedPlayerName(raid, context)
    local selectedPlayerNid = tonumber(context and context.selectedPlayerNid)
    if not selectedPlayerNid then
        return nil
    end

    local player = Store and Store.GetPlayer and Store:GetPlayer(raid, selectedPlayerNid) or nil
    return player and player.name or nil
end

local function getBossNameByNid(raid, bossNid)
    local boss = Store and Store.GetBoss and Store:GetBoss(raid, bossNid) or nil
    return boss and boss.name or ""
end

local function getBossTimeByNid(raid, bossNid)
    local boss = Store and Store.GetBoss and Store:GetBoss(raid, bossNid) or nil
    return boss and boss.time or nil
end

-- ----- Public methods ----- --
function Export:GetCSV(mode, raid, context)
    if type(raid) ~= "table" then
        return "", "INVALID_RAID"
    end

    if mode == "loot" then
        return self:GetLootCSV(raid, context)
    elseif mode == "raidAttendance" then
        return self:GetRaidAttendanceCSV(raid, context)
    end

    return "", "INVALID_MODE"
end

function Export:GetLootCSV(raid, context)
    context = normalizeContext(context)
    local queries = getRaidQueries()
    local playerName = getSelectedPlayerName(raid, context)
    local lootRows = queries and queries.GetLoot and queries:GetLoot(raid, context.selectedBossNid, playerName) or {}
    local rows = {}

    for i = 1, #lootRows do
        local loot = lootRows[i]
        if loot then
            local bossNid = tonumber(loot.bossNid) or ""
            rows[#rows + 1] = {
                getRaidNid(raid),
                getRaidDate(raid),
                getRaidZone(raid),
                getRaidSize(raid),
                getRaidDifficulty(raid),
                bossNid,
                loot.sourceName or getBossNameByNid(raid, bossNid),
                formatTimestamp(getBossTimeByNid(raid, bossNid)),
                tonumber(loot.id) or "",
                tonumber(loot.itemId) or "",
                loot.itemName or "",
                loot.looter or "",
                loot.looterClass or "",
                tonumber(loot.rollType) or "",
                tonumber(loot.rollValue) or "",
                formatTimestamp(loot.time),
            }
        end
    end

    return buildCSV(HEADER_LOOT, rows)
end

function Export:GetRaidAttendanceCSV(raid)
    local queries = getRaidQueries()
    local attendanceRows = queries and queries.GetRaidAttendance and queries:GetRaidAttendance(raid) or {}
    local rows = {}

    for i = 1, #attendanceRows do
        local entry = attendanceRows[i]
        if entry then
            rows[#rows + 1] = {
                getRaidNid(raid),
                getRaidDate(raid),
                getRaidZone(raid),
                getRaidSize(raid),
                getRaidDifficulty(raid),
                tonumber(entry.id) or "",
                entry.name or "",
                entry.class or "",
                formatTimestamp(entry.join),
                formatTimestamp(entry.leave),
                tonumber(entry.attendanceSeconds) or 0,
                tonumber(entry.onlineSeconds) or 0,
                tonumber(entry.offlineSeconds) or 0,
                tonumber(entry.segmentCount) or 0,
            }
        end
    end

    return buildCSV(HEADER_RAID_ATTENDANCE, rows)
end
