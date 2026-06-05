-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, pairs = type, pairs

addon.Features = addon.Features or feature.Features or {}
local Features = addon.Features

-- ----- Internal state ----- --
Features.WidgetFlags = Features.WidgetFlags or {}
local defaultWidgetFlags = {
    Config = true,
    LootCounter = true,
    Reserves = true,
}

-- ----- Private helpers ----- --
local function applyDefaultProfile()
    local flags = Features.WidgetFlags

    for widgetId in pairs(flags) do
        flags[widgetId] = nil
    end
    for widgetId, enabled in pairs(defaultWidgetFlags) do
        flags[widgetId] = enabled == true
    end

    Features.Profile = "full"
end

-- ----- Public methods ----- --
function Features:IsEnabled(widgetId)
    if type(widgetId) ~= "string" or widgetId == "" then
        return false
    end

    local flag = self.WidgetFlags[widgetId]
    if flag == nil then
        return true
    end
    return flag == true
end

function Features:GetProfile()
    return self.Profile or "full"
end

applyDefaultProfile()
