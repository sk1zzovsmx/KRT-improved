local _, addon = ...

addon.Diagnose = addon.Diagnose or {}
local Diagnose = addon.Diagnose
local Diag = setmetatable({}, {
    __index = Diagnose,
    __newindex = function(_, key, value)
        Diagnose[key] = value
    end,
})

Diag.I = Diag.I or {}
Diag.W = Diag.W or {}
Diag.E = Diag.E or {}
Diag.D = Diag.D or {}

-- ==================== Log Messages ==================== --
-- Core --
Diag.W.LogCoreCallbackHandlerMissing = "[Core] CallbackHandler missing: using fallback event wiring"
Diag.I.LogCoreLoaded = "[Core] Loaded version=%s logLevel=%s perfMode=%s"
Diag.D.LogCoreEventsRegistered = "[Core] Events registered=%d"
Diag.D.LogCorePlayerEnteringWorld = "[Core] PLAYER_ENTERING_WORLD -> scheduling FirstCheck"
Diag.E.LogCoreEventHandlerFailed = "[Core] Event handler failed event=%s err=%s"

-- Utils --
Diag.E.LogUtilsCallbackExec = "Error while executing callback %s for event %s: %s"
Diag.D.LogListHighlightRefresh = "[%s] refresh key=%s%s"

-- Raid --
Diag.D.LogRaidLeftGroupEndSession = "[Raid] Left group -> ending current raid session"
Diag.D.LogRaidRosterUpdate = "[Raid] RosterUpdate v=%d num=%d"
Diag.I.LogRaidCreated = "[Raid] Created id=%d zone=%s size=%d players=%d"
Diag.I.LogRaidEnded = "[Raid] Ended id=%d zone=%s size=%d bosses=%d loot=%d duration=%d"
Diag.D.LogRaidCheck = "[Raid] Check zone=%s diff=%s current=%s"
Diag.D.LogRaidSessionChange = "[Raid] Session change zone=%s size=%d diff=%d"
Diag.D.LogRaidSessionCreate = "[Raid] Session create zone=%s size=%d diff=%d"
Diag.D.LogRaidFirstCheck = "[Raid] FirstCheck inGroup=%s currentRaid=%s instance=%s type=%s diff=%s"
Diag.D.LogRaidPlayerJoin = "[Raid] Player join name=%s raidId=%d"
Diag.D.LogRaidPlayerRefresh = "[Raid] Player refresh name=%s raidId=%d"
Diag.D.LogRaidInstanceWelcome = "[Raid] RAID_INSTANCE_WELCOME name=%s type=%s diff=%s nextReset=%s"
Diag.W.LogRaidUnmappedZone = "[Raid] Unmapped raid zone: %s (diff=%s) -> no session check"
Diag.D.LogRaidInstanceRecognized = "[Raid] Instance recognized: %s diff=%s -> check"

-- Boss --
Diag.D.LogBossAddSkipped = "[Boss] AddBoss skipped raidId=%s boss=%s"
Diag.I.LogBossLogged = "[Boss] Logged boss=%s diff=%d raid=%d players=%d"
Diag.D.LogBossLastBossHash = "[Boss] lastBoss=%d hash=%s"
Diag.D.LogBossNoContextTrash = "[Boss] No boss context -> creating _TrashMob_ bucket"
Diag.D.LogBossYellMatched = "[Boss] Yell matched text=%s boss=%s"
Diag.D.LogBossUnitDiedMatched = "[Boss] UNIT_DIED matched npcId=%d boss=%s"

-- Loot --
Diag.D.LogLootParseFailed = "[Loot] Parse failed msg=%s"
Diag.D.LogLootParsed = "[Loot] Parsed looter=%s link=%s count=%d"
Diag.D.LogLootTaggedManual = "[Loot] tagged MANUAL (no matching pending award) item=%s -> %s (lastRollType=%s)."
Diag.D.LogLootIgnoredBelowThreshold = "[Loot] Ignored below threshold rarity=%s thr=%d link=%s"
Diag.D.LogLootIgnoredItemId = "[Loot] Ignored itemId=%s link=%s (ignoredItems)"
Diag.D.LogLootLogged = "[Loot] Logged raidId=%d itemId=%s bossNid=%s looter=%s"
Diag.D.LogLootFetchStart = "[Loot] FetchLoot numLootItems=%d oldIndex=%d"
Diag.D.LogLootFetchDone = "[Loot] FetchLoot done lootCount=%d currentIndex=%d"
Diag.D.LogLootItemInfoMissing = "[Loot] ItemInfo missing -> deferred link=%s"
Diag.D.LogLootChatMsgLootRaw = "[Loot] CHAT_MSG_LOOT raw=%s"

