-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type = type
local tonumber = tonumber
local floor = math.floor
local _G = _G

addon.UIPrimitives = addon.UIPrimitives or {}
local UIPrimitives = addon.UIPrimitives

addon.UIRowVisuals = addon.UIRowVisuals or {}
local UIRowVisuals = addon.UIRowVisuals

-- ----- Internal state ----- --

-- ----- Private helpers ----- --
local function round(value)
    if value >= 0 then
        return floor(value + 0.5)
    end
    return -floor(-value + 0.5)
end

local function getEffectiveScale(region)
    if region and type(region.GetEffectiveScale) == "function" then
        return tonumber(region:GetEffectiveScale()) or 1
    end
    return 1
end

local function getPhysicalScreenHeight()
    local currentResolution = _G.GetCurrentResolution
    local screenResolutions = _G.GetScreenResolutions
    if type(currentResolution) == "function" and type(screenResolutions) == "function" then
        local selected = ({ screenResolutions() })[currentResolution()]
        local height = selected and selected:match("%d+.-(%d+)")
        height = tonumber(height)
        if height and height > 0 then
            return height
        end
    end

    local screenHeight = _G.GetScreenHeight
    if type(screenHeight) == "function" then
        local height = tonumber(screenHeight())
        if height and height > 0 then
            return height
        end
    end

    return 768
end

local function ensureRowTextures(row)
    if not row or row._krtSelTex then
        return
    end

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints(row)
    sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD")
    sel:SetVertexColor(0.20, 0.60, 1.00, 0.52)
    sel:Hide()
    row._krtSelTex = sel

    local focus = row:CreateTexture(nil, "ARTWORK")
    focus:SetAllPoints(row)
    focus:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    focus:SetBlendMode("ADD")
    focus:SetVertexColor(0.20, 0.60, 1.00, 0.72)
    focus:Hide()
    row._krtFocusTex = focus

    local pushed = row:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints(row)
    pushed:SetTexture(1, 1, 1, 0.08)
    row:SetPushedTexture(pushed)
end

local function isLoggerRow(row)
    return row and row._krtRowVisualStyle == "logger"
end

-- ----- Public methods ----- --
function UIPrimitives.EnableDisable(frame, cond)
    if not frame then
        return
    end
    if cond and frame:IsEnabled() == 0 then
        frame:Enable()
    elseif not cond and frame:IsEnabled() == 1 then
        frame:Disable()
    end
end

function UIPrimitives.Toggle(frame)
    if not frame then
        return
    end
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
    end
end

function UIPrimitives.HideFrame(frame, onHide)
    if frame and frame:IsShown() then
        if onHide then
            onHide()
        end
        frame:Hide()
    end
end

function UIPrimitives.ShowHide(frame, cond)
    if not frame then
        return
    end
    if cond and not frame:IsShown() then
        frame:Show()
    elseif not cond and frame:IsShown() then
        frame:Hide()
    end
end

function UIPrimitives.ToggleHighlight(frame, cond)
    if not frame then
        return
    end
    if cond then
        frame:LockHighlight()
    else
        frame:UnlockHighlight()
    end
end

function UIPrimitives.SetButtonCount(btn, baseText, n)
    if not btn then
        return
    end
    if not btn._krtBaseText then
        btn._krtBaseText = baseText or btn:GetText() or ""
    end
    local base = baseText or btn._krtBaseText or ""
    if n and n > 1 then
        btn:SetText(("%s (%d)"):format(base, n))
    else
        btn:SetText(base)
    end
end

function UIPrimitives.SetButtonGlow(button, enabled, r, g, b, style, options)
    local effects = addon.UIEffects
    if effects and effects.SetButtonGlow then
        effects.SetButtonGlow(button, enabled, r, g, b, style, options)
    end
end

function UIPrimitives.GetPixelToUIUnitFactor()
    return 768 / getPhysicalScreenHeight()
end

