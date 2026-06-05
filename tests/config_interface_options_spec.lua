local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, pattern, message)
    assert(not text:find(pattern), message or ("unexpected pattern: " .. pattern))
end

local configLua = read("!KRT/Widgets/Config.lua")
local configXml = read("!KRT/UI/Config.xml")
local optionsLayoutLua = read("!KRT/Modules/UI/OptionsLayout.lua")
local toc = read("!KRT/!KRT.toc")
local localization = read("!KRT/Localization/localization.en.lua")
local diagnoseLog = read("!KRT/Localization/DiagnoseLog.en.lua")
local spammerLua = read("!KRT/Controllers/Spammer.lua")

assertContains(localization, "-- events: none", "Localization must document static string-table event behavior")
assert(not localization:find("-- events: document inbound/outbound events in module body", 1, true), "Localization must not keep the generic event placeholder")
assertContains(diagnoseLog, "-- events: none", "DiagnoseLog must document static diagnostic-template event behavior")
assert(not diagnoseLog:find("-- events: document inbound/outbound events in module body", 1, true), "DiagnoseLog must not keep the generic event placeholder")
assertContains(configXml, 'Frame name="KRTConfig"', "Custom KRT config popup must remain available")
assertNotContains(configLua, "addon%.options", "Config widget must use namespace cfg:Get/cfg:Set instead of addon.options")
assertNotContains(configXml, "AboutStr", "Custom KRT config popup must not show the old about footer")
assertNotContains(configLua, "StrConfigAbout", "Config widget must not localize the removed about footer")
assertNotContains(localization, "StrConfigAbout", "Localization must not keep the removed about footer")
assertContains(configXml, 'Frame name="KRTInterfaceOptionsPanel"', "Config XML must define the authoritative Blizzard Interface Options panel")
assertContains(configXml, 'Frame name="KRTInterfaceOptionsMasterLootPanel"', "Config XML must define a Master Loot Interface Options child panel")
assertContains(configXml, 'Frame name="KRTInterfaceOptionsLootHistoryPanel"', "Config XML must define a Loot History Interface Options child panel")
assertContains(configXml, 'Frame name="KRTInterfaceOptionsLFMSpamPanel"', "Config XML must define an LFM Spam Interface Options child panel")
assertContains(configXml, 'Frame name="KRTInterfaceOptionsRaidWarningPanel"', "Config XML must define a Raid Warning Interface Options child panel")
assertContains(configXml, 'Frame name="KRTInterfaceOptionsHelpPanel"', "Config XML must define a Help Interface Options child panel")
assertContains(configLua, "InterfaceOptions_AddCategory", "Config widget must register Blizzard Interface Options panels")
assertContains(configLua, "parent = L.StrConfigPanelTitle", "Child panels must register under KRT")
assertContains(toc, "Modules\\UI\\OptionsLayout.lua", "TOC must load the shared Interface Options layout renderer")
assertContains(configLua, "Modules/UI/OptionsLayout", "Config widget must declare the OptionsLayout dependency")
assertContains(configLua, "local OptionsLayout = feature.OptionsLayout", "Config widget must localize OptionsLayout from feature shared")
assert(not configLua:find("local OptionsLayout = addon.OptionsLayout", 1, true), "Config widget must not read OptionsLayout from addon root")
assertContains(configLua, "OptionsLayout.Apply", "Config widget must use the shared OptionsLayout renderer")
assertContains(optionsLayoutLua, "local commandX = leftX + textWidth + columnGap", "OptionsLayout must use a fixed right command column")
assertContains(optionsLayoutLua, "commandWidth", "OptionsLayout must reserve an explicit command-column width")
assertContains(optionsLayoutLua, "scrollChildWidth", "OptionsLayout must size scroll children from the layout contract")
assertContains(optionsLayoutLua, 'rowType == "check"', "OptionsLayout must support checkbox option rows")
assertContains(optionsLayoutLua, "local labelHeight", "OptionsLayout checkbox descriptions must be placed from label height")
assertContains(optionsLayoutLua, 'rowType == "command"', "OptionsLayout must support action rows")
assertContains(optionsLayoutLua, 'rowType == "editCommand"', "OptionsLayout must support editbox action rows")
assertContains(optionsLayoutLua, 'rowType == "dropdown"', "OptionsLayout must support dropdown rows")
assertContains(configLua, "layoutRootPanel", "Config widget must layout the KRT root panel through OptionsLayout")
assertContains(configLua, "layoutMasterLootPanel", "Config widget must layout Master Loot through OptionsLayout")
assertContains(configLua, "layoutLootHistoryPanel", "Config widget must layout Loot History through OptionsLayout")
assertContains(configLua, "layoutLFMSpamPanel", "Config widget must layout LFM Spam through OptionsLayout")
assertContains(configLua, "layoutRaidWarningPanel", "Config widget must layout Raid Warning through OptionsLayout")
assertContains(configLua, "layoutHelpPanel", "Config widget must layout Help through OptionsLayout")
assertNotContains(configXml, '<AbsDimension x="-28" y="0" />', "Interface Options scrollframes must not extend behind the panel border")
assertContains(configXml, '<AbsDimension x="-42" y="36" />', "Interface Options scrollframes must use a safe right/bottom inset")
assertContains(localization, 'L.StrConfigPanelTitle = "KRT"', "Interface Options panel must appear as KRT under AddOns")
assertContains(localization, 'L.StrConfigPanelHelp = "Help"', "Help child panel title must use localization")
assertContains(localization, 'L.StrConfigPanelMasterLoot = "Master Loot"', "Master Loot child panel title must use localization")
assertContains(localization, 'L.StrConfigPanelRaidWarning = "Raid Warning"', "Raid Warning child panel title must use localization")
assertContains(configLua, "registerInterfaceOptionsPanel", "Interface Options registration must be centralized and idempotent")
assertContains(configLua, "OptionsLoaded", "Interface Options panel must register after saved options load")
assertContains(configLua, "setConfigTitle(frameName, titleText, plainTitle)", "Interface Options titles must be able to skip the KRT title prefix")
assertContains(
    configLua,
    "localizeConfigControls(masterLootContentFrameName, L.StrConfigPanelMasterLoot, true)",
    "Master Loot Interface Options panel must show a plain title without the KRT prefix"
)
assertContains(
    configLua,
    'local masterLootContentFrameName = "KRTInterfaceOptionsMasterLootPanelScrollChild"',
    "Config widget must bind the Interface Options controls from the Master Loot scroll child"
)
assertContains(configLua, "localizeHelpPanel", "Config widget must localize the Help Interface Options child panel")
assertContains(
    configLua,
    "local countdownDurationValues = { 3, 5, 7, 10, 13, 15, 20, 25, 30, 40, 50, 60 }",
    "Countdown duration slider must use the requested discrete duration ladder"
)
assertContains(configLua, "normalizeCountdownDuration", "Countdown duration slider must snap raw slider values to an allowed duration")
assertContains(configLua, "slider:SetValueStep(1)", "Countdown duration slider must use unit slider steps before snapping to the duration ladder")
assertContains(configXml, 'minValue="3.0" maxValue="60.0" defaultValue="5.0" valueStep="1.0"', "Countdown duration sliders must expose the full 3-60 second range")
assertNotContains(configXml, 'valueStep="5.0"', "Countdown duration sliders must not keep fixed 5-second steps")

