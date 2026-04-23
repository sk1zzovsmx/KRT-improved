-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local setmetatable = setmetatable
local tostring = tostring
local rawset = rawset

local L = feature.L
setmetatable(L, {
    __index = function(self, k)
        if k ~= nil then
            rawset(self, k, tostring(k))
        end
        return tostring(k)
    end,
})

-- ----- Internal state ----- --

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

-- ==================== Callbacks ==================== --
L.StrCbErrUsage = "Usage: KRT:registerCallback(event, callbacks)"

-- ==================== General Buttons ==================== --
L.BtnConfigure = "Configure"
L.BtnDefaults = "Defaults"
L.BtnEdit = "Edit"
L.BtnOpen = "Open"
L.BtnAdd = "Add"
L.BtnRemove = "Remove"
L.BtnDelete = "Delete"
L.BtnUpdate = "Update"
L.BtnStart = "Start"
L.BtnStop = "Stop"
L.BtnResume = "Resume"
L.BtnSave = "Save"
L.BtnCancel = "Cancel"
L.BtnImport = "Import"

-- ==================== Minimap Button ==================== --
L.StrMinimapLClick = "|cffffd700Left-Click|r to access menu"
L.StrMinimapRClick = "|cffffd700Right-Click|r to access settings"
L.StrMinimapSClick = "|cffffd700Shift+Click|r to move"
L.StrMinimapAClick = "|cffffd700Alt+Click|r for free drag and drop"
L.StrLootLogger = "Loot Logger"
L.StrLootCounter = "Loot Counter"
L.StrLFMSpam = "LFM Spam"
L.StrMSChanges = "MS Changes"
L.StrClearIcons = "Clear Raid Icons"

