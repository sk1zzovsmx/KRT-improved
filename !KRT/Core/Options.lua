-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- exports: publish module APIs on addon.Options
-- events: emits OptionChanged, OptionsReset, OptionsLoaded via addon.Bus
local addon = select(2, ...)

local type, pairs, tostring = type, pairs, tostring
local format = string.format

addon.Options = addon.Options or {}
local Options = addon.Options

addon.Events = addon.Events or {}
addon.Events.Internal = addon.Events.Internal or {}
local Events = addon.Events.Internal
Events.OptionChanged = Events.OptionChanged or "OptionChanged"
Events.OptionsReset = Events.OptionsReset or "OptionsReset"
Events.OptionsLoaded = Events.OptionsLoaded or "OptionsLoaded"

local SCHEMA_VERSION = 2

-- ----- Internal state ----- --
local namespaces = {}
local keyToNamespace = {}
local loaded = false

-- Hardcoded mapping per la migrazione one-shot dalla struttura flat (schema 1) a nested (schema 2).
-- Ogni chiave flat conosciuta viene spostata nel suo namespace di destinazione.
local MIGRATION_MAP = {
    sortAscending = "Master",
    useRaidWarning = "Master",
    screenReminder = "Master",
    announceOnWin = "Master",
    announceOnHold = "Master",
    announceOnBank = "Master",
    announceOnDisenchant = "Master",
    lootWhispers = "Loot",
    ignoreStacks = "Loot",
    countdownDuration = "Rolls",
    countdownSimpleRaidMsg = "Rolls",
    countdownRollsBlock = "Rolls",
    softResWhisperReplies = "Reserves",
    srImportMode = "Reserves",
    minimapButton = "Minimap",
    minimapPos = "Minimap",
    showLootCounterDuringMSRoll = "LootCounter",
    showTooltips = "UI",
}

-- ----- Private helpers ----- --
local function shallowCopy(src)
    local dst = {}
    if type(src) == "table" then
        for k, v in pairs(src) do
            dst[k] = v
        end
    end
    return dst
end

local function ensureSavedTable()
    if type(_G.KRT_Options) ~= "table" then
        _G.KRT_Options = {}
    end
    return _G.KRT_Options
end

local function emit(eventName, ...)
    local bus = addon.Bus
    if bus and type(bus.TriggerEvent) == "function" then
        bus.TriggerEvent(eventName, ...)
    end
end

local function applyDefaultsToStorage(name, defaults)
    local saved = ensureSavedTable()
    local store = saved[name]
    if type(store) ~= "table" then
        store = {}
        saved[name] = store
    end

    for key, defaultValue in pairs(defaults) do
        if store[key] == nil then
            store[key] = defaultValue
        end
    end

    return store
end

local function migrateFlatToNested()
    local saved = ensureSavedTable()
    if saved._schema == SCHEMA_VERSION then
        return false
    end

    -- Vecchia struttura flat: chiavi conosciute sparse al top level.
    local migrated = false
    for flatKey, namespaceName in pairs(MIGRATION_MAP) do
        local value = saved[flatKey]
        if value ~= nil then
            local store = saved[namespaceName]
            if type(store) ~= "table" then
                store = {}
                saved[namespaceName] = store
            end
            -- Non sovrascrivere se il namespace ha già il valore (caso edge: doppio reload).
            if store[flatKey] == nil then
                store[flatKey] = value
            end
            saved[flatKey] = nil
            migrated = true
        end
    end

    -- Pulisci eventuali chiavi legacy non mappate (es. "debug" rimosso in passato).
    saved.debug = nil

    saved._schema = SCHEMA_VERSION
    return migrated
end

-- ----- Namespace prototype ----- --
local namespaceMt = {}
namespaceMt.__index = namespaceMt

function namespaceMt:Get(key)
    local store = self._store
    local value = store[key]
    if value == nil then
        return self._defaults[key]
    end
    return value
end

function namespaceMt:Set(key, value)
    if type(key) ~= "string" or key == "" then
        return false
    end
    if self._defaults[key] == nil then
        addon:warn(format("Options: namespace %q has no default for key %q (rejected)", self._name, tostring(key)))
        return false
    end

    local defaultType = type(self._defaults[key])
    if value ~= nil and type(value) ~= defaultType then
        addon:warn(format("Options: namespace %q key %q expects %s, got %s (rejected)", self._name, tostring(key), defaultType, type(value)))
        return false
    end

    local store = self._store
    local old = store[key]
    if old == value then
        return true
    end

    store[key] = value
    emit(Events.OptionChanged, self._name, key, old, value)
    return true
