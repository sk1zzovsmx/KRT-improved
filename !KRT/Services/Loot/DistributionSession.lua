-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Loot._DistributionSession
-- events: LootDistributionSessionChanged

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Database = feature.Database
local Diag = feature.Diag
local Events = feature.Events
local Bus = feature.Bus
local Comms = feature.Comms
local Item = feature.Item
local Services = feature.Services

local _G = _G
local type, tostring, tonumber = type, tostring, tonumber
local select = select
local tinsert, tsort, tconcat = table.insert, table.sort, table.concat
local strfind, strsub = string.find, string.sub

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Loot")
local module = addon.Services.Loot
module._DistributionSession = module._DistributionSession or {}

local DistributionSession = module._DistributionSession

local PREFIX = "KRTDist"
local SEP = "|"
local PROTOCOL_VERSION = 2

local MSG_ITEM = "ITEM"
local MSG_ROLL_START = "ROLL_START"
local MSG_ROLL_END = "ROLL_END"
local MSG_ITEM_DONE = "ITEM_DONE"
local MSG_CLEAR = "CLEAR"
local MSG_HELLO = "HELLO"
local MSG_SNAPSHOT_REQ = "SNAP_REQ"
local MSG_SNAPSHOT = "SNAP"
local MSG_ROLL_TICK = "ROLL_TICK"
local MSG_TIE_START = "TIE_START"
local MSG_AWARDED = "AWARDED"

local SNAP_ROW_SEP = "~"

local STATE_ACTIVE = "active"
local STATE_ROLLING = "rolling"
local STATE_WINNER = "winner"
local STATE_DONE = "done"
local STATE_AWARDED = "awarded"

local state = DistributionSession._state
if type(state) ~= "table" then
    state = {
        sessionId = nil,
        nextSessionOrdinal = 1,
        order = {},
        itemsByKey = {},
    }
    DistributionSession._state = state
end

-- ----- Private helpers ----- --
local function getChangedEventName()
    local internal = Events and Events.Internal
    return internal and internal.LootDistributionSessionChanged or "LootDistributionSessionChanged"
end

local function ensurePrefix()
    local register = _G.RegisterAddonMessagePrefix
    if type(register) == "function" then
        register(PREFIX)
    end
end

local function getPayload()
    Comms = feature.Comms or addon.Comms or Comms
    return Comms and Comms._Payload or nil
end

local function encodeText(value)
    local payload = getPayload()
    if payload and type(payload._EncodeText) == "function" then
        return payload._EncodeText(value)
    end
    return tostring(value or "")
end

local function decodeText(value)
    local payload = getPayload()
    if payload and type(payload._DecodeText) == "function" then
        local decoded = payload._DecodeText(value)
        if decoded ~= nil then
            return decoded
        end
    end
    return tostring(value or "")
end

local function packFields(...)
    local payload = getPayload()
    if payload and type(payload._PackFields) == "function" then
        return payload._PackFields(SEP, ...)
    end

    local n = select("#", ...)
    local out = {}
    for i = 1, n do
        out[i] = tostring(select(i, ...) or "")
    end
    return tconcat(out, SEP)
end

local function splitText(text, sep, out)
    local input = tostring(text or "")
    local delimiter = tostring(sep or "")
    local fields = out or {}
    local startPos = 1
    local n = 0

    if delimiter == "" then
        fields[1] = input
        for i = 2, #fields do
            fields[i] = nil
        end
        return fields, 1
    end

    while true do
        local fromPos, toPos = strfind(input, delimiter, startPos, true)
        if not fromPos then
            n = n + 1
            fields[n] = strsub(input, startPos)
            break
        end
        n = n + 1
        fields[n] = strsub(input, startPos, fromPos - 1)
        startPos = toPos + 1
    end
    for i = n + 1, #fields do
        fields[i] = nil
    end
    return fields, n
end

