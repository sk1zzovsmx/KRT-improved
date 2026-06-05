-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local floor = math.floor
local strmatch = string.match
local tonumber, type = tonumber, type

addon.UIPrimitives = addon.UIPrimitives or {}
local UIPrimitives = addon.UIPrimitives

addon.UIRowVisuals = addon.UIRowVisuals or {}
local UIRowVisuals = addon.UIRowVisuals

-- ----- Internal state ----- --

-- ----- Private helpers ----- --
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

local function getNamedFramePart(frameName, suffix)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end
    if type(suffix) ~= "string" or suffix == "" then
        return nil
    end
    return _G[frameName .. suffix]
end

local function setTextNamedPart(frameName, suffix, str1, str2, cond)
    local frame = getNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.SetText(frame, str1, str2, cond)
    end
    return frame
end

local function getScreenPixelScale(frame, scaleX, scaleY)
    local uiScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local resolvedScaleX = tonumber(scaleX) or 1
    local resolvedScaleY = tonumber(scaleY) or resolvedScaleX
    local resolutionIndex = GetCurrentResolution and GetCurrentResolution() or nil
    local resolution = resolutionIndex and GetScreenResolutions and select(resolutionIndex, GetScreenResolutions()) or nil
    local _, height = strmatch(resolution or "", "^(%d+)x(%d+)$")
    local physicalHeight = tonumber(height) or 768
    local baseScale = (physicalHeight / 768) / (tonumber(uiScale) or 1)
    return baseScale * resolvedScaleX, baseScale * resolvedScaleY
end

local function alignToPixel(value, pixelScale)
    local scale = tonumber(pixelScale) or 1
    if scale <= 0 then
        scale = 1
    end
    return floor((tonumber(value) or 0) * scale + 0.5) / scale
end

-- ----- Public methods ----- --
function UIPrimitives.SetPixelSize(frame, width, height, scaleX, scaleY)
    if not frame then
        return false
    end

    local pixelScaleX, pixelScaleY = getScreenPixelScale(frame, scaleX, scaleY)
    local alignedWidth = alignToPixel(width, pixelScaleX)
    local alignedHeight = alignToPixel(height, pixelScaleY)
    if frame.SetSize then
        frame:SetSize(alignedWidth, alignedHeight)
    else
        if frame.SetWidth then
            frame:SetWidth(alignedWidth)
        end
        if frame.SetHeight then
            frame:SetHeight(alignedHeight)
        end
    end
    return true
end

function UIPrimitives.SetPixelPoint(frame, point, relativeTo, relativePoint, x, y, scaleX, scaleY)
    if not (frame and frame.SetPoint) then
        return false
    end

    local pixelScaleX, pixelScaleY = getScreenPixelScale(frame, scaleX, scaleY)
    frame:SetPoint(point, relativeTo, relativePoint, alignToPixel(x, pixelScaleX), alignToPixel(y, pixelScaleY))
    return true
end

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

function UIPrimitives.EnableDisableNamedPart(frameName, suffix, cond)
    local frame = getNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.EnableDisable(frame, cond)
    end
    return frame
end

function UIPrimitives.ShowHideNamedPart(frameName, suffix, cond)
    local frame = getNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.ShowHide(frame, cond)
    end
    return frame
end

function UIPrimitives.UpdateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    if mode ~= lastMode then
        setTextNamedPart(frameName, suffix, str1, str2, mode)
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
            row._krtSelTex:SetVertexColor(0.08, 0.52, 0.10, 0.76)
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
            texture:SetVertexColor(0.95, 0.72, 0.20, 0.26)
        else
            texture:SetVertexColor(0.20, 0.60, 1.00, 0.72)
        end
        texture:Show()
    else
        texture:Hide()
    end
end

local registry = addon.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Modules/UI/Visuals", { deps = { "Init", "Modules/ModuleRegistry" } })
    registry.SetLoaded("Modules/UI/Visuals")
end
