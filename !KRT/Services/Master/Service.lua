-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Master
-- events: none
-- notes: Master service facade for focused domain/model helpers
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local Services = feature.Services
local Master = Services.Master or {}
Services.Master = Master
addon.Services.Master = Master

local AssignmentCandidates = Master.AssignmentCandidates
local AssignmentTargets = Master.AssignmentTargets
local AwardMessages = Master.AwardMessages
local ButtonState = Master.ButtonState
local DebugRaidGrid = Master.DebugRaidGrid
local FlowState = Master.FlowState
local AwardCounter = Master.AwardCounter
local LootSpam = Master.LootSpam
local RollAnnouncements = Master.RollAnnouncements
local RollRows = Master.RollRows
local SessionWinners = Master.SessionWinners
local SoftRes = Master.SoftRes

local type = type

-- ----- Internal state ----- --

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

function Master.BuildWorkflowState(opts)
    return FlowState.BuildState(opts)
end

function Master.BuildSessionWinnersModel(model)
    return SessionWinners.BuildModel(model)
end

function Master.BuildSrSummaryText(opts, rollModel)
    return SoftRes.BuildSummaryText(opts, rollModel)
end

function Master.BuildAssignmentCandidateRows(candidates, classProvider)
    return AssignmentCandidates.BuildRows(candidates, classProvider)
end

function Master.BuildDebugCandidateRows(count, rosterRows)
    return DebugRaidGrid.BuildRows(count, rosterRows)
end

function Master.GetDebugRaidGridTargetCount(debugState)
    return DebugRaidGrid.GetTargetCount(debugState)
end

function Master.IsDebugRaidGridFallbackEnabled(debugState, debugEnabled)
    return DebugRaidGrid.IsFallbackEnabled(debugState, debugEnabled)
end

function Master.BuildAssignmentTargetRows(groupedNames, classProvider)
    return AssignmentTargets.BuildRows(groupedNames, classProvider)
end

function Master.BuildMasterTooltipState(opts)
    return ButtonState.BuildTooltipState(opts)
end

function Master.ResolveAwardSelectionState(rollModel, isTieReroll)
    return ButtonState.ResolveAwardSelectionState(rollModel, isTieReroll)
end

function Master.BuildMasterButtonState(opts)
    return ButtonState.BuildState(opts)
end

function Master.BuildRollSelectionState(opts)
    return RollRows.BuildSelectionState(opts)
end

function Master.BuildRollRowsModel(opts)
    return RollRows.BuildModel(opts)
end

function Master.IsSelectableRollRow(row)
    return RollRows.IsSelectableRow(row)
end

function Master.BuildAssignMessages(opts)
    return AwardMessages.BuildAssignMessages(opts)
end

function Master.BuildLootSpamPlan(opts)
    return LootSpam.BuildPlan(opts)
end

function Master.BuildRollAnnouncementPlan(opts)
    return RollAnnouncements.BuildPlan(opts)
end

function Master.EnsureAwardCounterState(state)
    return AwardCounter.EnsureState(state)
end

function Master.QueueAwardCounterPending(state, opts)
    return AwardCounter.Queue(state, opts)
end

function Master.FindAwardCounterPendingBySlot(state, clearedSlot)
    return AwardCounter.FindBySlot(state, clearedSlot)
end

function Master.RemoveAwardCounterPending(state, index, cancelTimer)
    return AwardCounter.Remove(state, index, cancelTimer)
end

function Master.ClearAwardCounterPending(state, reason, cancelTimer)
    return AwardCounter.Clear(state, reason, cancelTimer)
end

function Master.FailAwardCounterPending(state, reason, cancelTimer)
    return AwardCounter.Fail(state, reason, cancelTimer)
end

function Master.ConfirmAwardCounterPending(state, clearedSlot, cancelTimer)
    return AwardCounter.Confirm(state, clearedSlot, cancelTimer)
end

function Master.HasAwardCounterPending(state)
    return AwardCounter.HasPending(state)
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Master/Service", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Services/Master/SoftRes",
            "Services/Master/SessionWinners",
            "Services/Master/FlowState",
            "Services/Master/ButtonState",
            "Services/Master/RollRows",
            "Services/Master/AssignmentCandidates",
            "Services/Master/AssignmentTargets",
            "Services/Master/DebugRaidGrid",
            "Services/Master/AwardMessages",
            "Services/Master/LootSpam",
            "Services/Master/AwardCounter",
            "Services/Master/RollAnnouncements",
        },
    })
    registry.SetLoaded("Services/Master/Service")
end
