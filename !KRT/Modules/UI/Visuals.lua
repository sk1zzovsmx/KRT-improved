-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.UI.Primitives, addon.UI.Rows
-- events: none
-- ui ownership: Lua applies row/panel visual state and keeps XML-template fallbacks only.

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local floor = math.floor
local strmatch = string.match
local tostring, tonumber, type = tostring, tonumber, type

local UI = feature.UI or {}
local Colors = feature.Colors
local Effects = UI.Effects

local Primitives = UI.Primitives or {}
UI.Primitives = Primitives

local Rows = UI.Rows or {}
UI.Rows = Rows
Rows._fallbackStats = Rows._fallbackStats or {
    selectable = 0,
    loggerHeader = 0,
    loggerRow = 0,
    masterSpecIcon = 0,
}

-- ----- Internal state ----- --
local LOGGER_HEADER_TAB_INSET = 1
local loggerHeaderSuffixes = {
    "HeaderNum",
    "HeaderDate",
    "HeaderZone",
    "HeaderSize",
    "HeaderName",
    "HeaderTime",
    "HeaderMode",
    "HeaderJoin",
    "HeaderLeave",
    "HeaderIlvl",
    "HeaderSpec",
    "HeaderInspect",
    "HeaderItem",
    "HeaderSource",
    "HeaderWinner",
    "HeaderType",
    "HeaderRoll",
}

-- ----- Private helpers ----- --
local function setTextureColor(texture, r, g, b, a)
    if texture and texture.SetTexture then
        texture:SetTexture(r, g, b, a)
    end
end

local function ensureRowTextures(row)
    if not row or row._krtVisualsResolved then
        return
    end

    local rowName = row.GetName and row:GetName() or nil

    row._krtSelTex = row._krtSelTex or (rowName and _G[rowName .. "SelectedTexture"])
    row._krtFocusTex = row._krtFocusTex or (rowName and _G[rowName .. "FocusTexture"])

    local pushed = rowName and _G[rowName .. "PushedTexture"]
    if pushed and row.SetPushedTexture then
        row:SetPushedTexture(pushed)
    end

    if row._krtSelTex and row._krtSelTex.Hide then
        row._krtSelTex:Hide()
    end
    if row._krtFocusTex and row._krtFocusTex.Hide then
        row._krtFocusTex:Hide()
    end

    if not row._krtSelTex and row.CreateTexture then
        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints(row)
        sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        sel:SetBlendMode("ADD")
        sel:SetVertexColor(0.20, 0.60, 1.00, 0.52)
        sel:Hide()
        row._krtSelTex = sel
        Rows._fallbackStats.selectable = Rows._fallbackStats.selectable + 1
    end

    if not row._krtFocusTex and row.CreateTexture then
        local focus = row:CreateTexture(nil, "ARTWORK")
        focus:SetAllPoints(row)
        focus:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        focus:SetBlendMode("ADD")
        focus:SetVertexColor(0.20, 0.60, 1.00, 0.72)
        focus:Hide()
        row._krtFocusTex = focus
        Rows._fallbackStats.selectable = Rows._fallbackStats.selectable + 1
    end

    if not pushed and row.CreateTexture and row.SetPushedTexture then
        pushed = row:CreateTexture(nil, "ARTWORK")
        pushed:SetAllPoints(row)
        pushed:SetTexture(1, 1, 1, 0.08)
        row:SetPushedTexture(pushed)
    end
    if row._krtSelTex and row._krtSelTex.SetDrawLayer then
        row._krtSelTex:SetDrawLayer("BORDER")
    end
    if row._krtFocusTex and row._krtFocusTex.SetDrawLayer then
        row._krtFocusTex:SetDrawLayer("BORDER")
    end

    row._krtVisualsResolved = true
end

local function isLoggerRow(row)
    return row and row._krtRowVisualStyle == "logger"
end

