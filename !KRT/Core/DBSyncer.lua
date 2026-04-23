-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Events = feature.Events or addon.Events
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Base64 = feature.Base64 or addon.Base64
local Time = feature.Time or addon.Time
local Comms = feature.Comms or addon.Comms
local Services = feature.Services or addon.Services

local _G = _G
local tinsert = table.insert
local tconcat = table.concat
local tsort = table.sort
local pairs, type, select = pairs, type, select
local strfind, strsub = string.find, string.sub
local tonumber, tostring = tonumber, tostring
local floor = math.floor

local GetTime = _G.GetTime
local SendAddonMessage = _G.SendAddonMessage

local InternalEvents = Events.Internal

-- Logger synchronization module.
do
    addon.DB.Syncer = addon.DB.Syncer or {}
    local module = addon.DB.Syncer

    -- ----- Internal state ----- --
    local COMM_PREFIX = "KRTLogSync"
    local PROTOCOL_VERSION = 1

    local FIELD_SEP = "\t"
    local RECORD_SEP = "\n"
    local LIST_SEP = "\031"

    local MSG_REQUEST = "RQ"
    local MSG_SNAPSHOT = "SN"

    local MODE_REQ = "REQ"
    local MODE_PUSH = "PUSH"
    local MODE_SYNC = "SYNC"

    local MAX_CHUNK_SIZE = 180
    local REQUEST_TTL_SECONDS = 30
    local INCOMING_TTL_SECONDS = 45
    local REQUEST_RATE_WINDOW_SECONDS = 30
    local REQUEST_RATE_MAX_PER_SENDER = 6
    local REQUEST_RATE_PRUNE_SECONDS = REQUEST_RATE_WINDOW_SECONDS * 2
    local SYNC_OFFICER_LOOKUP_GRACE_SECONDS = 2

    module._incoming = module._incoming or {}
    module._pendingRequests = module._pendingRequests or {}
    module._requestRate = module._requestRate or {}
    module._nextRequestId = tonumber(module._nextRequestId) or 0

    -- ----- Private helpers ----- --
    local function nowSec()
        return (GetTime and GetTime()) or 0
    end

    local function parseNumber(value, fallback)
        local n = tonumber(value)
        if n == nil then
            return fallback
        end
        return n
    end

    local function normalizeSender(sender)
        if type(sender) ~= "string" then
            return nil
        end
        local short = sender:match("^([^%-]+)") or sender
        return Strings.NormalizeName(short, true) or short
    end

    local function isSelfSender(sender)
        local selfName = Core.GetPlayerName()
        if not selfName then
            return false
        end
        local a = Strings.NormalizeLower(selfName, true)
        local b = Strings.NormalizeLower(normalizeSender(sender), true)
        return (a ~= nil and b ~= nil and a == b)
    end

    local function encodeText(value)
        local input = tostring(value or "")
        local ok, out = pcall(Base64.Encode, input)
        if ok and out then
            return out
        end
        return ""
    end

    local function decodeText(value)
        local input = tostring(value or "")
        if input == "" then
            return ""
        end
        local ok, out = pcall(Base64.Decode, input)
        if ok and out then
            return out
        end
        return nil
    end

    local function splitFields(text, sep, out)
        local delimiter = sep or FIELD_SEP
        local fields = out or {}
        local n = 0
        local startPos = 1

        while true do
            local fromPos, toPos = strfind(text, delimiter, startPos, true)
            if not fromPos then
                n = n + 1
                fields[n] = strsub(text, startPos)
                break
            end
            n = n + 1
            fields[n] = strsub(text, startPos, fromPos - 1)
            startPos = toPos + 1
        end

        for i = n + 1, #fields do
            fields[i] = nil
        end

        return fields, n
    end

    local function packFields(...)
        local n = select("#", ...)
        local out = {}
        for i = 1, n do
            out[i] = tostring(select(i, ...) or "")
        end
        return tconcat(out, FIELD_SEP)
    end

    local function buildPlayerNameMaps(players)
        local byNid = {}
        local byNameLower = {}
        local validNids = {}
        if type(players) ~= "table" then
            return byNid, byNameLower, validNids
        end

        for i = 1, #players do
            local player = players[i]
            if type(player) == "table" then
                local playerNid = tonumber(player.playerNid)
                local playerName = player.name
                if playerNid and playerNid > 0 then
                    validNids[playerNid] = true
                    if type(playerName) == "string" and playerName ~= "" then
                        byNid[playerNid] = playerName
                        local normalized = Strings.NormalizeLower(playerName, true)
                        if normalized and normalized ~= "" and byNameLower[normalized] == nil then
                            byNameLower[normalized] = playerNid
                        end
                    end
                end
            end
        end

        return byNid, byNameLower, validNids
    end

    local function joinBossAttendeeNameList(players, playerNameByNid)
        if type(players) ~= "table" or #players == 0 then
            return ""
        end
        local out = {}
        local seen = {}
        for i = 1, #players do
            local raw = players[i]
            local playerName = nil
            local playerNid = tonumber(raw)
            if playerNid and playerNid > 0 then
                playerName = playerNameByNid and playerNameByNid[playerNid] or nil
            elseif type(raw) == "string" then
                playerName = Strings.NormalizeName(raw, true) or raw
            end
            if playerName and playerName ~= "" and not seen[playerName] then
                seen[playerName] = true
                out[#out + 1] = tostring(playerName)
            end
        end
        return tconcat(out, LIST_SEP)
    end

    local function splitNameList(raw, out)
        local names = out or {}
        if not raw or raw == "" then
            for i = 1, #names do
                names[i] = nil
            end
            return names, 0
        end
        return splitFields(raw, LIST_SEP, names)
    end

    local function resolveLootLooterName(loot, playerNameByNid)
        if type(loot) ~= "table" then
            return ""
        end
        local looterNid = tonumber(loot.looterNid)
        if looterNid and looterNid > 0 then
            local playerName = playerNameByNid and playerNameByNid[looterNid] or nil
            if playerName and playerName ~= "" then
                return playerName
            end
        end
        return ""
    end

    local function cleanupExpiredState()
        local now = nowSec()

        for key, st in pairs(module._incoming) do
            local age = now - (tonumber(st and st.createdAt) or now)
            if age > INCOMING_TTL_SECONDS then
                module._incoming[key] = nil
            end
        end

        for reqId, st in pairs(module._pendingRequests) do
            local age = now - (tonumber(st and st.createdAt) or now)
            if age > REQUEST_TTL_SECONDS then
                module._pendingRequests[reqId] = nil
            end
        end

        for sender, st in pairs(module._requestRate) do
            local stamp = tonumber(st and st.windowStart) or tonumber(st and st.lastSeen) or now
            local age = now - stamp
            if age > REQUEST_RATE_PRUNE_SECONDS then
                module._requestRate[sender] = nil
            end
        end
    end

    local function cleanupIncomingByRequest(requestId, mode)
        local requestKey = tostring(requestId or "")
        local modeKey = tostring(mode or "")
        if requestKey == "" or modeKey == "" then
            return
        end
        for key, st in pairs(module._incoming) do
            local incomingRequestId = tostring(st and st.requestId or "")
            local incomingMode = tostring(st and st.mode or "")
            if incomingRequestId == requestKey and incomingMode == modeKey then
                module._incoming[key] = nil
            end
        end
    end

    local function allowIncomingRequest(rawSender)
        local sender = normalizeSender(rawSender) or tostring(rawSender or "?")
        local now = nowSec()
        local rate = module._requestRate[sender]
        if not rate then
            module._requestRate[sender] = {
                windowStart = now,
                lastSeen = now,
                count = 1,
                warned = false,
            }
            return true, sender
        end

        local windowStart = tonumber(rate.windowStart) or now
        if (now - windowStart) > REQUEST_RATE_WINDOW_SECONDS then
            rate.windowStart = now
            rate.lastSeen = now
            rate.count = 1
            rate.warned = false
            return true, sender
        end

        rate.lastSeen = now
        rate.count = (tonumber(rate.count) or 0) + 1
        if rate.count > REQUEST_RATE_MAX_PER_SENDER then
            if not rate.warned then
                addon:warn((Diag.W.LogSyncRequestRateLimited):format(tostring(sender), rate.count, REQUEST_RATE_WINDOW_SECONDS))
                rate.warned = true
            end
            return false, sender
        end

        return true, sender
    end

    local function canAnswerRequests(channel)
        if not addon.IsInGroup() then
            return false
        end
        if channel == "WHISPER" then
            return true
        end
        if not addon.IsInRaid() then
            return true
        end
        local raidService = Services and Services.Raid or nil
        if raidService and type(raidService.CanUseCapability) == "function" then
            return raidService:CanUseCapability("raid_leadership")
        end

        local leaderFn = addon.UnitIsGroupLeader
        local assistantFn = addon.UnitIsGroupAssistant
        local isLeader = leaderFn and leaderFn("player")
        local isAssistant = assistantFn and assistantFn("player")
        return (isLeader or isAssistant) and true or false
    end

    local function normalizeTargetName(raw)
        local text = Strings.TrimText(raw or "")
        if text == "" then
            return nil
        end
        return Strings.NormalizeName(text, true) or text
    end

    local function ensureGroupSyncAvailable()
        cleanupExpiredState()
        if addon.IsInGroup() then
            return true
        end

        addon:warn(L.MsgLoggerSyncNotInGroup)
        return false
    end

    local function resolveExternalTarget(targetName)
        local target = normalizeTargetName(targetName)
        if not target then
            addon:warn(L.MsgLoggerSyncTargetRequired)
            return nil
        end
        if isSelfSender(target) then
            addon:warn(L.MsgLoggerSyncTargetSelf)
            return nil
        end

        return target
    end

    local function nextRequestId(syncer)
        syncer._nextRequestId = (tonumber(syncer._nextRequestId) or 0) + 1
        return tostring(syncer._nextRequestId)
    end

    local function trackPendingRequest(syncer, requestId, pendingState)
        syncer._pendingRequests[requestId] = pendingState
    end

    local function sortedByNid(list, nidKey, tieKey)
        local out = {}
        if type(list) ~= "table" then
            return out
        end

        for i = 1, #list do
            local v = list[i]
            if v then
                tinsert(out, v)
            end
        end

        tsort(out, function(a, b)
            local aNid = tonumber(a and a[nidKey]) or 0
            local bNid = tonumber(b and b[nidKey]) or 0
            if aNid ~= bNid then
                return aNid < bNid
            end
            local aTie = tostring((a and a[tieKey]) or "")
            local bTie = tostring((b and b[tieKey]) or "")
            return aTie < bTie
        end)

        return out
    end

    local function buildSnapshotPayload(raid)
        if type(raid) ~= "table" then
            return nil
        end

        Core.EnsureRaidSchema(raid)

        local lines = {}
        local schemaVersion = tonumber(raid.schemaVersion) or tonumber(Core.GetRaidSchemaVersion and Core.GetRaidSchemaVersion()) or 1

        lines[#lines + 1] = packFields(
            "H",
            PROTOCOL_VERSION,
            schemaVersion,
            tonumber(raid.raidNid) or 0,
            encodeText(raid.zone),
            tonumber(raid.size) or 0,
            tonumber(raid.difficulty) or 0,
            encodeText(raid.realm),
            tonumber(raid.startTime) or 0,
            tonumber(raid.endTime) or 0,
            tonumber(raid.nextPlayerNid) or 1,
            tonumber(raid.nextBossNid) or 1,
            tonumber(raid.nextLootNid) or 1
        )

        local players = sortedByNid(raid.players, "playerNid", "name")
        local playerNameByNid = {}
        for i = 1, #players do
            local p = players[i]
            local playerNid = tonumber(p and p.playerNid)
            if playerNid and playerNid > 0 and p and p.name then
                playerNameByNid[playerNid] = p.name
            end
        end
        for i = 1, #players do
            local p = players[i]
            lines[#lines + 1] = packFields(
                "P",
                tonumber(p.playerNid) or 0,
                encodeText(p.name),
                tonumber(p.rank) or 0,
                tonumber(p.subgroup) or 1,
                encodeText(p.class),
                tonumber(p.join) or 0,
                tonumber(p.leave) or 0,
                tonumber(p.count) or 0
            )
        end

        local attendance = sortedByNid(raid.attendance, "playerNid", "playerNid")
        for i = 1, #attendance do
            local entry = attendance[i]
            local playerNid = type(entry) == "table" and (tonumber(entry.playerNid) or 0) or 0
            local segments = type(entry) == "table" and entry.segments or nil
            if playerNid > 0 and type(segments) == "table" then
                for j = 1, #segments do
                    local segment = segments[j]
                    if type(segment) == "table" then
                        lines[#lines + 1] = packFields(
                            "A",
                            playerNid,
                            tonumber(segment.startTime) or 0,
                            tonumber(segment.endTime) or 0,
                            tonumber(segment.subgroup) or 1,
                            segment.online == false and 0 or 1
                        )
                    end
                end
            end
        end

        local bosses = sortedByNid(raid.bossKills, "bossNid", "name")
        for i = 1, #bosses do
            local b = bosses[i]
            lines[#lines + 1] = packFields(
                "B",
                tonumber(b.bossNid) or 0,
                encodeText(b.name),
                encodeText(b.mode),
                tonumber(b.difficulty) or 0,
                tonumber(b.time) or 0,
                encodeText(b.hash),
                encodeText(joinBossAttendeeNameList(b.players, playerNameByNid))
            )
        end

        local lootRows = sortedByNid(raid.loot, "lootNid", "itemName")
        for i = 1, #lootRows do
            local loot = lootRows[i]
            lines[#lines + 1] = packFields(
                "L",
                tonumber(loot.lootNid) or 0,
                tonumber(loot.itemId) or 0,
                encodeText(loot.itemName),
                encodeText(loot.itemString),
                encodeText(loot.itemLink),
                tonumber(loot.itemRarity) or 0,
                encodeText(loot.itemTexture),
                tonumber(loot.itemCount) or 1,
                encodeText(resolveLootLooterName(loot, playerNameByNid)),
                tonumber(loot.rollType) or 0,
                tonumber(loot.rollValue) or 0,
                tonumber(loot.bossNid) or 0,
                tonumber(loot.time) or 0
            )
        end

        local changes = raid.changes or {}
        local names = {}
        for name in pairs(changes) do
            names[#names + 1] = name
        end
        tsort(names, function(a, b)
            return tostring(a):lower() < tostring(b):lower()
        end)
        for i = 1, #names do
            local name = names[i]
            lines[#lines + 1] = packFields("C", encodeText(name), encodeText(changes[name]))
        end

        return tconcat(lines, RECORD_SEP)
    end

    local function parseSnapshotPayload(payload)
        if type(payload) ~= "string" or payload == "" then
            return nil
        end

        local snapshot = {
            header = nil,
            players = {},
            bosses = {},
            loot = {},
            attendance = {},
            changes = {},
        }

        local fields = {}
        local listFields = {}
        local lineCount = 0

        for line in payload:gmatch("[^\n]+") do
            lineCount = lineCount + 1
            local f, n = splitFields(line, FIELD_SEP, fields)
            local kind = f[1]

            if kind == "H" and n >= 13 then
                local zone = decodeText(f[5])
                local realm = decodeText(f[8])
                if zone == nil or realm == nil then
                    return nil
                end
                snapshot.header = {
                    protocolVersion = parseNumber(f[2], 0),
                    schemaVersion = parseNumber(f[3], 1),
                    raidNid = parseNumber(f[4], nil),
                    zone = zone,
                    size = parseNumber(f[6], 0),
                    difficulty = parseNumber(f[7], 0),
                    realm = realm,
                    startTime = parseNumber(f[9], 0),
                    endTime = parseNumber(f[10], 0),
                    nextPlayerNid = parseNumber(f[11], 1),
                    nextBossNid = parseNumber(f[12], 1),
                    nextLootNid = parseNumber(f[13], 1),
                }
            elseif kind == "P" and n >= 9 then
                local name = decodeText(f[3])
                local className = decodeText(f[6])
                if name == nil or className == nil then
                    return nil
                end
                tinsert(snapshot.players, {
                    playerNid = parseNumber(f[2], nil),
                    name = name,
                    rank = parseNumber(f[4], 0),
                    subgroup = parseNumber(f[5], 1),
                    class = className,
                    join = parseNumber(f[7], 0),
                    leave = parseNumber(f[8], 0),
                    count = parseNumber(f[9], 0),
                })
            elseif kind == "A" and n >= 6 then
                tinsert(snapshot.attendance, {
                    playerNid = parseNumber(f[2], nil),
                    startTime = parseNumber(f[3], 0),
                    endTime = parseNumber(f[4], 0),
                    subgroup = parseNumber(f[5], 1),
                    online = parseNumber(f[6], 1) ~= 0,
                })
            elseif kind == "B" and n >= 8 then
                local name = decodeText(f[3])
                local mode = decodeText(f[4])
                local hash = decodeText(f[7])
                local playersRaw = decodeText(f[8])
                if name == nil or mode == nil or hash == nil or playersRaw == nil then
                    return nil
                end

                local names, namesCount = splitNameList(playersRaw, listFields)
                local players = {}
                for i = 1, namesCount do
                    if names[i] and names[i] ~= "" then
                        players[#players + 1] = names[i]
                    end
                end

                tinsert(snapshot.bosses, {
                    bossNid = parseNumber(f[2], nil),
                    name = name,
                    mode = mode,
                    difficulty = parseNumber(f[5], 0),
                    time = parseNumber(f[6], 0),
                    hash = hash,
                    players = players,
                })
            elseif kind == "L" and n >= 14 then
                local itemName = decodeText(f[4])
                local itemString = decodeText(f[5])
                local itemLink = decodeText(f[6])
                local itemTexture = decodeText(f[8])
                local looterName = decodeText(f[10])
                local looterNid = tonumber(looterName)
                if itemName == nil or itemString == nil or itemLink == nil then
                    return nil
                end
                if itemTexture == nil or looterName == nil then
                    return nil
                end
                tinsert(snapshot.loot, {
                    lootNid = parseNumber(f[2], nil),
                    itemId = parseNumber(f[3], 0),
                    itemName = itemName,
                    itemString = itemString,
                    itemLink = itemLink,
                    itemRarity = parseNumber(f[7], 0),
                    itemTexture = itemTexture,
                    itemCount = parseNumber(f[9], 1),
                    looterName = looterName,
                    looterNid = looterNid,
                    rollType = parseNumber(f[11], 0),
                    rollValue = parseNumber(f[12], 0),
                    bossNid = parseNumber(f[13], 0),
                    time = parseNumber(f[14], 0),
                })
            elseif kind == "C" and n >= 3 then
                local name = decodeText(f[2])
                local spec = decodeText(f[3])
                if name == nil or spec == nil then
                    return nil
                end
                if name ~= "" then
                    snapshot.changes[name] = spec
                end
            end
        end

        if lineCount == 0 or not snapshot.header or not tonumber(snapshot.header.raidNid) then
            return nil
        end

        return snapshot
    end

    local function buildNidIndex(list, nidField)
        local index = {}
        for i = 1, #list do
            local row = list[i]
            local nid = tonumber(row and row[nidField])
            if nid and nid > 0 then
                index[nid] = i
            end
        end
        return index
    end

    local function upsertByNid(list, index, nid)
        local idx = index[nid]
        if idx then
            return list[idx], idx
        end
        local row = {}
        list[#list + 1] = row
        idx = #list
        index[nid] = idx
        return row, idx
    end

    local function copyUniquePlayerNids(values, playerNidByName, validPlayerNids)
        local out = {}
        local seen = {}
        if type(values) ~= "table" then
            return out
        end
        for i = 1, #values do
            local raw = values[i]
            local playerNid = tonumber(raw)
            if not playerNid and type(raw) == "string" then
                playerNid = playerNidByName and playerNidByName[Strings.NormalizeLower(raw, true)] or nil
            end
            if playerNid and playerNid > 0 then
                if (not validPlayerNids) or validPlayerNids[playerNid] then
                    if not seen[playerNid] then
                        seen[playerNid] = true
                        out[#out + 1] = playerNid
                    end
                end
            end
        end
        return out
    end

    local function buildSignatureFromRaid(raid)
        return {
            zone = tostring(raid and raid.zone or ""),
            size = tonumber(raid and raid.size) or 0,
            diff = tonumber(raid and raid.difficulty) or 0,
        }
    end

    local function raidMatchesSignature(raid, signature)
        if not (raid and signature) then
            return false
        end

        local raidZone = tostring(raid.zone or "")
        local sigZone = tostring(signature.zone or "")
        if raidZone ~= sigZone then
            return false
        end

        local raidSize = tonumber(raid.size) or 0
        local sigSize = tonumber(signature.size) or 0
        if raidSize ~= sigSize then
            return false
        end

        local raidDiff = tonumber(raid.difficulty) or 0
        local sigDiff = tonumber(signature.diff) or 0
        if raidDiff ~= sigDiff then
            return false
        end

        return true
    end

    local function raidMatchesSnapshotHeader(raid, header)
        local signature = {
            zone = header and header.zone,
            size = header and header.size,
            diff = header and header.difficulty,
        }
        return raidMatchesSignature(raid, signature)
    end

    local function getCurrentRaidRecord()
        local currentId = Core.GetCurrentRaid()
        if not currentId then
            return nil, nil
        end
        return Core.EnsureRaidById(currentId), currentId
    end

    local function resolveRaidByReference(raidRef, allowFallback)
        local n = tonumber(raidRef)
        if n and n > 0 then
            local byId, byIdIndex = Core.EnsureRaidById(n)
            if byId then
                return byId, byIdIndex
            end

            local byNid, byNidIndex = Core.EnsureRaidByNid(n)
            if byNid then
                return byNid, byNidIndex
            end

            return nil, nil
        end

        if not allowFallback then
            return nil, nil
        end

        local selectedRaid = addon.State and addon.State.selectedRaid
        if selectedRaid then
            local raid = Core.EnsureRaidById(selectedRaid)
            if raid then
                return raid, selectedRaid
            end
        end

        local currentRaid = Core.GetCurrentRaid()
        if currentRaid then
            return Core.EnsureRaidById(currentRaid), currentRaid
        end

        return nil, nil
    end

    local function applySnapshotToRaid(raid, snapshot, updateMeta)
        if not (raid and snapshot and snapshot.header) then
            return nil
        end
        local header = snapshot.header

        if updateMeta then
            raid.schemaVersion = tonumber(header.schemaVersion) or tonumber(raid.schemaVersion) or 1
            raid.zone = header.zone or raid.zone
            raid.size = tonumber(header.size) or tonumber(raid.size)
            raid.difficulty = tonumber(header.difficulty) or tonumber(raid.difficulty)
            raid.realm = header.realm or raid.realm

            if tonumber(header.startTime) and tonumber(header.startTime) > 0 then
                raid.startTime = tonumber(header.startTime)
            end
            if tonumber(header.endTime) and tonumber(header.endTime) > 0 then
                raid.endTime = tonumber(header.endTime)
            end
        end

        raid.players = raid.players or {}
        local playerIdx = buildNidIndex(raid.players, "playerNid")
        for i = 1, #snapshot.players do
            local src = snapshot.players[i]
            local nid = tonumber(src and src.playerNid)
            if nid and nid > 0 then
                local dst = upsertByNid(raid.players, playerIdx, nid)
                local count = tonumber(src.count) or 0
                if count < 0 then
                    count = 0
                end
                dst.playerNid = nid
                dst.name = Strings.NormalizeName(src.name, true) or src.name or dst.name
                dst.rank = tonumber(src.rank) or 0
                dst.subgroup = tonumber(src.subgroup) or 1
                dst.class = (src.class and src.class ~= "") and src.class or "UNKNOWN"
                dst.join = tonumber(src.join) or dst.join
                local leave = tonumber(src.leave) or 0
                dst.leave = (leave > 0) and leave or nil
                dst.count = count
            end
        end

        local _, playerNidByName, validPlayerNids = buildPlayerNameMaps(raid.players)

        if #(snapshot.attendance or {}) > 0 then
            local attendance = {}
            local attendanceByNid = {}
            for i = 1, #snapshot.attendance do
                local src = snapshot.attendance[i]
                local playerNid = tonumber(src and src.playerNid) or 0
                local startTime = tonumber(src and src.startTime) or 0
                if playerNid > 0 and validPlayerNids[playerNid] and startTime > 0 then
                    local entry = attendanceByNid[playerNid]
                    if not entry then
                        entry = {
                            playerNid = playerNid,
                            segments = {},
                        }
                        attendanceByNid[playerNid] = entry
                        attendance[#attendance + 1] = entry
                    end

                    local segment = {
                        startTime = startTime,
                    }
                    local endTime = tonumber(src.endTime) or 0
                    if endTime > startTime then
                        segment.endTime = endTime
                    end
                    local subgroup = tonumber(src.subgroup) or 1
                    if subgroup > 1 then
                        segment.subgroup = subgroup
                    end
                    if src.online == false then
                        segment.online = false
                    end
                    entry.segments[#entry.segments + 1] = segment
                end
            end
            raid.attendance = attendance
        end

        raid.bossKills = raid.bossKills or {}
        local bossIdx = buildNidIndex(raid.bossKills, "bossNid")
        for i = 1, #snapshot.bosses do
            local src = snapshot.bosses[i]
            local nid = tonumber(src and src.bossNid)
            if nid and nid > 0 then
                local dst = upsertByNid(raid.bossKills, bossIdx, nid)
                dst.bossNid = nid
                dst.name = src.name or dst.name
                dst.mode = (src.mode == "h") and "h" or "n"
                dst.difficulty = tonumber(src.difficulty) or dst.difficulty
                dst.time = tonumber(src.time) or dst.time
                if src.hash and src.hash ~= "" then
                    dst.hash = src.hash
                end
                dst.players = copyUniquePlayerNids(src.players, playerNidByName, validPlayerNids)
            end
        end

        raid.loot = raid.loot or {}
        local lootIdx = buildNidIndex(raid.loot, "lootNid")
        for i = 1, #snapshot.loot do
            local src = snapshot.loot[i]
            local nid = tonumber(src and src.lootNid)
            if nid and nid > 0 then
                local dst = upsertByNid(raid.loot, lootIdx, nid)
                local count = tonumber(src.itemCount) or 1
                if count < 1 then
                    count = 1
                end
                dst.lootNid = nid
                dst.itemId = tonumber(src.itemId) or dst.itemId
                dst.itemName = src.itemName or dst.itemName
                dst.itemString = src.itemString or dst.itemString
                dst.itemLink = src.itemLink or dst.itemLink
                dst.itemRarity = tonumber(src.itemRarity) or dst.itemRarity
                if src.itemTexture and src.itemTexture ~= "" then
                    dst.itemTexture = src.itemTexture
                end
                dst.itemCount = count
                local looterNid = tonumber(src.looterNid)
                if not looterNid and type(src.looterName) == "string" then
                    looterNid = playerNidByName[Strings.NormalizeLower(src.looterName, true)]
                end
                if looterNid and looterNid > 0 and validPlayerNids[looterNid] then
                    dst.looterNid = looterNid
                end
                dst.looter = nil
                dst.rollType = tonumber(src.rollType) or 0
                dst.rollValue = tonumber(src.rollValue) or 0
                dst.bossNid = tonumber(src.bossNid) or 0
                dst.time = tonumber(src.time) or dst.time
            end
        end

        raid.changes = raid.changes or {}
        for name, spec in pairs(snapshot.changes or {}) do
            local normalizedName = Strings.NormalizeName(name, true) or name
            if normalizedName and normalizedName ~= "" then
                local normalizedSpec = Strings.NormalizeName(spec, true)
                raid.changes[normalizedName] = (normalizedSpec and normalizedSpec ~= "") and normalizedSpec or nil
            end
        end

        raid.nextPlayerNid = math.max(tonumber(raid.nextPlayerNid) or 1, tonumber(header.nextPlayerNid) or 1)
        raid.nextBossNid = math.max(tonumber(raid.nextBossNid) or 1, tonumber(header.nextBossNid) or 1)
        raid.nextLootNid = math.max(tonumber(raid.nextLootNid) or 1, tonumber(header.nextLootNid) or 1)

        if Core and Core.StripRuntimeRaidCaches then
            Core.StripRuntimeRaidCaches(raid)
        end
        Core.EnsureRaidSchema(raid)

        return raid
    end

    local function importSnapshotAsNewRaid(snapshot)
        local header = snapshot and snapshot.header
        if not header then
            return nil, nil
        end

        local raidStore = Core.GetRaidStoreOrNil and Core.GetRaidStoreOrNil("DBSyncer.ImportSnapshotAsNewRaid", { "CreateRaidRecord", "InsertRaid" }) or nil
        if not raidStore then
            return nil, nil
        end

        local raid = raidStore:CreateRaidRecord({
            realm = header.realm,
            zone = header.zone,
            size = tonumber(header.size),
            difficulty = tonumber(header.difficulty),
            startTime = tonumber(header.startTime) or Time.GetCurrentTime(),
            endTime = (tonumber(header.endTime) or 0) > 0 and tonumber(header.endTime) or nil,
        })

        raid = applySnapshotToRaid(raid, snapshot, true)
        if not raid then
            return nil, nil
        end

        return raidStore:InsertRaid(raid)
    end

    local function sendAddonPayload(target, payload)
        if target and target ~= "" then
            SendAddonMessage(COMM_PREFIX, payload, "WHISPER", target)
            return
        end

        Comms.Sync(COMM_PREFIX, payload)
    end

    local function buildIncomingSnapshotKey(sender, requestId, mode, raidNid)
        return tostring(sender) .. "|" .. tostring(requestId) .. "|" .. mode .. "|" .. tostring(raidNid)
    end

    local function sendRequest(mode, requestId, raidRef, signature, target)
        signature = signature or {}
        local payload = packFields(
            MSG_REQUEST,
            PROTOCOL_VERSION,
            requestId,
            mode,
            tonumber(raidRef) or 0,
            encodeText(signature.zone),
            tonumber(signature.size) or 0,
            tonumber(signature.diff) or 0
        )
        sendAddonPayload(target, payload)
        addon:debug((Diag.D.LogSyncRequestSent):format(tostring(requestId), tostring(raidRef)))
    end

    local function sendSnapshot(target, requestId, mode, raid)
        local payload = buildSnapshotPayload(raid)
        if not payload then
            return
        end

        local encodedPayload = encodeText(payload)
        local payloadLen = #encodedPayload
        local totalChunks = floor((payloadLen + MAX_CHUNK_SIZE - 1) / MAX_CHUNK_SIZE)
        if totalChunks < 1 then
            totalChunks = 1
        end

        for idx = 1, totalChunks do
            local fromPos = ((idx - 1) * MAX_CHUNK_SIZE) + 1
            local toPos = fromPos + MAX_CHUNK_SIZE - 1
            local chunk = strsub(encodedPayload, fromPos, toPos)
            local msg = packFields(MSG_SNAPSHOT, PROTOCOL_VERSION, requestId, mode, tonumber(raid.raidNid) or 0, idx, totalChunks, chunk)

            sendAddonPayload(target, msg)
        end

        addon:debug((Diag.D.LogSyncSnapshotSent):format(tostring(target or "GROUP"), tostring(requestId), tostring(raid.raidNid), totalChunks, payloadLen))
    end

    local function completeRequest(requestId)
        local pending = module._pendingRequests[requestId]
        if not pending then
            return
        end
        pending.completed = true
        module._pendingRequests[requestId] = nil
    end

    local function shouldAcceptResponseSender(pending, rawSender)
        if type(pending) ~= "table" then
            return false
        end

        local sender = normalizeSender(rawSender) or tostring(rawSender or "")
        if sender == "" then
            return false
        end

        local expectedTarget = normalizeSender(pending.target)
        if expectedTarget and expectedTarget ~= "" then
            if sender ~= expectedTarget then
                return false
            end
            pending.sender = expectedTarget
            return true
        end

        local expectedSender = normalizeSender(pending.sender)
        if expectedSender and expectedSender ~= "" then
            return sender == expectedSender
        end

        pending.sender = sender
        return true
    end

    local function getSenderKey(rawSender)
        local sender = normalizeSender(rawSender) or tostring(rawSender or "")
        if sender == "" then
            return nil
        end
        return sender
    end

    local function markSyncSenderFailed(pending, rawSender)
        if type(pending) ~= "table" then
            return nil
        end
        local sender = getSenderKey(rawSender)
        if not sender then
            return nil
        end
        pending.failedSenders = pending.failedSenders or {}
        pending.failedSenders[sender] = true
        return sender
    end

    local function rejectSyncSender(pending, rawSender, requestId, reason)
        local sender = markSyncSenderFailed(pending, rawSender)
        if not sender then
            sender = getSenderKey(rawSender) or tostring(rawSender or "?")
        end
        addon:debug((Diag.D.LogSyncSyncSenderFailed):format(tostring(sender), tostring(requestId), tostring(reason)))
    end

    local function finalizeSnapshotFailure(isSync, pending, sender, requestId, reason)
        if isSync then
            rejectSyncSender(pending, sender, requestId, reason)
            return
        end
        completeRequest(requestId)
    end

    local function isSyncSenderFailed(pending, rawSender)
        if type(pending) ~= "table" then
            return false
        end
        local sender = getSenderKey(rawSender)
        if not sender then
            return false
        end
        local failedSenders = pending.failedSenders
        return type(failedSenders) == "table" and failedSenders[sender] == true
    end

    local function isAuthorizedSyncResponder(rawSender, pending)
        if not addon.IsInRaid() then
            return true
        end
        local sender = getSenderKey(rawSender)
        if not sender then
            return false
        end

        local count = tonumber(GetNumRaidMembers and GetNumRaidMembers()) or 0
        for i = 1, count do
            local name, rank = GetRaidRosterInfo(i)
            local rosterName = getSenderKey(name)
            if rosterName and rosterName == sender then
                return (tonumber(rank) or 0) > 0
            end
        end

        local createdAt = tonumber(type(pending) == "table" and pending.createdAt) or 0
        if createdAt > 0 and (nowSec() - createdAt) <= SYNC_OFFICER_LOOKUP_GRACE_SECONDS then
            return true
        end
        return false
    end

    local function warnSyncSenderNotOfficer(pending, requestId, rawSender)
        if type(pending) ~= "table" then
            return
        end
        local sender = getSenderKey(rawSender) or tostring(rawSender or "?")
        pending.unauthorizedSenders = pending.unauthorizedSenders or {}
        if pending.unauthorizedSenders[sender] then
            return
        end
        pending.unauthorizedSenders[sender] = true
        addon:warn((Diag.W.LogSyncSenderNotOfficer):format(tostring(sender), tostring(requestId)))
    end

    local function isSyncSenderUnauthorized(pending, rawSender)
        if type(pending) ~= "table" then
            return false
        end
        local sender = getSenderKey(rawSender)
        if not sender then
            return false
        end
        local unauthorizedSenders = pending.unauthorizedSenders
        return type(unauthorizedSenders) == "table" and unauthorizedSenders[sender] == true
    end

    local function handleIncomingRequest(rawSender, channel, requestId, mode, raidRef, signature)
        if not canAnswerRequests(channel) then
            return
        end

        local allowed, sender = allowIncomingRequest(rawSender)
        if not allowed then
            return
        end

        local raid = nil
        if mode == MODE_REQ then
            raid = select(1, resolveRaidByReference(raidRef, false))
        elseif mode == MODE_SYNC then
            raid = select(1, getCurrentRaidRecord())
            if raid and not raidMatchesSignature(raid, signature) then
                raid = nil
            end
        end

        if not raid then
            return
        end

        addon:debug((Diag.D.LogSyncRequestReceived):format(tostring(sender), tostring(requestId), tostring(raidRef)))
        sendSnapshot(rawSender, requestId, mode, raid)
    end

    local function refreshLoggerUi(focusRaidId)
        local selectedRaid = tonumber(focusRaidId) or tonumber(addon.State and addon.State.selectedRaid) or tonumber(Core.GetCurrentRaid())
        Bus.TriggerEvent(InternalEvents.LoggerSelectRaid, selectedRaid, "sync")
    end

    local function onSnapshotReady(sender, requestId, mode, snapshot)
        if mode == MODE_SYNC then
            local currentRaid, currentId = getCurrentRaidRecord()
            local pending = module._pendingRequests[requestId]
            if not currentRaid then
                addon:warn(L.MsgLoggerSyncNoCurrent)
                completeRequest(requestId)
                return
            end
            if not raidMatchesSnapshotHeader(currentRaid, snapshot.header) then
                rejectSyncSender(pending, sender, requestId, "raid_mismatch")
                return
            end

            local ok, raid = pcall(applySnapshotToRaid, currentRaid, snapshot, false)
            if not ok or not raid then
                addon:error((Diag.E.LogSyncMergeFailed):format(tostring(sender), tostring(requestId), tostring(snapshot.header.raidNid), tostring(raid)))
                rejectSyncSender(pending, sender, requestId, "merge_failed")
                return
            end

            addon:info(L.MsgLoggerSyncApplied:format(tonumber(currentId) or 0, tostring(sender)))
            addon:debug((Diag.D.LogSyncMergeApplied):format(tonumber(raid.raidNid) or 0, tonumber(currentId) or 0, tostring(sender), #(raid.bossKills or {}), #(raid.loot or {})))

            cleanupIncomingByRequest(requestId, MODE_SYNC)
            completeRequest(requestId)
            refreshLoggerUi(currentId)
            return
        end

        local ok, raid, raidId = pcall(importSnapshotAsNewRaid, snapshot)
        if not ok or not raid then
            addon:error((Diag.E.LogSyncMergeFailed):format(tostring(sender), tostring(requestId), tostring(snapshot.header.raidNid), tostring(raid)))
            completeRequest(requestId)
            return
        end

        if mode == MODE_PUSH then
            addon:info(L.MsgLoggerPushImported:format(tostring(sender), tonumber(raidId) or 0))
        else
            addon:info(L.MsgLoggerReqImported:format(tostring(sender), tonumber(raidId) or 0))
            completeRequest(requestId)
        end

        addon:debug((Diag.D.LogSyncMergeApplied):format(tonumber(raid.raidNid) or 0, tonumber(raidId) or 0, tostring(sender), #(raid.bossKills or {}), #(raid.loot or {})))

        refreshLoggerUi(raidId)
    end

    local function shouldIgnoreSnapshotSender(sender, requestId, mode, raidNid, pending, isPush, isSync)
        if isPush then
            return false
        end

        if not pending or pending.completed or pending.mode ~= mode then
            addon:debug((Diag.D.LogSyncChunkIgnored):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            return true
        end

        if isSync and isSyncSenderFailed(pending, sender) then
            addon:debug((Diag.D.LogSyncChunkIgnored):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            return true
        end

        local expectedTarget = normalizeSender(pending.target)
        if expectedTarget and expectedTarget ~= "" and not shouldAcceptResponseSender(pending, sender) then
            addon:debug((Diag.D.LogSyncChunkIgnored):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            return true
        end

        return false
    end

    local function getOrCreateIncomingSnapshotState(sender, requestId, mode, raidNid, partCount, pending, isSync)
        local key = buildIncomingSnapshotKey(sender, requestId, mode, raidNid)
        local state = module._incoming[key]
        if state then
            return key, state
        end

        if isSync and isSyncSenderUnauthorized(pending, sender) then
            addon:debug((Diag.D.LogSyncChunkIgnored):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            return key, nil
        end
        if isSync and not isAuthorizedSyncResponder(sender, pending) then
            warnSyncSenderNotOfficer(pending, requestId, sender)
            addon:debug((Diag.D.LogSyncChunkIgnored):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            return key, nil
        end

        state = {
            createdAt = nowSec(),
            sender = sender,
            requestId = requestId,
            mode = mode,
            raidNid = raidNid,
            total = partCount,
            got = 0,
            parts = {},
        }
        module._incoming[key] = state
        return key, state
    end

    local function handleIncomingSnapshot(sender, requestId, mode, raidNid, partIndex, partCount, chunkData)
        local pending = module._pendingRequests[requestId]
        local isPush = (mode == MODE_PUSH)
        local isSync = (mode == MODE_SYNC)

        if shouldIgnoreSnapshotSender(sender, requestId, mode, raidNid, pending, isPush, isSync) then
            return
        end

        if partIndex < 1 or partCount < 1 or partIndex > partCount then
            addon:warn((Diag.W.LogSyncChunkMalformed):format(tostring(sender), tostring(requestId), tostring(partIndex), tostring(partCount)))
            return
        end

        local key, state = getOrCreateIncomingSnapshotState(sender, requestId, mode, raidNid, partCount, pending, isSync)
        if not state then
            return
        end

        if state.total ~= partCount then
            addon:warn((Diag.W.LogSyncChunkPartCountChanged):format(tostring(sender), tostring(requestId), tostring(raidNid), tonumber(state.total) or 0, tonumber(partCount) or 0))
            state.total = partCount
            state.got = 0
            state.parts = {}
            state.createdAt = nowSec()
        end

        if state.parts[partIndex] == nil then
            state.parts[partIndex] = chunkData or ""
            state.got = state.got + 1
        end

        addon:debug((Diag.D.LogSyncChunkReceived):format(tostring(sender), tostring(requestId), partIndex, partCount))

        if state.got < state.total then
            return
        end

        local ordered = {}
        for i = 1, state.total do
            local piece = state.parts[i]
            if piece == nil then
                module._incoming[key] = nil
                return
            end
            ordered[i] = piece
        end
        module._incoming[key] = nil

        local encodedPayload = tconcat(ordered, "")
        local payload = decodeText(encodedPayload)
        if payload == nil then
            addon:warn((Diag.W.LogSyncDecodeFailed):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            finalizeSnapshotFailure(isSync, pending, sender, requestId, "decode_failed")
            return
        end

        local snapshot = parseSnapshotPayload(payload)
        if not snapshot then
            addon:warn((Diag.W.LogSyncParseFailed):format(tostring(sender), tostring(requestId), tostring(raidNid)))
            finalizeSnapshotFailure(isSync, pending, sender, requestId, "parse_failed")
            return
        end

        if tonumber(snapshot.header.protocolVersion) ~= PROTOCOL_VERSION then
            addon:debug((Diag.D.LogSyncVersionMismatch):format(tostring(sender), tostring(snapshot.header.protocolVersion), PROTOCOL_VERSION))
            finalizeSnapshotFailure(isSync, pending, sender, requestId, "version_mismatch")
            return
        end

        onSnapshotReady(sender, requestId, mode, snapshot)
    end

    -- ----- Public methods ----- --
    function module:GetPrefix()
        return COMM_PREFIX
    end

    function module:RequestLoggerReq(raidRef, targetName)
        if not ensureGroupSyncAvailable() then
            return false
        end

        local requestRef = tonumber(raidRef)
        if not requestRef or requestRef <= 0 then
            addon:warn(L.MsgLoggerSyncRaidRefRequired)
            return false
        end

        local target = resolveExternalTarget(targetName)
        if not target then
            return false
        end

        local requestId = nextRequestId(self)

        trackPendingRequest(self, requestId, {
            createdAt = nowSec(),
            mode = MODE_REQ,
            raidRef = requestRef,
            target = target,
            sender = target,
            completed = false,
        })

        sendRequest(MODE_REQ, requestId, requestRef, nil, target)
        addon:info(L.MsgLoggerReqSent:format(tostring(requestRef), tostring(target)))
        return true
    end

    function module:BroadcastLoggerPush(raidRef, targetName)
        if not ensureGroupSyncAvailable() then
            return false
        end

        local raidRefNum = tonumber(raidRef)
        if not raidRefNum or raidRefNum <= 0 then
            addon:warn(L.MsgLoggerSyncRaidRefRequired)
            return false
        end

        local target = resolveExternalTarget(targetName)
        if not target then
            return false
        end

        local raid = select(1, resolveRaidByReference(raidRefNum, false))
        if not raid then
            addon:warn(L.MsgLoggerSyncNoRaid)
            return false
        end

        local requestId = nextRequestId(self)

        sendSnapshot(target, requestId, MODE_PUSH, raid)
        addon:info(L.MsgLoggerSyncPushSent:format(tostring(tonumber(raid.raidNid) or raidRefNum), tostring(target)))
        return true
    end

    function module:RequestLoggerSync()
        if not ensureGroupSyncAvailable() then
            return false
        end

        local currentRaid, currentRaidId = getCurrentRaidRecord()
        if not currentRaid then
            addon:warn(L.MsgLoggerSyncNoCurrent)
            return false
        end

        local signature = buildSignatureFromRaid(currentRaid)
        local requestId = nextRequestId(self)

        trackPendingRequest(self, requestId, {
            createdAt = nowSec(),
            mode = MODE_SYNC,
            signature = signature,
            sender = nil,
            failedSenders = {},
            unauthorizedSenders = {},
            completed = false,
        })

        sendRequest(MODE_SYNC, requestId, tonumber(currentRaid.raidNid) or 0, signature)
        addon:info(L.MsgLoggerSyncSent:format(tonumber(currentRaidId) or 0))
        return true
    end

    function module:OnAddonMessage(prefix, msg, channel, sender)
        if prefix ~= COMM_PREFIX then
            return
        end
        if isSelfSender(sender) then
            return
        end
        if type(msg) ~= "string" or msg == "" then
            return
        end

        cleanupExpiredState()

        local fields, n = splitFields(msg, FIELD_SEP)
        if n < 4 then
            return
        end

        local kind = fields[1]
        local version = parseNumber(fields[2], 0)
        if version ~= PROTOCOL_VERSION then
            addon:debug((Diag.D.LogSyncVersionMismatch):format(tostring(sender), tostring(version), PROTOCOL_VERSION))
            return
        end

        local requestId = tostring(fields[3] or "")
        if requestId == "" then
            return
        end

        if kind == MSG_REQUEST and n >= 8 then
            local mode = tostring(fields[4] or "")
            if mode ~= MODE_REQ and mode ~= MODE_SYNC then
                return
            end

            local raidRef = parseNumber(fields[5], 0)
            local zone = decodeText(fields[6])
            if zone == nil then
                return
            end

            local signature = {
                zone = zone,
                size = parseNumber(fields[7], 0),
                diff = parseNumber(fields[8], 0),
            }

            handleIncomingRequest(sender, channel, requestId, mode, raidRef, signature)
            return
        end

        if kind == MSG_SNAPSHOT and n >= 8 then
            local mode = tostring(fields[4] or "")
            if mode ~= MODE_REQ and mode ~= MODE_PUSH and mode ~= MODE_SYNC then
                return
            end

            local raidNid = parseNumber(fields[5], nil)
            local partIndex = parseNumber(fields[6], 0)
            local partCount = parseNumber(fields[7], 0)
            local chunkData = fields[8] or ""
            if not raidNid then
                return
            end

            local senderName = normalizeSender(sender) or tostring(sender)
            handleIncomingSnapshot(senderName, requestId, mode, raidNid, partIndex, partCount, chunkData)
        end
    end
end
