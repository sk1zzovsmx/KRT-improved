local callbacks = {}
local busEvents = {}
local now = 1000

local fakeLGT = {
    refreshed = {},
    snapshots = {},
}

function fakeLGT:GetUnitTalentSpec(unit)
    local row = self.snapshots[unit]
    if not row then
        return nil
    end
    return row.specName, row.t1 or 0, row.t2 or 0, row.t3 or 0
end

function fakeLGT:GetTalentTabInfo(unit, tab)
    local row = self.snapshots[unit]
    if not row or not row.tabs then
        return nil
    end
    local data = row.tabs[tab]
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
            return ({ Alice = "raid1", Bob = "raid2" })[name] or "none"
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
    specName = "Feral Combat",
    role = "tank",
    t1 = 0,
    t2 = 55,
    t3 = 16,
    tabs = {
        [2] = { name = "Feral Combat", icon = "Interface\\Icons\\ability_druid_catform" },
    },
}

local addon = newAddon()
loadAddonFile(addon, "!KRT/Services/SpecInspect.lua")

local service = assert(addon.Services.SpecInspect, "SpecInspect service must load")
local snapshot = assert(service:GetPlayerSpecSnapshot("Alice"), "Alice snapshot should be cached")
assert(snapshot.specName == "Feral Combat", "expected spec name from LibGroupTalents")
assert(snapshot.icon == "Interface\\Icons\\ability_druid_catform", "expected tree icon")
assert(snapshot.role == "TANK", "expected normalized tank role")

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

print("spec inspect service spec passed")
