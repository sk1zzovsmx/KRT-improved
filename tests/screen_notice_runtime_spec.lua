local addon = {
    Events = {},
    UI = {},
    Database = {},
}

local frames = {}

local function makeFrame(name)
    local frame = {
        _name = name,
        _shown = true,
    }

    function frame:SetFrameStrata(value)
        self._strata = value
    end

    function frame:SetFrameLevel(value)
        self._frameLevel = value
    end

    function frame:SetWidth(value)
        self._width = value
    end

    function frame:SetHeight(value)
        self._height = value
    end

    function frame:SetPoint(...)
        self._point = { ... }
    end

    function frame:Hide()
        self._shown = false
    end

    function frame:Show()
        self._shown = true
    end

    function frame:IsShown()
        return self._shown == true
    end

    function frame:SetAlpha(value)
        self._alpha = value
    end

    function frame:SetScript(scriptName, callback)
        self[scriptName] = callback
    end

    function frame:CreateFontString()
        local fontString = makeFrame()
        self._fontStrings = self._fontStrings or {}
        self._fontStrings[#self._fontStrings + 1] = fontString
        return fontString
    end

    function frame:SetJustifyH(value)
        self._justifyH = value
    end

    function frame:SetJustifyV(value)
        self._justifyV = value
    end

    function frame:SetFont(...)
        self._font = { ... }
    end

    function frame:SetTextColor(...)
        self._textColor = { ... }
    end

    function frame:SetShadowColor(...)
        self._shadowColor = { ... }
    end

    function frame:SetShadowOffset(...)
        self._shadowOffset = { ... }
    end

    function frame:SetText(value)
        self._text = value
    end

    return frame
end

function addon.Database.GetFeatureShared()
    return {
        Bus = addon.Bus,
        Database = addon.Database,
        Events = addon.Events,
        ModuleRegistry = addon.ModuleRegistry,
        UI = addon.UI,
        L = {
            StrCbErrUsage = "bad callback usage",
        },
        Diag = {
            E = {
                LogUtilsCallbackExec = "%s %s %s",
            },
        },
    }
end

function addon.Database.EnsureBootstrapEvents()
    addon.Events.Internal = addon.Events.Internal or {}
    addon.Events.Wow = addon.Events.Wow or {}
end

addon["error"] = function(_, message)
    error(message)
end

addon.ModuleRegistry = {
    AddModule = function() end,
    SetLoaded = function() end,
}

_G = _G or {}
_G.UIParent = makeFrame("UIParent")
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateFrame = function(_, name)
    local frame = makeFrame(name)
    if name then
        frames[name] = frame
    end
    return frame
end

local originalSelect = select
select = function(index, ...)
    if index == 2 then
        return addon
    end
    return originalSelect(index, ...)
end

dofile("!KRT/Modules/Events.lua")
dofile("!KRT/Modules/Bus.lua")
dofile("!KRT/Modules/UI/Effects.lua")
dofile("!KRT/Modules/UI/ScreenNotice.lua")

addon.Bus.TriggerEvent(addon.Events.Internal.ScreenNotice, "Boss targeted, auto switch to Master Loot.", 1.25)

local frame = frames.KRTScreenNoticeFrame
assert(frame, "screen notice frame must be created")
assert(frame._shown == true, "screen notice frame must be shown")
assert(frame._alpha == 1, "screen notice frame must start fully visible")
assert(frame._strata == "TOOLTIP", "screen notice frame must render above raid UI")
assert(frame._frameLevel == 1000, "screen notice frame must use a high frame level")
assert(frame._point and frame._point[5] == 140, "screen notice frame must use RollFor-style vertical placement")
assert(frame._fontStrings and frame._fontStrings[1]._text == "Boss targeted, auto switch to |cffff2020Master Loot|r.", "screen notice text must be applied")
assert(frame._fontStrings[1]._font[1] == "FONTS\\FRIZQT__.TTF", "screen notice title must use RollFor-style font path")
assert(frame._fontStrings[1]._font[2] == 24, "screen notice title must use RollFor-style title size")
assert(type(frame.OnUpdate) == "function", "screen notice must register timed fade update")

frame:OnUpdate(1.25)
assert(frame._shown == true, "screen notice frame must stay shown for the configured hold duration")
assert(frame._alpha == 1, "screen notice frame must remain fully visible through the hold duration")

frame:OnUpdate(0.175)
assert(frame._shown == true, "screen notice frame must stay shown while fading out")
assert(frame._alpha and frame._alpha > 0 and frame._alpha < 1, "screen notice frame must fade after the hold duration")

frame:OnUpdate(0.175)
assert(frame._shown == false, "screen notice frame must hide after its duration")

select = originalSelect

print("screen notice runtime contract passed")
