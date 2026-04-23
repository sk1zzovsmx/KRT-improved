-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Diag = feature.Diag

Diag.I = Diag.I or {}
Diag.W = Diag.W or {}
Diag.E = Diag.E or {}
Diag.D = Diag.D or {}

-- ----- Internal state ----- --

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

-- ==================== Log Messages ==================== --
-- Core --
Diag.W.LogRaidStoreUnavailable = "[Core] RaidStore unavailable (context=%s)"
Diag.W.LogRaidStoreMethodMissing = "[Core] RaidStore missing method %s (context=%s)"
Diag.I.LogCoreLoaded = "[Core] Loaded version=%s logLevel=%s perfMode=%s"
Diag.D.LogCoreEventsRegistered = "[Core] Events registered=%d"
Diag.D.LogCorePlayerEnteringWorld = "[Core] PLAYER_ENTERING_WORLD -> scheduling FirstCheck"
Diag.E.LogCoreEventHandlerFailed = "[Core] Event handler failed event=%s err=%s"

-- Utils --
Diag.E.LogUtilsCallbackExec = "Error while executing callback %s for event %s: %s"
Diag.D.LogListHighlightRefresh = "[%s] refresh key=%s%s"
Diag.W.LogLegacyAliasAccess = "[Compat] Legacy alias used alias=%s target=%s site=%s"

-- Raid --
Diag.D.LogRaidLeftGroupEndSession = "[Raid] Left group -> ending current raid session"
Diag.W.LogRaidLegacyFieldsDetected = "[RaidStore] Legacy fields phase=%s raidNid=%s idx=%s runtime=%s " .. "looter=%d mask=%d"
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
Diag.D.LogDebugRaidSeed = "[Debug] Raid seed raidId=%s name=%s class=%s"
Diag.D.LogDebugRaidClearRemoved = "[Debug] Raid clear removed raidId=%s name=%s nid=%s"
Diag.D.LogDebugRaidClearBlocked = "[Debug] Raid clear blocked raidId=%s name=%s nid=%s"
Diag.D.LogDebugRaidRoll = "[Debug] Raid roll raidId=%s name=%s roll=%d ok=%s reason=%s"

-- Boss --
Diag.D.LogBossAddSkipped = "[Boss] AddBoss skipped raidId=%s boss=%s"
Diag.I.LogBossLogged = "[Boss] Logged boss=%s diff=%d raid=%d players=%d"
Diag.D.LogBossLastBossHash = "[Boss] lastBoss=%d hash=%s"
Diag.D.LogBossNoContextTrash = "[Boss] No boss context -> creating _TrashMob_ bucket"
Diag.D.LogBossEventContextSet = "[Boss] Event context set boss=%s bossNid=%d raid=%d source=%s"
Diag.D.LogBossEventContextRecovered = "[Boss] Event context recovered boss=%s bossNid=%d delta=%d source=%s"
Diag.D.LogBossLootWindowContextSet = "[Boss] Loot-window context set boss=%s bossNid=%d raid=%d source=%s"
Diag.D.LogBossLootWindowContextRecovered = "[Boss] Loot-window context recovered boss=%s bossNid=%d raid=%d source=%s"
Diag.D.LogBossLootWindowContextBlocked = "[Boss] Loot-window context blocked raid=%d unit=%s name=%s npcId=%d source=%s"
Diag.D.LogBossYellMatched = "[Boss] Yell matched text=%s boss=%s"
Diag.D.LogBossUnitDiedMatched = "[Boss] UNIT_DIED matched npcId=%d boss=%s"
Diag.D.LogBossUnitDiedIgnored = "[Boss] UNIT_DIED ignored npcId=%d boss=%s"
Diag.D.LogBossDuplicateSuppressed = "[Boss] Duplicate suppressed boss=%s sourceNpcId=%d existingBossNid=%d delta=%d"

-- Master --
Diag.E.LogMasterUILocalizationFailed = "[Master] UI localization failed; controls are still bound."

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
Diag.D.LogLootGroupSelectionQueued = "[Loot] Group selection queued type=%s looter=%s link=%s"
Diag.D.LogLootGroupWinnerDetected = "[Loot] Group winner observed looter=%s msgType=%s msgRoll=%s link=%s"
Diag.D.LogLootPendingAwardConsumed = "[Loot] Pending consumed item=%s looter=%s remaining=%d ttl=%d"
Diag.D.LogLootTradeOnlyLogged = "[Loot] Trade-only logged raidId=%d itemId=%s lootNid=%s looter=%s count=%d source=%s"

