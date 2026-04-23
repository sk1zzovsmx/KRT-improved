-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local type, pairs, pcall, tostring = type, pairs, pcall, tostring
local debugprofilestop = debugprofilestop

addon.Bus = addon.Bus or {}
local Bus = addon.Bus

-- ----- Internal state ----- --
local events = Bus._events or {}
Bus._events = events

local stats = Bus._stats or {}
Bus._stats = stats

-- ----- Private helpers ----- --
local function isDebugEnabled()
    return addon and addon.State and addon.State.debugEnabled == true
end

local function ensureStats(eventName)
    local entry = stats[eventName]
    if not entry then
        entry = { listeners = 0, fires = 0, maxListeners = 0, totalMs = 0, lastMs = 0, errors = 0 }
        stats[eventName] = entry
    end
    return entry
end

-- ----- Public methods ----- --
function Bus.RegisterCallback(eventName, callback)
    if not eventName or type(callback) ~= "function" then
        error(L.StrCbErrUsage)
    end

    local listeners = events[eventName]
    if not listeners then
        listeners = {}
        events[eventName] = listeners
    end

    local token = {}
    listeners[token] = callback

    local entry = ensureStats(eventName)
    entry.listeners = entry.listeners + 1
    if entry.listeners > entry.maxListeners then
        entry.maxListeners = entry.listeners
    end

    return { e = eventName, t = token }
end

function Bus.UnregisterCallback(handle)
    if type(handle) ~= "table" or not handle.e or not handle.t then
        return
    end

    local eventName, token = handle.e, handle.t
    local listeners = events[eventName]
    if listeners and listeners[token] then
        listeners[token] = nil

        local entry = ensureStats(eventName)
        if entry.listeners > 0 then
            entry.listeners = entry.listeners - 1
        end
    end
end

-- Reusable dispatch buffers keyed by nesting depth to keep nested TriggerEvent()
-- calls isolated while still avoiding per-fire table allocation.
local dispatchStack = {}
local dispatchDepth = 0

function Bus.TriggerEvent(eventName, ...)
    local listeners = events[eventName]
    if not listeners then
        return
    end

    local entry = ensureStats(eventName)
    entry.fires = entry.fires + 1

    local profileNow = (isDebugEnabled() and debugprofilestop) or nil
    local t0 = profileNow and profileNow() or nil
    local dispatchBuf
    local dispatchCount = 0
    local depth

    dispatchDepth = dispatchDepth + 1
    depth = dispatchDepth
    dispatchBuf = dispatchStack[depth]
    if not dispatchBuf then
        dispatchBuf = {}
        dispatchStack[depth] = dispatchBuf
    end

    for token in pairs(listeners) do
        dispatchCount = dispatchCount + 1
        dispatchBuf[dispatchCount] = token
    end

    if dispatchCount > entry.maxListeners then
        entry.maxListeners = dispatchCount
    end

    for i = 1, dispatchCount do
        local token = dispatchBuf[i]
        dispatchBuf[i] = nil
        local fn = listeners[token]
        if fn then
            local ok, err = pcall(fn, eventName, ...)
            if not ok then
                entry.errors = entry.errors + 1
                addon:error((Diag.E.LogUtilsCallbackExec):format(tostring(fn), tostring(eventName), tostring(err)))
            end
        end
    end

    if profileNow and t0 then
        local elapsed = profileNow() - t0
        entry.lastMs = elapsed
        entry.totalMs = entry.totalMs + elapsed
    end

    dispatchDepth = depth - 1
end

function Bus.RegisterCallbacks(names, callback)
    for i = 1, #names do
        Bus.RegisterCallback(names[i], callback)
    end
end

function Bus.GetInternalCallbackStats()
    local out = {}
    for eventName, entry in pairs(stats) do
        out[eventName] = {
            listeners = entry.listeners or 0,
            fires = entry.fires or 0,
            maxListeners = entry.maxListeners or 0,
            totalMs = entry.totalMs or 0,
            lastMs = entry.lastMs or 0,
            errors = entry.errors or 0,
        }
    end
    return out
end

function Bus.ResetInternalCallbackStats()
    for eventName in pairs(stats) do
        stats[eventName] = nil
    end
end

function Bus.DumpInternalCallbackStats(sortBy)
    if not addon or not addon.info then
        return
    end

    local rows = {}
    for eventName, entry in pairs(stats) do
        local fires = entry.fires or 0
        local total = entry.totalMs or 0
        local avg = (fires > 0) and (total / fires) or 0
        rows[#rows + 1] = {
            ev = eventName,
            listeners = entry.listeners or 0,
            fires = fires,
            max = entry.maxListeners or 0,
            total = total,
            avg = avg,
            last = entry.lastMs or 0,
            errors = entry.errors or 0,
        }
    end

    local key = "max"
    local normalized = tostring(sortBy or ""):lower()
    if normalized == "fires" or normalized == "fire" then
        key = "fires"
    elseif normalized == "listeners" or normalized == "l" then
        key = "listeners"
    elseif normalized == "time" or normalized == "total" then
        key = "total"
    elseif normalized == "avg" then
        key = "avg"
    elseif normalized == "errors" or normalized == "err" then
        key = "errors"
    end

    table.sort(rows, function(a, b)
        if a[key] == b[key] then
            return tostring(a.ev) < tostring(b.ev)
        end
        return a[key] > b[key]
    end)

    local limit = 20
    if #rows < limit then
        limit = #rows
    end

    addon:info("Internal callbacks: top %d (sort=%s).", limit, key)
    for i = 1, limit do
        local row = rows[i]
        addon:info(
            "%2d) %s | now:%d max:%d | fires:%d | total:%.2fms avg:%.3fms last:%.3fms | errors:%d",
            i,
            tostring(row.ev),
            row.listeners,
            row.max,
            row.fires,
            row.total,
            row.avg,
            row.last,
            row.errors
        )
    end
    addon:info("Tip: /krt debug callbacks reset  |  /krt debug callbacks fires|max|time|avg|errors")
end
