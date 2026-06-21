-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Widgets.RaidGrid
-- events: listens SpecInspectUpdated

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Widgets = feature.Widgets
local UI = feature.UI
local UIWidgets = UI.Widgets
local Primitives = UI.Primitives
local Services = feature.Services
local Colors = feature.Colors
local L = feature.L
local Events = feature.Events
local Bus = feature.Bus

local _G = _G
local tinsert = table.insert
local type, tostring, tonumber = type, tostring, tonumber
local strmatch, strlen, strsub = string.match, string.len, string.sub
local ceil, floor, min, max = math.ceil, math.floor, math.min, math.max
local InternalEvents = Events and Events.Internal or nil

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Widgets/RaidGrid", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Bus",
            "Modules/Colors",
            "Services/SpecInspect",
            "Modules/UI/Facade",
            "Modules/UI/Visuals",
        },
    })
    registry.SetLoaded("Widgets/RaidGrid")
end

do
    if UIWidgets and UIWidgets.IsEnabled and not UIWidgets.IsEnabled("RaidGrid") then
        return
    end

    Widgets.RaidGrid = Widgets.RaidGrid or {}
    local module = Widgets.RaidGrid
    addon.Widgets.RaidGrid = module

    -- ----- Internal state ----- --
    local CFG = {
        maxCols = 5,
        buttonWidth = 150,
        buttonHeight = 28,
        gapX = 5,
        gapY = 4,
        padding = 22,
        headerHeight = 62,
        footerPadding = 18,
        maxNameLen = 15,
        buttonAlpha = 0.42,
        buttonHoverAlpha = 0.85,
        specIconSize = 16,
        specIconGap = 4,
    }

    local frame
    local activeConfig
    local entries = {}
    local buttons = {}
    local activeButtonCount = 0

    -- ----- Private helpers ----- --
    local function noop() end

    local function ensureRegion()
        return {
            Show = noop,
            Hide = noop,
            SetAllPoints = noop,
            SetBlendMode = noop,
            SetFontObject = noop,
            SetHeight = noop,
            SetJustifyH = noop,
            SetPoint = noop,
            SetText = noop,
            SetTextColor = noop,
            SetTexture = noop,
            SetVertexColor = noop,
            SetWidth = noop,
        }
    end

    local function safeCall(obj, methodName, ...)
        local fn = obj and obj[methodName]
        if type(fn) == "function" then
            return fn(obj, ...)
        end
        return nil
    end

    local function setSize(obj, width, height)
        if not obj then
            return
        end
        if obj.SetSize then
            obj:SetSize(width, height)
        else
            safeCall(obj, "SetWidth", width)
            safeCall(obj, "SetHeight", height)
        end
    end

    local setTextureColor = Primitives.SetTextureColor
        or function(texture, r, g, b, a)
            if texture and texture.SetTexture then
                texture:SetTexture(r, g, b, a)
            end
        end

    local function createTexture(parent, layer)
        if parent and parent.CreateTexture then
            return parent:CreateTexture(nil, layer)
        end
        return ensureRegion()
    end

    local function createFontString(parent, template)
        if parent and parent.CreateFontString then
            return parent:CreateFontString(nil, "OVERLAY", template)
        end
        return ensureRegion()
    end

    local function shortName(name)
        if not name then
            return ""
        end
        return strmatch(tostring(name), "^[^-]+") or tostring(name)
    end

    local function trimName(name)
        local value = shortName(name)
        if strlen(value) > CFG.maxNameLen then
            return strsub(value, 1, CFG.maxNameLen - 3) .. "..."
        end
        return value
    end

    local function getEntryName(entry)
        return entry and (entry.displayName or entry.name) or ""
    end

    local function getClassColor(entry)
        local className = entry and entry.class
        if className and Colors and Colors.GetClassColor then
            return Colors.GetClassColor(className)
        end
        if className and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[className] then
            local color = _G.RAID_CLASS_COLORS[className]
            return color.r or 1, color.g or 0.82, color.b or 0
        end
        return 1, 0.82, 0
    end

    local function getTooltipLine()
        if activeConfig and activeConfig.mode == "target" then
            return L.TipRaidGridClickTarget
        end
        if activeConfig and activeConfig.mode == "debug" then
            return L.TipRaidGridClickDebug
        end
        return L.TipRaidGridClickAward
    end

    local function updateButtonColor(button, hovered)
        if not button or not button.bg then
            return
        end
        if hovered then
            setTextureColor(button.bg, 0.05, 0.32, 0.65, CFG.buttonHoverAlpha)
        else
            setTextureColor(button.bg, 0, 0, 0, CFG.buttonAlpha)
        end
    end

    local function getTextWidth(textFrame, fallbackText)
        if textFrame and textFrame.GetStringWidth then
            return tonumber(textFrame:GetStringWidth()) or 0
        end
        return min(CFG.buttonWidth - 8, strlen(tostring(fallbackText or "")) * 8)
    end

    local function layoutButtonText(button, label, hasSpecIcon)
        if not button or not button.text then
            return
        end

        safeCall(button.text, "ClearAllPoints")
        if hasSpecIcon and button.specIcon then
            local textWidth = getTextWidth(button.text, label)
            local groupWidth = CFG.specIconSize + CFG.specIconGap + textWidth
            local iconLeft = floor((CFG.buttonWidth - groupWidth) / 2)
            if iconLeft < 4 then
                iconLeft = 4
            end

            safeCall(button.specIcon, "ClearAllPoints")
            safeCall(button.specIcon, "SetPoint", "LEFT", button, "LEFT", iconLeft, 0)
            safeCall(button.text, "SetPoint", "LEFT", button.specIcon, "RIGHT", CFG.specIconGap, 0)
            safeCall(button.text, "SetWidth", max(20, CFG.buttonWidth - iconLeft - CFG.specIconSize - CFG.specIconGap - 4))
            safeCall(button.text, "SetJustifyH", "LEFT")
            return
        end

        safeCall(button.text, "SetPoint", "CENTER", button, "CENTER", 0, 0)
        safeCall(button.text, "SetWidth", CFG.buttonWidth - 8)
        safeCall(button.text, "SetJustifyH", "CENTER")
    end

    local function selectEntry(entry)
        if not entry then
            return nil
        end

        local result
        if activeConfig and type(activeConfig.onSelect) == "function" then
            result = activeConfig.onSelect(entry, activeConfig)
        end
        if not (activeConfig and activeConfig.closeOnSelect == false) and result ~= false then
            module.Hide()
        end
        return result
    end

    local function createButton(index)
        local buttonName = "KRTRaidGridButton" .. tostring(index)
        local button = _G.CreateFrame("Button", buttonName, frame)
        setSize(button, CFG.buttonWidth, CFG.buttonHeight)
        safeCall(button, "RegisterForClicks", "LeftButtonUp")

        button.bg = createTexture(button, "BACKGROUND")
        safeCall(button.bg, "SetAllPoints", button)
        updateButtonColor(button, false)

        button.topLine = createTexture(button, "BORDER")
        safeCall(button.topLine, "SetHeight", 1)
        safeCall(button.topLine, "SetPoint", "TOPLEFT", button, "TOPLEFT", 0, 0)
        safeCall(button.topLine, "SetPoint", "TOPRIGHT", button, "TOPRIGHT", 0, 0)
        setTextureColor(button.topLine, 1, 1, 1, 0.08)

        button.bottomLine = createTexture(button, "BORDER")
        safeCall(button.bottomLine, "SetHeight", 1)
        safeCall(button.bottomLine, "SetPoint", "BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        safeCall(button.bottomLine, "SetPoint", "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        setTextureColor(button.bottomLine, 0, 0, 0, 0.90)

        button.highlight = createTexture(button, "HIGHLIGHT")
        safeCall(button.highlight, "SetAllPoints", button)
        safeCall(button.highlight, "SetTexture", "Interface\\QuestFrame\\UI-QuestTitleHighlight")
        safeCall(button.highlight, "SetBlendMode", "ADD")

        button.text = createFontString(button, "GameFontNormalLarge")
        safeCall(button.text, "SetPoint", "CENTER", button, "CENTER", 0, 0)
        safeCall(button.text, "SetWidth", CFG.buttonWidth - 8)
        safeCall(button.text, "SetJustifyH", "CENTER")

        button.specIcon = createTexture(button, "ARTWORK")
        safeCall(button.specIcon, "SetPoint", "LEFT", button, "LEFT", 12, 0)
        setSize(button.specIcon, CFG.specIconSize, CFG.specIconSize)
        safeCall(button.specIcon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
        safeCall(button.specIcon, "Hide")

        safeCall(button, "SetScript", "OnEnter", function(self)
            updateButtonColor(self, true)
            if _G.GameTooltip and _G.GameTooltip.SetOwner then
                _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if _G.GameTooltip.AddLine then
                    _G.GameTooltip:AddLine(self.fullName or "Unknown", 1, 1, 1)
                    _G.GameTooltip:AddLine(getTooltipLine(), 0.75, 0.75, 0.75)
                end
                if _G.GameTooltip.Show then
                    _G.GameTooltip:Show()
                end
            end
        end)
        safeCall(button, "SetScript", "OnLeave", function(self)
            updateButtonColor(self, false)
            if _G.GameTooltip and _G.GameTooltip.Hide then
                _G.GameTooltip:Hide()
            end
        end)
        safeCall(button, "SetScript", "OnClick", function(self)
            selectEntry(self.entry)
        end)

        buttons[index] = button
        return button
    end

    local function ensureFrame()
        if frame then
            return frame
        end

        frame = _G.CreateFrame("Frame", "KRTRaidGridFrame", _G.UIParent, "KRTDialogTemplate")
        frame.buttons = buttons
        safeCall(frame, "Hide")
        safeCall(frame, "SetFrameStrata", "FULLSCREEN_DIALOG")
        safeCall(frame, "SetToplevel", true)
        safeCall(frame, "SetClampedToScreen", true)
        safeCall(frame, "SetMovable", true)
        safeCall(frame, "EnableMouse", true)
        safeCall(frame, "RegisterForDrag", "LeftButton")
        safeCall(frame, "SetScript", "OnDragStart", function(self)
            if self.StartMoving then
                self:StartMoving()
            end
        end)
        safeCall(frame, "SetScript", "OnDragStop", function(self)
            if self.StopMovingOrSizing then
                self:StopMovingOrSizing()
            end
        end)

        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true,
                tileSize = 8,
                edgeSize = 8,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
        end

        frame.icon = createTexture(frame, "ARTWORK")
        setSize(frame.icon, 30, 30)
        safeCall(frame.icon, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 22, -18)

        frame.title = createFontString(frame, "GameFontNormalLarge")
        safeCall(frame.title, "SetPoint", "LEFT", frame.icon, "RIGHT", 8, 0)
        safeCall(frame.title, "SetJustifyH", "LEFT")

        frame.count = createFontString(frame, "GameFontNormal")
        safeCall(frame.count, "SetPoint", "LEFT", frame.title, "RIGHT", 8, 0)
        safeCall(frame.count, "SetTextColor", 1, 1, 1)
        safeCall(frame.count, "Hide")

        frame.divider = createTexture(frame, "ARTWORK")
        safeCall(frame.divider, "SetHeight", 1)
        safeCall(frame.divider, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 22, -CFG.headerHeight + 6)
        safeCall(frame.divider, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -22, -CFG.headerHeight + 6)
        setTextureColor(frame.divider, 1, 0.82, 0, 0.35)

        frame.empty = createFontString(frame, "GameFontHighlight")
        safeCall(frame.empty, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 24, -CFG.headerHeight)
        safeCall(frame.empty, "SetJustifyH", "LEFT")
        safeCall(frame.empty, "SetTextColor", 1, 0.2, 0.2)

        if _G.CreateFrame then
            local close = _G.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
            if close then
                safeCall(close, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -5, -5)
                safeCall(close, "SetScript", "OnClick", function()
                    module.Hide()
                end)
            end
        end

        if type(_G.UISpecialFrames) == "table" then
            tinsert(_G.UISpecialFrames, "KRTRaidGridFrame")
        end

        return frame
    end

    local function updateHeader(width)
        local title = activeConfig and activeConfig.title or L.StrRaidGridTitle
        local texture = activeConfig and activeConfig.texture or nil
        local count = activeConfig and tonumber(activeConfig.count) or nil

        if texture then
            safeCall(frame.icon, "SetTexture", texture)
            safeCall(frame.icon, "Show")
            safeCall(frame.title, "ClearAllPoints")
            safeCall(frame.title, "SetPoint", "LEFT", frame.icon, "RIGHT", 8, 0)
            safeCall(frame.title, "SetWidth", max(100, width - 120))
        else
            safeCall(frame.icon, "Hide")
            safeCall(frame.title, "ClearAllPoints")
            safeCall(frame.title, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 22, -22)
            safeCall(frame.title, "SetWidth", max(100, width - 70))
        end

        safeCall(frame.title, "SetText", title or L.StrRaidGridTitle)
        if count and count > 1 then
            safeCall(frame.count, "SetText", "x" .. tostring(count))
            safeCall(frame.count, "Show")
        else
            safeCall(frame.count, "SetText", "")
            safeCall(frame.count, "Hide")
        end
    end

    local function positionFrame(anchor)
        safeCall(frame, "ClearAllPoints")
        safeCall(frame, "SetPoint", "CENTER", _G.UIParent, "CENTER", 0, 0)
        if anchor and anchor.GetFrameLevel then
            safeCall(frame, "SetFrameLevel", (anchor:GetFrameLevel() or 1) + 50)
        else
            safeCall(frame, "SetFrameLevel", 100)
        end
        safeCall(frame, "Raise")
    end

    local function normalizeConfig(selfOrConfig, maybeConfig)
        if selfOrConfig == module then
            return maybeConfig
        end
        return selfOrConfig
    end

    -- ----- Public methods ----- --
    function module.ShowPicker(selfOrConfig, maybeConfig)
        local config = normalizeConfig(selfOrConfig, maybeConfig) or {}
        local source = type(config.entries) == "table" and config.entries or {}

        ensureFrame()
        activeConfig = config
        entries = {}
        for i = 1, #source do
            entries[i] = source[i]
        end
        module.Refresh()
        positionFrame(config.anchor)
        safeCall(frame, "Show")
        return true
    end

    function module.Refresh(selfOrEntries, maybeEntries)
        local overrideEntries = selfOrEntries
        if selfOrEntries == module then
            overrideEntries = maybeEntries
        end
        if type(overrideEntries) == "table" then
            entries = {}
            for i = 1, #overrideEntries do
                entries[i] = overrideEntries[i]
            end
        end

        ensureFrame()
        local count = #entries
        local cols = min(CFG.maxCols, max(1, count))
        local rows = max(1, ceil(count / cols))
        local width = (CFG.padding * 2) + (cols * CFG.buttonWidth) + (max(0, cols - 1) * CFG.gapX)
        local height = CFG.headerHeight + CFG.padding + (rows * CFG.buttonHeight) + (max(0, rows - 1) * CFG.gapY) + CFG.footerPadding

        setSize(frame, width, height)
        updateHeader(width)
        activeButtonCount = count

        if count <= 0 then
            safeCall(frame.empty, "SetText", (activeConfig and activeConfig.emptyText) or L.StrRaidGridEmpty)
            safeCall(frame.empty, "Show")
        else
            safeCall(frame.empty, "Hide")
        end

        for i = 1, #buttons do
            safeCall(buttons[i], "Hide")
        end

        for i = 1, count do
            local entry = entries[i]
            local button = buttons[i] or createButton(i)
            local col = (i - 1) % cols
            local row = ceil(i / cols) - 1
            local x = CFG.padding + (col * (CFG.buttonWidth + CFG.gapX))
            local y = -(CFG.headerHeight + (row * (CFG.buttonHeight + CFG.gapY)))
            local r, g, b = getClassColor(entry)
            local fullName = getEntryName(entry)
            local specIcon

            if Services and Services.SpecInspect and Services.SpecInspect.GetPlayerSpecSnapshot and fullName then
                local spec = Services.SpecInspect:GetPlayerSpecSnapshot(fullName)
                specIcon = spec and spec.icon or nil
            end

            safeCall(button, "ClearAllPoints")
            safeCall(button, "SetPoint", "TOPLEFT", frame, "TOPLEFT", x, y)
            button.entry = entry
            button.fullName = fullName
            local buttonLabel = trimName(button.fullName)
            safeCall(button.text, "SetText", buttonLabel)
            safeCall(button.text, "SetTextColor", r, g, b)
            if button.specIcon then
                if specIcon and specIcon ~= "" then
                    safeCall(button.specIcon, "SetTexture", specIcon)
                    safeCall(button.specIcon, "Show")
                    layoutButtonText(button, buttonLabel, true)
                else
                    safeCall(button.specIcon, "Hide")
                    layoutButtonText(button, buttonLabel, false)
                end
            end
            updateButtonColor(button, false)
            safeCall(button, "Show")
        end

        return true
    end

    function module.Hide()
        if frame then
            safeCall(frame, "Hide")
        end
    end

    function module.IsShown()
        return frame and frame.IsShown and frame:IsShown() or false
    end

    function module.GetButtonCount()
        return activeButtonCount
    end

    function module.GetMode()
        return activeConfig and activeConfig.mode or nil
    end

    function module.ClickButtonForTest(selfOrIndex, maybeIndex)
        local index = selfOrIndex == module and maybeIndex or selfOrIndex
        local entry = entries[tonumber(index) or 0]
        return selectEntry(entry)
    end

    function module.GetEntryNameForTest(selfOrIndex, maybeIndex)
        local index = selfOrIndex == module and maybeIndex or selfOrIndex
        return getEntryName(entries[tonumber(index) or 0])
    end

    local function requestSpecRefresh()
        if module.IsShown() then
            module.Refresh()
        end
    end

    if Bus and InternalEvents and InternalEvents.SpecInspectUpdated then
        Bus.RegisterCallback(InternalEvents.SpecInspectUpdated, requestSpecRefresh)
    end

    if UIWidgets and UIWidgets.Register then
        UIWidgets.Register("RaidGrid", module)
    end
end
