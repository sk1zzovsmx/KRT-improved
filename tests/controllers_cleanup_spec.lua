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

local function assertContainsAny(text, needles, message)
    for i = 1, #needles do
        if text:find(needles[i], 1, true) then
            return
        end
    end
    assert(false, message)
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
    assertContains(source, "local UI = feature.UI", path .. " must localize UI root from feature shared")
    assertNotContains(source, "addon.UIScaffold", path .. " must not use legacy UIScaffold root")
    assertNotContains(source, "addon.UIPrimitives", path .. " must not use legacy UIPrimitives root")
    assertNotContains(source, "feature.UIScaffold", path .. " must not use legacy UIScaffold feature field")
    assertNotContains(source, "feature.UIPrimitives", path .. " must not use legacy UIPrimitives feature field")
    assertNotContains(source, "addon.Timer.BindMixin", path .. " must use the local Timer dependency")
end

local master = read("!KRT/Controllers/Master.lua")
assertNotContains(master, "module.PrepareDropDowns = prepareDropDowns", "Master dropdown preparation must stay private")
assertNotContains(master, "addon.options", "Master option reads must go through Options namespace helpers")
assertNotContains(master, "addon.Database.GetCurrentRaid", "Master current raid lookups must use the local Database dependency")
assertContains(master, "local UI = feature.UI", "Master must localize UI root from feature shared")
assertNotContains(master, "local UIFacade = addon.UI", "Master must not read UI facade from addon root")
assertNotContains(master, "addon.UIPrimitives or UIPrimitives", "Master must use the UI.Primitives dependency")
assertContains(master, "local function getOption(namespace, key)", "Master must centralize namespace option reads")
assertContains(master, 'getOption("Master",', "Master namespace reads must use getOption")
assertContains(master, 'getOption("Loot",', "Loot namespace reads must use getOption")
assertContains(master, 'getOption("Rolls",', "Rolls namespace reads must use getOption")
assertContains(master, 'getOption("UI",', "UI namespace reads must use getOption")
assertNotContains(master, "local function getMasterOption", "Master must avoid extra option wrapper locals")
assertContains(master, "Rows.DrawMasterRollRow(row, data, onRollRowClick)", "Master roll row rendering must delegate to shared row visuals")
assertNotContains(master, "getRollRowRefs = function", "Master must not keep local roll row part lookup glue")
assertNotContains(master, "nameStr:SetVertexColor", "Master must not own roll row color rendering")

local logger = read("!KRT/Controllers/Logger.lua")
assertNotContains(logger, "Campi uniformi", "Logger comments must remain English-only")
assertContains(logger, "Uniform fields:", "Logger popup field comment must describe the fields in English")
assertNotContains(logger, "local LoggerSvc = addon.Services.Logger", "Logger must use the local Services dependency")
assertContains(logger, "local LoggerSvc = Services.Logger", "Logger must use the local Services dependency")
assertContains(logger, "local Popups = UI.Popups", "Logger must localize the shared popup helper")
assertContains(logger, 'Popups.ShowConfirm("KRTLOGGER_DELETE_RAID"', "Logger raid deletes must use shared confirm popups")
assertContains(logger, 'Popups.ShowConfirm("KRTLOGGER_DELETE_BOSS"', "Logger boss deletes must use shared confirm popups")
assertContains(logger, 'Popups.ShowConfirm("KRTLOGGER_DELETE_ATTENDEE"', "Logger boss-attendee deletes must use shared confirm popups")
assertContains(logger, 'Popups.ShowConfirm("KRTLOGGER_DELETE_RAIDATTENDEE"', "Logger raid-attendee deletes must use shared confirm popups")
assertContains(logger, 'Popups.ShowConfirm("KRTLOGGER_DELETE_ITEM"', "Logger item deletes must use shared confirm popups")
assertNotContains(logger, 'StaticPopup_Show("KRTLOGGER_DELETE', "Logger delete confirms must not call StaticPopup_Show directly")
assertContains(logger, 'Popups.ShowEditBox("KRTLOGGER_ITEM_EDIT_WINNER"', "Logger winner edit popup must use shared editbox popup helper")
assertContains(logger, 'Popups.ShowEditBox("KRTLOGGER_ITEM_EDIT_VALUE"', "Logger roll-value edit popup must use shared editbox popup helper")
assertNotContains(logger, 'StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER"', "Logger winner edit popup must not call StaticPopup_Show directly")
assertNotContains(logger, 'StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE"', "Logger roll-value edit popup must not call StaticPopup_Show directly")
assertNotContains(logger, 'UI.Popups.DefineEditBox("KRTLOGGER_ITEM_EDIT', "Logger item edit popups must be opened through Popups.ShowEditBox")
assertNotContains(logger, "StaticPopup", "Logger popup actions must go through shared UI.Popups helpers")

local warnings = read("!KRT/Controllers/Warnings.lua")
assertContains(warnings, "local function getWarningsStore()", "Warnings SavedVariables access must be centralized")
assertContains(warnings, "tremove(warnings, selectedID)", "Warnings delete must mutate the SavedVariables table in place")
assertNotContains(warnings, "KRT_Warnings = oldWarnings", "Warnings delete must not replace the SavedVariables table")

local spammer = read("!KRT/Controllers/Spammer.lua")
assertContains(spammer, "local function getSpammerStore()", "Spammer SavedVariables access must be centralized")

print("controllers cleanup source contract passed")
