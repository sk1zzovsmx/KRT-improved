-- =======================================================
--  KRT Event Dispatcher Template
--  If you already have an event system, keep the repo one.
-- =======================================================
local _, addon = ...

addon.Events = addon.Events or {}
local Events = addon.Events

-- event -> array of { owner=table, method="OnX" } or { owner=table, fn=function }
Events._map = Events._map or {}
local map = Events._map

addon.EventFrame = addon.EventFrame or CreateFrame("Frame", "KRT_EventFrame")
local EF = addon.EventFrame

local function EnsureEvent(event)
  if not map[event] then
    map[event] = {}
    EF:RegisterEvent(event)
  end
end

function Events:Register(event, owner, methodOrFn)
  EnsureEvent(event)
  map[event][#map[event] + 1] = { owner = owner, h = methodOrFn }
end

local function CallHandler(entry, ...)
  local h = entry.h
  if type(h) == "string" then
    local f = entry.owner and entry.owner[h]
    if f then return f(entry.owner, ...) end
  else
    return h(entry.owner, ...)
  end
end

EF:SetScript("OnEvent", function(_, event, ...)
  local list = map[event]
  if not list then return end
  for i = 1, #list do
    CallHandler(list[i], ...)
  end
end)
