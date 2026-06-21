local function newAddon()
    local addon = {
        Services = {},
        Database = {},
    }
    local feature = {
        Services = addon.Services,
        Database = addon.Database,
        rollTypes = {
            MAINSPEC = 1,
            OFFSPEC = 2,
            RESERVED = 3,
            FREE = 4,
            HOLD = 5,
            BANK = 6,
            DISENCHANT = 7,
        },
        L = {
            BtnAward = "Award",
            BtnBank = "Bank",
            BtnCountdown = "Countdown",
            BtnDisenchant = "DE",
            BtnFree = "Free",
            BtnHold = "Hold",
            BtnInsertList = "Import SoftRes",
            BtnMS = "MS",
            BtnOS = "OS",
            BtnOpenList = "Open SoftRes",
            BtnRemoveItem = "Remove Item",
            BtnReroll = "Reroll",
            BtnSelectItem = "Select Item",
            BtnSpamLoot = "Spam Loot",
            BtnSR = "SR",
            BtnStop = "Stop",
            ChatAward = "Congrats! %s won %s",
            ChatBank = "%s is holding %s for the bank",
            ChatDisenchant = "%s will be disenchanted by %s",
            ChatHold = "%s is holding %s for later roll",
            ChatSpamLoot = "The boss dropped:",
            ChatSpamLootFrom = "%s dropped:",
            ChatSpamLootReservedHeader = "Item reserved:",
            ChatSpamLootReservedLine = "%d. %s by %s",
            TipMasterAward = "Award %s",
            TipMasterAwardMultiple = "Award %d",
            TipMasterBank = "Bank %s",
            TipMasterBankUnset = "Bank unset",
            TipMasterClear = "Clear",
            TipMasterConfig = "Config",
            TipMasterCountdown = "Countdown active",
            TipMasterCountdownInactive = "Countdown inactive",
            TipMasterDisenchant = "DE %s",
            TipMasterDisenchantUnset = "DE unset",
            TipMasterHold = "Hold %s",
            TipMasterHoldUnset = "Hold unset",
            TipMasterLootCounter = "Counter",
            TipMasterPickWinner = "Pick winner",
            TipMasterReadyCheck = "Ready check",
            TipMasterRemoveItem = "Remove item",
            TipMasterReserveImport = "Import reserves",
            TipMasterReserveList = "Open reserves",
            TipMasterReroll = "Reroll tied",
            TipMasterRollMode = "Roll %s",
            TipMasterRollModeMultiple = "Roll %s x%d",
            TipMasterRollSelf = "Roll self",
            TipMasterSelectItem = "Select item",
            TipMasterSpamLoot = "Spam loot",
            TipMasterSRUnavailable = "No SR",
            TipMasterTrade = "Trade %s",
            TipMasterTradeMultiple = "Trade %d",
            WarnMLOnlyMode = "ML only",
            WarnReadyCheckNotAllowed = "No ready",
            WhisperBankAssign = "Bank whisper %s",
            WhisperDisenchantAssign = "DE whisper %s",
            WhisperHoldAssign = "Hold whisper %s",
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
loadAddonFile(addon, "!KRT/Services/Master/ButtonState.lua")
loadAddonFile(addon, "!KRT/Services/Master/RollRows.lua")
loadAddonFile(addon, "!KRT/Services/Master/AwardMessages.lua")
loadAddonFile(addon, "!KRT/Services/Master/LootSpam.lua")
loadAddonFile(addon, "!KRT/Services/Master/AwardCounter.lua")
loadAddonFile(addon, "!KRT/Services/Master/Service.lua")

local Master = addon.Services.Master
local rollTypes = addon.Database.GetFeatureShared().rollTypes

local lootState = {
    banker = "Banker",
    disenchanter = "Enchanter",
    fromInventory = true,
    holder = "Holder",
    lootCount = 2,
    rollStarted = true,
    rollsCount = 1,
}

local tooltipState = Master.BuildMasterTooltipState({
    awardTarget = "Alice",
    countdownRunning = false,
    hasEligibleRaidReserve = false,
    hasInventoryTradeAccess = false,
    hasLootAccess = false,
    hasReadyCheckAccess = false,
    hasReserves = true,
    lootState = lootState,
    msCount = 1,
    rollModel = {
        requiredWinnerCount = 2,
    },
    selectedItemCount = 2,
})

assert(tooltipState.spamLoot == "No ready", "expected inventory spam tooltip to use ready-check warning")
assert(tooltipState.award == "ML only", "expected blocked inventory award tooltip")
assert(tooltipState.hold == "ML only", "expected blocked hold tooltip")
assert(tooltipState.reserveList == "Open reserves", "expected reserve list tooltip")

local buttonState = Master.BuildMasterButtonState({
    autoLootSuggestion = {
        action = "bank",
    },
    countdownRunning = false,
    hasInventoryTradeAccess = true,
    hasItem = true,
    hasLootAccess = false,
    labels = {
        readyCheck = "Ready Check",
        trade = "Trade",
    },
    lootState = lootState,
    isTieReroll = false,
    statusText = "Ready",
    tooltipState = tooltipState,
    workflowState = {
        canAward = true,
        canChangeItem = true,
        canReserveList = true,
        canRollSelf = false,
        canSpamLoot = true,
        canStartRolls = true,
        canStartSR = false,
    },
})

assert(buttonState.awardText == "Trade", "expected inventory award button text")
assert(buttonState.spamLootText == "Ready Check", "expected inventory spam text")
assert(buttonState.canAward == true, "expected facade button state award flag")
assert(buttonState.glowBankSuggestion == "Banker", "expected bank suggestion glow target")

local _, msCount, canAwardSelection = Master.ResolveAwardSelectionState({
    msCount = 1,
    pickMode = true,
    requiredWinnerCount = 2,
    resolution = {
        requiresManualResolution = true,
    },
}, false)
assert(msCount == 1, "expected award selection count")
assert(canAwardSelection == false, "expected incomplete multi selection to block award")

local selectionState = Master.BuildRollSelectionState({
    fromInventory = false,
    mode = "AUTO",
    resolution = {
        autoWinners = {
            { name = "Alice", roll = 99 },
        },
        topRollName = "Alice",
    },
    requiredWinnerCount = 1,
    selectedWinners = {},
    selectionAllowed = true,
})
assert(selectionState.winnerName == "Alice", "expected auto winner to be selected by model")
assert(selectionState.highlightTarget == "Alice", "expected top roll highlight")

local decoratedRows, visibleRows = Master.BuildRollRowsModel({
    rows = {
        { name = "Alice", roll = 99 },
        { name = "Bob", hasExplicitResponse = true },
        { name = "Cara" },
    },
    resolution = {
        autoWinners = {
            { name = "Alice", roll = 99 },
        },
    },
    selectionState = selectionState,
    showRollsOnly = true,
})
assert(decoratedRows[1].showStar == true, "expected automatic winner star")
assert(decoratedRows[1].isFocused == true, "expected automatic winner focus")
assert(#visibleRows == 2, "expected rows without rolls or explicit responses to stay hidden")

local output, whisper = Master.BuildAssignMessages({
    itemLink = "[Blade]",
    lootWhispers = true,
    options = {
        announceOnHold = true,
    },
    playerName = "Holder",
    rollType = rollTypes.HOLD,
})
assert(output == "Holder is holding [Blade] for later roll", "expected hold assign output")
assert(whisper == "Hold whisper [Blade]", "expected hold whisper")

local spamPlan = Master.BuildLootSpamPlan({
    items = {
        {
            count = 2,
            itemLink = "[Blade]",
            reservedPlayers = "Alice, Bob",
        },
        {
            count = 1,
            itemLink = "[Ring]",
        },
    },
    sourceName = "Patchwerk",
})
assert(spamPlan.header == "Patchwerk dropped:", "expected source-specific spam header")
assert(spamPlan.lootLines[1] == "1. [Blade] x2", "expected loot count suffix")
assert(spamPlan.reservedLines[1] == "1. [Blade] by Alice, Bob", "expected reserved line")

local awardState = Master.EnsureAwardCounterState()
local firstPending = Master.QueueAwardCounterPending(awardState, {
    itemLink = "[Blade]",
    itemIndex = 2,
    playerName = "Alice",
    rollType = rollTypes.MAINSPEC,
    rollValue = 98,
    sessionId = "roll-1",
    itemCount = 1,
})
assert(firstPending.itemKey == "[Blade]", "expected pending award item key")
assert(firstPending.itemIndex == 2, "expected pending award slot")
assert(firstPending.playerName == "Alice", "expected pending award player")
assert(Master.FindAwardCounterPendingBySlot(awardState, 2) == firstPending, "expected slot lookup")

local confirmed = Master.ConfirmAwardCounterPending(awardState, 2)
assert(confirmed == firstPending, "expected confirmed pending award")
assert(confirmed.counterApplied == true, "expected confirm to mark counter applied")
assert(Master.FindAwardCounterPendingBySlot(awardState, 2) == nil, "expected confirmed award removal")

Master.QueueAwardCounterPending(awardState, {
    itemLink = "[Ring]",
    itemIndex = 4,
    playerName = "Bob",
    rollType = rollTypes.OFFSPEC,
    rollValue = 77,
})
Master.QueueAwardCounterPending(awardState, {
    itemLink = "[Trinket]",
    itemIndex = 5,
    playerName = "Cara",
    rollType = rollTypes.FREE,
    rollValue = 11,
})
local failed = Master.FailAwardCounterPending(awardState, "Inventory is full.")
assert(#failed == 2, "expected all pending awards to fail")
assert(awardState.Awards[1] == nil, "expected failed awards to be cleared")

assert(Master.ButtonState, "expected ButtonState module")
assert(Master.RollRows, "expected RollRows module")
assert(Master.AwardMessages, "expected AwardMessages module")
assert(Master.LootSpam, "expected LootSpam module")

print("master model services spec passed")