-- MasterLooter --
Diag.D.LogMLCandidateCacheBuilt = "[ML] Candidate cache built item=%s candidates=%d"
Diag.D.LogMLAwardRequested = "[ML] Award requested winner=%s type=%d roll=%d item=%s"
Diag.W.LogMLCountdownActive = "[ML] Countdown active: wait for it to finish before awarding"
Diag.D.LogMLAwardBlocked = "[ML] Award blocked lootCount=%d rollsCount=%d"
Diag.D.LogMLInventorySoulbound = "[ML] Inventory item is soulbound -> cannot trade link=%s"
Diag.D.LogMLLootOpenedTrace = "[ML] LOOT_OPENED items=%d fromInv=%s"
Diag.D.LogMLLootOpenedInfo = "[ML] Loot opened items=%d fromInv=%s target=%s"
Diag.D.LogMLLootClosed = "[ML] LOOT_CLOSED opened=%s items=%d"
Diag.D.LogMLLootClosedCleanup = "[ML] LOOT_CLOSED -> scheduling cleanup"
Diag.D.LogMLLootSlotCleared = "[ML] LOOT_SLOT_CLEARED items=%d"
Diag.D.LogMLLootWindowEmptied = "[ML] Loot window emptied"
Diag.D.LogMLCandidateCacheMiss = "[ML] Candidate cache miss item=%s player=%s -> rebuild"
Diag.D.LogMLAwarded = "[ML] Awarded item=%s -> %s type=%d roll=%d slot=%d cand=%d"
Diag.W.LogMLSetItemPayloadInvalid = "[ML] SetItem payload invalid itemLink=%s itemDataType=%s"
Diag.W.LogMLRaidRosterDeltaPayloadInvalid = "[ML] RaidRosterDelta payload invalid deltaType=%s " .. "rosterVersion=%s raidId=%s"
Diag.W.LogMLAddRollPayloadInvalid = "[ML] AddRoll payload invalid name=%s roll=%s"
Diag.W.ErrMLMultiAwardInProgress = "[ML] Multi-award in progress: wait until it finishes before awarding again."
Diag.W.ErrMLMultiSelectTooMany = "[ML] Cannot select more than %d winner(s) for this item."
Diag.W.ErrMLMultiSelectNotEnough = "[ML] Select %d winner(s) before awarding multiple copies (currently %d)."
Diag.D.LogMLMultiAwardStarted = "[ML] Multi-award start item=%s total=%d available=%d slots=%s timeout=%ds"
Diag.I.LogMLTieReroll = "[ML] Tie reroll item=%s players=%s"
Diag.W.ErrMLMultiAwardInterruptedTimeout = "[ML] Multi-award interrupted: loot window did not update as expected within %ds " .. "item=%s expected<%d observed=%d slot=%s"

-- Trade --
Diag.D.LogTradeAcceptUpdate = "[Trade] ACCEPT_UPDATE trader=%s winner=%s t=%s p=%s"
Diag.D.LogTradeCompleted = "[Trade] Completed item=%s winner=%s type=%d roll=%d"
Diag.W.LogTradeCurrentRollItemMissing = "[Trade] currentRollItem missing; cannot update loot entry"
Diag.W.LogTradeCurrentRollItemMissingContext = "[Trade] currentRollItem missing winner=%s itemId=%s link=%s"
Diag.E.LogTradeLoggerLogFailed = "[Trade] Logger log failed raidId=%s lootNid=%s link=%s"
Diag.E.LogTradeKeepLoggerFailed = "[Trade] Keep logged but Logger failed raidId=%s lootNid=%s link=%s"
Diag.D.LogTradeStart = "[Trade] TradeItem start item=%s trader=%s target=%s type=%d roll=%d count=%d"
Diag.D.LogTradeTraderKeeps = "[Trade] Trader keeps item=%s winner=%s"
Diag.D.LogTradeAwardedCountResolved = "[Trade] Awarded count=%d source=%s before=%s after=%s selected=%d"
Diag.D.LogTradeStackBlocked = "[Trade] Stack trade blocked ignoreStacks=%s link=%s"
Diag.D.LogTradeInitiated = "[Trade] Initiated item=%s -> %s"
Diag.W.LogTradeDelayedOutOfRange = "[Trade] Delayed: %s out of range item=%s"
Diag.W.LogTradeNoLootContextTradeOnly = "[Trade] No lootNid context; created trade-only entry lootNid=%s winner=%s item=%s count=%d"

-- SoftRes --
Diag.D.LogSRImportRequested = "[SR] Import requested chars=%d"
Diag.D.LogSRParseSkippedLine = "[SR] ParseCSV skipped line=%s"
Diag.D.LogSRQueryMissingItems = "[SR] QueryMissingItems updated=%s pending=%d"