-- ==================== Loot Master Frame ==================== --
L.BtnLootCounter = "Loot Counter"
L.BtnLootCounterAnnounce = "Spam Counter"
L.BtnLootCounterResetAll = "Reset All"
L.TipLootCounterPlus = "Increment count"
L.TipLootCounterMinus = "Decrement count"
L.TipLootCounterReset = "Reset count to 0"
L.TipLootCounterAnnounce = "Announce MS/OS/FREE counts grouped by +N in raid chat."
L.TipLootCounterResetAll = "Reset all player counts to 0."
L.BtnInsertList = "Import SoftRes"
L.BtnOpenList = "Open SoftRes"
L.BtnSelectItem = "Select Item"
L.BtnRemoveItem = "Remove Item"
L.BtnSpamLoot = "Spam Loot"
L.BtnManual = "Manual"
L.BtnMS = "MS"
L.BtnOS = "OS"
L.BtnSR = "SR"
L.BtnFree = "Free"
L.BtnNeed = "NE"
L.BtnGreed = "GR"
L.BtnRoll = "Roll"
L.BtnCountdown = "Countdown"
L.BtnAward = "Award"
L.BtnReroll = "Reroll"
L.BtnHold = "Hold"
L.BtnBank = "Bank"
L.BtnDisenchant = "DE"
L.StrNoItemSelected = "No item selected"
L.StrMasterStatusIdle = "Select or drag an item to start."
L.StrMasterStatusReady = "Ready. Start a roll or use Hold, Bank, or DE."
L.StrMasterStatusRolling = "Rolls are open. Responses: %d."
L.StrMasterStatusRollingBypassed = "Rolls are open. Countdown bypassed. Responses: %d."
L.StrMasterStatusCountdown = "Countdown running. Awarding unlocks when the timer ends."
L.StrMasterStatusResolveTie = "Tie at the cutoff. Select winners manually before awarding."
L.StrMasterStatusSelectWinners = "Select %d winner(s) before awarding."
L.StrMasterStatusAwardTarget = "Ready to award: %s."
L.StrMasterStatusAwardSelection = "Ready to award %d winner(s)."
L.StrMasterStatusTrade = "Trade in progress with %s."
L.StrMasterStatusInventory = "Inventory item mode. Select winners and use Trade."
L.StrMasterStatusInventoryTarget = "Ready to trade: %s."
L.StrMasterStatusInventorySelection = "Ready to trade %d winner(s)."
L.StrMasterStatusMultiAward = "Multi-award %d/%d: %s."
L.StrMasterStatusPickWinner = "Pick a winner before continuing."
L.TipMasterConfig = "Open KRT settings and UI options."
L.TipMasterSelectItem = "Pick the next item from the loot window."
L.TipMasterRemoveItem = "Remove the current inventory item and return to loot-window selection."
L.TipMasterSpamLoot = "Announce the current loot list to the raid."
L.TipMasterReadyCheck = "Send a ready-check style reminder before trading inventory loot."
L.TipMasterRollMode = "Start a %s roll for the current item."
L.TipMasterRollModeMultiple = "Start a %s roll for the current item and resolve %d winner(s) at the cutoff."
L.TipMasterSRUnavailable = "This item has no SoftRes entries yet. Import or open the reserve list first."
L.TipMasterCountdown = "Left-click starts or stops the countdown. Right-click closes rolls immediately."
L.TipMasterCountdownInactive = "Start a roll first, then use the countdown to close intake."
L.TipMasterAward = "Award the current item to %s."
L.TipMasterAwardMultiple = "Award the current item to %d selected winner(s)."
L.TipMasterTrade = "Trade the current inventory item to %s."
L.TipMasterTradeMultiple = "Trade the current inventory item across %d selected winner(s)."
L.TipMasterReroll = "Start a tiebreak reroll for the players tied at the cutoff."
L.TipMasterHold = "Assign the current item to %s for later distribution."
L.TipMasterHoldUnset = "Assign the current item to the configured holder."
L.TipMasterBank = "Assign the current item to %s for bank storage."
L.TipMasterBankUnset = "Assign the current item to the configured banker."
L.TipMasterDisenchant = "Assign the current item to %s for disenchanting."
L.TipMasterDisenchantUnset = "Assign the current item to the configured disenchanter."
L.TipMasterReserveImport = "Open the SoftRes import window."
L.TipMasterReserveList = "Open the SoftRes list for the current raid."
L.TipMasterRollSelf = "Submit your own roll to the active session."
L.TipMasterClear = "Clear recorded rolls for the current item."
L.TipMasterLootCounter = "Open the loot counter widget."
L.StrCounter = "Count"
L.StrInfo = "Info"
L.StrTrashMobName = "Trash Mob"
L.StrRoll = "Roll"
L.StrRolls = "Rolls"
L.ChatSpamLoot = "The boss dropped:"
L.StrLootCounterAnnounceHeader = "MS Counter:"
L.StrLootCounterAnnounceNone = "MS Counter: no MS awards yet."
L.StrLootCounterAnnounceHeaderOs = "OS Counter:"
L.StrLootCounterAnnounceNoneOs = "OS Counter: no OS awards yet."
L.StrLootCounterAnnounceHeaderFree = "FREE Counter:"
L.StrLootCounterAnnounceNoneFree = "FREE Counter: no FREE awards yet."
L.StrConfirmLootCounterResetAll = "Are you sure you want to reset all loot counts?"
L.ChatReadyCheck = "Ready Check before rolling items!"
L.WarnReadyCheckNotAllowed = "Ready Check requires party lead or raid assist/lead."
L.WarnLootCounterBroadcastNotAllowed = "Counter announce requires raid lead or assist."
L.WarnRaidWarningFallback = "No Raid Warning permission: announcing to RAID chat."
L.ChatRollMS = "Roll for MS on: %s"
L.ChatRollOS = "Roll for OS on: %s"
L.ChatRollSR = "Roll %s for SR on: %s"
L.ChatRollFree = "Free roll on: %s"
L.ChatCountdownTic = "Rolling ends in %d sec"
L.ChatCountdownEnd = "Rolling ends now!"
L.ChatCountdownBlock = "Rolls are ignored after countdown!"
L.ChatAward = "Congrats! %s won %s"
L.ChatAwardMutiple = "Congrats! %s have won %s"
L.ChatTrade = "Congrats {triangle} %s ! Please trade {star} %s"
L.ChatTradeMutiple = "Winners are: %s, Please trade {star} %s"
L.ChatHold = "%s is holding %s for later roll"
L.ChatBank = "%s is holding %s for the bank"
L.ChatDisenchant = "%s will be disenchanted by %s"
L.ChatNoneRolledHold = "No one rolled on %s, %s is holding it"
L.ChatNoneRolledBank = "No one rolled on %s, %s holds it for bank"
L.ChatNoneRolledDisenchant = "No one rolled on %s, %s will disenchant it"
L.ChatOnlyRollOnce = "Roll: you have used all allowed rolls for this item."
L.ChatRollNotInRaid = "Roll ignored: you are not in raid."
L.ChatRollExcluded = "Roll ignored: you are excluded from this item."
L.ChatRollInactive = "Roll ignored: no active roll session."
L.ChatRollTieOnly = "Roll ignored: only tied players may reroll this item."
L.ChatTieReroll = "Tie reroll for %s on: %s"
L.WhisperHoldTrade = "KRT > Please trade me to hold %s"
L.WhisperBankTrade = "KRT > Please trade me to hold %s (reserved)"
L.WhisperDisenchantTrade = "KRT > Please trade me to disenchant %s"
L.WhisperHoldAssign = "KRT > You received an item to hold: %s (for later)"
L.WhisperBankAssign = "KRT > You received a reserved item: %s (reserved)"
L.WhisperDisenchantAssign = "KRT > You received an item to disenchant: %s"
L.ErrScreenReminder = "Please take a screenshot before trading, you never know!"
L.ErrItemStack = "You have a stack of %s, you may want to split it first"
L.ErrCannotFindItem = "Cannot find item: %s"
L.ErrCannotFindPlayer = "Cannot find player: %s"
L.WarnMLNoPermission = "Cannot award: you are not the Master Looter."
L.WarnChangesBroadcastNotAllowed = "Changes demand/announce requires raid lead or assist."
L.WarnMLOnlyMode = "Action blocked: this addon is available only to the Master Looter."
L.WarnMLNoCandidatesAvailable = "Cannot award: no Master Loot candidates available."
L.WarnMLWinnerNoCandidate = "Cannot award: %s is not a valid Master Loot candidate."
L.ErrMLWinnerNameUnresolved = "Cannot award: winner name is empty or unresolved."
L.ErrMLWinnerNotInRaid = "Cannot award: %s is not in raid."
L.ErrMLWinnerExcluded = "Cannot award: %s is manually excluded from this roll."
L.ErrMLWinnerIneligible = "Cannot award: %s is not eligible for this roll."
L.ErrMLWinnerPassed = "Cannot award: %s has passed on this item."
L.ErrMLWinnerCancelled = "Cannot award: %s withdrew their response for this item."
L.ErrMLWinnerTimedOut = "Cannot award: %s timed out for this item."
L.ErrMLWinnerNoRoll = "Cannot award: %s has no active roll response."
L.ErrMLWinnerTieUnresolved = "Cannot award: tie at the winner cutoff. Select winners manually."
L.ErrMLInventorySoulbound = "Only non-soulbound or tradeable items can be added: %s"
L.ErrMLInventoryItemMissing = "Cannot find the item in your bags: %s"
L.ErrNoWinnerSelected = "No winner selected. Use Roll or Select Winner first."
L.StrRollTieTag = "TIE"
L.StrRollPassTag = "PASS"
L.StrRollCancelledTag = "CXL"
L.StrRollTimedOutTag = "OOT"
L.StrRollOutTag = "OUT"
L.StrRollBlockedTag = "BLK"