local splitScratch = {}
local function splitFields(text)
    local payload = getPayload()
    if payload and type(payload._SplitFields) == "function" then
        return payload._SplitFields(text, SEP, splitScratch)
    end

    local input = tostring(text or "")
    local startPos = 1
    local n = 0
    while true do
        local fromPos, toPos = strfind(input, SEP, startPos, true)
        if not fromPos then
            n = n + 1
            splitScratch[n] = strsub(input, startPos)
            break
        end
        n = n + 1
        splitScratch[n] = strsub(input, startPos, fromPos - 1)
        startPos = toPos + 1
    end
    for i = n + 1, #splitScratch do
        splitScratch[i] = nil
    end
    return splitScratch, n
end

local snapshotRowsScratch = {}
local snapshotFieldScratch = {}

local function normalizeNumber(value)
    local numeric = tonumber(value)
    if numeric then
        return numeric
    end
    return nil
end

local function normalizeText(value)
    if value == nil then
        return nil
    end
    value = tostring(value)
    if value == "" then
        return nil
    end
    return value
end

local function resolveItemKey(itemKeyOrLink, itemLink)
    local key = normalizeText(itemKeyOrLink)
    local link = normalizeText(itemLink)

    if link and Item and type(Item.GetItemStringFromLink) == "function" then
        key = Item.GetItemStringFromLink(link) or key
    elseif key and strfind(key, "|Hitem:", 1, true) and Item and type(Item.GetItemStringFromLink) == "function" then
        key = Item.GetItemStringFromLink(key) or key
    end

    return normalizeText(key or link)
end

local function buildSessionId()
    local playerName = Database and Database.GetPlayerName and Database.GetPlayerName() or "player"
    local ordinal = tonumber(state.nextSessionOrdinal) or 1
    state.nextSessionOrdinal = ordinal + 1

    local getTime = _G.GetTime
    local now = type(getTime) == "function" and getTime() or ordinal
    return tostring(playerName or "player") .. ":" .. tostring(ordinal) .. ":" .. tostring(now or 0)
end

local function ensureSessionId()
    if not state.sessionId or state.sessionId == "" then
        state.sessionId = buildSessionId()
    end
    return state.sessionId
end

local function setSessionId(sessionId)
    sessionId = normalizeText(sessionId)
    if sessionId then
        state.sessionId = sessionId
    else
        ensureSessionId()
    end
    return state.sessionId
end

local function canPublish()
    local raid = Services and Services.Raid or nil
    if raid and type(raid.CanUseCapability) == "function" then
        return raid:CanUseCapability("loot") == true
    end
    if raid and type(raid.GetPlayerRoleState) == "function" then
        local role = raid:GetPlayerRoleState()
        if role and role.inRaid and role.isMasterLooter ~= true then
            return false
        end
    end
    return true
end

local function triggerChanged(reason, row)
    if Bus and type(Bus.TriggerEvent) == "function" then
        Bus.TriggerEvent(getChangedEventName(), reason, row, state.sessionId)
    end
end