local function ensureLoggerHeaderTab(header)
    if not header or header._krtHeaderTab then
        return
    end

    local headerName = header.GetName and header:GetName() or nil
    local fill = headerName and _G[headerName .. "Fill"] or nil
    if not fill then
        fill = header:CreateTexture(nil, "BACKGROUND")
        fill:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
        fill:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
        Rows._fallbackStats.loggerHeader = Rows._fallbackStats.loggerHeader + 1
    end
    header._krtHeaderFill = fill

    local top = headerName and _G[headerName .. "Top"] or nil
    if not top then
        top = header:CreateTexture(nil, "BORDER")
        top:SetHeight(1)
        top:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
        top:SetPoint("TOPRIGHT", header, "TOPRIGHT", -LOGGER_HEADER_TAB_INSET, -1)
        Rows._fallbackStats.loggerHeader = Rows._fallbackStats.loggerHeader + 1
    end
    header._krtHeaderTop = top

    local bottom = headerName and _G[headerName .. "Bottom"] or nil
    if not bottom then
        bottom = header:CreateTexture(nil, "BORDER")
        bottom:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", LOGGER_HEADER_TAB_INSET, 1)
        bottom:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
        Rows._fallbackStats.loggerHeader = Rows._fallbackStats.loggerHeader + 1
    end
    header._krtHeaderBottom = bottom

    local left = headerName and _G[headerName .. "Left"] or nil
    if not left then
        left = header:CreateTexture(nil, "BORDER")
        left:SetWidth(1)
        left:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
        left:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", LOGGER_HEADER_TAB_INSET, 1)
        Rows._fallbackStats.loggerHeader = Rows._fallbackStats.loggerHeader + 1
    end
    header._krtHeaderLeft = left

    local right = headerName and _G[headerName .. "Right"] or nil
    if not right then
        right = header:CreateTexture(nil, "BORDER")
        right:SetWidth(1)
        right:SetPoint("TOPRIGHT", header, "TOPRIGHT", -LOGGER_HEADER_TAB_INSET, -1)
        right:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
        Rows._fallbackStats.loggerHeader = Rows._fallbackStats.loggerHeader + 1
    end
    header._krtHeaderRight = right

    if fill and fill.SetDrawLayer then
        fill:SetDrawLayer("BACKGROUND")
    end
    if top and top.SetDrawLayer then
        top:SetDrawLayer("BORDER")
    end
    if bottom and bottom.SetDrawLayer then
        bottom:SetDrawLayer("BORDER")
    end
    if left and left.SetDrawLayer then
        left:SetDrawLayer("BORDER")
    end
    if right and right.SetDrawLayer then
        right:SetDrawLayer("BORDER")
    end

    header._krtHeaderTab = true
end

local function styleLoggerHeader(header)
    if not header then
        return
    end

    ensureLoggerHeaderTab(header)

    local text = header.GetFontString and header:GetFontString() or nil
    if text and text.SetTextColor then
        text:SetTextColor(1.00, 0.86, 0.20)
    end
    if text and text.SetJustifyH then
        text:SetJustifyH("LEFT")
    end

    local bg = header.GetName and _G[header:GetName() .. "Bg"] or nil
    if bg and bg.SetTexture then
        bg:SetTexture(0.02, 0.02, 0.02, 0.00)
    end

    setTextureColor(header._krtHeaderFill, 0.015, 0.014, 0.012, 0.88)
    setTextureColor(header._krtHeaderTop, 0.72, 0.62, 0.38, 0.92)
    setTextureColor(header._krtHeaderBottom, 0.25, 0.22, 0.16, 0.95)
    setTextureColor(header._krtHeaderLeft, 0.38, 0.34, 0.24, 0.72)
    setTextureColor(header._krtHeaderRight, 0.38, 0.34, 0.24, 0.72)
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
        Primitives.SetText(frame, str1, str2, cond)
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

local function getMasterRollRowRefs(row)
    if not row then
        return nil
    end
    if row._p then
        return row._p
    end
    local Frames = UI.Frames
    if Frames and Frames.GetNamedParts then
        return Frames.GetNamedParts(row, {
            name = "Name",
            roll = "Roll",
            counter = "Counter",
            info = "Info",
            star = "Star",
            specIcon = "SpecIcon",
        })
    end
    return nil
end

local function clearPoints(frame)
    if frame and frame.ClearAllPoints then
        frame:ClearAllPoints()
    end
end

local function setPoint(frame, point, relativeTo, relativePoint, x, y)
    if frame and frame.SetPoint then
        frame:SetPoint(point, relativeTo, relativePoint, x, y)
    end
end

local function setSinglePoint(frame, point, relativeTo, relativePoint, x, y)
    clearPoints(frame)
    setPoint(frame, point, relativeTo, relativePoint, x, y)
end

local function setFrameShown(frame, cond)
    if not frame then
        return
    end
    if cond then
        if frame.Show then
            frame:Show()
        end
    elseif frame.Hide then
        frame:Hide()
    end
end

local function setMasterRollNamePoints(nameStr, row, infoStr, leftOffset)
    clearPoints(nameStr)
    setPoint(nameStr, "LEFT", row, "LEFT", leftOffset, 0)
    if infoStr then
        setPoint(nameStr, "RIGHT", infoStr, "LEFT", -3, 0)
    end
end

