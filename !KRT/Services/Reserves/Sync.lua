-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.Services.Reserves._Sync
-- events: handles KRTResSync addon-message traffic

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Base64 = feature.Base64 or addon.Base64
local Comms = feature.Comms or addon.Comms
local Services = feature.Services or addon.Services
local Strings = feature.Strings or addon.Strings

local floor = math.floor
local sort = table.sort
local tconcat = table.concat
local pairs, tostring, tonumber, type = pairs, tostring, tonumber, type
local _G = _G

addon.Services = addon.Services or {}
addon.Services.Reserves = addon.Services.Reserves or {}

-- ----- Internal state ----- --
local module = addon.Services.Reserves
module._Sync = module._Sync or {}

local Sync = module._Sync

local PREFIX = "KRTResSync"
local FIELD_SEP = "|"
local MSG_META_REQ = "META_REQ"
local MSG_META_ACK = "META_ACK"
local MSG_DATA_REQ = "DATA_REQ"
local MSG_DATA_CHUNK = "DATA_CHUNK"
local MSG_DATA_DONE = "DATA_DONE"
local MSG_DATA_ERR = "DATA_ERR"
local MAX_CHUNK_SIZE = 180

Sync._incoming = Sync._incoming or {}
Sync._nextRequestId = Sync._nextRequestId or 0

-- ----- Private helpers ----- --
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

local function splitFields(text, out)
    local fields = out or {}
    local n = 0
    local startPos = 1
    local input = tostring(text or "")

    while true do
        local fromPos, toPos = input:find(FIELD_SEP, startPos, true)
        if not fromPos then
            n = n + 1
            fields[n] = input:sub(startPos)
            break
        end
        n = n + 1
        fields[n] = input:sub(startPos, fromPos - 1)
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

local function normalizeSender(sender)
    local name = tostring(sender or "")
    local normalized = Strings and Strings.NormalizeName and Strings.NormalizeName(name, true) or name
    return normalized or name
end

local function getReservesService()
    return Services and Services.Reserves or module
end

local function canProvideReserves()
    local service = getReservesService()
    if not (service and service.IsLocalDataAvailable and service:IsLocalDataAvailable()) then
        return false
    end

    local raid = Services and Services.Raid or nil
    if not (raid and raid.GetPlayerRoleState) then
        return true
    end

    local role = raid:GetPlayerRoleState() or {}
    return role.isMasterLooter == true or role.isLeader == true or role.isAssistant == true
end

local function nextRequestId()
    Sync._nextRequestId = (tonumber(Sync._nextRequestId) or 0) + 1
    return tostring(Sync._nextRequestId)
end

local function sendWhisper(target, msg)
    SendAddonMessage(PREFIX, msg, "WHISPER", target)
end

local function sendError(target, reason)
    sendWhisper(target, packFields(MSG_DATA_ERR, tostring(reason or "unknown")))
end

local function shouldRequestRemoteData(remoteChecksum)
    local checksum = tostring(remoteChecksum or "")
    if checksum == "" then
        return false
    end

    local service = getReservesService()
    if service and service.IsLocalDataAvailable and service:IsLocalDataAvailable() then
        return false
    end

    local localMeta = service and service.GetSyncMetadata and service:GetSyncMetadata() or nil
    return not (localMeta and localMeta.checksum == checksum)
end

local function requestDataFrom(target, requestId, checksum)
    if target == "" then
        return false
    end
    sendWhisper(target, packFields(MSG_DATA_REQ, requestId, checksum or ""))
    addon:info(L.MsgReservesSyncDataRequested)
    return true
end