local function getOrCreateRow(itemKey)
    itemKey = normalizeText(itemKey)
    if not itemKey then
        return nil
    end

    local row = state.itemsByKey[itemKey]
    if row then
        return row
    end

    row = {
        itemKey = itemKey,
        order = #state.order + 1,
        state = STATE_ACTIVE,
    }
    state.itemsByKey[itemKey] = row
    state.order[#state.order + 1] = itemKey
    return row
end

local function copyRow(row)
    if type(row) ~= "table" then
        return nil
    end
    return {
        itemKey = row.itemKey,
        itemLink = row.itemLink,
        itemName = row.itemName,
        itemTexture = row.itemTexture,
        itemColor = row.itemColor,
        quality = row.quality,
        count = row.count,
        slot = row.slot,
        order = row.order,
        state = row.state,
        rollType = row.rollType,
        duration = row.duration,
        winnerName = row.winnerName,
        rollValue = row.rollValue,
        reason = row.reason,
        remaining = row.remaining,
        tieNamesText = row.tieNamesText,
        protocolVersion = row.protocolVersion or PROTOCOL_VERSION,
        sessionId = row.sessionId or state.sessionId,
        sender = row.sender,
    }
end

local function upsertRow(data, reason)
    if type(data) ~= "table" then
        return nil
    end

    local itemKey = resolveItemKey(data.itemKey or data.key or data.itemLink, data.itemLink)
    if not itemKey then
        return nil
    end

    local row = getOrCreateRow(itemKey)
    row.itemKey = itemKey
    row.sessionId = data.sessionId or row.sessionId or state.sessionId
    row.itemLink = normalizeText(data.itemLink) or row.itemLink
    row.itemName = normalizeText(data.itemName or data.name) or row.itemName
    row.itemTexture = normalizeText(data.itemTexture or data.texture) or row.itemTexture
    row.itemColor = normalizeText(data.itemColor or data.color) or row.itemColor
    row.quality = normalizeNumber(data.quality or data.itemRarity or data.rarity) or row.quality
    row.count = normalizeNumber(data.count or data.itemCount) or row.count or 1
    row.slot = normalizeNumber(data.slot or data.index) or row.slot
    row.sender = normalizeText(data.sender) or row.sender
    row.protocolVersion = normalizeNumber(data.protocolVersion) or row.protocolVersion or PROTOCOL_VERSION

    if data.rollType ~= nil then
        row.rollType = normalizeNumber(data.rollType) or data.rollType
    end
    if data.duration ~= nil then
        row.duration = normalizeNumber(data.duration)
    end
    if data.winnerName ~= nil then
        row.winnerName = normalizeText(data.winnerName)
    end
    if data.rollValue ~= nil then
        row.rollValue = normalizeNumber(data.rollValue)
    end
    if data.reason ~= nil then
        row.reason = normalizeText(data.reason)
    end
    if data.remaining ~= nil then
        row.remaining = normalizeNumber(data.remaining)
    end
    if data.tieNamesText ~= nil then
        row.tieNamesText = normalizeText(data.tieNamesText)
    end

    if data.state then
        row.state = data.state
    elseif not row.state then
        row.state = STATE_ACTIVE
    end

    local snapshot = copyRow(row)
    triggerChanged(reason, snapshot)
    return row
end

local function clearState(sessionId)
    state.sessionId = normalizeText(sessionId) or buildSessionId()
    state.order = {}
    state.itemsByKey = {}
    triggerChanged("clear", nil)
end

local function sendMessage(...)
    Comms = feature.Comms or addon.Comms or Comms
    if not (Comms and type(Comms.Sync) == "function") then
        return false
    end
    ensurePrefix()
    local ok = Comms.Sync(PREFIX, packFields(...))
    return ok == true
end

local function publishMessage(...)
    if not canPublish() then
        return false
    end
    return sendMessage(...)
end

local function sendDirect(channel, target, ...)
    ensurePrefix()
    if type(_G.SendAddonMessage) ~= "function" then
        return false
    end
    _G.SendAddonMessage(PREFIX, packFields(...), channel, target)
    return true
end

local function isSupportedVersion(version)
    local numeric = tonumber(version)
    if numeric == PROTOCOL_VERSION then
        return true
    end
    if addon.hasDebug and Diag and Diag.W and Diag.W.LogDistributionUnsupportedVersion then
        addon:warn(Diag.W.LogDistributionUnsupportedVersion:format(tostring(version)))
    end
    return false
end

local function encodeSnapshot()
    local rows = {}
    for i = 1, #state.order do
        local row = state.itemsByKey[state.order[i]]
        if row then
            rows[#rows + 1] = packFields(
                row.itemKey,
                row.count or 1,
                row.quality or "",
                encodeText(row.itemLink),
                encodeText(row.itemName),
                encodeText(row.itemTexture),
                row.slot or "",
                row.state or "",
                row.rollType or "",
                row.duration or "",
                encodeText(row.winnerName),
                row.rollValue or "",
                encodeText(row.reason),
                row.remaining or "",
                encodeText(row.tieNamesText)
            )
        end
    end
    return encodeText(tconcat(rows, SNAP_ROW_SEP))
end

local function countSnapshotRows()
    local count = 0
    for i = 1, #state.order do
        if state.itemsByKey[state.order[i]] then
            count = count + 1
        end
    end
    return count
end

local function publishItemRow(row)
    return publishMessage(
        MSG_ITEM,
        PROTOCOL_VERSION,
        ensureSessionId(),
        row.itemKey,
        row.count or 1,
        row.quality or "",
        encodeText(row.itemLink),
        encodeText(row.itemName),
        encodeText(row.itemTexture),
        row.slot or ""
    )
end

local function publishRollStartRow(row)
    return publishMessage(MSG_ROLL_START, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, row.rollType or "", row.duration or "")
end

local function publishRollEndRow(row)
    return publishMessage(MSG_ROLL_END, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, encodeText(row.winnerName), row.rollValue or "", encodeText(row.reason))
end

local function publishItemDoneRow(row)
    return publishMessage(MSG_ITEM_DONE, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, encodeText(row.winnerName))
end

local function handleItemMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[4],
        count = fields[5],
        quality = fields[6],
        itemLink = decodeText(fields[7]),
        itemName = decodeText(fields[8]),
        itemTexture = decodeText(fields[9]),
        slot = fields[10],
        state = STATE_ACTIVE,
        sender = sender,
    }, "item")
    return row ~= nil