-- ----- Public methods ----- --
function Primitives.SetPixelSize(frame, width, height, scaleX, scaleY)
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

function Primitives.SetPixelPoint(frame, point, relativeTo, relativePoint, x, y, scaleX, scaleY)
    if not (frame and frame.SetPoint) then
        return false
    end

    local pixelScaleX, pixelScaleY = getScreenPixelScale(frame, scaleX, scaleY)
    frame:SetPoint(point, relativeTo, relativePoint, alignToPixel(x, pixelScaleX), alignToPixel(y, pixelScaleY))
    return true
end

function Primitives.SetEnabled(frame, cond)
    if not frame then
        return
    end
    if cond and frame:IsEnabled() == 0 then
        frame:Enable()
    elseif not cond and frame:IsEnabled() == 1 then
        frame:Disable()
    end
end

function Primitives.Toggle(frame)
    if not frame then
        return
    end
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
    end
end

function Primitives.SetShown(frame, cond)
    if not frame then
        return
    end
    if cond and not frame:IsShown() then
        frame:Show()
    elseif not cond and frame:IsShown() then
        frame:Hide()
    end
end

function Primitives.SetHighlighted(frame, cond)
    if not frame then
        return
    end
    if cond then
        frame:LockHighlight()
    else
        frame:UnlockHighlight()
    end
end

function Primitives.SetButtonCount(btn, baseText, n)
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

function Primitives.SetButtonGlow(button, enabled, r, g, b, style, options)
    if Effects and Effects.SetButtonGlow then
        Effects.SetButtonGlow(button, enabled, r, g, b, style, options)
    end
end

function Primitives.SetTextureColor(texture, r, g, b, a)
    setTextureColor(texture, r, g, b, a)
end

function Primitives.SetTextureColorRgba(texture, rgba)
    if texture and rgba then
        setTextureColor(texture, rgba[1], rgba[2], rgba[3], rgba[4])
    end
end

function Primitives.SetText(frame, str1, str2, cond)
    if not frame then
        return
    end
    if cond then
        frame:SetText(str1)
    else
        frame:SetText(str2)
    end
end

function Primitives.SetNamedPartEnabled(frameName, suffix, cond)
    local frame = getNamedFramePart(frameName, suffix)
    if frame then
        Primitives.SetEnabled(frame, cond)
    end
    return frame
end

function Primitives.SetNamedPartShown(frameName, suffix, cond)
    local frame = getNamedFramePart(frameName, suffix)
    if frame then
        Primitives.SetShown(frame, cond)
    end
    return frame
end

function Primitives.UpdateNamedPartModeText(frameName, suffix, str1, str2, mode, lastMode)
    if mode ~= lastMode then
        setTextNamedPart(frameName, suffix, str1, str2, mode)
        return mode
    end
    return lastMode
end

function Rows.EnsureVisuals(row)
    ensureRowTextures(row)
end

function Rows.SetSelected(row, cond)
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

function Rows.SetFocused(row, cond)
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

function Rows.StyleLoggerRow(row)
    if not row then
        return
    end

    row._krtRowVisualStyle = "logger"
    if not row._krtLoggerBg then
        local rowName = row.GetName and row:GetName() or nil
        local bg = rowName and _G[rowName .. "LoggerBg"] or nil
        if not bg then
            bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            Rows._fallbackStats.loggerRow = Rows._fallbackStats.loggerRow + 1
        end
        row._krtLoggerBg = bg
    end
    if not row._krtLoggerLine then
        local rowName = row.GetName and row:GetName() or nil
        local line = rowName and _G[rowName .. "LoggerBottomLine"] or nil
        if not line then
            line = row:CreateTexture(nil, "BORDER")
            line:SetHeight(1)
            line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
            line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
            Rows._fallbackStats.loggerRow = Rows._fallbackStats.loggerRow + 1
        end
        row._krtLoggerLine = line
    end
    if row._krtLoggerBg and row._krtLoggerBg.SetDrawLayer then
        row._krtLoggerBg:SetDrawLayer("BACKGROUND")
    end
    if row._krtLoggerLine and row._krtLoggerLine.SetDrawLayer then
        row._krtLoggerLine:SetDrawLayer("BORDER")
    end

    if row._krtLoggerLine then
        row._krtLoggerLine:SetTexture(0.32, 0.30, 0.25, 0.42)
    end
end

function Rows.GetFallbackStats()
    return Rows._fallbackStats
end

