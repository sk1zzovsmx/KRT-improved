-- =======================================================
--  KRT Core Template (WotLK 3.3.5a • Lua 5.1)
--  Put this pattern in KRT.lua (adapt to existing codebase)
-- =======================================================
local ADDON_NAME, addon = ...

addon = addon or {}
addon.name = addon.name or ADDON_NAME

-- -------------------------------------------------------
-- Event frame (single)
-- -------------------------------------------------------
addon.EventFrame = addon.EventFrame or CreateFrame("Frame", "KRT_EventFrame")
local EF = addon.EventFrame

-- dispatcher table: event -> { {owner=..., fn=...}, ... }
addon._handlers = addon._handlers or {}
local handlers = addon._handlers

local function Dispatch(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local h = list[i]
    -- allow fn to be string or function
    if type(h.fn) == "string" then
      local m = h.owner
      local f = m and m[h.fn]
      if f then f(m, ...) end
    else
      h.fn(h.owner, ...)
    end
  end
end

function addon:RegisterHandler(event, owner, fn)
  if not handlers[event] then
    handlers[event] = {}
    EF:RegisterEvent(event)
  end
  handlers[event][#handlers[event] + 1] = { owner = owner, fn = fn }
end

EF:SetScript("OnEvent", function(_, event, ...)
  Dispatch(event, ...)
end)

-- -------------------------------------------------------
-- Core lifecycle
-- -------------------------------------------------------
local function InitSavedVars()
  -- create tables if missing; do not overwrite user values
  KRT_Options = KRT_Options or {}
  KRT_Debug = KRT_Debug or {}
  KRT_Options.schemaVersion = KRT_Options.schemaVersion or 1
end

local function InitModules()
  -- Example:
  -- addon.Rolls:Init()
  -- addon.Reserves:Init()
end

addon:RegisterHandler("ADDON_LOADED", addon, function(self, addonName)
  if addonName ~= ADDON_NAME then return end
  -- Only once
  EF:UnregisterEvent("ADDON_LOADED")
  InitSavedVars()
  InitModules()
end)
