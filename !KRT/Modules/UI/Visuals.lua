-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local type = type
local _G = _G

addon.UIPrimitives = addon.UIPrimitives or {}
local UIPrimitives = addon.UIPrimitives

addon.UIRowVisuals = addon.UIRowVisuals or {}
local UIRowVisuals = addon.UIRowVisuals

function UIPrimitives.enableDisable(frame, cond)
    if not frame then
        return
    end
    if cond and frame:IsEnabled() == 0 then
        frame:Enable()
    elseif not cond and frame:IsEnabled() == 1 then
        frame:Disable()
    end
end

function UIPrimitives.toggle(frame)
    if not frame then
        return
    end
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
    end
end

function UIPrimitives.hideFrame(frame, onHide)
    if frame and frame:IsShown() then
        if onHide then
            onHide()
        end
        frame:Hide()
    end
end

function UIPrimitives.showHide(frame, cond)
    if not frame then
        return
    end
    if cond and not frame:IsShown() then
        frame:Show()
    elseif not cond and frame:IsShown() then
        frame:Hide()
    end
end

function UIPrimitives.toggleHighlight(frame, cond)
    if not frame then
        return
    end
    if cond then
        frame:LockHighlight()
    else
        frame:UnlockHighlight()
    end
end

function UIPrimitives.setButtonCount(btn, baseText, n)
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

function UIPrimitives.setText(frame, str1, str2, cond)
    if not frame then
        return
    end
    if cond then
        frame:SetText(str1)
    else
        frame:SetText(str2)
    end
end

function UIPrimitives.getNamedFramePart(frameName, suffix)
    if type(frameName) ~= "string" or frameName == "" then
        return nil
    end
    if type(suffix) ~= "string" or suffix == "" then
        return nil
    end
    return _G[frameName .. suffix]
end

function UIPrimitives.enableDisableNamedPart(frameName, suffix, cond)
    local frame = UIPrimitives.getNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.enableDisable(frame, cond)
    end
    return frame
end

function UIPrimitives.showHideNamedPart(frameName, suffix, cond)
    local frame = UIPrimitives.getNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.showHide(frame, cond)
    end
    return frame
end

function UIPrimitives.setTextNamedPart(frameName, suffix, str1, str2, cond)
    local frame = UIPrimitives.getNamedFramePart(frameName, suffix)
    if frame then
        UIPrimitives.setText(frame, str1, str2, cond)
    end
    return frame
end

function UIPrimitives.updateModeTextNamedPart(frameName, suffix, str1, str2, mode, lastMode)
    if mode ~= lastMode then
        UIPrimitives.setTextNamedPart(frameName, suffix, str1, str2, mode)
        return mode
    end
    return lastMode
end

local function ensureRowVisuals(row)
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

function UIRowVisuals.ensureRowVisuals(row)
    ensureRowVisuals(row)
end

function UIRowVisuals.setRowSelected(row, cond)
    ensureRowVisuals(row)
    if not row or not row._krtSelTex then
        return
    end
    if cond then
        row._krtSelTex:Show()
    else
        row._krtSelTex:Hide()
    end
end

function UIRowVisuals.setRowFocused(row, cond)
    ensureRowVisuals(row)
    local texture = row and row._krtFocusTex
    if not texture then
        return
    end
    if cond then
        texture:Show()
    else
        texture:Hide()
    end
end
