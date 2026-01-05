local addonName, addon            = ...

local setmetatable                = setmetatable
local tostring                    = tostring
local rawset                      = rawset

-- Define L *once* with the metatable and assign it directly to addon.L
addon.L                           = addon.L or {} -- Ensure addon.L exists before setting metatable
addon.L                           = setmetatable(addon.L, {
	__index = function(self, k)
		if k ~= nil then rawset(self, k, tostring(k)) end
		return tostring(k)
	end
})
local L                           = addon.L -- Make a local reference for convenience within this file

-- ==================== Callbacks ==================== --
L.StrCbErrUsage                   = "Usage: KRT:registerCallback(event, callbacks)"
L.StrCbErrExec                    = "Error while executing callback %s for event %s: %s"

-- ==================== Log Messages ==================== --
L.LogCoreCallbackHandlerMissing   = "[Core] CallbackHandler missing: using fallback event wiring"
L.LogCoreLoaded                   = "[Core] Loaded version=%s logLevel=%s perfMode=%s"
L.LogCoreEventsRegistered         = "[Core] Events registered=%d"
L.LogCorePlayerEnteringWorld      = "[Core] PLAYER_ENTERING_WORLD -> scheduling FirstCheck"
L.LogRaidLeftGroupEndSession      = "[Raid] Left group -> ending current raid session"
L.LogRaidRosterUpdate             = "[Raid] RosterUpdate v=%d num=%d"
L.LogRaidCreated                  = "[Raid] Created id=%d zone=%s size=%d players=%d"
L.LogRaidEnded                    = "[Raid] Ended id=%d zone=%s size=%d bosses=%d loot=%d duration=%d"
L.LogRaidCheck                    = "[Raid] Check zone=%s diff=%s current=%s"
L.LogRaidSessionChange            = "[Raid] Session change zone=%s size=%d diff=%d"
L.LogRaidSessionCreate            = "[Raid] Session create zone=%s size=%d diff=%d"
L.LogRaidFirstCheck               = "[Raid] FirstCheck inGroup=%s currentRaid=%s instance=%s type=%s diff=%s"
L.LogRaidPlayerJoin               = "[Raid] Player join name=%s raidId=%d"
L.LogRaidPlayerRefresh            = "[Raid] Player refresh name=%s raidId=%d"
L.LogRaidInstanceWelcome          = "[Raid] RAID_INSTANCE_WELCOME name=%s type=%s diff=%s nextReset=%s"
L.LogRaidUnmappedZone             = "[Raid] Unmapped raid zone: %s (diff=%s) -> no session check"
L.LogRaidInstanceRecognized       = "[Raid] Instance recognized: %s diff=%s -> check"
L.LogBossAddSkipped               = "[Boss] AddBoss skipped raidId=%s boss=%s"
L.LogBossLogged                   = "[Boss] Logged boss=%s diff=%d raid=%d players=%d"
L.LogBossLastBossHash             = "[Boss] lastBoss=%d hash=%s"
L.LogBossNoContextTrash           = "[Boss] No boss context -> creating _TrashMob_ bucket"
L.LogBossYellMatched              = "[Boss] Yell matched text=%s boss=%s"
L.LogBossUnitDiedMatched          = "[Boss] UNIT_DIED matched npcId=%d boss=%s"
L.LogLootParseFailed              = "[Loot] Parse failed msg=%s"
L.LogLootParsed                   = "[Loot] Parsed looter=%s link=%s count=%d"
L.LogLootIgnoredBelowThreshold    = "[Loot] Ignored below threshold rarity=%s thr=%d link=%s"
L.LogLootIgnoredItemId            = "[Loot] Ignored itemId=%s link=%s (ignoredItems)"
L.LogLootLogged                   = "[Loot] Logged raidId=%d itemId=%s bossNum=%s looter=%s"
L.LogLootFetchStart               = "[Loot] FetchLoot numLootItems=%d oldIndex=%d"
L.LogLootFetchDone                = "[Loot] FetchLoot done lootCount=%d currentIndex=%d"
L.LogLootItemInfoMissing          = "[Loot] ItemInfo missing -> deferred link=%s"
L.LogLootChatMsgLootRaw           = "[Loot] CHAT_MSG_LOOT raw=%s"
L.LogMLCandidateCacheBuilt        = "[ML] Candidate cache built item=%s candidates=%d"
L.LogMLAwardRequested             = "[ML] Award requested winner=%s type=%d roll=%d item=%s"
L.LogMLItemLocked                 = "[ML] ITEM_LOCKED bag=%s slot=%s link=%s count=%s soulbound=%s"
L.LogMLInventorySoulbound         = "[ML] Inventory item is soulbound -> cannot trade link=%s"
L.LogMLLootOpenedTrace            = "[ML] LOOT_OPENED items=%d fromInv=%s"
L.LogMLLootOpenedInfo             = "[ML] Loot opened items=%d fromInv=%s target=%s"
L.LogMLLootClosed                 = "[ML] LOOT_CLOSED opened=%s items=%d"
L.LogMLLootClosedCleanup          = "[ML] LOOT_CLOSED -> scheduling cleanup"
L.LogMLLootSlotCleared            = "[ML] LOOT_SLOT_CLEARED items=%d"
L.LogMLLootWindowEmptied          = "[ML] Loot window emptied"
L.LogMLCandidateCacheMiss         = "[ML] Candidate cache miss item=%s player=%s -> rebuild"
L.LogMLAwarded                    = "[ML] Awarded item=%s -> %s type=%d roll=%d slot=%d cand=%d"
L.LogMLAwardHistoryFailed         = "[ML] Awarded but History failed raidId=%s itemIndex=%s link=%s"
L.LogTradeAcceptUpdate            = "[Trade] ACCEPT_UPDATE trader=%s winner=%s t=%s p=%s"
L.LogTradeCompleted               = "[Trade] Completed item=%s winner=%s type=%d roll=%d"
L.LogTradeHistoryLogFailed        = "[Trade] History log failed raidId=%s itemIndex=%s link=%s"
L.LogTradeKeepHistoryFailed       = "[Trade] Keep logged but History failed raidId=%s itemIndex=%s link=%s"
L.LogTradeStart                   = "[Trade] TradeItem start item=%s trader=%s target=%s type=%d roll=%d count=%d"
L.LogTradeTraderKeeps             = "[Trade] Trader keeps item=%s winner=%s"
L.LogTradeStackBlocked            = "[Trade] Stack trade blocked ignoreStacks=%s link=%s"
L.LogTradeInitiated               = "[Trade] Initiated item=%s -> %s"
L.LogTradeDelayedOutOfRange       = "[Trade] Delayed: %s out of range item=%s"
L.LogSRImportRequested            = "[SR] Import requested chars=%d"
L.LogSRItemInfoResolved           = "[SR] Item info resolved itemId=%d link=%s"
L.LogSRParseSkippedLine           = "[SR] ParseCSV skipped line=%s"
L.LogSRImportComplete             = "[SR] Import complete players=%d"
L.LogSRQueryMissingItems          = "[SR] QueryMissingItems updated=%s pending=%d"
L.LogHistoryLootLogAttempt        = "[History] Loot:Log attempt source=%s raidId=%s itemIndex=%s "
    .. "looter=%s type=%s roll=%s lastBoss=%s"
