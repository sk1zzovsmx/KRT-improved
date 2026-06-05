-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: emits option-specific events; listens OptionsLoaded
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L

local Widgets = feature.Widgets
local Database = feature.Database
local Options = feature.Options
local Frames = feature.Frames
local Strings = feature.Strings
local UIScaffold = feature.UIScaffold
local OptionsLayout = feature.OptionsLayout
local Events = feature.Events
local Bus = feature.Bus
local Services = feature.Services

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G

local format = string.format
local strlen = string.len
local strsub = string.sub
local type, tostring, tonumber = type, tostring, tonumber

local UIFacade = feature.UI

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Widgets/Config", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
            "Modules/UI/OptionsLayout",
        },
    })
    registry.SetLoaded("Widgets/Config")
end

-- =========== Configuration Frame Module  =========== --
do
    if not UIFacade:IsEnabled("Config") then
        return
    end

    Widgets.Config = Widgets.Config or {}
    local module = Widgets.Config
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui

    -- Namespace registration: generic UI options (tooltip toggle).
    -- Other options exposed by this widget are owned by their source modules
    -- (Master, Loot, Rolls, Reserves, Minimap, LootCounter).
    Options.AddNamespace("UI", {
        showTooltips = true,
    })

    local getFrame = makeModuleFrameGetter(module, "KRTConfig")
    -- ----- Internal state ----- --

    local countdownDurationValues = { 3, 5, 7, 10, 13, 15, 20, 25, 30, 40, 50, 60 }
    local loggerLootQualityOptions = {
        { value = 0, labelKey = "StrLootQualityPoor" },
        { value = 2, labelKey = "StrLootQualityUncommon" },
        { value = 3, labelKey = "StrLootQualityRare" },
        { value = 4, labelKey = "StrLootQualityEpic" },
        { value = 5, labelKey = "StrLootQualityLegendary" },
    }
    local MIN_COUNTDOWN = countdownDurationValues[1]
    local MAX_COUNTDOWN = countdownDurationValues[#countdownDurationValues]
    local interfacePanelFrameName = "KRTInterfaceOptionsPanel"
    local masterLootPanelFrameName = "KRTInterfaceOptionsMasterLootPanel"
    local masterLootContentFrameName = "KRTInterfaceOptionsMasterLootPanelScrollChild"
    local lootHistoryPanelFrameName = "KRTInterfaceOptionsLootHistoryPanel"
    local lootHistoryContentFrameName = "KRTInterfaceOptionsLootHistoryPanelScrollChild"
    local lfmSpamPanelFrameName = "KRTInterfaceOptionsLFMSpamPanel"
    local lfmSpamContentFrameName = "KRTInterfaceOptionsLFMSpamPanelScrollChild"
    local raidWarningPanelFrameName = "KRTInterfaceOptionsRaidWarningPanel"
    local raidWarningContentFrameName = "KRTInterfaceOptionsRaidWarningPanelScrollChild"
    local helpPanelFrameName = "KRTInterfaceOptionsHelpPanel"
    local helpContentFrameName = "KRTInterfaceOptionsHelpPanelScrollChild"
    local cleanupPopupFrameName = "KRTLootHistoryCleanupPopup"
    local interfacePanelBound = false
    local lootHistoryPanelBound = false
    local cleanupPopupBound = false
    local lfmSpamPanelBound = false
    local raidWarningPanelBound = false
    local interfacePanelsRegistered = false
    local refreshInterfaceOptionsPanel

    local optionSuffixes = {
        "sortAscending",
        "useRaidWarning",
        "countdownSimpleRaidMsg",
        "announceOnWin",
        "announceOnHold",
        "announceOnBank",
        "announceOnDisenchant",
        "lootWhispers",
        "softResWhisperReplies",
        "countdownRollsBlock",
        "screenReminder",
        "ignoreStacks",
        "showTooltips",
        "showLootCounterDuringMSRoll",
        "minimapButton",
    }

    local optionNamespaces = {
        announceOnBank = "Master",
        announceOnDisenchant = "Master",
        announceOnHold = "Master",
        announceOnWin = "Master",
        countdownDuration = "Rolls",
        countdownRollsBlock = "Rolls",
        countdownSimpleRaidMsg = "Rolls",
        ignoreGroupLoot = "Logger",
        ignoreSelectionThreshold = "Logger",
        ignoreStacks = "Loot",
        loggerLootQualityThreshold = "Logger",
        lootWhispers = "Loot",
        minimapButton = "Minimap",
        persistentSync = "Logger",
        screenReminder = "Master",
        showLootCounterDuringMSRoll = "LootCounter",
        showTooltips = "UI",
        softResWhisperReplies = "Reserves",
        sortAscending = "Master",
        syncPushPlayer = "Logger",
        syncRequirePlayer = "Logger",
        useRaidWarning = "Master",
    }

    -- ----- Private helpers ----- --
    local function collectConfigRefs(frame, includeClose)
        local refs = {
            defaultsBtn = Frames.GetRef(frame, "DefaultsBtn"),
            countdownDuration = Frames.GetRef(frame, "countdownDuration"),
            options = {},
        }
        if includeClose then
            refs.closeBtn = Frames.GetRef(frame, "CloseBtn")
        end
        for i = 1, #optionSuffixes do
            local suffix = optionSuffixes[i]
            refs.options[suffix] = Frames.GetRef(frame, suffix)
        end
        return refs
    end

    function UI.AcquireRefs(frame)
        return collectConfigRefs(frame, true)
    end

    local function getOptionConfig(key)
        local namespace = optionNamespaces[key]
        return namespace and Options and Options.Get and Options.Get(namespace) or nil
    end

    local function getOption(key)
        local cfg = getOptionConfig(key)
        if cfg and cfg.Get then
            return cfg:Get(key)
        end
        return nil
    end

    local function setOption(key, value)
        local cfg = getOptionConfig(key)
        if cfg and cfg.Set then
            return cfg:Set(key, value)
        end
        return false
    end

    -- ----- Public methods ----- --

    local function setText(frameName, suffix, value)
        local widget = _G[frameName .. suffix]
        if widget then
            widget:SetText(value)
        end
    end

    local function setChecked(frameName, suffix, checked)
        local widget = _G[frameName .. suffix]
        if widget then
            widget:SetChecked(checked == true)
        end
    end

    local function getChecked(frameOrName, suffix)
        local widget = Frames.GetRef(frameOrName, suffix)
        if widget and widget.GetChecked then
            local checked = widget:GetChecked()
            return checked == true or checked == 1
        end
        return false
    end

    local function getEditBoxText(frameOrName, suffix)
        local widget = Frames.GetRef(frameOrName, suffix)
        if widget and widget.GetText then
            return Strings.TrimText(widget:GetText() or "") or ""
        end
        return ""
    end

    local function setEditBoxText(frameName, suffix, value)
        local widget = Frames.GetRef(frameName, suffix)
        if widget and widget.SetText then
            widget:SetText(value or "")
        end
    end

    local function formatCleanupOptionLabel(label, count)
        if count == nil then
            return label
        end
        return format("%s (%d)", label or "", tonumber(count) or 0)
    end

    local function requestController(controllerName, methodName, ...)
        if Database and Database.RequestControllerMethod then
            return Database.RequestControllerMethod(controllerName, methodName, ...)
        end
        return nil
    end

    local function normalizeCountdownDuration(value)
        local duration = tonumber(value) or 5
        local selected = countdownDurationValues[1]
        local selectedDelta = math.abs(duration - selected)
        for i = 2, #countdownDurationValues do
            local candidate = countdownDurationValues[i]
            local delta = math.abs(duration - candidate)
            if delta < selectedDelta then
                selected = candidate
                selectedDelta = delta
            end
        end
        return selected
    end

    local function normalizeLoggerLootQualityThreshold(value)
        local threshold = tonumber(value) or 4
        for i = 1, #loggerLootQualityOptions do
            if loggerLootQualityOptions[i].value == threshold then
                return threshold
            end
        end
        return 4
    end

    local function getLoggerLootQualityLabel(value)
        local threshold = normalizeLoggerLootQualityThreshold(value)
        for i = 1, #loggerLootQualityOptions do
            local option = loggerLootQualityOptions[i]
            if option.value == threshold then
                return L[option.labelKey] or tostring(threshold)
            end
        end
        return tostring(threshold)
    end

    local function setLoggerLootQualityDropDown(dropDown, value, enabled)
        if not dropDown then
            return
        end

        local threshold = normalizeLoggerLootQualityThreshold(value)
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(dropDown, getLoggerLootQualityLabel(threshold))
        end
        if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(dropDown, threshold)
        end
        if enabled then
            if UIDropDownMenu_EnableDropDown then
                UIDropDownMenu_EnableDropDown(dropDown)
            end
        elseif UIDropDownMenu_DisableDropDown then
            UIDropDownMenu_DisableDropDown(dropDown)
        end
    end

    local function setCountdownDurationDisplay(frameName, value)
        local duration = normalizeCountdownDuration(value)
        local slider = _G[frameName .. "countdownDuration"]
        if slider then
            slider._krtSuppressOption = true
            slider:SetValue(duration)
            slider._krtSuppressOption = nil
        end
        setText(frameName, "countdownDurationText", duration)
        return duration
    end

    local function setConfigTitle(frameName, titleText, plainTitle)
        if plainTitle then
            setText(frameName, "Title", titleText)
        else
            Frames.SetFrameTitle(frameName, titleText or SETTINGS)
        end
    end

    local function applyOptionsLayout(frameName, rows, cfg)
        if OptionsLayout and OptionsLayout.Apply then
            return OptionsLayout.Apply(frameName, rows, cfg)
        end
        return 0
    end

    local function layoutRootPanel()
        applyOptionsLayout(interfacePanelFrameName, {
            { type = "title", suffix = "Title", gap = 18 },
            { type = "text", title = "OverviewTitle", body = "OverviewBody", bodyHeight = 46, gap = 18 },
            { type = "text", title = "WhatTitle", body = "WhatBody", bodyHeight = 58, gap = 18 },
            { type = "text", title = "HowTitle", body = "HowBody", bodyHeight = 58, gap = 18 },
            { type = "text", title = "WhyTitle", body = "WhyBody", bodyHeight = 58, gap = 0 },
        }, {
            contentWidth = 440,
            scrollChildWidth = 560,
            minHeight = 560,
        })
    end

    local function getOptionsPanelLayoutCfg()
        return {
            contentWidth = 380,
            scrollChildWidth = 420,
            textWidth = 240,
            commandWidth = 105,
            columnGap = 12,
            rowGap = 7,
            bottomPadding = 28,
            minHeight = 500,
        }
    end

    local function layoutMasterLootPanel()
        local rows = {
            { type = "title", suffix = "Title", gap = 16 },
        }
        for i = 1, #optionSuffixes do
            local suffix = optionSuffixes[i]
            rows[#rows + 1] = {
                type = "check",
                check = suffix,
                label = suffix .. "Str",
                desc = suffix .. "Desc",
                descHeight = 22,
                height = 40,
                gap = 4,
            }
        end
        rows[#rows + 1] = {
            type = "slider",
            title = "countdownDurationStr",
            desc = "countdownDurationDesc",
            control = "countdownDuration",
            descHeight = 20,
            height = 74,
            gap = 12,
        }
        rows[#rows + 1] = { type = "section", suffix = "PresetsTitle", gap = 10 }
        rows[#rows + 1] = {
            type = "command",
            title = "DefaultsPresetTitle",
            desc = "DefaultsPresetDesc",
            button = "DefaultsBtn",
            descHeight = 34,
            height = 52,
            gap = 4,
        }
        rows[#rows + 1] = {
            type = "command",
            title = "QuietPresetTitle",
            desc = "QuietPresetDesc",
            button = "QuietPresetBtn",
            descHeight = 34,
            height = 52,
            gap = 4,
        }
        rows[#rows + 1] = {
            type = "command",
            title = "StandardPresetTitle",
            desc = "StandardPresetDesc",
            button = "StandardPresetBtn",
            descHeight = 34,
            height = 52,
            gap = 4,
        }
        rows[#rows + 1] = {
            type = "command",
            title = "VerbosePresetTitle",
            desc = "VerbosePresetDesc",
            button = "VerbosePresetBtn",
            descHeight = 34,
            height = 52,
            gap = 10,
        }
        rows[#rows + 1] = {
            type = "text",
            title = "AnnouncementPreviewTitle",
            body = "AnnouncementPreviewBody",
            bodyHeight = 88,
            gap = 0,
        }
        applyOptionsLayout(masterLootContentFrameName, rows, getOptionsPanelLayoutCfg())
    end

    local function layoutLootHistoryPanel()
        applyOptionsLayout(lootHistoryContentFrameName, {
            { type = "title", suffix = "Title", gap = 16 },
            { type = "text", title = "ReportTitle", body = "ReportSummary", bodyHeight = 116, gap = 16 },
            { type = "section", suffix = "SyncTitle", gap = 10 },
            {
                type = "check",
                check = "PersistentSyncCheck",
                label = "PersistentSyncStr",
                desc = "PersistentSyncDesc",
                height = 42,
                gap = 6,
            },
            {
                type = "check",
                check = "IgnoreGroupLootCheck",
                label = "IgnoreGroupLootStr",
                desc = "IgnoreGroupLootDesc",
                height = 42,
                gap = 6,
            },
            {
                type = "check",
                check = "IgnoreSelectionThresholdCheck",
                label = "IgnoreSelectionThresholdStr",
                desc = "IgnoreSelectionThresholdDesc",
                height = 42,
                gap = 8,
            },
            {
                type = "dropdown",
                title = "LoggerLootQualityTitle",
                desc = "LoggerLootQualityDesc",
                dropdown = "LoggerLootQualityDropDown",
                descHeight = 34,
                height = 56,
                gap = 8,
            },
            {
                type = "editCommand",
                title = "RequireDatabaseTitle",
                desc = "RequireDatabaseDesc",
                editBox = "RequireDatabaseEditBox",
                button = "RequireDatabaseBtn",
                descHeight = 34,
                height = 60,
                gap = 8,
            },
            {
                type = "editCommand",
                title = "PushDatabaseTitle",
                desc = "PushDatabaseDesc",
                editBox = "PushDatabaseEditBox",
                button = "PushDatabaseBtn",
                descHeight = 34,
                height = 60,
                gap = 8,
            },
            {
                type = "command",
                title = "SyncNowTitle",
                desc = "SyncNowDesc",
                button = "SyncNowBtn",
                descHeight = 34,
                height = 54,
                gap = 14,
            },
            { type = "section", suffix = "DataHealthTitle", gap = 10 },
            {
                type = "command",
                title = "ScanHistoryTitle",
                desc = "ScanHistoryDesc",
                button = "ScanHistoryBtn",
                descHeight = 54,
                height = 74,
                gap = 14,
            },
            { type = "section", suffix = "MaintenanceTitle", gap = 10 },
            {
                type = "command",
                title = "PurgeHistoryTitle",
                desc = "PurgeHistoryDesc",
                button = "PurgeHistoryBtn",
                descHeight = 54,
                height = 74,
                gap = 8,
            },
            {
                type = "command",
                title = "RebuildSourcesTitle",
                desc = "RebuildSourcesDesc",
                button = "RebuildSourcesBtn",
                descHeight = 54,
                height = 74,
                gap = 8,
            },
            {
                type = "command",
                title = "CleanUpTitle",
                desc = "CleanUpDesc",
                button = "CleanUpBtn",
                descHeight = 54,
                height = 74,
                gap = 0,
            },
        }, getOptionsPanelLayoutCfg())
    end

    local function layoutLFMSpamPanel()
        applyOptionsLayout(lfmSpamContentFrameName, {
            { type = "title", suffix = "Title", gap = 16 },
            { type = "text", title = "MessagePreviewTitle", body = "MessagePreviewBody", bodyHeight = 66, gap = 8 },
            {
                type = "buttonRow",
                buttons = { "RefreshPreviewBtn", "ClearPreviewBtn" },
                buttonWidth = 105,
                buttonGap = 12,
                gap = 14,
            },
            { type = "text", title = "SafetyTitle", body = "SafetyBody", bodyHeight = 86, gap = 10 },
            {
                type = "buttonRow",
                buttons = { "OpenBtn", "StartBtn", "StopBtn" },
                buttonWidth = 105,
                buttonGap = 12,
                gap = 0,
            },
        }, getOptionsPanelLayoutCfg())
    end

    local function layoutRaidWarningPanel()
        applyOptionsLayout(raidWarningContentFrameName, {
            { type = "title", suffix = "Title", gap = 16 },
            { type = "text", title = "TemplatesTitle", body = "TemplatesBody", bodyHeight = 44, gap = 8 },
            {
                type = "buttonRow",
                buttons = { "PreviewBtn", "OpenBtn" },
                buttonWidth = 105,
                buttonGap = 12,
                gap = 14,
            },
            { type = "text", title = "PreviewTitle", body = "PreviewBody", bodyHeight = 112, gap = 12 },
            { type = "text", title = "PermissionTitle", body = "PermissionBody", bodyHeight = 54, gap = 14 },
            { type = "section", suffix = "MaintenanceTitle", gap = 10 },
            {
                type = "command",
                title = "ClearSavedTitle",
                desc = "ClearSavedDesc",
                button = "ClearSavedBtn",
                descHeight = 42,
                height = 62,
                gap = 0,
            },
        }, getOptionsPanelLayoutCfg())
    end

    local function layoutHelpPanel()
        applyOptionsLayout(helpContentFrameName, {
            { type = "title", suffix = "Title", gap = 16 },
            { type = "text", title = "MasterLootTitle", body = "MasterLootBody", bodyHeight = 76, gap = 12 },
            { type = "text", title = "LootHistoryTitle", body = "LootHistoryBody", bodyHeight = 94, gap = 12 },
            { type = "text", title = "LFMSpamTitle", body = "LFMSpamBody", bodyHeight = 86, gap = 12 },
            { type = "text", title = "RaidWarningTitle", body = "RaidWarningBody", bodyHeight = 64, gap = 12 },
            {
                type = "text",
                title = "CommandPermissionsTitle",
                body = "CommandPermissionsBody",
                bodyHeight = 80,
                gap = 12,
            },
            { type = "text", title = "DiagnosticsTitle", body = "DiagnosticsBody", bodyHeight = 68, gap = 0 },
        }, {
            contentWidth = 380,
            scrollChildWidth = 420,
            rowGap = 7,
            bottomPadding = 28,
            minHeight = 640,
        })
    end

    local function layoutCleanupPopup()
        applyOptionsLayout(cleanupPopupFrameName, {
            { type = "title", suffix = "Title", leftX = 20, width = 340, height = 20, gap = 10 },
            { type = "body", suffix = "Body", leftX = 30, width = 320, height = 34, gap = 12 },
            {
                type = "check",
                check = "EmptyRaidsCheck",
                label = "EmptyRaidsLabel",
                desc = "EmptyRaidsDesc",
                leftX = 30,
                textWidth = 292,
                descHeight = 34,
                height = 54,
                gap = 8,
            },
            {
                type = "check",
                check = "NonEpicLootCheck",
                label = "NonEpicLootLabel",
                desc = "NonEpicLootDesc",
                leftX = 30,
                textWidth = 292,
                descHeight = 34,
                height = 54,
                gap = 8,
            },
            {
                type = "check",
                check = "NoBossEncounterCheck",
                label = "NoBossEncounterLabel",
                desc = "NoBossEncounterDesc",
                leftX = 30,
                textWidth = 292,
                descHeight = 34,
                height = 54,
                gap = 12,
            },
            {
                type = "buttonRow",
                buttons = { "DeleteBtn", "CancelBtn" },
                leftX = 62,
                buttonWidth = 110,
                buttonGap = 40,
                gap = 0,
            },
        }, {
            contentWidth = 340,
            scrollChildWidth = 380,
            rowGap = 6,
            bottomPadding = 18,
            minHeight = 320,
        })
    end

    local function localizeRootPanel()
        setText(interfacePanelFrameName, "Title", L.StrConfigPanelTitle)
        setText(interfacePanelFrameName, "OverviewTitle", L.StrConfigRootOverviewTitle)
        setText(interfacePanelFrameName, "OverviewBody", L.StrConfigRootOverviewBody)
        setText(interfacePanelFrameName, "WhatTitle", L.StrConfigRootWhatTitle)
        setText(interfacePanelFrameName, "WhatBody", L.StrConfigRootWhatBody)
        setText(interfacePanelFrameName, "HowTitle", L.StrConfigRootHowTitle)
        setText(interfacePanelFrameName, "HowBody", L.StrConfigRootHowBody)
        setText(interfacePanelFrameName, "WhyTitle", L.StrConfigRootWhyTitle)
        setText(interfacePanelFrameName, "WhyBody", L.StrConfigRootWhyBody)
        layoutRootPanel()
    end

    local function updateMasterLootPreview(frameName)
        if not frameName then
            return
        end
        local channel = (getOption("useRaidWarning") == true) and (RAID_WARNING or "Raid Warning") or "RAID"
        local countdownMode = (getOption("countdownSimpleRaidMsg") == true) and L.StrConfigMasterLootPreviewSimple or L.StrConfigMasterLootPreviewDetailed
        local countdownDuration = tostring(getOption("countdownDuration") or 5)
        local lines = {
            format(L.StrConfigMasterLootPreviewWin or "Winner announce: %s", channel),
            format(L.StrConfigMasterLootPreviewHold or "Hold announce: %s", getOption("announceOnHold") and "on" or "off"),
            format(L.StrConfigMasterLootPreviewBank or "Bank announce: %s", getOption("announceOnBank") and "on" or "off"),
            format(L.StrConfigMasterLootPreviewDisenchant or "Disenchant announce: %s", getOption("announceOnDisenchant") and "on" or "off"),
            format(L.StrConfigMasterLootPreviewCountdown or "Countdown: %s sec, %s", countdownDuration, countdownMode),
        }
        setText(frameName, "AnnouncementPreviewBody", table.concat(lines, "\n"))
    end

    local function setOptions(values)
        if type(values) ~= "table" then
            return
        end
        for key, value in pairs(values) do
            setOption(key, value)
            local eventName = Events.GetConfigOptionChanged and Events.GetConfigOptionChanged(key)
            if eventName then
                Bus.TriggerEvent(eventName, value)
            end
        end
    end

    function module:ApplyMasterLootPreset(presetName)
        if presetName == "quiet" then
            setOptions({
                useRaidWarning = false,
                countdownSimpleRaidMsg = true,
                announceOnWin = true,
                announceOnHold = false,
                announceOnBank = false,
                announceOnDisenchant = false,
                lootWhispers = false,
                softResWhisperReplies = true,
                countdownDuration = 5,
            })
        elseif presetName == "verbose" then
            setOptions({
                useRaidWarning = true,
                countdownSimpleRaidMsg = false,
                announceOnWin = true,
                announceOnHold = true,
                announceOnBank = true,
                announceOnDisenchant = true,
                lootWhispers = true,
                softResWhisperReplies = true,
                countdownDuration = 10,
            })
        else
            setOptions({
                useRaidWarning = true,
                countdownSimpleRaidMsg = false,
                announceOnWin = true,
                announceOnHold = true,
                announceOnBank = false,
                announceOnDisenchant = false,
                lootWhispers = false,
                softResWhisperReplies = true,
                countdownDuration = 5,
            })
        end
        module:RequestRefresh("master_loot_preset")
        refreshInterfaceOptionsPanel()
        addon:info(L.MsgConfigPresetApplied)
    end

    local function localizeConfigControls(frameName, titleText, plainTitle)
        if not frameName then
            return
        end

        setText(frameName, "sortAscendingStr", L.StrConfigSortAscending)
        setText(frameName, "useRaidWarningStr", L.StrConfigUseRaidWarning)
        setText(frameName, "announceOnWinStr", L.StrConfigAnnounceOnWin)
        setText(frameName, "announceOnHoldStr", L.StrConfigAnnounceOnHold)
        setText(frameName, "announceOnBankStr", L.StrConfigAnnounceOnBank)
        setText(frameName, "announceOnDisenchantStr", L.StrConfigAnnounceOnDisenchant)
        setText(frameName, "lootWhispersStr", L.StrConfigLootWhisper)
        setText(frameName, "softResWhisperRepliesStr", L.StrConfigSoftResWhisperReplies)
        setText(frameName, "countdownRollsBlockStr", L.StrConfigCountdownRollsBlock)
        setText(frameName, "screenReminderStr", L.StrConfigScreenReminder)
        setText(frameName, "ignoreStacksStr", L.StrConfigIgnoreStacks)
        setText(frameName, "showTooltipsStr", L.StrConfigShowTooltips)
        setText(frameName, "showLootCounterDuringMSRollStr", L.StrConfigShowLootCounterDuringMSRoll)
        setText(frameName, "minimapButtonStr", L.StrConfigMinimapButton)
        setText(frameName, "countdownDurationStr", L.StrConfigCountdownDuration)
        setText(frameName, "countdownSimpleRaidMsgStr", L.StrConfigCountdownSimpleRaidMsg)
        setText(frameName, "sortAscendingDesc", L.StrConfigSortAscendingDesc)
        setText(frameName, "useRaidWarningDesc", L.StrConfigUseRaidWarningDesc)
        setText(frameName, "announceOnWinDesc", L.StrConfigAnnounceOnWinDesc)
        setText(frameName, "announceOnHoldDesc", L.StrConfigAnnounceOnHoldDesc)
        setText(frameName, "announceOnBankDesc", L.StrConfigAnnounceOnBankDesc)
        setText(frameName, "announceOnDisenchantDesc", L.StrConfigAnnounceOnDisenchantDesc)
        setText(frameName, "lootWhispersDesc", L.StrConfigLootWhisperDesc)
        setText(frameName, "softResWhisperRepliesDesc", L.StrConfigSoftResWhisperRepliesDesc)
        setText(frameName, "countdownRollsBlockDesc", L.StrConfigCountdownRollsBlockDesc)
        setText(frameName, "screenReminderDesc", L.StrConfigScreenReminderDesc)
        setText(frameName, "ignoreStacksDesc", L.StrConfigIgnoreStacksDesc)
        setText(frameName, "showTooltipsDesc", L.StrConfigShowTooltipsDesc)
        setText(frameName, "showLootCounterDuringMSRollDesc", L.StrConfigShowLootCounterDuringMSRollDesc)
        setText(frameName, "minimapButtonDesc", L.StrConfigMinimapButtonDesc)
        setText(frameName, "countdownDurationDesc", L.StrConfigCountdownDurationDesc)
        setText(frameName, "countdownSimpleRaidMsgDesc", L.StrConfigCountdownSimpleRaidMsgDesc)
        setText(frameName, "PresetsTitle", L.StrConfigMasterLootPresetsTitle)
        setText(frameName, "DefaultsPresetTitle", L.StrConfigMasterLootPresetDefaultsTitle)
        setText(frameName, "DefaultsPresetDesc", L.StrConfigMasterLootPresetDefaultsDesc)
        setText(frameName, "QuietPresetTitle", L.StrConfigMasterLootPresetQuietTitle)
        setText(frameName, "QuietPresetDesc", L.StrConfigMasterLootPresetQuietDesc)
        setText(frameName, "StandardPresetTitle", L.StrConfigMasterLootPresetStandardTitle)
        setText(frameName, "StandardPresetDesc", L.StrConfigMasterLootPresetStandardDesc)
        setText(frameName, "VerbosePresetTitle", L.StrConfigMasterLootPresetVerboseTitle)
        setText(frameName, "VerbosePresetDesc", L.StrConfigMasterLootPresetVerboseDesc)
        setText(frameName, "QuietPresetBtn", L.BtnConfigPresetQuiet)
        setText(frameName, "StandardPresetBtn", L.BtnConfigPresetStandard)
        setText(frameName, "VerbosePresetBtn", L.BtnConfigPresetVerbose)
        setText(frameName, "AnnouncementPreviewTitle", L.StrConfigMasterLootAnnouncementPreviewTitle)

        setConfigTitle(frameName, titleText, plainTitle)
        setText(frameName, "DefaultsBtn", L.BtnDefaults)
        setText(frameName, "CloseBtn", L.BtnClose)
        if frameName == masterLootContentFrameName then
            layoutMasterLootPanel()
        end
    end

    local function localizeHelpPanel()
        setText(helpContentFrameName, "Title", L.StrConfigPanelHelp)
        setText(helpContentFrameName, "MasterLootTitle", L.StrConfigHelpMasterLootTitle)
        setText(helpContentFrameName, "MasterLootBody", L.StrConfigHelpMasterLootBody)
        setText(helpContentFrameName, "LootHistoryTitle", L.StrConfigHelpLootHistoryTitle)
        setText(helpContentFrameName, "LootHistoryBody", L.StrConfigHelpLootHistoryBody)
        setText(helpContentFrameName, "LFMSpamTitle", L.StrConfigHelpLFMSpamTitle)
        setText(helpContentFrameName, "LFMSpamBody", L.StrConfigHelpLFMSpamBody)
        setText(helpContentFrameName, "RaidWarningTitle", L.StrConfigHelpRaidWarningTitle)
        setText(helpContentFrameName, "RaidWarningBody", L.StrConfigHelpRaidWarningBody)
        setText(helpContentFrameName, "CommandPermissionsTitle", L.StrConfigHelpCommandPermissionsTitle)
        setText(helpContentFrameName, "CommandPermissionsBody", L.StrConfigHelpCommandPermissionsBody)
        setText(helpContentFrameName, "DiagnosticsTitle", L.StrConfigHelpDiagnosticsTitle)
        setText(helpContentFrameName, "DiagnosticsBody", L.StrConfigHelpDiagnosticsBody)
        layoutHelpPanel()
    end

    local function localizeLootHistoryPanel()
        setText(lootHistoryContentFrameName, "Title", L.StrLootHistory)
        setText(lootHistoryContentFrameName, "ReportTitle", L.StrConfigLootHistoryReportTitle)
        setText(lootHistoryContentFrameName, "SyncTitle", L.StrConfigLootHistorySyncTitle)
        setText(lootHistoryContentFrameName, "PersistentSyncStr", L.StrConfigLootHistoryPersistentSync)
        setText(lootHistoryContentFrameName, "PersistentSyncDesc", L.StrConfigLootHistoryPersistentSyncDesc)
        setText(lootHistoryContentFrameName, "IgnoreGroupLootStr", L.StrConfigLootHistoryIgnoreGroupLoot)
        setText(lootHistoryContentFrameName, "IgnoreGroupLootDesc", L.StrConfigLootHistoryIgnoreGroupLootDesc)
        setText(lootHistoryContentFrameName, "IgnoreSelectionThresholdStr", L.StrConfigLootHistoryIgnoreSelectionThreshold)
        setText(lootHistoryContentFrameName, "IgnoreSelectionThresholdDesc", L.StrConfigLootHistoryIgnoreSelectionThresholdDesc)
        setText(lootHistoryContentFrameName, "LoggerLootQualityTitle", L.StrConfigLootHistoryLoggerLootQuality)
        setText(lootHistoryContentFrameName, "LoggerLootQualityDesc", L.StrConfigLootHistoryLoggerLootQualityDesc)
        setText(lootHistoryContentFrameName, "RequireDatabaseTitle", L.StrConfigLootHistoryRequireDatabaseTitle)
        setText(lootHistoryContentFrameName, "RequireDatabaseDesc", L.StrConfigLootHistoryRequireDatabaseDesc)
        setText(lootHistoryContentFrameName, "PushDatabaseTitle", L.StrConfigLootHistoryPushDatabaseTitle)
        setText(lootHistoryContentFrameName, "PushDatabaseDesc", L.StrConfigLootHistoryPushDatabaseDesc)
        setText(lootHistoryContentFrameName, "SyncNowTitle", L.StrConfigLootHistorySyncNowTitle)
        setText(lootHistoryContentFrameName, "SyncNowDesc", L.StrConfigLootHistorySyncNowDesc)
        setText(lootHistoryContentFrameName, "RequireDatabaseBtn", L.BtnLoggerRequireDatabase)
        setText(lootHistoryContentFrameName, "PushDatabaseBtn", L.BtnLoggerPushDatabase)
        setText(lootHistoryContentFrameName, "SyncNowBtn", L.BtnLoggerSyncNow)
        setText(lootHistoryContentFrameName, "DataHealthTitle", L.StrConfigLootHistoryDataHealthTitle)
        setText(lootHistoryContentFrameName, "ScanHistoryTitle", L.StrConfigLootHistoryScanHistoryTitle)
        setText(lootHistoryContentFrameName, "ScanHistoryDesc", L.StrConfigLootHistoryScanHistoryDesc)
        setText(lootHistoryContentFrameName, "ScanHistoryBtn", L.BtnLoggerScanHistory)
        setText(lootHistoryContentFrameName, "MaintenanceTitle", L.StrConfigLootHistoryMaintenanceTitle)
        setText(lootHistoryContentFrameName, "PurgeHistoryTitle", L.StrConfigLootHistoryPurgeHistoryTitle)
        setText(lootHistoryContentFrameName, "PurgeHistoryDesc", L.StrConfigLootHistoryPurgeHistoryDesc)
        setText(lootHistoryContentFrameName, "PurgeHistoryBtn", L.BtnLoggerPurgeHistory)
        setText(lootHistoryContentFrameName, "RebuildSourcesTitle", L.StrConfigLootHistoryRebuildSourcesTitle)
        setText(lootHistoryContentFrameName, "RebuildSourcesDesc", L.StrConfigLootHistoryRebuildSourcesDesc)
        setText(lootHistoryContentFrameName, "RebuildSourcesBtn", L.BtnLoggerRebuildSources)
        setText(lootHistoryContentFrameName, "CleanUpTitle", L.StrConfigLootHistoryCleanUpTitle)
        setText(lootHistoryContentFrameName, "CleanUpDesc", L.StrConfigLootHistoryCleanUpDesc)
        setText(lootHistoryContentFrameName, "CleanUpBtn", L.BtnLoggerCleanUp)
        layoutLootHistoryPanel()
    end

    local function localizeCleanupPopup(preview)
        preview = preview or {}
        setText(cleanupPopupFrameName, "Title", L.StrConfigLootHistoryCleanupPopupTitle)
        setText(cleanupPopupFrameName, "Body", L.StrConfigLootHistoryCleanupPopupBody)
        setText(cleanupPopupFrameName, "EmptyRaidsLabel", formatCleanupOptionLabel(L.StrConfigLootHistoryCleanupEmptyRaids, preview.emptyRaids))
        setText(cleanupPopupFrameName, "EmptyRaidsDesc", L.StrConfigLootHistoryCleanupEmptyRaidsDesc)
        setText(cleanupPopupFrameName, "NonEpicLootLabel", formatCleanupOptionLabel(L.StrConfigLootHistoryCleanupNonEpicLoot, preview.nonEpicLoot))
        setText(cleanupPopupFrameName, "NonEpicLootDesc", L.StrConfigLootHistoryCleanupNonEpicLootDesc)
        setText(cleanupPopupFrameName, "NoBossEncounterLabel", formatCleanupOptionLabel(L.StrConfigLootHistoryCleanupNoBossEncounter, preview.raidsWithoutBosses))
        setText(cleanupPopupFrameName, "NoBossEncounterDesc", L.StrConfigLootHistoryCleanupNoBossEncounterDesc)
        setText(cleanupPopupFrameName, "DeleteBtn", L.BtnDelete)
        setText(cleanupPopupFrameName, "CancelBtn", L.BtnCancel)
        layoutCleanupPopup()
    end

    local function localizeLFMSpamPanel()
        setText(lfmSpamContentFrameName, "Title", L.StrLFMSpam)
        setText(lfmSpamContentFrameName, "MessagePreviewTitle", L.StrConfigLFMSpamPreviewTitle)
        setText(lfmSpamContentFrameName, "MessagePreviewBody", L.StrConfigLFMSpamPreviewPending)
        setText(lfmSpamContentFrameName, "SafetyTitle", L.StrConfigLFMSpamSafetyTitle)
        setText(lfmSpamContentFrameName, "SafetyBody", L.StrConfigLFMSpamSafetyBody)
        setText(lfmSpamContentFrameName, "OpenBtn", L.BtnOpen)
        setText(lfmSpamContentFrameName, "StartBtn", L.BtnStart)
        setText(lfmSpamContentFrameName, "StopBtn", L.BtnStop)
        setText(lfmSpamContentFrameName, "RefreshPreviewBtn", L.BtnRefresh)
        setText(lfmSpamContentFrameName, "ClearPreviewBtn", L.BtnClear)
        layoutLFMSpamPanel()
    end

    local function localizeRaidWarningPanel()
        setText(raidWarningContentFrameName, "Title", L.StrConfigPanelRaidWarning)
        setText(raidWarningContentFrameName, "TemplatesTitle", L.StrConfigRaidWarningTemplatesTitle)
        setText(raidWarningContentFrameName, "TemplatesBody", L.StrConfigRaidWarningTemplatesBody)
        setText(raidWarningContentFrameName, "PreviewTitle", L.StrConfigRaidWarningPreviewTitle)
        setText(raidWarningContentFrameName, "PreviewBody", L.StrConfigRaidWarningPreviewPending)
        setText(raidWarningContentFrameName, "PermissionTitle", L.StrConfigRaidWarningPermissionTitle)
        setText(raidWarningContentFrameName, "PermissionBody", L.StrConfigRaidWarningPermissionBody)
        setText(raidWarningContentFrameName, "MaintenanceTitle", L.StrConfigRaidWarningMaintenanceTitle)
        setText(raidWarningContentFrameName, "ClearSavedTitle", L.StrConfigRaidWarningClearSavedTitle)
        setText(raidWarningContentFrameName, "ClearSavedDesc", L.StrConfigRaidWarningClearSavedDesc)
        setText(raidWarningContentFrameName, "OpenBtn", L.BtnOpen)
        setText(raidWarningContentFrameName, "PreviewBtn", L.BtnPreview)
        setText(raidWarningContentFrameName, "ClearSavedBtn", L.BtnClearAll)
        layoutRaidWarningPanel()
    end

    local function refreshConfigControls(frameName)
        if not frameName then
            return
        end

        setChecked(frameName, "sortAscending", getOption("sortAscending") == true)
        setChecked(frameName, "useRaidWarning", getOption("useRaidWarning") == true)
        setChecked(frameName, "announceOnWin", getOption("announceOnWin") == true)
        setChecked(frameName, "announceOnHold", getOption("announceOnHold") == true)
        setChecked(frameName, "announceOnBank", getOption("announceOnBank") == true)
        setChecked(frameName, "announceOnDisenchant", getOption("announceOnDisenchant") == true)
        setChecked(frameName, "lootWhispers", getOption("lootWhispers") == true)
        setChecked(frameName, "softResWhisperReplies", getOption("softResWhisperReplies") == true)
        setChecked(frameName, "countdownRollsBlock", getOption("countdownRollsBlock") == true)
        setChecked(frameName, "screenReminder", getOption("screenReminder") == true)
        setChecked(frameName, "ignoreStacks", getOption("ignoreStacks") == true)
        setChecked(frameName, "showTooltips", getOption("showTooltips") == true)
        setChecked(frameName, "showLootCounterDuringMSRoll", getOption("showLootCounterDuringMSRoll") == true)
        setChecked(frameName, "minimapButton", getOption("minimapButton") == true)
        setChecked(frameName, "countdownSimpleRaidMsg", getOption("countdownSimpleRaidMsg") == true)

        setCountdownDurationDisplay(frameName, getOption("countdownDuration"))

        local useRaidWarning = getOption("useRaidWarning") == true
        local countdownSimpleRaidMsgBtn = _G[frameName .. "countdownSimpleRaidMsg"]
        local countdownSimpleRaidMsgStr = _G[frameName .. "countdownSimpleRaidMsgStr"]

        if countdownSimpleRaidMsgBtn and countdownSimpleRaidMsgStr then
            if useRaidWarning then
                countdownSimpleRaidMsgBtn:Enable()
                countdownSimpleRaidMsgStr:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
            else
                countdownSimpleRaidMsgBtn:Disable()
                countdownSimpleRaidMsgStr:SetTextColor(0.5, 0.5, 0.5)
            end
        end
        updateMasterLootPreview(frameName)
    end

    refreshInterfaceOptionsPanel = function()
        refreshConfigControls(masterLootContentFrameName)
    end

    -- Loads the default options into the settings table.
    local function loadDefaultOptions()
        if Options and Options.GetNamespaces then
            for _, ns in pairs(Options.GetNamespaces()) do
                ns:ResetDefaults()
            end
            Options.SetDebugEnabled(false)
        end
        module:RequestRefresh("defaults")
        refreshInterfaceOptionsPanel()
        addon:info(L.MsgDefaultsRestored)
    end

    local function loadConfigFrame(frame)
        UI.FrameName = Frames.BindModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                module:MarkDirty("show")
            end,
        }) or UI.FrameName
        if not UI.FrameName then
            return
        end
    end

    local function initCountdownSlider(slider)
        if not slider then
            return
        end
        local sliderName = slider:GetName()
        if not sliderName then
            return
        end
        slider:SetMinMaxValues(MIN_COUNTDOWN, MAX_COUNTDOWN)
        slider:SetValueStep(1)
        local low = _G[sliderName .. "Low"]
        if low then
            low:SetText(tostring(MIN_COUNTDOWN))
        end
        local high = _G[sliderName .. "High"]
        if high then
            high:SetText(tostring(MAX_COUNTDOWN))
        end
    end

    local function getButtonFrameName(btn, frameName)
        if frameName then
            return frameName
        end
        if btn and btn.GetParent then
            local parent = btn:GetParent()
            return parent and parent.GetName and parent:GetName() or nil
        end
        return nil
    end

    -- OnClick handler for option controls.
    local function onOptionClick(btn, frameName)
        if not btn then
            return
        end
        if btn._krtSuppressOption == true then
            return
        end
        frameName = getButtonFrameName(btn, frameName)
        if not frameName then
            return
        end

        local value
        local name = btn:GetName()
        if type(name) ~= "string" or name == "" then
            return
        end

        if name ~= frameName .. "countdownDuration" then
            value = (btn:GetChecked() == 1) or false
            if name == frameName .. "minimapButton" then
                addon.Minimap:ToggleMinimapButton()
            end
        else
            value = normalizeCountdownDuration(btn:GetValue())
            if btn.SetValue and btn:GetValue() ~= value then
                btn._krtSuppressOption = true
                btn:SetValue(value)
                btn._krtSuppressOption = nil
            end
            setText(frameName, "countdownDurationText", value)
        end

        name = strsub(name, strlen(frameName) + 1)
        setOption(name, value)
        local eventName = Events.GetConfigOptionChanged and Events.GetConfigOptionChanged(name)
        if eventName then
            Bus.TriggerEvent(eventName, value)
        end

        module:RequestRefresh("option_changed")
        refreshInterfaceOptionsPanel()
    end

    local function bindConfigHandlers(frameName, refs, includeClose)
        if not refs then
            return
        end
        if includeClose then
            Frames.SetScriptSafely(refs.closeBtn, "OnClick", function()
                module:Hide()
            end)
        end
        Frames.SetScriptSafely(refs.defaultsBtn, "OnClick", function()
            loadDefaultOptions()
        end)
        Frames.SetScriptSafely(refs.countdownDuration, "OnValueChanged", function(self)
            onOptionClick(self, frameName)
        end)
        initCountdownSlider(refs.countdownDuration)

        for i = 1, #optionSuffixes do
            local suffix = optionSuffixes[i]
            local optionBtn = refs.options[suffix]
            Frames.SetScriptSafely(optionBtn, "OnClick", function(self)
                onOptionClick(self, frameName)
            end)
        end
    end

    local function getLoggerActions()
        local logger = Services and Services.Logger or nil
        return logger and logger.Actions or nil
    end

    local function scanCleanupPreview()
        local actions = getLoggerActions()
        if actions and actions.GetRaidHistoryScan then
            return actions:GetRaidHistoryScan()
        end
        return nil
    end

    local function refreshLoggerAfterMaintenance()
        if Database and Database.RequestControllerMethod then
            Database.RequestControllerMethod("Logger", "RequestRefresh", "maintenance")
        end
    end

    local function formatLootHistoryReport(result)
        result = result or {}
        return format(
            L.StrConfigLootHistoryReportSummary,
            tonumber(result.raids) or 0,
            tonumber(result.emptyRaids) or 0,
            tonumber(result.raidsWithoutBosses) or 0,
            tonumber(result.nonEpicLoot) or 0,
            tonumber(result.missingSources) or 0,
            tonumber(result.invalidSources) or 0,
            tonumber(result.orphanLoot) or 0,
            tonumber(result.duplicateRaidCandidates) or 0
        )
    end

    local function refreshLootHistoryReport()
        local actions = getLoggerActions()
        if not (actions and actions.GetRaidHistoryScan) then
            setText(lootHistoryContentFrameName, "ReportSummary", formatLootHistoryReport(nil))
            return nil
        end
        local result = actions:GetRaidHistoryScan()
        setText(lootHistoryContentFrameName, "ReportSummary", formatLootHistoryReport(result))
        return result
    end

    local function refreshLootHistorySyncControls()
        local thresholdOverride = getOption("ignoreSelectionThreshold") == true
        setChecked(lootHistoryContentFrameName, "PersistentSyncCheck", getOption("persistentSync") == true)
        setChecked(lootHistoryContentFrameName, "IgnoreGroupLootCheck", getOption("ignoreGroupLoot") == true)
        setChecked(lootHistoryContentFrameName, "IgnoreSelectionThresholdCheck", thresholdOverride)
        setEditBoxText(lootHistoryContentFrameName, "RequireDatabaseEditBox", getOption("syncRequirePlayer") or "")
        setEditBoxText(lootHistoryContentFrameName, "PushDatabaseEditBox", getOption("syncPushPlayer") or "")
        setLoggerLootQualityDropDown(Frames.GetRef(lootHistoryContentFrameName, "LoggerLootQualityDropDown"), getOption("loggerLootQualityThreshold"), thresholdOverride)
    end

    local function refreshLootHistoryPanel()
        local result = refreshLootHistoryReport()
        refreshLootHistorySyncControls()
        return result
    end

    local function saveLootHistorySyncTargets()
        setOptions({
            syncRequirePlayer = getEditBoxText(lootHistoryContentFrameName, "RequireDatabaseEditBox"),
            syncPushPlayer = getEditBoxText(lootHistoryContentFrameName, "PushDatabaseEditBox"),
        })
    end

    local function getLoggerSyncer()
        return Database.GetSyncer and Database.GetSyncer() or nil
    end

    function module:RequestLoggerSyncPanelAction(actionName)
        saveLootHistorySyncTargets()

        local syncer = getLoggerSyncer()
        if not syncer then
            addon:warn(L.MsgLoggerMaintenanceUnavailable)
            return nil
        end

        local currentRaid = Database.GetCurrentRaid and Database.GetCurrentRaid() or nil
        if actionName == "require" and syncer.RequestLoggerReq then
            return syncer:RequestLoggerReq(currentRaid, getOption("syncRequirePlayer"))
        elseif actionName == "push" and syncer.BroadcastLoggerPush then
            return syncer:BroadcastLoggerPush(currentRaid, getOption("syncPushPlayer"))
        elseif actionName == "sync" and syncer.RequestLoggerSync then
            return syncer:RequestLoggerSync()
        end

        addon:warn(L.MsgLoggerMaintenanceUnavailable)
        return nil
    end

    function module:RequestLoggerMaintenance(actionName, options)
        local actions = getLoggerActions()
        if not actions then
            addon:warn(L.MsgLoggerMaintenanceUnavailable)
            return nil
        end

        local result
        if actionName == "scan" and actions.GetRaidHistoryScan then
            result = refreshLootHistoryReport()
            addon:info(
                L.MsgLoggerHistoryScanned:format(
                    tonumber(result and result.raids) or 0,
                    tonumber(result and result.emptyRaids) or 0,
                    tonumber(result and result.missingSources) or 0,
                    tonumber(result and result.invalidSources) or 0
                )
            )
        elseif actionName == "purge" and actions.PurgeRaidHistory then
            result = actions:PurgeRaidHistory()
            addon:info(L.MsgLoggerHistoryPurged:format(tonumber(result and result.removed) or 0))
        elseif actionName == "rebuildSources" and actions.EnsureLootSources then
            result = actions:EnsureLootSources()
            addon:info(
                L.MsgLoggerLootSourcesRebuilt:format(
                    tonumber(result and result.repaired) or 0,
                    tonumber(result and result.bossesCreated) or 0,
                    tonumber(result and result.unresolved) or 0
                )
            )
        elseif actionName == "cleanUp" and actions.RemoveRaidHistoryEntries then
            options = options or {}
            if options.emptyRaids ~= true and options.nonEpicLoot ~= true and options.noBossEncounter ~= true then
                addon:warn(L.MsgLoggerCleanupNoSelection)
                return nil
            end
            result = actions:RemoveRaidHistoryEntries(options)
            addon:info(L.MsgLoggerCleanupDone:format(tonumber(result and result.raidsRemoved) or 0, tonumber(result and result.lootRemoved) or 0))
        else
            addon:warn(L.MsgLoggerMaintenanceUnavailable)
            return nil
        end

        if actionName ~= "scan" then
            refreshLootHistoryReport()
            refreshLoggerAfterMaintenance()
        end
        return result
    end

    local function ensureLootHistoryConfirmPopups()
        if type(StaticPopupDialogs) ~= "table" or not (Frames and Frames.MakeConfirmPopup) then
            return false
        end
        if not StaticPopupDialogs["KRT_CONFIG_PURGE_LOOT_HISTORY"] then
            Frames.MakeConfirmPopup("KRT_CONFIG_PURGE_LOOT_HISTORY", L.StrConfirmPurgeLootHistory, function()
                module:RequestLoggerMaintenance("purge")
            end)
        end
        return true
    end

    local function showConfirmOrRun(popupKey, actionName)
        if ensureLootHistoryConfirmPopups() and type(StaticPopup_Show) == "function" then
            StaticPopup_Show(popupKey)
            return
        end
        module:RequestLoggerMaintenance(actionName)
    end

    local function resetCleanupPopupOptions(frame)
        if not frame then
            return
        end
        local emptyRaidsCheck = Frames.GetRef(frame, "EmptyRaidsCheck")
        local nonEpicLootCheck = Frames.GetRef(frame, "NonEpicLootCheck")
        local noBossEncounterCheck = Frames.GetRef(frame, "NoBossEncounterCheck")
        if emptyRaidsCheck and emptyRaidsCheck.SetChecked then
            emptyRaidsCheck:SetChecked(false)
        end
        if nonEpicLootCheck and nonEpicLootCheck.SetChecked then
            nonEpicLootCheck:SetChecked(false)
        end
        if noBossEncounterCheck and noBossEncounterCheck.SetChecked then
            noBossEncounterCheck:SetChecked(false)
        end
    end

    local function bindCleanupPopup()
        if cleanupPopupBound then
            return true
        end
        local frame = _G[cleanupPopupFrameName]
        if not frame then
            return false
        end

        local deleteBtn = Frames.GetRef(frame, "DeleteBtn")
        local cancelBtn = Frames.GetRef(frame, "CancelBtn")
        Frames.SetScriptSafely(deleteBtn, "OnClick", function()
            module:RequestLoggerMaintenance("cleanUp", {
                emptyRaids = getChecked(frame, "EmptyRaidsCheck"),
                nonEpicLoot = getChecked(frame, "NonEpicLootCheck"),
                noBossEncounter = getChecked(frame, "NoBossEncounterCheck"),
            })
            frame:Hide()
        end)
        Frames.SetScriptSafely(cancelBtn, "OnClick", function()
            frame:Hide()
        end)

        cleanupPopupBound = true
        return true
    end

    local function showCleanupPopup()
        local frame = _G[cleanupPopupFrameName]
        if not frame then
            addon:warn(L.MsgLoggerMaintenanceUnavailable)
            return
        end
        bindCleanupPopup()
        localizeCleanupPopup(scanCleanupPreview())
        resetCleanupPopupOptions(frame)
        frame:Show()
        if frame.Raise then
            frame:Raise()
        end
    end

    local function saveLootHistoryOption(optionKey, value)
        setOptions({
            [optionKey] = value,
        })
        refreshLootHistorySyncControls()
    end

    local function onLoggerLootQualityDropDownClick(_button, owner, value)
        local threshold = normalizeLoggerLootQualityThreshold(value)
        saveLootHistoryOption("loggerLootQualityThreshold", threshold)
        if owner then
            setLoggerLootQualityDropDown(owner, threshold, getOption("ignoreSelectionThreshold") == true)
        end
        if CloseDropDownMenus then
            CloseDropDownMenus()
        end
    end

    local function initializeLoggerLootQualityDropDown()
        for i = 1, #loggerLootQualityOptions do
            local option = loggerLootQualityOptions[i]
            local info = UIDropDownMenu_CreateInfo()
            info.hasArrow = false
            info.notCheckable = 1
            info.text = getLoggerLootQualityLabel(option.value)
            info.value = option.value
            info.func = onLoggerLootQualityDropDownClick
            info.arg1 = UIDROPDOWNMENU_OPEN_MENU
            info.arg2 = option.value
            UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
        end
    end

    local function bindLootHistorySyncEditBox(editBox, optionKey)
        if not editBox then
            return
        end
        Frames.SetScriptSafely(editBox, "OnEnterPressed", function(self)
            local value = Strings.TrimText(self:GetText() or "") or ""
            setOptions({
                [optionKey] = value,
            })
            self:ClearFocus()
        end)
        Frames.SetScriptSafely(editBox, "OnEditFocusLost", function(self)
            setOptions({
                [optionKey] = Strings.TrimText(self:GetText() or "") or "",
            })
        end)
        Frames.SetScriptSafely(editBox, "OnEscapePressed", function(self)
            self:SetText(getOption(optionKey) or "")
            self:ClearFocus()
        end)
    end

    local function bindLootHistoryPanel()
        if lootHistoryPanelBound then
            return
        end
        local content = _G[lootHistoryContentFrameName]
        if not content then
            return
        end

        local scanBtn = Frames.GetRef(content, "ScanHistoryBtn")
        local purgeBtn = Frames.GetRef(content, "PurgeHistoryBtn")
        local rebuildSourcesBtn = Frames.GetRef(content, "RebuildSourcesBtn")
        local cleanUpBtn = Frames.GetRef(content, "CleanUpBtn")
        local persistentSyncCheck = Frames.GetRef(content, "PersistentSyncCheck")
        local ignoreGroupLootCheck = Frames.GetRef(content, "IgnoreGroupLootCheck")
        local ignoreSelectionThresholdCheck = Frames.GetRef(content, "IgnoreSelectionThresholdCheck")
        local loggerLootQualityDropDown = Frames.GetRef(content, "LoggerLootQualityDropDown")
        local requireDatabaseEditBox = Frames.GetRef(content, "RequireDatabaseEditBox")
        local pushDatabaseEditBox = Frames.GetRef(content, "PushDatabaseEditBox")
        local requireDatabaseBtn = Frames.GetRef(content, "RequireDatabaseBtn")
        local pushDatabaseBtn = Frames.GetRef(content, "PushDatabaseBtn")
        local syncNowBtn = Frames.GetRef(content, "SyncNowBtn")

        Frames.SetScriptSafely(scanBtn, "OnClick", function()
            module:RequestLoggerMaintenance("scan")
        end)
        Frames.SetScriptSafely(purgeBtn, "OnClick", function()
            showConfirmOrRun("KRT_CONFIG_PURGE_LOOT_HISTORY", "purge")
        end)
        Frames.SetScriptSafely(rebuildSourcesBtn, "OnClick", function()
            module:RequestLoggerMaintenance("rebuildSources")
        end)
        Frames.SetScriptSafely(cleanUpBtn, "OnClick", function()
            showCleanupPopup()
        end)
        Frames.SetScriptSafely(persistentSyncCheck, "OnClick", function(self)
            local checked = self:GetChecked()
            saveLootHistoryOption("persistentSync", checked == true or checked == 1)
        end)
        Frames.SetScriptSafely(ignoreGroupLootCheck, "OnClick", function(self)
            local checked = self:GetChecked()
            saveLootHistoryOption("ignoreGroupLoot", checked == true or checked == 1)
        end)
        Frames.SetScriptSafely(ignoreSelectionThresholdCheck, "OnClick", function(self)
            local checked = self:GetChecked()
            saveLootHistoryOption("ignoreSelectionThreshold", checked == true or checked == 1)
        end)
        if loggerLootQualityDropDown and UIDropDownMenu_Initialize then
            UIDropDownMenu_Initialize(loggerLootQualityDropDown, initializeLoggerLootQualityDropDown)
            if UIDropDownMenu_SetWidth then
                UIDropDownMenu_SetWidth(loggerLootQualityDropDown, 72)
            end
            if UIDropDownMenu_SetButtonWidth then
                UIDropDownMenu_SetButtonWidth(loggerLootQualityDropDown, 92)
            end
            if UIDropDownMenu_JustifyText then
                UIDropDownMenu_JustifyText(loggerLootQualityDropDown, "LEFT")
            end
        end
        bindLootHistorySyncEditBox(requireDatabaseEditBox, "syncRequirePlayer")
        bindLootHistorySyncEditBox(pushDatabaseEditBox, "syncPushPlayer")
        Frames.SetScriptSafely(requireDatabaseBtn, "OnClick", function()
            module:RequestLoggerSyncPanelAction("require")
        end)
        Frames.SetScriptSafely(pushDatabaseBtn, "OnClick", function()
            module:RequestLoggerSyncPanelAction("push")
        end)
        Frames.SetScriptSafely(syncNowBtn, "OnClick", function()
            module:RequestLoggerSyncPanelAction("sync")
        end)

        ensureLootHistoryConfirmPopups()
        lootHistoryPanelBound = true
    end

    function module:RequestSpammerPanelAction(actionName)
        local result
        if actionName == "open" then
            requestController("Spammer", "Toggle")
        elseif actionName == "start" then
            requestController("Spammer", "RequestStart")
        elseif actionName == "stop" then
            requestController("Spammer", "RequestStop")
        elseif actionName == "clear" then
            result = requestController("Spammer", "RequestClear")
        else
            result = requestController("Spammer", "RequestPreview")
        end
        if result and result.output then
            local previewLength = format(L.StrConfigLFMSpamPreviewLength, tonumber(result.length) or 0)
            setText(lfmSpamContentFrameName, "MessagePreviewBody", result.output .. "\n" .. previewLength)
        end
        return result
    end

    local function bindLFMSpamPanel()
        if lfmSpamPanelBound then
            return
        end
        local content = _G[lfmSpamContentFrameName]
        if not content then
            return
        end

        Frames.SetScriptSafely(Frames.GetRef(content, "OpenBtn"), "OnClick", function()
            module:RequestSpammerPanelAction("open")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "StartBtn"), "OnClick", function()
            module:RequestSpammerPanelAction("start")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "StopBtn"), "OnClick", function()
            module:RequestSpammerPanelAction("stop")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "RefreshPreviewBtn"), "OnClick", function()
            module:RequestSpammerPanelAction("preview")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "ClearPreviewBtn"), "OnClick", function()
            module:RequestSpammerPanelAction("clear")
        end)

        lfmSpamPanelBound = true
    end

    function module:RequestRaidWarningPanelAction(actionName, includeStock)
        local result
        if actionName == "open" then
            requestController("Warnings", "Toggle")
        elseif actionName == "clearSaved" then
            result = requestController("Warnings", "RequestClearSavedWarnings", includeStock == true)
            addon:info(L.MsgRaidWarningsCleared:format(tonumber(result and result.removed) or 0))
            local preview = requestController("Warnings", "RequestTemplatePreview")
            if preview and preview.text then
                setText(raidWarningContentFrameName, "PreviewBody", preview.text)
            end
        else
            result = requestController("Warnings", "RequestTemplatePreview")
            if result and result.text then
                setText(raidWarningContentFrameName, "PreviewBody", result.text)
            end
        end
        return result
    end

    local function ensureRaidWarningConfirmPopups()
        if type(StaticPopupDialogs) ~= "table" then
            return false
        end
        if not StaticPopupDialogs["KRT_CONFIG_CLEAR_RAID_WARNINGS"] then
            StaticPopupDialogs["KRT_CONFIG_CLEAR_RAID_WARNINGS"] = {
                text = L.StrConfirmClearRaidWarnings,
                button1 = YES or "Yes",
                button2 = NO or "No",
                button3 = CANCEL or L.BtnCancel,
                OnAccept = function()
                    module:RequestRaidWarningPanelAction("clearSaved", true)
                end,
                OnCancel = function(_, _, reason)
                    if reason == "clicked" then
                        module:RequestRaidWarningPanelAction("clearSaved", false)
                    end
                end,
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                cancels = "KRT_CONFIG_CLEAR_RAID_WARNINGS",
            }
        end
        return true
    end

    local function showRaidWarningConfirmOrRun(popupKey, actionName, includeStock)
        if ensureRaidWarningConfirmPopups() and type(StaticPopup_Show) == "function" then
            StaticPopup_Show(popupKey)
            return
        end
        module:RequestRaidWarningPanelAction(actionName, includeStock)
    end

    local function bindRaidWarningPanel()
        if raidWarningPanelBound then
            return
        end
        local content = _G[raidWarningContentFrameName]
        if not content then
            return
        end

        Frames.SetScriptSafely(Frames.GetRef(content, "OpenBtn"), "OnClick", function()
            module:RequestRaidWarningPanelAction("open")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "PreviewBtn"), "OnClick", function()
            module:RequestRaidWarningPanelAction("preview")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "ClearSavedBtn"), "OnClick", function()
            showRaidWarningConfirmOrRun("KRT_CONFIG_CLEAR_RAID_WARNINGS", "clearSaved", false)
        end)

        ensureRaidWarningConfirmPopups()
        raidWarningPanelBound = true
    end

    local function BindHandlers(frameName, _, refs)
        bindConfigHandlers(frameName, refs, true)
    end

    local function bindInterfaceOptionsPanel(panel)
        if interfacePanelBound or not panel then
            return
        end

        local content = _G[masterLootContentFrameName]
        if not content then
            return
        end

        local refs = collectConfigRefs(content, false)
        bindConfigHandlers(masterLootContentFrameName, refs, false)
        Frames.SetScriptSafely(Frames.GetRef(content, "QuietPresetBtn"), "OnClick", function()
            module:ApplyMasterLootPreset("quiet")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "StandardPresetBtn"), "OnClick", function()
            module:ApplyMasterLootPreset("standard")
        end)
        Frames.SetScriptSafely(Frames.GetRef(content, "VerbosePresetBtn"), "OnClick", function()
            module:ApplyMasterLootPreset("verbose")
        end)
        localizeConfigControls(masterLootContentFrameName, L.StrConfigPanelMasterLoot, true)
        refreshConfigControls(masterLootContentFrameName)
        if panel.HookScript then
            panel:HookScript("OnShow", function()
                refreshConfigControls(masterLootContentFrameName)
            end)
        end
        interfacePanelBound = true
    end

    local function getInterfacePanelSpecs()
        return {
            {
                frameName = interfacePanelFrameName,
                title = L.StrConfigPanelTitle,
                root = true,
            },
            {
                frameName = masterLootPanelFrameName,
                title = L.StrConfigPanelMasterLoot,
                parent = L.StrConfigPanelTitle,
                controls = true,
            },
            {
                frameName = lootHistoryPanelFrameName,
                title = L.StrLootHistory,
                parent = L.StrConfigPanelTitle,
                maintenance = true,
            },
            {
                frameName = lfmSpamPanelFrameName,
                title = L.StrLFMSpam,
                parent = L.StrConfigPanelTitle,
                lfmSpam = true,
            },
            {
                frameName = raidWarningPanelFrameName,
                title = L.StrConfigPanelRaidWarning,
                parent = L.StrConfigPanelTitle,
                raidWarning = true,
            },
            {
                frameName = helpPanelFrameName,
                title = L.StrConfigPanelHelp,
                parent = L.StrConfigPanelTitle,
                help = true,
            },
        }
    end

    local function registerInterfaceOptionsPanel()
        if interfacePanelsRegistered then
            return true
        end

        local addCategory = _G.InterfaceOptions_AddCategory
        if type(addCategory) ~= "function" then
            return false
        end

        local specs = getInterfacePanelSpecs()
        for i = 1, #specs do
            local spec = specs[i]
            local panel = _G[spec.frameName]
            if not panel then
                return false
            end

            panel.name = spec.title
            panel.parent = spec.parent
            setConfigTitle(spec.frameName, spec.title, true)

            if spec.controls then
                panel.default = function()
                    loadDefaultOptions()
                end
                panel.refresh = function()
                    refreshConfigControls(masterLootContentFrameName)
                end
                panel.cancel = function()
                    refreshConfigControls(masterLootContentFrameName)
                end
                bindInterfaceOptionsPanel(panel)
            elseif spec.root then
                localizeRootPanel()
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        localizeRootPanel()
                    end)
                end
            elseif spec.maintenance then
                localizeLootHistoryPanel()
                bindLootHistoryPanel()
                refreshLootHistoryPanel()
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        localizeLootHistoryPanel()
                        bindLootHistoryPanel()
                        refreshLootHistoryPanel()
                    end)
                end
            elseif spec.lfmSpam then
                localizeLFMSpamPanel()
                bindLFMSpamPanel()
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        localizeLFMSpamPanel()
                        bindLFMSpamPanel()
                        module:RequestSpammerPanelAction("preview")
                    end)
                end
            elseif spec.raidWarning then
                localizeRaidWarningPanel()
                bindRaidWarningPanel()
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        localizeRaidWarningPanel()
                        bindRaidWarningPanel()
                        module:RequestRaidWarningPanelAction("preview")
                    end)
                end
            elseif spec.help then
                localizeHelpPanel()
                if panel.HookScript then
                    panel:HookScript("OnShow", function()
                        localizeHelpPanel()
                    end)
                end
            end

            addCategory(panel)
        end

        interfacePanelsRegistered = true
        return true
    end

    local function OnLoadFrame(frame)
        loadConfigFrame(frame)
        return UI.FrameName
    end

    UIScaffold.DefineModuleUi({
        module = module,
        getFrame = getFrame,
        acquireRefs = UI.AcquireRefs,
        bind = BindHandlers,
        localize = function()
            UI.Localize()
        end,
        onLoad = OnLoadFrame,
        refresh = function(_, _, _, dirty)
            UI.Refresh(dirty)
        end,
    })

    -- Localizes UI elements.
    function UI.Localize()
        local frameName = UI.FrameName
        if not frameName then
            return
        end

        localizeConfigControls(frameName, SETTINGS)
    end

    -- UI refresh handler for the configuration frame.
    function UI.Refresh(dirty)
        if not dirty and not UI.Dirty then
            return
        end

        local frameName = UI.FrameName
        if not frameName then
            return
        end
        refreshConfigControls(frameName)

        UI.Dirty = false
    end

    UIFacade:Register(
        "Config",
        UIScaffold.MakeStandardWidgetApi(module, {
            Default = function()
                loadDefaultOptions()
            end,
        })
    )

    if Bus and Bus.RegisterCallback and Events.Internal and Events.Internal.OptionsLoaded then
        Bus.RegisterCallback(Events.Internal.OptionsLoaded, function()
            registerInterfaceOptionsPanel()
        end)
    end
end
