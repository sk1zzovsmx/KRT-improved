local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local K_COLOR = C.K_COLOR
local RT_COLOR = C.RT_COLOR

---============================================================================
-- Minimap Button Module
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Minimap = addon.Minimap or {}
    local module = addon.Minimap
    local L = addon.L

    -------------------------------------------------------
    -- 3. Internal state (non-exposed local variables)
    -------------------------------------------------------
    local addonMenu
    local dragMode

    -- Cached math functions
    local abs, sqrt = math.abs, math.sqrt
    local cos, sin = math.cos, math.sin
    local rad, atan2, deg = math.rad, math.atan2, math.deg

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------
    -- Initializes and opens the right-click menu for the minimap button.
    local function OpenMenu()
        local info = {}
        local function AddMenuButton(level, text, func)
            twipe(info)
            info.text = text
            info.notCheckable = 1
            info.func = func
            UIDropDownMenu_AddButton(info, level)
        end

        local function AddMenuTitle(level, text)
            twipe(info)
            info.isTitle = 1
            info.text = text
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
        end

        local function AddMenuSeparator(level)
            twipe(info)
            info.disabled = 1
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
        end

        addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
        addonMenu.displayMode = "MENU"
        addonMenu.initialize = function(self, level)
            if level == 1 then
                -- Toggle master loot frame:
                AddMenuButton(level, MASTER_LOOTER, function() addon.Master:Toggle() end)
                -- Toggle raid warnings frame:
                AddMenuButton(level, RAID_WARNING, function() addon.Warnings:Toggle() end)
                -- Toggle loot logger frame:
                AddMenuButton(level, L.StrLootLogger, function() addon.Logger:Toggle() end)
                -- Separator:
                AddMenuSeparator(level)
                -- Clear raid icons:
                AddMenuButton(level, L.StrClearIcons, function() addon.Raid:ClearRaidIcons() end)
                -- Separator:
                AddMenuSeparator(level)
                -- MS changes header:
                AddMenuTitle(level, L.StrMSChanges)
                -- Toggle MS Changes frame:
                AddMenuButton(level, L.BtnConfigure, function() addon.Changes:Toggle() end)
                -- Ask for MS changes:
                AddMenuButton(level, L.BtnDemand, function() addon.Changes:Demand() end)
                -- Spam ms changes:
                AddMenuButton(level, CHAT_ANNOUNCE, function() addon.Changes:Announce() end)
                AddMenuSeparator(level)
                -- Toggle lfm spammer frame:
                AddMenuButton(level, L.StrLFMSpam, function() addon.Spammer:Toggle() end)
            end
        end
        ToggleDropDownMenu(1, nil, addonMenu, KRT_MINIMAP_GUI, 0, 0)
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

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------
    local function SetMinimapShown(show)
        Utils.setShown(KRT_MINIMAP_GUI, show)
    end

    function module:SetPos(angle)
        local options = addon.options
        angle = angle % 360
        options.minimapPos = angle
        local r = rad(angle)
        KRT_MINIMAP_GUI:ClearAllPoints()
        KRT_MINIMAP_GUI:SetPoint("CENTER", cos(r) * 80, sin(r) * 80)
    end

    function module:OnLoad()
        local options = addon.options
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
                OpenMenu()
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
        local options = addon.options
        options.minimapButton = not options.minimapButton
        SetMinimapShown(options.minimapButton)
    end

    -- Hides the minimap button.
    function module:HideMinimapButton()
        return Utils.setShown(KRT_MINIMAP_GUI, false)
    end
end
