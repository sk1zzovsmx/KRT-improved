-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Strings = feature.Strings

local tonumber = tonumber
local ipairs = ipairs

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Logger", "Helpers")
local Helpers = addon.Services.Logger.Helpers
local Store = addon.Services.Logger.Store

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

-- Search raid.loot by itemId (non-NID fallback diagnostic).
function Helpers.FindLootByItemId(raid, itemId)
    if not (raid and raid.loot) then
        return nil, 0
    end

    local queryItemId = tonumber(itemId)
    if not queryItemId then
        return nil, 0
    end

    local match = nil
    local matches = 0
    for i = #raid.loot, 1, -1 do
        local entry = raid.loot[i]
        if entry and tonumber(entry.itemId) == queryItemId then
            matches = matches + 1
            if not match then
                match = entry
            end
        end
    end
    return match, matches
end

-- Find a player name in raid.players or boss attendees by normalized name.
function Helpers.FindLoggerPlayer(normalizedName, raid, bossKill)
    if raid and raid.players then
        for _, p in ipairs(raid.players) do
            if normalizedName == Strings.NormalizeLower(p.name) then
                return p.name
            end
        end
    end
    if bossKill and bossKill.players then
        for i = 1, #bossKill.players do
            local playerNid = tonumber(bossKill.players[i])
            local playerName = playerNid and Store._ResolvePlayerNameByNid(raid, playerNid) or nil
            if playerName and normalizedName == Strings.NormalizeLower(playerName) then
                return playerName
            end
        end
    end
    return nil
end

local registry = addon.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Logger/Helpers", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Services/Logger/Store",
        },
    })
    registry.SetLoaded("Services/Logger/Helpers")
end