-- ==================== Configuration Frame ==================== --
L.StrConfigSortAscending = "Sort rolls ascending"
L.StrConfigUseRaidWarning = "Use raid warnings"
L.StrConfigAnnounceOnWin = "Announce loot items winners"
L.StrConfigAnnounceOnHold = "Announce items held for later roll"
L.StrConfigAnnounceOnBank = "Announce reserved items (bank)"
L.StrConfigAnnounceOnDisenchant = "Announce items to be disenchanted"
L.StrConfigLootWhisper = "Send whispers to loot holder, banker and disenchanter."
L.StrConfigCountdownRollsBlock = "Ignore all rolls done after countdown"
L.StrConfigScreenReminder = "ScreenShot reminder before trading an item"
L.StrConfigIgnoreStacks = "Allow trading a stack of an item"
L.StrConfigShowTooltips = "Show items tooltips"
L.StrConfigShowLootCounterDuringMSRoll = "Show loot counter during MS roll"
L.StrConfigMinimapButton = "Show minimap button"
L.StrConfigCountdownDuration = "Countdown Duration"
L.StrConfigCountdownSimpleRaidMsg = "Simple raid messages for countdown"
L.StrConfigAbout = "Made with love by |cfff58cbaKader|r B\n|cffffffffhttps://github.com/bkader|r\nhttps://discord.gg/a8z5CyS3eW"