-- Rolls --
Diag.D.LogRollsAddEntry = "[Rolls] Add name=%s roll=%d item=%s"
Diag.D.LogRollsBlockedPlayer = "[Rolls] Blocked player=%s (%d/%d)"
Diag.D.LogRollsPlayerRolled = "[Rolls] Player=%s item=%d"
Diag.D.LogRollsRecordState = "[Rolls] Record=%s"
Diag.W.LogRollsMissingItem = "[Rolls] Item ID missing or loot table not ready - roll ignored"
Diag.D.LogRollsDeniedPlayer = "[Rolls] Denied player=%s (%d/%d)"
Diag.D.LogRollsAcceptedPlayer = "[Rolls] Accepted player=%s (%d/%d)"
Diag.D.LogRollsCurrentItemId = "[Rolls] Current itemId=%s"
Diag.D.LogRollsEligibility = "[Rolls] Eligibility name=%s ok=%s bucket=%s reason=%s used=%d/%d"
Diag.D.LogRollsResponse = "[Rolls] Response name=%s status=%s bucket=%s best=%s last=%s"
Diag.D.LogRollsResolution = "[Rolls] Resolution top=%s tied=%s cutoff=%d manual=%s"
Diag.D.LogRollsTimedOut = "[Rolls] Timed out name=%s"
Diag.D.LogRollsTieReroll = "[Rolls] Tie reroll item=%s players=%s"
Diag.D.LogRollsTiebreakerApplied = "[Rolls] Tiebreaker applied: scope=%s n=%d, tied=%s, counts=%s, resolved=%s"

-- Reserves --
Diag.W.LogReservesLegacyFieldsDetected = "[Reserves] Legacy fields phase=%s original=%d rowPlayer=%d dropped=%d merged=%d"
Diag.D.LogReservesTrackPending = "[Reserves] Track pending itemId=%d pending=%d"
Diag.D.LogReservesItemReady = "[Reserves] Item ready itemId=%d pending=%d"
Diag.D.LogReservesPendingComplete = "[Reserves] Pending item info complete"
Diag.D.LogReservesToggleCollapse = "[Reserves] Toggle collapse source=%s state=%s"
Diag.D.LogReservesSaveEntries = "[Reserves] Save entries=%d"
Diag.D.LogReservesLoadData = "[Reserves] Load data=%s"
Diag.D.LogReservesResetSaved = "[Reserves] Reset saved data"
Diag.D.LogReservesShowWindow = "[Reserves] Show list window"
Diag.D.LogReservesHideWindow = "[Reserves] Hide list window"
Diag.E.LogReservesImportWindowMissing = "[Reserves] KRTImportWindow not found"
Diag.D.LogReservesFrameLoaded = "[Reserves] Frame loaded"
Diag.D.LogReservesBindButton = "[Reserves] Bind button=%s action=%s"
Diag.D.LogReservesItemInfoReceived = "[Reserves] Item info received itemId=%d"
Diag.D.LogReservesItemInfoPending = "[Reserves] Item info still pending itemId=%d"
Diag.D.LogReservesUILocalized = "[Reserves] UI localized %s"
Diag.D.LogReservesUIAlreadyLocalized = "[Reserves] UI already localized"
Diag.D.LogReservesPlayerFound = "[Reserves] Player found %s data=%s"
Diag.D.LogReservesPlayerNotFound = "[Reserves] Player not found %s"
Diag.D.LogReservesFetchAll = "[Reserves] Fetch all players=%d"
Diag.W.LogReservesImportFailedEmpty = "[Reserves] Import failed: empty or invalid data"
Diag.D.LogReservesParseStart = "[Reserves] Parse CSV start"
Diag.D.LogReservesParseComplete = "[Reserves] Parse CSV complete players=%d"
Diag.D.LogReservesImportRows = "[Reserves] Import rows valid=%d skipped=%d header=%s lines=%d"
Diag.D.LogReservesImportWrongModePlus = "[Reserves] Wrong CSV for Plus System; player=%s has multiple entries"
Diag.D.LogReservesQueryItemInfo = "[Reserves] Query item info itemId=%d"
Diag.D.LogReservesItemInfoReady = "[Reserves] Item info ready itemId=%d name=%s"
Diag.D.LogReservesItemInfoPendingQuery = "[Reserves] Item info pending itemId=%d"
Diag.D.LogReservesQueryMissingItems = "[Reserves] Query missing items"
Diag.D.LogReservesMissingItems = "[Reserves] Missing items requested=%d"
Diag.D.LogReservesFormatPlayers = "[Reserves] Format players itemId=%d"
Diag.D.LogReservesPlayersList = "[Reserves] Players itemId=%d list=%s"

-- Changes --
Diag.D.LogChangesInitTable = "[Changes] Init table"