end

local function handleRollStartMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[4],
        rollType = fields[5],
        duration = fields[6],
        state = STATE_ROLLING,
        sender = sender,
    }, "roll_start")
    return row ~= nil
end

local function handleRollEndMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local winnerName = decodeText(fields[5])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[4],
        winnerName = winnerName,
        rollValue = fields[6],
        reason = decodeText(fields[7]),
        state = normalizeText(winnerName) and STATE_WINNER or STATE_ACTIVE,
        sender = sender,
    }, "roll_end")
    return row ~= nil
end

local function handleItemDoneMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[4],
        winnerName = decodeText(fields[5]),
        state = STATE_DONE,
        sender = sender,
    }, "item_done")
    return row ~= nil
end

local function handleRollTickMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local row = upsertRow({
        protocolVersion = fields[2],
        sessionId = sessionId,
        itemKey = fields[4],
        remaining = fields[5],
        state = STATE_ROLLING,
        sender = sender,
    }, "roll_tick")
    return row ~= nil
end

local function handleTieStartMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local row = upsertRow({
        protocolVersion = fields[2],
        sessionId = sessionId,
        itemKey = fields[4],
        tieNamesText = decodeText(fields[5]),
        state = STATE_WINNER,
        sender = sender,
    }, "tie_start")
    return row ~= nil
end

local function handleAwardedMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end
    local sessionId = setSessionId(fields[3])
    local row = upsertRow({
        protocolVersion = fields[2],
        sessionId = sessionId,
        itemKey = fields[4],
        winnerName = decodeText(fields[5]),
        rollValue = fields[6],
        state = STATE_AWARDED,
        sender = sender,
    }, "awarded")
    return row ~= nil
end