function Rows.SetLoggerRowIndex(row, index)
    if not row then
        return
    end

    Rows.StyleLoggerRow(row)
    row._krtLoggerRowIndex = index
    if row._krtLoggerBg then
        if (tonumber(index) or 0) % 2 == 0 then
            row._krtLoggerBg:SetTexture(0.07, 0.07, 0.07, 0.74)
        else
            row._krtLoggerBg:SetTexture(0.025, 0.025, 0.025, 0.76)
        end
    end
end

function Rows.StyleLoggerPanel(frameName)
    local frame = frameName and _G[frameName] or nil
    if not frame then
        return
    end

    if frame.SetBackdropColor then
        frame:SetBackdropColor(0.01, 0.01, 0.01, 0.88)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(0.56, 0.52, 0.45, 0.95)
    end

    local title = _G[frameName .. "Title"]
    if title then
        title:SetTextColor(1.00, 0.82, 0.00)
        title:SetJustifyH("LEFT")
    end

    for i = 1, #loggerHeaderSuffixes do
        styleLoggerHeader(_G[frameName .. loggerHeaderSuffixes[i]])
    end
end

function Rows.ApplyLoggerSkin(panelNames)
    if type(panelNames) ~= "table" then
        return
    end
    for i = 1, #panelNames do
        Rows.StyleLoggerPanel(panelNames[i])
    end
end

function Rows.DrawMasterRollRow(row, data, onClick)
    if not row or not data then
        return
    end

    if onClick and not row.krtHasOnClick then
        local Frames = UI.Frames
        if Frames and Frames.SetScriptSafely then
            Frames.SetScriptSafely(row, "OnClick", onClick)
        elseif row.SetScript then
            row:SetScript("OnClick", onClick)
        end
        row.krtHasOnClick = true
    end

    row.playerName = data.name
    if row.EnableMouse then
        row:EnableMouse(data.canClick == true)
    end

    local ui = getMasterRollRowRefs(row)
    local nameStr = ui and (ui.name or ui.Name) or nil
    local rollStr = ui and (ui.roll or ui.Roll) or nil
    local counterStr = ui and (ui.counter or ui.Counter) or nil
    local infoStr = ui and (ui.info or ui.Info) or nil
    local star = ui and (ui.star or ui.Star) or nil
    local hasSpecIcon = data.specIcon ~= nil and data.specIcon ~= ""
    local hasStar = data.showStar == true

    if nameStr then
        local class = data.class or "UNKNOWN"
        if data.isReserved then
            nameStr:SetVertexColor(0.4, 0.6, 1.0)
        else
            local r, g, b = Colors.GetClassColor(class)
            nameStr:SetVertexColor(r, g, b)
        end
        nameStr:SetText(data.displayName or data.name or "")
        nameStr:Show()
    end

    local specIcon = ui and (ui.specIcon or ui.SpecIcon) or row._krtSpecIcon
    if hasSpecIcon and not specIcon and row.CreateTexture then
        specIcon = row:CreateTexture(nil, "ARTWORK")
        row._krtSpecIcon = specIcon
        Rows._fallbackStats.masterSpecIcon = Rows._fallbackStats.masterSpecIcon + 1
    end
    if specIcon then
        if hasSpecIcon then
            if specIcon.SetTexture then
                specIcon:SetTexture(data.specIcon)
            end
            if specIcon.SetTexCoord then
                specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            if specIcon.SetSize then
                specIcon:SetSize(12, 12)
            else
                if specIcon.SetWidth then
                    specIcon:SetWidth(12)
                end
                if specIcon.SetHeight then
                    specIcon:SetHeight(12)
                end
            end
            if hasStar then
                setSinglePoint(specIcon, "LEFT", row, "LEFT", 16, 0)
            else
                setSinglePoint(specIcon, "LEFT", row, "LEFT", 2, 0)
            end
            setFrameShown(specIcon, true)
        else
            setFrameShown(specIcon, false)
        end
    end

    if rollStr then
        rollStr:SetText(tostring(data.roll or ""))
        rollStr:Show()
    end
    if counterStr then
        counterStr:SetText(data.counterText or "")
        counterStr:Show()
    end
    if infoStr then
        infoStr:SetText(data.infoText or "")
        infoStr:Show()
    end

    if nameStr then
        local nameLeft = 18
        if hasSpecIcon and hasStar then
            nameLeft = 30
        end
        setMasterRollNamePoints(nameStr, row, infoStr, nameLeft)
    end

    if star then
        setSinglePoint(star, "LEFT", row, "LEFT", 2, 0)
        setFrameShown(star, hasStar)
    end
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Modules/UI/Visuals", { deps = { "Init", "Modules/ModuleRegistry", "Modules/Colors", "Modules/UI/Effects" } })
    registry.SetLoaded("Modules/UI/Visuals")
end
