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

local luaFiles = {
    "!KRT/Init.lua",
    "!KRT/Modules/UI/Facade.lua",
    "!KRT/Modules/UI/Effects.lua",
    "!KRT/Modules/UI/Visuals.lua",
    "!KRT/Modules/UI/Frames.lua",
    "!KRT/Modules/UI/ListController.lua",
    "!KRT/Modules/UI/MultiSelect.lua",
    "!KRT/Modules/UI/OptionsLayout.lua",
    "!KRT/Modules/UI/ScreenNotice.lua",
    "!KRT/EntryPoints/Minimap.lua",
    "!KRT/EntryPoints/SlashEvents.lua",
    "!KRT/Controllers/Master.lua",
    "!KRT/Controllers/Logger.lua",
    "!KRT/Controllers/Warnings.lua",
    "!KRT/Controllers/Spammer.lua",
    "!KRT/Widgets/Config.lua",
    "!KRT/Widgets/LootCounter.lua",
    "!KRT/Widgets/ReservesUI.lua",
}

local legacyRoots = {
    "addon.Frames",
    "addon.UIScaffold",
    "addon.ListController",
    "addon.UIRowVisuals",
    "addon.UIPrimitives",
    "addon.UIEffects",
    "addon.OptionsLayout",
    "addon.MultiSelect",
    "feature.Frames",
    "feature.UIScaffold",
    "feature.ListController",
    "feature.UIRowVisuals",
    "feature.UIPrimitives",
    "feature.UIEffects",
    "feature.OptionsLayout",
    "feature.MultiSelect",
}

for i = 1, #luaFiles do
    local path = luaFiles[i]
    local source = read(path)
    for j = 1, #legacyRoots do
        assertNotContains(source, legacyRoots[j], path .. " must use feature.UI.* instead of " .. legacyRoots[j])
    end
    assertNotContains(source, "addon.UI:", path .. " must route widget facade calls through addon.UI.Widgets")
    assertNotContains(source, "UI:Call", path .. " must route widget facade calls through UI.Widgets")
    assertNotContains(source, "UI:IsEnabled", path .. " must route widget feature gates through UI.Widgets")
    assertNotContains(source, "UI:IsRegistered", path .. " must route widget registration checks through UI.Widgets")
    assertNotContains(source, "module._ui", path .. " must store lifecycle state through UI.ModuleState")
    assertNotContains(source, "Import._ui", path .. " must store import lifecycle state through UI.ModuleState")
    assertNotContains(source, "Box._ui", path .. " must store popup lifecycle state through UI.ModuleState")
    assertNotContains(source, "local UiRoot = feature.UI", path .. " must name the UI root local UI")
    assertNotContains(source, "_makeConfirmPopup", path .. " must define confirmation popups through UI.Popups")
end

local initSource = read("!KRT/Init.lua")
assertContains(initSource, "UI = addon.UI", "feature shared must expose the canonical UI root")
assertNotContains(initSource, "Frames = addon.Frames", "feature shared must not expose legacy Frames root")
assertNotContains(initSource, "UIScaffold = addon.UIScaffold", "feature shared must not expose legacy UIScaffold root")
assertNotContains(initSource, "ListController = addon.ListController", "feature shared must not expose legacy ListController root")

local facadeSource = read("!KRT/Modules/UI/Facade.lua")
assertContains(facadeSource, "UI.Widgets", "UI facade must own widget routing under UI.Widgets")

local framesSource = read("!KRT/Modules/UI/Frames.lua")
assertContains(framesSource, "UI.Frames", "Frames helpers must export through UI.Frames")
assertContains(framesSource, "UI.Scaffold", "Scaffold helpers must export through UI.Scaffold")
assertContains(framesSource, "UI.ModuleState", "Module lifecycle state must export through UI.ModuleState")
assertContains(framesSource, "UI.EditBoxes", "Editbox helpers must export through UI.EditBoxes")
assertContains(framesSource, "UI.Popups", "Popup helpers must export through UI.Popups")
assertContains(framesSource, "UI.Tooltips", "Tooltip helpers must export through UI.Tooltips")

local listsSource = read("!KRT/Modules/UI/ListController.lua")
assertContains(listsSource, "UI.Lists", "ListController must export through UI.Lists")

local visualsSource = read("!KRT/Modules/UI/Visuals.lua")
assertContains(visualsSource, "UI.Primitives", "Visual primitives must export through UI.Primitives")
assertContains(visualsSource, "UI.Rows", "Row visuals must export through UI.Rows")

local effectsSource = read("!KRT/Modules/UI/Effects.lua")
assertContains(effectsSource, "UI.Effects", "Effects must export through UI.Effects")

local optionsLayoutSource = read("!KRT/Modules/UI/OptionsLayout.lua")
assertContains(optionsLayoutSource, "UI.Layout", "Options layout must export through UI.Layout")

local screenNoticeSource = read("!KRT/Modules/UI/ScreenNotice.lua")
assertContains(screenNoticeSource, "UI.ScreenNotice", "Screen notice must export through UI.ScreenNotice")

local multiSelectSource = read("!KRT/Modules/UI/MultiSelect.lua")
assertContains(multiSelectSource, "UI.Selection", "MultiSelect must export through UI.Selection")

print("ui api namespace source contract passed")
