-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: addon.Services.Loot._DistributionSession
-- events: LootDistributionSessionChanged

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core
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

local MSG_ITEM = "ITEM"
local MSG_ROLL_START = "ROLL_START"
local MSG_ROLL_END = "ROLL_END"
local MSG_ITEM_DONE = "ITEM_DONE"
local MSG_CLEAR = "CLEAR"

local STATE_ACTIVE = "active"
local STATE_ROLLING = "rolling"
local STATE_WINNER = "winner"
local STATE_DONE = "done"

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
    local playerName = Core and Core.GetPlayerName and Core.GetPlayerName() or "player"
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

local function publishItemRow(row)
    return publishMessage(
        MSG_ITEM,
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
    return publishMessage(MSG_ROLL_START, ensureSessionId(), row.itemKey, row.rollType or "", row.duration or "")
end

local function publishRollEndRow(row)
    return publishMessage(MSG_ROLL_END, ensureSessionId(), row.itemKey, encodeText(row.winnerName), row.rollValue or "", encodeText(row.reason))
end

local function publishItemDoneRow(row)
    return publishMessage(MSG_ITEM_DONE, ensureSessionId(), row.itemKey, encodeText(row.winnerName))
end

local function handleItemMessage(fields, sender)
    local sessionId = setSessionId(fields[2])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[3],
        count = fields[4],
        quality = fields[5],
        itemLink = decodeText(fields[6]),
        itemName = decodeText(fields[7]),
        itemTexture = decodeText(fields[8]),
        slot = fields[9],
        state = STATE_ACTIVE,
        sender = sender,
    }, "item")
    return row ~= nil
end

local function handleRollStartMessage(fields, sender)
    local sessionId = setSessionId(fields[2])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[3],
        rollType = fields[4],
        duration = fields[5],
        state = STATE_ROLLING,
        sender = sender,
    }, "roll_start")
    return row ~= nil
end

local function handleRollEndMessage(fields, sender)
    local sessionId = setSessionId(fields[2])
    local winnerName = decodeText(fields[4])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[3],
        winnerName = winnerName,
        rollValue = fields[5],
        reason = decodeText(fields[6]),
        state = normalizeText(winnerName) and STATE_WINNER or STATE_ACTIVE,
        sender = sender,
    }, "roll_end")
    return row ~= nil
end

local function handleItemDoneMessage(fields, sender)
    local sessionId = setSessionId(fields[2])
    local row = upsertRow({
        sessionId = sessionId,
        itemKey = fields[3],
        winnerName = decodeText(fields[4]),
        state = STATE_DONE,
        sender = sender,
    }, "item_done")
    return row ~= nil
end

-- ----- Public methods ----- --
function DistributionSession.GetPrefix()
    return PREFIX
end

function DistributionSession.Clear()
    if not canPublish() then
        return false
    end
    local sessionId = buildSessionId()
    clearState(sessionId)
    return publishMessage(MSG_CLEAR, sessionId)
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

function DistributionSession.RequestMessageHandling(prefix, msg, _channel, sender)
    if prefix ~= PREFIX then
        return false
    end

    local fields = splitFields(msg)
    local kind = fields[1]
    if kind == MSG_CLEAR then
        clearState(fields[2])
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
        sessionId = state.sessionId,
        rows = rows,
    }
end

ensurePrefix()
