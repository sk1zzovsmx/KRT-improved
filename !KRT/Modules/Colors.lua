-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type = type

addon.Colors = addon.Colors or feature.Colors or {}
local Colors = addon.Colors

function Colors.NormalizeHexColor(color)
    if type(color) == "string" then
        local hex = color:gsub("^|c", ""):gsub("|r$", ""):gsub("^#", "")
        if #hex == 6 then
            hex = "ff" .. hex
        end
        return hex
    end

    if type(color) == "table" and color.GenerateHexColor then
        local hex = color:GenerateHexColor():gsub("^#", "")
        if #hex == 6 then
            hex = "ff" .. hex
        end
        return hex
    end

    return "ffffffff"
end

function Colors.GetClassColor(className)
    local r, g, b = addon.GetClassColor(className)
    return (r or 1), (g or 1), (b or 1)
end
