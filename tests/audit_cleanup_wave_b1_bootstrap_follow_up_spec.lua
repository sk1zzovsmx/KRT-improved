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

local init = read("!KRT/Init.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local architecture = read("docs/ARCHITECTURE.md")
local overview = read("docs/OVERVIEW.md")

local initOwnedContracts = {
    "addon.Database = addon.Database or {}",
    "addon.State = addon.State or {}",
    "addon.Events = addon.Events or {}",
    "addon.Controllers = addon.Controllers or {}",
    "addon.Services = addon.Services or {}",
    "addon.Widgets = addon.Widgets or {}",
    "addon.Bus = addon.Bus or {}",
    "function Database.GetFeatureShared()",
    "function Database.EnsureBootstrapEvents()",
    "function Database.RequestControllerMethod(name, methodName, ...)",
    "function Database.EnsureServiceNamespace(...)",
    "function Database.EnsureLootRuntimeState()",
    "function Database.NormalizeSavedVariablesAfterLoad()",
    "function Database.PrepareSavedVariablesForSave(contextTag)",
    "function addon:RegisterEvent(eventName)",
    "function addon:UnregisterEvent(eventName)",
    'mainFrame:SetScript("OnEvent", handleEvent)',
    'addon:RegisterEvent("ADDON_LOADED")',
    "function addon:ADDON_LOADED(name)",
    "function addon:PLAYER_LOGOUT()",
}

for i = 1, #initOwnedContracts do
    assertContains(init, initOwnedContracts[i])
end

local eventForwardingContracts = {
    "WowEvents.LootOpened",
    "WowEvents.LootClosed",
    "WowEvents.OpenMasterLootList",
    "WowEvents.UpdateMasterLootList",
    "WowEvents.ChatMsgWhisper",
    "WowEvents.ReadyCheck",
    "Bus.TriggerEvent(eventKey, ...)",
}

for i = 1, #eventForwardingContracts do
    assertContains(init, eventForwardingContracts[i])
end

local bootstrapSideEffects = {
    "addon.Options.EnsureLoaded()",
    "addon.Options.SetDebugEnabled(false)",
    'addon.Timer.BindMixin(addon, "Database")',
    "minimap:EnsureUI()",
    "reservesService:Load()",
    "addon.Comms:EnsureVersionPrefix()",
    "Database.NormalizeSavedVariablesAfterLoad()",
    "self:RAID_ROSTER_UPDATE(true)",
}

for i = 1, #bootstrapSideEffects do
    assertContains(init, bootstrapSideEffects[i])
end

local eventHandlerContracts = {
    "function addon:RAID_ROSTER_UPDATE(forceImmediate)",
    "function addon:RAID_INSTANCE_WELCOME(...)",
    "function addon:PLAYER_DIFFICULTY_CHANGED()",
    "function addon:UPDATE_INSTANCE_INFO()",
    "function addon:PLAYER_ENTERING_WORLD()",
    "function addon:CHAT_MSG_LOOT(msg)",
    "function addon:CHAT_MSG_SYSTEM(msg)",
    "function addon:START_LOOT_ROLL(rollId, rollTime)",
    "function addon:CHAT_MSG_ADDON(prefix, msg, channel, sender)",
    "function addon:CHAT_MSG_MONSTER_YELL(...)",
    "function addon:COMBAT_LOG_EVENT_UNFILTERED(...)",
}

for i = 1, #eventHandlerContracts do
    assertContains(init, eventHandlerContracts[i])
end

local addonMessageHandlers = {
    "addon.Comms:HandleVersionMessage(prefix, msg, channel, sender)",
    "reservesService:HandleSyncMessage(prefix, msg, channel, sender)",
    "lootService:HandleDistributionMessage(prefix, msg, channel, sender)",
    "syncer:OnAddonMessage(prefix, msg, channel, sender)",
}

for i = 1, #addonMessageHandlers do
    assertContains(init, addonMessageHandlers[i])
end

assertContains(init, "lootService:ObservePassiveLootMessage(msg, winnerOnly)")
assertContains(init, "lootService:AddGroupLootMessage(msg)")
assertContains(init, "lootService:AddLoot(msg, nil, nil, parsedLoot)")
assertContains(init, "rollsService:CHAT_MSG_SYSTEM(msg)")
assertContains(init, "lootService:AddPassiveLootRoll(rollId, rollTime)")
assertContains(init, "raidService:AddBoss(L.BossYells[text])")
assertContains(init, "raidService:COMBAT_LOG_EVENT_UNFILTERED(...)")
assertContains(init, "Bus.TriggerEvent(InternalEvents.RaidRosterDelta")

assertContains(backlog, "Wave B1 completed the bootstrap residual-owner inventory.")
assertContains(backlog, "no bootstrap block was proven safe to move out of `!KRT/Init.lua` in this pass.")
assertContains(backlog, "open a fresh inventory item only when a new owner-specific candidate is proven")
assertContains(backlog, "keep `!KRT/Init.lua` and `!KRT/Services/Reserves.lua` in hold without new call-site evidence")
assertContains(backlog, "no speculative splitting")
assertContains(backlog, "no event-wiring rewrite without evidence")
assertContains(backlog, "`!KRT/Modules/UI/Frames.lua`: cleanup wave U1 completed, monitor only")
assertContains(architecture, "`!KRT/Init.lua`")
assertContains(architecture, "Owns shared bootstrap namespaces")
assertContains(overview, "`Init.lua` also owns global WoW event wiring and bus forwarding.")

assertNotContains(init, "self.Raid")
assertNotContains(init, "addon.Master")
assertNotContains(init, "addon.Raid")
assertNotContains(init, "addon.Config")
assertNotContains(init, "addon.Frames")

print("audit cleanup wave B1 bootstrap follow-up source contract passed")