local expectedControls = {
    "sortAscending",
    "useRaidWarning",
    "countdownSimpleRaidMsg",
    "announceOnWin",
    "announceOnHold",
    "announceOnBank",
    "announceOnDisenchant",
    "lootWhispers",
    "softResWhisperReplies",
    "countdownRollsBlock",
    "screenReminder",
    "ignoreStacks",
    "showTooltips",
    "showLootCounterDuringMSRoll",
    "minimapButton",
    "countdownDuration",
}

local expectedDescriptions = {
    { "sortAscending", "SortAscending" },
    { "useRaidWarning", "UseRaidWarning" },
    { "countdownSimpleRaidMsg", "CountdownSimpleRaidMsg" },
    { "announceOnWin", "AnnounceOnWin" },
    { "announceOnHold", "AnnounceOnHold" },
    { "announceOnBank", "AnnounceOnBank" },
    { "announceOnDisenchant", "AnnounceOnDisenchant" },
    { "lootWhispers", "LootWhisper" },
    { "softResWhisperReplies", "SoftResWhisperReplies" },
    { "countdownRollsBlock", "CountdownRollsBlock" },
    { "screenReminder", "ScreenReminder" },
    { "ignoreStacks", "IgnoreStacks" },
    { "showTooltips", "ShowTooltips" },
    { "showLootCounterDuringMSRoll", "ShowLootCounterDuringMSRoll" },
    { "minimapButton", "MinimapButton" },
    { "countdownDuration", "CountdownDuration" },
}

local panelStart = assert(configXml:find('Frame name="KRTInterfaceOptionsPanel"', 1, true), "Config XML must define the authoritative KRT Interface Options panel")
local rootPanelEnd = assert(configXml:find('Frame name="KRTInterfaceOptionsMasterLootPanel"', panelStart, true), "Config XML must define Master Loot after the KRT parent panel")
local rootPanelXml = configXml:sub(panelStart, rootPanelEnd - 1)
assertNotContains(rootPanelXml, "sortAscending", "KRT root panel must not contain Master Loot settings")
assertContains(rootPanelXml, "$parentOverviewTitle", "KRT root panel must title the addon overview")
assertContains(rootPanelXml, "$parentWhatTitle", "KRT root panel must explain what the addon does")
assertContains(rootPanelXml, "$parentHowTitle", "KRT root panel must explain how the addon works")
assertContains(rootPanelXml, "$parentWhyTitle", "KRT root panel must explain why to use it")
assertContains(configLua, "localizeRootPanel", "Config widget must localize the KRT root panel")
assertContains(localization, "L.StrConfigRootWhatTitle", "Localization must define root-panel What title")
assertContains(localization, "L.StrConfigRootHowTitle", "Localization must define root-panel How title")
assertContains(localization, "L.StrConfigRootWhyTitle", "Localization must define root-panel Why title")

local masterLootPanelStart = assert(configXml:find('Frame name="KRTInterfaceOptionsMasterLootPanel"', 1, true), "Config XML must define the Master Loot Interface Options panel")
local masterLootPanelEnd =
    assert(configXml:find('Frame name="KRTInterfaceOptionsLootHistoryPanel"', masterLootPanelStart, true), "Loot History panel must follow Master Loot in Config XML")
local masterLootFrameXml = configXml:sub(masterLootPanelStart, masterLootPanelEnd - 1)
local scrollFrameStart =
    assert(masterLootFrameXml:find('ScrollFrame name="$parentScrollFrame"', 1, true), "Master Loot Interface Options panel must place its controls inside a scroll frame")
local scrollChildStart = assert(
    masterLootFrameXml:find('Frame name="KRTInterfaceOptionsMasterLootPanelScrollChild"', scrollFrameStart, true),
    "Master Loot Interface Options panel must expose a scroll child for controls"
)
local masterLootPanelXml = masterLootFrameXml:sub(scrollChildStart)

for i = 1, #expectedControls do
    local suffix = expectedControls[i]
    assertContains(masterLootPanelXml, "$parent" .. suffix, "Master Loot panel XML must replicate " .. suffix)
end

