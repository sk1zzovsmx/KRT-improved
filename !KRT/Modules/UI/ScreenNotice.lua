-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.UI.ScreenNotice
-- events: listens Internal.ScreenNotice; delegates fade timing to UI.Effects

local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local UI = feature.UI or {}
local ScreenNotice = UI.ScreenNotice or {}
UI.ScreenNotice = ScreenNotice

local Effects = UI.Effects
local Bus = feature.Bus
local Events = feature.Events

local CreateFrame = CreateFrame
local UIParent = UIParent
local max = math.max
local min = math.min
local gsub = string.gsub
local tonumber, tostring, type = tonumber, tostring, type

-- ----- Internal state ----- --
local FRAME_NAME = "KRTScreenNoticeFrame"
local FONT_PATH = "FONTS\\FRIZQT__.TTF"
local DEFAULT_DURATION_SECONDS = 1.25
local FADE_SECONDS = 0.35

local frame
local titleText
local detailText
local detailVisible = false

-- ----- Private helpers ----- --
local function colorizeTitle(message)
    return gsub(tostring(message), "Master Loot", "|cffff2020Master Loot|r")
end

local function ensureFrame()
    if frame then
        return frame
    end
    if type(CreateFrame) ~= "function" or not UIParent then
        return nil
    end

    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1000)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    frame:Hide()

    titleText = frame:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("CENTER", 0, 0)
    titleText:SetFont(FONT_PATH, 24, "OUTLINE")
    titleText:SetTextColor(1, 1, 1, 1)
    titleText:SetShadowColor(0, 0, 0, 1)
    titleText:SetShadowOffset(2, -2)

    detailText = frame:CreateFontString(nil, "OVERLAY")
    detailText:SetPoint("CENTER", 0, -22)
    detailText:SetFont(FONT_PATH, 16, "OUTLINE")
    detailText:SetTextColor(0.78, 0.78, 0.78, 1)
    detailText:SetShadowColor(0, 0, 0, 1)
    detailText:SetShadowOffset(1, -1)

    frame:SetWidth(1)
    frame:SetHeight(1)

    return frame
end

local function updateFrameSize()
    if not frame or not titleText then
        return
    end

    local width = titleText.GetWidth and titleText:GetWidth() or 1
    if detailText and detailVisible and detailText.GetWidth then
        width = max(width, detailText:GetWidth() or 1)
    end

    frame:SetWidth(max(width, 1))
    frame:SetHeight(detailVisible and 42 or 24)
end

local function hideNotice(noticeFrame)
    noticeFrame:Hide()
    noticeFrame:SetAlpha(1)
end

local function showNotice(_eventName, message, requestedDuration)
    if not message or message == "" then
        return false
    end

    local noticeFrame = ensureFrame()
    if not noticeFrame or not titleText then
        return false
    end
    if not (Effects and Effects.SetTimedFade) then
        return false
    end

    local duration = max(tonumber(requestedDuration) or DEFAULT_DURATION_SECONDS, 0.1)
    duration = min(duration, 5)

    titleText:SetText(colorizeTitle(message))
    if detailText then
        detailText:SetText("")
        detailText:Hide()
    end
    detailVisible = false
    updateFrameSize()
    noticeFrame:SetAlpha(1)
    noticeFrame:Show()
    Effects.SetTimedFade(noticeFrame, duration, FADE_SECONDS, hideNotice)
    return true
end

-- ----- Public methods ----- --
function ScreenNotice.Show(message, requestedDuration)
    return showNotice(nil, message, requestedDuration)
end

local InternalEvents = Events and Events.Internal
if Bus and Bus.RegisterCallback and InternalEvents and InternalEvents.ScreenNotice then
    Bus.RegisterCallback(InternalEvents.ScreenNotice, showNotice)
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Modules/UI/ScreenNotice", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Bus",
            "Modules/Events",
            "Modules/UI/Effects",
        },
    })
    registry.SetLoaded("Modules/UI/ScreenNotice")
end
