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
local Services = feature.Services or addon.Services or {}
local Widgets = feature.Widgets or addon.Widgets or {}

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

local function callControllerMethod(name, methodName, ...)
    local controller = getController(name)
    local method = controller and controller[methodName]
    if type(method) ~= "function" then
        return nil
    end
    return method(controller, ...)
end

local function getLootCounterController()
    local widget = Widgets.LootCounter
    if type(widget) == "table" and type(widget.Toggle) == "function" then
        return widget
    end
    return nil
end

local function getRaidService()
    return Services.Raid
end

local function isWidgetAvailable(widgetId)
    if UIFacade:IsEnabled(widgetId) and UIFacade:IsRegistered(widgetId) then
        return true
    end
    if widgetId == "LootCounter" and getLootCounterController() then
        return true
    end
    return false
end

local function callWidgetMethod(widgetId, methodName, ...)
    if not (UIFacade:IsEnabled(widgetId) and UIFacade:IsRegistered(widgetId)) then
        return nil
    end
    return UIFacade:Call(widgetId, methodName, ...)
end

local function toggleLootCounterWidget()
    if not isWidgetAvailable("LootCounter") then
        return nil
    end

    if UIFacade:IsEnabled("LootCounter") and UIFacade:IsRegistered("LootCounter") then
        return UIFacade:Call("LootCounter", "Toggle")
    end

    local widget = getLootCounterController()
    local method = widget and widget.Toggle
    if type(method) ~= "function" then
        return nil
    end
    return method(widget)
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

local function buildMenu()
    local raid = getRaidService()
    local hasRaidGroup = raid and raid.IsPlayerInRaid and raid:IsPlayerInRaid() or false
    local hasLootAccess = addon:CanUseRaidCapability("loot")
    local hasRaidIconsAccess = addon:CanUseRaidCapability("raid_icons")
    local hasChangesBroadcastAccess = addon:CanUseRaidCapability("changes_broadcast")
    local disableLootActions = nil
    if not hasLootAccess then
        disableLootActions = 1
    end
    local disableRaidActions = nil
    if not hasRaidIconsAccess then
        disableRaidActions = 1
    end
    local disableLootRaidActions = 1
    if hasRaidGroup and hasLootAccess then
        disableLootRaidActions = nil
    end
    local disableChangesBroadcastActions = nil
    if not hasChangesBroadcastAccess then
        disableChangesBroadcastActions = 1
    end

    return {
        {
            text = MASTER_LOOTER,
            notCheckable = 1,
            disabled = disableLootActions,
            func = function()
                callControllerMethod("Master", "Toggle")
            end,
        },
        {
            text = L.StrLootCounter,
            notCheckable = 1,
            disabled = disableLootRaidActions,
            func = function()
                if not (raid and raid.IsPlayerInRaid and raid:IsPlayerInRaid()) then
                    return
                end
                toggleLootCounterWidget()
            end,
        },
        {
            text = L.StrLootLogger,
            notCheckable = 1,
            func = function()
                callControllerMethod("Logger", "Toggle")
            end,
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = L.StrClearIcons,
            notCheckable = 1,
            disabled = disableRaidActions,
            func = function()
                if raid and raid.ClearRaidIcons then
                    raid:ClearRaidIcons()
                end
            end,
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = RAID_WARNING,
            notCheckable = 1,
            func = function()
                callControllerMethod("Warnings", "Toggle")
            end,
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = L.StrMSChanges,
            notCheckable = 1,
            hasArrow = 1,
            menuList = {
                {
                    text = L.BtnOpen,
                    notCheckable = 1,
                    func = function()
                        callControllerMethod("Changes", "Toggle")
                    end,
                },
                {
                    text = L.BtnDemand,
                    notCheckable = 1,
                    disabled = disableChangesBroadcastActions,
                    func = function()
                        callControllerMethod("Changes", "Demand")
                    end,
                },
                {
                    text = CHAT_ANNOUNCE,
                    notCheckable = 1,
                    disabled = disableChangesBroadcastActions,
                    func = function()
                        callControllerMethod("Changes", "Announce")
                    end,
                },
            },
        },
        { text = " ", disabled = 1, notCheckable = 1 },
        {
            text = L.StrLFMSpam,
            notCheckable = 1,
            func = function()
                callControllerMethod("Spammer", "Toggle")
            end,
        },
    }
end

-- Initializes and opens the menu for the minimap button.
local function openMenu()
    addonMenu = addonMenu or CreateFrame("Frame", "KRTMenu", UIParent, "UIDropDownMenuTemplate")
    local menu = buildMenu()
    -- EasyMenu handles UIDropDownMenu initialization and opening.
    EasyMenu(menu, addonMenu, KRT_MINIMAP_GUI, 0, 0, "MENU")
end

local function isMenuOpen()
    return addonMenu and UIDROPDOWNMENU_OPEN_MENU == addonMenu and DropDownList1 and DropDownList1:IsShown()
end

local function toggleMenu()
    if isMenuOpen() then
        CloseDropDownMenus()
        return
    end
    openMenu()
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

local function setMinimapShown(show)
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
    setMinimapShown(options.minimapButton ~= false)
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
        if IsShiftKeyDown() or IsAltKeyDown() then
            return
        end
        if button == "RightButton" then
            callWidgetMethod("Config", "Toggle")
        elseif button == "LeftButton" then
            toggleMenu()
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetText(
            addon.WrapTextInColorCode("Kader", Colors.NormalizeHexColor(K_COLOR)) .. " " .. addon.WrapTextInColorCode("Raid Tools", Colors.NormalizeHexColor("aad4af37"))
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
    setMinimapShown(nextValue)
end

-- Hides the minimap button.
function module:HideMinimapButton()
    if not self:EnsureUI() then
        return
    end
    return Frames.SetShown(KRT_MINIMAP_GUI, false)
end