-- ==================== Raid Helper Reserves ==================== --
L.BtnClearReserve = "Clear Reserve"
L.BtnQueryItem = "Query Item"
L.StrRaidReserves = "Raid Reserves"
L.StrImportReservesTitle = "Import Raid Reserves"
L.StrImportReservesHint = "Paste your raid reserves CSV data below:"
L.StrImportModeLabel = ""
L.StrImportModeMulti = "Multi-reserve"
L.StrImportModePlus = "Plus System"
L.ErrCSVWrongForPlusShort = "Wrong CSV format for Plus System."
L.ErrCSVWrongForPlusWithPlayer = "Wrong CSV format for Plus System.\nPlayer '%s' has multiple reserve entries.\nSwitch to Multi-reserve or check your SoftRes settings."
L.ErrCSVWrongForPlus = "Wrong CSV format for Plus System.\nThis CSV contains players with multiple reserve entries.\nSwitch to Multi-reserve or check your SoftRes settings."
L.BtnSwitchToMulti = "Switch to Multi-reserve"
L.ErrImportReservesEmpty = "Import failed: empty or invalid CSV data."
L.WarnNoValidRows = "No valid rows found in CSV (check header)."
L.WarnReservesHeaderHint = "CSV header not detected. Expected columns include itemId and name."
L.SuccessReservesParsed = "Reserves parsed: %s"
L.BtnClose = "Close"
L.BtnClearReserves = "Clear Reserves"
L.StrReserveCountSuffix = " (x%d)"
L.StrReservesTooltipTitle = "Reserves"
L.StrReservesTooltipTotal = "Total: %d"
L.StrReservesTooltipShownHidden = "Shown: %d | Hidden: +%d"
L.StrReservesTooltipPlus = "P+%d: %s"
L.StrReservesTooltipQuantity = "x%d: %s"
L.StrReservesPlayersHiddenSuffix = " ... +%d"
L.StrReservesItemIdLabel = "Item ID: %s"
L.StrReservesTooltipDroppedBy = "Dropped by: %s"
L.StrReservesItemFallback = "[Item %s]"

-- ==================== Raid Warnings Frame ==================== --
L.StrMessage = "Message"
L.StrWarningsHelpTitle = "Tips:"
L.StrWarningsHelpBody =
    "- |cffffd700Left-Click|r to select a warning, click again to cancel selection.\n- |cffffd700Ctrl-Click|r for a quick raid warning.\n- When you select a warning, you can either |cffffd700Edit|r it, |cffffd700Delete|r it or |cffffd700Announce|r it using the provided buttons."
L.StrWarningsError = "Only the body of a message is required! Though, we recommend naming your warnings so you never get lost."
L.StrCmdWarningAnnounce = "announce the specified raid warning"

-- ==================== MS Changes Frame ==================== --
L.StrChanges = "MS Changes"
L.StrChangesDemand = "Please whisper me your MS changes before we start!"
L.StrChangesAnnounce = "MS Changes: "
L.StrChangesAnnounceOne = "%s is rolling %s"
L.StrChangesAnnounceNone = "No MS changes received!"
L.BtnClear = "Clear"
L.BtnDemand = "Demand"
L.BtnAnnounce = "Announce"
L.ErrChangesNoPlayer = "The name is required. Leaving the change empty will remove the player from the list."

-- ==================== LFM Spam Frame ==================== --
L.StrSpammer = "LFM Spam"
L.StrSpammerCompStr = "Raid Composition"
L.StrSpammerNeedStr = "Need"
L.StrSpammerMessageStr = "Message"
L.StrSpammerPreviewStr = "Preview"
L.StrSpammerErrLength = "Your LFM message is too long."
L.StrSpammerDurationHelp = "It is recommended to use at least 60 seconds to avoid server mute."
L.StrSpammerMessageHelp1 = "This will be added to the end of the generated message."
L.StrSpammerMessageHelp2 = "You can use |cffffd700{ID}|r to include achievements links."
L.StrSpammerMessageHelp3 = "You can find the achievement |cffffd700ID|r using the command: \n|cffffd700/krt ach [link]|r."

L.StrRaid = "Raid"
L.StrDuration = "Duration"
L.StrTank = "Tank"
L.StrHealer = "Healer"
L.StrMelee = "Melee"
L.StrRanged = "Ranged"
L.StrChannels = "Channels"
L.StrGuild = "Guild"
L.StrYell = "Yell"

