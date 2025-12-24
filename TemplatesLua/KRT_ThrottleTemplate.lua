-- =======================================================
--  KRT Throttle Template (keyed, uses GetTime)
-- =======================================================
local _, addon = ...

addon.Throttle = addon.Throttle or {}
local T = addon.Throttle

T._next = T._next or {}

function T:Allow(key, delay)
  local now = GetTime()
  local t = self._next[key] or 0
  if now < t then return false end
  self._next[key] = now + (delay or 0)
  return true
end