local expectedMasterLootWidgets = {
    "PresetsTitle",
    "DefaultsPresetTitle",
    "DefaultsPresetDesc",
    "QuietPresetTitle",
    "QuietPresetDesc",
    "StandardPresetTitle",
    "StandardPresetDesc",
    "VerbosePresetTitle",
    "VerbosePresetDesc",
    "QuietPresetBtn",
    "StandardPresetBtn",
    "VerbosePresetBtn",
    "AnnouncementPreviewTitle",
    "AnnouncementPreviewBody",
}

for i = 1, #expectedMasterLootWidgets do
    local suffix = expectedMasterLootWidgets[i]
    assertContains(masterLootPanelXml, "$parent" .. suffix, "Master Loot panel XML must include " .. suffix)
end

assertContains(configLua, "ApplyMasterLootPreset", "Config widget must support Master Loot option presets")
assertContains(configLua, "updateMasterLootPreview", "Config widget must refresh the Master Loot announcement preview")
assertContains(localization, "L.StrConfigMasterLootPresetsTitle", "Localization must define Master Loot preset title")
assertContains(localization, "L.StrConfigMasterLootPresetDefaultsDesc", "Localization must describe the Defaults preset row")
assertContains(localization, "L.StrConfigMasterLootPresetQuietDesc", "Localization must describe the Quiet preset row")
assertContains(localization, "L.StrConfigMasterLootPresetStandardDesc", "Localization must describe the Standard preset row")
assertContains(localization, "L.StrConfigMasterLootPresetVerboseDesc", "Localization must describe the Verbose preset row")
assertContains(configLua, 'setText(frameName, "DefaultsPresetDesc"', "Config widget must localize Defaults preset description")
assertContains(configLua, 'setText(frameName, "QuietPresetDesc"', "Config widget must localize Quiet preset description")
assertContains(configLua, 'setText(frameName, "StandardPresetDesc"', "Config widget must localize Standard preset description")
assertContains(configLua, 'setText(frameName, "VerbosePresetDesc"', "Config widget must localize Verbose preset description")
assertContains(localization, "L.StrConfigMasterLootAnnouncementPreviewTitle", "Localization must define Master Loot preview title")
assertContains(configXml, '<AbsDimension x="390" y="24" />', "Default Interface option descriptions must remain tall enough for wrapped text")
assertContains(configXml, "KRTConfigCompactDescriptionFontStringTemplate", "Master Loot must use an explicit compact description template")
assertContains(configXml, '<AbsDimension x="390" y="18" />', "Compact Master Loot descriptions must use one-line spacing")
assertContains(masterLootPanelXml, 'inherits="KRTConfigCompactDescriptionFontStringTemplate"', "Master Loot descriptions must opt into compact spacing")
assertContains(configLua, 'type = "command"', "Master Loot presets must be rendered as command rows")
assertContains(configLua, 'button = "DefaultsBtn"', "Master Loot Defaults preset must use the fixed command column")
assertContains(configLua, 'button = "QuietPresetBtn"', "Master Loot Quiet preset must use the fixed command column")
assertContains(configLua, 'button = "StandardPresetBtn"', "Master Loot Standard preset must use the fixed command column")
assertContains(configLua, 'button = "VerbosePresetBtn"', "Master Loot Verbose preset must use the fixed command column")
assertNotContains(configLua, 'relativeTo="$parentDefaultsPresetDesc" relativePoint="BOTTOMLEFT"', "Config widget layout must not depend on wrapped preset description height")
assertContains(configLua, "textWidth = 240", "Config widget must keep the command column inside the AddOns viewport")
assertContains(configLua, "commandWidth = 105", "Config widget must reserve a compact stable command column")
assertContains(configLua, "columnGap = 12", "Config widget must keep a visible gap between text and command columns")

local customConfigStart = assert(configXml:find('Frame name="KRTConfig"', 1, true), "Config XML must define the custom config popup")
local customConfigEnd = assert(configXml:find("End of Config Frame", customConfigStart, true), "Config XML must mark the end of the custom config popup")
local customConfigXml = configXml:sub(customConfigStart, customConfigEnd)

for i = 1, #expectedDescriptions do
    local suffix = expectedDescriptions[i][1]
    local localizationSuffix = expectedDescriptions[i][2]
    assertContains(masterLootPanelXml, "$parent" .. suffix .. "Desc", "Master Loot panel XML must explain " .. suffix)
    assertContains(configLua, suffix .. 'Desc", L.StrConfig' .. localizationSuffix .. "Desc", "Config widget must localize " .. suffix .. " description")
    assertContains(localization, "L.StrConfig" .. localizationSuffix .. "Desc", "Localization must define " .. suffix .. " description")
    assertNotContains(customConfigXml, suffix .. "Desc", "Custom config popup must not include " .. suffix .. " description")
end

local helpPanelStart = assert(configXml:find('Frame name="KRTInterfaceOptionsHelpPanel"', 1, true), "Config XML must define the Help Interface Options panel")
local helpScrollStart = assert(configXml:find('ScrollFrame name="$parentScrollFrame"', helpPanelStart, true), "Help Interface Options panel must be scrollable")
local helpScrollChildStart =
    assert(configXml:find('Frame name="KRTInterfaceOptionsHelpPanelScrollChild"', helpScrollStart, true), "Help Interface Options panel must expose a scroll child")
local helpPanelXml = configXml:sub(helpScrollChildStart)

local lootHistoryPanelStart = assert(configXml:find('Frame name="KRTInterfaceOptionsLootHistoryPanel"', 1, true), "Config XML must define the Loot History Interface Options panel")
local lootHistoryPanelEnd =
    assert(configXml:find('Frame name="KRTInterfaceOptionsLFMSpamPanel"', lootHistoryPanelStart, true), "LFM Spam panel must follow Loot History in Config XML")