-- ==================== Logger Frame ==================== --
L.StrNumber = "#"
L.StrDate = "Date"
L.StrZone = "Zone"
L.StrSize = "Size"
L.StrName = "Name"
L.StrCount = "Count"
L.StrPlayer = "Player"
L.StrMS = "MS"
L.StrOS = "OS"
L.StrFREE = "FREE"
L.StrClass = "Class"
L.StrDifficulty = "Difficulty"
L.StrTime = "Time"
L.StrMode = "Mode"
L.StrItem = "Item"
L.StrSource = "Source"
L.StrWinner = "Winner"
L.StrType = "Type"
L.BtnExport = "Export"
L.StrHistoryTab = "History"
L.StrLoggerLabelPlayer = "Player: %s"
L.StrLoggerEmptyRaids = "No raid logs yet. Enter a raid and log a boss or loot event to start history."
L.StrLoggerEmptyBossesSelectRaid = "Select a raid to inspect boss kills and trash entries."
L.StrLoggerEmptyBosses = "No bosses or trash entries were logged for this raid."
L.StrLoggerEmptyBossAttendeesSelectRaid = "Select a raid, then a boss, to inspect that fight's attendees."
L.StrLoggerEmptyBossAttendeesSelectBoss = "Select a boss to inspect that fight's attendees."
L.StrLoggerEmptyBossAttendees = "No attendees were recorded for this boss."
L.StrLoggerEmptyRaidAttendeesSelectRaid = "Select a raid to inspect its roster timeline."
L.StrLoggerEmptyRaidAttendees = "No roster snapshots were recorded for this raid."
L.StrLoggerEmptyLootSelectRaid = "Select a raid to inspect loot history."
L.StrLoggerEmptyLoot = "No loot was logged for this raid."
L.StrLoggerEmptyLootFiltered = "No loot matches the current boss or player filter."

-- Raids List:
L.StrRaidsList = "Raids List"
L.StrSetCurrent = "Set Current"
L.StrConfirmDeleteRaid = "Are you sure you want to delete this raid log?"
L.StrRaidCurrentTitle = "Duplicate Notice"
L.StrRaidsCurrentHelp =
    "Sometimes you may notice duplicate raid creation. If that happends, make sure to simply set the selected one as current and delete all similar ones above it."
L.ErrCannotDeleteRaid = "Cannot delete the current raid."
L.ErrCannotSetCurrentRaidSize = "Cannot set a raid with a different size as current raid."
L.ErrCannotSetCurrentRaidDifficulty = "Cannot set a raid with a different difficulty as current raid."
L.ErrCannotSetCurrentRaidReset = "Cannot set an expired raid as current raid."
L.ErrCannotSetCurrentNotInRaid = "You must be in a raid group to set the current raid."
L.ErrCannotSetCurrentNotInInstance = "You must be inside a raid instance to set the current raid."
L.ErrCannotSetCurrentZoneMismatch = "Cannot set a raid from a different zone as current raid."
L.LogRaidSetCurrent = "Current raid set to #%d (%s, %d-player)."
L.StrNewRaidSessionChange = "Raid session: zone or size changed; starting a new raid."

-- Boss List:
L.StrBosses = "Bosses"
L.StrTrashMob = "Trash Mob"
L.StrConfirmDeleteBoss = "Are you sure you want to delete this raid boss?"

-- Raid Attendees:
L.StrRaidAttendees = "Raid Attendees"
L.StrJoin = "Join"
L.StrLeave = "Leave"
L.StrConfirmDeleteAttendee = "Are you sure you want to remove this player from the raid?"

L.StrBossAttendees = "Boss Attendees"

-- Raid loot list:
L.StrRaidLoot = "Raid Loot"
L.StrUnknown = "Unknown"
L.StrNone = "None"
L.StrConfirmDeleteItem = "Are you sure you want to delete this item from the log?"
L.StrEditItemLooter = "Change winner"
L.StrEditItemLooterHelp = "Enter the name of the winner:"
L.StrEditItemRollType = "Change roll type"
L.StrEditItemRollValue = "Change roll value"
L.StrEditItemRollValueHelp = "Enter the value of the roll:"

