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

local UI = addon.UI or {}
if type(UI.Call) ~= "function" then
    UI.Call = function()
        return nil
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

-- ----- Internal state ----- --
local addonMenu
local dragMode
local uiBound = false

-- Cached math functions
local sqrt = math.sqrt
local cos, sin = math.cos, math.sin
local rad, atan2, deg = math.rad, math.atan2, math.deg

-- ----- Private helpers ----- --
local function AcquireRefs(frame)
    return {
        button = frame,
    }
end

-- Menu definition for EasyMenu (built once).
local minimapMenu = {
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
    { text = L.StrLootCounter, notCheckable = 1, func = function() UI:Call("LootCounter", "Toggle") end },
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
            local moduleRef = getController("Changes")
            if moduleRef and moduleRef.Toggle then
                moduleRef:Toggle()
            end
        end
    },
    {
        text = L.BtnDemand,
        notCheckable = 1,
        func = function()
            local moduleRef = getController("Changes")
            if moduleRef and moduleRef.Demand then
                moduleRef:Demand()
            end
        end
    },
    {
        text = CHAT_ANNOUNCE,
        notCheckable = 1,
        func = function()
            local moduleRef = getController("Changes")
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
    frame:SetPoint("CENTER", cos(r) * 80, sin(r) * 80)
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
        if IsAltKeyDown() then
            dragMode = "free"
            self:SetScript("OnUpdate", moveButton)
        elseif IsShiftKeyDown() then
            dragMode = nil
            self:SetScript("OnUpdate", moveButton)
        end
    end)
    frame:SetScript("OnMouseUp", function(self)
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
    frame:SetScript("OnClick", function(self, button, down)
        -- Ignore clicks if Shift or Alt keys are held:
        if IsShiftKeyDown() or IsAltKeyDown() then return end
        if button == "RightButton" then
            UI:Call("Config", "Toggle")
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
    if uiBound and self.frame and self.refs then
        return self.frame, self.refs
    end

    local frame = Frames.Get("KRT_MINIMAP_GUI") or KRT_MINIMAP_GUI
    if not frame then
        return nil
    end

    local refs = AcquireRefs(frame)
    self.refs = refs

    self:OnLoad(frame)

    uiBound = true
    return frame, refs
end

function module:EnsureUI()
    if uiBound and self.frame and self.refs then
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
