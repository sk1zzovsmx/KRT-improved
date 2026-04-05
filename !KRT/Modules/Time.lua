-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local tonumber = tonumber
local floor = math.floor
local format = string.format

addon.Time = addon.Time or feature.Time or {}
local Time = addon.Time

-- ----- Internal state ----- --

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

function Time.SecondsToClock(seconds)
    local sec = tonumber(seconds)
    if sec <= 0 then
        return "00:00:00"
    end
    local total = floor(sec)
    local hours = floor(total / 3600)
    local minutes = floor((total % 3600) / 60)
    local secondsPart = floor(total % 60)
    return format("%02d:%02d:%02d", hours, minutes, secondsPart)
end

function Time.IsRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return (inInstance and (instanceType == "raid"))
end

function Time.GetDifficulty()
    local difficulty = nil
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "raid" then
        difficulty = GetRaidDifficulty()
    end
    return difficulty
end

function Time.GetCurrentTime(server)
    if server == nil then
        server = true
    end
    local ts = time()
    if server == true then
        local _, month, day, year = CalendarGetDate()
        local hour, minute = GetGameTime()
        ts = time({ year = year, month = month, day = day, hour = hour, min = minute })
    end
    return ts
end

function Time.GetServerOffset()
    local sH, sM = GetGameTime()
    local lH, lM = tonumber(date("%H")), tonumber(date("%M"))
    local sT = sH + sM / 60
    local lT = lH + lM / 60
    local offset = addon.Round((sT - lT) / 0.5) * 0.5
    if offset >= 12 then
        offset = offset - 24
    elseif offset < -12 then
        offset = offset + 24
    end
    return offset
end