-- MasterLooter --
Diag.D.LogMLCandidateCacheBuilt = "[ML] Candidate cache built item=%s candidates=%d"
Diag.D.LogMLAwardRequested = "[ML] Award requested winner=%s type=%d roll=%d item=%s"
Diag.W.LogMLCountdownActive = "[ML] Countdown active: wait for it to finish before awarding"
Diag.D.LogMLAwardBlocked = "[ML] Award blocked lootCount=%d rollsCount=%d"
Diag.D.LogMLItemLocked = "[ML] ITEM_LOCKED bag=%s slot=%s link=%s count=%s soulbound=%s"
Diag.D.LogMLInventorySoulbound = "[ML] Inventory item is soulbound -> cannot trade link=%s"
Diag.D.LogMLLootOpenedTrace = "[ML] LOOT_OPENED items=%d fromInv=%s"
Diag.D.LogMLLootOpenedInfo = "[ML] Loot opened items=%d fromInv=%s target=%s"
Diag.D.LogMLLootClosed = "[ML] LOOT_CLOSED opened=%s items=%d"
Diag.D.LogMLLootClosedCleanup = "[ML] LOOT_CLOSED -> scheduling cleanup"
Diag.D.LogMLLootSlotCleared = "[ML] LOOT_SLOT_CLEARED items=%d"
Diag.D.LogMLLootWindowEmptied = "[ML] Loot window emptied"
Diag.D.LogMLCandidateCacheMiss = "[ML] Candidate cache miss item=%s player=%s -> rebuild"
Diag.D.LogMLAwarded = "[ML] Awarded item=%s -> %s type=%d roll=%d slot=%d cand=%d"
Diag.E.LogMLAwardLoggerFailed = "[ML] Awarded but Logger failed raidId=%s lootNid=%s link=%s"
Diag.W.ErrMLMultiAwardInProgress = "[ML] Multi-award in progress: wait until it finishes before awarding again."
Diag.W.ErrMLMultiSelectTooMany = "[ML] Cannot select more than %d winner(s) for this item."
Diag.W.ErrMLMultiSelectNotEnough = "[ML] Select %d winner(s) before awarding multiple copies (currently %d)."

-- Trade --
Diag.D.LogTradeAcceptUpdate = "[Trade] ACCEPT_UPDATE trader=%s winner=%s t=%s p=%s"
Diag.D.LogTradeCompleted = "[Trade] Completed item=%s winner=%s type=%d roll=%d"
Diag.W.LogTradeCurrentRollItemMissing = "[Trade] currentRollItem missing; cannot update loot entry"
Diag.E.LogTradeLoggerLogFailed = "[Trade] Logger log failed raidId=%s lootNid=%s link=%s"
Diag.E.LogTradeKeepLoggerFailed = "[Trade] Keep logged but Logger failed raidId=%s lootNid=%s link=%s"
Diag.D.LogTradeStart = "[Trade] TradeItem start item=%s trader=%s target=%s type=%d roll=%d count=%d"
Diag.D.LogTradeTraderKeeps = "[Trade] Trader keeps item=%s winner=%s"
Diag.D.LogTradeStackBlocked = "[Trade] Stack trade blocked ignoreStacks=%s link=%s"
Diag.D.LogTradeInitiated = "[Trade] Initiated item=%s -> %s"
Diag.W.LogTradeDelayedOutOfRange = "[Trade] Delayed: %s out of range item=%s"

-- SoftRes --
Diag.D.LogSRImportRequested = "[SR] Import requested chars=%d"
Diag.D.LogSRItemInfoResolved = "[SR] Item info resolved itemId=%d link=%s"
Diag.D.LogSRParseSkippedLine = "[SR] ParseCSV skipped line=%s"
Diag.I.LogSRImportComplete = "[SR] Import complete players=%d"
Diag.D.LogSRQueryMissingItems = "[SR] QueryMissingItems updated=%s pending=%d"