L.LogHistoryNoRaidSession         = "[History] Loot:Log FAILED no raid session raidId=%s itemIndex=%s"
L.LogHistoryItemNotFound          = "[History] Loot:Log FAILED item not found raidId=%d itemIndex=%s lootCount=%d"
L.LogHistoryLooterEmpty           = "[History] Loot:Log looter empty raidId=%d itemIndex=%s link=%s"
L.LogHistoryRollTypeNil           = "[History] Loot:Log rollType nil raidId=%d itemIndex=%s looter=%s"
L.LogHistoryLootBefore            = "[History] Loot:Log BEFORE raidId=%d itemIndex=%s link=%s "
    .. "prevLooter=%s prevType=%s prevRoll=%s"
L.LogHistoryLootOverwrite         = "[History] Loot overwrite raidId=%d itemIndex=%s link=%s from=%s to=%s"
L.LogHistoryLootRecorded          = "[History] Loot recorded source=%s raidId=%d itemIndex=%s link=%s -> "
    .. "looter=%s type=%s roll=%s"
L.LogHistoryVerifyFailed          = "[History] Loot:Log VERIFY FAILED raidId=%d itemIndex=%s "
    .. "got(looter=%s type=%s roll=%s)"
L.LogHistoryVerified              = "[History] Loot:Log verified raidId=%d itemIndex=%s"
L.LogHistoryRecordedNoBossContext = "[History] Loot recorded without boss context raidId=%d itemIndex=%s link=%s"
L.LogHistoryBossLootRemoved       = "[History] Boss delete removed loot raidId=%d bossId=%d removed=%d"