-- Add/Edit Boss:
L.StrAddBoss = "Add Boss"
L.StrEditBoss = "Edit Boss"
L.StrBossNameHelp = "Leave empty for |cffffd700Trash Mob|r."
L.StrBossDifficultyHelp = '"|cffffd700N|r" for normal or "|cffffd700H|r" for heroic.'
L.StrBossTimeHelp = "Accepted format: |cffffd700DD/MM/YYY HH:MM|r."
L.ErrBossDifficulty = "Please provide a valid encounter difficulty: N or H"
L.ErrBossTime = "Please provide a valid encounter time: HH:MM"

-- Add/Delete Players/Boss  Attendees:
L.StrAddPlayer = "Add Player"
L.ErrAttendeesInvalidName = "The provided name is either invalid or the player was not in the raid."
L.ErrAttendeesInvalidRaidBoss = "Invalid raid or boss ID."
L.ErrAttendeesPlayerExists = "This player is already on the boss attendees list."
L.StrAttendeesAddSuccess = "Attendees: player added."

-- ==================== Logger: EditBox Frame ==================== --
-- Error Messages:
L.ErrLoggerInvalidRaid = "Invalid raid selection for Logger edit."
L.ErrLoggerInvalidItem = "Invalid loot item selection for Logger edit."
L.ErrLoggerWinnerEmpty = "Please enter a valid winner name."
L.ErrLoggerWinnerNotFound = "Winner not found in raid or boss attendees: %s"
L.ErrLoggerInvalidRollValue = "Invalid roll value. Enter a non-negative number."

-- ==================== Logger: Export Frame ==================== --

-- ==================== Slash Commands ==================== --
L.StrCmdCommands = "Commands: valid subcommands for |caaf49141/%s|r:"
L.StrCmdToggle = "shows or hides the main window"
L.StrCmdConfig = "shows or hides configuration window"
L.StrCmdGrouper = "access LFM Spam related commands"
L.StrCmdAchiev = "look for achievement ID to use for LFM"
L.StrCmdChanges = "access ms changes related commands"
L.StrCmdWarnings = "access warnings related commands"
L.StrCmdLogger = "access loot logger related commands"
L.StrCmdLoggerReq = "request a specific raid snapshot from one target player"
L.StrCmdLoggerPush = "push a specific raid snapshot to one target player"
L.StrCmdLoggerSync = "sync current raid only when raid characteristics match"
L.StrCmdDebug = "toggle debugger or use test helpers: debug on|off|level <name|num>|raid"
L.StrCmdDebugRaidSeed = "add or reactivate 4 synthetic players in the current raid"
L.StrCmdDebugRaidClear = "remove synthetic players from the current raid when safe"
L.StrCmdDebugRaidRolls = "make the 4 synthetic players roll on the active item (optional: tie)"
L.StrCmdDebugRaidRoll = "make one synthetic player roll: roll <1-4|name> [1-100]"
L.StrCmdCounter = "shows or hides loot counter window"
L.StrCmdLFMStart = "starts LFM spam"
L.StrCmdLFMStop = "stops LFM spam"
L.StrCmdChangesDemand = "ask raid members to whisper you their ms changes"
L.StrCmdChangesAnnounce = "spam ms changes to raid channel"
L.StrCmdReserves = "access reserve list related commands"
L.StrCmdReservesImport = "import reserves from SoftRes CSV data"
L.StrCmdValidate = "run data validation commands"
L.StrCmdValidateRaids = "validate raid history schema and invariants"
L.StrCmdMinimapPos = "set minimap button angle"

