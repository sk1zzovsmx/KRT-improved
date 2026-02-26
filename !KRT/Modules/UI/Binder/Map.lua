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
}

local frameTemplateMap = {
    ["KRTButtonTemplate"] = "UIPanelButtonDisabledTexture",
    ["KRTEditBoxTemplate"] = "GameFontHighlight",
    ["KRTFrameTemplateTitle"] = "GameFontNormalSmall",
    ["KRTItemSelectionButtonName"] = "GameFontNormalSmall",
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
}

Map.widgetFrameExact = widgetFrameExact
Map.widgetFramePrefixes = widgetFramePrefixes
Map.GetFrameWidgetId = getFrameWidgetId
Map.frameBindings = frameBindings
Map.frameTemplateMap = frameTemplateMap
Map.templateInheritsMap = templateInheritsMap
Map.templateBindings = templateBindings