-- ==================== General Buttons ==================== --
L.BtnConfig                       = "Config"
L.BtnConfigure                    = "Configure"
L.BtnConfirm                      = "Confirm"
L.BtnDefaults                     = "Defaults"
L.BtnEdit                         = "Edit"
L.BtnOK                           = "OK"
L.BtnStop                         = "Stop"
L.BtnResume                       = "Resume"

-- ==================== Minimap Button ==================== --
L.StrMinimapLClick                = "|cffffd700Left-Click|r to access menu"
L.StrMinimapRClick                = "|cffffd700Right-Click|r to access settings"
L.StrMinimapSClick                = "|cffffd700Shift+Click|r to move"
L.StrMinimapAClick                = "|cffffd700Alt+Click|r for free drag and drop"
L.StrLootHistory                  = "Loot History"
L.StrLootCounter                  = "Loot Counter"
L.StrRaidWarnings                 = "Raid Warnings"
L.StrLFMSpam                      = "LFM Spam"
L.StrMSChanges                    = "MS Changes"
L.StrLootBans                     = "Loot Bans"
L.StrSpamBans                     = "Spam Bans"
L.StrClearIcons                   = "Clear Raid Icons"

-- ==================== Loot Master Frame ==================== --
L.BtnLootCounter                 = "Loot Counter"
L.BtnRaidList                    = "Raid List"
L.BtnSelectItem                   = "Select Item"
L.BtnRemoveItem                   = "Remove Item"
L.BtnSpamLoot                     = "Spam Loot"
L.BtnMS                           = "MS"
L.BtnOS                           = "OS"
L.BtnSR                           = "SR"
L.BtnFree                         = "Free"
L.BtnRoll                         = "Roll"
L.BtnCountdown                    = "Countdown"
L.BtnAward                        = "Award"
L.BtnHold                         = "Hold"
L.BtnBank                         = "Bank"
L.BtnDisenchant                   = "DE"
L.StrNoItemSelected               = "No item selected"
L.StrRoll                         = "Roll"
L.ChatSpamLoot                    = "The boss dropped:"
L.ChatReadyCheck                  = "Ready Check before rolling items!"
L.ChatRollMS                      = "Roll for MS on: %s"
L.ChatRollOS                      = "Roll for OS on: %s"
L.ChatRollSR                      = "Roll %s for SR on: %s"
L.ChatRollFree                    = "Free roll on: %s"
L.ChatRollMSMultipleHigh          = "Roll for MS on: %s. Highest %s rolls win"
L.ChatRollOSMultipleHigh          = "Roll for OS on: %s. Highest %s rolls win"
L.ChatRollSRMultipleHigh          = "Roll %s for SR on: %s. Highest %s rolls win"
L.ChatRollFreeMultipleHigh        = "Free roll on: %s. Highest %s rolls win"
L.ChatRollMSMultipleLow           = "Roll for MS on: %s. Lowest %s rolls win"
L.ChatRollOSMultipleLow           = "Roll for OS on: %s. Lowest %s rolls win"
L.ChatRollSRMultipleLow           = "Roll %s for SR on: %s. Lowest %s rolls win"
L.ChatRollFreeMultipleLow         = "Free roll on: %s. Lowest %s rolls win"
L.ChatCountdownTic                = "Rolling ends in %d sec"
L.ChatCountdownEnd                = "Rolling ends now!"
L.ChatCountdownBlock              = "Rolls are ignored after countdown!"
L.ChatAward                       = "Congrats! %s won %s"
L.ChatTrade                       = "Congrats {triangle} %s ! Please trade {star} %s"
L.ChatTradeMutiple                = "Winners are: %s, Please trade {star} %s"
L.ChatPlayerRolled                = "%s rolled %s"
L.ChatHold                        = "%s is holding %s for later roll"
L.ChatBank                        = "%s is holding %s for the bank"
L.ChatDisenchant                  = "%s will be disenchanted by %s"
L.ChatNoneRolledHold              = "No one rolled on %s, %s is holding it"
L.ChatNoneRolledBank              = "No one rolled on %s, %s holds it for bank"
L.ChatNoneRolledDisenchant        = "No one rolled on %s, %s will disenchant it"
L.ChatOnlyRollOnce                = "Roll: you can only roll once!"
L.WhisperHoldTrade                = "KRT > Please trade me to hold %s"
L.WhisperBankTrade                = "KRT > Please trade me to hold %s (reserved)"
L.WhisperDisenchantTrade          = "KRT > Please trade me to disenchant %s"
L.WhisperHoldAssign               = "KRT > You received an item to hold: %s (for later)"
L.WhisperBankAssign               = "KRT > You received a reserved item: %s (reserved)"
L.WhisperDisenchantAssign         = "KRT > You received an item to disenchant: %s"
L.ErrScreenReminder               = "Please take a screenshot before trading, you never know!"
L.ErrItemStack                    = "You have a stack of %s, you may want to split it first"
L.ErrCannotFindItem               = "Cannot find item: %s"
L.ErrCannotFindPlayer             = "Cannot find player: %s"
L.ErrNoWinnerSelected             = "No winner selected. Use Roll or Select Winner first."
L.ErrPlayerCountBelowZero         = "Cannot decrement player count below zero for %s"

