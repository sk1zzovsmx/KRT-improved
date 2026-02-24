-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type = type
local strsub = string.sub

addon.UIBinder = addon.UIBinder or {}
local UIBinder = addon.UIBinder

UIBinder.Map = UIBinder.Map or {}
local Map = UIBinder.Map

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

Map.widgetFrameExact = widgetFrameExact
Map.widgetFramePrefixes = widgetFramePrefixes
Map.GetFrameWidgetId = getFrameWidgetId
Map.frameBindings = frameBindings
Map.frameTemplateMap = frameTemplateMap
Map.templateInheritsMap = templateInheritsMap
Map.templateBindings = templateBindings