-- Rolls --
Diag.D.LogRollsSortNoEntries = "[Rolls] Sort skipped: no entries"
Diag.D.LogRollsAddEntry = "[Rolls] Add name=%s roll=%d item=%s"
Diag.D.LogRollsBlockedPlayer = "[Rolls] Blocked player=%s (%d/%d)"
Diag.D.LogRollsPlayerRolled = "[Rolls] Player=%s item=%d"
Diag.D.LogRollsRecordState = "[Rolls] Record=%s"
Diag.D.LogRollsCountdownBlocked = "[Rolls] Blocked: countdown active"
Diag.W.LogRollsMissingItem = "[Rolls] Item ID missing or loot table not ready - roll ignored"
Diag.D.LogRollsDeniedPlayer = "[Rolls] Denied player=%s (%d/%d)"
Diag.D.LogRollsAcceptedPlayer = "[Rolls] Accepted player=%s (%d/%d)"
Diag.D.LogRollsCurrentItemId = "[Rolls] Current itemId=%s"

-- Reserves --
Diag.D.LogReservesTrackPending = "[Reserves] Track pending itemId=%d pending=%d"
Diag.D.LogReservesItemReady = "[Reserves] Item ready itemId=%d pending=%d"
Diag.D.LogReservesPendingComplete = "[Reserves] Pending item info complete"
Diag.D.LogReservesToggleCollapse = "[Reserves] Toggle collapse source=%s state=%s"
Diag.D.LogReservesSaveEntries = "[Reserves] Save entries=%d"
Diag.D.LogReservesLoadData = "[Reserves] Load data=%s"
Diag.D.LogReservesResetSaved = "[Reserves] Reset saved data"
Diag.W.LogReservesFrameMissing = "[Reserves] Reserve List frame not available"
Diag.D.LogReservesShowWindow = "[Reserves] Show list window"
Diag.D.LogReservesHideWindow = "[Reserves] Hide list window"
Diag.D.LogReservesOpenImportWindow = "[Reserves] Open import window"
Diag.E.LogReservesImportWindowMissing = "[Reserves] KRTImportWindow not found"
Diag.D.LogReservesFrameLoaded = "[Reserves] Frame loaded"
Diag.D.LogReservesBindButton = "[Reserves] Bind button=%s action=%s"
Diag.D.LogReservesItemInfoReceived = "[Reserves] Item info received itemId=%d"
Diag.D.LogReservesUpdateItemData = "[Reserves] Update item data %s"
Diag.D.LogReservesItemInfoMissing = "[Reserves] Item info missing itemId=%d"
Diag.D.LogReservesItemInfoPending = "[Reserves] Item info still pending itemId=%d"
Diag.D.LogReservesUILocalized = "[Reserves] UI localized %s"
Diag.D.LogReservesUIAlreadyLocalized = "[Reserves] UI already localized"
Diag.D.LogReservesPlayerFound = "[Reserves] Player found %s data=%s"
Diag.D.LogReservesPlayerNotFound = "[Reserves] Player not found %s"
Diag.D.LogReservesFetchAll = "[Reserves] Fetch all players=%d"
Diag.W.LogReservesImportFailedEmpty = "[Reserves] Import failed: empty or invalid data"
Diag.D.LogReservesParseStart = "[Reserves] Parse CSV start"
Diag.D.LogReservesParseComplete = "[Reserves] Parse CSV complete players=%d"
Diag.D.LogReservesImportWrongModePlus = "[Reserves] Wrong CSV for Plus System; player=%s has multiple entries"
Diag.D.LogReservesQueryItemInfo = "[Reserves] Query item info itemId=%d"
Diag.D.LogReservesItemInfoReady = "[Reserves] Item info ready itemId=%d name=%s"
Diag.D.LogReservesItemInfoPendingQuery = "[Reserves] Item info pending itemId=%d"
Diag.D.LogReservesQueryMissingItems = "[Reserves] Query missing items"
Diag.D.LogReservesMissingItems = "[Reserves] Missing items requested=%d"
Diag.D.LogReservesCheckCount = "[Reserves] Check count itemId=%d player=%s"
Diag.D.LogReservesFoundCount = "[Reserves] Found itemId=%d player=%s qty=%d"
Diag.D.LogReservesNoCount = "[Reserves] None itemId=%d player=%s"
Diag.D.LogReservesFormatPlayers = "[Reserves] Format players itemId=%d"
Diag.D.LogReservesPlayersList = "[Reserves] Players itemId=%d list=%s"

-- Changes --
Diag.D.LogChangesInitTable = "[Changes] Init table"
Diag.D.LogChangesFetchAll = "[Changes] Fetch all"

