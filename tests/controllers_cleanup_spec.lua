local function read(path)
    local file = assert(io.open(path, "r"))
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

local controllers = {
    "!KRT/Controllers/Master.lua",
    "!KRT/Controllers/Logger.lua",
    "!KRT/Controllers/Warnings.lua",
    "!KRT/Controllers/Spammer.lua",
}

for i = 1, #controllers do
    local path = controllers[i]
    local source = read(path)
    assertNotContains(source, ":SetScript(", path .. " must route script binding through Frames.SetScriptSafely")
    assertNotContains(source, "local UIScaffold = addon.UIScaffold", path .. " must localize UIScaffold from feature shared")
    assertNotContains(source, "local UIPrimitives = addon.UIPrimitives", path .. " must localize UIPrimitives from feature shared")
    assertContains(source, "local UIScaffold = feature.UIScaffold", path .. " must localize UIScaffold from feature shared")
    assertContains(source, "local UIPrimitives = feature.UIPrimitives", path .. " must localize UIPrimitives from feature shared")
    assertNotContains(source, "addon.Timer.BindMixin", path .. " must use the local Timer dependency")
end

local master = read("!KRT/Controllers/Master.lua")
assertNotContains(master, "module.PrepareDropDowns = prepareDropDowns", "Master dropdown preparation must stay private")
assertNotContains(master, "addon.options", "Master option reads must go through Options namespace helpers")
assertNotContains(master, "addon.Database.GetCurrentRaid", "Master current raid lookups must use the local Database dependency")
assertContains(master, "local UIFacade = feature.UI", "Master must localize UI facade from feature shared")
assertNotContains(master, "local UIFacade = addon.UI", "Master must not read UI facade from addon root")
assertNotContains(master, "addon.UIPrimitives or UIPrimitives", "Master must use the local UIPrimitives dependency")
assertContains(master, "local function getOption(namespace, key)", "Master must centralize namespace option reads")
assertContains(master, 'getOption("Master",', "Master namespace reads must use getOption")
assertContains(master, 'getOption("Loot",', "Loot namespace reads must use getOption")
assertContains(master, 'getOption("Rolls",', "Rolls namespace reads must use getOption")
assertContains(master, 'getOption("UI",', "UI namespace reads must use getOption")
assertNotContains(master, "local function getMasterOption", "Master must avoid extra option wrapper locals")

local logger = read("!KRT/Controllers/Logger.lua")
assertNotContains(logger, "Campi uniformi", "Logger comments must remain English-only")
assertContains(logger, "Uniform fields:", "Logger popup field comment must describe the fields in English")
assertNotContains(logger, "local LoggerSvc = addon.Services.Logger", "Logger must use the local Services dependency")
assertContains(logger, "local LoggerSvc = Services.Logger", "Logger must use the local Services dependency")

local warnings = read("!KRT/Controllers/Warnings.lua")
assertContains(warnings, "local function getWarningsStore()", "Warnings SavedVariables access must be centralized")
assertContains(warnings, "tremove(warnings, selectedID)", "Warnings delete must mutate the SavedVariables table in place")
assertNotContains(warnings, "KRT_Warnings = oldWarnings", "Warnings delete must not replace the SavedVariables table")

local spammer = read("!KRT/Controllers/Spammer.lua")
assertContains(spammer, "local function getSpammerStore()", "Spammer SavedVariables access must be centralized")

print("controllers cleanup source contract passed")
