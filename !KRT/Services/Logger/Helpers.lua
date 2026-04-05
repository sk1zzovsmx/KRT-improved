-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Strings = feature.Strings or addon.Strings

local tconcat = table.concat
local tostring, tonumber = tostring, tonumber
local ipairs = ipairs

-- ----- Internal state ----- --
addon.Services.Logger.Helpers = addon.Services.Logger.Helpers or {}

local Helpers = addon.Services.Logger.Helpers
local Store = addon.Services.Logger.Store
local View = addon.Services.Logger.View

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

-- Pure string: "Label (N)"
function Helpers.GetCountTitle(baseText, count)
    return ("%s (%d)"):format(tostring(baseText or ""), tonumber(count) or 0)
end

-- Pure string: "Base - Context" or "Base - Hint" or just "Base"
function Helpers.GetContextTitle(baseText, contextText, emptyHint)
    local suffix = contextText
    if not suffix or suffix == "" then
        suffix = emptyHint
    end
    if suffix and suffix ~= "" then
        return ("%s - %s"):format(baseText, suffix)
    end
    return baseText
end

-- Shorthand: GetContextTitle(GetCountTitle(...), context, hint)
function Helpers.GetCountContextTitle(baseText, count, contextText, emptyHint)
    return Helpers.GetContextTitle(Helpers.GetCountTitle(baseText, count), contextText, emptyHint)
end

-- Context label for a raid selection: "Zone Difficulty" or zone or difficulty.
function Helpers.GetRaidContextLabel(selectedRaid)
    if not selectedRaid then
        return nil
    end
    local raid = Store:GetRaid(selectedRaid)
    if not raid then
        return nil
    end
    local zone = raid.zone or nil
    local difficulty = View:GetRaidDifficultyLabel(raid) or ""
    if zone and zone ~= "" and difficulty ~= "" then
        return ("%s %s"):format(zone, difficulty)
    end
    if zone and zone ~= "" then
        return zone
    end
    if difficulty ~= "" then
        return difficulty
    end
    return nil
end

-- Context label for a boss selection: "BossName Mode".
function Helpers.GetBossContextLabel(selectedRaid, selectedBoss)
    if not (selectedRaid and selectedBoss) then
        return nil
    end
    local raid = Store:GetRaid(selectedRaid)
    local boss = raid and Store:GetBoss(raid, selectedBoss) or nil
    if not boss then
        return nil
    end
    local name = boss.name
    if not name or name == "" then
        name = L.StrTrashMob
    end
    local mode = View:GetBossModeLabel(boss)
    if mode and mode ~= "" then
        return ("%s %s"):format(name, mode)
    end
    return name
end

-- Context label for a player selection: "Player: Name".
function Helpers.GetPlayerContextLabel(selectedRaid, playerNid)
    if not (selectedRaid and playerNid) then
        return nil
    end
    local raid = Store:GetRaid(selectedRaid)
    local player = raid and Store:GetPlayer(raid, playerNid) or nil
    if player and player.name and player.name ~= "" then
        return L.StrLoggerLabelPlayer:format(player.name)
    end
    return nil
end

-- Composite context label for the loot panel: "Boss | Player" or raid fallback.
function Helpers.GetLootPanelContextLabel(sel)
    local parts = {}
    local bossLabel = Helpers.GetBossContextLabel(sel.selectedRaid, sel.selectedBoss)
    local playerLabel = Helpers.GetPlayerContextLabel(sel.selectedRaid, sel.selectedBossPlayer or sel.selectedPlayer)

    if bossLabel and bossLabel ~= "" then
        parts[#parts + 1] = bossLabel
    end
    if playerLabel and playerLabel ~= "" then
        parts[#parts + 1] = playerLabel
    end
    if #parts > 0 then
        return tconcat(parts, " | ")
    end
    return Helpers.GetRaidContextLabel(sel.selectedRaid)
end

-- ----- Empty-state text builders ----- --

function Helpers.GetBossEmptyStateText(count, selectedRaid)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not selectedRaid then
        return L.StrLoggerEmptyBossesSelectRaid
    end
    return L.StrLoggerEmptyBosses
end

function Helpers.GetBossAttendeesEmptyStateText(count, selectedRaid, selectedBoss)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not selectedRaid then
        return L.StrLoggerEmptyBossAttendeesSelectRaid
    end
    if not selectedBoss then
        return L.StrLoggerEmptyBossAttendeesSelectBoss
    end
    return L.StrLoggerEmptyBossAttendees
end

function Helpers.GetRaidAttendeesEmptyStateText(count, selectedRaid)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not selectedRaid then
        return L.StrLoggerEmptyRaidAttendeesSelectRaid
    end
    return L.StrLoggerEmptyRaidAttendees
end

function Helpers.GetLootEmptyStateText(count, sel)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not sel.selectedRaid then
        return L.StrLoggerEmptyLootSelectRaid
    end
    if sel.selectedBoss or sel.selectedBossPlayer or sel.selectedPlayer then
        return L.StrLoggerEmptyLootFiltered
    end
    return L.StrLoggerEmptyLoot
end

function Helpers.GetCsvEmptyStateText(selectedRaid, csvValue)
    if not selectedRaid then
        return L.StrLoggerEmptyCsvSelectRaid
    end
    if not csvValue or csvValue == "" then
        return L.StrLoggerEmptyCsv
    end
    return nil
end

-- ----- Data lookup helpers ----- --

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
            local playerName = playerNid and Store:ResolvePlayerNameByNid(raid, playerNid) or nil
            if playerName and normalizedName == Strings.NormalizeLower(playerName) then
                return playerName
            end
        end
    end
    return nil
end

-- Validate a roll value text input.
function Helpers.IsValidRollValue(text)
    local value = text and tonumber(text)
    if not value or value < 0 then
        return false
    end
    return true, value
end
