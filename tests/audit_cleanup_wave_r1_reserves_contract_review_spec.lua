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

local reserves = read("!KRT/Services/Reserves.lua")
local architecture = read("docs/ARCHITECTURE.md")
local overview = read("docs/OVERVIEW.md")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")
local slash = read("!KRT/EntryPoints/SlashEvents.lua")
local init = read("!KRT/Init.lua")
local master = read("!KRT/Controllers/Master.lua")
local reservesUi = read("!KRT/Widgets/ReservesUI.lua")
local lootHints = read("!KRT/Widgets/LootHints.lua")
local rollsService = read("!KRT/Services/Rolls/Service.lua")
local rollsResponses = read("!KRT/Services/Rolls/Responses.lua")

local publicMethods = {
    "GetCounts",
    "Save",
    "Load",
    "ClearSavedReserves",
    "HasData",
    "IsLocalDataAvailable",
    "HasItemReserves",
    "GetNameAliases",
    "SetNameAlias",
    "RemoveNameAlias",
    "GetPlayerReserveEntries",
    "GetImportMode",
    "SetImportMode",
    "IsPlusSystem",
    "ParseImport",
    "ApplyImport",
    "RequestApplyImport",
    "QueryItemInfo",
    "QueryMissingItems",
    "GetReserveCountForItem",
    "GetPlusForItem",
    "SetPlayerReserveQuantity",
    "SetPlayerReservePlus",
    "RemovePlayerReserve",
    "HasCurrentRaidPlayersForItem",
    "GetItemReserveContext",
    "GetReadinessReport",
    "GetPlayersForItem",
    "FormatReservedPlayersLine",
    "GetDisplayList",
    "GetSyncMetadata",
    "GetSyncPayload",
    "SetSyncedData",
    "DeleteSyncedReservesCache",
    "RequestSyncMetadata",
    "HandleSyncMessage",
    "HasPendingItem",
}

for i = 1, #publicMethods do
    local methodName = publicMethods[i]
    local methodNeedle = "function module:" .. methodName .. "("
    local missingMessage = "missing documented Reserves facade method: " .. methodName
    assertContains(reserves, methodNeedle, missingMessage)
end
assertNotContains(reserves, "function module:IsSourceCollapsed(", "source collapse API should no longer be on Reserves facade")
assertNotContains(reserves, "function module:ToggleSourceCollapsed(", "source collapse API should no longer be on Reserves facade")
assertNotContains(reserves, "collapsedBossGroups", "source collapse source state should no longer exist in Reserves service contract")

assertContains(reserves, "function Sync:GetPayload()")
assertContains(reserves, "function Sync:SetSyncedData(sourceData, meta)")
assertContains(reserves, "function module:GetSyncPayload()")
assertContains(reserves, "function module:SetSyncedData(sourceData, meta)")

assertContains(backlog, "deeper `!KRT/Services/Reserves.lua` review only for proven package-internal contracts")
local backlogAliasContract = table.concat({
    "alias, collapse, readiness, and display methods ",
    "are currently real slash/UI/controller contracts",
})
assertContains(backlog, backlogAliasContract)
local backlogDefaultNextStep = table.concat({
    "hold further `!KRT/Services/Reserves.lua` contraction unless ",
    "a fresh inventory proves a package-internal-only method",
})
assertContains(backlog, backlogDefaultNextStep)
assertContains(overview, "For reserves, use `addon.Services.Reserves` as the canonical public surface.")
assertContains(architecture, "External call sites use the parent facade for sync operations")
assertContains(architecture, "`HandleSyncMessage`, `GetSyncPayload`, `SetSyncedData`, and cache APIs")

assertContains(slash, "reserves:GetCounts()")
assertContains(slash, "reserves:GetReadinessReport(itemId)")
assertContains(slash, "reserves:SetNameAlias(reserveName, raidName)")
assertContains(slash, "reserves:RemoveNameAlias(reserveName)")
assertContains(slash, "reserves:GetNameAliases()")
assertContains(slash, "reserves:RequestSyncMetadata()")
assertContains(slash, "reserves:GetSyncMetadata()")
assertContains(slash, "reserves:DeleteSyncedReservesCache()")

assertContains(init, "reservesService:HandleSyncMessage(prefix, msg, channel, sender)")

assertContains(master, "reserves:HasData()")
assertContains(master, "reserves:FormatReservedPlayersLine(")
assertContains(master, "reserves:HasCurrentRaidPlayersForItem(itemId)")

assertContains(reservesUi, "collapsedItems[itemId]", "ReservesUI should keep item collapse as UI-local state")
assertContains(reservesUi, "reserveHeaderOnClick", "ReservesUI should collapse directly from the item header")
assertContains(reservesUi, "getDisplayList(Reserves)", "ReservesUI should render the Reserves display contract")
assertContains(reservesUi, "Reserves:QueryItemInfo(itemId)")
assertContains(reservesUi, "Reserves:QueryMissingItems(silent")
assertContains(reservesUi, "Reserves:ClearSavedReserves()")
assertContains(reservesUi, "Reserves:GetImportMode()")
assertContains(reservesUi, "Reserves:RequestApplyImport(parsed")
assertContains(reservesUi, "Reserves:ApplyImport(parsed")
assertContains(reservesUi, "Reserves:ParseImport(")
assertContains(reservesUi, "Reserves:SetImportMode(mode, true)")
assertContains(reservesUi, "Reserves:HasPendingItem(itemId)")

assertContains(lootHints, "reserves:GetPlayersForItem(itemId")

assertContains(rollsService, "reserves:GetReserveCountForItem(itemId, name)")
assertContains(rollsService, "reserves:GetPlusForItem(itemId, name)")
assertContains(rollsService, "reserves:GetItemReserveContext(itemId)")
assertContains(rollsService, "reserves:IsPlusSystem()")
assertContains(rollsResponses, "reserves:GetPlayersForItem(itemId")

assertNotContains(slash, "._Sync")
assertNotContains(init, "._Sync")
assertNotContains(master, "._Display")
assertNotContains(reservesUi, "._Display")
assertNotContains(lootHints, "._Display")
assertNotContains(rollsService, "reserves._Display")
assertNotContains(rollsResponses, "._Display")

print("audit cleanup wave R1 Reserves contract review source contract passed")
