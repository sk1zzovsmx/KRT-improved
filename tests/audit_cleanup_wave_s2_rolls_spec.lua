local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing: " .. needle), 0)
    end
end

local function assertNotContains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected: " .. needle), 0)
    end
end

local service = read("!KRT/Services/Rolls/Service.lua")
local sessions = read("!KRT/Services/Rolls/Sessions.lua")
local backlog = read("docs/TECH_CLEANUP_BACKLOG.md")

local publicMethods = {
    "Roll",
    "GetRollStatus",
    "SetRollRecordingEnabled",
    "CHAT_MSG_SYSTEM",
    "SubmitDebugRoll",
    "GetCandidateEligibility",
    "SetManualExclusion",
    "SetPlayerResponse",
    "GetRolls",
    "GetHighestRoll",
    "ClearRolls",
    "BeginTieReroll",
    "ValidateWinner",
    "GetDisplayModel",
    "GetRollSession",
    "SetExpectedWinners",
    "EnsureRollSession",
    "EnsureLootRollSession",
    "SyncSessionState",
    "GetResolvedWinner",
    "ShouldUseTieReroll",
    "StopCountdown",
    "StartCountdown",
    "IsCountdownRunning",
    "FinalizeRollSession",
}

for i = 1, #publicMethods do
    local methodName = publicMethods[i]
    assertContains(service, "function module:" .. methodName .. "(", "missing Rolls public method: " .. methodName)
end

assertContains(sessions, "function Sessions.GetCurrentRollItemId(ctx, onResolved)")
assertContains(service, "Sessions.GetCurrentRollItemId(getSessionsContext(), logCurrentRollItemId)")
assertNotContains(service, "local sessionItemId = session and tonumber(session.itemId) or nil")
assertNotContains(service, "Item.GetItemStringFromLink(itemLink) or itemLink")
assertContains(service, "local function beginRollIntake()")
assertContains(service, "local function finishRollIntake()")
assertContains(service, "local function resetForTieReroll(session, reroll, itemId, itemLink, currentRollType)")
assertContains(service, "local function finalizeRollSession()")
assertContains(service, "`resolution` table is a stable part of this API")
assertContains(backlog, "Wave S2 completed: Rolls Service facade helper cleanup")
assertNotContains(service, "addon.Services.Rolls", "Rolls service must keep Services.Rolls localization")
assertNotContains(service, "addon.Rolls", "Rolls service must not reintroduce root Rolls aliases")

print("audit cleanup wave s2 rolls source contract passed")
