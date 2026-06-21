local callbacks = {}
local busEvents = {}
local now = 1000

local fakeLGT = {
    refreshed = {},
    snapshots = {},
}

function fakeLGT:GetActiveTalentGroup(unit)
    local row = self.snapshots[unit]
    return row and row.activeGroup or nil
end

function fakeLGT:GetNumTalentGroups(unit)
    local row = self.snapshots[unit]
    return row and row.numGroups or nil
end

function fakeLGT:GetUnitTalentSpec(unit, group)
    local row = self.snapshots[unit]
    if row and row.raiseTalentError then
        error("talent read failed")
    end
    if not row then
        return nil
    end

    local groupIndex = tonumber(group) or tonumber(row.activeGroup) or 1
    local groupData = row.groups and row.groups[groupIndex] or row
    if not groupData then
        return nil
    end
    return groupData.specName, groupData.t1 or 0, groupData.t2 or 0, groupData.t3 or 0
end

function fakeLGT:GetTalentTabInfo(unit, tab, group)
    local row = self.snapshots[unit]
    if not row then
        return nil
    end

    local groupIndex = tonumber(group) or tonumber(row.activeGroup) or 1
    local groupData = row.groups and row.groups[groupIndex] or row
    if not groupData or not groupData.tabs then
        return nil
    end

    local data = groupData.tabs[tab]
    if not data then
        return nil
    end
    return data.name, data.icon, data.points or 0, data.background
end

function fakeLGT:GetUnitRole(unit)
    local row = self.snapshots[unit]
    return row and row.role or nil
end