-- ==================== Configuration Frame ==================== --
L.StrConfigSortAscending          = "Sort rolls ascending"
L.StrConfigUseRaidWarning         = "Use raid warnings"
L.StrConfigAnnounceOnWin          = "Announce loot items winners"
L.StrConfigAnnounceOnHold         = "Announce items held for later roll"
L.StrConfigAnnounceOnBank         = "Announce reserved items (bank)"
L.StrConfigAnnounceOnDisenchant   = "Announce items to be disenchanted"
L.StrConfigLootWhisper            = "Send whispers to loot holder, banker and disenchanter."
L.StrConfigCountdownRollsBlock    = "Ignore all rolls done after countdown"
L.StrConfigScreenReminder         = "ScreenShot reminder before trading an item"
L.StrConfigIgnoreStacks           = "Allow trading a stack of an item"
L.StrConfigShowTooltips           = "Show items tooltips"
L.StrConfigMinimapButton          = "Show minimap button"
L.StrConfigCountdownDuration      = "Countdown Duration"
L.StrConfigCountdownSimpleRaidMsg = "Simple raid messages for countdown"
L.StrConfigAbout                  =
"Made with love by |cfff58cbaKader|r B\n|cffffffffhttps://github.com/bkader|r\nhttps://discord.gg/a8z5CyS3eW"

-- ==================== Raid Helper Reserves ==================== --
L.BtnClearReserve                 = "Clear Reserve"
L.BtnCloseWindow                  = "Close Window"
L.BtnQueryItem                    = "Query Item"
L.BtnOpenReserve                  = "Open Reserves"
L.StrNoReserveFound               = "No reserves found."
L.StrRaidReserves                 = "Raid Reserves"
L.StrImportReservesTitle          = "Import Raid Reserves"
L.StrImportReservesHint           = "Paste your raid reserves CSV data below:"
L.BtnLoad                         = "Load"
L.ErrNoTextFound                  = "No text found in the import window."
L.WarnNoValidRows                 = "No valid rows found in CSV (check header)."
L.SuccessReservesParsed           = "Reserves parsed: %s"
L.StrItemUnavailable              = "[Item ID %s unavailable]"
L.TooltipQueryItemHelp1           = "Click to retrieve item information from the server."
L.TooltipQueryItemHelp2           = "|cffff0000Warning: May cause a temporary disconnect!|r"
L.StrQueryingItemInitiated        = "Attempting to retrieve info for ItemID: %s. You might be disconnected!"
L.StrQueryingItemSuccess          = "Successfully retrieved item information for %s."
L.StrReserveListCleared           = "Reserves: list cleared."
L.StrReserveListTitle             = "Reserve List"
L.BtnClose                        = "Close"
L.BtnClearReserves                = "Clear Reserves"
L.StrReserveCountSuffix           = " (x%d)"

