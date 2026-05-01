-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: bootstrap-sensitive internal loot state helpers
-- exports: addon.Services.Loot._State

local addon = select(2, ...)

addon.Services = addon.Services or {}
addon.Services.Loot = addon.Services.Loot or {}

-- ----- Internal state ----- --
local module = addon.Services.Loot
module._State = module._State or {}

local ContextState = module._State
local ContextHelpers = assert(module._Context, "Loot context helpers are not initialized")

local normalizeBossEventContext = assert(ContextHelpers.NormalizeBossEventContext, "Missing LootContext.NormalizeBossEventContext")
local normalizeLootSessionState = assert(ContextHelpers.NormalizeLootSessionState, "Missing LootContext.NormalizeLootSessionState")
local normalizeLootSnapshotState = assert(ContextHelpers.NormalizeLootSnapshotState, "Missing LootContext.NormalizeLootSnapshotState")
local normalizeActiveLootContext = assert(ContextHelpers.NormalizeActiveLootContext, "Missing LootContext.NormalizeActiveLootContext")
local buildActiveLootContext = assert(ContextHelpers.BuildActiveLootContext, "Missing LootContext.BuildActiveLootContext")
local projectLootWindowBossContext = assert(ContextHelpers.ProjectLootWindowBossContext, "Missing LootContext.ProjectLootWindowBossContext")
local projectLootSourceState = assert(ContextHelpers.ProjectLootSourceState, "Missing LootContext.ProjectLootSourceState")

-- ----- Private helpers ----- --
local function ensureRaidState(raidState)
    return assert(type(raidState) == "table" and raidState or nil, "Loot context state requires raidState table")
end

local function syncActiveContext(raidState, lootContext)
    local value = buildActiveLootContext(lootContext.activeLoot, raidState.lootWindowBossContext or lootContext.activeWindow, raidState.lootSource or lootContext.source)
    return ContextState.SetActive(raidState, value)
end

local function mutateActiveContext(raidState, mutateFn)
    local activeLoot = ContextState.SyncActive(raidState)
    if type(activeLoot) ~= "table" then
        ContextState.SetActive(raidState, nil)
        return nil
    end

    mutateFn(activeLoot)
    return ContextState.SetActive(raidState, activeLoot)
end

-- ----- Public methods ----- --
function ContextState.EnsureState(raidState)
    raidState = ensureRaidState(raidState)
    local lootContext = raidState.lootContext
    if type(lootContext) ~= "table" then
        lootContext = {}
        raidState.lootContext = lootContext
    end
    return lootContext
end

function ContextState.SetField(raidState, slotKey, legacyKey, value)
    raidState = ensureRaidState(raidState)
    local lootContext = ContextState.EnsureState(raidState)
    lootContext[slotKey] = value
    raidState[legacyKey] = value
    return value
end

function ContextState.SyncField(raidState, slotKey, legacyKey, normalizeFn)
    raidState = ensureRaidState(raidState)
    local lootContext = ContextState.EnsureState(raidState)
    local legacyValue = raidState[legacyKey]
    local value = lootContext[slotKey]

    if legacyValue == nil then
        value = nil
    elseif legacyValue ~= value then
        value = normalizeFn(legacyValue)
    else
        value = normalizeFn(value)
    end

    return ContextState.SetField(raidState, slotKey, legacyKey, value)
end

function ContextState.SetActive(raidState, activeLoot)
    raidState = ensureRaidState(raidState)
    local lootContext = ContextState.EnsureState(raidState)
    local value = normalizeActiveLootContext(activeLoot)
    lootContext.activeLoot = value
    lootContext.activeWindow = projectLootWindowBossContext(value)
    lootContext.source = projectLootSourceState(value)
    raidState.lootWindowBossContext = lootContext.activeWindow
    raidState.lootSource = lootContext.source
    return value
end

function ContextState.SyncActive(raidState)
    raidState = ensureRaidState(raidState)
    local lootContext = ContextState.EnsureState(raidState)
    return syncActiveContext(raidState, lootContext)
end

function ContextState.GetBossEvent(raidState)
    return ContextState.SyncField(raidState, "eventBoss", "bossEventContext", normalizeBossEventContext)
end

function ContextState.GetWindow(raidState)
    local activeLoot = ContextState.SyncActive(raidState)
    return projectLootWindowBossContext(activeLoot)
end

function ContextState.ClearWindow(raidState)
    mutateActiveContext(raidState, function(activeLoot)
        activeLoot.blocked = false
        activeLoot.source = nil
        activeLoot.sourceUnit = nil
        activeLoot.windowExpiresAt = 0
    end)
end

function ContextState.GetSource(raidState)
    local activeLoot = ContextState.SyncActive(raidState)
    return projectLootSourceState(activeLoot)
end

function ContextState.ClearSource(raidState)
    mutateActiveContext(raidState, function(activeLoot)
        activeLoot.kind = nil
        activeLoot.snapshotId = nil
        activeLoot.openedAt = 0
        activeLoot.expiresAt = 0
    end)