function fakeLGT:RefreshTalentsByUnit(unit)
    self.refreshed[#self.refreshed + 1] = unit
end

function fakeLGT.RegisterCallback(owner, eventName, handler)
    callbacks[eventName] = callbacks[eventName] or {}
    callbacks[eventName][#callbacks[eventName] + 1] = { owner = owner, handler = handler }
end

local function fireLgt(eventName, ...)
    for i = 1, #(callbacks[eventName] or {}) do
        local cb = callbacks[eventName][i]
        cb.handler(eventName, ...)
    end
end

local function newAddon()
    local addon = { Services = {}, Database = {} }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
        Events = {
            Internal = {
                SpecInspectUpdated = "SpecInspectUpdated",
            },
            Wow = {
                ReadyCheck = "wow.READY_CHECK",
            },
            GetWowForwarded = function(name)
                return "wow." .. tostring(name)
            end,
        },
        Bus = {
            RegisterCallback = function(eventName, fn)
                busEvents[eventName] = busEvents[eventName] or {}
                busEvents[eventName][#busEvents[eventName] + 1] = fn
            end,
            TriggerEvent = function(eventName, ...)
                busEvents._triggered = busEvents._triggered or {}
                busEvents._triggered[#busEvents._triggered + 1] = { eventName, ... }
            end,
        },
        Strings = {
            NormalizeName = function(name)
                return name
            end,
        },
        ModuleRegistry = {
            AddModule = function() end,
            SetLoaded = function() end,
        },
    }
    feature.Services.Raid = {
        GetUnitID = function(_, name)
            return ({ Alice = "raid1", Bob = "raid2", Charlie = "raid3" })[name] or "none"
        end,
        GetPlayers = function(_, _, _, out)
            out = out or {}
            out[#out + 1] = { name = "Alice", class = "DRUID" }
            out[#out + 1] = { name = "Bob", class = "MAGE" }
            return out
        end,
        GetPlayerClass = function(_, name)
            return name == "Alice" and "DRUID" or "MAGE"
        end,
    }
    addon.Database.GetCurrentRaid = function()
        return 1
    end
    addon.Database.GetFeatureShared = function()
        return feature
    end
    feature.EnsureServiceNamespace = function(name)
        feature.Services[name] = feature.Services[name] or {}
        addon.Services[name] = feature.Services[name]
        return feature.Services[name]
    end
    return addon
end

local function loadAddonFile(addon, path)
    local chunk = assert(loadfile(path))
    setfenv(
        chunk,
        setmetatable({
            select = select,
            LibStub = function(name, silent)
                assert(name == "LibGroupTalents-1.0", "unexpected library lookup")
                assert(silent == true, "library lookup should be silent")
                return fakeLGT
            end,
            GetTime = function()
                return now
            end,
            UnitGUID = function(unit)
                return ({ raid1 = "GUID-A", raid2 = "GUID-B" })[unit]
            end,
        }, { __index = _G })
    )
    chunk("!KRT", addon)
end

fakeLGT.snapshots.raid1 = {
    activeGroup = 1,
    numGroups = 2,
    role = "tank",
    groups = {
        [1] = {
            specName = "Feral Combat",
            t1 = 0,
            t2 = 55,
            t3 = 16,
            tabs = {
                [1] = { name = "Balance", icon = "Interface\\Icons\\spell_nature_starfall", points = 0 },
                [2] = { name = "Feral Combat", icon = "Interface\\Icons\\ability_druid_catform", points = 55 },
                [3] = { name = "Restoration", icon = "Interface\\Icons\\spell_nature_healingtouch", points = 16 },
            },
        },
        [2] = {
            specName = "Restoration",
            t1 = 11,
            t2 = 0,
            t3 = 60,
            tabs = {
                [1] = { name = "Balance", icon = "Interface\\Icons\\spell_nature_starfall", points = 11 },
                [2] = { name = "Feral Combat", icon = "Interface\\Icons\\ability_druid_catform", points = 0 },
                [3] = { name = "Restoration", icon = "Interface\\Icons\\spell_nature_healingtouch", points = 60 },
            },
        },
    },
}

local addon = newAddon()
loadAddonFile(addon, "!KRT/Services/SpecInspect.lua")

local service = assert(addon.Services.SpecInspect, "SpecInspect service must load")
local snapshot = assert(service:GetPlayerSpecSnapshot("Alice"), "Alice snapshot should be cached")
assert(snapshot.specName == "Feral Combat", "expected spec name from LibGroupTalents")
assert(snapshot.icon == "Interface\\Icons\\ability_druid_catform", "expected tree icon")
assert(snapshot.role == "TANK", "expected normalized tank role")

local rowSnapshot = service:GetUnitTalentSnapshot("raid1", { name = "Alice" }, "row_test", true)
assert(rowSnapshot ~= nil, "row table input should be handled by GetUnitTalentSnapshot")
assert(rowSnapshot.name == "Alice", "row table name should be normalized to Alice")
assert(rowSnapshot.specName == "Feral Combat", "row snapshot should expose active spec name")
assert(rowSnapshot.icon == "Interface\\Icons\\ability_druid_catform", "row snapshot should expose icon")

local talentSnapshot = assert(service:GetPlayerTalentSnapshot("Alice"), "Alice talent snapshot should be available")
assert(talentSnapshot.activeGroup == 1, "Alice active talent group should be captured")
assert(talentSnapshot.numGroups == 2, "Alice should expose both talent groups")
assert(talentSnapshot.specName == "Feral Combat", "active spec name should remain compatible")
assert(talentSnapshot.secondarySpecName == "Restoration", "secondary spec name should be captured")
assert(talentSnapshot.groups and talentSnapshot.groups[1], "active group details should be present")
assert(talentSnapshot.groups and talentSnapshot.groups[2], "secondary group details should be present")
assert(talentSnapshot.groups[1].specIcon == "Interface\\Icons\\ability_druid_catform", "active group icon should be captured")
assert(talentSnapshot.groups[2].specIcon == "Interface\\Icons\\spell_nature_healingtouch", "secondary group icon should be captured")
assert(talentSnapshot.groups[1].mainTalentTree == 2, "active group dominant tree should be Feral")
assert(talentSnapshot.groups[2].mainTalentTree == 3, "secondary group dominant tree should be Restoration")

fakeLGT.refreshed = {}
local result = service:RefreshRaidSpecs({ reason = "test" })
assert(result.refreshed >= 1, "missing player should request a library refresh")
assert(fakeLGT.refreshed[1] == "raid2", "Bob should be refreshed through LibGroupTalents")

fakeLGT.snapshots.raid2 = {
    specName = "Frost",
    role = "caster",
    t1 = 0,
    t2 = 0,
    t3 = 57,
    tabs = {
        [3] = { name = "Frost", icon = "Interface\\Icons\\spell_frost_frostbolt02" },
    },
}
fireLgt("LibGroupTalents_Update", "GUID-B", "raid2", "Frost", 0, 0, 57)
local bob = assert(service:GetPlayerSpecSnapshot("Bob"), "Bob snapshot should update from callback")
assert(bob.role == "DAMAGER", "caster role should normalize to DAMAGER")
assert(bob.icon == "Interface\\Icons\\spell_frost_frostbolt02", "expected callback refresh icon")
assert(busEvents._triggered and #busEvents._triggered > 0, "SpecInspectUpdated should be emitted")

fakeLGT.snapshots.raid3 = {
    raiseTalentError = true,
}
local ok, charlie = pcall(service.GetPlayerSpecSnapshot, service, "Charlie")
assert(ok, "GetPlayerSpecSnapshot should not leak LibGroupTalents errors")
assert(charlie == nil, "GetPlayerSpecSnapshot should return nil when talent reads fail")

print("spec inspect service spec passed")