local lootHistoryFrameXml = configXml:sub(lootHistoryPanelStart, lootHistoryPanelEnd - 1)
local lootHistoryScrollStart =
    assert(lootHistoryFrameXml:find('ScrollFrame name="$parentScrollFrame"', 1, true), "Loot History Interface Options panel must place maintenance commands inside a scroll frame")
local lootHistoryScrollChildStart = assert(
    lootHistoryFrameXml:find('Frame name="KRTInterfaceOptionsLootHistoryPanelScrollChild"', lootHistoryScrollStart, true),
    "Loot History Interface Options panel must expose a scroll child for maintenance commands"
)
local lootHistoryPanelXml = lootHistoryFrameXml:sub(lootHistoryScrollChildStart)

local expectedLootHistoryCommands = {
    { "ScanHistory", "ScanHistoryBtn" },
    { "PurgeHistory", "PurgeHistoryBtn" },
    { "RebuildSources", "RebuildSourcesBtn" },
    { "CleanUp", "CleanUpBtn" },
}

for i = 1, #expectedLootHistoryCommands do
    local textSuffix = expectedLootHistoryCommands[i][1]
    local buttonSuffix = expectedLootHistoryCommands[i][2]
    assertContains(lootHistoryPanelXml, "$parent" .. textSuffix .. "Title", "Loot History panel XML must title " .. textSuffix)
    assertContains(lootHistoryPanelXml, "$parent" .. textSuffix .. "Desc", "Loot History panel XML must describe " .. textSuffix)
    assertContains(lootHistoryPanelXml, "$parent" .. buttonSuffix, "Loot History panel XML must expose " .. buttonSuffix)
    assertContains(configLua, "StrConfigLootHistory" .. textSuffix .. "Title", "Config widget must localize " .. textSuffix .. " title")
    assertContains(configLua, "StrConfigLootHistory" .. textSuffix .. "Desc", "Config widget must localize " .. textSuffix .. " description")
    assertContains(localization, "L.StrConfigLootHistory" .. textSuffix .. "Title", "Localization must define " .. textSuffix .. " title")
    assertContains(localization, "L.StrConfigLootHistory" .. textSuffix .. "Desc", "Localization must define " .. textSuffix .. " description")
end

assertContains(configLua, "bindLootHistoryPanel", "Config widget must bind Loot History maintenance commands")
assertContains(configLua, "RequestLoggerMaintenance", "Config widget must route Loot History maintenance through one helper")
assertContains(configLua, "GetRaidHistoryScan", "Config widget must support Loot History scan/status actions")
assertContains(lootHistoryPanelXml, "$parentReportTitle", "Loot History panel XML must title the report first")
assertContains(lootHistoryPanelXml, "$parentReportSummary", "Loot History panel XML must show the report summary")
assertContains(lootHistoryPanelXml, "$parentDataHealthTitle", "Loot History panel XML must separate data-health commands from the report")
assertContains(configLua, "refreshLootHistoryReport", "Config widget must refresh the report on panel open and maintenance actions")
assertContains(configLua, "formatLootHistoryReport", "Config widget must format the visible Loot History report")
assertContains(lootHistoryPanelXml, "$parentSyncTitle", "Loot History panel XML must include a sync section between report and data health")
assertContains(lootHistoryPanelXml, "$parentPersistentSyncCheck", "Loot History panel XML must expose persistent sync checkbox")
assertContains(lootHistoryPanelXml, "$parentIgnoreGroupLootCheck", "Loot History panel XML must expose Ignore GroupLoot checkbox")
assertContains(lootHistoryPanelXml, "$parentIgnoreSelectionThresholdCheck", "Loot History panel XML must expose raid-threshold override checkbox")
assertContains(lootHistoryPanelXml, "$parentLoggerLootQualityDropDown", "Loot History panel XML must expose Logger Loot Quality dropdown")
assertContains(lootHistoryPanelXml, "UIDropDownMenuTemplate", "Loot History quality selector must use the Blizzard dropdown template")
assertContains(lootHistoryPanelXml, '<AbsDimension x="125" y="32" />', "Loot History quality selector must fit inside the visible panel")
assertContains(lootHistoryPanelXml, '<AbsDimension x="260" y="8" />', "Loot History quality selector must use the safe fixed control column")
local loggerLootQualityDropDownStart =
    assert(lootHistoryPanelXml:find('<Frame name="$parentLoggerLootQualityDropDown"', 1, true), "Loot History panel must define Logger Loot Quality dropdown")
