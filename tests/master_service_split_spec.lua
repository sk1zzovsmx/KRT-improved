local function newAddon()
    local addon = {
        Services = {},
        Database = {},
    }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
        L = {
            BtnBank = "Bank",
            BtnDisenchant = "DE",
            BtnHold = "Hold",
            StrAutoLootSuggestionSkipLogger = "Skip logger",
            StrMasterSessionTieSummary = "Tie: %s",
            StrMasterSessionWinnerSummary = "Winner: %s",
            StrMasterStatusAwardSelection = "Award %d selected",
            StrMasterStatusAwardTarget = "Award %s",
            StrMasterStatusCountdown = "Countdown",
            StrMasterStatusIdle = "Idle",
            StrMasterStatusInventory = "Inventory",
            StrMasterStatusInventorySelection = "Inventory %d selected",
            StrMasterStatusInventoryTarget = "Inventory target %s",
            StrMasterStatusMultiAward = "Multi %d/%d %s",
            StrMasterStatusPickWinner = "Pick winner",
            StrMasterStatusReady = "Ready",
            StrMasterStatusReadyWithSummary = "Ready: %s",
            StrMasterStatusResolveTie = "Resolve tie",
            StrMasterStatusRolling = "Rolling %d",
            StrMasterStatusRollingBypassed = "Rolling bypassed %d",
            StrMasterStatusRollingWithSummary = "Rolling %s %d",
            StrMasterStatusSelectWinners = "Select %d winners",
            StrMasterStatusSuggestion = "Suggestion %s",
            StrMasterStatusTrade = "Trade %s",
            StrRollSrSummaryFallback = "SR fallback",
            StrRollSrSummaryNoPresent = "No SR present",
            StrRollSrSummaryPresent = "%d SR present",
            StrRollSrSummaryPresentMissing = "%d SR present, %d missing",
        },
    }
    addon.Database.GetFeatureShared = function()
        return feature
    end
    return addon
end

local function loadAddonFile(addon, path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
    chunk("!KRT", addon)
end

local addon = newAddon()
loadAddonFile(addon, "!KRT/Services/Master/SoftRes.lua")
loadAddonFile(addon, "!KRT/Services/Master/SessionWinners.lua")
loadAddonFile(addon, "!KRT/Services/Master/FlowState.lua")
loadAddonFile(addon, "!KRT/Services/Master/ButtonState.lua")
loadAddonFile(addon, "!KRT/Services/Master/RollRows.lua")
loadAddonFile(addon, "!KRT/Services/Master/AssignmentCandidates.lua")
loadAddonFile(addon, "!KRT/Services/Master/AssignmentTargets.lua")
loadAddonFile(addon, "!KRT/Services/Master/DebugRaidGrid.lua")
loadAddonFile(addon, "!KRT/Services/Master/AwardMessages.lua")
loadAddonFile(addon, "!KRT/Services/Master/LootSpam.lua")
loadAddonFile(addon, "!KRT/Services/Master/Service.lua")

local Master = addon.Services.Master

local workflowState = Master.BuildWorkflowState({
    hasItem = true,
    hasLootAccess = true,
    lootState = {
        lootCount = 1,
        rollsCount = 0,
    },
    autoLootSuggestion = {
        action = "hold",
    },
})
assert(workflowState.name == "suggestion", "expected facade workflow delegation")
assert(workflowState.statusText == "Suggestion Hold", "expected suggestion label from FlowState")

local srText = Master.BuildSrSummaryText({}, {
    srContext = {
        eligibleReserveCount = 2,
        totalReserveCount = 3,
    },
})
assert(srText == "2 SR present, 1 missing", "expected SoftRes summary delegation")

local winnerModel = Master.BuildSessionWinnersModel({
    resolution = {
        autoWinners = {
            { name = "Alice", roll = 99 },
        },
        tiedNames = {
            "Bob",
        },
    },
})
assert(#winnerModel.rows == 2, "expected SessionWinners rows")
assert(winnerModel.summaryText == "Winner: Alice; Tie: Bob", "expected SessionWinners summary")

local candidateRows = Master.BuildAssignmentCandidateRows({
    { name = "Alice", index = 1 },
}, function()
    return "MAGE"
end)
assert(candidateRows[1].class == "MAGE", "expected candidate row delegation")

local targetRows = Master.BuildAssignmentTargetRows({
    [2] = { Bob = "Bob" },
    [1] = { Alice = "Alice" },
})
assert(targetRows[1].name == "Alice", "expected assignment target ordering")

local debugRows, total = Master.BuildDebugCandidateRows(2, {
    { name = "Cara", class = "ROGUE" },
})
assert(total == 2, "expected debug raid grid total")
assert(debugRows[1].realRoster == true, "expected debug raid grid roster row")

assert(Master.SoftRes, "expected SoftRes module")
assert(Master.SessionWinners, "expected SessionWinners module")
assert(Master.FlowState, "expected FlowState module")
assert(Master.ButtonState, "expected ButtonState module")
assert(Master.RollRows, "expected RollRows module")
assert(Master.AssignmentCandidates, "expected AssignmentCandidates module")
assert(Master.AssignmentTargets, "expected AssignmentTargets module")
assert(Master.DebugRaidGrid, "expected DebugRaidGrid module")
assert(Master.AwardMessages, "expected AwardMessages module")
assert(Master.LootSpam, "expected LootSpam module")

print("master service split spec passed")
