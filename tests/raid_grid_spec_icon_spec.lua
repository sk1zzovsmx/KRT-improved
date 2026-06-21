local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function makeFrame(name)
    local frame = {
        _name = name,
        shown = false,
        points = {},
        regions = {},
    }

    function frame:GetName()
        return self._name
    end

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:SetWidth(width)
        self.width = width
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end

    function frame:SetAllPoints(relativeTo)
        self.allPoints = relativeTo
    end

    function frame:SetTexture(texture)
        self.texture = texture
    end

    function frame:SetTexCoord(left, right, top, bottom)
        self.texCoord = { left, right, top, bottom }
    end

    function frame:SetBlendMode(mode)
        self.blendMode = mode
    end

    function frame:SetText(text)
        self.text = text
    end

    function frame:GetText()
        return self.text
    end

    function frame:SetTextColor(r, g, b)
        self.textColor = { r, g, b }
    end

    function frame:SetJustifyH(value)
        self.justifyH = value
    end

    function frame:GetStringWidth()
        return string.len(tostring(self.text or "")) * 8
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:SetScript(scriptName, callback)
        self[scriptName] = callback
    end

    function frame:RegisterForClicks() end
    function frame:RegisterForDrag() end
    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end
    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end
    function frame:GetFrameLevel()
        return self.frameLevel or 1
    end
    function frame:SetToplevel(value)
        self.topLevel = value and true or false
    end
    function frame:SetClampedToScreen(value)
        self.clamped = value and true or false
    end
    function frame:SetMovable(value)
        self.movable = value and true or false
    end
    function frame:EnableMouse(value)
        self.mouseEnabled = value ~= false
    end
    function frame:SetBackdrop(backdrop)
        self.backdrop = backdrop
    end
    function frame:Raise()
        self.raised = true
    end

    function frame:CreateTexture(textureName, layer)
        local texture = makeFrame(textureName)
        texture.layer = layer
        self.regions[#self.regions + 1] = texture
        return texture
    end

    function frame:CreateFontString(fontName, layer, template)
        local font = makeFrame(fontName)
        font.layer = layer
        font.template = template
        self.regions[#self.regions + 1] = font
        return font
    end

    return frame
end

local callbacks = {}
local tooltipLines = {}
local snapshotIcon = "Interface\\Icons\\Spell_Holy_HolyBolt"
local specCalls = 0
local frames = {}
local fakeG

local function seedRaidGridFrame()
    local frame = makeFrame("KRTRaidGridFrame")
    local childNames = {
        "KRTRaidGridFrameIcon",
        "KRTRaidGridFrameTitle",
        "KRTRaidGridFrameCount",
        "KRTRaidGridFrameDivider",
        "KRTRaidGridFrameEmpty",
        "KRTRaidGridFrameCloseButton",
    }
    frames.KRTRaidGridFrame = frame
    fakeG.KRTRaidGridFrame = frame
    for _, name in ipairs(childNames) do
        local child = makeFrame(name)
        frames[name] = child
        fakeG[name] = child
    end
end

fakeG = {
    UIParent = makeFrame("UIParent"),
    UISpecialFrames = {},
    GameTooltip = {
        SetOwner = function(_, owner, anchor)
            fakeG.GameTooltip.owner = owner
            fakeG.GameTooltip.anchor = anchor
        end,
        AddLine = function(_, text, r, g, b)
            tooltipLines[#tooltipLines + 1] = { text = text, r = r, g = g, b = b }
        end,
        Show = function()
            fakeG.GameTooltip.shown = true
        end,
        Hide = function()
            fakeG.GameTooltip.hidden = true
        end,
    },
}

seedRaidGridFrame()

function fakeG.CreateFrame(_, name, parent, template)
    local frame = makeFrame(name)
    frame.parent = parent
    frame.template = template
    if name then
        frames[name] = frame
        fakeG[name] = frame
    end
    if name and string.find(name, "^KRTRaidGridButton") then
        local childSuffixes = { "Bg", "TopLine", "BottomLine", "Highlight", "Text", "SpecIcon" }
        for _, suffix in ipairs(childSuffixes) do
            local childName = name .. suffix
            local child = makeFrame(childName)
            frames[childName] = child
            fakeG[childName] = child
        end
    end
    return frame
end

local addon = {
    Widgets = {},
    Database = {},
}
local feature
feature = {
    Widgets = addon.Widgets,
    UI = {
        Widgets = {
            IsEnabled = function()
                return true
            end,
            Register = function(_, module)
                feature.registeredRaidGrid = module
            end,
        },
        Primitives = {
            SetTextureColor = function(texture, r, g, b, a)
                if texture and texture.SetTexture then
                    texture:SetTexture(r, g, b, a)
                end
            end,
        },
    },
    Services = {
        SpecInspect = {
            GetPlayerSpecSnapshot = function(_, name)
                specCalls = specCalls + 1
                if name == "Disonesta" and snapshotIcon then
                    return { icon = snapshotIcon }
                end
                return nil
            end,
        },
    },
    Colors = {
        GetClassColor = function()
            return 1, 0.82, 0
        end,
    },
    Events = {
        Internal = {
            SpecInspectUpdated = "SpecInspectUpdated",
        },
    },
    Bus = {
        RegisterCallback = function(eventName, callback)
            callbacks[eventName] = callback
        end,
    },
    L = {
        StrRaidGridTitle = "Raid Grid",
        StrRaidGridEmpty = "No targets.",
        TipRaidGridClickTarget = "Click to select this target.",
        TipRaidGridClickAward = "Click to award this loot.",
        TipRaidGridClickDebug = "Debug target.",
    },
    ModuleRegistry = {
        AddModule = function() end,
        SetLoaded = function() end,
    },
}

function addon.Database.GetFeatureShared()
    return feature
end

local chunk = assert(loadfile("!KRT/Widgets/RaidGrid.lua"))
setfenv(
    chunk,
    setmetatable({
        _G = fakeG,
        select = select,
        table = table,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        string = string,
        math = math,
    }, { __index = _G })
)
chunk("!KRT", addon)

local grid = assert(addon.Widgets.RaidGrid, "RaidGrid widget must load")
assert(feature.registeredRaidGrid == grid, "RaidGrid should register through UI.Widgets")

grid.ShowPicker({
    mode = "target",
    title = "Select Target: Hold",
    entries = {
        { name = "Disonesta", class = "PALADIN" },
    },
})

local button = assert(frames.KRTRaidGridButton1, "RaidGrid should create the first target button")
assertEquals(button.template, "KRTRaidGridButtonTemplate", "RaidGrid dynamic buttons must use XML template")
assertEquals(button.parent, frames.KRTRaidGridFrame, "RaidGrid dynamic buttons must attach to the grid frame")
assert(button.text == fakeG.KRTRaidGridButton1Text, "RaidGrid must resolve XML text child")
assert(button.specIcon == fakeG.KRTRaidGridButton1SpecIcon, "RaidGrid must resolve XML spec icon child")
assert(button.specIcon, "RaidGrid target buttons should own a spec icon texture")
assertEquals(button.specIcon.texture, snapshotIcon, "spec icon should use cached SpecInspect icon")
assertEquals(button.specIcon.shown, true, "spec icon should be visible when cached")
assertEquals(button.specIcon.points[1].x, 29, "spec icon and name should be centered as one visual group")
assertEquals(button.text.text, "Disonesta", "button text should keep the player name")
assertEquals(button.text.justifyH, "LEFT", "text should align next to the visible spec icon")
assert(specCalls > 0, "RaidGrid should query SpecInspect snapshots")

tooltipLines = {}
button.OnEnter(button)
assertEquals(#tooltipLines, 2, "RaidGrid tooltip should not add spec text")
assertEquals(tooltipLines[1].text, "Disonesta", "tooltip should keep the player name")
assertEquals(tooltipLines[2].text, "Click to select this target.", "tooltip should keep the existing action hint")

snapshotIcon = nil
assert(callbacks.SpecInspectUpdated, "RaidGrid should refresh when spec snapshots update")
callbacks.SpecInspectUpdated("SpecInspectUpdated")
assertEquals(button.specIcon.shown, false, "spec icon should hide when the snapshot is missing")
assertEquals(button.text.justifyH, "CENTER", "text should recenter when no spec icon is visible")

snapshotIcon = "Interface\\Icons\\Spell_Holy_SealOfWisdom"
callbacks.SpecInspectUpdated("SpecInspectUpdated")
assertEquals(button.specIcon.texture, snapshotIcon, "spec icon should refresh from updated cache")
assertEquals(button.specIcon.shown, true, "spec icon should show after cache refresh")

print("raid grid spec icon spec passed")