local loggerLootQualityDropDownEnd = assert(lootHistoryPanelXml:find("</Frame>", loggerLootQualityDropDownStart, true), "Logger Loot Quality dropdown XML must close")
local loggerLootQualityDropDownXml = lootHistoryPanelXml:sub(loggerLootQualityDropDownStart, loggerLootQualityDropDownEnd)
assertContains(
    loggerLootQualityDropDownXml,
    'relativeTo="$parentLoggerLootQualityDesc" relativePoint="TOPLEFT"',
    "Loot History quality selector must be anchored from the text column origin"
)
assertNotContains(loggerLootQualityDropDownXml, 'relativePoint="TOPRIGHT"', "Loot History quality selector must not calculate its position from the description right edge")
assertNotContains(loggerLootQualityDropDownXml, '<AbsDimension x="%-', "Loot History quality selector must not overlap the description with a negative X offset")
assertContains(lootHistoryPanelXml, "$parentRequireDatabaseEditBox", "Loot History panel XML must expose Require Database target editbox")
assertContains(lootHistoryPanelXml, "$parentPushDatabaseEditBox", "Loot History panel XML must expose Push Database target editbox")
assertContains(lootHistoryPanelXml, "$parentSyncNowBtn", "Loot History panel XML must expose Sync Now button")
assertContains(lootHistoryPanelXml, "$parentRequireDatabaseBtn", "Loot History panel XML must expose Require Database action")
assertContains(lootHistoryPanelXml, "$parentPushDatabaseBtn", "Loot History panel XML must expose Push Database action")
local requireDatabaseTitleStart = assert(lootHistoryPanelXml:find('<FontString name="$parentRequireDatabaseTitle"', 1, true), "Loot History panel must title Require Database")
local requireDatabaseTitleEnd = assert(lootHistoryPanelXml:find("</FontString>", requireDatabaseTitleStart, true), "Require Database title XML must close")
local requireDatabaseTitleXml = lootHistoryPanelXml:sub(requireDatabaseTitleStart, requireDatabaseTitleEnd)
assertNotContains(requireDatabaseTitleXml, '<AbsDimension x="%-34"', "Require Database title must not be shifted outside the visible Loot History command column")
assertContains(
    lootHistoryPanelXml,
    '<Anchor point="TOPLEFT" relativeTo="$parentSyncNowDesc" relativePoint="BOTTOMLEFT">',
    "Loot History Data Health heading must follow the sync controls"
)
assertContains(configLua, "RequestLoggerSyncPanelAction", "Config widget must route Loot History sync commands")
assertContains(configLua, "persistentSync", "Config widget must bind persistent sync option")
assertContains(configLua, "ignoreGroupLoot", "Config widget must bind ignore GroupLoot option")
assertContains(configLua, "ignoreSelectionThreshold", "Config widget must bind raid-threshold override option")
assertContains(configLua, "loggerLootQualityThreshold", "Config widget must bind Logger Loot Quality threshold option")
assertContains(configLua, "layoutLootHistoryPanel", "Loot History panel must use the shared options layout")
assertContains(configLua, 'type = "dropdown"', "Loot History quality selector must use a fixed dropdown row")
assertContains(configLua, 'dropdown = "LoggerLootQualityDropDown"', "Loot History dropdown must be assigned to the fixed command column")
assertContains(configLua, 'type = "editCommand"', "Loot History sync target commands must use editbox command rows")
assertContains(configLua, 'editBox = "RequireDatabaseEditBox"', "Require Database editbox must be assigned to the fixed command column")
assertContains(configLua, 'editBox = "PushDatabaseEditBox"', "Push Database editbox must be assigned to the fixed command column")
assertContains(configLua, "UIDropDownMenu_SetWidth(loggerLootQualityDropDown, 72)", "Loot History quality dropdown display width must fit the panel")
assertContains(configLua, "UIDropDownMenu_SetButtonWidth(loggerLootQualityDropDown, 92)", "Loot History quality dropdown button width must fit the panel")
assertContains(localization, "L.StrConfigLootHistorySyncTitle", "Localization must title the Loot History sync section")
assertContains(localization, "L.StrConfigLootHistoryPersistentSync", "Localization must define persistent sync checkbox")
assertContains(localization, "L.StrConfigLootHistoryIgnoreGroupLoot", "Localization must define Ignore GroupLoot checkbox")
assertContains(localization, 'L.StrConfigLootHistoryIgnoreSelectionThreshold = "Override raid loot threshold"', "Localization must label the raid-threshold override clearly")
assertContains(localization, "L.StrConfigLootHistoryIgnoreSelectionThresholdDesc", "Localization must describe the raid-threshold override")
assertContains(localization, "L.StrConfigLootHistoryLoggerLootQuality", "Localization must define Logger Loot Quality dropdown label")
assertContains(localization, "L.StrConfigLootHistoryRequireDatabaseTitle", "Localization must define Require Database command")
assertContains(localization, "L.StrConfigLootHistoryPushDatabaseTitle", "Localization must define Push Database command")
assertNotContains(configLua, "BuildRaidHistoryBackup", "Loot History panel must not expose the old backup builder")
assertNotContains(lootHistoryPanelXml, "ExportBackup", "Loot History panel must not expose backup controls")
assertNotContains(lootHistoryPanelXml, "BackupOutput", "Loot History panel must not expose a backup output box")
assertContains(configXml, 'Frame name="KRTLootHistoryCleanupPopup"', "Loot History cleanup must use a custom checkbox popup")
assertContains(configXml, "$parentEmptyRaidsCheck", "Loot History cleanup popup must expose Empty Raid checkbox")
assertContains(configXml, "$parentNonEpicLootCheck", "Loot History cleanup popup must expose Non Epic Loot checkbox")
assertContains(configXml, "$parentNoBossEncounterCheck", "Loot History cleanup popup must expose No Boss Encounter checkbox")
assertContains(configXml, "$parentEmptyRaidsDesc", "Loot History cleanup popup must describe Empty Raid cleanup")
assertContains(configXml, "$parentNonEpicLootDesc", "Loot History cleanup popup must describe Non Epic Loot cleanup")
assertContains(configXml, "$parentNoBossEncounterDesc", "Loot History cleanup popup must describe No Boss Encounter cleanup")
assertContains(configXml, "$parentDeleteBtn", "Loot History cleanup popup must expose a Delete button")
assertContains(configLua, "layoutCleanupPopup", "Loot History cleanup popup must use the shared options layout")
assertContains(configLua, 'buttons = { "DeleteBtn", "CancelBtn" }', "Cleanup popup buttons must use a stable button row")
local cleanupPopupStart = assert(configXml:find('<Frame name="KRTLootHistoryCleanupPopup"', 1, true), "Cleanup popup XML must exist")
local cleanupPopupXml = configXml:sub(cleanupPopupStart)
assertContains(cleanupPopupXml, '<AbsDimension x="380" y="340" />', "Cleanup popup must be tall enough for three two-line cleanup options")
assertContains(cleanupPopupXml, '<AbsDimension x="292" y="34" />', "Cleanup popup descriptions must have a stable text column")
local function extractCleanupPopupBlock(tagName, objectName)
    local blockStart = assert(cleanupPopupXml:find("<" .. tagName .. ' name="' .. objectName .. '"', 1, true), "Cleanup popup must define " .. objectName)
    local blockEnd = assert(cleanupPopupXml:find("</" .. tagName .. ">", blockStart, true), "Cleanup popup block must close")
    return cleanupPopupXml:sub(blockStart, blockEnd)
