local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    if not string.find(text, needle, 1, true) then
        error(message .. " (missing " .. needle .. ")", 2)
    end
end

local function assertNotContains(text, needle, message)
    if string.find(text, needle, 1, true) then
        error(message .. " (found " .. needle .. ")", 2)
    end
end

local logger = read("!KRT/Controllers/Logger.lua")
assertNotContains(logger, "local function getBossEmptyStateText", "old Logger boss empty-state helper must stay removed")
assertNotContains(logger, "local function getBossAttendeesEmptyStateText", "old Logger boss-attendee empty-state helper must stay removed")
assertNotContains(logger, "module._getSelectedRaidRecord = function", "old Logger selected-raid getter must stay removed")
assertNotContains(logger, "module._deleteSelectedAttendees = function", "old Logger attendee-delete helper must stay removed")
assertNotContains(logger, "module._needBoss = function", "old Logger selected-boss guard must stay removed")
assertNotContains(logger, "module._needLoot = function", "old Logger selected-loot guard must stay removed")
assertContains(logger, "local function getRaidAttendeesEmptyStateText", "active Logger raid-attendee empty-state helper must remain")
assertContains(logger, "module._needRaid = function", "active Logger selected-raid guard must remain")
assertContains(logger, "module._runWithSelectedRaid = function", "active Logger selected-raid action wrapper must remain")

local master = read("!KRT/Controllers/Master.lua")
assertNotContains(master, "function module._PendingCounter:CancelAward", "old pending counter CancelAward helper must stay removed")
assertNotContains(master, "function Private.GetLootSpamHeader", "old private loot spam header helper must stay removed")
assertNotContains(master, "Private.GetLootSpamHeader = function", "old private loot spam header helper must stay removed")
assertContains(master, "function module._PendingCounter:Remove", "active pending counter Remove helper must remain")
assertContains(master, "Private.AnnounceLootLinks = function", "active loot announce helper must remain")

local specInspect = read("!KRT/Services/SpecInspect.lua")
assertNotContains(specInspect, "local function buildSpecIcon", "old single-spec icon builder must stay removed")
assertContains(specInspect, "local function buildGroupSpecIcon", "active grouped spec icon builder must remain")

local events = read("!KRT/Modules/Events.lua")
assertNotContains(events, 'Internal.RaidLeave = "RaidLeave"', "unused RaidLeave internal event must stay removed")
assertContains(events, 'Internal.RaidRosterDelta = "RaidRosterDelta"', "active raid roster delta event must remain")

local constants = read("!KRT/Modules/C.lua")
assertNotContains(constants, "C.CHAT_PREFIX = ", "unused long chat prefix constant must stay removed")
assertNotContains(constants, "C.GROUP_LOOT_CONTEXT_REUSE_SECONDS = ", "unused group-loot reuse constant must stay removed")
assertNotContains(constants, "C.RESERVES_ROW_HEIGHT = ", "unused reserves row height constant must stay removed")
assertNotContains(constants, "C.RESERVE_HEADER_HEIGHT = ", "unused reserve header height constant must stay removed")
assertContains(constants, "C.CHAT_PREFIX_SHORT = ", "active short chat prefix constant must remain")
assertContains(constants, "C.CHAT_PREFIX_HEX = ", "active chat prefix color constant must remain")
assertContains(constants, "C.RESERVES_QUERY_COOLDOWN_SECONDS = ", "active reserves query cooldown constant must remain")

local actions = read("!KRT/Services/Logger/Actions.lua")
assertNotContains(actions, "local function removeFromList(", "helper used only by removed boss attendee API must stay removed")
assertNotContains(actions, "function Actions:DeleteBoss(", "old manual boss delete API must stay removed")
assertNotContains(actions, "function Actions:DeleteBossAttendee(", "old manual boss attendee delete API must stay removed")
assertNotContains(actions, "function Actions:UpsertBossKill(", "old manual boss upsert API must stay removed")
assertNotContains(actions, "function Actions:AddBossAttendee(", "old manual boss attendee add API must stay removed")
assertContains(actions, "function Actions:DeleteLootMany(", "active loot-delete API must remain")
assertContains(actions, "function Actions:DeleteRaidAttendeeMany(", "active raid-attendee delete API must remain")
assertContains(actions, "function Actions:SetLootEntry(", "active loot edit API must remain")
assertContains(actions, "function Actions:ResolveLootEditWinner(", "active loot winner resolver API must remain")
assertContains(actions, "function Actions:SetCurrentRaid(", "active current-raid API must remain")
assertContains(actions, "function Actions:RemoveRaidHistoryEntries(", "active raid history removal API must remain")