L.MsgDebugOn = "Debug: enabled."
L.MsgDebugOff = "Debug: disabled."
L.MsgDebugRaidNoCurrent = "Debug raid: no current raid available."
L.MsgDebugRaidSeeded = "Debug raid: synthetic players=%d added=%d refreshed=%d."
L.MsgDebugRaidCleared = "Debug raid: synthetic players removed=%d kept=%d."
L.MsgDebugRaidClearResetRolls = "Debug raid: current roll state was reset during cleanup."
L.MsgDebugRaidNoActiveRoll = "Debug raid: no active roll session is accepting rolls."
L.MsgDebugRaidUnknownPlayer = "Debug raid: unknown synthetic player '%s'. Use 1-4 or a debug name."
L.MsgDebugRaidInvalidRoll = "Debug raid: roll value must be between 1 and 100."
L.MsgDebugRaidRollSingle = "Debug raid: %s rolled %d."
L.MsgDebugRaidRolls = "Debug raid: submitted %d/%d synthetic rolls."
L.MsgDebugRaidRollsTie = "Debug raid: submitted %d/%d synthetic rolls with tie=%d at roll=%d."
L.MsgDebugRaidRollsPartial = "Debug raid: submitted %d/%d synthetic rolls; first rejection=%s."
L.MsgDebugRaidRollRejected = "Debug raid: %s roll rejected (%s)."
L.MsgSpammerAutoStopDuration = "LFM spam auto-stopped after %d sec (safety cap)."
L.MsgSpammerAutoStopMessages = "LFM spam auto-stopped after %d messages (safety cap)."
L.MsgMinimapPosSet = "Minimap: angle set to %s."
L.MsgDefaultsRestored = "Options: defaults restored."
L.MsgLogLevelCurrent = "Log level: current=%s."
L.MsgLogLevelSet = "Log level: set=%s."
L.MsgLogLevelUnknown = "Unknown log level: %s."
L.MsgLogLevelList = "Log levels: error, warn, info, debug, trace, spam (or 1-6)."
L.MsgReserveItemsRequested = "Reserves: requested info for %s missing items."
L.MsgReserveItemsReady = "Reserves: all item infos are available."
L.MsgReserveItemsQueryCooldown = "Reserves: query cooldown active (%d sec)."
L.MsgReservesImportRows = "Reserves import rows: valid=%d skipped=%d."
L.MsgFeatureDisabledByProfile = "Feature '%s' is disabled by current profile (%s)."
L.MsgFeatureUnavailable = "Feature '%s' action '%s' is not available."
L.MsgLoggerSyncNotInGroup = "Logger Sync: you must be in a group."
L.MsgLoggerSyncRaidRefRequired = "Logger Sync: raid reference is required for req/push."
L.MsgLoggerSyncTargetRequired = "Logger Sync: target player is required for req/push."
L.MsgLoggerSyncTargetSelf = "Logger Sync: target player cannot be yourself."
L.MsgLoggerSyncNoRaid = "Logger Sync: no matching raid found for the provided reference."
L.MsgLoggerSyncPushSent = "Logger Sync: pushed raid NID %s to %s."
L.MsgLoggerReqSent = "Logger Sync: req sent for raid reference %s to %s."
L.MsgLoggerReqImported = "Logger Sync: imported requested snapshot from %s as raid #%d."
L.MsgLoggerPushImported = "Logger Sync: imported pushed snapshot from %s as raid #%d."
L.MsgLoggerSyncSent = "Logger Sync: sync request sent for current raid #%d."
L.MsgLoggerSyncNoCurrent = "Logger Sync: no current raid available for sync."
L.MsgLoggerSyncApplied = "Logger Sync: applied sync to current raid #%d from %s."
L.MsgValidateUnavailable = "Validation service is not available."
L.MsgValidateRaidsNoData = "Raid validation: no raids available."
L.MsgValidateRaidsSummary = "Raid validation: raids=%d ok=%d warn=%d err=%d schema=%d."
L.MsgValidateRaidsDetailsTruncated = "Raid validation: %d detail rows were truncated."
L.MsgValidateDetailRaidNotTable = "raid[%d] nid=%s: record is not a table."
L.MsgValidateDetailNormalizeFailed = "raid[%d] nid=%s: normalization failed."
L.MsgValidateDetailSchemaMissing = "raid[%d] nid=%s: schemaVersion is missing."
L.MsgValidateDetailSchemaNewer = "raid[%d] nid=%s: schemaVersion=%d is newer than current=%d."
L.MsgValidateDetailCounterTooLow = "raid[%d] nid=%s: %s=%d is lower than required=%d."
L.MsgValidateDetailPlayerCountType = "raid[%d] nid=%s: players[%d].count is not a number."
L.MsgValidateDetailPlayerCountNegative = "raid[%d] nid=%s: players[%d].count is negative (%d)."
L.MsgValidateDetailLootMissingBoss = "raid[%d] nid=%s: loot[%d].bossNid=%d does not exist."
L.MsgValidateDetailLootNoBossTrash = "raid[%d] nid=%s: loot[%d] has no bossNid and no _TrashMob_."
L.MsgValidateDetailBossAttendeeInvalid = "raid[%d] nid=%s: bossKills[%d].players[%d] is not a valid playerNid."
L.MsgValidateDetailBossAttendeeMissingPlayer = "raid[%d] nid=%s: bossKills[%d].players[%d]=%d does not match any raid player."
L.MsgValidateDetailLootMissingLooter = "raid[%d] nid=%s: loot[%d] has no looterNid."
L.MsgValidateDetailLootMissingLooterNid = "raid[%d] nid=%s: loot[%d].looterNid=%d does not exist."
L.MsgValidateDetailRuntimeOutside = "raid[%d] nid=%s: runtime key outside _runtime: %s."
L.MsgValidateDetailLegacyRuntime = "raid[%d] nid=%s: legacy runtime key found: %s."
L.MsgValidateDetailUnknown = "raid[%d] nid=%s: %s."