end

local emptyRaidsLabelXml = extractCleanupPopupBlock("FontString", "$parentEmptyRaidsLabel")
local nonEpicLootLabelXml = extractCleanupPopupBlock("FontString", "$parentNonEpicLootLabel")
local noBossEncounterLabelXml = extractCleanupPopupBlock("FontString", "$parentNoBossEncounterLabel")
local emptyRaidsCheckXml = extractCleanupPopupBlock("CheckButton", "$parentEmptyRaidsCheck")
local nonEpicLootCheckXml = extractCleanupPopupBlock("CheckButton", "$parentNonEpicLootCheck")
local noBossEncounterCheckXml = extractCleanupPopupBlock("CheckButton", "$parentNoBossEncounterCheck")

assertContains(emptyRaidsLabelXml, 'relativeTo="$parentBody"', "Cleanup popup first option label must start below the body text")
assertContains(nonEpicLootLabelXml, 'relativeTo="$parentEmptyRaidsDesc"', "Cleanup popup second option label must follow the first description")
assertContains(noBossEncounterLabelXml, 'relativeTo="$parentNonEpicLootDesc"', "Cleanup popup third option label must follow the second description")
assertContains(emptyRaidsCheckXml, 'relativeTo="$parentEmptyRaidsLabel"', "Cleanup popup Empty Raid checkbox must align to its own label")
assertContains(nonEpicLootCheckXml, 'relativeTo="$parentNonEpicLootLabel"', "Cleanup popup Non Epic checkbox must align to its own label")
assertContains(noBossEncounterCheckXml, 'relativeTo="$parentNoBossEncounterLabel"', "Cleanup popup No Boss checkbox must align to its own label")
assertContains(configLua, "bindCleanupPopup", "Config widget must bind the cleanup popup")
assertContains(configLua, "showCleanupPopup", "Config widget must show the cleanup popup from the panel")
assertContains(configLua, "formatCleanupOptionLabel", "Cleanup popup must show preview counts beside each option")
assertContains(configLua, "scanCleanupPreview", "Cleanup popup must scan current history before it opens")
assertContains(configLua, "RemoveRaidHistoryEntries", "Config widget must route cleanup through logger actions")
assertContains(configLua, 'RequestLoggerMaintenance("cleanUp"', "Cleanup popup must call the cleanup maintenance action")
assertNotContains(configLua, "KRT_CONFIG_DELETE_EMPTY_RAIDS", "Cleanup must replace the old delete-empty confirmation")
assertNotContains(lootHistoryPanelXml, '<AbsDimension x="350" y="3" />', "Loot History buttons must not be clipped off the panel edge")
assertNotContains(lootHistoryPanelXml, '<AbsDimension x="325"', "Loot History descriptions must fit the clipped Blizzard AddOns panel")
assertNotContains(lootHistoryPanelXml, '<AbsDimension x="455"', "Loot History wide widgets must fit the clipped Blizzard AddOns panel")
assertContains(lootHistoryPanelXml, '<AbsDimension x="250" y="34" />', "Loot History sync command descriptions must reserve a safe text column")
assertContains(lootHistoryPanelXml, '<AbsDimension x="250" y="54" />', "Loot History maintenance descriptions must reserve a safe text column")
assertContains(lootHistoryPanelXml, '<AbsDimension x="105" y="25" />', "Loot History command buttons must use the compact button column")
assertContains(lootHistoryPanelXml, '<AbsDimension x="365" y="116" />', "Loot History report must reserve enough space for all report rows")
assertNotContains(lootHistoryPanelXml, '<AbsDimension x="335"', "Loot History controls must not use the clipped legacy control column")
assertContains(lootHistoryPanelXml, '<AbsDimension x="0" y="-12" />', "Loot History section gaps must use compact spacing")
assertContains(lootHistoryPanelXml, '<AbsDimension x="0" y="-14" />', "Loot History command groups must use compact spacing")
assertNotContains(lootHistoryPanelXml, '<AbsDimension x="0" y="-18" />', "Loot History must not keep loose section gaps")
assertNotContains(lootHistoryPanelXml, '<AbsDimension x="0" y="-20" />', "Loot History must not keep loose command gaps")
assertContains(
    lootHistoryPanelXml,
    '<Anchor point="TOPLEFT" relativeTo="$parentReportSummary" relativePoint="BOTTOMLEFT">',
    "Loot History Data Health heading must follow the report"
)
assertContains(
    lootHistoryPanelXml,
    '<Anchor point="TOPLEFT" relativeTo="$parentScanHistoryDesc" relativePoint="TOPLEFT">',
    "Loot History scan button must use the fixed control column"
)
assertContains(
    lootHistoryPanelXml,
    '<Anchor point="TOPLEFT" relativeTo="$parentPurgeHistoryDesc" relativePoint="TOPLEFT">',
    "Loot History purge button must use the fixed control column"
)
assertContains(
    lootHistoryPanelXml,
    '<Anchor point="TOPLEFT" relativeTo="$parentRebuildSourcesDesc" relativePoint="TOPLEFT">',
    "Loot History rebuild button must use the fixed control column"
)
assertContains(
    lootHistoryPanelXml,
    '<Anchor point="TOPLEFT" relativeTo="$parentCleanUpDesc" relativePoint="TOPLEFT">',
    "Loot History cleanup button must use the fixed control column"
)
assertNotContains(lootHistoryPanelXml, 'relativeTo="$parentScanHistoryBtn"', "Loot History text must not anchor to buttons")
assertNotContains(lootHistoryPanelXml, 'relativeTo="$parentPurgeHistoryBtn"', "Loot History text must not anchor to buttons")
assertNotContains(lootHistoryPanelXml, 'relativeTo="$parentRebuildSourcesBtn"', "Loot History text must not anchor to buttons")
assertNotContains(lootHistoryPanelXml, 'relativeTo="$parentCleanUpBtn"', "Loot History text must not anchor to buttons")
assertContains(configLua, "KRT_CONFIG_PURGE_LOOT_HISTORY", "Purge history command must require a confirmation popup")
assertContains(localization, "L.MsgLoggerHistoryPurged", "Localization must report purge results")
assertContains(localization, "L.MsgLoggerLootSourcesRebuilt", "Localization must report source rebuild results")
assertContains(localization, "L.MsgLoggerCleanupDone", "Localization must report cleanup results")
assertContains(localization, "L.StrConfigLootHistoryCleanupEmptyRaidsDesc", "Localization must describe empty-raid cleanup")
assertContains(localization, "L.StrConfigLootHistoryCleanupNonEpicLootDesc", "Localization must describe non-epic cleanup")
assertContains(localization, "L.StrConfigLootHistoryCleanupNoBossEncounterDesc", "Localization must describe no-boss cleanup")
assertContains(localization, "L.MsgLoggerHistoryScanned", "Localization must report scan results")
assertContains(localization, "L.StrConfigLootHistoryReportTitle", "Localization must title the Loot History report")
assertContains(localization, "L.StrConfigLootHistoryReportSummary", "Localization must format the Loot History report")
assertNotContains(localization, "L.MsgLoggerBackupBuilt", "Localization must not keep backup output messaging")
assertNotContains(localization, "Build backup", "Localization must not expose the old backup label")