-- Logger --
Diag.E.LogLoggerUIError = "[LoggerUI:%s] %s"
Diag.D.LogLoggerUIShow = "[LoggerUI] show %s -> %s"
Diag.D.LogLoggerUIWidgets = "[LoggerUI:%s] widgets sf=%s sc=%s sfW=%.1f sfH=%.1f scW=%.1f scH=%.1f"
Diag.W.LogLoggerUIMissingWidgets = "[LoggerUI:%s] Missing ScrollFrame widgets for %s"
Diag.D.LogLoggerUIDeferLayout = "[LoggerUI:%s] defer (layout not ready): sfW=%.1f"
Diag.D.LogLoggerUIFetch = "[LoggerUI:%s] fetch count=%d sfW=%.1f sfH=%.1f scW=%.1f scH=%.1f frameW=%.1f frameH=%.1f"
Diag.D.LogLoggerSelectInit = "[LoggerSelect] init ctx=%s ver=%d"
Diag.D.LogLoggerSelectToggle = "[LoggerSelect] toggle ctx=%s id=%s multi=%s action=%s count %d->%d ver=%d"
Diag.D.LogLoggerSelectAnchor = "[LoggerSelect] anchor ctx=%s from=%s to=%s ver=%d"
Diag.D.LogLoggerSelectRange = "[LoggerSelect] range ctx=%s id=%s add=%s action=%s count %d->%d ver=%d anchor=%s"
Diag.D.LogLoggerSelectClickRaid = "[LoggerSelect] click list=Raid id=%s ctrl=%d shift=%d action=%s selectedCount=%d focus=%s"
Diag.D.LogLoggerSelectClickBoss = "[LoggerSelect] click list=Boss id=%s ctrl=%d shift=%d action=%s selectedCount=%d focus=%s"
Diag.D.LogLoggerSelectClickBossAttendees = "[LoggerSelect] click list=BossAttendees id=%s ctrl=%d shift=%d action=%s selectedCount=%d focus=%s"
Diag.D.LogLoggerSelectClickRaidAttendees = "[LoggerSelect] click list=RaidAttendees id=%s ctrl=%d shift=%d action=%s selectedCount=%d focus=%s"
Diag.D.LogLoggerSelectClickLoot = "[LoggerSelect] click list=Loot id=%s ctrl=%d shift=%d action=%s selectedCount=%d focus=%s"
Diag.D.LogLoggerSelectClickContextMenu = "[LoggerSelect] click id=%s ctrl=0 action=CONTEXT_MENU(%s) selectedCount=%d"
Diag.D.LogLoggerSelectDeleteItems = "[LoggerSelect] delete items removed=%d"
Diag.W.ErrLoggerUpdateRosterNotInRaid = "[Logger] Cannot update roster: you are not in a raid."
Diag.W.ErrLoggerUpdateRosterNotCurrent = "[Logger] Cannot update roster: selected raid is not the current raid."
Diag.D.LogLoggerLootLogAttempt = "[Logger] Loot:Log attempt source=%s raidId=%s lootNid=%s "
    .. "looter=%s type=%s roll=%s lastBoss=%s"
Diag.E.LogLoggerNoRaidSession = "[Logger] Loot:Log FAILED no raid session raidId=%s lootNid=%s"
Diag.E.LogLoggerItemNotFound = "[Logger] Loot:Log FAILED item not found raidId=%d lootNid=%s lootCount=%d"
Diag.W.LogLoggerLooterEmpty = "[Logger] Loot:Log looter empty raidId=%d lootNid=%s link=%s"
Diag.W.LogLoggerRollTypeNil = "[Logger] Loot:Log rollType nil raidId=%d lootNid=%s looter=%s"
Diag.D.LogLoggerLootBefore = "[Logger] Loot:Log BEFORE raidId=%d lootNid=%s link=%s "
    .. "prevLooter=%s prevType=%s prevRoll=%s"
Diag.W.LogLoggerLootOverwrite = "[Logger] Loot overwrite raidId=%d lootNid=%s link=%s from=%s to=%s"
Diag.D.LogLoggerLootRecorded = "[Logger] Loot recorded source=%s raidId=%d lootNid=%s link=%s -> "
    .. "looter=%s type=%s roll=%s"
Diag.E.LogLoggerVerifyFailed = "[Logger] Loot:Log VERIFY FAILED raidId=%d lootNid=%s "
    .. "got(looter=%s type=%s roll=%s)"
Diag.D.LogLoggerVerified = "[Logger] Loot:Log verified raidId=%d lootNid=%s"
Diag.D.LogLoggerRecordedNoBossContext = "[Logger] Loot recorded without boss context raidId=%d lootNid=%s link=%s"
Diag.D.LogLoggerBossLootRemoved = "[Logger] Boss delete removed loot raidId=%d bossId=%d removed=%d"
