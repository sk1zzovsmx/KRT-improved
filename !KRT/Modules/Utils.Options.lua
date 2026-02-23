-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local pairs, type = pairs, type

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.Options = Utils.Options or {}
local Options = Utils.Options

Options.defaultValues = Options.defaultValues or {
    sortAscending = false,
    useRaidWarning = true,
    announceOnWin = true,
    announceOnHold = true,
    announceOnBank = false,
    announceOnDisenchant = false,
    lootWhispers = false,
    screenReminder = true,
    ignoreStacks = false,
    showTooltips = true,
    showLootCounterDuringMSRoll = false,
    minimapButton = true,
    countdownSimpleRaidMsg = false,
    countdownDuration = 5,
    countdownRollsBlock = true,
    srImportMode = 0,
}

local function copyFlat(dst, src)
    for key, value in pairs(src or {}) do
        dst[key] = value
    end
    return dst
end

function Options.newOptions()
    return copyFlat({}, Options.defaultValues)
end

function Options.isDebugEnabled()
    return addon and addon.State and addon.State.debugEnabled == true
end

function Options.applyDebugSetting(enabled)
    local state = addon.State
    state.debugEnabled = enabled and true or false

    local levels = addon and addon.Debugger and addon.Debugger.logLevels
    local level = enabled and (levels and levels.DEBUG) or (levels and levels.INFO)
    if level and addon and addon.SetLogLevel then
        addon:SetLogLevel(level)
    end
end

-- Write an addon option and keep runtime and SavedVariables in sync.
function Options.setOption(key, value)
    if type(key) ~= "string" or key == "" then
        return false
    end

    local options = addon and addon.options
    if type(options) ~= "table" then
        if type(KRT_Options) == "table" then
            options = KRT_Options
        else
            options = {}
            KRT_Options = options
        end
        addon.options = options
    end

    options[key] = value

    if type(KRT_Options) == "table" and KRT_Options ~= options then
        KRT_Options[key] = value
    end

    return true
end

function Options.loadOptions()
    local options = Options.newOptions()
    if type(KRT_Options) == "table" then
        copyFlat(options, KRT_Options)
    end

    options.debug = nil
    KRT_Options = options
    addon.options = options

    Options.applyDebugSetting(false)
    return options
end

function Options.restoreDefaults()
    local options = Options.newOptions()
    KRT_Options = options
    addon.options = options
    Options.applyDebugSetting(false)
    return options
end

if type(addon.LoadOptions) ~= "function" then
    addon.LoadOptions = Options.loadOptions
end