local lfmPanelStart = assert(configXml:find('Frame name="KRTInterfaceOptionsLFMSpamPanel"', 1, true), "Config XML must define LFM Spam panel")
local lfmPanelEnd = assert(configXml:find('Frame name="KRTInterfaceOptionsRaidWarningPanel"', lfmPanelStart, true), "Raid Warning panel must follow LFM Spam in Config XML")
local lfmFrameXml = configXml:sub(lfmPanelStart, lfmPanelEnd - 1)
local lfmScrollStart = assert(lfmFrameXml:find('ScrollFrame name="$parentScrollFrame"', 1, true), "LFM Spam panel must be scrollable")
local lfmScrollChildStart = assert(lfmFrameXml:find('Frame name="KRTInterfaceOptionsLFMSpamPanelScrollChild"', lfmScrollStart, true), "LFM Spam panel must expose a scroll child")
local lfmPanelXml = lfmFrameXml:sub(lfmScrollChildStart)

local expectedLfmWidgets = {
    "MessagePreviewTitle",
    "MessagePreviewBody",
    "SafetyTitle",
    "SafetyBody",
    "OpenBtn",
    "StartBtn",
    "StopBtn",
    "RefreshPreviewBtn",
    "ClearPreviewBtn",
}

for i = 1, #expectedLfmWidgets do
    local suffix = expectedLfmWidgets[i]
    assertContains(lfmPanelXml, "$parent" .. suffix, "LFM Spam panel XML must include " .. suffix)
end

assertContains(configLua, "layoutLFMSpamPanel", "LFM Spam panel must use the shared options layout")
assertContains(configLua, 'buttons = { "RefreshPreviewBtn", "ClearPreviewBtn" }', "LFM Spam preview buttons must share one fixed row")
assertContains(configLua, 'buttons = { "OpenBtn", "StartBtn", "StopBtn" }', "LFM Spam action buttons must share one fixed row")

local retiredLfmPresetWidgets = {
    "PresetsTitle",
    "PresetsBody",
    "ICC10PresetBtn",
    "ICC25PresetBtn",
    "VoAPresetBtn",
}

for i = 1, #retiredLfmPresetWidgets do
    local suffix = retiredLfmPresetWidgets[i]
    assertNotContains(lfmPanelXml, "%$parent" .. suffix, "LFM Spam panel XML must not keep preset widget " .. suffix)
end

assertContains(configLua, "bindLFMSpamPanel", "Config widget must bind LFM Spam panel commands")
assertContains(configLua, "RequestSpammerPanelAction", "Config widget must route LFM Spam panel actions")
assertContains(configLua, "RequestClear", "Config widget must route the LFM Spam clear command")
assertContains(configLua, '"ClearPreviewBtn"', "LFM Spam clear command must be present in the options layout")
assertNotContains(configLua, "RequestApplyPreset", "Config widget must not route retired LFM Spam presets")
assertNotContains(spammerLua, "RequestApplyPreset", "Spammer controller must not expose retired LFM Spam presets")
assertNotContains(localization, "L.StrConfigLFMSpamPresetsTitle", "Localization must not define retired LFM Spam preset title")
assertNotContains(localization, "L.StrConfigLFMSpamPresetsBody", "Localization must not define retired LFM Spam preset copy")
assertNotContains(localization, "L.BtnConfigPresetICC10", "Localization must not define retired ICC 10 preset button")
assertNotContains(localization, "L.BtnConfigPresetICC25", "Localization must not define retired ICC 25 preset button")
assertNotContains(localization, "L.BtnConfigPresetVoA", "Localization must not define retired VoA preset button")
assertContains(localization, "L.StrConfigLFMSpamSafetyBody", "Localization must define LFM Spam safety copy")

