local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function makeRegion()
    local frame = {
        shown = false,
        points = {},
    }

    function frame:SetText(text)
        self.text = text
    end

    function frame:GetText()
        return self.text
    end

    function frame:SetVertexColor(r, g, b, a)
        self.vertexColor = { r, g, b, a }
    end

    function frame:SetTexture(texture)
        self.texture = texture
    end

    function frame:GetTexture()
        return self.texture
    end

    function frame:SetTexCoord(left, right, top, bottom)
        self.texCoord = { left, right, top, bottom }
    end

    function frame:SetSize(width, height)
        self.width = width
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

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    return frame
end

local function makeRow(name)
    local row = {
        name = name,
        createdTextures = {},
    }

    function row:GetName()
        return self.name
    end

    function row:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end

    function row:CreateTexture(textureName, layer)
        error("CreateTexture is not allowed in this batch")
    end

    return row
end

local function loadRowsWithParts(parts)
    local feature = {
        UI = {
            Frames = {},
        },
        Colors = {
            GetClassColor = function()
                return 1, 1, 1
            end,
        },
    }
    local addon = {
        Database = {
            GetFeatureShared = function()
                return feature
            end,
        },
    }

    function feature.UI.Frames.GetNamedParts()
        return parts
    end

    local chunk = assert(loadfile("!KRT/Modules/UI/Visuals.lua"))
    chunk("!KRT", addon)
    return feature.UI.Rows
end

local row = makeRow("KRTTestMasterRollRow")
local parts = {
    name = makeRegion(),
    roll = makeRegion(),
    counter = makeRegion(),
    info = makeRegion(),
    star = makeRegion(),
    specIcon = makeRegion(),
}
local Rows = loadRowsWithParts(parts)

Rows.DrawMasterRollRow(row, {
    name = "Disonesta",
    displayName = "Disonesta",
    class = "PALADIN",
    roll = 46,
    counterText = "1",
    infoText = "MS",
    canClick = true,
    showStar = true,
    specIcon = "Interface\\Icons\\Spell_Holy_HolyBolt",
})

assertEquals(parts.name:GetText(), "Disonesta", "name text should still render")
assertEquals(parts.roll:GetText(), "46", "roll text should still render")
assertEquals(parts.counter:GetText(), "1", "counter text should still render")
assertEquals(parts.info:GetText(), "MS", "info text should still render")
assertEquals(row.mouseEnabled, true, "row click state should still render")
assertEquals(parts.specIcon:GetTexture(), "Interface\\Icons\\Spell_Holy_HolyBolt", "spec texture should be assigned")
assertEquals(parts.specIcon.shown, true, "spec icon should be visible")
assertEquals(parts.specIcon.width, 12, "spec icon width should be stable")
assertEquals(parts.specIcon.height, 12, "spec icon height should be stable")
assertEquals(#parts.specIcon.points, 1, "spec icon should not accumulate anchors")
assertEquals(parts.specIcon.points[1].x, 16, "spec icon should sit between star and name")
assertEquals(#parts.star.points, 1, "star should not accumulate anchors")
assertEquals(parts.star.points[1].x, 2, "star should stay at the left edge before spec icon")
assertEquals(parts.star.shown, true, "star should remain visible")
assertEquals(parts.name.points[1].x, 30, "name should shift after spec icon and star")

Rows.DrawMasterRollRow(row, {
    name = "Disonesta",
    displayName = "Disonesta",
    class = "PALADIN",
    roll = 47,
    counterText = "1",
    infoText = "OS",
    canClick = true,
    showStar = false,
})

assertEquals(parts.roll:GetText(), "47", "roll text should update on redraw")
assertEquals(parts.info:GetText(), "OS", "info text should update on redraw")
assertEquals(parts.specIcon.shown, false, "spec icon should hide when spec data is absent")
assertEquals(#parts.specIcon.points, 1, "spec icon anchors should remain stable across redraws")
assertEquals(#parts.star.points, 1, "star anchors should remain stable across redraws")
assertEquals(parts.star.points[1].x, 2, "star should use the original left position without spec icon")
assertEquals(parts.star.shown, false, "star should hide when showStar is false")
assertEquals(parts.name.points[1].x, 18, "name should use original offset without spec icon")

print("master roll row visuals spec passed")
