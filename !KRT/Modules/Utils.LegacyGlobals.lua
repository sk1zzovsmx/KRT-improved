-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local _G = _G
local type = type
local random = math.random
local gsub = string.gsub
local strsub, strlen = string.sub, string.len

addon.Utils = addon.Utils or {}
local Utils = addon.Utils

Utils.LegacyGlobals = Utils.LegacyGlobals or {}
local LegacyGlobals = Utils.LegacyGlobals

function LegacyGlobals.install()
    if LegacyGlobals._installed then
        return
    end

    -- Shuffle a table:
    _G.table.shuffle = function(t)
        if type(t) ~= "table" then
            return t
        end

        local n = #t
        while n > 1 do
            local k = random(1, n)
            t[n], t[k] = t[k], t[n]
            n = n - 1
        end
        return t
    end

    -- Reverse table:
    _G.table.reverse = function(t, count)
        if type(t) ~= "table" then
            return t
        end

        local maxIndex = tonumber(count) or #t
        if maxIndex < 2 then
            return t
        end
        if maxIndex > #t then
            maxIndex = #t
        end

        local i, j = 1, maxIndex
        while i < j do
            t[i], t[j] = t[j], t[i]
            i = i + 1
            j = j - 1
        end
        return t
    end

    -- Trim a string:
    _G.string.trim = function(str)
        if str == nil then
            return ""
        end
        return gsub(tostring(str), "^%s*(.-)%s*$", "%1")
    end

    -- String starts with:
    _G.string.startsWith = function(str, piece)
        if type(str) ~= "string" or type(piece) ~= "string" then
            return false
        end
        return strsub(str, 1, strlen(piece)) == piece
    end

    -- String ends with:
    _G.string.endsWith = function(str, piece)
        if type(str) ~= "string" or type(piece) ~= "string" then
            return false
        end
        local lenPiece = strlen(piece)
        if #str < lenPiece then
            return false
        end
        return strsub(str, -lenPiece) == piece
    end

    LegacyGlobals._installed = true
end

LegacyGlobals.install()