function UIPrimitives.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
    local size = tonumber(uiUnitSize) or 0
    local scale = tonumber(layoutScale) or 1
    if scale <= 0 then
        scale = 1
    end
    local minimum = tonumber(minPixels)
    if size == 0 and (not minimum or minimum == 0) then
        return 0
    end

    local uiUnitFactor = UIPrimitives.GetPixelToUIUnitFactor()
    local pixels = round((size * scale) / uiUnitFactor)
    if minimum then
        if size < 0 then
            if pixels > -minimum then
                pixels = -minimum
            end
        elseif pixels < minimum then
            pixels = minimum
        end
    end

    return pixels * uiUnitFactor / scale
end

function UIPrimitives.SetPixelWidth(region, width, minPixels)
    if region and type(region.SetWidth) == "function" then
        region:SetWidth(UIPrimitives.GetNearestPixelSize(width, getEffectiveScale(region), minPixels))
    end
end

function UIPrimitives.SetPixelHeight(region, height, minPixels)
    if region and type(region.SetHeight) == "function" then
        region:SetHeight(UIPrimitives.GetNearestPixelSize(height, getEffectiveScale(region), minPixels))
    end
end

function UIPrimitives.SetPixelSize(region, width, height, minWidthPixels, minHeightPixels)
    UIPrimitives.SetPixelWidth(region, width, minWidthPixels)
    UIPrimitives.SetPixelHeight(region, height, minHeightPixels)
end

function UIPrimitives.SetPixelPoint(region, point, relativeTo, relativePoint, offsetX, offsetY, minOffsetXPixels, minOffsetYPixels)
    if not region or type(region.SetPoint) ~= "function" then
        return
    end

    local scale = getEffectiveScale(region)
    region:SetPoint(
        point,
        relativeTo,
        relativePoint,
        UIPrimitives.GetNearestPixelSize(offsetX, scale, minOffsetXPixels),
        UIPrimitives.GetNearestPixelSize(offsetY, scale, minOffsetYPixels)
    )
end

function UIPrimitives.SetText(frame, str1, str2, cond)
    if not frame then
        return
    end
    if cond then
        frame:SetText(str1)
    else
        frame:SetText(str2)
    end
end

function UIPrimitives.GetNamedFramePart(frameName, suffix)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end
    if type(suffix) ~= "string" or suffix == "" then
        return nil
    end
    return _G[frameName .. suffix]
end

function UIPrimitives.EnableDisableNamedPart(frameName, suffix, cond)
    local frame = UIPrimitives.GetNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.EnableDisable(frame, cond)
    end
    return frame
end

function UIPrimitives.ShowHideNamedPart(frameName, suffix, cond)
    local frame = UIPrimitives.GetNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.ShowHide(frame, cond)
    end
    return frame
end

function UIPrimitives.SetTextNamedPart(frameName, suffix, str1, str2, cond)
    local frame = UIPrimitives.GetNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.SetText(frame, str1, str2, cond)
    end
    return frame
end

function UIPrimitives.UpdateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    if mode ~= lastMode then
        UIPrimitives.SetTextNamedPart(frameName, suffix, str1, str2, mode)
        return mode
    end
    return lastMode
end

function UIRowVisuals.EnsureRowVisuals(row)
    ensureRowTextures(row)
end

function UIRowVisuals.SetRowSelected(row, cond)
    ensureRowTextures(row)
    if not row or not row._krtSelTex then
        return
    end
    if cond then
        if isLoggerRow(row) then
            row._krtSelTex:SetVertexColor(0.08, 0.52, 0.10, 0.72)
        else
            row._krtSelTex:SetVertexColor(0.20, 0.60, 1.00, 0.52)
        end
        row._krtSelTex:Show()
    else
        row._krtSelTex:Hide()
    end
end

function UIRowVisuals.SetRowFocused(row, cond)
    ensureRowTextures(row)
    local texture = row and row._krtFocusTex
    if not texture then
        return
    end
    if cond then
        if isLoggerRow(row) then
            texture:SetVertexColor(0.20, 0.85, 0.18, 0.34)
        else
            texture:SetVertexColor(0.20, 0.60, 1.00, 0.72)
        end
        texture:Show()
    else
        texture:Hide()
    end
end
