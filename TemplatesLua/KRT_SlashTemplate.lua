--[[
    KRT_SlashTemplate.lua
    - Single root handler (/krt, /kraidtools) + subcommand table.
    - Prefer using Utils.splitArgs() if available.
]]

local _, addon = ...

addon.Slash = addon.Slash or {}
local Slash = addon.Slash
local Utils = addon.Utils
local L = addon.L

Slash.sub = Slash.sub or {}

local function SplitArgs(msg)
    if Utils and Utils.splitArgs then
        return Utils.splitArgs(msg)
    end

    msg = msg or ""
    msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    return (cmd or ""):lower(), rest or ""
end

function Slash:Register(cmd, fn)
    self.sub[cmd] = fn
end

function Slash:RegisterAliases(list, fn)
    for _, cmd in ipairs(list) do
        self.sub[cmd] = fn
    end
end

function Slash:Handle(msg)
    local cmd, rest = SplitArgs(msg)
    if cmd == "" then
        if addon.PrintHelp then addon:PrintHelp() end
        return
    end

    local fn = self.sub[cmd]
    if fn then return fn(rest, cmd, msg) end

    -- fallback help
    if addon.PrintHelp then addon:PrintHelp() end
end

SLASH_KRT1, SLASH_KRT2 = "/krt", "/kraidtools"
SlashCmdList["KRT"] = function(msg)
    Slash:Handle(msg)
end