-- ==================== Raid Warnings Frame ==================== --
L.StrMessage                      = "Message"
L.StrWarningsHelpTitle            = "Tips:"
L.StrWarningsHelpBody             =
"- |cffffd700Left-Click|r to select a warning, click again to cancel selection.\n- |cffffd700Ctrl-Click|r for a quick raid warning.\n- When you select a warning, you can either |cffffd700Edit|r it, |cffffd700Delete|r it or |cffffd700Announce|r it using the provided buttons."
L.StrWarningsError                =
"Only the body of a message is required! Though, we recommend naming your warnings so you never get lost."
L.StrCmdWarningAnnounce           = "announce the specified raid warning"
L.StrConfirmDeleteWarning         = "Are you sure you want to delete this raid warning?"

-- ==================== MS Changes Frame ==================== --
L.StrChanges                      = "MS Changes"
L.StrChangesDemand                = "Please whisper me your MS changes before we start!"
L.StrChangesAnnounce              = "MS Changes: "
L.StrChangesAnnounceOne           = "%s is rolling %s"
L.StrChangesAnnounceNone          = "No MS changes received!"
L.BtnClear                        = "Clear"
L.BtnDemand                       = "Demand"
L.BtnAnnounce                     = "Announce"
L.ErrChangesNoPlayer              = "The name is required. Leaving the change empty will remove the player from the list."

-- ==================== LFM Spam Frame ==================== --
L.StrSpammer                      = "LFM Spam"
L.StrSpammerCompStr               = "Raid Composition"
L.StrSpammerMessageStr            = "Message"
L.StrSpammerPreviewStr            = "Preview"
L.StrSpammerErrLength             = "Your LFM message is too long."
L.StrSpammerDurationHelp          = "It is recommended to use at least 60 seconds to avoid server mute."
L.StrSpammerMessageHelp1          = "This will be added to the end of the generated message."
L.StrSpammerMessageHelp2          = "You can use |cffffd700{ID}|r to include achievements links."
L.StrSpammerMessageHelp3          =
"You can find the achievement |cffffd700ID|r using the command: \n|cffffd700/krt ach [link]|r."

-- ==================== History Frame ==================== --
L.StrNumber                       = "#"
L.StrDate                         = "Date"
L.StrZone                         = "Zone"
L.StrSize                         = "Size"
L.StrName                         = "Name"
L.StrTime                         = "Time"
L.StrMode                         = "Mode"
L.StrItem                         = "Item"
L.StrSource                       = "Source"
L.StrWinner                       = "Winner"
L.StrType                         = "Type"
L.StrLoading                      = "Loading..."
L.BtnExport                       = "Export"

-- Raids List:
L.StrRaidsList                    = "Raids List"
L.StrSetCurrent                   = "Set Current"
L.StrConfirmDeleteRaid            = "Are you sure you want to delete this raid log?"
L.StrRaidCurrentTitle             = "Duplicate Notice"
L.StrRaidsCurrentHelp             =
"Sometimes you may notice duplicate raid creation. If that happends, make sure to simply set the selected one as current and delete all similar ones above it."
L.ErrCannotDeleteRaid             = "Cannot delete the current raid."
L.ErrCannotSetCurrentRaidSize     = "Cannot set a raid with a different difficulty as current raid."
L.ErrCannotSetCurrentRaidReset    = "Cannot set an expired raid as current raid."
L.StrNewRaidSessionChange         = "Raid session: zone or size changed; starting a new raid."

-- Boss List:
L.StrBosses                       = "Bosses"
L.StrTrashMob                     = "Trash Mob"
L.StrConfirmDeleteBoss            = "Are you sure you want to delete this raid boss?"

-- Raid Attendees:
L.StrRaidAttendees                = "Raid Attendees"
L.StrJoin                         = "Join"
L.StrLeave                        = "Leave"
L.StrConfirmDeleteAttendee        = "Are you sure you want to remove this player from the raid?"

L.StrBossAttendees                = "Boss Attendees"
L.StrPlayers                      = "Players"