end

function ContextState.ResolveExpiry(now, ttlSeconds, defaultTtl, minTtl)
    local resolvedNow = tonumber(now) or addon.Time.GetCurrentTime()
    local ttl = tonumber(ttlSeconds) or tonumber(defaultTtl) or 0
    local resolvedMinTtl = tonumber(minTtl) or tonumber(defaultTtl) or 0
    if ttl < resolvedMinTtl then
        ttl = resolvedMinTtl
    end
    return resolvedNow, ttl, resolvedNow + ttl
end

function ContextState.Reset(raidState)
    raidState = ensureRaidState(raidState)
    raidState.lootContext = nil
    raidState.bossEventContext = nil
    raidState.recentLootDeathContext = nil
    raidState.lootWindowBossContext = nil
    raidState.lootBossSessions = nil
    raidState.lootWindowItemSnapshots = nil
    raidState.lootSource = nil
end

function ContextState.SyncRuntimeState(raidState)
    raidState = ensureRaidState(raidState)
    local lootContext = ContextState.EnsureState(raidState)

    lootContext.eventBoss = ContextState.SyncField(raidState, "eventBoss", "bossEventContext", normalizeBossEventContext)
    lootContext.activeLoot = syncActiveContext(raidState, lootContext)
    lootContext = ContextState.EnsureState(raidState)
    lootContext.sessions = ContextState.SyncField(raidState, "sessions", "lootBossSessions", normalizeLootSessionState)
    lootContext.snapshots = ContextState.SyncField(raidState, "snapshots", "lootWindowItemSnapshots", normalizeLootSnapshotState)
    lootContext = ContextState.EnsureState(raidState)
    return lootContext
end

-- ----- Loot session helpers (merged from Loot/Sessions.lua) ----- --

module._Sessions = module._Sessions or {}
local Sessions = module._Sessions

local GROUP_LOOT_PENDING_AWARD_TTL_SECONDS_SESSION = tonumber(addon.C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS) or 60

local function getSessionState(raidState)
    local state = ContextState.SyncField(raidState, "sessions", "lootBossSessions", normalizeLootSessionState)
    if type(state) ~= "table" then
        state = {
            bySessionId = {},
        }
        ContextState.SetField(raidState, "sessions", "lootBossSessions", state)
    end
    return state
end

function Sessions.PurgeExpired(raidState, now)
    local state = getSessionState(raidState)
    local currentTime = tonumber(now) or addon.Time.GetCurrentTime()

    for sessionId, entry in pairs(state.bySessionId) do
        local expiresAt = tonumber(entry and entry.expiresAt) or 0
        local entryRaidNum = tonumber(entry and entry.raidNum) or 0
        local entryBossNid = tonumber(entry and entry.bossNid) or 0
        if type(sessionId) ~= "string" or sessionId == "" or entryRaidNum <= 0 or entryBossNid <= 0 or (expiresAt > 0 and expiresAt <= currentTime) then
            state.bySessionId[sessionId] = nil
        end
    end

    return state
end

function Sessions.Remember(raidState, raidNum, rollSessionId, bossNid, ttlSeconds, now)
    local sessionId = rollSessionId and tostring(rollSessionId) or nil
    local resolvedRaidNum = tonumber(raidNum) or 0
    local resolvedBossNid = tonumber(bossNid) or 0
    if not sessionId or sessionId == "" or resolvedRaidNum <= 0 or resolvedBossNid <= 0 then
        return
    end

    local state = getSessionState(raidState)
    local _, _, expiresAt = ContextState.ResolveExpiry(now, ttlSeconds, GROUP_LOOT_PENDING_AWARD_TTL_SECONDS_SESSION, GROUP_LOOT_PENDING_AWARD_TTL_SECONDS_SESSION)
    state.bySessionId[sessionId] = {
        raidNum = resolvedRaidNum,
        bossNid = resolvedBossNid,
        expiresAt = expiresAt,
    }
end

function Sessions.Resolve(raidState, raid, raidNum, rollSessionId, now, findBossByNid)
    local sessionId = rollSessionId and tostring(rollSessionId) or nil
    if not sessionId or sessionId == "" then
        return 0
    end

    local state = Sessions.PurgeExpired(raidState, now)
    local entry = state.bySessionId[sessionId]
    if type(entry) ~= "table" then
        return 0
    end

    local entryRaidNum = tonumber(entry.raidNum) or 0
    local entryBossNid = tonumber(entry.bossNid) or 0
    if entryRaidNum ~= (tonumber(raidNum) or 0) or entryBossNid <= 0 then
        state.bySessionId[sessionId] = nil
        return 0
    end

    if type(findBossByNid) == "function" and findBossByNid(raid, entryBossNid) then
        return entryBossNid
    end

    state.bySessionId[sessionId] = nil
    return 0
end
