-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local Options = feature.Options or addon.Options
local Frames = feature.Frames or addon.Frames
local UIScaffold = addon.UIScaffold
local Events = feature.Events or addon.Events
local Bus = feature.Bus or addon.Bus

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G

local strlen = string.len
local strsub = string.sub
local type, tostring = type, tostring

local UIFacade = addon.UI

-- =========== Configuration Frame Module  =========== --
do
    if not UIFacade:IsEnabled("Config") then
        return
    end

    addon.Widgets.Config = addon.Widgets.Config or {}
    local module = addon.Widgets.Config
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui

    local getFrame = makeModuleFrameGetter(module, "KRTConfig")
    -- ----- Internal state ----- --

    local MIN_COUNTDOWN = 5
    local MAX_COUNTDOWN = 60

    local TIEBREAKER_N_MIN = 1
    local TIEBREAKER_N_MAX = 50
    local TIEBREAKER_FRAME_HEIGHT = 560

    local tiebreakerRefs = nil
    local optionSuffixes = {
        "sortAscending",
        "useRaidWarning",
        "countdownSimpleRaidMsg",
        "announceOnWin",
        "announceOnHold",
        "announceOnBank",
        "announceOnDisenchant",
        "lootWhispers",
        "countdownRollsBlock",
        "screenReminder",
        "ignoreStacks",
        "showTooltips",
        "showLootCounterDuringMSRoll",
        "minimapButton",
    }

    -- ----- Private helpers ----- --
    function UI.AcquireRefs(frame)
        local refs = {
            closeBtn = Frames.Ref(frame, "CloseBtn"),
            defaultsBtn = Frames.Ref(frame, "DefaultsBtn"),
            countdownDuration = Frames.Ref(frame, "countdownDuration"),
            options = {},
        }
        for i = 1, #optionSuffixes do
            local suffix = optionSuffixes[i]
            refs.options[suffix] = Frames.Ref(frame, suffix)
        end
        return refs
    end

    -- ----- Public methods ----- --

    -- Loads the default options into the settings table.
    local function loadDefaultOptions()
        if Options and Options.RestoreDefaults then
            Options.RestoreDefaults()
        end
        module:RequestRefresh("defaults")
        addon:info(L.MsgDefaultsRestored)
    end

    -- Loads addon options from saved variables, filling in defaults.
    local function loadOptions()
        if Options and Options.LoadOptions then
            Options.LoadOptions()
        end
        module:RequestRefresh("options")

        if KRT_MINIMAP_GUI then
            addon.Minimap:SetPos(addon.options.minimapPos or 325)
            if addon.options.minimapButton then
                Frames.SetShown(KRT_MINIMAP_GUI, true)
            else
                Frames.SetShown(KRT_MINIMAP_GUI, false)
            end
        end
    end
    addon.LoadOptions = loadOptions

    -- Public method to reset options to default.
    function module:Default()
        return loadDefaultOptions()
    end

    local function getTiebreakerOpt()
        addon.options = addon.options or {}
        addon.options.tiebreakerMSCount = addon.options.tiebreakerMSCount or {}
        local opt = addon.options.tiebreakerMSCount
        if type(opt.enabled) ~= "boolean" then
            opt.enabled = false
        end
        if opt.scope ~= "CURRENT" and opt.scope ~= "LAST_N" and opt.scope ~= "ALL" then
            opt.scope = "CURRENT"
        end
        local n = tonumber(opt.n)
        if not n or n < TIEBREAKER_N_MIN or n > TIEBREAKER_N_MAX then
            opt.n = 5
        end
        return opt
    end

    local function scopeToText(scope)
        if scope == "LAST_N" then
            return L.CfgTiebreakerScopeLastN
        elseif scope == "ALL" then
            return L.CfgTiebreakerScopeAll
        end
        return L.CfgTiebreakerScopeCurrent
    end

    local function syncTiebreakerEnabledState()
        if not tiebreakerRefs then
            return
        end
        local on = getTiebreakerOpt().enabled == true
        local scopeDropdown = tiebreakerRefs.scopeDropdown
        local nSlider = tiebreakerRefs.nSlider
        if on then
            if _G.UIDropDownMenu_EnableDropDown then
                _G.UIDropDownMenu_EnableDropDown(scopeDropdown)
            end
            if nSlider.Enable then
                nSlider:Enable()
            end
            tiebreakerRefs.scopeLabel:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
            tiebreakerRefs.nLabel:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        else
            if _G.UIDropDownMenu_DisableDropDown then
                _G.UIDropDownMenu_DisableDropDown(scopeDropdown)
            end
            if nSlider.Disable then
                nSlider:Disable()
            end
            tiebreakerRefs.scopeLabel:SetTextColor(0.5, 0.5, 0.5)
            tiebreakerRefs.nLabel:SetTextColor(0.5, 0.5, 0.5)
        end
        local nVisible = getTiebreakerOpt().scope == "LAST_N"
        if nVisible and on then
            nSlider:Show()
            tiebreakerRefs.nLabel:Show()
        else
            nSlider:Hide()
            tiebreakerRefs.nLabel:Hide()
        end
    end

    local function setTiebreakerScope(value)
        local opt = getTiebreakerOpt()
        opt.scope = value
        if tiebreakerRefs then
            _G.UIDropDownMenu_SetSelectedValue(tiebreakerRefs.scopeDropdown, value)
            _G.UIDropDownMenu_SetText(tiebreakerRefs.scopeDropdown, scopeToText(value))
        end
        syncTiebreakerEnabledState()
    end

    local function buildTiebreakerControls(frame)
        if tiebreakerRefs or not frame then
            return
        end
        local frameName = frame:GetName()
        if not frameName then
            return
        end

        frame:SetHeight(TIEBREAKER_FRAME_HEIGHT)

        local anchorStr = _G[frameName .. "minimapButtonStr"]
        if not anchorStr then
            return
        end

        local header = frame:CreateFontString(frameName .. "TiebreakerHeader", "ARTWORK", "GameFontNormal")
        header:SetPoint("TOPLEFT", anchorStr, "BOTTOMLEFT", 0, -18)

        local enabledStr = frame:CreateFontString(frameName .. "TiebreakerEnabledStr", "ARTWORK", "KRTConfigFontStringTemplate")
        enabledStr:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)

        local enabledBtn = CreateFrame("CheckButton", frameName .. "TiebreakerEnabled", frame, "KRTConfigCheckButtonTemplate")
        enabledBtn:SetPoint("TOPRIGHT", enabledStr, "TOPLEFT", -2.5, 5)
        enabledBtn:SetScript("OnClick", function(self)
            local checked = (self:GetChecked() == 1) or false
            getTiebreakerOpt().enabled = checked
            syncTiebreakerEnabledState()
            module:RequestRefresh("tiebreaker")
        end)

        local scopeLabel = frame:CreateFontString(frameName .. "TiebreakerScopeLabel", "ARTWORK", "GameFontHighlightSmall")
        scopeLabel:SetPoint("TOPLEFT", enabledStr, "BOTTOMLEFT", 0, -18)

        local scopeDropdown = CreateFrame("Frame", frameName .. "TiebreakerScopeDropdown", frame, "UIDropDownMenuTemplate")
        scopeDropdown:SetPoint("TOPLEFT", scopeLabel, "BOTTOMLEFT", -18, -4)
        _G.UIDropDownMenu_SetWidth(scopeDropdown, 150)

        _G.UIDropDownMenu_Initialize(scopeDropdown, function()
            local scopes = { "CURRENT", "LAST_N", "ALL" }
            for i = 1, #scopes do
                local value = scopes[i]
                local info = _G.UIDropDownMenu_CreateInfo()
                info.text = scopeToText(value)
                info.value = value
                info.func = function()
                    setTiebreakerScope(value)
                    module:RequestRefresh("tiebreaker")
                end
                _G.UIDropDownMenu_AddButton(info)
            end
        end)

        local nLabel = frame:CreateFontString(frameName .. "TiebreakerNLabel", "ARTWORK", "GameFontHighlightSmall")
        nLabel:SetPoint("TOPLEFT", scopeDropdown, "BOTTOMLEFT", 18, -10)

        local nSlider = CreateFrame("Slider", frameName .. "TiebreakerNSlider", frame, "OptionsSliderTemplate")
        nSlider:SetWidth(180)
        nSlider:SetHeight(15)
        nSlider:SetPoint("TOPLEFT", nLabel, "BOTTOMLEFT", 0, -15)
        nSlider:SetMinMaxValues(TIEBREAKER_N_MIN, TIEBREAKER_N_MAX)
        nSlider:SetValueStep(1)
        local lowFs = _G[nSlider:GetName() .. "Low"]
        if lowFs then
            lowFs:SetText(tostring(TIEBREAKER_N_MIN))
        end
        local highFs = _G[nSlider:GetName() .. "High"]
        if highFs then
            highFs:SetText(tostring(TIEBREAKER_N_MAX))
        end
        nSlider:SetScript("OnValueChanged", function(self, v)
            local n = math.floor(tonumber(v) or 5)
            if n < TIEBREAKER_N_MIN then
                n = TIEBREAKER_N_MIN
            elseif n > TIEBREAKER_N_MAX then
                n = TIEBREAKER_N_MAX
            end
            getTiebreakerOpt().n = n
            local textFs = _G[self:GetName() .. "Text"]
            if textFs then
                textFs:SetText(tostring(n))
            end
        end)

        tiebreakerRefs = {
            header = header,
            enabledBtn = enabledBtn,
            enabledStr = enabledStr,
            scopeLabel = scopeLabel,
            scopeDropdown = scopeDropdown,
            nLabel = nLabel,
            nSlider = nSlider,
        }
    end

    local function localizeTiebreakerControls()
        if not tiebreakerRefs then
            return
        end
        tiebreakerRefs.header:SetText(L.CfgTiebreakerHeader)
        tiebreakerRefs.enabledStr:SetText(L.CfgTiebreakerEnabled)
        tiebreakerRefs.scopeLabel:SetText(L.CfgTiebreakerScopeLabel)
        tiebreakerRefs.nLabel:SetText(L.CfgTiebreakerNLabel)
        local opt = getTiebreakerOpt()
        _G.UIDropDownMenu_SetText(tiebreakerRefs.scopeDropdown, scopeToText(opt.scope))
    end

    local function refreshTiebreakerControls()
        if not tiebreakerRefs then
            return
        end
        local opt = getTiebreakerOpt()
        tiebreakerRefs.enabledBtn:SetChecked(opt.enabled == true)
        _G.UIDropDownMenu_SetSelectedValue(tiebreakerRefs.scopeDropdown, opt.scope)
        _G.UIDropDownMenu_SetText(tiebreakerRefs.scopeDropdown, scopeToText(opt.scope))
        tiebreakerRefs.nSlider:SetValue(tonumber(opt.n) or 5)
        local textFs = _G[tiebreakerRefs.nSlider:GetName() .. "Text"]
        if textFs then
            textFs:SetText(tostring(tonumber(opt.n) or 5))
        end
        syncTiebreakerEnabledState()
    end

    -- OnLoad handler for the configuration frame.
    function module:OnLoad(frame)
        UI.FrameName = Frames.InitModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                module:MarkDirty("show")
            end,
        }) or UI.FrameName
        if not UI.FrameName then
            return
        end
        buildTiebreakerControls(frame)
    end

    function module:InitCountdownSlider(slider)
        if not slider then
            return
        end
        local sliderName = slider:GetName()
        if not sliderName then
            return
        end
        local low = _G[sliderName .. "Low"]
        if low then
            low:SetText(tostring(MIN_COUNTDOWN))
        end
        local high = _G[sliderName .. "High"]
        if high then
            high:SetText(tostring(MAX_COUNTDOWN))
        end
    end

    local function BindHandlers(_, _, refs)
        Frames.SafeSetScript(refs.closeBtn, "OnClick", function()
            module:Hide()
        end)
        Frames.SafeSetScript(refs.defaultsBtn, "OnClick", function()
            loadDefaultOptions()
        end)
        Frames.SafeSetScript(refs.countdownDuration, "OnValueChanged", function(self)
            module:OnClick(self)
        end)
        module:InitCountdownSlider(refs.countdownDuration)

        for i = 1, #optionSuffixes do
            local suffix = optionSuffixes[i]
            local optionBtn = refs.options[suffix]
            Frames.SafeSetScript(optionBtn, "OnClick", function(self, button)
                module:OnClick(self, button)
            end)
        end
    end

    local function OnLoadFrame(frame)
        module:OnLoad(frame)
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
    })

    -- OnClick handler for option controls.
    function module:OnClick(btn)
        if not btn then
            return
        end
        local frameName = UI.FrameName
        if not frameName and btn.GetParent then
            local parent = btn:GetParent()
            frameName = parent and parent.GetName and parent:GetName() or nil
            UI.FrameName = frameName or UI.FrameName
        end
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
            value = btn:GetValue()
            _G[frameName .. "countdownDurationText"]:SetText(value)
        end

        name = strsub(name, strlen(frameName) + 1)
        if Options and Options.SetOption then
            Options.SetOption(name, value)
        end
        local eventName = Events.ConfigOptionChanged and Events.ConfigOptionChanged(name)
        if eventName then
            Bus.TriggerEvent(eventName, value)
        end

        module:RequestRefresh("option_changed")
    end

    -- Localizes UI elements.
    function UI.Localize()
        local frameName = UI.FrameName
        if not frameName then
            return
        end

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

        Frames.SetFrameTitle(frameName, SETTINGS)
        _G[frameName .. "AboutStr"]:SetText(L.StrConfigAbout)
        _G[frameName .. "DefaultsBtn"]:SetText(L.BtnDefaults)
        _G[frameName .. "CloseBtn"]:SetText(L.BtnClose)

        localizeTiebreakerControls()
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
                    countdownSimpleRaidMsgStr:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                else
                    countdownSimpleRaidMsgBtn:Disable()
                    countdownSimpleRaidMsgStr:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end

        refreshTiebreakerControls()

        UI.Dirty = false
    end

    function module:RefreshUI(_, _, _, dirty)
        UI.Refresh(dirty)
    end

    function module:Refresh()
        return self:RefreshUI(nil, nil, nil, true)
    end

    if UIFacade and UIFacade.Register then
        UIFacade:Register(
            "Config",
            UIScaffold.MakeStandardWidgetApi(module, {
                Default = function()
                    module:Default()
                end,
            })
        )
    end
end