-- Raid loot list:
L.StrRaidLoot                     = "Raid Loot"
L.StrUnknown                      = "Unknown"
L.StrConfirmDeleteItem            = "Are you sure you want to delete this item from the log?"
L.StrEditItemLooter               = "Change winner"
L.StrEditItemLooterHelp           = "Enter the name of the winner:"
L.StrEditItemRollType             = "Change roll type"
L.StrEditItemRollTypeHelp         = "1=MS, 2=OS, 3=SR, 4=Free, 5=Bank, 6=DE, 7=Hold"
L.StrEditItemRollValue            = "Change roll value"
L.StrEditItemRollValueHelp        = "Enter the value of the roll:"

-- Add/Edit Boss:
L.StrAddBoss                      = "Add Boss"
L.StrEditBoss                     = "Edit Boss"
L.StrBossNameHelp                 = "Leave empty for |cffffd700Trash Mob|r."
L.StrBossDifficultyHelp           = "\"|cffffd700N|r\" for normal or \"|cffffd700H|r\" for heroic."
L.StrBossTimeHelp                 = "Accepted format: |cffffd700DD/MM/YYY HH:MM|r."
L.ErrBossDifficulty               = "Please provide a valid encounter difficulty: N or H"
L.ErrBossTime                     = "Please provide a valid encounter time: HH:MM"

-- Add/Delete Players/Boss  Attendees:
L.StrAddPlayer                    = "Add Player"
L.ErrAttendeesInvalidName         = "The provided name is either invalid or the player was not in the raid."
L.ErrAttendeesInvalidRaidBoss     = "Invalid raid or boss ID."
L.ErrAttendeesPlayerExists        = "This player is already on the boss attendees list."
L.StrAttendeesAddSuccess          = "Attendees: player added."

-- ==================== History: EditBox Frame ==================== --
L.StrAddEntry                     = "Add Entry"
L.StrEditEntry                    = "Edit Entry"
L.StrDateEditBox                  = "Day/Month/Year"
-- Error Messages:
L.ErrEditBoxInvalidData           = "Attempt to add an invalid item. Possible loss of data."
L.ErrEditBoxInvalidItem           = "Invalid Item: Please use a valid item link or ID."
L.ErrEditBoxInvalidYear           = "Invalid Year: Please enter a valid year."
L.ErrEditBoxInvalidMonth          = "Invalid Month: Please enter a valid month."
L.ErrEditBoxInvalidDay            = "Invalid Day: Please enter a valid day."
L.ErrEditBoxInvalidHour           = "Invalid Hour: Please enter a valid hour."
L.ErrEditBoxInvalidMinute         = "Invalid Minute: Please enter a valid minute."
L.ErrHistoryInvalidRaid           = "Invalid raid selection for History edit."
L.ErrHistoryInvalidItem           = "Invalid loot item selection for History edit."
L.ErrHistoryWinnerEmpty           = "Please enter a valid winner name."
L.ErrHistoryWinnerNotFound        = "Winner not found in raid or boss attendees: %s"
L.ErrHistoryInvalidRollType       = "Invalid roll type. Use a valid roll type number."
L.ErrHistoryInvalidRollValue      = "Invalid roll value. Enter a non-negative number."

-- ==================== History: Export Frame ==================== --
L.StrExportBoxTitle               = "Export Loot History"
L.StrExportFormat                 = "Please enter the export format:"
L.StrExportBoxHelp                = "Copy the data below and paste it to an external location to save it:"

-- ==================== Slash Commands ==================== --
L.StrCmdCommands                  = "Commands: valid subcommands for |caaf49141/%s|r:"
L.StrCmdToggle                    = "shows or hides the main window"
L.StrCmdConfig                    = "shows or hides configuration window"
L.StrCmdGrouper                   = "access LFM Spam related commands"
L.StrCmdAchiev                    = "look for achievement ID to use for LFM"
L.StrCmdChanges                   = "access ms changes related commands"
L.StrCmdWarnings                  = "access warnings related commands"
L.StrCmdHistory                   = "access loot history related commands"
L.StrCmdDebug                     = "toggle debugger or set level: debug on|off|level <name|num>"
L.StrCmdLFMStart                  = "starts LFM spam"
L.StrCmdLFMStop                   = "stops LFM spam"
L.StrCmdChangesDemand             = "ask raid members to whisper you their ms changes"
L.StrCmdChangesAnnounce           = "spam ms changes to raid channel"
L.StrCmdReserves                  = "access reserve list related commands"
L.StrCmdLFMPeriod                 = "set LFM spam period"
L.StrCmdMinimapPos                = "set minimap button angle"

