-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.Services.Reserves._Sync
-- events: handles KRTResSync addon-message traffic

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Comms = feature.Comms
local Services = feature.Services
local Strings = feature.Strings

local floor = math.floor
local sort = table.sort
local tconcat = table.concat
local pairs, tostring, tonumber, type = pairs, tostring, tonumber, type
local _G = _G

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Reserves")
local module = addon.Services.Reserves
module._Sync = module._Sync or {}

local Sync = module._Sync
local Payload = Comms and Comms._Payload or nil

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
local function getPayload()
    Payload = Payload or (Comms and Comms._Payload)
    return assert(Payload, "Comms payload helpers are not initialized")
end

local function normalizeSender(sender)
    local name = tostring(sender or "")
    local normalized = Strings and Strings.NormalizeName and Strings.NormalizeName(name, true) or name
    return normalized or name
end

local function getReservesService()
    return Services and Services.Reserves or module
end

local function ensurePrefix()
    if _G.RegisterAddonMessagePrefix then
        _G.RegisterAddonMessagePrefix(PREFIX)
    end
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
    local payload = getPayload()
    sendWhisper(target, payload._PackFields(FIELD_SEP, MSG_DATA_ERR, tostring(reason or "unknown")))
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
    local payload = getPayload()
    sendWhisper(target, payload._PackFields(FIELD_SEP, MSG_DATA_REQ, requestId, checksum or ""))
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
    local payload = getPayload()
    local lines = { payload._PackFields(FIELD_SEP, "H", mode or "multi") }
    local keys = sortedPlayerKeys(data)

    for i = 1, #keys do
        local playerKey = keys[i]
        local player = data[playerKey]
        if type(player) == "table" and type(player.reserves) == "table" then
            local playerName = player.playerNameDisplay or player.original or playerKey
            for j = 1, #player.reserves do
                local row = player.reserves[j]
                if type(row) == "table" and row.rawID then
                    lines[#lines + 1] = payload._PackFields(
                        FIELD_SEP,
                        "R",
                        payload._EncodeText(playerName),
                        tonumber(row.rawID) or 0,
                        tonumber(row.quantity) or 1,
                        tonumber(row.plus) or 0,
                        payload._EncodeText(row.class),
                        payload._EncodeText(row.spec),
                        payload._EncodeText(row.note),
                        payload._EncodeText(row.source)
                    )
                end
            end
        end
    end

    return tconcat(lines, "\n")
end

local function parsePayload(payload)
    local payloadCodec = getPayload()
    local reserves = {}
    local mode = "multi"
    local fields = {}

    for line in tostring(payload or ""):gmatch("[^\n]+") do
        payloadCodec._SplitFields(line, FIELD_SEP, fields)
        if fields[1] == "H" then
            mode = (fields[2] == "plus") and "plus" or "multi"
        elseif fields[1] == "R" then
            local playerName = payloadCodec._DecodeText(fields[2])
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
                    class = payloadCodec._DecodeText(fields[6]),
                    spec = payloadCodec._DecodeText(fields[7]),
                    note = payloadCodec._DecodeText(fields[8]),
                    source = payloadCodec._DecodeText(fields[9]),
                }
            end
        end
    end

    return reserves, mode
end

local function getLocalPayload()
    local data, meta = Sync:GetPayload()
    local payload = buildPayload(data, meta and meta.mode or "multi")
    return payload, meta
end

local function sendMetadata(target, requestId)
    if not canProvideReserves() then
        local payload = getPayload()
        sendWhisper(target, payload._PackFields(FIELD_SEP, MSG_DATA_ERR, requestId, "no_data"))
        return false
    end

    local _, meta = getLocalPayload()
    local payload = getPayload()
    sendWhisper(
        target,
        payload._PackFields(
            FIELD_SEP,
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
    local payloadCodec = getPayload()
    local encoded = payloadCodec._EncodeText(payload)
    local payloadLen = #encoded
    local totalChunks = floor((payloadLen + MAX_CHUNK_SIZE - 1) / MAX_CHUNK_SIZE)
    if totalChunks < 1 then
        totalChunks = 1
    end

    for idx = 1, totalChunks do
        local fromPos = ((idx - 1) * MAX_CHUNK_SIZE) + 1
        local toPos = fromPos + MAX_CHUNK_SIZE - 1
        local chunk = encoded:sub(fromPos, toPos)
        sendWhisper(target, payloadCodec._PackFields(FIELD_SEP, MSG_DATA_CHUNK, requestId, idx, totalChunks, chunk))
    end

    sendWhisper(target, payloadCodec._PackFields(FIELD_SEP, MSG_DATA_DONE, requestId, meta and meta.checksum or ""))
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

    local payloadCodec = getPayload()
    local decodedPayload = payloadCodec._DecodeText(tconcat(parts, ""))
    if not decodedPayload then
        return false, "decode_failed"
    end

    local reserves, mode = parsePayload(decodedPayload)
    local ok, reason = Sync:SetSyncedData(reserves, {
        source = sender,
        checksum = checksum,
        mode = mode,
    })
    Sync._incoming[key] = nil
    return ok, reason
end

-- ----- Public methods ----- --

function Sync:RequestMetadata()
    ensurePrefix()
    local requestId = nextRequestId()
    local payload = getPayload()
    local ok = Comms and Comms.Sync and Comms.Sync(PREFIX, payload._PackFields(FIELD_SEP, MSG_META_REQ, requestId))
    if ok == false then
        addon:warn(L.MsgReservesSyncNotInGroup)
        return false
    end
    addon:info(L.MsgReservesSyncRequested)
    return true
end

function Sync:HandleMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX then
        return false
    end

    local fields = {}
    getPayload()._SplitFields(msg, FIELD_SEP, fields)
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

local registry = addon.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Reserves/Sync", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Comms",
            "Modules/Strings",
        },
    })
    registry.SetLoaded("Services/Reserves/Sync")
end
