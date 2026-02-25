-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
-- @legacy transitional: scheduled for removal; use XML-first layout with explicit Lua wiring.

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type = type
local strsub = string.sub

addon.UIBinder = addon.UIBinder or {}
local UIBinder = addon.UIBinder

UIBinder.Map = UIBinder.Map or {}
local Map = UIBinder.Map

local widgetFrameExact = {
}

local widgetFramePrefixes = {
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
}

local frameTemplateMap = {
    ["KRTButtonTemplate"] = "UIPanelButtonDisabledTexture",
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
    ["KRTMaster"] = "KRTFrameTemplate",
    ["KRTMasterAwardBtn"] = "KRTButtonTemplate",
    ["KRTMasterBankBtn"] = "KRTButtonTemplate",
    ["KRTMasterBankDropDown"] = "UIDropDownMenuTemplate",
    ["KRTMasterClearBtn"] = "KRTButtonTemplate",
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
    ["KRTWarningButtonTemplateID"] = "KRTFontStringGray",
    ["KRTWarningButtonTemplateName"] = "GameFontNormalSmall",
}

local templateInheritsMap = {
    ["KRTEditBoxTemplate"] = "InputBoxTemplate",
    ["KRTFontStringGray"] = "GameFontNormalSmall",
    ["KRTFrameTemplate"] = "UIPanelDialogTemplate",
    ["KRTScrollFrameTemplate"] = "UIPanelScrollFrameTemplate",
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
}

Map.widgetFrameExact = widgetFrameExact
Map.widgetFramePrefixes = widgetFramePrefixes
Map.GetFrameWidgetId = getFrameWidgetId
Map.frameBindings = frameBindings
Map.frameTemplateMap = frameTemplateMap
Map.templateInheritsMap = templateInheritsMap
Map.templateBindings = templateBindings