local function sortedPlayerKeys(data)
    local keys = {}
    for key in pairs(data or {}) do
        keys[#keys + 1] = key
    end
    sort(keys)
    return keys
end

local function buildPayload(data, mode)
    local lines = { packFields("H", mode or "multi") }
    local keys = sortedPlayerKeys(data)

    for i = 1, #keys do
        local playerKey = keys[i]
        local player = data[playerKey]
        if type(player) == "table" and type(player.reserves) == "table" then
            local playerName = player.playerNameDisplay or player.original or playerKey
            for j = 1, #player.reserves do
                local row = player.reserves[j]
                if type(row) == "table" and row.rawID then
                    lines[#lines + 1] = packFields(
                        "R",
                        encodeText(playerName),
                        tonumber(row.rawID) or 0,
                        tonumber(row.quantity) or 1,
                        tonumber(row.plus) or 0,
                        encodeText(row.class),
                        encodeText(row.spec),
                        encodeText(row.note),
                        encodeText(row.source)
                    )
                end
            end
        end
    end

    return tconcat(lines, "\n")
end

local function parsePayload(payload)
    local reserves = {}
    local mode = "multi"
    local fields = {}

    for line in tostring(payload or ""):gmatch("[^\n]+") do
        splitFields(line, fields)
        if fields[1] == "H" then
            mode = (fields[2] == "plus") and "plus" or "multi"
        elseif fields[1] == "R" then
            local playerName = decodeText(fields[2])
            local itemId = tonumber(fields[3])
            if playerName and playerName ~= "" and itemId and itemId > 0 then
                local playerKey = Strings and Strings.NormalizeLower and Strings.NormalizeLower(playerName, true) or playerName
                local container = reserves[playerKey]
                if not container then
                    container = {
                        playerNameDisplay = playerName,
                        reserves = {},
                    }
                    reserves[playerKey] = container
                end
                container.reserves[#container.reserves + 1] = {
                    rawID = itemId,
                    quantity = tonumber(fields[4]) or 1,
                    plus = tonumber(fields[5]) or 0,
                    class = decodeText(fields[6]),
                    spec = decodeText(fields[7]),
                    note = decodeText(fields[8]),
                    source = decodeText(fields[9]),
                }
            end
        end
    end

    return reserves, mode
end

local function getLocalPayload()
    local service = getReservesService()
    local data, meta = service:GetSyncPayload()
    local payload = buildPayload(data, meta and meta.mode or "multi")
    return payload, meta
end

local function sendMetadata(target, requestId)
    if not canProvideReserves() then
        sendWhisper(target, packFields(MSG_DATA_ERR, requestId, "no_data"))
        return false
    end

    local _, meta = getLocalPayload()
    sendWhisper(
        target,
        packFields(
            MSG_META_ACK,
            requestId,
            meta and meta.checksum or "",
            meta and meta.mode or "multi",
            meta and meta.players or 0,
            meta and meta.entries or 0,
            normalizeSender(UnitName and UnitName("player") or "")
        )
    )
    return true
end

local function sendData(target, requestId)
    if not canProvideReserves() then
        sendError(target, "no_data")
        return false
    end

    local payload, meta = getLocalPayload()
    local encoded = encodeText(payload)
    local payloadLen = #encoded
    local totalChunks = floor((payloadLen + MAX_CHUNK_SIZE - 1) / MAX_CHUNK_SIZE)
    if totalChunks < 1 then
        totalChunks = 1
    end

    for idx = 1, totalChunks do
        local fromPos = ((idx - 1) * MAX_CHUNK_SIZE) + 1
        local toPos = fromPos + MAX_CHUNK_SIZE - 1
        local chunk = encoded:sub(fromPos, toPos)
        sendWhisper(target, packFields(MSG_DATA_CHUNK, requestId, idx, totalChunks, chunk))
    end

    sendWhisper(target, packFields(MSG_DATA_DONE, requestId, meta and meta.checksum or ""))
    return true
end

local function applyIncoming(sender, requestId, checksum)
    local key = tostring(sender or "?") .. ":" .. tostring(requestId or "")
    local pending = Sync._incoming[key]
    if type(pending) ~= "table" then
        return false, "missing_request"
    end

    local parts = {}
    for i = 1, tonumber(pending.total) or 0 do
        if pending.chunks[i] == nil then
            return false, "missing_chunk"
        end
        parts[i] = pending.chunks[i]
    end

    local payload = decodeText(tconcat(parts, ""))
    if not payload then
        return false, "decode_failed"
    end

    local reserves, mode = parsePayload(payload)
    local service = getReservesService()
    local ok, reason = service:SetSyncedReservesData(reserves, {
        source = sender,
        checksum = checksum,
        mode = mode,
    })
    Sync._incoming[key] = nil
    return ok, reason
end

-- ----- Public methods ----- --
function Sync:GetPrefix()
    return PREFIX
end

function Sync:EnsurePrefix()
    if _G.RegisterAddonMessagePrefix then
        _G.RegisterAddonMessagePrefix(PREFIX)
    end
end

function Sync:RequestMetadata()
    self:EnsurePrefix()
    local requestId = nextRequestId()
    local ok = Comms and Comms.Sync and Comms.Sync(PREFIX, packFields(MSG_META_REQ, requestId))
    if ok == false then
        addon:warn(L.MsgReservesSyncNotInGroup)
        return false
    end
    addon:info(L.MsgReservesSyncRequested)
    return true
end

function Sync:RequestData(checksum)
    self:EnsurePrefix()
    local requestId = nextRequestId()
    local ok = Comms and Comms.Sync and Comms.Sync(PREFIX, packFields(MSG_DATA_REQ, requestId, checksum or ""))
    if ok == false then
        addon:warn(L.MsgReservesSyncNotInGroup)
        return false
    end
    addon:info(L.MsgReservesSyncDataRequested)
    return true
end

function Sync:RequestMessageHandling(prefix, msg, channel, sender)
    if prefix ~= PREFIX then
        return false
    end

    local fields = {}
    splitFields(msg, fields)
    local kind = fields[1]
    local requestId = fields[2]
    local source = normalizeSender(sender)

    if kind == MSG_META_REQ then
        sendMetadata(source, requestId)
        return true
    end

    if kind == MSG_DATA_REQ then
        sendData(source, requestId)
        return true
    end

    if kind == MSG_META_ACK then
        local checksum = tostring(fields[3] or "")
        addon:info(L.MsgReservesSyncMeta:format(source, checksum, tostring(fields[4] or ""), tonumber(fields[5]) or 0, tonumber(fields[6]) or 0))
        if shouldRequestRemoteData(checksum) then
            requestDataFrom(source, requestId, checksum)
        end
        return true
    end

    if kind == MSG_DATA_CHUNK then
        local key = source .. ":" .. tostring(requestId or "")
        local idx = tonumber(fields[3]) or 0
        local total = tonumber(fields[4]) or 0
        local pending = Sync._incoming[key]
        if not pending then
            pending = {
                total = total,
                chunks = {},
            }
            Sync._incoming[key] = pending
        end
        pending.total = total
        if idx > 0 then
            pending.chunks[idx] = fields[5] or ""
        end
        return true
    end

    if kind == MSG_DATA_DONE then
        local ok, reason = applyIncoming(source, requestId, fields[3])
        if ok then
            addon:info(L.MsgReservesSyncApplied:format(source))
        else
            addon:warn(L.MsgReservesSyncFailed:format(tostring(reason or "unknown")))
        end
        return true
    end

    if kind == MSG_DATA_ERR then
        addon:warn(L.MsgReservesSyncFailed:format(tostring(fields[3] or fields[2] or "unknown")))
        return true
    end

    return true
end