local raidWarningPanelStart = assert(configXml:find('Frame name="KRTInterfaceOptionsRaidWarningPanel"', 1, true), "Config XML must define Raid Warning panel")
local raidWarningPanelEnd = assert(configXml:find('Frame name="KRTInterfaceOptionsHelpPanel"', raidWarningPanelStart, true), "Help panel must follow Raid Warning in Config XML")
local raidWarningFrameXml = configXml:sub(raidWarningPanelStart, raidWarningPanelEnd - 1)
local raidWarningScrollStart = assert(raidWarningFrameXml:find('ScrollFrame name="$parentScrollFrame"', 1, true), "Raid Warning panel must be scrollable")
local raidWarningScrollChildStart =
    assert(raidWarningFrameXml:find('Frame name="KRTInterfaceOptionsRaidWarningPanelScrollChild"', raidWarningScrollStart, true), "Raid Warning panel must expose a scroll child")
local raidWarningPanelXml = raidWarningFrameXml:sub(raidWarningScrollChildStart)

local expectedRaidWarningWidgets = {
    "TemplatesTitle",
    "TemplatesBody",
    "PreviewTitle",
    "PreviewBody",
    "PermissionTitle",
    "PermissionBody",
    "MaintenanceTitle",
    "ClearSavedTitle",
    "ClearSavedDesc",
    "OpenBtn",
    "PreviewBtn",
    "ClearSavedBtn",
}

for i = 1, #expectedRaidWarningWidgets do
    local suffix = expectedRaidWarningWidgets[i]
    assertContains(raidWarningPanelXml, "$parent" .. suffix, "Raid Warning panel XML must include " .. suffix)
end

assertContains(configLua, "bindRaidWarningPanel", "Config widget must bind Raid Warning panel commands")
assertContains(configLua, "RequestRaidWarningPanelAction", "Config widget must route Raid Warning panel actions")
assertContains(configLua, "KRT_CONFIG_CLEAR_RAID_WARNINGS", "Raid Warning clear command must require a confirmation popup")
assertContains(configLua, "RequestClearSavedWarnings", "Config widget must route saved-warning cleanup")
assertNotContains(configLua, "RequestEnsureDefaultTemplates", "Config widget must not expose a manual Add Templates command")
assertNotContains(raidWarningPanelXml, "$parentAddTemplatesBtn", "Raid Warning panel XML must remove the Add Templates button")
assertContains(localization, "L.StrConfigRaidWarningTemplatesTitle", "Localization must define Raid Warning template title")
assertContains(localization, "L.StrConfigRaidWarningPermissionBody", "Localization must define Raid Warning permission copy")
assertContains(localization, "L.StrConfigRaidWarningClearSavedTitle", "Localization must title the clear saved warnings command")
assertContains(localization, "L.StrConfigRaidWarningClearSavedDesc", "Localization must describe the clear saved warnings command")
assertContains(localization, "L.StrConfirmClearRaidWarnings", "Localization must define the clear saved warnings confirmation")
assertContains(localization, "L.MsgRaidWarningsCleared", "Localization must report cleared saved warnings")
assertNotContains(localization, "L.BtnConfigAddTemplates", "Localization must not keep the retired Add Templates button")
assertNotContains(localization, "L.MsgRaidWarningTemplatesAdded", "Localization must not report retired manual template installs")
assertContains(configLua, "layoutRaidWarningPanel", "Raid Warning panel must use the shared options layout")
assertContains(configLua, 'buttons = { "PreviewBtn", "OpenBtn" }', "Raid Warning template buttons must share one fixed row")
assertContains(configLua, 'button = "ClearSavedBtn"', "Raid Warning clear command must use the fixed command column")
assertContains(configLua, 'desc = "ClearSavedDesc"', "Raid Warning clear command must keep text in the left column")

local expectedHelpWidgets = {
    "MasterLootTitle",
    "MasterLootBody",
    "LootHistoryTitle",
    "LootHistoryBody",
    "LFMSpamTitle",
    "LFMSpamBody",
    "RaidWarningTitle",
    "RaidWarningBody",
    "CommandPermissionsTitle",
    "CommandPermissionsBody",
    "DiagnosticsTitle",
    "DiagnosticsBody",
}

for i = 1, #expectedHelpWidgets do
    local suffix = expectedHelpWidgets[i]
    assertContains(helpPanelXml, "$parent" .. suffix, "Help panel XML must include " .. suffix)
end

assertContains(helpPanelXml, '<AbsDimension x="0" y="-10" />', "Help panel sections must use compact spacing")
assertContains(helpPanelXml, '<AbsDimension x="0" y="-4" />', "Help panel title/body pairs must use compact spacing")
assertContains(helpPanelXml, '<AbsDimension x="430"', "Help panel bodies must use a safe text width")
assertNotContains(helpPanelXml, '<AbsDimension x="455"', "Help panel bodies must not exceed the visible AddOns panel")
assertContains(localization, "/krt ach [link]: print achievement ID.", "Help command copy must keep LFM lines short")
assertNotContains(helpPanelXml, '<AbsDimension x="0" y="-16" />', "Help panel must not keep loose section gaps")
assertNotContains(configXml, '<AbsDimension x="455"', "Interface Options text blocks must not exceed the safe Blizzard AddOns width")

local expectedHelpCommands = {
    "/krt ml",
    "/krt counter",
    "/krt config reset",
    "/krt logger",
    "/krt attendance",
    "/krt logger req",
    "/krt logger push",
    "/krt logger sync",
    "/krt lfm",
    "/krt lfm start",
    "/krt lfm stop",
    "/krt ach",
    "/krt rw",
    "/krt rw [ID]",
    "Master Looter:",
    "Raid leader or assistant:",
    "/krt bug",
    "/krt version",
}

for i = 1, #expectedHelpCommands do
    local command = expectedHelpCommands[i]
    assertContains(localization, command, "Help localization must document " .. command)
end

assertNotContains(configXml, "<Scripts>", "Config XML must stay layout-only")
assertNotContains(configXml, "<On[A-Za-z]+>", "Config XML must not contain inline script handlers")

print("config interface options source contract passed")