-- ==================== Raid & Loot Locales ==================== --
L.RaidZones = {
    -- The Burning Crusade
    ["Karazhan"] = "Karazhan",
    ["Gruul's Lair"] = "Gruul's Lair",
    ["Magtheridon's Lair"] = "Magtheridon's Lair",
    ["Serpentshrine Cavern"] = "Serpentshrine Cavern",
    ["The Eye"] = "The Eye", -- Tempest Keep: The Eye
    ["Battle for Mount Hyjal"] = "Battle for Mount Hyjal",
    ["Black Temple"] = "Black Temple",
    ["Sunwell Plateau"] = "Sunwell Plateau",
    ["Zul'Aman"] = "Zul'Aman",

    -- Wrath of the Lich King
    ["Naxxramas"] = "Naxxramas",
    ["The Obsidian Sanctum"] = "The Obsidian Sanctum",
    ["The Eye of Eternity"] = "The Eye of Eternity",
    ["Vault of Archavon"] = "Vault of Archavon",
    ["Ulduar"] = "Ulduar",
    ["Onyxia's Lair"] = "Onyxia's Lair", -- Note: Onyxia is also present in Classic
    ["Trial of the Crusader"] = "Trial of the Crusader",
    ["Trial of the Grand Crusader"] = "Trial of the Grand Crusader", -- Already present, keeping it
    ["Icecrown Citadel"] = "Icecrown Citadel",
    ["The Ruby Sanctum"] = "The Ruby Sanctum", -- Already present, keeping it
}
-- The reason we are using these is because of the missing
-- UNIT_DIED event once these bosses are dealt with.
L.BossYells = {
    -- Naxxramas
    ["I grow tired of these games. Proceed, and I will banish your souls to oblivion!"] = "Four Horsemen",
    -- Ulduar
    ["You rush headlong into the maw of madness!"] = "Iron Council", -- Normalmode - Stormcaller Brundir last
    ["What have you gained from my defeat? You are no less doomed, mortals!"] = "Iron Council", -- Semi-Hardmode - Runemaster Molgeim last
    -- ["Impossible..."] = MRT_IsInstanceUlduar("Iron Council"),  -- Hardmode - Steelbreaker last  // also yelled by Lich King -> instance check necessary
    ["I... I am released from his grasp... at last."] = "Hodir",
    ["Stay your arms! I yield!"] = "Thorim",
    ["His hold on me dissipates. I can see clearly once more. Thank you, heroes."] = "Freya",
    ["It would appear that I've made a slight miscalculation. I allowed my mind to be corrupted by the fiend in the prison, overriding my primary directive. All systems seem to be functional now. Clear."] = "Mimiron",
    ["I've rearranged the reply code. Your planet will be spared. I cannot be certain of my own calculations anymore."] = "Algalon",
    -- Trial of the Crusader
    ["A shallow and tragic victory. We are weaker as a whole from the losses suffered today. Who but the Lich King could benefit from such foolishness? Great warriors have lost their lives. And for what? The true threat looms ahead - the Lich King awaits us all in death."] = "Faction Champions",
    ["The Scourge cannot be stopped..."] = "Val'kyr Twins",
    -- Icecrown Citadel
    ["Don't say I didn't warn ya, scoundrels! Onward, brothers and sisters!"] = "Gunship Battle", -- Muradin
    ["The Alliance falter. Onward to the Lich King!"] = "Gunship Battle", -- Saurfang
    ["My queen, they... come."] = "Blood Prince Council", -- Prince Keleseth
    ["I AM RENEWED! Ysera grant me the favor to lay these foul creatures to rest!"] = "Valithria Dreamwalker", -- Dreamwalker
    -- Ruby Sanctum
    ["Relish this victory, mortals, for it will be your last. This world will burn with the master's return!"] = "Halion", -- Halion
}
