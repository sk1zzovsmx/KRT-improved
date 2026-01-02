--[[
    KRT_ThrottleTemplate.lua
    - Keyed throttles using GetTime() (3.3.5 compatible).
    - Use this for chat spam / UI refresh / repeated logs.
]]

local _, addon = ...

addon.Throttle = addon.Throttle or {}
local Throttle = addon.Throttle

Throttle._next = Throttle._next or {}

function Throttle:Allow(key, delaySec)
    local now = GetTime()
    local t = self._next[key] or 0
    if now < t then return false end
    self._next[key] = now + (delaySec or 0)
    return true
end