L.MsgDebugOn                      = "Debug: enabled."
L.MsgDebugOff                     = "Debug: disabled."
L.MsgChatThrottleSet              = "Chat throttle: set to %s sec."
L.MsgLFMPeriodSet                 = "LFM period: set to %s sec."
L.MsgMinimapPosSet                = "Minimap: angle set to %s."
L.MsgDefaultsRestored             = "Options: defaults restored."
L.MsgLogLevelCurrent              = "Log level: current=%s."
L.MsgLogLevelSet                  = "Log level: set=%s."
L.MsgLogLevelUnknown              = "Unknown log level: %s."
L.MsgLogLevelList                 = "Log levels: error, warn, info, debug, trace, spam (or 1-6)."
L.MsgReserveItemsRequested        = "Reserves: requested info for %s missing items."
L.MsgReserveItemsReady            = "Reserves: all item infos are available."

L.LFM_TEMPLATE                   = "[KRT] LFM: {raid} {roles} {time}"

-- ==================== Raid & Loot Locales ==================== --
L.ItemValues                      = {
	[1] = "Poor",
	[2] = "Common",
	[3] = "Uncommon",
	[4] = "Rare",
	[5] = "Epic",
	[6] = "Legendary",
	[7] = "Artifact",
}
L.RaidZones                       = {
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
        ["Onyxia's Lair"] = "Onyxia's Lair",                          -- Note: Onyxia is also present in Classic
	["Trial of the Crusader"] = "Trial of the Crusader",
        ["Trial of the Grand Crusader"] = "Trial of the Grand Crusader", -- Already present, keeping it
	["Icecrown Citadel"] = "Icecrown Citadel",
        ["The Ruby Sanctum"] = "The Ruby Sanctum",                    -- Already present, keeping it
}
-- The reason we are using these is because of the missing
-- UNIT_DIED event once these bosses are dealt with.
L.BossYells                       = {
	-- Naxxramas
	["I grow tired of these games. Proceed, and I will banish your souls to oblivion!"] = "Four Horsemen",
	-- Ulduar
	["You rush headlong into the maw of madness!"] = "Iron Council",                         -- Normalmode - Stormcaller Brundir last
	["What have you gained from my defeat? You are no less doomed, mortals!"] = "Iron Council", -- Semi-Hardmode - Runemaster Molgeim last
	-- ["Impossible..."] = MRT_IsInstanceUlduar("Iron Council"),  -- Hardmode - Steelbreaker last  // also yelled by Lich King -> instance check necessary
	["I... I am released from his grasp... at last."] = "Hodir",
	["Stay your arms! I yield!"] = "Thorim",
	["His hold on me dissipates. I can see clearly once more. Thank you, heroes."] = "Freya",
	["It would appear that I've made a slight miscalculation. I allowed my mind to be corrupted by the fiend in the prison, overriding my primary directive. All systems seem to be functional now. Clear."] =
	"Mimiron",
	["I've rearranged the reply code. Your planet will be spared. I cannot be certain of my own calculations anymore."] =
	"Algalon",
	-- Trial of the Crusader
	["A shallow and tragic victory. We are weaker as a whole from the losses suffered today. Who but the Lich King could benefit from such foolishness? Great warriors have lost their lives. And for what? The true threat looms ahead - the Lich King awaits us all in death."] =
	"Faction Champions",
	["The Scourge cannot be stopped..."] = "Val'kyr Twins",
	-- Icecrown Citadel
	["Don't say I didn't warn ya, scoundrels! Onward, brothers and sisters!"] = "Gunship Battle",                       -- Muradin
	["The Alliance falter. Onward to the Lich King!"] = "Gunship Battle",                                               -- Saurfang
	["My queen, they... come."] = "Blood Prince Council",                                                               -- Prince Keleseth
	["I AM RENEWED! Ysera grant me the favor to lay these foul creatures to rest!"] = "Valithria Dreamwalker",          -- Dreamwalker
	-- Ruby Sanctum
	["Relish this victory, mortals, for it will be your last. This world will burn with the master's return!"] = "Halion", -- Halion
}
