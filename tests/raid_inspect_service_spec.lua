local callbacks = {}
local busEvents = {}
local timers = {}
local notifyHistory = {}

local inspectLinksBySlot = {
    ["raid1"] = {
        [1] = "|cffa335ee|Hitem:16820:0:0:0:0:0:0:0:0|h[Helm]|h|r",
        [16] = "|cffa335ee|Hitem:16817:0:0:0:0:0:0:0:0|h[Main Hand]|h|r",
    },
}

local function runTimerWork(limit)
    local i = 1
    local executed = 0
    while i <= #timers and (not limit or executed < limit) do
        local fn = timers[i]
        i = i + 1
        if fn then
            fn()
            executed = executed + 1
        end
    end
    local remaining = {}
    for j = i, #timers do
        remaining[#remaining + 1] = timers[j]
    end
    timers = remaining
end

local function newAddon()
    local featureShared = nil
    local raidData = nil
    local fake = {
        Services = {},
        Database = {
            GetCurrentRaid = function()
                return 1
            end,
            GetCurrentRaidNid = function()
                return 10
            end,
            GetRaid = function(_, selfOrRaidId, maybeRaidId)
                local resolvedRaidId = tonumber(maybeRaidId) or tonumber(selfOrRaidId)
                return raidData[resolvedRaidId]
            end,
            GetFeatureShared = function()
                return featureShared
            end,
            GetRaidStoreOrNil = function()
                local store = {
                    [1] = (raidData and raidData[1]) or nil,
                    [100] = (raidData and raidData[100]) or nil,
                }
                return {
                    GetRaid = function(_, model)
                        return store[model.id or model]
                    end,
                }
            end,
            EnsureRaidById = function(_, selfOrRaidId, maybeRaidId)
                local raidId = tonumber(maybeRaidId) or tonumber(selfOrRaidId)
                return (raidData and raidData[raidId]) or nil
            end,
            EnsureRaidSchema = function(_, maybeRaid, raid)
                local resolvedRaid = raid or maybeRaid
                if resolvedRaid then
                    resolvedRaid.players = resolvedRaid.players or {}
                    resolvedRaid.attendance = resolvedRaid.attendance or {}
                    resolvedRaid.inspect = resolvedRaid.inspect or {}
                    resolvedRaid.inspect.players = resolvedRaid.inspect.players or {}
                end
                return resolvedRaid
            end,
        },
        Strings = {
            NormalizeName = function(name)
                return name
            end,
        },
    }

    raidData = {
        [1] = {
            id = 1,
            raidNid = 10,
            inspect = {
                players = {},
            },
            players = {
                [1] = { name = "Alice", class = "DRUID", playerNid = 1 },
                [2] = { name = "Bob", class = "MAGE", playerNid = 2 },
            },
        },
        [100] = {
            id = 100,
            raidNid = 300,
            inspect = {
                players = {
                    [1] = { status = "ready", playerNid = 1, avgIlvl = 999 },
                },
            },
        },
        [2] = {
            raidNid = 100,
            players = {
                [1] = { name = "Charlie", class = "PRIEST", playerNid = 1 },
            },
        },
    }

    fake.Database.GetFeatureShared = function()
        return featureShared
    end

    local function getRaidById(selfOrRaidId, maybeRaidId)
        local resolvedRaidId = tonumber(maybeRaidId) or tonumber(selfOrRaidId)
        return raidData[resolvedRaidId]
    end

    local function getRaidIdByNid(raidNid)
        local nid = tonumber(raidNid)
        if not nid then
            return nil
        end
        for raidId, raid in pairs(raidData) do
            if type(raid) == "table" and tonumber(raid.raidNid) == nid then
                return tonumber(raidId)
            end
        end
        return nil
    end

    fake.Database.GetRaid = getRaidById
    fake.Database.GetFeatureShared = function()
        return featureShared
    end
    fake.Database.GetRaidStoreOrNil = function()
        local store = {
            [1] = raidData[1],
            [2] = raidData[2],
            [100] = raidData[100],
        }
        return {
            GetRaid = function(_, model)
                return store[model.id or model]
            end,
        }
    end
    fake.Database.EnsureRaidById = getRaidById
    fake.Database.GetRaidIdByNid = getRaidIdByNid

    local rosterPlayers = {
        [1] = { name = "Alice", class = "DRUID", playerNid = 1, unit = "raid1", group = 1 },
        [2] = { name = "Bob", class = "MAGE", playerNid = 2, unit = "raid2", group = 1 },
    }
    local roster = {
        players = rosterPlayers,
        GetPlayers = function(_, _, _, out)
            out = out or {}
            out[#out + 1] = rosterPlayers[1]
            out[#out + 1] = rosterPlayers[2]
            return out
        end,
        GetPlayerNid = function(_, name)
            if name == "Alice" then
                return 1
            end
            if name == "Bob" then
                return 2
            end
            return nil
        end,
        GetPlayerInfo = function(_, _, playerNid)
            return rosterPlayers[playerNid]
        end,
        GetPlayerUnit = function(_, _, playerNid)
            return rosterPlayers[playerNid] and rosterPlayers[playerNid].unit or nil
        end,
        GetUnitByPlayerNid = function(_, _, playerNid)
            return rosterPlayers[playerNid] and rosterPlayers[playerNid].unit or nil
        end,
    }

    featureShared = {
        L = {
            Get = function() end,
        },
        Diag = { E = {} },
        Services = fake.Services,
        Database = fake.Database,
        Strings = fake.Strings,
        EnsureServiceNamespace = function(name)
            fake.Services[name] = fake.Services[name] or {}
            return fake.Services[name]
        end,
        ModuleRegistry = {
            AddModule = function() end,
            SetLoaded = function() end,
        },
        Timer = {
            BindMixin = function(target)
                target.ScheduleTimer = function(_, callback)
                    timers[#timers + 1] = callback
                    return true
                end
                target.ScheduleRepeatingTimer = function(_, callback)
                    timers[#timers + 1] = callback
                    return true
                end
                target.CancelTimer = function()
                    return true
                end
            end,
            RefreshStats = function() end,
            ShowStats = function() end,
        },
        Bus = {
            RegisterCallback = function(eventName, callback)
                callbacks[eventName] = callbacks[eventName] or {}
                callbacks[eventName][#callbacks[eventName] + 1] = callback
            end,
            TriggerEvent = function(eventName, ...)
                busEvents[#busEvents + 1] = { eventName, ... }
                local handlers = callbacks[eventName]
                if handlers then
                    for i = 1, #handlers do
                        handlers[i](eventName, ...)
                    end
                end
            end,
        },
        Events = {
            Internal = {
                RaidCreate = "RaidCreate",
                RaidInspectStarted = "RaidInspectStarted",
                RaidInspectUpdated = "RaidInspectUpdated",
                RaidInspectCompleted = "RaidInspectCompleted",
                RaidAttendanceChanged = "RaidAttendanceChanged",
            },
            Wow = {
                InspectTalentReady = "INSPECT_TALENT_READY",
                PlayerRegenEnabled = "PLAYER_REGEN_ENABLED",
            },
            GetWowForwarded = function(wowEvent)
                return wowEvent
            end,
        },
    }
    fake.FeatureShared = featureShared

    fake.Services.Raid = roster
    fake.Services["Raid/Roster"] = roster
    fake.Services["Raid/Attendance"] = {
        SeedAttendanceFromCurrentRaid = function() end,
        CloseAttendanceForRaid = function() end,
        GetPlayerAttendance = function(_, _, playerNid)
            return roster.players[playerNid]
        end,
    }

    return fake
end

local function loadAddonFile(addon, path)
    local chunk = assert(loadfile(path))
    setfenv(
        chunk,
        setmetatable({
            select = select,
            pairs = pairs,
            ipairs = ipairs,
            unpack = unpack,
            tostring = tostring,
            tonumber = tonumber,
            string = string,
            math = math,
            table = table,
            pcall = pcall,
            error = error,
            time = function()
                return 1000
            end,
            UnitExists = function(unit)
                return unit == "raid1" or unit == "raid2"
            end,
            UnitIsConnected = function(unit)
                if unit == "raid1" then
                    return true
                end
                return unit ~= "raid2"
            end,
            CanInspect = function(unit)
                return unit == "raid1"
            end,
            CheckInteractDistance = function(unit, index)
                return unit == "raid1" and index == 1
            end,
            UnitGUID = function(unit)
                return ({ raid1 = "GUID-A", raid2 = "GUID-B" })[unit]
            end,
            ClearInspectPlayer = function()
                return true
            end,
            GetInventoryItemLink = function(unit, slot)
                return (inspectLinksBySlot[unit] and inspectLinksBySlot[unit][slot]) or nil
            end,
            GetInventoryItemTexture = function(unit, slot)
                if inspectLinksBySlot[unit] and inspectLinksBySlot[unit][slot] then
                    return "Interface\\Icons\\item"
                end
                return nil
            end,
            GetInventoryItemQuality = function(unit, slot)
                if inspectLinksBySlot[unit] and inspectLinksBySlot[unit][slot] then
                    return 4
                end
                return nil
            end,
            GetItemInfo = function(itemLink)
                if itemLink then
                    return "Test Item", itemLink, 4, 264
                end
                return nil
            end,
            GetTalentTabInfo = function(tab, inspect)
                if inspect == true then
                    local tabs = {
                        [1] = { icon = "Interface\\Icons\\icon-fury", name = "Balance", points = 10 },
                        [2] = { icon = "Interface\\Icons\\icon-protection", name = "Feral", points = 55 },
                        [3] = { icon = "Interface\\Icons\\icon-runes", name = "Restoration", points = 16 },
                    }
                    local data = tabs[tab]
                    if data then
                        return data.name, data.icon, data.points
                    end
                end
                return nil
            end,
            GetTalentSpecName = function()
                return nil
            end,
            NotifyInspect = function(unit)
                notifyHistory[#notifyHistory + 1] = unit
            end,
        }, { __index = _G })
    )
    chunk("!KRT", addon)
    addon.Bus = addon.FeatureShared and addon.FeatureShared.Bus or addon.Bus
end

local addon = newAddon()
loadAddonFile(addon, "!KRT/Services/RaidInspect.lua")

local service = assert(addon.Services.RaidInspect, "RaidInspect service must load")

local currentRaid = addon.Database.GetRaid(1)
local historicalRaid = addon.Database.GetRaid(2)

local historicalSnapshot = service:GetSnapshot(historicalRaid, 1)
assert(historicalSnapshot == nil, "historical raid table should not read inspect data from matching raidNid as an index")

local ok, reason = service:StartRaidSnapshot(nil)
assert(ok == false and reason == "missing_raid", "StartRaidSnapshot(nil) should return missing_raid")

ok, reason = service:StartRaidSnapshot(100)
assert(ok == false and reason == "not_current_raid", "StartRaidSnapshot(100) should reject historical raids")

ok, reason = service:ForcePlayer(100, 1)
assert(ok == false and reason == "not_current_raid", "ForcePlayer(100, 1) should reject historical raids")

ok, reason = service:ForcePlayer(1, 9999)
assert(ok == false and reason == "missing_player", "ForcePlayer(1, 9999) should reject missing players")

ok = service:StartRaidSnapshot(1)
assert(ok == true, "current raid should start snapshot")
assert(currentRaid.inspect.mode == "raid_snapshot", "StartRaidSnapshot should set inspect mode")
assert(type(currentRaid.inspect.startedAt) == "number", "StartRaidSnapshot should set inspect startedAt")
local function hasInspectUpdate(playerNid, status)
    for i = 1, #busEvents do
        local event = busEvents[i]
        local payload = event and event[4]
        if event and event[1] == "RaidInspectUpdated" and tonumber(event[3]) == tonumber(playerNid) and payload and payload.status == status then
            return true
        end
    end
    return false
end
assert(hasInspectUpdate(1, "queued"), "queued runtime inspect status should emit a refresh event")

ok = service:StartRaidSnapshot(1)
assert(ok == true, "re-starting snapshot should still be accepted")

assert(#timers > 0, "snapshot start should schedule work")
runTimerWork(1)
assert(notifyHistory[1] == "raid1", "first inspectable player should be notified first")
assert(notifyHistory[2] == nil, "first inspectable player should be notified once")

local runtimeBeforeReady = service:GetRuntimeStatus(1, 1)
assert(runtimeBeforeReady and runtimeBeforeReady.status == "pending", "Alice should be pending after first work")
assert(currentRaid.inspect.players[1] == nil, "Alice runtime pending should not persist under raid.inspect")
assert(hasInspectUpdate(1, "pending"), "pending runtime inspect status should emit a refresh event")

addon.Bus.TriggerEvent("INSPECT_TALENT_READY")
runTimerWork(1)

local aliceSnapshot = service:GetSnapshot(currentRaid, 1)
assert(aliceSnapshot.status == "ready", "Alice should be ready after INSPECT_TALENT_READY")
assert(type(aliceSnapshot.avgIlvl) == "number", "ready Alice snapshot should include numeric avgIlvl")
assert(type(aliceSnapshot.specName) == "string", "ready Alice snapshot should include string specName")
assert(type(aliceSnapshot.items) == "table", "ready Alice snapshot should include items table")

runTimerWork(1)
local bobSnapshot = service:GetSnapshot(currentRaid, 2)
assert(bobSnapshot.status == "skipped", "offline Bob should be skipped")
assert(bobSnapshot.reason == "offline", "offline Bob should use offline reason")
assert(type(currentRaid.inspect.completedAt) == "number", "inspect completion should set completedAt")

local alicePersisted = service:GetPersistedSnapshot(currentRaid, 1)
local bobPersisted = service:GetPersistedSnapshot(currentRaid, 2)
assert(alicePersisted.status ~= "queued" and alicePersisted.status ~= "pending", "persisted Alice snapshot should be final")
assert(bobPersisted.status ~= "queued" and bobPersisted.status ~= "pending", "persisted Bob snapshot should be final")

ok, reason = service:ForcePlayer(1, 1)
assert(ok == true and reason == nil, "ForcePlayer(current, readyPlayer) should succeed and queue again")

local readyAgain = service:GetRuntimeStatus(1, 1)
assert(readyAgain and readyAgain.status == "pending", "forced ready player should be pending")

print("raid inspect service spec passed")
