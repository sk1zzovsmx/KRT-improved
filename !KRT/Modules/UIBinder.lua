-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local _G = _G
local tostring, type, pairs, next = tostring, type, pairs, next
local gmatch = string.gmatch
local strmatch = string.match
local strgsub = string.gsub
local strsub = string.sub

addon.UIBinder = addon.UIBinder or {}
local UIBinder = addon.UIBinder

local widgetFrameExact = {
    ["KRTMasterConfigBtn"] = "Config",
}

local widgetFramePrefixes = {
    { "KRTConfig", "Config" },
    { "KRTLootCounter", "LootCounter" },
    { "KRTReserve", "Reserves" },
    { "KRTImport", "Reserves" },
}

local function getFrameWidgetId(frameName)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end

    local exact = widgetFrameExact[frameName]
    if exact then
        return exact
    end

    for i = 1, #widgetFramePrefixes do
        local prefix = widgetFramePrefixes[i][1]
        if strsub(frameName, 1, #prefix) == prefix then
            return widgetFramePrefixes[i][2]
        end
    end

    return nil
end

local function shouldBindFrame(frameName)
    local widgetId = getFrameWidgetId(frameName)
    if not widgetId then
        return true
    end

    local ui = addon.UI
    if type(ui) ~= "table" then
        return false
    end

    if type(ui.IsEnabled) == "function" and not ui:IsEnabled(widgetId) then
        return false
    end

    if type(ui.IsRegistered) == "function" then
        return ui:IsRegistered(widgetId)
    end

    local registry = ui._registry
    return type(registry) == "table" and type(registry[widgetId]) == "table"
end

local frameBindings = {
    ["KRT_MINIMAP_GUI"] = {
        OnLoad = [[
KRT.Minimap:OnLoad(self)
]],
    },
    ["KRTChanges"] = {
        OnLoad = [[
KRT.Changes:OnLoad(self)
]],
    },
    ["KRTChangesAddBtn"] = {
        OnClick = [[
KRT.Changes:Add(self, button)
]],
    },
    ["KRTChangesAnnounceBtn"] = {
        OnClick = [[
KRT.Changes:Announce()
]],
    },
    ["KRTChangesClearBtn"] = {
        OnClick = [[
KRT.Changes:Clear()
]],
    },
    ["KRTChangesDemandBtn"] = {
        OnClick = [[
KRT.Changes:Demand()
]],
    },
    ["KRTChangesEditBtn"] = {
        OnClick = [[
KRT.Changes:Edit(self, button)
]],
    },
    ["KRTChangesName"] = {
        OnTabPressed = [[
_G[self:GetParent():GetName().."Spec"]:SetFocus()
]],
    },
    ["KRTChangesSpec"] = {
        OnTabPressed = [[
_G[self:GetParent():GetName().."Name"]:SetFocus()
]],
    },
    ["KRTConfig"] = {
        OnLoad = [[
KRT.Config:OnLoad(self)
]],
    },
    ["KRTConfigCloseBtn"] = {
        OnClick = [[
self:GetParent():Hide()
]],
    },
    ["KRTConfigcountdownDuration"] = {
        OnLoad = [[
KRT.Config:InitCountdownSlider(self)
]],
        OnValueChanged = [[
KRT.Config:OnClick(self)
]],
    },
    ["KRTConfigcountdownSimpleRaidMsg"] = {
        OnClick = [[
KRT.Config:OnClick(self, button)
]],
    },
    ["KRTConfiguseRaidWarning"] = {
        OnClick = [[
KRT.Config:OnClick(self, button)
]],
    },
    ["KRTImportCancelButton"] = {
        OnClick = [[
KRT.ReservesUI.Import:Hide()
]],
    },
    ["KRTImportConfirmButton"] = {
        OnClick = [[
KRT.ReservesUI.Import:ImportFromEditBox()
]],
    },
    ["KRTImportEditBox"] = {
        OnEscapePressed = [[
self:ClearFocus()
]],
    },
    ["KRTImportWindow"] = {
        OnLoad = [[
KRT.ReservesUI.Import:OnLoad(self)
]],
    },
    ["KRTImportWindowModeSlider"] = {
        OnLoad = [[
KRT.ReservesUI.Import:OnModeSliderLoad(self)
]],
        OnValueChanged = [[
KRT.ReservesUI.Import:OnModeSliderChanged(self, value)
]],
    },
    ["KRTLogger"] = {
        OnLoad = [[
KRT.Logger:OnLoad(self)
]],
    },
    ["KRTLoggerBossAttendees"] = {
        OnLoad = [[
KRT.Logger.BossAttendees:OnLoad(self)
]],
    },
    ["KRTLoggerBossAttendeesAddBtn"] = {
        OnClick = [[
KRT.Logger.BossAttendees:Add(self, button)
]],
    },
    ["KRTLoggerBossAttendeesHeaderName"] = {
        OnClick = [[
KRT.Logger.BossAttendees:Sort("name")
]],
    },
    ["KRTLoggerBossAttendeesRemoveBtn"] = {
        OnClick = [[
KRT.Logger.BossAttendees:Delete(self, button)
]],
    },
    ["KRTLoggerBossBox"] = {
        OnDragStart = [[
self:GetParent():StartMoving()
]],
        OnDragStop = [[
self:GetParent():StopMovingOrSizing()
]],
        OnLoad = [[
KRT.Logger.BossBox:OnLoad(self)
]],
    },
    ["KRTLoggerBossBoxCancelBtn"] = {
        OnClick = [[
self:GetParent():Hide()
]],
    },
    ["KRTLoggerBossBoxDifficulty"] = {
        OnEnterPressed = [[
KRT.Logger.BossBox:Save()
]],
    },
    ["KRTLoggerBossBoxName"] = {
        OnEnterPressed = [[
KRT.Logger.BossBox:Save()
]],
    },
    ["KRTLoggerBossBoxSaveBtn"] = {
        OnClick = [[
KRT.Logger.BossBox:Save()
]],
    },
    ["KRTLoggerBossBoxTime"] = {
        OnEnterPressed = [[
KRT.Logger.BossBox:Save()
]],
    },
    ["KRTLoggerBosses"] = {
        OnLoad = [[
KRT.Logger.Boss:OnLoad(self)
]],
    },
    ["KRTLoggerBossesAddBtn"] = {
        OnClick = [[
KRT.Logger.Boss:Add(self, button)
]],
    },
    ["KRTLoggerBossesDeleteBtn"] = {
        OnClick = [[
KRT.Logger.Boss:Delete(self, button)
]],
    },
    ["KRTLoggerBossesEditBtn"] = {
        OnClick = [[
KRT.Logger.Boss:Edit(self, button)
]],
    },
    ["KRTLoggerBossesHeaderMode"] = {
        OnClick = [[
KRT.Logger.Boss:Sort("mode")
]],
    },
    ["KRTLoggerBossesHeaderName"] = {
        OnClick = [[
KRT.Logger.Boss:Sort("name")
]],
    },
    ["KRTLoggerBossesHeaderNum"] = {
        OnClick = [[
KRT.Logger.Boss:Sort("id")
]],
    },
    ["KRTLoggerBossesHeaderTime"] = {
        OnClick = [[
KRT.Logger.Boss:Sort("time")
]],
    },
    ["KRTLoggerLoot"] = {
        OnLoad = [[
KRT.Logger.Loot:OnLoad(self)
]],
    },
    ["KRTLoggerLootDeleteBtn"] = {
        OnClick = [[
KRT.Logger.Loot:Delete(self, button)
]],
    },
    ["KRTLoggerLootHeaderItem"] = {
        OnClick = [[
KRT.Logger.Loot:Sort("id")
]],
    },
    ["KRTLoggerLootHeaderRoll"] = {
        OnClick = [[
KRT.Logger.Loot:Sort("roll")
]],
    },
    ["KRTLoggerLootHeaderSource"] = {
        OnClick = [[
KRT.Logger.Loot:Sort("source")
]],
    },
    ["KRTLoggerLootHeaderTime"] = {
        OnClick = [[
KRT.Logger.Loot:Sort("time")
]],
    },
    ["KRTLoggerLootHeaderType"] = {
        OnClick = [[
KRT.Logger.Loot:Sort("type")
]],
    },
    ["KRTLoggerLootHeaderWinner"] = {
        OnClick = [[
KRT.Logger.Loot:Sort("winner")
]],
    },
    ["KRTLoggerPlayerBox"] = {
        OnDragStart = [[
self:GetParent():StartMoving()
]],
        OnDragStop = [[
self:GetParent():StopMovingOrSizing()
]],
        OnLoad = [[
KRT.Logger.AttendeesBox:OnLoad(self)
]],
    },
    ["KRTLoggerPlayerBoxAddBtn"] = {
        OnClick = [[
KRT.Logger.AttendeesBox:Save()
]],
    },
    ["KRTLoggerPlayerBoxCancelBtn"] = {
        OnClick = [[
self:GetParent():Hide()
]],
    },
    ["KRTLoggerRaidAttendees"] = {
        OnLoad = [[
KRT.Logger.RaidAttendees:OnLoad(self)
]],
    },
    ["KRTLoggerRaidAttendeesAddBtn"] = {
        OnClick = [[
KRT.Logger.RaidAttendees:Add(self, button)
]],
    },
    ["KRTLoggerRaidAttendeesDeleteBtn"] = {
        OnClick = [[
KRT.Logger.RaidAttendees:Delete(self, button)
]],
    },
    ["KRTLoggerRaidAttendeesHeaderJoin"] = {
        OnClick = [[
KRT.Logger.RaidAttendees:Sort("join")
]],
    },
    ["KRTLoggerRaidAttendeesHeaderLeave"] = {
        OnClick = [[
KRT.Logger.RaidAttendees:Sort("leave")
]],
    },
    ["KRTLoggerRaidAttendeesHeaderName"] = {
        OnClick = [[
KRT.Logger.RaidAttendees:Sort("name")
]],
    },
    ["KRTLoggerRaids"] = {
        OnLoad = [[
KRT.Logger.Raids:OnLoad(self)
]],
    },
    ["KRTLoggerRaidsCurrentBtn"] = {
        OnClick = [[
KRT.Logger.Raids:SetCurrent(self, button)
]],
    },
    ["KRTLoggerRaidsDeleteBtn"] = {
        OnClick = [[
KRT.Logger.Raids:Delete(self, button)
]],
    },
    ["KRTLoggerRaidsHeaderDate"] = {
        OnClick = [[
KRT.Logger.Raids:Sort("date")
]],
    },
    ["KRTLoggerRaidsHeaderNum"] = {
        OnClick = [[
KRT.Logger.Raids:Sort("id")
]],
    },
    ["KRTLoggerRaidsHeaderSize"] = {
        OnClick = [[
KRT.Logger.Raids:Sort("size")
]],
    },
    ["KRTLoggerRaidsHeaderZone"] = {
        OnClick = [[
KRT.Logger.Raids:Sort("zone")
]],
    },
    ["KRTLootCounterFrame"] = {
        OnLoad = [[
KRT.LootCounter:OnLoad(self)
]],
    },
    ["KRTMaster"] = {
        OnLoad = [[
KRT.Master:OnLoad(self)
]],
    },
    ["KRTMasterAwardBtn"] = {
        OnClick = [[
KRT.Master:BtnAward(self, button)
]],
    },
    ["KRTMasterBankBtn"] = {
        OnClick = [[
KRT.Master:BtnBank(self, button)
]],
    },
    ["KRTMasterClearBtn"] = {
        OnClick = [[
KRT.Master:BtnClear(self, button)
]],
    },
    ["KRTMasterConfigBtn"] = {
        OnClick = [[
KRT.UI:Call("Config", "Toggle")
]],
    },
    ["KRTMasterCountdownBtn"] = {
        OnClick = [[
KRT.Master:BtnCountdown(self, button)
]],
    },
    ["KRTMasterDisenchantBtn"] = {
        OnClick = [[
KRT.Master:BtnDisenchant(self, button)
]],
    },
    ["KRTMasterFreeBtn"] = {
        OnClick = [[
KRT.Master:BtnFree(self, button)
]],
    },
    ["KRTMasterHoldBtn"] = {
        OnClick = [[
KRT.Master:BtnHold(self, button)
]],
    },
    ["KRTMasterItemCount"] = {
        OnEnterPressed = [[
self:ClearFocus()
]],
    },
    ["KRTMasterLootCounterBtn"] = {
        OnClick = [[
KRT.Master:BtnLootCounter(self, button)
]],
    },
    ["KRTMasterMSBtn"] = {
        OnClick = [[
KRT.Master:BtnMS(self, button)
]],
    },
    ["KRTMasterOSBtn"] = {
        OnClick = [[
KRT.Master:BtnOS(self, button)
]],
    },
    ["KRTMasterReserveListBtn"] = {
        OnClick = [[
KRT.Master:BtnReserveList(self, button)
]],
    },
    ["KRTMasterRollBtn"] = {
        OnClick = [[
KRT.Rolls:Roll(self, button)
]],
    },
    ["KRTMasterSelectItemBtn"] = {
        OnClick = [[
KRT.Master:BtnSelectItem(self, button)
]],
    },
    ["KRTMasterSpamLootBtn"] = {
        OnClick = [[
KRT.Master:BtnSpamLoot(self, button)
]],
    },
    ["KRTMasterSRBtn"] = {
        OnClick = [[
KRT.Master:BtnSR(self, button)
]],
    },
    ["KRTReserveListFrame"] = {
        OnLoad = [[
KRT.ReservesUI:OnLoad(self)
]],
    },
    ["KRTSpammer"] = {
        OnLoad = [[
KRT.Spammer:OnLoad(self)
]],
    },
    ["KRTSpammerClearBtn"] = {
        OnClick = [[
KRT.Spammer:Clear()
]],
    },
    ["KRTSpammerDuration"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Tank", "Name")
]],
    },
    ["KRTSpammerHealer"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("HealerClass", "TankClass")
]],
    },
    ["KRTSpammerHealerClass"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Melee", "Healer")
]],
    },
    ["KRTSpammerMelee"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("MeleeClass", "HealerClass")
]],
    },
    ["KRTSpammerMeleeClass"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Ranged", "Melee")
]],
    },
    ["KRTSpammerMessage"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Name", "RangedClass")
]],
    },
    ["KRTSpammerName"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Duration", "Message")
]],
    },
    ["KRTSpammerRanged"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("RangedClass", "MeleeClass")
]],
    },
    ["KRTSpammerRangedClass"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Message", "Ranged")
]],
    },
    ["KRTSpammerTank"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("TankClass", "Duration")
]],
    },
    ["KRTSpammerTankClass"] = {
        OnTabPressed = [[
KRT.Spammer:Tab("Healer", "Tank")
]],
    },
    ["KRTWarnings"] = {
        OnHide = [[
KRT.Warnings:Cancel()
]],
        OnLoad = [[
KRT.Warnings:OnLoad(self)
]],
        OnShow = [[
KRT.Warnings:Cancel()
]],
    },
    ["KRTWarningsAnnounceBtn"] = {
        OnClick = [[
KRT.Warnings:Announce()
]],
    },
    ["KRTWarningsContent"] = {
        OnTabPressed = [[
_G[self:GetParent():GetName().."Name"]:SetFocus()
]],
    },
    ["KRTWarningsDeleteBtn"] = {
        OnClick = [[
KRT.Warnings:Delete(self, button)
]],
    },
    ["KRTWarningsEditBtn"] = {
        OnClick = [[
KRT.Warnings:Edit(self, button)
]],
    },
    ["KRTWarningsName"] = {
        OnTabPressed = [[
_G[self:GetParent():GetName().."Content"]:SetFocus()
]],
    },
}