local localization = read("!KRT/Localization/localization.en.lua")
local removedLocalizationKeys = {
    "StrBosses",
    "StrConfirmDeleteBoss",
    "StrConfirmDeleteAttendee",
    "StrBossAttendees",
    "StrBossParticipation",
    "StrAddBoss",
    "StrEditBoss",
    "StrBossNameHelp",
    "StrBossDifficultyHelp",
    "StrBossTimeHelp",
    "ErrBossDifficulty",
    "ErrBossTime",
    "StrAddPlayer",
    "ErrAttendeesInvalidName",
    "ErrAttendeesInvalidRaidBoss",
    "ErrAttendeesPlayerExists",
    "StrAttendeesAddSuccess",
}

for i = 1, #removedLocalizationKeys do
    local key = removedLocalizationKeys[i]
    assertNotContains(localization, "L." .. key .. " =", "localization key tied to removed Logger boss/attendee API must stay removed: " .. key)
end

assertContains(localization, "L.StrRaidAttendees = ", "active raid attendee label must remain")
assertContains(localization, "L.StrConfirmDeleteItem = ", "active loot delete confirmation must remain")
assertContains(localization, "L.StrLoggerSharedSource = ", "active logger shared-source label must remain")

local raidQueries = read("!KRT/Database/DBRaidQueries.lua")
assertNotContains(raidQueries, "function module:ResolveLootLooterNid", "unused public RaidQueries looter nid resolver must stay removed")
assertContains(raidQueries, "local function resolveLootLooterNid", "private RaidQueries looter nid helper must remain")
assertContains(raidQueries, "function module:ResolveLootLooterName", "active RaidQueries looter name resolver must remain")
assertContains(raidQueries, "function module:ResolveLootLooterNameFromMap", "active RaidQueries looter map resolver must remain")

local syncer = read("!KRT/Database/DBSyncer.lua")
assertNotContains(syncer, "function module:GetPrefix", "unused public sync prefix getter must stay removed")
assertContains(syncer, 'local COMM_PREFIX = "KRTLogSync"', "active sync prefix constant must remain")
assertContains(syncer, "function module:GetProtocolVersion", "active sync protocol getter must remain")
assertContains(syncer, "function module:GetSyncMetrics", "active sync metrics getter must remain")
assertContains(syncer, "function module:ResetSyncMetrics", "active sync metrics reset must remain")
assertContains(syncer, "function module:OnAddonMessage", "active sync addon-message handler must remain")

local lootSourceCandidates = read("!KRT/Modules/LootSourceCandidates.lua")
assertNotContains(lootSourceCandidates, "function LootSourceCandidates.ParseLegacySharedText", "unused legacy shared-text parser wrapper must stay removed")
assertContains(lootSourceCandidates, "function LootSourceCandidates.IsLegacySharedText", "active legacy shared-text predicate must remain")
assertContains(lootSourceCandidates, "function LootSourceCandidates.ParseSharedText", "active shared-text parser must remain")
assertContains(lootSourceCandidates, "function LootSourceCandidates.Copy", "active loot source candidate copy helper must remain")
assertContains(lootSourceCandidates, "function LootSourceCandidates.BuildLootSourceModel", "active loot source model builder must remain")

local frames = read("!KRT/Modules/UI/Frames.lua")
assertNotContains(frames, "function ModuleState.ClearDirty", "unused ModuleState clear helper must stay removed")
assertContains(frames, "function ModuleState.Ensure", "active ModuleState Ensure helper must remain")
assertContains(frames, "function ModuleState.Get", "active ModuleState Get helper must remain")
assertContains(frames, "function ModuleState.Reset", "active ModuleState Reset helper must remain")
assertContains(frames, "function ModuleState.MarkDirty", "active ModuleState MarkDirty helper must remain")

local visuals = read("!KRT/Modules/UI/Visuals.lua")
assertNotContains(visuals, "function Primitives.SetNamedPartShown", "unused named-part show helper must stay removed")
assertContains(visuals, "function Primitives.SetShown", "active primitive show helper must remain")
assertContains(visuals, "function Primitives.SetEnabled", "active primitive enabled helper must remain")
assertContains(visuals, "function Primitives.SetNamedPartEnabled", "active named-part enabled helper must remain")
assertContains(visuals, "function Primitives.UpdateNamedPartModeText", "active named-part mode text helper must remain")

local lootHints = read("!KRT/Widgets/LootHints.lua")
assertNotContains(lootHints, "module.ApplyLootReserveUi = function", "unused LootHints reserve UI wrapper must stay removed")
assertContains(lootHints, "module.BuildLootReserveUiState = function", "active LootHints reserve state builder must remain")
assertContains(lootHints, "module.ApplyLootFrameReserveHints = function", "active LootFrame reserve hint applier must remain")
assertContains(lootHints, "module.ClearLootFrameReserveHints = function", "active LootFrame reserve hint clearer must remain")
assertContains(lootHints, "module.EnsureLootFrameHooks = function", "active LootFrame hook installer must remain")

print("dead code trim source contract passed")
