-- =======================================================
--  KRT Slash Template (single root + subcommands table)
-- =======================================================
local _, addon = ...

addon.Slash = addon.Slash or {}
local Slash = addon.Slash

local function SplitArgs(msg)
  msg = msg or ""
  msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  return (cmd or ""):lower(), rest or ""
end

Slash.sub = Slash.sub or {}

function Slash:Register(cmd, fn)
  self.sub[cmd] = fn
end

function Slash:Handle(msg)
  local cmd, rest = SplitArgs(msg)
  local fn = self.sub[cmd]
  if fn then return fn(rest) end
  -- fallback: help
  if addon.PrintHelp then addon:PrintHelp() end
end

SLASH_KRT1 = "/krt"
SLASH_KRT2 = "/kraidtools"
SlashCmdList.KRT = function(msg)
  Slash:Handle(msg)
end
