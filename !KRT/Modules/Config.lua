local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper

-- Configuration Frame Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Config = addon.Config or {}
    local module = addon.Config
    local L = addon.L
    local frameName

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    local localized = false
    local configDirty = false

    -- Frame update
    local UpdateUIFrame
    local updateInterval = C.UPDATE_INTERVAL_CONFIG

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    local LocalizeUIFrame
    local function MergeDefaults(target, defaults)
        for key, value in pairs(defaults) do
            if type(value) == "table" then
                if type(target[key]) ~= "table" then
                    target[key] = {}
                end
                MergeDefaults(target[key], value)
            elseif target[key] == nil then
                target[key] = value
            end
        end
    end

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    --
    -- Default options for the addon.
    --
    local defaultOptions = {
        sortAscending          = false,
        useRaidWarning         = true,
        announceOnWin          = true,
        announceOnHold         = true,
        announceOnBank         = false,
        announceOnDisenchant   = false,
        lootWhispers           = false,
        screenReminder         = true,
        ignoreStacks           = false,
        showTooltips           = true,
        minimapButton          = true,
        countdownSimpleRaidMsg = false,
        countdownDuration      = 5,
        countdownRollsBlock    = true,
    }

    --
    -- Loads the default options into the settings table.
    --
    local function LoadDefaultOptions()
        if type(KRT_Options) ~= "table" then
            KRT_Options = {}
        end
        local options = KRT_Options
        twipe(options)
        addon.tCopy(options, defaultOptions)
        addon.options = options
        configDirty = true
        addon:info(L.MsgDefaultsRestored)
    end

    --
    -- Loads addon options from saved variables, filling in defaults.
    --
    local function LoadOptions()
        if type(KRT_Options) ~= "table" then
            KRT_Options = {}
        end
        MergeDefaults(KRT_Options, defaultOptions)
        addon.options = KRT_Options

        Utils.applyDebugSetting(addon.options.debug)
        configDirty = true

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

    --
    -- Public method to reset options to default.
    --
    function module:Default()
        return LoadDefaultOptions()
    end

    --
    -- OnLoad handler for the configuration frame.
    --
    function module:OnLoad(frame)
        if not frame then return end
        UIConfig = frame
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")

        -- Localize once (no per-tick calls)
        LocalizeUIFrame()

        frame:SetScript("OnUpdate", UpdateUIFrame)
    end

    --
    -- Toggles the visibility of the configuration frame.
    --
    function module:Toggle()
        local wasShown = UIConfig and UIConfig:IsShown()
        Utils.toggle(UIConfig)
        if UIConfig and UIConfig:IsShown() and not wasShown then
            configDirty = true
        end
    end

    --
    -- Hides the configuration frame.
    --
    function module:Hide()
        Utils.hideFrame(UIConfig)
    end

    --
    -- OnClick handler for option controls.
    --
    function module:OnClick(btn)
        if not btn then return end
        frameName = frameName or btn:GetParent():GetName()
        local value, name = nil, btn:GetName()

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
        Utils.triggerEvent("Config" .. name, value)
        KRT_Options[name] = value

        configDirty = true
    end

    --
    -- Localizes UI elements.
    --
    function LocalizeUIFrame()
        if localized then
            return
        end

        -- frameName must be ready here (OnLoad sets it before calling)
        if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
            Utils.setTextByName(frameName, "sortAscendingStr", L.StrConfigSortAscending)
            Utils.setTextByName(frameName, "useRaidWarningStr", L.StrConfigUseRaidWarning)
            Utils.setTextByName(frameName, "announceOnWinStr", L.StrConfigAnnounceOnWin)
            Utils.setTextByName(frameName, "announceOnHoldStr", L.StrConfigAnnounceOnHold)
            Utils.setTextByName(frameName, "announceOnBankStr", L.StrConfigAnnounceOnBank)
            Utils.setTextByName(frameName, "announceOnDisenchantStr", L.StrConfigAnnounceOnDisenchant)
            Utils.setTextByName(frameName, "lootWhispersStr", L.StrConfigLootWhisper)
            Utils.setTextByName(frameName, "countdownRollsBlockStr", L.StrConfigCountdownRollsBlock)
            Utils.setTextByName(frameName, "screenReminderStr", L.StrConfigScreenReminder)
            Utils.setTextByName(frameName, "ignoreStacksStr", L.StrConfigIgnoreStacks)
            Utils.setTextByName(frameName, "showTooltipsStr", L.StrConfigShowTooltips)
            Utils.setTextByName(frameName, "minimapButtonStr", L.StrConfigMinimapButton)
            Utils.setTextByName(frameName, "countdownDurationStr", L.StrConfigCountdownDuration)
            Utils.setTextByName(frameName, "countdownSimpleRaidMsgStr", L.StrConfigCountdownSimpleRaidMsg)
        end

        Utils.setFrameTitle(frameName, SETTINGS)
        Utils.setTextByName(frameName, "AboutStr", L.StrConfigAbout)
        _G[frameName .. "DefaultsBtn"]:SetScript("OnClick", LoadDefaultOptions)

        localized = true
    end

    --
    -- OnUpdate handler for the configuration frame.
    --
    function UpdateUIFrame(self, elapsed)
        if configDirty then
            Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
                Utils.setCheckedByName(frameName, "sortAscending", addon.options.sortAscending)
                Utils.setCheckedByName(frameName, "useRaidWarning", addon.options.useRaidWarning)
                Utils.setCheckedByName(frameName, "announceOnWin", addon.options.announceOnWin)
                Utils.setCheckedByName(frameName, "announceOnHold", addon.options.announceOnHold)
                Utils.setCheckedByName(frameName, "announceOnBank", addon.options.announceOnBank)
                Utils.setCheckedByName(frameName, "announceOnDisenchant", addon.options.announceOnDisenchant)
                Utils.setCheckedByName(frameName, "lootWhispers", addon.options.lootWhispers)
                Utils.setCheckedByName(frameName, "countdownRollsBlock", addon.options.countdownRollsBlock)
                Utils.setCheckedByName(frameName, "screenReminder", addon.options.screenReminder)
                Utils.setCheckedByName(frameName, "ignoreStacks", addon.options.ignoreStacks)
                Utils.setCheckedByName(frameName, "showTooltips", addon.options.showTooltips)
                Utils.setCheckedByName(frameName, "minimapButton", addon.options.minimapButton)

                -- IMPORTANT: always update checked state (even if disabled)
                Utils.setCheckedByName(frameName, "countdownSimpleRaidMsg", addon.options.countdownSimpleRaidMsg)

                _G[frameName .. "countdownDuration"]:SetValue(addon.options.countdownDuration)
                Utils.setTextByName(frameName, "countdownDurationText", addon.options.countdownDuration)

                -- Dependency: if Use Raid Warnings is OFF, keep check state but grey out + disable.
                do
                    local useRaidWarning = addon.options.useRaidWarning == true
                    local countdownSimpleRaidMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
                    local countdownSimpleRaidMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]

                    if countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
                        Utils.enableDisable(countdownSimpleRaidMsgBtn, useRaidWarning)
                        Utils.setTextColorByEnabled(countdownSimpleRaidMsgStr, useRaidWarning)
                    end
                end

                configDirty = false
            end)
        end
    end
end
