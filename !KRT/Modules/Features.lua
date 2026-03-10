-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: feature-profile and widget-flag runtime control

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local _G = _G
local type, pairs = type, pairs
local lower = string.lower

addon.Features = addon.Features or feature.Features or {}
local Features = addon.Features

Features.WidgetFlags = Features.WidgetFlags or {}
Features.Profiles = Features.Profiles
    or {
        full = {
            Config = true,
            LootCounter = true,
            Reserves = true,
        },
        core = {
            Config = false,
            LootCounter = false,
            Reserves = false,
        },
    }

local function normalizeProfile(profileName)
    if type(profileName) ~= "string" or profileName == "" then
        return "full"
    end
    return lower(profileName)
end

local function applyProfileFlags(profileName)
    local profileKey = normalizeProfile(profileName)
    local profileFlags = Features.Profiles[profileKey] or Features.Profiles.full
    local flags = Features.WidgetFlags

    for widgetId in pairs(flags) do
        flags[widgetId] = nil
    end
    for widgetId, enabled in pairs(profileFlags or {}) do
        flags[widgetId] = enabled == true
    end

    Features.Profile = profileKey
    return profileKey
end

function Features:SetProfile(profileName)
    return applyProfileFlags(profileName)
end

function Features:Set(widgetId, enabled)
    if type(widgetId) ~= "string" or widgetId == "" then
        return false
    end
    self.WidgetFlags[widgetId] = enabled == true
    return true
end

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

local requestedProfile = _G.KRT_FEATURE_PROFILE
if type(requestedProfile) ~= "string" or requestedProfile == "" then
    requestedProfile = Features.Profile or "full"
end
applyProfileFlags(requestedProfile)

local overrides = _G.KRT_FEATURE_FLAGS
if type(overrides) == "table" then
    for widgetId, enabled in pairs(overrides) do
        Features:Set(widgetId, enabled)
    end
end
