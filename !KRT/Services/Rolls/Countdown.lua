-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: countdown runtime helpers for rolls service
-- exports: addon.Services.Rolls._Countdown

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Services = feature.Services or addon.Services

addon.Services = addon.Services or {}
addon.Services.Rolls = addon.Services.Rolls or {}

-- ----- Internal state ----- --
local module = addon.Services.Rolls
module._Countdown = module._Countdown or {}

local Countdown = module._Countdown

local Chat = Services.Chat
local tonumber = tonumber

-- ----- Private helpers ----- --
local function shouldAnnounceTick(remaining, duration)
    if remaining >= duration then
        return true
    end
    if remaining >= 10 then
        return (remaining % 10 == 0)
    end
    if remaining > 0 and remaining < 10 and remaining % 7 == 0 then
        return true
    end
    if remaining > 0 and remaining >= 5 and remaining % 5 == 0 then
        return true
    end
    return remaining > 0 and remaining <= 3
end

-- ----- Public methods ----- --
function Countdown.ShouldAnnounceTick(remaining, duration)
    return shouldAnnounceTick(remaining, duration)
end

function Countdown.Stop(state)
    addon.CancelTimer(state.countdownTicker, true)
    addon.CancelTimer(state.countdownEndTimer, true)
    state.countdownTicker = nil
    state.countdownEndTimer = nil
    state.countdownRunning = false
    state.countdownRemaining = 0
end

function Countdown.Start(state, duration, onTick, onComplete)
    Countdown.Stop(state)

    local countdownDuration = tonumber(duration) or 0
    if countdownDuration <= 0 then
        return false
    end

    state.countdownRunning = true
    state.countdownDuration = countdownDuration
    state.countdownRemaining = countdownDuration
    state.countdownExpired = false

    if shouldAnnounceTick(state.countdownRemaining, countdownDuration) then
        Chat:Announce(L.ChatCountdownTic:format(state.countdownRemaining))
    end
    if type(onTick) == "function" then
        onTick(state.countdownRemaining, countdownDuration)
    end

    state.countdownTicker = addon.NewTicker(1, function()
        if not state.countdownRunning then
            return
        end
        state.countdownRemaining = state.countdownRemaining - 1
        if state.countdownRemaining > 0 then
            if shouldAnnounceTick(state.countdownRemaining, countdownDuration) then
                Chat:Announce(L.ChatCountdownTic:format(state.countdownRemaining))
            end
            if type(onTick) == "function" then
                onTick(state.countdownRemaining, countdownDuration)
            end
        end
    end, countdownDuration)

    state.countdownEndTimer = addon.NewTimer(countdownDuration, function()
        if not state.countdownRunning then
            return
        end
        Countdown.Stop(state)
        state.countdownExpired = true
        Chat:Announce(L.ChatCountdownEnd)
        if type(onComplete) == "function" then
            onComplete()
        end
    end)

    return true
end

function Countdown.IsRunning(state)
    return state.countdownRunning == true
end