local frameTemplateMap = {
    ["KRTButtonTemplate"] = "UIPanelButtonDisabledTexture",
    ["KRTChanges"] = "KRTFrameTemplate",
    ["KRTChangesAddBtn"] = "KRTButtonTemplate",
    ["KRTChangesAnnounceBtn"] = "KRTButtonTemplate",
    ["KRTChangesButtonTemplateName"] = "GameFontHighlightSmall",
    ["KRTChangesButtonTemplateSpec"] = "GameFontHighlightSmall",
    ["KRTChangesClearBtn"] = "KRTButtonTemplate",
    ["KRTChangesDemandBtn"] = "KRTButtonTemplate",
    ["KRTChangesEditBtn"] = "KRTButtonTemplate",
    ["KRTChangesName"] = "GameFontHighlightSmall",
    ["KRTChangesScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTChangesSpec"] = "GameFontHighlightSmall",
    ["KRTConfig"] = "KRTFrameTemplate",
    ["KRTConfigAboutStr"] = "GameFontNormalSmall",
    ["KRTConfigannounceOnBank"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigannounceOnBankStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigannounceOnDisenchant"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigannounceOnDisenchantStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigannounceOnHold"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigannounceOnHoldStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigannounceOnWin"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigannounceOnWinStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigCloseBtn"] = "KRTButtonTemplate",
    ["KRTConfigcountdownDuration"] = "OptionsSliderTemplate",
    ["KRTConfigcountdownDurationStr"] = "GameFontNormalSmall",
    ["KRTConfigcountdownRollsBlock"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigcountdownRollsBlockStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigcountdownSimpleRaidMsg"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigcountdownSimpleRaidMsgStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigDefaultsBtn"] = "KRTButtonTemplate",
    ["KRTConfigignoreStacks"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigignoreStacksStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfiglootWhispers"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfiglootWhispersStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigminimapButton"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigminimapButtonStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigscreenReminder"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigscreenReminderStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigshowLootCounterDuringMSRoll"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigshowLootCounterDuringMSRollStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigshowTooltips"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigshowTooltipsStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfigsortAscending"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfigsortAscendingStr"] = "KRTConfigFontStringTemplate",
    ["KRTConfiguseRaidWarning"] = "KRTConfigCheckButtonTemplate",
    ["KRTConfiguseRaidWarningStr"] = "KRTConfigFontStringTemplate",
    ["KRTEditBoxTemplate"] = "GameFontHighlight",
    ["KRTFrameTemplateTitle"] = "GameFontNormalSmall",
    ["KRTImportCancelButton"] = "KRTButtonTemplate",
    ["KRTImportConfirmButton"] = "KRTButtonTemplate",
    ["KRTImportEditBox"] = "InputBoxTemplate",
    ["KRTImportScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTImportWindow"] = "KRTFrameTemplate",
    ["KRTImportWindowHint"] = "GameFontNormalSmall",
    ["KRTImportWindowModeSlider"] = "OptionsSliderTemplate",
    ["KRTImportWindowStatus"] = "GameFontHighlightSmall",
    ["KRTItemSelectionButtonName"] = "GameFontNormalSmall",
    ["KRTLogger"] = "KRTFrameTemplate",
    ["KRTLoggerBossAttendees"] = "KRTLoggerFrameTemplate",
    ["KRTLoggerBossAttendeesAddBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossAttendeesHeaderName"] = "KRTLoggerTableHeader",
    ["KRTLoggerBossAttendeesRemoveBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossAttendeesScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTLoggerBossBox"] = "KRTSimpleFrameTemplate",
    ["KRTLoggerBossBoxCancelBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossBoxDifficulty"] = "KRTEditBoxTemplate",
    ["KRTLoggerBossBoxDifficultyStr"] = "KRTFontString",
    ["KRTLoggerBossBoxName"] = "KRTEditBoxTemplate",
    ["KRTLoggerBossBoxNameStr"] = "KRTFontString",
    ["KRTLoggerBossBoxSaveBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossBoxTime"] = "KRTEditBoxTemplate",
    ["KRTLoggerBossBoxTimeStr"] = "KRTFontString",
    ["KRTLoggerBossButtonMode"] = "GameFontHighlightSmall",
    ["KRTLoggerBossButtonName"] = "GameFontHighlightSmall",
    ["KRTLoggerBossButtonTime"] = "GameFontHighlightSmall",
    ["KRTLoggerBosses"] = "KRTLoggerFrameTemplate",
    ["KRTLoggerBossesAddBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossesDeleteBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossesEditBtn"] = "KRTButtonTemplate",
    ["KRTLoggerBossesHeaderMode"] = "KRTLoggerTableHeader",
    ["KRTLoggerBossesHeaderName"] = "KRTLoggerTableHeader",
    ["KRTLoggerBossesHeaderNum"] = "KRTLoggerTableHeader",
    ["KRTLoggerBossesHeaderTime"] = "KRTLoggerTableHeader",
    ["KRTLoggerBossesScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTLoggerLoot"] = "KRTLoggerFrameTemplate",
    ["KRTLoggerLootAddBtn"] = "KRTButtonTemplate",
    ["KRTLoggerLootButtonRoll"] = "GameFontHighlightSmall",
    ["KRTLoggerLootButtonSource"] = "GameFontHighlightSmall",
    ["KRTLoggerLootButtonTime"] = "GameFontHighlightSmall",
    ["KRTLoggerLootButtonType"] = "GameFontHighlightSmall",
    ["KRTLoggerLootButtonWinner"] = "GameFontHighlightSmall",
    ["KRTLoggerLootClearBtn"] = "KRTButtonTemplate",
    ["KRTLoggerLootDeleteBtn"] = "KRTButtonTemplate",
    ["KRTLoggerLootEditBtn"] = "KRTButtonTemplate",
    ["KRTLoggerLootExportBtn"] = "KRTButtonTemplate",
    ["KRTLoggerLootHeaderItem"] = "KRTLoggerTableHeader",
    ["KRTLoggerLootHeaderRoll"] = "KRTLoggerTableHeader",
    ["KRTLoggerLootHeaderSource"] = "KRTLoggerTableHeader",
    ["KRTLoggerLootHeaderTime"] = "KRTLoggerTableHeader",
    ["KRTLoggerLootHeaderType"] = "KRTLoggerTableHeader",
    ["KRTLoggerLootHeaderWinner"] = "KRTLoggerTableHeader",
    ["KRTLoggerLootScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTLoggerPlayerBox"] = "KRTSimpleFrameTemplate",
    ["KRTLoggerPlayerBoxAddBtn"] = "KRTButtonTemplate",
    ["KRTLoggerPlayerBoxCancelBtn"] = "KRTButtonTemplate",
    ["KRTLoggerPlayerBoxName"] = "KRTEditBoxTemplate",
    ["KRTLoggerPlayerBoxNameStr"] = "KRTFontString",
    ["KRTLoggerRaidAttendeeButtonJoin"] = "GameFontHighlightSmall",
    ["KRTLoggerRaidAttendeeButtonLeave"] = "GameFontHighlightSmall",
    ["KRTLoggerRaidAttendees"] = "KRTLoggerFrameTemplate",
    ["KRTLoggerRaidAttendeesAddBtn"] = "KRTButtonTemplate",
    ["KRTLoggerRaidAttendeesDeleteBtn"] = "KRTButtonTemplate",
    ["KRTLoggerRaidAttendeesHeaderJoin"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidAttendeesHeaderLeave"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidAttendeesHeaderName"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidAttendeesScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTLoggerRaidButtonDate"] = "GameFontHighlightSmall",
    ["KRTLoggerRaidButtonSize"] = "GameFontHighlightSmall",
    ["KRTLoggerRaidButtonZone"] = "GameFontHighlightSmall",
    ["KRTLoggerRaids"] = "KRTLoggerFrameTemplate",
    ["KRTLoggerRaidsCurrentBtn"] = "KRTButtonTemplate",
    ["KRTLoggerRaidsDeleteBtn"] = "KRTButtonTemplate",
    ["KRTLoggerRaidsExportBtn"] = "KRTButtonTemplate",
    ["KRTLoggerRaidsHeaderDate"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidsHeaderNum"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidsHeaderSize"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidsHeaderZone"] = "KRTLoggerTableHeader",
    ["KRTLoggerRaidsScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTLoggerRollTypePickerFrameBank"] = "UIPanelButtonTemplate",
    ["KRTLoggerRollTypePickerFrameDE"] = "UIPanelButtonTemplate",
    ["KRTLoggerRollTypePickerFrameFree"] = "UIPanelButtonTemplate",
    ["KRTLoggerRollTypePickerFrameHold"] = "UIPanelButtonTemplate",
    ["KRTLoggerRollTypePickerFrameMS"] = "UIPanelButtonTemplate",
    ["KRTLoggerRollTypePickerFrameOS"] = "UIPanelButtonTemplate",
    ["KRTLoggerRollTypePickerFrameSR"] = "UIPanelButtonTemplate",
    ["KRTLootCounterFrame"] = "KRTFrameTemplate",
    ["KRTLootCounterFrameScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTMaster"] = "KRTFrameTemplate",
    ["KRTMasterAwardBtn"] = "KRTButtonTemplate",
    ["KRTMasterBankBtn"] = "KRTButtonTemplate",
    ["KRTMasterBankDropDown"] = "UIDropDownMenuTemplate",
    ["KRTMasterClearBtn"] = "KRTButtonTemplate",
    ["KRTMasterConfigBtn"] = "KRTButtonTemplate",
    ["KRTMasterCountdownBtn"] = "KRTButtonTemplate",
    ["KRTMasterDisenchantBtn"] = "KRTButtonTemplate",
    ["KRTMasterDisenchantDropDown"] = "UIDropDownMenuTemplate",
    ["KRTMasterFreeBtn"] = "KRTButtonTemplate",
    ["KRTMasterHoldBtn"] = "KRTButtonTemplate",
    ["KRTMasterHoldDropDown"] = "UIDropDownMenuTemplate",
    ["KRTMasterItemBtn"] = "KRTItemButtonTemplate",
    ["KRTMasterItemCount"] = "GameFontHighlightSmall",
    ["KRTMasterLootCounterBtn"] = "KRTButtonTemplate",
    ["KRTMasterMSBtn"] = "KRTButtonTemplate",
    ["KRTMasterName"] = "KRTFontStringGray",
    ["KRTMasterOSBtn"] = "KRTButtonTemplate",
    ["KRTMasterReserveListBtn"] = "KRTButtonTemplate",
    ["KRTMasterRollBtn"] = "KRTButtonTemplate",
    ["KRTMasterRollsHeaderPlayer"] = "KRTFontStringGray",
    ["KRTMasterRollsHeaderRoll"] = "KRTFontStringGray",
    ["KRTMasterScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTMasterSelectItemBtn"] = "KRTButtonTemplate",
    ["KRTMasterSpamLootBtn"] = "KRTButtonTemplate",
    ["KRTMasterSRBtn"] = "KRTButtonTemplate",
    ["KRTReserveHeaderTemplateLabel"] = "GameFontNormal",
    ["KRTReserveListFrame"] = "KRTFrameTemplate",
    ["KRTReserveListFrameClearButton"] = "KRTButtonTemplate",
    ["KRTReserveListFrameCloseButton"] = "KRTButtonTemplate",
    ["KRTReserveListFrameQueryButton"] = "KRTButtonTemplate",
    ["KRTReserveListFrameScrollFrame"] = "KRTScrollFrameTemplate",
    ["KRTReserveRowTemplateIconBtn"] = "KRTItemButtonTemplate",
    ["KRTReserveRowTemplateQuantity"] = "GameFontNormalSmall",
    ["KRTReserveRowTemplateTextBlockName"] = "KRTFontString",
    ["KRTReserveRowTemplateTextBlockPlayers"] = "GameFontHighlightSmall",
    ["KRTReserveRowTemplateTextBlockSource"] = "GameFontHighlightSmall",
    ["KRTSelectPlayerTemplateCounter"] = "GameFontNormalSmall",
    ["KRTSelectPlayerTemplateName"] = "GameFontNormal",
    ["KRTSelectPlayerTemplateRoll"] = "GameFontNormalSmall",
    ["KRTSpammer"] = "KRTFrameTemplate",
    ["KRTSpammerChannel1Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel2Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel3Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel4Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel5Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel6Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel7Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannel8Str"] = "GameFontHighlightSmall",
    ["KRTSpammerChannelGuildStr"] = "GameFontHighlightSmall",
    ["KRTSpammerChannelsStr"] = "GameFontNormalSmall",
    ["KRTSpammerChannelYellStr"] = "GameFontHighlightSmall",
    ["KRTSpammerChat1"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat2"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat3"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat4"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat5"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat6"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat7"] = "KRTSpammerCheckButton",
    ["KRTSpammerChat8"] = "KRTSpammerCheckButton",
    ["KRTSpammerChatGuild"] = "KRTSpammerCheckButton",
    ["KRTSpammerChatYell"] = "KRTSpammerCheckButton",
    ["KRTSpammerClassStr"] = "KRTFontStringGray",
    ["KRTSpammerClearBtn"] = "KRTButtonTemplate",
    ["KRTSpammerCompStr"] = "GameFontNormalSmall",
    ["KRTSpammerDuration"] = "GameFontHighlightSmall",
    ["KRTSpammerDurationStr"] = "GameFontNormalSmall",
    ["KRTSpammerEditBox"] = "GameFontHighlightSmall",
    ["KRTSpammerHealer"] = "KRTSpammerEditBox",
    ["KRTSpammerHealerClass"] = "KRTSpammerEditBox",
    ["KRTSpammerHealersStr"] = "GameFontNormalSmall",
    ["KRTSpammerLength"] = "KRTFontStringGray",
    ["KRTSpammerMelee"] = "KRTSpammerEditBox",
    ["KRTSpammerMeleeClass"] = "KRTSpammerEditBox",
    ["KRTSpammerMeleesStr"] = "GameFontNormalSmall",
    ["KRTSpammerMessage"] = "KRTSpammerEditBox",
    ["KRTSpammerMessageStr"] = "GameFontNormalSmall",
    ["KRTSpammerName"] = "KRTSpammerEditBox",
    ["KRTSpammerNameStr"] = "GameFontNormalSmall",
    ["KRTSpammerNeedStr"] = "KRTFontStringGray",
    ["KRTSpammerOutput"] = "GameFontHighlightSmall",
    ["KRTSpammerPreviewStr"] = "GameFontNormal",
    ["KRTSpammerRanged"] = "KRTSpammerEditBox",
    ["KRTSpammerRangedClass"] = "KRTSpammerEditBox",
    ["KRTSpammerRangedStr"] = "GameFontNormalSmall",
    ["KRTSpammerStartBtn"] = "KRTButtonTemplate",
    ["KRTSpammerTank"] = "KRTSpammerEditBox",
    ["KRTSpammerTankClass"] = "KRTSpammerEditBox",
    ["KRTSpammerTanksStr"] = "GameFontNormalSmall",
    ["KRTSpammerTick"] = "KRTFontStringGray",
    ["KRTWarningButtonTemplateID"] = "KRTFontStringGray",
    ["KRTWarningButtonTemplateName"] = "GameFontNormalSmall",
    ["KRTWarnings"] = "KRTFrameTemplate",
    ["KRTWarningsAnnounceBtn"] = "KRTButtonTemplate",
    ["KRTWarningsContent"] = "KRTEditBoxTemplate",
    ["KRTWarningsDeleteBtn"] = "KRTButtonTemplate",
    ["KRTWarningsEditBtn"] = "KRTButtonTemplate",
    ["KRTWarningsMessageStr"] = "GameFontNormal",
    ["KRTWarningsName"] = "GameFontHighlight",
    ["KRTWarningsNameStr"] = "GameFontNormal",
    ["KRTWarningsOutputContent"] = "KRTFontStringGray",
    ["KRTWarningsOutputName"] = "GameFontNormal",
    ["KRTWarningsScrollFrame"] = "KRTScrollFrameTemplate",
}

local templateInheritsMap = {
    ["KRTConfigCheckButtonTemplate"] = "InterfaceOptionsCheckButtonTemplate",
    ["KRTConfigFontStringTemplate"] = "GameFontHighlightSmall",
    ["KRTEditBoxTemplate"] = "InputBoxTemplate",
    ["KRTFontStringGray"] = "GameFontNormalSmall",
    ["KRTFrameTemplate"] = "UIPanelDialogTemplate",
    ["KRTScrollFrameTemplate"] = "UIPanelScrollFrameTemplate",
    ["KRTSpammerCheckButton"] = "SendMailRadioButtonTemplate",
    ["KRTSpammerEditBox"] = "KRTEditBoxTemplate",
}

local templateBindings = {
    ["KRTButtonTemplate"] = {
        root = {
            OnLoad = [[
self:RegisterForClicks("AnyUp")
]],
        },
        children = {
        },
    },
    ["KRTChangesButtonTemplate"] = {
        root = {
            OnClick = [[
KRT.Changes:Select(self, button)
]],
            OnDoubleClick = [[
KRT.Changes:Edit(self)
]],
        },
        children = {
        },
    },
    ["KRTConfigCheckButtonTemplate"] = {
        root = {
            OnClick = [[
KRT.Config:OnClick(self, button)
]],
        },
        children = {
        },
    },
    ["KRTEditBoxSimpleTemplate"] = {
        root = {
            OnEscapePressed = [[
self:ClearFocus()
]],
        },
        children = {
        },
    },
    ["KRTEditBoxTemplate"] = {
        root = {
            OnEscapePressed = [[
self:ClearFocus()
]],
        },
        children = {
        },
    },
    ["KRTItemSelectionButton"] = {
        root = {
            OnClick = [[
KRT.Master:BtnSelectedItem(self, button)
]],
        },
        children = {
        },
    },
    ["KRTLoggerBossAttendeeButton"] = {
        root = {
            OnClick = [[
KRT.Logger:SelectBossPlayer(self, button)
]],
        },
        children = {
        },
    },
    ["KRTLoggerBossButton"] = {
        root = {
            OnClick = [[
KRT.Logger:SelectBoss(self, button)
]],
        },
        children = {
        },
    },
    ["KRTLoggerLootButton"] = {
        root = {
            OnClick = [[
KRT.Logger:SelectItem(self, button)
]],
            OnEnter = [[
KRT.Logger:OnLootRowEnter(self)
]],
            OnLeave = [[
KRT.Logger:OnLootRowLeave(self)
]],
            OnLoad = [[
self:RegisterForClicks("AnyUp")
]],
        },
        children = {
            ["Item"] = {
                OnEnter = [[
KRT.Logger.Loot:OnEnter(self)
]],
                OnLeave = [[
GameTooltip:Hide()
]],
            },
        },
    },
    ["KRTLoggerRaidAttendeeButton"] = {
        root = {
            OnClick = [[
KRT.Logger:SelectPlayer(self, button)
]],
        },
        children = {
        },
    },
    ["KRTLoggerRaidButton"] = {
        root = {
            OnClick = [[
KRT.Logger:SelectRaid(self, button)
]],
        },
        children = {
        },
    },
    ["KRTSpammerCheckButton"] = {
        root = {
            OnClick = [[
KRT.Spammer:Save(self, button)
]],
        },
        children = {
        },
    },
    ["KRTSpammerEditBox"] = {
        root = {
            OnEditFocusLost = [[
KRT.Spammer:Save(self)
]],
            OnEnterPressed = [[
KRT.Spammer:Save(self)
]],
            OnTextChanged = [[
KRT.Spammer:Pause()
]],
        },
        children = {
        },
    },
    ["KRTWarningButtonTemplate"] = {
        root = {
            OnClick = [[
KRT.Warnings:Select(self, button)
]],
            OnLoad = [[
self:RegisterForClicks("LeftButtonUp")
]],
        },
        children = {
        },
    },
}

local unpack = unpack
local compiled = {}
local templateNameCache = {}
local templateScriptCache = {}

local function mergeMap(dst, src)
    if not src then return end
    for key, value in pairs(src) do
        dst[key] = value
    end
end

local function hasEntries(map)
    return map and next(map) ~= nil
end

local function parseTemplateList(templateList)
    if type(templateList) ~= "string" or templateList == "" then
        return nil
    end

    local cached = templateNameCache[templateList]
    if cached then
        return cached
    end

    local out = {}
    for templateName in gmatch(templateList, "([^,%s]+)") do
        out[#out + 1] = templateName
    end
    templateNameCache[templateList] = out
    return out
end

local function trimBinderToken(value)
    if type(value) ~= "string" then
        return ""
    end
    return strgsub(value, "^%s*(.-)%s*$", "%1")
end

local function splitCommaArgs(argList)
    local out = {}
    local clean = trimBinderToken(argList)
    if clean == "" then
        return out
    end
    for token in gmatch(clean, "([^,]+)") do
        out[#out + 1] = trimBinderToken(token)
    end
    return out
end

local function parseStringLiteral(token)
    local value = strmatch(token, "^\"(.*)\"$")
    if value ~= nil then
        return strgsub(value, "\\\"", "\"")
    end
    return nil
end

local function resolveObjectPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local first, rest = strmatch(path, "^([^.]+)%.?(.*)$")
    if not first then
        return nil
    end

    local object
    if first == "KRT" then
        object = addon
    else
        object = _G[first]
    end
    if not object then
        return nil
    end

    if rest and rest ~= "" then
        for part in gmatch(rest, "([^.]+)") do
            object = object[part]
            if object == nil then
                return nil
            end
        end
    end

    return object
end

local function resolveArgToken(token, self, arg1, arg2)
    if token == "self" then
        return self
    end
    if token == "button" then
        return arg1
    end
    if token == "down" then
        return arg2
    end
    if token == "value" then
        return arg1
    end
    if token == "true" then
        return true
    end
    if token == "false" then
        return false
    end
    if token == "nil" then
        return nil
    end

    local strLiteral = parseStringLiteral(token)
    if strLiteral ~= nil then
        return strLiteral
    end

    local numeric = tonumber(token)
    if numeric ~= nil then
        return numeric
    end

    return token
end

local function buildResolvedArgs(tokens, self, arg1, arg2)
    if not tokens or #tokens == 0 then
        return nil, 0
    end

    local out = {}
    for i = 1, #tokens do
        out[i] = resolveArgToken(tokens[i], self, arg1, arg2)
    end
    return out, #tokens
end

local function parseBodyToHandler(body)
    local focusSuffix = strmatch(body, '^_G%[self:GetParent%(%)%:GetName%(%)%.%.%"([^"]+)"%]%:SetFocus%(%s*%)$')
    if focusSuffix then
        return function(self)
            local parent = self and self.GetParent and self:GetParent()
            local parentName = parent and parent.GetName and parent:GetName()
            if not parentName then
                return
            end
            local target = _G[parentName .. focusSuffix]
            if target and target.SetFocus then
                target:SetFocus()
            end
        end
    end

    local parentMethod, parentArgs = strmatch(body, "^self:GetParent%(%)%:([%w_]+)%((.-)%)$")
    if parentMethod then
        local argTokens = splitCommaArgs(parentArgs)
        return function(self, ...)
            local parent = self and self.GetParent and self:GetParent()
            if not parent then
                return
            end
            local method = parent[parentMethod]
            if type(method) ~= "function" then
                return
            end
            local arg1, arg2 = ...
            local resolved, n = buildResolvedArgs(argTokens, self, arg1, arg2)
            if n == 0 then
                return method(parent)
            end
            return method(parent, unpack(resolved, 1, n))
        end
    end

    local selfMethod, selfArgs = strmatch(body, "^self:([%w_]+)%((.-)%)$")
    if selfMethod then
        local argTokens = splitCommaArgs(selfArgs)
        return function(self, ...)
            if not self then
                return
            end
            local method = self[selfMethod]
            if type(method) ~= "function" then
                return
            end
            local arg1, arg2 = ...
            local resolved, n = buildResolvedArgs(argTokens, self, arg1, arg2)
            if n == 0 then
                return method(self)
            end
            return method(self, unpack(resolved, 1, n))
        end
    end

    local objectPath, methodName, methodArgs = strmatch(body, "^([%w_%.]+):([%w_]+)%((.-)%)$")
    if objectPath and methodName then
        local argTokens = splitCommaArgs(methodArgs)
        return function(self, ...)
            local target = resolveObjectPath(objectPath)
            if not target then
                return
            end
            local method = target[methodName]
            if type(method) ~= "function" then
                return
            end
            local arg1, arg2 = ...
            local resolved, n = buildResolvedArgs(argTokens, self, arg1, arg2)
            if n == 0 then
                return method(target)
            end
            return method(target, unpack(resolved, 1, n))
        end
    end

    return nil, "unsupported_expression"
end

local function compileHandler(frameName, scriptName, body)
    if type(body) == "function" then
        return body
    end
    if type(body) ~= "string" then
        return nil
    end

    local normalizedBody = trimBinderToken(strgsub(body, "\r", ""))
    if normalizedBody == "" then
        return nil
    end

    local cacheKey = tostring(scriptName) .. "::" .. normalizedBody
    local cached = compiled[cacheKey]
    if cached then
        return cached
    end

    local fn, err = parseBodyToHandler(normalizedBody)
    if type(fn) ~= "function" then
        if addon and addon.error then
            addon:error("[UIBinder] parse failed frame=%s script=%s expr=%s err=%s",
                tostring(frameName), tostring(scriptName), tostring(normalizedBody), tostring(err))
        end
        return nil
    end

    compiled[cacheKey] = fn
    return fn
end

local function applyScriptMap(frame, frameName, scriptMap)
    if not (frame and frame.SetScript and hasEntries(scriptMap)) then
        return
    end
    if not shouldBindFrame(frameName) then
        return
    end

    for scriptName, body in pairs(scriptMap) do
        if scriptName ~= "OnLoad" then
            local fn = compileHandler(frameName, scriptName, body)
            if fn then
                scriptMap[scriptName] = fn
                frame:SetScript(scriptName, fn)
            end
        end
    end

    local onLoadBody = scriptMap.OnLoad
    if onLoadBody then
        local onLoad = compileHandler(frameName, "OnLoad", onLoadBody)
        if onLoad then
            scriptMap.OnLoad = onLoad
            onLoad(frame)
        end
    end
end

local function normalizeScriptMap(scriptMap, mapName)
    if not hasEntries(scriptMap) then
        return
    end

    for scriptName, body in pairs(scriptMap) do
        local fn = compileHandler(mapName, scriptName, body)
        if fn then
            scriptMap[scriptName] = fn
        end
    end
end

local function normalizeAllBindings()
    for frameName, scriptMap in pairs(frameBindings) do
        normalizeScriptMap(scriptMap, frameName)
    end

    for templateName, bundle in pairs(templateBindings) do
        normalizeScriptMap(bundle and bundle.root, templateName .. ".root")
        if bundle and bundle.children then
            for suffix, childMap in pairs(bundle.children) do
                normalizeScriptMap(childMap, templateName .. "." .. tostring(suffix))
            end
        end
    end
end

local function collectTemplateScripts(templateName, rootOut, childrenOut, seen)
    if not templateName or seen[templateName] then
        return
    end
    seen[templateName] = true

    local inherited = parseTemplateList(templateInheritsMap[templateName])
    if inherited then
        for i = 1, #inherited do
            collectTemplateScripts(inherited[i], rootOut, childrenOut, seen)
        end
    end

    local scripts = templateBindings[templateName]
    if not scripts then
        return
    end

    mergeMap(rootOut, scripts.root)
    for suffix, scriptMap in pairs(scripts.children) do
        local target = childrenOut[suffix]
        if not target then
            target = {}
            childrenOut[suffix] = target
        end
        mergeMap(target, scriptMap)
    end
end

local function resolveTemplateScripts(templateList)
    if type(templateList) ~= "string" or templateList == "" then
        return nil
    end

    local cached = templateScriptCache[templateList]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local templates = parseTemplateList(templateList)
    if not templates or #templates == 0 then
        templateScriptCache[templateList] = false
        return nil
    end

    local root = {}
    local children = {}
    for i = 1, #templates do
        local seen = {}
        collectTemplateScripts(templates[i], root, children, seen)
    end

    if not hasEntries(root) and not hasEntries(children) then
        templateScriptCache[templateList] = false
        return nil
    end

    local bundle = { root = root, children = children }
    templateScriptCache[templateList] = bundle
    return bundle
end

function UIBinder:BindCreatedFrame(frame, frameName, templateList)
    if not frame then
        return nil
    end

    local bundle = resolveTemplateScripts(templateList)
    if not bundle then
        return frame
    end

    applyScriptMap(frame, frameName or "<anonymous>", bundle.root)

    if frameName and hasEntries(bundle.children) then
        for suffix, scriptMap in pairs(bundle.children) do
            local childName = frameName .. suffix
            local child = _G[childName]
            if child then
                applyScriptMap(child, childName, scriptMap)
            end
        end
    end

    return frame
end

function UIBinder:BindAll()
    if self._bound then
        return
    end

    local frameNames = {}
    for frameName in pairs(frameTemplateMap) do
        frameNames[frameName] = true
    end
    for frameName in pairs(frameBindings) do
        frameNames[frameName] = true
    end

    for frameName in pairs(frameNames) do
        local frame = _G[frameName]
        if frame then
            local merged = {}

            local templateBundle = resolveTemplateScripts(frameTemplateMap[frameName])
            if templateBundle then
                mergeMap(merged, templateBundle.root)
                if hasEntries(templateBundle.children) then
                    for suffix, scriptMap in pairs(templateBundle.children) do
                        local childName = frameName .. suffix
                        local child = _G[childName]
                        if child then
                            applyScriptMap(child, childName, scriptMap)
                        end
                    end
                end
            end

            mergeMap(merged, frameBindings[frameName])
            applyScriptMap(frame, frameName, merged)
        end
    end

    self._bound = true
end

function UIBinder:PatchCreateFrame()
    if self._createFramePatched then
        return
    end

    local originalCreateFrame = _G.CreateFrame
    self._originalCreateFrame = originalCreateFrame

    local binder = self
    _G.CreateFrame = function(frameType, frameName, parent, templateList)
        local frame = originalCreateFrame(frameType, frameName, parent, templateList)
        binder:BindCreatedFrame(frame, frameName, templateList)
        return frame
    end

    self._createFramePatched = true
end

normalizeAllBindings()

UIBinder:PatchCreateFrame()

do
    local addonName = addon.name
    local binderFrame = _G.CreateFrame("Frame")
    binderFrame:RegisterEvent("ADDON_LOADED")
    binderFrame:SetScript("OnEvent", function(_, _, loadedAddonName)
        if loadedAddonName ~= addonName then
            return
        end

        UIBinder:BindAll()
        binderFrame:UnregisterEvent("ADDON_LOADED")
    end)
end