local function handleSnapshotMessage(fields, sender)
    if not isSupportedVersion(fields[2]) then
        return true
    end

    local sessionId = normalizeText(fields[4]) or buildSessionId()
    local snapshotText = decodeText(fields[5])
    local rows, rowCount = splitText(snapshotText, SNAP_ROW_SEP, snapshotRowsScratch)
    local applied = 0

    clearState(sessionId)
    for i = 1, rowCount do
        local rowText = rows[i]
        if rowText and rowText ~= "" then
            local rowFields = splitText(rowText, SEP, snapshotFieldScratch)
            local row = upsertRow({
                protocolVersion = fields[2],
                sessionId = sessionId,
                itemKey = rowFields[1],
                count = rowFields[2],
                quality = rowFields[3],
                itemLink = decodeText(rowFields[4]),
                itemName = decodeText(rowFields[5]),
                itemTexture = decodeText(rowFields[6]),
                slot = rowFields[7],
                state = normalizeText(rowFields[8]) or STATE_ACTIVE,
                rollType = rowFields[9],
                duration = rowFields[10],
                winnerName = decodeText(rowFields[11]),
                rollValue = rowFields[12],
                reason = decodeText(rowFields[13]),
                remaining = rowFields[14],
                tieNamesText = decodeText(rowFields[15]),
                sender = sender,
            }, "snapshot")
            if row then
                applied = applied + 1
            end
        end
    end

    if addon.hasDebug and Diag and Diag.D and Diag.D.LogDistributionSnapshotApplied then
        addon:debug(Diag.D.LogDistributionSnapshotApplied:format(applied, tostring(sender or "?")))
    end
    return true
end

-- ----- Public methods ----- --

function DistributionSession.Clear()
    if not canPublish() then
        return false
    end
    local sessionId = buildSessionId()
    clearState(sessionId)
    return publishMessage(MSG_CLEAR, PROTOCOL_VERSION, sessionId)
end

function DistributionSession.PublishItem(item)
    if not canPublish() then
        return false
    end
    local row = upsertRow(item, "item")
    if not row then
        return false
    end
    if row.state ~= STATE_ROLLING and row.state ~= STATE_WINNER and row.state ~= STATE_DONE then
        row.state = STATE_ACTIVE
    end
    return publishItemRow(row)
end

function DistributionSession.PublishWindowItems(items)
    if type(items) ~= "table" or not canPublish() then
        return false
    end

    local sent = false
    for i = 1, #items do
        if DistributionSession.PublishItem(items[i]) then
            sent = true
        end
    end
    return sent
end

function DistributionSession.PublishRollStart(itemKeyOrLink, rollType, duration)
    if not canPublish() then
        return false
    end
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    if not itemKey then
        return false
    end

    local row = upsertRow({
        itemKey = itemKey,
        rollType = rollType,
        duration = duration,
        state = STATE_ROLLING,
    }, "roll_start")
    if not row then
        return false
    end
    return publishRollStartRow(row)
end

function DistributionSession.PublishRollEnd(itemKeyOrLink, winnerName, rollValue, reason)
    if not canPublish() then
        return false
    end
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    if not itemKey then
        return false
    end

    local row = upsertRow({
        itemKey = itemKey,
        winnerName = winnerName,
        rollValue = rollValue,
        reason = reason,
        state = STATE_WINNER,
    }, "roll_end")
    if not row then
        return false
    end
    return publishRollEndRow(row)
end

function DistributionSession.PublishItemDone(itemKeyOrLink, winnerName)
    if not canPublish() then
        return false
    end
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    if not itemKey then
        return false
    end

    local row = upsertRow({
        itemKey = itemKey,
        winnerName = winnerName,
        state = STATE_DONE,
    }, "item_done")
    if not row then
        return false
    end
    return publishItemDoneRow(row)
end

function DistributionSession.RequestSnapshot()
    return publishMessage(MSG_SNAPSHOT_REQ, PROTOCOL_VERSION, ensureSessionId())
end

function DistributionSession.PublishSnapshot(target, requestId)
    if not canPublish() then
        return false
    end

    local sessionId = ensureSessionId()
    local snapshot = encodeSnapshot()
    local sent
    if target and target ~= "" then
        sent = sendDirect("WHISPER", target, MSG_SNAPSHOT, PROTOCOL_VERSION, requestId or "", sessionId, snapshot)
    else
        sent = publishMessage(MSG_SNAPSHOT, PROTOCOL_VERSION, requestId or "", sessionId, snapshot)
    end
    if sent and addon.hasDebug and Diag and Diag.D and Diag.D.LogDistributionSnapshotSent then
        addon:debug(Diag.D.LogDistributionSnapshotSent:format(countSnapshotRows(), tostring(target or "group")))
    end
    return sent == true
