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
local Colors = feature.Colors or addon.Colors
local Core = feature.Core or addon.Core

local K_COLOR = feature.K_COLOR

local UIFacade = addon.UI or {}
if type(UIFacade.Call) ~= "function" then
    UIFacade.Call = function()
        return nil
    end
end
if type(UIFacade.IsEnabled) ~= "function" then
    UIFacade.IsEnabled = function()
        return true
    end
end
if type(UIFacade.IsRegistered) ~= "function" then
    UIFacade.IsRegistered = function()
        return false
    end
end

-- =========== Minimap Button Module  =========== --
addon.Minimap = addon.Minimap or {}
local module = addon.Minimap

local function getController(name)
    if Core and Core.GetController then
        return Core.GetController(name)
    end
    local controllers = addon.Controllers
    return controllers and controllers[name] or nil
end

local function getChangesController()
    local controller = getController("Changes")
    if type(controller) == "table" then
        return controller
    end
    local legacy = addon.Changes
    if type(legacy) == "table" then
        return legacy
    end
    return nil
end

local function getLootCounterWidget()
    local widgets = addon.Widgets
    local legacy = (widgets and widgets.LootCounter) or addon.LootCounter
    if type(legacy) == "table" and type(legacy.Toggle) == "function" then
        return legacy
    end
    return nil
end

local function IsWidgetAvailable(widgetId)
    if UIFacade:IsEnabled(widgetId) and UIFacade:IsRegistered(widgetId) then
        return true
    end
    if widgetId == "LootCounter" and getLootCounterWidget() then
        return true
    end
    return false
end

-- ----- Internal state ----- --
local addonMenu
local dragMode
local dragActive = false
local UI = {
    Bound = false,
}

-- Cached math functions
local sqrt = math.sqrt
local cos, sin = math.cos, math.sin
local rad, atan2, deg = math.rad, math.atan2, math.deg
local MINIMAP_RING_RADIUS = 80
local MIN_DRAG_DISTANCE = 0.001

-- ----- Private helpers ----- --
function UI.AcquireRefs(frame)
    return {
        button = frame,
    }
end

local function BuildMenu()
    local hasRaidGroup = addon.Raid:IsPlayerInRaid()
    local disableRaidActions = 1
    if hasRaidGroup then
        disableRaidActions = nil
    end

    return {
        {
            text = MASTER_LOOTER,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Master")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        {
            text = L.StrLootCounter,
            notCheckable = 1,
            disabled = disableRaidActions,
            func = function()
                if not addon.Raid:IsPlayerInRaid() then
                    return
                end
                if not IsWidgetAvailable("LootCounter") then
                    return
                end
                if UIFacade:IsEnabled("LootCounter") and UIFacade:IsRegistered("LootCounter") then
                    UIFacade:Call("LootCounter", "Toggle")
                    return
                end
                local legacy = getLootCounterWidget()
                if legacy and legacy.Toggle then
                    legacy:Toggle()
                end
            end
        },
        {
            text = L.StrLootLogger,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Logger")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        { text = L.StrClearIcons, notCheckable = 1, func = function() addon.Raid:ClearRaidIcons() end },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = RAID_WARNING,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Warnings")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = L.StrMSChanges,
            notCheckable = 1,
            func = function()
                local moduleRef = getChangesController()
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
        {
            text = L.BtnDemand,
            notCheckable = 1,
            disabled = disableRaidActions,
            func = function()
                if not addon.Raid:IsPlayerInRaid() then
                    return
                end
                local moduleRef = getChangesController()
                if moduleRef and moduleRef.Demand then
                    moduleRef:Demand()
                end
            end
        },
        {
            text = CHAT_ANNOUNCE,
            notCheckable = 1,
            disabled = disableRaidActions,
            func = function()
                if not addon.Raid:IsPlayerInRaid() then
                    return
                end
                local moduleRef = getChangesController()
                if moduleRef and moduleRef.Announce then
                    moduleRef:Announce()
                end
            end
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = L.StrLFMSpam,
            notCheckable = 1,
            func = function()
                local moduleRef = getController("Spammer")
                if moduleRef and moduleRef.Toggle then
                    moduleRef:Toggle()
                end
            end
        },
    }
end