-- Logger --
Diag.E.LogListUIError = "[ListUI:%s] %s"
Diag.D.LogListUIShow = "[ListUI] show %s -> %s"
Diag.D.LogListUIWidgets = "[ListUI:%s] widgets sf=%s sc=%s sfW=%.1f sfH=%.1f scW=%.1f scH=%.1f"
Diag.W.LogListUIMissingWidgets = "[ListUI:%s] Missing ScrollFrame widgets for %s"
Diag.D.LogListUIDeferLayout = "[ListUI:%s] defer (layout not ready): sfW=%.1f"
Diag.D.LogListUIFetch = "[ListUI:%s] fetch count=%d sfW=%.1f sfH=%.1f scW=%.1f scH=%.1f frameW=%.1f frameH=%.1f"
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
Diag.D.LogLoggerLootLogAttempt = "[Logger] Loot:SetLootEntry attempt source=%s raidId=%s lootNid=%s " .. "looter=%s type=%s roll=%s lastBoss=%s"
Diag.E.LogLoggerNoRaidSession = "[Logger] Loot:SetLootEntry FAILED no raid session raidId=%s lootNid=%s"
Diag.E.LogLoggerLootNidExpected = "[Logger] Loot:SetLootEntry expected lootNid but got raw itemId raidId=%s value=%s link=%s matches=%d"
Diag.E.LogLoggerItemNotFound = "[Logger] Loot:SetLootEntry FAILED item not found raidId=%d lootNid=%s lootCount=%d"
Diag.W.LogLoggerLooterEmpty = "[Logger] Loot:SetLootEntry looter empty raidId=%d lootNid=%s link=%s"
Diag.W.LogLoggerRollTypeNil = "[Logger] Loot:SetLootEntry rollType nil raidId=%d lootNid=%s looter=%s"
Diag.D.LogLoggerLootBefore = "[Logger] Loot:SetLootEntry BEFORE raidId=%d lootNid=%s link=%s " .. "prevLooter=%s prevType=%s prevRoll=%s"
Diag.W.LogLoggerLootOverwrite = "[Logger] Loot overwrite raidId=%d lootNid=%s link=%s from=%s to=%s"
Diag.D.LogLoggerLootRecorded = "[Logger] Loot recorded source=%s raidId=%d lootNid=%s link=%s -> " .. "looter=%s type=%s roll=%s"
Diag.E.LogLoggerVerifyFailed = "[Logger] Loot:SetLootEntry VERIFY FAILED raidId=%d lootNid=%s " .. "got(looter=%s type=%s roll=%s)"
Diag.D.LogLoggerVerified = "[Logger] Loot:SetLootEntry verified raidId=%d lootNid=%s"
Diag.D.LogLoggerRecordedNoBossContext = "[Logger] Loot recorded without boss context raidId=%d lootNid=%s link=%s"
Diag.D.LogLoggerBossLootRemoved = "[Logger] Boss delete removed loot raidId=%d bossId=%d removed=%d"
Diag.W.LogLoggerSelectRaidPayloadInvalid = "[Logger] LoggerSelectRaid payload invalid raidId=%s reason=%s"
Diag.E.LogLoggerLootLogRequestPayloadInvalid = "[Logger] LoggerLootLogRequest invalid payload type=%s"

-- Syncer --
Diag.D.LogSyncRequestSent = "[Sync] Request sent req=%s raidNid=%s"
Diag.D.LogSyncRequestReceived = "[Sync] Request received from=%s req=%s raidNid=%s"
Diag.D.LogSyncSnapshotSent = "[Sync] Snapshot sent to=%s req=%s raidNid=%s chunks=%d bytes=%d"
Diag.D.LogSyncChunkReceived = "[Sync] Chunk received from=%s req=%s part=%d/%d"
Diag.D.LogSyncChunkIgnored = "[Sync] Chunk ignored from=%s req=%s raidNid=%s"
Diag.D.LogSyncVersionMismatch = "[Sync] Version mismatch from=%s got=%s expected=%s"
Diag.D.LogSyncSyncSenderFailed = "[Sync] Sender failed from=%s req=%s reason=%s"
Diag.W.LogSyncRequestRateLimited = "[Sync] Request rate-limited sender=%s count=%d window=%ds"
Diag.W.LogSyncSenderNotOfficer = "[Sync] Ignored non-officer responder from=%s req=%s"
Diag.W.LogSyncChunkPartCountChanged = "[Sync] Chunk total changed from=%s req=%s raidNid=%s old=%d new=%d"
Diag.W.LogSyncChunkMalformed = "[Sync] Malformed chunk from=%s req=%s part=%s/%s"
Diag.W.LogSyncDecodeFailed = "[Sync] Payload decode failed from=%s req=%s raidNid=%s"
Diag.W.LogSyncParseFailed = "[Sync] Payload parse failed from=%s req=%s raidNid=%s"
Diag.E.LogSyncMergeFailed = "[Sync] Merge failed from=%s req=%s raidNid=%s err=%s"
Diag.D.LogSyncMergeApplied = "[Sync] Merge applied raidNid=%s raidId=%s from=%s bosses=%d loot=%d"
