local function newAddon()
    local addon = {
        Services = {},
        Database = {},
    }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
    }
    addon.Database.GetFeatureShared = function()
        return feature
    end
    return addon, feature
end

local addon = newAddon()
local function loadAddonFile(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
    chunk("!KRT", addon)
end

loadAddonFile("!KRT/Services/Master/AssignmentCandidates.lua")
loadAddonFile("!KRT/Services/Master/AssignmentTargets.lua")
loadAddonFile("!KRT/Services/Master/DebugRaidGrid.lua")
loadAddonFile("!KRT/Services/Master/Service.lua")

local AssignmentCandidates = addon.Services.Master.AssignmentCandidates
local AssignmentTargets = addon.Services.Master.AssignmentTargets
local DebugRaidGrid = addon.Services.Master.DebugRaidGrid
local Master = addon.Services.Master

local rows = AssignmentCandidates.BuildRows({
    { name = "Alice", index = 1 },
    { name = "Bob", index = 2 },
}, function(name)
    if name == "Alice" then
        return "MAGE"
    end
    return "PRIEST"
end)

assert(#rows == 2, "expected candidate rows")
assert(rows[1].name == "Alice", "expected first candidate name")
assert(rows[1].displayName == "Alice", "expected first candidate display name")
assert(rows[1].index == 1, "expected first candidate index")
assert(rows[1].class == "MAGE", "expected class provider result")

local debugRows, total = DebugRaidGrid.BuildRows(3, {
    { name = "Cara", class = "ROGUE" },
})
assert(total == 3, "expected debug count")
assert(#debugRows == 3, "expected roster row plus fake fillers")
assert(debugRows[1].name == "Cara", "expected real roster row first")
assert(debugRows[1].realRoster == true, "expected roster flag")
assert(debugRows[1].debugOnly == true, "expected debug flag")
assert(debugRows[2].name == "Player1", "expected fake filler")

local targetRows = AssignmentTargets.BuildRows({
    [2] = { Bob = "Bob" },
    [1] = { Alice = "Alice" },
}, function(name)
    if name == "Bob" then
        return "PRIEST"
    end
    return "MAGE"
end)
assert(#targetRows == 2, "expected target rows")
assert(targetRows[1].name == "Alice", "expected rows sorted by group then name")
assert(targetRows[1].group == 1, "expected group on target row")
assert(targetRows[2].name == "Bob", "expected second sorted row")

assert(DebugRaidGrid.GetTargetCount({ raidGridTargetCount = 12 }) == 12, "expected debug count")
assert(DebugRaidGrid.GetTargetCount({}) == 25, "expected default debug count")
assert(DebugRaidGrid.IsFallbackEnabled({ raidGridTargetCount = 12 }, false) == true, "expected state flag")
assert(DebugRaidGrid.IsFallbackEnabled({}, true) == true, "expected debug flag")
assert(DebugRaidGrid.IsFallbackEnabled({}, false) == false, "expected disabled fallback")
assert(Master.BuildAssignmentCandidateRows({ { name = "Cara" } })[1].name == "Cara", "expected facade rows")
assert(Master.GetDebugRaidGridTargetCount({}) == 25, "expected facade debug count")

print("master assignment service spec passed")