-- Initializes and opens the menu for the minimap button.
local function OpenMenu()
    addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
    local menu = BuildMenu()
    -- EasyMenu handles UIDropDownMenu initialization and opening.
    EasyMenu(menu, addonMenu, KRT_MINIMAP_GUI, 0, 0, "MENU")
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
    if not dragActive then
        return
    end

    local scale = self and self.GetEffectiveScale and self:GetEffectiveScale()
    if not scale or scale == 0 then
        return
    end

    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    if not cursorX or not cursorY then
        return
    end

    local x, y = cursorX / scale - centerX, cursorY / scale - centerY

    if dragMode == "free" then
        -- Free drag mode
        self:ClearAllPoints()
        self:SetPoint("CENTER", x, y)
    else
        -- Circular drag mode (snap to ring radius ~80)
        local dist = sqrt(x * x + y * y)
        if dist <= MIN_DRAG_DISTANCE then
            return
        end
        local px, py = (x / dist) * MINIMAP_RING_RADIUS, (y / dist) * MINIMAP_RING_RADIUS
        self:ClearAllPoints()
        self:SetPoint("CENTER", px, py)
    end
end

local function SetMinimapShown(show)
    Frames.SetShown(KRT_MINIMAP_GUI, show)
end

-- ----- Public methods ----- --
function module:SetPos(angle)
    local frame = self.frame or Frames.Get("KRT_MINIMAP_GUI") or KRT_MINIMAP_GUI
    if not frame then
        return
    end
    angle = angle % 360
    Options.SetOption("minimapPos", angle)
    local r = rad(angle)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", cos(r) * MINIMAP_RING_RADIUS, sin(r) * MINIMAP_RING_RADIUS)
end

function module:OnLoad(frame)
    frame = frame or Frames.Get("KRT_MINIMAP_GUI") or KRT_MINIMAP_GUI
    if not frame then
        return nil
    end

    self.frame = frame
    local options = addon.options or KRT_Options or {}
    frame:SetUserPlaced(true)
    self:SetPos(options.minimapPos or 325)
    SetMinimapShown(options.minimapButton ~= false)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then
            return
        end
        if IsAltKeyDown() then
            dragMode = "free"
        elseif IsShiftKeyDown() then
            dragMode = "ring"
        else
            return
        end
        dragActive = true
        self:SetScript("OnUpdate", moveButton)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        self:SetScript("OnUpdate", nil)
        if not dragActive then
            return
        end
        local wasFreeDrag = (dragMode == "free")
        dragActive = false
        dragMode = nil
        if wasFreeDrag then
            return
        end
        local mx, my = Minimap:GetCenter()
        local bx, by = self:GetCenter()
        if not (mx and my and bx and by) then
            return
        end
        module:SetPos(deg(atan2(by - my, bx - mx)))
    end)
    frame:SetScript("OnClick", function(self, button)
        -- Ignore clicks if Shift or Alt keys are held:
        if IsShiftKeyDown() or IsAltKeyDown() then return end
        if button == "RightButton" then
            UIFacade:Call("Config", "Toggle")
        elseif button == "LeftButton" then
            ToggleMenu()
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetText(
            addon.WrapTextInColorCode("Kader", Colors.NormalizeHexColor(K_COLOR))
            .. " "
            .. addon.WrapTextInColorCode("Raid Tools", Colors.NormalizeHexColor("aad4af37"))
        )
        GameTooltip:AddLine(L.StrMinimapLClick, 1, 1, 1)
        GameTooltip:AddLine(L.StrMinimapRClick, 1, 1, 1)
        GameTooltip:AddLine(L.StrMinimapSClick, 1, 1, 1)
        GameTooltip:AddLine(L.StrMinimapAClick, 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    return frame
end

function module:BindUI()
    if UI.Bound and self.frame and self.refs then
        return self.frame, self.refs
    end

    local frame = Frames.Get("KRT_MINIMAP_GUI") or KRT_MINIMAP_GUI
    if not frame then
        return nil
    end

    local refs = UI.AcquireRefs(frame)
    self.refs = refs

    self:OnLoad(frame)

    UI.Bound = true
    return frame, refs
end

function module:EnsureUI()
    if UI.Bound and self.frame and self.refs then
        return self.frame
    end
    return self:BindUI()
end

-- Toggles the visibility of the minimap button.
function module:ToggleMinimapButton()
    if not self:EnsureUI() then
        return
    end
    local options = addon.options or KRT_Options or {}
    local nextValue = not options.minimapButton
    Options.SetOption("minimapButton", nextValue)
    SetMinimapShown(nextValue)
end

-- Hides the minimap button.
function module:HideMinimapButton()
    if not self:EnsureUI() then
        return
    end
    return Frames.SetShown(KRT_MINIMAP_GUI, false)
end
