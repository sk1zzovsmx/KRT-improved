local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function readOptional(path)
    local file = io.open(path, "r")
    if not file then
        return ""
    end
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local toc = read("!KRT/!KRT.toc")
local lootSourceCandidatesSource = read("!KRT/Modules/LootSourceCandidates.lua")
local lootSourcesSource = read("!KRT/Modules/LootSources.lua")
local lootSourcesDataSource = read("!KRT/Modules/Dataset/LootSourcesData.lua")
local assignmentHelpers = readOptional("!KRT/Services/Master/AssignmentHelpers.lua")
local assignmentCandidates = read("!KRT/Services/Master/AssignmentCandidates.lua")
local assignmentTargets = read("!KRT/Services/Master/AssignmentTargets.lua")

assertContains(lootSourceCandidatesSource, "function LootSourceCandidates.GetModeSignature(modes)", "LootSourceCandidates should export shared mode-signature helper")
assertContains(lootSourcesSource, "local LootSourceCandidates = feature.LootSourceCandidates", "LootSources should localize LootSourceCandidates from feature shared")
assertContains(lootSourcesDataSource, "local LootSourceCandidates = feature.LootSourceCandidates", "LootSourcesData should localize LootSourceCandidates from feature shared")
assertContains(lootSourcesSource, "LootSourceCandidates.GetModeSignature(candidate and candidate.modes)", "LootSources should call shared mode-signature helper")
assertContains(lootSourcesDataSource, "LootSourceCandidates.GetModeSignature(source and source.modes)", "LootSourcesData should call shared mode-signature helper")
assertNotContains(lootSourcesSource, "local function getModeSignature(modes)", "LootSources should not keep local mode-signature helper")
assertNotContains(lootSourcesDataSource, "local function getModeSignature(modes)", "LootSourcesData should not keep local mode-signature helper")
assertContains(toc, "Services\\Master\\AssignmentHelpers.lua", "TOC should load Master assignment helpers before assignment row modules")
assertContains(assignmentHelpers, "-- exports: addon.Services.Master.AssignmentHelpers", "AssignmentHelpers should document its Master helper export")
assertContains(assignmentHelpers, "function AssignmentHelpers.ResolveClass(classProvider, name)", "AssignmentHelpers should own class-provider resolution")
assertContains(assignmentCandidates, "local AssignmentHelpers = Master.AssignmentHelpers", "AssignmentCandidates should localize AssignmentHelpers")
assertContains(assignmentTargets, "local AssignmentHelpers = Master.AssignmentHelpers", "AssignmentTargets should localize AssignmentHelpers")
assertContains(assignmentCandidates, "AssignmentHelpers.ResolveClass(classProvider, name)", "AssignmentCandidates should use shared class resolution")
assertContains(assignmentTargets, "AssignmentHelpers.ResolveClass(classProvider, name)", "AssignmentTargets should use shared class resolution")
assertNotContains(assignmentCandidates, "local function getClass(classProvider, name)", "AssignmentCandidates should not keep the duplicated local class helper")
assertNotContains(assignmentTargets, "local function getClass(classProvider, name)", "AssignmentTargets should not keep the duplicated local class helper")

print("audit cleanup wave3 source contract passed")