end

function namespaceMt:GetDefaults()
    return shallowCopy(self._defaults)
end

function namespaceMt:ResetDefaults()
    local saved = ensureSavedTable()
    local fresh = shallowCopy(self._defaults)
    saved[self._name] = fresh
    self._store = fresh
    emit(Events.OptionsReset, self._name)
    return fresh
end

function namespaceMt:All()
    local out = shallowCopy(self._defaults)
    for k, v in pairs(self._store) do
        out[k] = v
    end
    return out
end

function namespaceMt:Name()
    return self._name
end

-- ----- Public API ----- --
function Options.AddNamespace(name, defaults)
    if type(name) ~= "string" or name == "" then
        error("Options.AddNamespace: name must be a non-empty string", 2)
    end
    if type(defaults) ~= "table" then
        error("Options.AddNamespace: defaults must be a table", 2)
    end

    local existing = namespaces[name]
    if existing then
        -- Permetti re-register idempotente con stessi defaults (no-op safe).
        return existing
    end

    local store = applyDefaultsToStorage(name, defaults)
    local ns = setmetatable({
        _name = name,
        _defaults = shallowCopy(defaults),
        _store = store,
    }, namespaceMt)

    namespaces[name] = ns
    -- Indice inverso key → namespace per il proxy `addon.options` (lookup O(1)).
    -- Se la stessa chiave è registrata in due namespace, l'ultima registrazione vince.
    for key in pairs(defaults) do
        keyToNamespace[key] = ns
    end
    return ns
end

function Options.Get(name)
    return namespaces[name]
end

function Options.EnsureLoaded()
    if loaded then
        return
    end
    ensureSavedTable()
    migrateFlatToNested()

    -- Re-bind storage references per i namespace registrati prima del load.
    -- (Caso normale: i moduli registrano in fase di file load, prima di ADDON_LOADED.)
    local saved = ensureSavedTable()
    for name, ns in pairs(namespaces) do
        local store = saved[name]
        if type(store) ~= "table" then
            store = shallowCopy(ns._defaults)
            saved[name] = store
        else
            -- Riempi defaults mancanti su store esistente.
            for key, defaultValue in pairs(ns._defaults) do
                if store[key] == nil then
                    store[key] = defaultValue
                end
            end
        end
        ns._store = store
    end

    loaded = true
    emit(Events.OptionsLoaded)
end

-- ----- Read-only flat proxy ----- --
-- `addon.options.<key>` risolve attraverso il namespace che possiede la chiave
-- (lookup O(1) via keyToNamespace). I writes devono passare per namespace:Set.
-- Esiste per evitare di aggiungere upvalue extra in file ai limiti (es. Master.lua).
addon.options = setmetatable({}, {
    __index = function(_, key)
        local ns = keyToNamespace[key]
        if ns then
            return ns:Get(key)
        end
        return nil
    end,
    __newindex = function(_, key)
        error(format("addon.options is read-only (key %q): use addon.Options.Get(ns):Set", tostring(key)), 2)
    end,
    __metatable = false,
})

-- Iterate via this getter to avoid exposing the internal table directly.
function Options.GetNamespaces()
    return namespaces
end

-- Convenience write quando il chiamante non conosce il namespace (es. Config UI):
-- risolve `key` via keyToNamespace e delega a namespace:Set. Restituisce false se
-- la chiave non è registrata in alcun namespace.
function Options.Set(key, value)
    local ns = keyToNamespace[key]
    if not ns then
        return false
    end
    return ns:Set(key, value)
end

-- ----- Debug toggle (non legato a un namespace) ----- --
-- Gestisce solo il flag runtime addon.State.debugEnabled e il log level.
-- Non viene persistito su SavedVariables (resettato a false ad ogni load).
function Options.IsDebugEnabled()
    return addon and addon.State and addon.State.debugEnabled == true
end

function Options.SetDebugEnabled(enabled)
    local state = addon.State
    state.debugEnabled = enabled and true or false

    local levels = addon and addon.Debugger and addon.Debugger.logLevels
    local level = enabled and (levels and levels.DEBUG) or (levels and levels.INFO)
    if level and addon and addon.SetLogLevel then
        addon:SetLogLevel(level)
    end
end
