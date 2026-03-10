--[[
    Features/Minimap.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Utils = feature.Utils

local K_COLOR = feature.K_COLOR

-- =========== Minimap Button Module  =========== --
do
    addon.Minimap = addon.Minimap or {}
    local module = addon.Minimap
    -- ----- Internal state ----- --
    local addonMenu
    local dragMode

    -- Cached math functions
    local sqrt = math.sqrt
    local cos, sin = math.cos, math.sin
    local rad, atan2, deg = math.rad, math.atan2, math.deg

    -- ----- Private helpers ----- --
    -- Menu definition for EasyMenu (built once).
    local minimapMenu = {
        { text = MASTER_LOOTER,    notCheckable = 1, func = function() addon.Master:Toggle() end },
        { text = L.StrLootCounter, notCheckable = 1, func = function() addon.LootCounter:Toggle() end },
        { text = L.StrLootLogger,  notCheckable = 1, func = function() addon.Logger:Toggle() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrClearIcons,  notCheckable = 1, func = function() addon.Raid:ClearRaidIcons() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = RAID_WARNING,     notCheckable = 1, func = function() addon.Warnings:Toggle() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrMSChanges,   notCheckable = 1, func = function() addon.Changes:Toggle() end },
        { text = L.BtnDemand,      notCheckable = 1, func = function() addon.Changes:Demand() end },
        { text = CHAT_ANNOUNCE,    notCheckable = 1, func = function() addon.Changes:Announce() end },
        { text = " ",              disabled = 1,     notCheckable = 1 },
        { text = L.StrLFMSpam,     notCheckable = 1, func = function() addon.Spammer:Toggle() end },
    }

    -- Initializes and opens the menu for the minimap button.
    local function OpenMenu()
        addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
        -- EasyMenu handles UIDropDownMenu initialization and opening.
        EasyMenu(minimapMenu, addonMenu, KRT_MINIMAP_GUI, 0, 0, "MENU")
    end

    local function IsMenuOpen()
        return addonMenu and UIDROPDOWNMENU_OPEN_MENU == addonMenu and DropDownList1 and DropDownList1:IsShown()
    end

    local function ToggleMenu()
        if IsMenuOpen() then
            CloseDropDownMenus()
            return
        end
        OpenMenu()
    end

    -- Moves the minimap button while dragging.
    local function moveButton(self)
        local centerX, centerY = Minimap:GetCenter()
        local x, y = GetCursorPosition()
        x, y = x / self:GetEffectiveScale() - centerX, y / self:GetEffectiveScale() - centerY

        if dragMode == "free" then
            -- Free drag mode
            self:ClearAllPoints()
            self:SetPoint("CENTER", x, y)
        else
            -- Circular drag mode (snap to ring radius ~80)
            local dist = sqrt(x * x + y * y)
            local px, py = (x / dist) * 80, (y / dist) * 80
            self:ClearAllPoints()
            self:SetPoint("CENTER", px, py)
        end
    end

    local function SetMinimapShown(show)
        Utils.setShown(KRT_MINIMAP_GUI, show)
    end

    -- ----- Public methods ----- --
    function module:SetPos(angle)
        angle = angle % 360
        Utils.setOption("minimapPos", angle)
        local r = rad(angle)
        KRT_MINIMAP_GUI:ClearAllPoints()
        KRT_MINIMAP_GUI:SetPoint("CENTER", cos(r) * 80, sin(r) * 80)
    end

    function module:OnLoad()
        local options = addon.options or KRT_Options or {}
        KRT_MINIMAP_GUI:SetUserPlaced(true)
        self:SetPos(options.minimapPos or 325)
        SetMinimapShown(options.minimapButton ~= false)
        KRT_MINIMAP_GUI:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        KRT_MINIMAP_GUI:SetScript("OnMouseDown", function(self, button)
            if IsAltKeyDown() then
                dragMode = "free"
                self:SetScript("OnUpdate", moveButton)
            elseif IsShiftKeyDown() then
                dragMode = nil
                self:SetScript("OnUpdate", moveButton)
            end
        end)
        KRT_MINIMAP_GUI:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil)
            if dragMode == "free" then
                dragMode = nil
                return
            end
            local mx, my = Minimap:GetCenter()
            local bx, by = self:GetCenter()
            module:SetPos(deg(atan2(by - my, bx - mx)))
            dragMode = nil
        end)
        KRT_MINIMAP_GUI:SetScript("OnClick", function(self, button, down)
            -- Ignore clicks if Shift or Alt keys are held:
            if IsShiftKeyDown() or IsAltKeyDown() then return end
            if button == "RightButton" then
                addon.Config:Toggle()
            elseif button == "LeftButton" then
                ToggleMenu()
            end
        end)
        KRT_MINIMAP_GUI:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetText(
                addon.WrapTextInColorCode("Kader", Utils.normalizeHexColor(K_COLOR))
                .. " "
                .. addon.WrapTextInColorCode("Raid Tools", Utils.normalizeHexColor("aad4af37"))
            )
            GameTooltip:AddLine(L.StrMinimapLClick, 1, 1, 1)
            GameTooltip:AddLine(L.StrMinimapRClick, 1, 1, 1)
            GameTooltip:AddLine(L.StrMinimapSClick, 1, 1, 1)
            GameTooltip:AddLine(L.StrMinimapAClick, 1, 1, 1)
            GameTooltip:Show()
        end)
        KRT_MINIMAP_GUI:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end

    -- Toggles the visibility of the minimap button.
    function module:ToggleMinimapButton()
        local options = addon.options or KRT_Options or {}
        local nextValue = not options.minimapButton
        Utils.setOption("minimapButton", nextValue)
        SetMinimapShown(nextValue)
    end

    -- Hides the minimap button.
    function module:HideMinimapButton()
        return Utils.setShown(KRT_MINIMAP_GUI, false)
    end
end
