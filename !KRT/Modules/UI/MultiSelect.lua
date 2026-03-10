-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag

local pairs, tostring, tonumber, type = pairs, tostring, tonumber, type

addon.MultiSelect = addon.MultiSelect or {}
local MultiSelect = addon.MultiSelect

local stateByContext = MultiSelect._stateByContext or {}
MultiSelect._stateByContext = stateByContext

local function isDebugEnabled()
    return addon and addon.State and addon.State.debugEnabled == true
end

local function debugLog(msg)
    if isDebugEnabled() and addon.debug then
        addon:debug(msg)
    end
end

local function msKey(id)
    if id == nil then
        return nil
    end
    local n = tonumber(id)
    return n or id
end

local function ensureContext(contextKey)
    if not contextKey or contextKey == "" then
        contextKey = "_default"
    end
    local st = stateByContext[contextKey]
    if not st then
        st = { set = {}, count = 0, ver = 0 }
        stateByContext[contextKey] = st
    end
    return st, contextKey
end

local function idOf(value)
    if type(value) == "table" then
        return value.id
    end
    return value
end

local function findIndex(ordered, key)
    if not ordered or not key then
        return nil
    end
    for i = 1, #ordered do
        local id = idOf(ordered[i])
        if msKey(id) == key then
            return i
        end
    end
    return nil
end

function MultiSelect.MultiSelectInit(contextKey)
    local st, key = ensureContext(contextKey)
    st.set = {}
    st.count = 0
    st.ver = (st.ver or 0) + 1
    debugLog((Diag.D.LogLoggerSelectInit):format(tostring(key), st.ver))
    return st
end

function MultiSelect.MultiSelectClear(contextKey)
    return MultiSelect.MultiSelectInit(contextKey)
end

function MultiSelect.MultiSelectToggle(contextKey, id, isMulti, allowDeselect)
    local st, key = ensureContext(contextKey)
    local k = msKey(id)
    if k == nil then
        return nil, st.count or 0
    end

    local before = st.count or 0
    local action

    local allow = false
    if allowDeselect == true then
        allow = true
    elseif type(allowDeselect) == "table" and allowDeselect.allowDeselect == true then
        allow = true
    end

    if isMulti then
        if st.set[k] then
            st.set[k] = nil
            st.count = before - 1
            action = "TOGGLE_OFF"
        else
            st.set[k] = true
            st.count = before + 1
            action = "TOGGLE_ON"
        end
    else
        local already = (st.set[k] == true)
        if allow and already and before == 1 then
            st.set = {}
            st.count = 0
            action = "SINGLE_DESELECT"
        else
            st.set = {}
            st.set[k] = true
            st.count = 1
            action = "SINGLE_CLEAR+SELECT"
        end
    end

    st.ver = (st.ver or 0) + 1

    debugLog((Diag.D.LogLoggerSelectToggle):format(
        tostring(key), tostring(id), isMulti and "1" or "0", tostring(action), before, st.count or 0, st.ver
    ))

    return action, st.count or 0
end

function MultiSelect.MultiSelectSetAnchor(contextKey, id)
    local st, key = ensureContext(contextKey)
    local before = st.anchor
    local k = msKey(id)
    st.anchor = k
    local ver = st.ver or 0
    debugLog((Diag.D.LogLoggerSelectAnchor):format(
        tostring(key), tostring(before), tostring(st.anchor), ver
    ))
    return st.anchor
end

function MultiSelect.MultiSelectGetAnchor(contextKey)
    local st = stateByContext[contextKey or "_default"]
    return st and st.anchor or nil
end

function MultiSelect.MultiSelectRange(contextKey, ordered, id, isAdd)
    local st, key = ensureContext(contextKey)
    local k = msKey(id)
    if k == nil then
        return nil, st.count or 0
    end

    local before = st.count or 0
    local action

    local anchorKey = st.anchor
    local ai = findIndex(ordered, anchorKey)
    local bi = findIndex(ordered, k)

    if not ai or not bi then
        st.set = {}
        st.set[k] = true
        st.count = 1
        if not st.anchor then
            st.anchor = k
        end
        action = st.anchor == k and "RANGE_NOANCHOR_SINGLE" or "RANGE_FALLBACK_SINGLE"
    else
        if not isAdd then
            st.set = {}
            st.count = 0
        end
        local from = ai
        local to = bi
        if from > to then
            from, to = to, from
        end

        for i = from, to do
            local id2 = idOf(ordered[i])
            local k2 = msKey(id2)
            if k2 ~= nil and not st.set[k2] then
                st.set[k2] = true
                st.count = (st.count or 0) + 1
            end
        end
        action = isAdd and "RANGE_ADD" or "RANGE_SET"
    end

    st.ver = (st.ver or 0) + 1
    debugLog((Diag.D.LogLoggerSelectRange):format(
        tostring(key), tostring(id), isAdd and "1" or "0", tostring(action), before, st.count or 0, st.ver,
        tostring(st.anchor)
    ))
    return action, st.count or 0
end

function MultiSelect.MultiSelectIsSelected(contextKey, id)
    local st = stateByContext[contextKey or "_default"]
    if not st or not st.set then
        return false
    end
    local k = msKey(id)
    return (k ~= nil) and (st.set[k] == true) or false
end

function MultiSelect.MultiSelectCount(contextKey)
    local st = stateByContext[contextKey or "_default"]
    return (st and st.count) or 0
end

function MultiSelect.MultiSelectGetVersion(contextKey)
    local st = stateByContext[contextKey or "_default"]
    return (st and st.ver) or 0
end

function MultiSelect.MultiSelectGetSelected(contextKey)
    local st = stateByContext[contextKey or "_default"]
    local out = {}
    if not st or not st.set then
        return out
    end
    local n = 0
    for id, selected in pairs(st.set) do
        if selected then
            n = n + 1
            out[n] = id
        end
    end
    table.sort(out, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then
            return na < nb
        end
        return tostring(a) < tostring(b)
    end)
    return out
end