end

function DistributionSession.PublishRollTick(itemKeyOrLink, remaining)
    if not canPublish() then
        return false
    end
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    local row = upsertRow({
        itemKey = itemKey,
        remaining = remaining,
        state = STATE_ROLLING,
    }, "roll_tick")
    if not row then
        return false
    end
    return publishMessage(MSG_ROLL_TICK, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, row.remaining or "")
end

function DistributionSession.PublishTieStart(itemKeyOrLink, names)
    if not canPublish() then
        return false
    end
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    local tieNamesText = type(names) == "table" and tconcat(names, ",") or tostring(names or "")
    local row = upsertRow({
        itemKey = itemKey,
        tieNamesText = tieNamesText,
        state = STATE_WINNER,
    }, "tie_start")
    if not row then
        return false
    end
    return publishMessage(MSG_TIE_START, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, encodeText(tieNamesText))
end

function DistributionSession.PublishAwarded(itemKeyOrLink, winnerName, rollValue)
    if not canPublish() then
        return false
    end
    local itemKey = resolveItemKey(itemKeyOrLink, itemKeyOrLink)
    local row = upsertRow({
        itemKey = itemKey,
        winnerName = winnerName,
        rollValue = rollValue,
        state = STATE_AWARDED,
    }, "awarded")
    if not row then
        return false
    end
    return publishMessage(MSG_AWARDED, PROTOCOL_VERSION, ensureSessionId(), row.itemKey, encodeText(winnerName), row.rollValue or "")
end

function DistributionSession.HandleMessage(prefix, msg, _channel, sender)
    if prefix ~= PREFIX then
        return false
    end

    local fields = splitFields(msg)
    local kind = fields[1]
    if kind == MSG_CLEAR then
        if not isSupportedVersion(fields[2]) then
            return true
        end
        clearState(fields[3])
        return true
    end
    if kind == MSG_ITEM then
        return handleItemMessage(fields, sender)
    end
    if kind == MSG_ROLL_START then
        return handleRollStartMessage(fields, sender)
    end
    if kind == MSG_ROLL_END then
        return handleRollEndMessage(fields, sender)
    end
    if kind == MSG_ITEM_DONE then
        return handleItemDoneMessage(fields, sender)
    end
    if kind == MSG_HELLO then
        return isSupportedVersion(fields[2])
    end
    if kind == MSG_SNAPSHOT_REQ then
        if not isSupportedVersion(fields[2]) then
            return true
        end
        return DistributionSession.PublishSnapshot(sender, fields[3])
    end
    if kind == MSG_SNAPSHOT then
        return handleSnapshotMessage(fields, sender)
    end
    if kind == MSG_ROLL_TICK then
        return handleRollTickMessage(fields, sender)
    end
    if kind == MSG_TIE_START then
        return handleTieStartMessage(fields, sender)
    end
    if kind == MSG_AWARDED then
        return handleAwardedMessage(fields, sender)
    end
    return true
end

function DistributionSession.GetDisplayModel()
    local rows = {}
    for i = 1, #state.order do
        local key = state.order[i]
        local row = key and state.itemsByKey[key] or nil
        if row then
            rows[#rows + 1] = copyRow(row)
        end
    end
    tsort(rows, function(a, b)
        local left = tonumber(a and a.slot) or tonumber(a and a.order) or 0
        local right = tonumber(b and b.slot) or tonumber(b and b.order) or 0
        if left ~= right then
            return left < right
        end
        return tostring(a and a.itemKey or "") < tostring(b and b.itemKey or "")
    end)
    return {
        prefix = PREFIX,
        protocolVersion = PROTOCOL_VERSION,
        sessionId = state.sessionId,
        rows = rows,
    }
end

ensurePrefix()

local registry = addon.ModuleRegistry
if registry and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Loot/DistributionSession", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Comms",
            "Modules/Item",
        },
    })
    registry.SetLoaded("Services/Loot/DistributionSession")
end
