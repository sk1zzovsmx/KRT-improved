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

local function assertNoSingularServiceToken(text, message)
    assert(not text:find("%f[%w_]Service%f[^%w_]"), message or "unexpected singular Service token")
end

local reserves = read("!KRT/Services/Reserves.lua")
local moduleRegistry = read("tests/module_registry_services_spec.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

assertContains(reserves, "local module = Reserves")
assertNotContains(reserves, "local Service = module")
assertNoSingularServiceToken(reserves, "Reserves.lua must not keep singular Service facade owner references")
assertNotContains(reserves, "function Service:")
assertNotContains(reserves, "Service:")

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
    "IsSourceCollapsed",
    "ToggleSourceCollapsed",
    "RequestSyncMetadata",
    "HandleSyncMessage",
    "HasPendingItem",
}

for i = 1, #publicMethods do
    local methodName = publicMethods[i]
    assertContains(reserves, "function module:" .. methodName .. "(", "missing Reserves public method: " .. methodName)
end

assertContains(reserves, "function Sync:GetPayload()")
assertContains(reserves, "function Sync:SetSyncedData(sourceData, meta)")
assertContains(reserves, "function module:GetSyncPayload()")
assertContains(reserves, "function module:SetSyncedData(sourceData, meta)")

assertNotContains(reserves, "CreateFrame(")
assertNotContains(reserves, "GameTooltip")
assertNotContains(reserves, "addon.Widgets")
assertNotContains(reserves, "addon.Controllers")

assertContains(moduleRegistry, 'name = "Services/Reserves",\n        path = "!KRT/Services/Reserves.lua",\n        owner = "module",')
assertContains(backlog, "Wave S3 completed: Reserves Service facade owner normalization")

print("audit cleanup wave s3 reserves source contract passed")
