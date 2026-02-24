-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local Events = feature.Events or addon.Events or {}
local Core = feature.Core
local Bus = feature.Bus or addon.Bus
local Strings = feature.Strings or addon.Strings
local Base64 = feature.Base64 or addon.Base64
local Time = feature.Time or addon.Time
local Comms = feature.Comms or addon.Comms

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
    addon.Services = addon.Services or {}
    addon.Services.Syncer = addon.Services.Syncer or {}
    addon.Syncer = addon.Services.Syncer -- Legacy alias during namespacing migration.
    local module = addon.Services.Syncer

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

    module._incoming = module._incoming or {}
    module._pendingRequests = module._pendingRequests or {}
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
        if type(sender) ~= "string" then return nil end
        local short = sender:match("^([^%-]+)") or sender
        return Strings.normalizeName(short, true) or short
    end

    local function isSelfSender(sender)
        local selfName = Core.getPlayerName()
        if not selfName then
            return false
        end
        local a = Strings.normalizeLower(selfName, true)
        local b = Strings.normalizeLower(normalizeSender(sender), true)
        return (a ~= nil and b ~= nil and a == b)
    end

    local function encodeText(value)
        local input = tostring(value or "")
        local ok, out = pcall(Base64.encode, input)
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
        local ok, out = pcall(Base64.decode, input)
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

    local function joinNameList(names)
        if type(names) ~= "table" or #names == 0 then
            return ""
        end
        local out = {}
        for i = 1, #names do
            out[i] = tostring(names[i] or "")
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

        local leaderFn = addon.UnitIsGroupLeader
        local assistantFn = addon.UnitIsGroupAssistant
        local isLeader = leaderFn and leaderFn("player")
        local isAssistant = assistantFn and assistantFn("player")
        return (isLeader or isAssistant) and true or false
    end

    local function normalizeTargetName(raw)
        local text = Strings.trimText(raw or "")
        if text == "" then
            return nil
        end
        return Strings.normalizeName(text, true) or text
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

        Core.ensureRaidSchema(raid)

        local lines = {}
        local schemaVersion = tonumber(raid.schemaVersion)
            or tonumber(Core.getRaidSchemaVersion and Core.getRaidSchemaVersion())
            or 1

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
                encodeText(joinNameList(b.players))
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
                encodeText(loot.looter),
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
            lines[#lines + 1] = packFields(
                "C",
                encodeText(name),
                encodeText(changes[name])
            )
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
                local looter = decodeText(f[10])
                if itemName == nil or itemString == nil or itemLink == nil then
                    return nil
                end
                if itemTexture == nil or looter == nil then
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
                    looter = looter,
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

    local function copyUniqueNames(names)
        local out = {}
        local seen = {}
        if type(names) ~= "table" then
            return out
        end
        for i = 1, #names do
            local raw = names[i]
            local normalized = Strings.normalizeName(raw, true)
            local name = normalized or tostring(raw or "")
            if name ~= "" and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
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
        local currentId = Core.getCurrentRaid()
        if not currentId then
            return nil, nil
        end
        return Core.ensureRaidById(currentId), currentId
    end

    local function resolveRaidByReference(raidRef, allowFallback)
        local n = tonumber(raidRef)
        if n and n > 0 then
            local byId, byIdIndex = Core.ensureRaidById(n)
            if byId then
                return byId, byIdIndex
            end

            local byNid, byNidIndex = Core.ensureRaidByNid(n)
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
            local raid = Core.ensureRaidById(selectedRaid)
            if raid then
                return raid, selectedRaid
            end
        end

        local currentRaid = Core.getCurrentRaid()
        if currentRaid then
            return Core.ensureRaidById(currentRaid), currentRaid
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
                if count < 0 then count = 0 end
                dst.playerNid = nid
                dst.name = Strings.normalizeName(src.name, true) or src.name or dst.name
                dst.rank = tonumber(src.rank) or 0
                dst.subgroup = tonumber(src.subgroup) or 1
                dst.class = (src.class and src.class ~= "") and src.class or "UNKNOWN"
                dst.join = tonumber(src.join) or dst.join
                local leave = tonumber(src.leave) or 0
                dst.leave = (leave > 0) and leave or nil
                dst.count = count
            end
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
                dst.players = copyUniqueNames(src.players)
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
                if count < 1 then count = 1 end
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
                dst.looter = Strings.normalizeName(src.looter, true) or src.looter or dst.looter
                dst.rollType = tonumber(src.rollType) or 0
                dst.rollValue = tonumber(src.rollValue) or 0
                dst.bossNid = tonumber(src.bossNid) or 0
                dst.time = tonumber(src.time) or dst.time
            end
        end

        raid.changes = raid.changes or {}
        for name, spec in pairs(snapshot.changes or {}) do
            local normalizedName = Strings.normalizeName(name, true) or name
            if normalizedName and normalizedName ~= "" then
                local normalizedSpec = Strings.normalizeName(spec, true)
                raid.changes[normalizedName] = (normalizedSpec and normalizedSpec ~= "") and normalizedSpec or nil
            end
        end

        raid.nextPlayerNid = math.max(
            tonumber(raid.nextPlayerNid) or 1,
            tonumber(header.nextPlayerNid) or 1
        )
        raid.nextBossNid = math.max(
            tonumber(raid.nextBossNid) or 1,
            tonumber(header.nextBossNid) or 1
        )
        raid.nextLootNid = math.max(
            tonumber(raid.nextLootNid) or 1,
            tonumber(header.nextLootNid) or 1
        )

        Core.ensureRaidSchema(raid)

        return raid
    end

    local function importSnapshotAsNewRaid(snapshot)
        local header = snapshot and snapshot.header
        if not header then
            return nil, nil
        end

        local raid = Core.createRaidRecord({
            realm = header.realm,
            zone = header.zone,
            size = tonumber(header.size),
            difficulty = tonumber(header.difficulty),
            startTime = tonumber(header.startTime) or Time.getCurrentTime(),
            endTime = (tonumber(header.endTime) or 0) > 0 and tonumber(header.endTime) or nil,
        })

        raid = applySnapshotToRaid(raid, snapshot, true)
        if not raid then
            return nil, nil
        end

        tinsert(KRT_Raids, raid)
        local raidId = #KRT_Raids
        local outRaid = Core.ensureRaidById(raidId)
        return outRaid, raidId
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
        if target and target ~= "" then
            SendAddonMessage(COMM_PREFIX, payload, "WHISPER", target)
        else
            Comms.sync(COMM_PREFIX, payload)
        end
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
            local msg = packFields(
                MSG_SNAPSHOT,
                PROTOCOL_VERSION,
                requestId,
                mode,
                tonumber(raid.raidNid) or 0,
                idx,
                totalChunks,
                chunk
            )

            if target and target ~= "" then
                SendAddonMessage(COMM_PREFIX, msg, "WHISPER", target)
            else
                Comms.sync(COMM_PREFIX, msg)
            end
        end

        addon:debug((Diag.D.LogSyncSnapshotSent):format(
            tostring(target or "GROUP"), tostring(requestId), tostring(raid.raidNid), totalChunks, payloadLen
        ))
    end

    local function completeRequest(requestId)
        local pending = module._pendingRequests[requestId]
        if not pending then
            return
        end
        pending.completed = true
        module._pendingRequests[requestId] = nil
    end

    local function handleIncomingRequest(rawSender, channel, requestId, mode, raidRef, signature)
        if not canAnswerRequests(channel) then
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

        local sender = normalizeSender(rawSender) or tostring(rawSender)
        addon:debug((Diag.D.LogSyncRequestReceived):format(
            tostring(sender), tostring(requestId), tostring(raidRef)
        ))
        sendSnapshot(rawSender, requestId, mode, raid)
    end

    local function refreshLoggerUi(focusRaidId)
        local selectedRaid = tonumber(focusRaidId)
            or tonumber(addon.State and addon.State.selectedRaid)
            or tonumber(Core.getCurrentRaid())
        Bus.triggerEvent(InternalEvents.LoggerSelectRaid, selectedRaid, "sync")
    end

    local function onSnapshotReady(sender, requestId, mode, snapshot)
        if mode == MODE_SYNC then
            local currentRaid, currentId = getCurrentRaidRecord()
            if not currentRaid then
                addon:warn(L.MsgLoggerSyncNoCurrent)
                completeRequest(requestId)
                return
            end
            if not raidMatchesSnapshotHeader(currentRaid, snapshot.header) then
                addon:warn(L.MsgLoggerSyncRaidMismatch)
                completeRequest(requestId)
                return
            end

            local ok, raid = pcall(applySnapshotToRaid, currentRaid, snapshot, false)
            if not ok or not raid then
                addon:error((Diag.E.LogSyncMergeFailed):format(
                    tostring(sender), tostring(requestId), tostring(snapshot.header.raidNid), tostring(raid)
                ))
                completeRequest(requestId)
                return
            end

            addon:info(L.MsgLoggerSyncApplied:format(tonumber(currentId) or 0, tostring(sender)))
            addon:debug((Diag.D.LogSyncMergeApplied):format(
                tonumber(raid.raidNid) or 0,
                tonumber(currentId) or 0,
                tostring(sender),
                #(raid.bossKills or {}),
                #(raid.loot or {})
            ))

            completeRequest(requestId)
            refreshLoggerUi(currentId)
            return
        end

        local ok, raid, raidId = pcall(importSnapshotAsNewRaid, snapshot)
        if not ok or not raid then
            addon:error((Diag.E.LogSyncMergeFailed):format(
                tostring(sender), tostring(requestId), tostring(snapshot.header.raidNid), tostring(raid)
            ))
            completeRequest(requestId)
            return
        end

        if mode == MODE_PUSH then
            addon:info(L.MsgLoggerPushImported:format(tostring(sender), tonumber(raidId) or 0))
        else
            addon:info(L.MsgLoggerReqImported:format(tostring(sender), tonumber(raidId) or 0))
            completeRequest(requestId)
        end

        addon:debug((Diag.D.LogSyncMergeApplied):format(
            tonumber(raid.raidNid) or 0,
            tonumber(raidId) or 0,
            tostring(sender),
            #(raid.bossKills or {}),
            #(raid.loot or {})
        ))

        refreshLoggerUi(raidId)
    end

    local function handleIncomingSnapshot(sender, requestId, mode, raidNid, partIndex, partCount, chunkData)
        local pending = module._pendingRequests[requestId]
        local isPush = (mode == MODE_PUSH)

        if not isPush then
            if not pending or pending.completed or pending.mode ~= mode then
                addon:debug((Diag.D.LogSyncChunkIgnored):format(
                    tostring(sender), tostring(requestId), tostring(raidNid)
                ))
                return
            end
        end

        if partIndex < 1 or partCount < 1 or partIndex > partCount then
            addon:warn((Diag.W.LogSyncChunkMalformed):format(
                tostring(sender), tostring(requestId), tostring(partIndex), tostring(partCount)
            ))
            return
        end

        local key = tostring(sender) .. "|" .. tostring(requestId) .. "|" .. mode .. "|" .. tostring(raidNid)
        local state = module._incoming[key]
        if not state then
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
        end

        if state.total ~= partCount then
            state.total = partCount
            state.got = 0
            state.parts = {}
            state.createdAt = nowSec()
        end

        if state.parts[partIndex] == nil then
            state.parts[partIndex] = chunkData or ""
            state.got = state.got + 1
        end

        addon:debug((Diag.D.LogSyncChunkReceived):format(
            tostring(sender), tostring(requestId), partIndex, partCount
        ))

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
            addon:warn((Diag.W.LogSyncDecodeFailed):format(
                tostring(sender), tostring(requestId), tostring(raidNid)
            ))
            completeRequest(requestId)
            return
        end

        local snapshot = parseSnapshotPayload(payload)
        if not snapshot then
            addon:warn((Diag.W.LogSyncParseFailed):format(
                tostring(sender), tostring(requestId), tostring(raidNid)
            ))
            completeRequest(requestId)
            return
        end

        if tonumber(snapshot.header.protocolVersion) ~= PROTOCOL_VERSION then
            addon:debug((Diag.D.LogSyncVersionMismatch):format(
                tostring(sender), tostring(snapshot.header.protocolVersion), PROTOCOL_VERSION
            ))
            completeRequest(requestId)
            return
        end

        onSnapshotReady(sender, requestId, mode, snapshot)
    end

    -- ----- Public methods ----- --
    function module:GetPrefix()
        return COMM_PREFIX
    end

    function module:RequestLoggerReq(raidRef, targetName)
        cleanupExpiredState()

        if not addon.IsInGroup() then
            addon:warn(L.MsgLoggerSyncNotInGroup)
            return false
        end

        local requestRef = tonumber(raidRef)
        if not requestRef or requestRef <= 0 then
            addon:warn(L.MsgLoggerSyncRaidRefRequired)
            return false
        end

        local target = normalizeTargetName(targetName)
        if not target then
            addon:warn(L.MsgLoggerSyncTargetRequired)
            return false
        end
        if isSelfSender(target) then
            addon:warn(L.MsgLoggerSyncTargetSelf)
            return false
        end

        self._nextRequestId = (tonumber(self._nextRequestId) or 0) + 1
        local requestId = tostring(self._nextRequestId)

        self._pendingRequests[requestId] = {
            createdAt = nowSec(),
            mode = MODE_REQ,
            raidRef = requestRef,
            target = target,
            completed = false,
        }

        sendRequest(MODE_REQ, requestId, requestRef, nil, target)
        addon:info(L.MsgLoggerReqSent:format(tostring(requestRef), tostring(target)))
        return true
    end

    function module:BroadcastLoggerPush(raidRef, targetName)
        cleanupExpiredState()

        if not addon.IsInGroup() then
            addon:warn(L.MsgLoggerSyncNotInGroup)
            return false
        end

        local raidRefNum = tonumber(raidRef)
        if not raidRefNum or raidRefNum <= 0 then
            addon:warn(L.MsgLoggerSyncRaidRefRequired)
            return false
        end

        local target = normalizeTargetName(targetName)
        if not target then
            addon:warn(L.MsgLoggerSyncTargetRequired)
            return false
        end
        if isSelfSender(target) then
            addon:warn(L.MsgLoggerSyncTargetSelf)
            return false
        end

        local raid = select(1, resolveRaidByReference(raidRefNum, false))
        if not raid then
            addon:warn(L.MsgLoggerSyncNoRaid)
            return false
        end

        self._nextRequestId = (tonumber(self._nextRequestId) or 0) + 1
        local requestId = tostring(self._nextRequestId)

        sendSnapshot(target, requestId, MODE_PUSH, raid)
        addon:info(L.MsgLoggerSyncPushSent:format(tostring(tonumber(raid.raidNid) or raidRefNum), tostring(target)))
        return true
    end

    function module:RequestLoggerSync()
        cleanupExpiredState()

        if not addon.IsInGroup() then
            addon:warn(L.MsgLoggerSyncNotInGroup)
            return false
        end

        local currentRaid, currentRaidId = getCurrentRaidRecord()
        if not currentRaid then
            addon:warn(L.MsgLoggerSyncNoCurrent)
            return false
        end

        local signature = buildSignatureFromRaid(currentRaid)
        self._nextRequestId = (tonumber(self._nextRequestId) or 0) + 1
        local requestId = tostring(self._nextRequestId)

        self._pendingRequests[requestId] = {
            createdAt = nowSec(),
            mode = MODE_SYNC,
            signature = signature,
            completed = false,
        }

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
            addon:debug((Diag.D.LogSyncVersionMismatch):format(
                tostring(sender), tostring(version), PROTOCOL_VERSION
            ))
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
