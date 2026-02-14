--[[
    Features/Config.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Utils = feature.Utils

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

local _G = _G

local strlen = string.len
local strsub = string.sub
local tostring = tostring

-- =========== Configuration Frame Module  =========== --
do
    addon.Config = addon.Config or {}
    local module = addon.Config
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTConfig")
    -- ----- Internal state ----- --
    local localized = false
    local configDirty = false

    -- Frame update
    local UpdateUIFrame
    local MIN_COUNTDOWN = 5
    local MAX_COUNTDOWN = 60

    -- ----- Private helpers ----- --
    local LocalizeUIFrame

    -- ----- Public methods ----- --

    -- Default options for the addon.
    local defaultOptions = {
        sortAscending               = false,
        useRaidWarning              = true,
        announceOnWin               = true,
        announceOnHold              = true,
        announceOnBank              = false,
        announceOnDisenchant        = false,
        lootWhispers                = false,
        screenReminder              = true,
        ignoreStacks                = false,
        showTooltips                = true,
        showLootCounterDuringMSRoll = false,
        minimapButton               = true,
        countdownSimpleRaidMsg      = false,
        countdownDuration           = 5,
        countdownRollsBlock         = true,
        srImportMode                = 0,
    }

    -- Creates a fresh options table seeded with defaults.
    -- Returns a new table populated with the values in defaultOptions. This helper
    -- avoids duplication between LoadDefaultOptions and LoadOptions when
    -- constructing the base options table.
    local function NewOptions()
        local options = {}
        addon.tCopy(options, defaultOptions)
        return options
    end

    -- Loads the default options into the settings table.
    local function LoadDefaultOptions()
        local options = NewOptions()
        KRT_Options = options
        addon.options = options
        configDirty = true
        module:RequestRefresh()
        addon:info(L.MsgDefaultsRestored)
    end

    -- Loads addon options from saved variables, filling in defaults.
    local function LoadOptions()
        local options = NewOptions()
        if KRT_Options then
            addon.tCopy(options, KRT_Options)
        end
        -- Debug flag is runtime-only and must not persist in SavedVariables.
        options.debug = nil
        KRT_Options = options
        addon.options = options

        Utils.applyDebugSetting(false)
        configDirty = true
        module:RequestRefresh()

        if KRT_MINIMAP_GUI then
            addon.Minimap:SetPos(addon.options.minimapPos or 325)
            if addon.options.minimapButton then
                Utils.setShown(KRT_MINIMAP_GUI, true)
            else
                Utils.setShown(KRT_MINIMAP_GUI, false)
            end
        end
    end
    addon.LoadOptions = LoadOptions

    -- Public method to reset options to default.
    function module:Default()
        return LoadDefaultOptions()
    end

    -- OnLoad handler for the configuration frame.
    function module:OnLoad(frame)
        frameName = Utils.initModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                configDirty = true
            end,
        })
        if not frameName then return end

        -- Localize once (no per-tick calls)
        LocalizeUIFrame()
    end

    function module:InitCountdownSlider(slider)
        if not slider then return end
        local sliderName = slider:GetName()
        if not sliderName then return end
        local low = _G[sliderName .. "Low"]
        if low then
            low:SetText(tostring(MIN_COUNTDOWN))
        end
        local high = _G[sliderName .. "High"]
        if high then
            high:SetText(tostring(MAX_COUNTDOWN))
        end
    end

    -- Initialize UI controller for Toggle/Hide.
    Utils.bootstrapModuleUi(module, getFrame, function()
        configDirty = true
        module:RequestRefresh()
    end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    -- OnClick handler for option controls.
    function module:OnClick(btn)
        if not btn then return end
        frameName = frameName or btn:GetParent():GetName()
        local value
        local name = btn:GetName()

        if name ~= frameName .. "countdownDuration" then
            value = (btn:GetChecked() == 1) or false
            if name == frameName .. "minimapButton" then
                addon.Minimap:ToggleMinimapButton()
            end
        else
            value = btn:GetValue()
            _G[frameName .. "countdownDurationText"]:SetText(value)
        end

        name = strsub(name, strlen(frameName) + 1)
        Utils.setOption(name, value)
        Utils.triggerEvent("Config" .. name, value)

        configDirty = true
        module:RequestRefresh()
    end

    -- Localizes UI elements.
    function LocalizeUIFrame()
        if localized then
            return
        end

        -- frameName must be ready here (OnLoad sets it before calling)
        _G[frameName .. "sortAscendingStr"]:SetText(L.StrConfigSortAscending)
        _G[frameName .. "useRaidWarningStr"]:SetText(L.StrConfigUseRaidWarning)
        _G[frameName .. "announceOnWinStr"]:SetText(L.StrConfigAnnounceOnWin)
        _G[frameName .. "announceOnHoldStr"]:SetText(L.StrConfigAnnounceOnHold)
        _G[frameName .. "announceOnBankStr"]:SetText(L.StrConfigAnnounceOnBank)
        _G[frameName .. "announceOnDisenchantStr"]:SetText(L.StrConfigAnnounceOnDisenchant)
        _G[frameName .. "lootWhispersStr"]:SetText(L.StrConfigLootWhisper)
        _G[frameName .. "countdownRollsBlockStr"]:SetText(L.StrConfigCountdownRollsBlock)
        _G[frameName .. "screenReminderStr"]:SetText(L.StrConfigScreenReminder)
        _G[frameName .. "ignoreStacksStr"]:SetText(L.StrConfigIgnoreStacks)
        _G[frameName .. "showTooltipsStr"]:SetText(L.StrConfigShowTooltips)
        _G[frameName .. "showLootCounterDuringMSRollStr"]:SetText(L.StrConfigShowLootCounterDuringMSRoll)
        _G[frameName .. "minimapButtonStr"]:SetText(L.StrConfigMinimapButton)
        _G[frameName .. "countdownDurationStr"]:SetText(L.StrConfigCountdownDuration)
        _G[frameName .. "countdownSimpleRaidMsgStr"]:SetText(L.StrConfigCountdownSimpleRaidMsg)

        Utils.setFrameTitle(frameName, SETTINGS)
        _G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
        _G[frameName .. "DefaultsBtn"]:SetText(L.BtnDefaults)
        _G[frameName .. "CloseBtn"]:SetText(L.BtnClose)
        _G[frameName .. "DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)

        localized = true
    end

    -- UI refresh handler for the configuration frame.
    function UpdateUIFrame()
        if not configDirty then return end
        _G[frameName .. "sortAscending"]:SetChecked(addon.options.sortAscending == true)
        _G[frameName .. "useRaidWarning"]:SetChecked(addon.options.useRaidWarning == true)
        _G[frameName .. "announceOnWin"]:SetChecked(addon.options.announceOnWin == true)
        _G[frameName .. "announceOnHold"]:SetChecked(addon.options.announceOnHold == true)
        _G[frameName .. "announceOnBank"]:SetChecked(addon.options.announceOnBank == true)
        _G[frameName .. "announceOnDisenchant"]:SetChecked(addon.options.announceOnDisenchant == true)
        _G[frameName .. "lootWhispers"]:SetChecked(addon.options.lootWhispers == true)
        _G[frameName .. "countdownRollsBlock"]:SetChecked(addon.options.countdownRollsBlock == true)
        _G[frameName .. "screenReminder"]:SetChecked(addon.options.screenReminder == true)
        _G[frameName .. "ignoreStacks"]:SetChecked(addon.options.ignoreStacks == true)
        _G[frameName .. "showTooltips"]:SetChecked(addon.options.showTooltips == true)
        _G[frameName .. "showLootCounterDuringMSRoll"]:SetChecked(addon.options.showLootCounterDuringMSRoll == true)
        _G[frameName .. "minimapButton"]:SetChecked(addon.options.minimapButton == true)

        -- IMPORTANT: always update checked state (even if disabled)
        _G[frameName .. "countdownSimpleRaidMsg"]:SetChecked(addon.options.countdownSimpleRaidMsg == true)

        _G[frameName .. "countdownDuration"]:SetValue(addon.options.countdownDuration)
        _G[frameName .. "countdownDurationText"]:SetText(addon.options.countdownDuration)

        -- Dependency: if Use Raid Warnings is OFF, keep check state but grey out + disable.
        do
            local useRaidWarning = addon.options.useRaidWarning == true
            local countdownSimpleRaidMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
            local countdownSimpleRaidMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]

            if countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
                if useRaidWarning then
                    countdownSimpleRaidMsgBtn:Enable()
                    countdownSimpleRaidMsgStr:SetTextColor(
                        HIGHLIGHT_FONT_COLOR.r,
                        HIGHLIGHT_FONT_COLOR.g,
                        HIGHLIGHT_FONT_COLOR.b
                    )
                else
                    countdownSimpleRaidMsgBtn:Disable()
                    countdownSimpleRaidMsgStr:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end

        configDirty = false
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end
end
