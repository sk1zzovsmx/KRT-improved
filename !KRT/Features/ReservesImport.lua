--[[
    Features/ReservesImport.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

local _G = _G

local pairs, type = pairs, type

local tostring, tonumber = tostring, tonumber

-- =========== Reserve Import Window Module  =========== --
-- Handles the CSV import dialog for Reserves.
do
    addon.ReservesImport = addon.ReservesImport or {}
    local module = addon.ReservesImport

    -- ----- Internal state ----- --
    local getFrame = makeModuleFrameGetter(module, "KRTImportWindow")
    local localized = false
    -- Import mode slider: 0 = Multi-reserve, 1 = Plus System (priority)
    local MODE_MULTI, MODE_PLUS = 0, 1

    -- ----- Private helpers ----- --
    local function GetImportModeString()
        if addon.Reserves and addon.Reserves.GetImportMode then
            return addon.Reserves:GetImportMode()
        end
        local v = addon.options and addon.options.srImportMode
        if v == MODE_PLUS then return "plus" end
        return "multi"
    end

    local function GetImportModeValue()
        return (GetImportModeString() == "plus") and MODE_PLUS or MODE_MULTI
    end

    local function GetModeSlider()
        return _G["KRTImportWindowModeSlider"] or _G["KRTImportModeSlider"]
    end

    -- ----- Public methods ----- --
    function module:SetImportMode(modeValue, suppressSlider)
        local mode = (modeValue == MODE_PLUS) and "plus" or "multi"
        if addon.Reserves and addon.Reserves.SetImportMode then
            addon.Reserves:SetImportMode(mode, true)
        else
            Utils.setOption("srImportMode", (mode == "plus") and MODE_PLUS or MODE_MULTI)
        end

        if not suppressSlider then
            local s = GetModeSlider()
            if s and s.SetValue then
                s:SetValue(GetImportModeValue())
            end
        end
    end

    function module:OnModeSliderLoad(slider)
        if not slider then return end
        slider:SetMinMaxValues(MODE_MULTI, MODE_PLUS)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

        local low = _G[slider:GetName() .. "Low"]
        local high = _G[slider:GetName() .. "High"]
        local text = _G[slider:GetName() .. "Text"]
        if low then low:SetText(L.StrImportModeMulti or "Multi-reserve") end
        if high then high:SetText(L.StrImportModePlus or "Plus System") end
        if text then text:SetText(L.StrImportModeLabel or "") end

        slider:SetValue(GetImportModeValue())
    end

    function module:OnModeSliderChanged(slider, value)
        if not slider then return end
        local v = tonumber(value) or MODE_MULTI
        if v >= 0.5 then v = MODE_PLUS else v = MODE_MULTI end
        module:SetImportMode(v, true)
    end

    -- Popup shown when Plus System is selected but CSV contains multi-item reserves per player.
    local function EnsureWrongCSVPopup()
        if StaticPopupDialogs and StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] then return end
        if not StaticPopupDialogs then return end

        StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] = {
            text = L.ErrCSVWrongForPlus,
            button1 = L.BtnSwitchToMulti,
            button2 = L.BtnCancel,
            OnShow = function(self, data)
                if not self or not self.text then return end
                local msg = L.ErrCSVWrongForPlus
                if type(data) == "table" and data.player then
                    msg = L.ErrCSVWrongForPlusWithPlayer:format(tostring(data.player))
                end
                self.text:SetText(msg)
            end,
            OnAccept = function(self, data)
                if type(data) ~= "table" or type(data.csv) ~= "string" then return end
                module:SetImportMode(MODE_MULTI)

                -- Re-run import in multi mode (Plus ignored by definition).
                local ok = addon.Reserves:ParseCSV(data.csv, "multi")
                if ok then
                    module:Hide()
                    local rf = (addon.Reserves and addon.Reserves.frame) or _G["KRTReserveListFrame"]
                    if not (rf and rf.IsShown and rf:IsShown()) then
                        addon.Reserves:Toggle()
                    else
                        addon.Reserves:RequestRefresh()
                    end
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    local function LocalizeUIFrame()
        if localized then return end
        local frame = getFrame()
        if not frame then return end

        local confirmButton = _G["KRTImportConfirmButton"]
        if confirmButton then confirmButton:SetText(L.BtnImport) end
        local cancelButton = _G["KRTImportCancelButton"]
        if cancelButton then cancelButton:SetText(L.BtnClose) end

        Utils.setFrameTitle(frame, L.StrImportReservesTitle)
        local hint = _G["KRTImportWindowHint"]
        if hint then hint:SetText(L.StrImportReservesHint) end

        localized = true
    end

    function module:OnLoad(frame)
        Utils.initModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                Utils.resetEditBox(_G["KRTImportEditBox"])
                local editBox = _G["KRTImportEditBox"]
                if editBox then
                    editBox:SetFocus()
                    editBox:HighlightText()
                end
                local status = _G["KRTImportWindowStatus"]
                if status then status:SetText("") end
                module:RequestRefresh()
            end,
        })
        module:RequestRefresh()
    end

    function module:Refresh()
        LocalizeUIFrame()
        local slider = GetModeSlider()
        if slider and slider.SetValue then
            slider:SetValue(GetImportModeValue())
        end
        local status = _G["KRTImportWindowStatus"]
        if status and (status:GetText() == nil or status:GetText() == "") then
            status:SetText("")
        end
    end

    -- Initialize UI controller for Toggle/Hide.
    Utils.bootstrapModuleUi(module, getFrame, function() module:RequestRefresh() end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    function module:ImportFromEditBox()
        local editBox = _G["KRTImportEditBox"]
        local status = _G["KRTImportWindowStatus"]
        if status then status:SetText("") end
        if not editBox then return false, 0 end

        local csv = editBox:GetText()
        if type(csv) ~= "string" or not csv:match("%S") then
            if status then
                status:SetText(L.ErrImportReservesEmpty)
                status:SetTextColor(1, 0.2, 0.2)
            end
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return false, 0
        end

        addon:debug(Diag.D.LogSRImportRequested:format(#csv))
        EnsureWrongCSVPopup()
        local mode = GetImportModeString()
        local ok, nPlayers, errCode, errData = addon.Reserves:ParseCSV(csv, mode)
        if (not ok) and errCode == "CSV_WRONG_FOR_PLUS" then
            if status then
                status:SetText(L.ErrCSVWrongForPlusShort)
                status:SetTextColor(1, 0.2, 0.2)
            end
            local popupData = { csv = csv }
            if type(errData) == "table" then
                for k, v in pairs(errData) do
                    popupData[k] = v
                end
            end
            StaticPopup_Show("KRT_WRONG_CSV_FOR_PLUS", nil, nil, popupData)
            return false, 0
        end
        if ok then
            if status then
                status:SetText(string.format(L.SuccessReservesParsed, tostring(nPlayers)))
                status:SetTextColor(0.2, 1, 0.2)
            end
            module:Hide()
            local rf = (addon.Reserves and addon.Reserves.frame) or _G["KRTReserveListFrame"]
            if not (rf and rf.IsShown and rf:IsShown()) then
                addon.Reserves:Toggle()
            else
                addon.Reserves:RequestRefresh()
            end
            return true, nPlayers
        else
            if status then
                status:SetText(L.ErrImportReservesEmpty)
                status:SetTextColor(1, 0.2, 0.2)
            end
            return false, 0
        end
    end
end
