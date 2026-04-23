-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: consumes RaidRosterDelta
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core
local Events = feature.Events or addon.Events
local Bus = feature.Bus or addon.Bus
local Time = feature.Time or addon.Time

local InternalEvents = Events.Internal

local tinsert = table.insert
local type, tonumber = type, tonumber

do
    addon.Services.Raid = addon.Services.Raid or {}
    local module = addon.Services.Raid

    -- ----- Internal state ----- --

    -- ----- Private helpers ----- --
    local function ensureAttendanceTable(raid)
        if type(raid.attendance) ~= "table" then
            raid.attendance = {}
        end
        return raid.attendance
    end

    local function ensureAttendanceEntry(raid, playerNid)
        local resolvedPlayerNid = tonumber(playerNid) or 0
        if resolvedPlayerNid <= 0 then
            return nil
        end

        local attendance = ensureAttendanceTable(raid)
        for i = 1, #attendance do
            local entry = attendance[i]
            if type(entry) == "table" and tonumber(entry.playerNid) == resolvedPlayerNid then
                if type(entry.segments) ~= "table" then
                    entry.segments = {}
                end
                entry.playerNid = resolvedPlayerNid
                return entry
            end
        end

        local entry = {
            playerNid = resolvedPlayerNid,
            segments = {},
        }
        attendance[#attendance + 1] = entry
        return entry
    end

    local function getOpenSegment(entry)
        local segments = entry and entry.segments or nil
        if type(segments) ~= "table" then
            return nil
        end

        for i = #segments, 1, -1 do
            local segment = segments[i]
            if type(segment) == "table" and not segment.endTime then
                return segment
            end
        end
        return nil
    end

    local function closeOpenSegment(entry, timestamp)
        local segment = getOpenSegment(entry)
        if not segment then
            return false
        end

        local resolvedTimestamp = tonumber(timestamp) or Time.GetCurrentTime()
        local startTime = tonumber(segment.startTime) or resolvedTimestamp
        if resolvedTimestamp < startTime then
            resolvedTimestamp = startTime
        end

        segment.endTime = resolvedTimestamp
        return true
    end

    local function openSegment(entry, timestamp, subgroup, online)
        local resolvedTimestamp = tonumber(timestamp) or Time.GetCurrentTime()
        local resolvedSubgroup = tonumber(subgroup) or 1
        local resolvedOnline = online ~= false
        local segment = getOpenSegment(entry)

        if segment then
            local segmentSubgroup = tonumber(segment.subgroup) or 1
            local segmentOnline = segment.online ~= false
            if segmentSubgroup == resolvedSubgroup and segmentOnline == resolvedOnline then
                return segment
            end
            closeOpenSegment(entry, resolvedTimestamp)
        end

        local segmentOnline = nil
        if not resolvedOnline then
            segmentOnline = false
        end

        local newSegment = {
            startTime = resolvedTimestamp,
            subgroup = resolvedSubgroup > 1 and resolvedSubgroup or nil,
            online = segmentOnline,
        }
        tinsert(entry.segments, newSegment)
        return newSegment
    end

    local function applyRosterPresence(raid, event, timestamp, isLeaving)
        local playerNid = tonumber(event and event.playerNid) or 0
        if playerNid <= 0 then
            return false
        end

        local entry = ensureAttendanceEntry(raid, playerNid)
        if not entry then
            return false
        end

        if isLeaving then
            return closeOpenSegment(entry, timestamp)
        end

        openSegment(entry, timestamp, event.subgroup, event.online)
        return true
    end

    local function applyRosterList(raid, list, timestamp, isLeaving)
        local changed = false
        if type(list) ~= "table" then
            return false
        end

        for i = 1, #list do
            changed = applyRosterPresence(raid, list[i], timestamp, isLeaving) or changed
        end
        return changed
    end

    local function handleRosterDelta(_, delta, _, raidNum)
        local resolvedRaidNum = tonumber(raidNum) or tonumber(delta and delta.raidNum) or 0
        if resolvedRaidNum <= 0 or type(delta) ~= "table" then
            return
        end

        local raid = Core.EnsureRaidById(resolvedRaidNum)
        if not raid then
            return
        end
        Core.EnsureRaidSchema(raid)

        local timestamp = tonumber(delta.timestamp) or Time.GetCurrentTime()
        applyRosterList(raid, delta.joined, timestamp, false)
        applyRosterList(raid, delta.updated, timestamp, false)
        applyRosterList(raid, delta.left, timestamp, true)
    end

    -- ----- Public methods ----- --
    function module:GetAttendanceEntry(raid, playerNid)
        local attendance = raid and raid.attendance or nil
        local resolvedPlayerNid = tonumber(playerNid) or 0
        if type(attendance) ~= "table" or resolvedPlayerNid <= 0 then
            return nil
        end

        for i = 1, #attendance do
            local entry = attendance[i]
            if type(entry) == "table" and tonumber(entry.playerNid) == resolvedPlayerNid then
                return entry
            end
        end
        return nil
    end

    function module:GetAttendanceSegments(raid, playerNid)
        local entry = self:GetAttendanceEntry(raid, playerNid)
        if not entry or type(entry.segments) ~= "table" then
            return {}
        end
        return entry.segments
    end

    function module:AddAttendanceDelta(raidNum, delta, timestamp)
        if type(delta) ~= "table" then
            return false
        end

        local resolvedRaidNum = tonumber(raidNum) or tonumber(delta.raidNum) or Core.GetCurrentRaid()
        local raid = resolvedRaidNum and Core.EnsureRaidById(resolvedRaidNum) or nil
        if not raid then
            return false
        end
        Core.EnsureRaidSchema(raid)

        local resolvedTimestamp = tonumber(timestamp) or tonumber(delta.timestamp) or Time.GetCurrentTime()
        local changed = false
        changed = applyRosterList(raid, delta.joined, resolvedTimestamp, false) or changed
        changed = applyRosterList(raid, delta.updated, resolvedTimestamp, false) or changed
        changed = applyRosterList(raid, delta.left, resolvedTimestamp, true) or changed
        return changed
    end

    if Bus and Bus.RegisterCallback and InternalEvents and InternalEvents.RaidRosterDelta then
        Bus.RegisterCallback(InternalEvents.RaidRosterDelta, handleRosterDelta)
    end
end
