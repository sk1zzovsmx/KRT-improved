# Changelog

All notable changes to !KRT will be documented in this file.

## Unreleased

Release-Version: 0.8.0-beta.1

## [0.8.0-beta.1] - 2026-06-05

### Documentation

- **Debug command reference** - Added `debug/README.md` under the addon root
  with all debug and related diagnostic slash commands plus copy-ready snippets
  for timer stats, synthetic raid rolls, Master Loot grid previews, SoftRes
  readiness, support reports, and performance spike capture.

### Fixes

- **Shared Loot History sources** - Bumped the raid SavedVariables schema to
  migrate legacy `Shared: Boss A / Boss B` loot-source labels into compact
  `Shared` rows with tooltip-only boss candidates, recover compact shared
  candidate metadata from item IDs when the static loot-source resolver is
  available during migration, kept CSV export on the compact label, and made
  Master Loot prefer the real boss context over shared static dataset fallback
  when the boss source is known.
- **Raid dataset coverage** - Added a build-time raid source generator and
  regenerated the Vanilla, The Burning Crusade, and Wrath loot-source shards
  from reviewed raid boss, world-boss, and encounter tables, keeping non-raid
  sections out of runtime data and preserving separate Classic/Wrath records
  for raids such as Naxxramas and Onyxia's Lair.
- **Naxxramas 25 loot-source data** - Corrected Seized Beauty (`40108`) so it
  is treated as a shared Naxxramas 25 drop across Anub'Rekhan, Grand Widow
  Faerlina, Instructor Razuvious, Noth the Plaguebringer, and Patchwerk.
- **Logger attendance boss participation** - Stopped loot-source attribution
  records such as `Shared: ...` from seeding or displaying boss attendance,
  so Attendance shows player participation only for actual boss fights.
- **Clear button localization** - Added the missing shared Clear button label
  so Loot Master, Loot History, and Spammer controls no longer display `BtnClear`.
- **MS Changes removal** - Removed the retired MS Changes window, minimap
  menu entry, slash commands, localization strings, controller, XML layout,
  and public Raid change-management APIs. Legacy `raid.changes` data remains
  tolerated during SavedVariables normalization and old sync payload parsing
  so existing raid history can still load safely.

- **Wrath raid loot-source recognition** - Expanded the Naxxramas 10/25
  and Onyxia level 80 loot-source tables from the local raid dataset so
  Logger source attribution recognizes missing boss drops such as
  Dawnwalkers, Rescinding Grips, Mantle of the Locusts, and Flowing
  Sapphiron Drape, while keeping classic Onyxia data separated from Wrath
  raid-size modes and shared Naxxramas drops ambiguous until recent boss
  context can disambiguate them.
- **Loot record reconciliation** - Trade-only fallback records now merge into
  matching loot-session rows instead of creating duplicate Logger entries for
  the same item, source, and looter.
- **Group Loot logger attribution** - Passive Group Loot entries now observe
  Need, Greed, and Disenchant selection/roll metadata before final loot is
  saved and resolve their source through the static raid loot-source table, so
  the Logger Type, Roll, and Source columns are populated for attributed raid
  drops. Late roll metadata can upgrade the already-saved winner row, and
  passive Group Loot no longer falls back to the current manual roll mode or
  displays unknown roll metadata as Manual when no roll metadata is available.

### Enhancements

- **Master Loot assignment grid** - Replaced the manual Master Loot candidate
  dropdown flow with a native Blizzard-style KRT grid that expands to the
  current candidate count without scrolling, confirms above-threshold awards
  through a standard StaticPopup, and uses the same grid for Hold, Bank, and
  DE target selection without awarding loot.
- **Master Loot grid debug view** - Added `/krt debug mlgrid [1-40]` to open
  the native grid with a configurable fake player count for layout testing,
  and to let the item-click popup use real roster names plus fake fillers when
  no live Blizzard Master Loot candidates are available. Debug rows never award
  loot.
- **Loot method automation** - Added opt-in Master Loot options to switch
  to Master Loot when a raid leader targets a recognized raid boss and to
  show a configurable KRT screen notice when it fires, then ask
  before restoring Group Loot after boss loot is cleared.
- **Opened-loot autospam** - Added opt-in Master Loot options to announce
  opened loot automatically and, when enabled with loot autospam, add SoftRes
  player lines only for opened items that have current-raid SoftRes players.
  Loot spam now names the current loot target when the client exposes one and
  groups reserved-item lines after the full opened-loot list.
- **SoftRes import wizard** - Reworked the SoftRes import popup into a compact
  chooser with explicit Multi-reserve/Plus System and JSON/CSV buttons, defaulting
  to JSON for supported compressed and plain reserve export payloads, bundling
  decompression support so compressed imports decode without extra dependencies,
  while keeping CSV imports available. Encoded JSON imports now stay in one
  un-sourced reserve group instead of inferring boss labels from static
  loot-source data.
- **Master Loot flow visibility** - Added readable loot workflow snapshots,
  SoftRes present/missing and loot-copy summaries in roll display models,
  `tie_start` distribution updates for tie rerolls, and compact session winner
  summaries that distinguish automatic winners from tied candidates.
- **Interface Options panel** - Added a KRT entry under
  Interface > AddOns that mirrors the existing configuration controls while
  keeping the Loot Master configuration popup available in its current workflow.
  The AddOns entry now uses KRT subcategories for Master Loot, Loot History,
  LFM Spam, Raid Warning, and Help, with the Master Loot options panel
  scrollable and grouped slash-command guidance available under Help.
- **Interface Options layout renderer** - Added a local options layout renderer
  with fixed text and command columns for every KRT AddOns subpanel, without
  adding an external options dependency.
- **Interface Options overview** - Added a short overview to the root KRT
  AddOns panel explaining what the addon does, how it works, and why to use it.
- **Configuration popup footer** - Removed the old author/link footer from the
  custom configuration popup and moved the bottom controls into the freed space.
- **Countdown duration slider** - Changed countdown duration selection to snap
  to a discrete 3-to-60 second ladder instead of fixed five-second steps.
- **Master Loot option descriptions** - Added short explanations to each
  Master Loot option in Interface > AddOns while keeping the custom popup compact.
- **Master Loot preset layout** - Kept the Defaults preset in the preset button
  row and moved the preset descriptions/buttons onto a fixed grid so they no
  longer overlap the countdown slider area or each other in Interface Options.
- **Raid Warning panel layout** - Narrowed the description and command columns
  so text and buttons no longer clip inside Blizzard's AddOns options panel.
- **Loot History maintenance panel** - Added Interface > AddOns commands to
  show a live Loot History report, purge history, rebuild missing loot sources,
  and run a cleanup popup for empty raid logs, non-epic loot rows, and
  non-empty raids without boss encounters.
- **Loot History cleanup popup layout** - Reworked the selectable cleanup
  popup into fixed option rows so labels and descriptions no longer overlap.
- **Loot History sync controls** - Added Interface Options controls for
  persistent logger sync, passive Group Loot ignore, targeted require/push
  player names, and a current-raid Sync Now command.
- **Loot History quality threshold** - Added a Logger quality override in
  Interface Options so Loot History can record only Poor, Uncommon, Rare,
  Epic, or Legendary-and-above loot, defaulting to Epic instead of the raid's
  current loot threshold.
- **Interface Options control center** - Expanded the remaining KRT AddOns
  subpanels with Loot History data-health reporting, Master Loot presets and
  announcement preview, LFM Spam message preview and controls, Raid Warning
  stock templates, saved-warning cleanup, and preview, plus command
  permission/diagnostic guidance in Help.
- **Raid Warning stock templates** - Fresh installs now start with the six
  stock Raid Warning templates, the Add Templates command was removed from the
  AddOns panel, and Clear All now asks whether stock warnings should be deleted.
- **LFM Spam panel controls** - Added a Clear command beside Refresh in
  Interface Options so the saved LFM message draft can be reset without opening
  the custom spammer frame.
- **LootFrame SoftRes hints** - Reserved loot items in the Blizzard loot
  window now show a colored reserve border and append a `Reserved by` section
  to the item tooltip with the reserving player names.
- **Logger views** - Split the old combined logger minimap entry into
  dedicated Loot History and Raid Attendance windows, so attendance can be
  opened as its own frame instead of as a tab inside loot history.
- **Loot Reserve empty import** - The Loot Reserve window now keeps its
  left action button visible when the reserve list is empty and switches it
  from Clear Loot Reserve to Import, matching the Loot Master shortcut.
- **Minimap raid menu** - Reordered the minimap menu into grouped raid
  workflow sections for Loot Master, Loot Reserve, Loot Counter, Loot History,
  Raid Attendance, Raid Warning, LFM Spam, and Clear Raid Icons.
- **Loot workflow hardening** - Loot ingestion now uses focused internal
  workflow, receipt, record, and reconciliation helpers so parsed loot events,
  canonical record creation, and passive/trade duplicate handling are easier
  to audit without changing Loot Master award policy.
- **SoftRes imports** - Reserve import now accepts encoded SoftRes JSON
  exports in addition to the existing CSV flow, preserving the same Multi
  and Plus aggregation rules after parsing.
- **SoftRes aliases** - Added manual SoftRes name aliases for cases where
  imported reserve names differ from raid roster names, including local
  readiness reporting and `/krt sr alias` management commands.
- **Roll resolution policy** - Extracted roll resolver ordering into
  dedicated strategy helpers for normal, SoftRes, tie, and raid-roll flows
  while preserving the existing display model fields.
- **Distribution sync protocol** - Extended the `KRTDist` session protocol
  with versioned snapshots, roll countdown ticks, tie state, and awarded
  state plus versioned item, roll, done, clear, snapshot, tick, tie, and
  awarded messages.
- **Strict schema cleanup** - Removed retired runtime aliases, old SavedVariables
  fallbacks, flat option migration, and stale compatibility fixtures so fresh
  installs use the current strict SavedVariables schema directly.
- **Master Loot distribution session** - Master Loot now maintains a compact
  loot distribution session and syncs item, roll-start, winner, and done state
  through addon messages so raiders can consume a read-only corpse/session
  queue without changing KRT award policy.
- **SoftRes roll eligibility** - SR rolls now accept only in-raid players
  who reserved the current item, keep out-of-raid reservers visible as
  ineligible context, and expose SR reserve counts through the roll display
  model.
- **SoftRes name-match report** - Reserves now exposes a read-only runtime
  report for imported names that do not exactly match the current raid
  roster, including strong/weak suggestions for local readiness checks.
- **SoftRes readiness report** - Reserves now exposes a consolidated
  read-only readiness report for item, roster, and name-match context.
- **Roll visibility** - Duplicate roll attempts now stay out of resolver
  candidates but remain visible on the accepted roll row with a `DUP` info
  tag for easier Master Loot review.
- **Duplicate roll detail** - Duplicate roll attempts now keep the last
  ignored roll value, denial reason, and source in the roll display model for
  diagnostics while leaving the Master roll list visually unchanged.
- **SoftRes readiness command** - Added local `/krt res check` and
  `/krt sr check` reports for current-item SoftRes coverage, roster/import
  readiness, and possible name mismatches without announcing to raid or
  changing imported reserve data.
- **SoftRes health audit** - Extended the local SoftRes readiness report
  with read-only health severity and issue counts for missing import data,
  current-item coverage, imported names outside raid, raid members without
  exact SoftRes, and suggested name matches.
- **Master workflow state cleanup** - Master status rendering now uses a
  named workflow-state model for ready, rolling, SR rolling, tie resolution,
  inventory, trade, and multi-award states while preserving existing user
  behavior and status text.
- **Master workflow button state** - Master button and tooltip refresh now
  consume the workflow-state capability model for roll starts, SR starts,
  awards, reserve-list access, self-rolls, and loot spam visibility without
  changing the existing gating behavior.
- **Raid loot-source database** - Added a static item-to-NPC loot source
  resolver for Vanilla, The Burning Crusade, and Wrath raid boss/encounter
  drops so passive Group Loot and Need Before Greed logging can attribute
  items by item ID before timing-based fallbacks run. Shared boss items now
  use matching recent boss context when available, otherwise they stay visible
  as `Shared: Boss A / Boss B` instead of falling back to TrashMob.
- **Group Loot parsing performance** - Passive Group Loot winner messages now
  reuse the parsed result when materializing logger entries, avoiding repeated
  winner-pattern parsing during loot-chat bursts. Burst roll metadata now
  reuses the first captured boss context for nearby `START_LOOT_ROLL` events,
  stores native roll session metadata by `rollId`, and passive
  Need/Greed/Disenchant entries skip unnecessary LootCounter count calls.
  Repeated winner checks for the same loot-chat message now reuse the previous
  parse result, and append-only loot logging patches the runtime loot index
  instead of dropping the whole raid runtime cache. `CHAT_MSG_LOOT` now uses a
  winner-only passive parser path, and Logger loot refreshes are filtered by
  selected raid and debounced during loot bursts.
- **Group Loot loot-window fetch** - Passive Group Loot observers now skip the
  repeated `LOOT_SLOT_CLEARED` loot-window refetch path when they are not the
  master looter, keeping the chat-driven logging flow intact while cutting the
  hottest refresh loop that was causing the lag.
- **Group Loot lightweight logger** - Passive Group Loot and Need Before Greed
  logger rows now skip corpse/source attribution and keep only the item,
  winner, roll type, and roll score in the hot chat path to reduce loot-burst
  lag while leaving non-passive source tracking intact.
- **Logger tabs** - Reworked Logger history into focused `Loot` and
  `Attendance` tabs. The Loot tab now shows the raid list with raid loot,
  while the Attendance tab shows raid attendees and the selected player's boss
  participation.
- **Logger list visuals** - Refreshed Logger table rows, headers, selection
  highlights, and loot column spacing while preserving the current Loot and
  Attendance tab layout.
- **Logger Attendance spacing** - Tuned the Attendance tab player and boss
  columns to reduce name truncation without changing the current tab layout.
- **Logger dynamic columns** - Logger table columns now derive their widths
  from the visible list frame so Loot and Attendance panels use available
  space more evenly and reduce clipped values.
- **Logger header alignment** - Logger table headers now include the same
  visual spacing used by row columns so labels align with Loot, Attendance,
  Boss, and Raid list content.
- **Logger row striping** - Logger zebra striping now follows the visible row
  position after sorting instead of moving with the underlying record.
- **Logger header tabs** - Logger column headers now render as distinct dark
  Wrath-style tabs with subtle metallic edges for clearer table separation.
- **Logger header geometry** - Logger header tabs are now positioned from the
  same row geometry used by visible list content so columns stay aligned.
- **Logger Attendance columns** - Raid Attendance rows now reserve more space
  for Join/Leave timestamps to avoid clipping full `HH:MM` values.
- **Logger row width** - Logger list rows now resync to the current scroll
  frame width on refresh so row striping spans the full visible table.
- **API surface cleanup** - Removed unused internal compatibility aliases,
  obsolete global helper injections, dead Bus/UI/Timer APIs, duplicate
  LibCompat bootstrap includes, feature override hooks, unused Time helpers,
  a redundant Bus registration helper, and the callback-statistics debug command.
- **API reduction pass 2** - Removed orphan Roll-Service wrappers in
  `Services/Rolls/Service.lua` (`DidRoll`, `GetCandidateEligibility`,
  `SetManualExclusion`, `IsManuallyExcluded`,
  `GetUsedReserveCount`, `GetRollSessionItemKey`, `GetDisplayedWinner`) and
  corrected a reserve readiness exact-match path in `Services/Reserves/Display.lua`
  (`normalizeAliasKey` in `splitExactNameMatches`).
- **Roll response API cleanup** - Collapsed the explicit pass/cancel roll
  response helpers into the canonical `SetPlayerResponse(name, status)`
  contract using `PASS` and `CANCELLED` statuses.
- **SoftRes contract cleanup** - Kept slash/UI-facing SoftRes facade methods
  public, moved sync-only payload/cache intake helpers to the package-internal
  `_Sync` surface, and removed test-only reserve lookup wrappers from the
  public service surface.
- **Master planner adapter naming** - Renamed private Master helpers that adapt
  Loot service planner output to UI/trade side effects so they no longer look
  like duplicate pure planner contracts.
- **Internal helper deduplication** - Collapsed repeated Logger multiselect
  focus adapters, reused Spammer cycle callbacks, and renamed generic timer
  callback helpers so the function inventory better reflects real ownership.

### Fixes

- **Slash controller dispatch** - Slash warning announce and LFM start/stop
  commands now resolve through their controller dispatch contracts correctly.
- **Group Loot passive state cleanup** - Removed per-message full scans of the
  passive Group Loot roll table from hot parser paths by purging only entries
  touched by the current message, reducing frame-time spikes during roll/chat
  bursts. System-chat Group Loot parsing now also exits early when no native
  passive roll session is active, avoiding pattern scans on unrelated system
  messages.

## [0.7.1-beta.3] - 2026-05-03

### Enhancements

- **Group Loot frame access** - Loot Counter and the Master Looter frame can
  be opened manually while the raid uses Group Loot or Need Before Greed,
  while master-loot-only actions and automatic Master frame opening remain
  gated behind Master Looter access.

### Fixes

- **LootCounter scrolling** - Fixed the Loot Counter frame so moving the
  scrollbar also scrolls the player list instead of only moving the thumb.
- **SoftRes sync transport** - SoftRes sync now warns when no group
  addon-message transport is available instead of reporting a sent request
  while solo.

## [0.7.1-beta.1] - 2026-04-27

### Enhancements

- **LootCounter reliability** - Master-loot awards now queue LootCounter
  credit from the KRT award action, confirm it on loot-slot clear events, and
  cancel it on visible UI failure messages or timeout instead of depending
  only on range-limited loot chat observation.
- **Slash diagnostics** - Added focused `/krt help <command>` pages plus
  `/krt version` and `/krt bug` local diagnostic summaries for support.
- **Performance diagnostics** - Added runtime-only `/krt perf on|off` logging
  with a configurable `/krt perf threshold <ms>` slow-block threshold for loot
  and group-loot spike investigation.
- **Group version check** - `/krt version` now requests KRT version details
  from grouped addon users through a dedicated addon-message prefix.
- **SoftRes runtime sync** - Added lightweight `/krt res sync` support for
  grouped KRT clients to request runtime-only SoftRes metadata/data from an
  authorized reserve owner without persisting received reserves.
- **SoftRes item metadata** - Reserve item queries now use the shared item
  cache loader, so missing item names/icons can populate automatically once
  the 3.3.5a client item cache resolves.
- **Master item metadata** - Current Master Loot item views now refresh from
  the shared item cache loader when inventory/manual item metadata resolves
  after initial selection.
- **Whisper SoftRes replies** - Added opt-in `!sr`/`!softres` whisper replies,
  with `sr`/`softres` fallback aliases for private servers that reserve `!`
  commands, so ML/leader/assistant clients with reserve data can send a player
  their current reserves in chat-safe whisper lines.
- **Auto-loot suggestions** - Added a lightweight suggestion-only loot rules
  classifier for ignored items, enchanting materials, and quality BoE loot,
  including 3.3.5a tooltip-based bind detection; it does not auto-award or
  auto-trade items.
- **Logger UI polish** - Refreshed the Logger toward a Wrath raid-log look
  with dark compact tables, yellow section titles, out-of-panel controls, and
  green selected rows.
- **Raid attendance ledger** - Added a per-player attendance ledger keyed by
  `playerNid`, updated from roster deltas, persisted as raid schema v4, and
  exported through a dedicated attendance CSV builder without replacing the
  existing loot-oriented raid export.
- **Loot source recovery** - Reworked loot-source recovery to prefer recent
  `UNIT_DIED` context backed by `LibBossIDs` for loot windows and passive
  group-loot roll sessions, while removing the raid-target scan that could
  stall the client during looting.
- **Performance: trash death context** - Throttled repeated trash
  `UNIT_DIED` context updates so large group-loot pulls do not rewrite the
  same loot-source state for every dying mob.
- **Performance: recent death TTL** - Shortened the `UNIT_DIED`
  recent-death context window used by group-loot source recovery without
  reducing group-loot roll/session TTLs.
- **Performance: trash death filtering** - Trash `UNIT_DIED` events now seed
  recent-death loot context only while a boss context is still recoverable,
  with a lightweight activity timestamp keeping burst TTLs anchored to the
  latest trash death without repeated full context writes.
- **Passive group-loot logger filter** - Group Loot and Need Before Greed
  passive logging now skips green-quality drops, gems, and recipes so DE/Greed
  filler items do not clutter the raid logger.
- **Performance: Bus event dispatch** - Eliminated per-fire table allocation
  in `Bus.TriggerEvent`; reuses a static dispatch buffer to reduce GC pressure
  during active raiding (dozens of events/second).
- **Performance: Proc glow animation** - Throttled sparkle `OnUpdate` to ~30 FPS
  (was unthrottled at 60 FPS), cutting `SetPoint` layout recalculations by half
  during glow effects.
- **Performance: Roll UI model** - Decorated roll rows in-place instead of
  allocating + copying a new table per visible row per refresh; also simplified
  `copyVisibleRollRows` to reference existing rows directly.
- **Performance: Loot window item info** - When loot-slot hints are available
  (loot window path), skip the blocking `GetItemInfo` call and defer tooltip-
  based item cache warming through a timer queue, avoiding micro-freezes on
  `LOOT_OPENED` with many items. Auto-loot suggestion metadata now follows the
  same deferred path, so BoE tooltip checks no longer run synchronously while
  the loot window opens.
- **Performance: Passive group loot** - Reuse a static `numbers` buffer in
  `extractGroupLootPatternValues` instead of allocating a new table per
  parsed loot message.

### Internal

- Consolidated `Services/Raid/Boss.lua` and `Services/Raid/Changes.lua` into
  `Services/Raid/Session.lua`; removed 2 redundant thin-wrapper files.
- Consolidated `Services/Loot/Sessions.lua` into `Services/Loot/State.lua`;
  removed 1 redundant thin-wrapper file.
- Cleaned `Services/Loot/PendingAwards.lua` public surface: removed 13
  internal helpers that were unnecessarily exported; only
  `NormalizePendingAwardItemKey` remains exposed for cross-module use.
- Removed 9 pure pass-through `PassiveGroupLoot` wrappers from
  `Services/Loot/Service.lua`; internal callers now call
  `PassiveGroupLoot.*` directly.
- Removed redundant `normalizeCandidateKey` local from
  `Services/Rolls/Service.lua`; calls `Sessions.NormalizeCandidateKey`
  directly.
- Removed 3 pass-through format methods from `Services/Reserves.lua`;
  `Widgets/ReservesUI.lua` now uses inline `L.*` format calls directly.
- Simplified verbose `getRaidService()` pattern in 3 Loot service files
  to the concise 1-line variant.
- Removed inline fallback loop from `resolveLootLooterName` in
  `Services/Loot/Service.lua`; delegates to canonical
  `Roster:GetPlayerName` instead of reimplementing player-by-NID lookup.
- Replaced inline `string.find` item-link parsing in
  `Services/Loot/Service.lua` with canonical `Item.GetItemStringFromLink`
  and `Item.GetItemIdFromLink`; removed unused `ITEM_LINK_PATTERN` local.
- Centralized `requireServiceMethod` in `Database.RequireServiceMethod`;
  removed 4 identical copies from Controllers (Master, Warnings, Spammer,
  Changes).
- Removed `resolveRaidDifficulty` and `getRaidSizeFromDifficulty`
  pass-through wrappers from `Services/Raid/Session.lua`; call sites use
  internal `_ResolveRaidDifficultyInternal`/`_GetRaidSizeFromDifficultyInternal`
  directly.
- Eliminated `getRaidService()` wrapper functions from 5 Service files
  (Chat, Rolls/Service, Loot/Service, Loot/PassiveGroupLoot, Loot/Tracking);
  replaced with direct `Services.Raid` access.
- Removed `getLootModule()` pass-through from `Services/Rolls/Service.lua`;
  replaced with direct `Services.Loot` access.
- Simplified 6 defensive item-helper wrappers in `Controllers/Master.lua`
  to direct `Loot.*` delegation (load order guarantees availability).
- Added `UIScaffold.EnsureModuleUi(module)` factory in `Modules/UI/Frames.lua`;
  replaced 8 identical inline `_ui` schema initializations across Controllers
  and Widgets with single-line factory calls.

### Fixed

- Fixed Master loading on Lua 5.1/WoW clients by reducing chunk-scope locals in
  `Controllers/Master.lua`.
- Fixed Master assignment dropdown clicks (`Hold`/`Bank`/`Disenchant`) using the
  wrong `UIDropDownMenu` callback argument order, which could trigger
  `UIDropDownMenu.lua:862` (`filterText` nil) on selection.
- Fixed multi-item boss loot attribution in Master Loot windows: once the first
  item resolves the boss correctly, later items from the same open boss loot
  window now keep that scoped boss context instead of falling back to
  `_TrashMob_` after the short event context expires.
- Fixed Award and Hold/Trade boss propagation so loot-window event context is
  snapped on open, carried on the roll session, and reused by trade-only
  fallbacks instead of reclassifying the loot source late.
- Tightened Boss/Trash attribution on `LOOT_OPENED`: an explicitly opened
  non-boss corpse now blocks recent boss-context recovery, while boss corpse
  mouseover can restore the correct boss scope without relying on late loot
  receipt heuristics.

## Archived (not published)

### [0.7.0-beta.3] - 2026-04-06

### Added

- Added dedicated `Services/Raid/*` modules (`State`, `Roster`, `Counts`,
  `Session`, `Boss`, `LootRecords`, `Changes`, `Capabilities`) so raid data,
  loot ownership, roster helpers, loot-counter state, and capability checks now
  expose focused canonical APIs outside the old monolithic `Services/Raid.lua`.
- Added canonical raid capability and loot-context APIs such as
  `CanUseCapability`, `EnsureMasterOnlyAccess`, `CanBroadcastChanges`,
  `FindAndRememberBossContextForLootSession`, and `FindOrCreateBossNidForLoot`
  to centralize controller/service access rules.
- Added changelog-driven GitHub release note generation in `tools/krt.py` and
  the publish workflow, with concise `Included Commits`,
  `New Functionality`, and `Enhancements/Improvement` sections.

### Changed

- Split the previous monolithic `Services/Raid.lua` implementation into focused
  `Services/Raid/*` files and migrated loot/runtime call-sites to canonical
  Raid/Loot service ownership, reducing redundant bridge wrappers and aliases.
- Aligned the remaining loot-bridge APIs to the repo verb taxonomy and
  canonical PascalCase contracts, then refreshed API catalogs and cleanup docs
  to match the reduced public surface after the cleanup wave.
- GitHub release publishing now uses changelog-derived summaries plus an exact
  commit-range compare link instead of raw auto-generated release notes.

### [0.7.0-beta.2] - 2026-04-06

### Added

- Introduced scoped loot-boss session tracking for passive Group Loot and
  trade follow-up flows, so later loot receipts can reuse the original boss
  context without relying on implicit `lastBoss` inheritance.

### Changed

- Tightened boss/trash loot association policy: loot records now resolve
  `bossNid` from scoped roll-session context (including passive Group Loot
  sessions) and only use short-lived boss-event context for non-passive flows.
  The previous recent-boss and current-target recovery heuristics were removed,
  and missing scoped context now falls back directly to `_TrashMob_`.
- Localized the synthetic trash bucket label through `L.StrTrashMobName`
  while keeping legacy `_TrashMob_` compatibility in logger and validator
  flows.

### Fixed

- Fixed incorrect boss attribution in loot history when scoped context was
  missing or stale: loot receipts no longer recover boss ownership from recent
  kills or the current target and now fall back cleanly to the trash bucket.
- Fixed trade-only loot and roll-session lookups inheriting stale boss context
  from implicit `lastBoss`; they now use explicit/scoped context with the same
  trash fallback policy.

## [0.7.0-beta.1] - 2026-04-05

### Added

- Extended synthetic raid-roll debug helper: `/krt debug raid rolls` now
  accepts optional `tie` mode (`/krt debug raid rolls tie`) to submit
  deterministic high-priority ties across a random 2-3 subset of synthetic
  players, making tie-resolution testing faster.

### Changed

- Logger loot now shows the item tooltip on mouse over the item icon only and
  anchors it to the cursor, with an `itemId` fallback hyperlink when a stored
  `itemLink` is missing.
- Countdown late-roll handling now honors `countdownRollsBlock`: when disabled,
  rolls submitted after countdown expiry remain accepted and are marked as
  `OOT` in the rolls Info column, but `OOT` responses are excluded from
  resolver candidates, manual winner selection, and tie-reroll triggers.
- Improved Master status readability: long status lines now wrap instead of
  clipping (for example countdown-bypassed rolling status), and the rolls
  header/list anchors were shifted to preserve spacing.
- Hardened master-looter-only behavior in raid context:
  non-master clients no longer run loot/roll ingestion
  (`CHAT_MSG_LOOT`/`CHAT_MSG_SYSTEM`) and slash/minimap
  entrypoints now block master-only modules.
- Restored passive Logger history for non-master loot modes:
  Group Loot / Need Before Greed outcomes now log into the
  current raid history with `NE`, `GR`, and `DE` roll types
  while keeping master-only gameplay flows blocked. When the
  server also emits numeric group-roll lines, the Logger now
  preserves that `rollValue` too. Passive winner messages now
  materialize Logger rows immediately, while later duplicate
  loot receipts are deduplicated. Self roll lines now feed the
  same `rollValue` pipeline, and late numeric passive updates can
  backfill a winner row that was logged before the value arrived.
  Raw chat lines such as "Need Roll - 67 for ... by ..." are now
  parsed too, so those values no longer fall through as passive
  zero-value wins.
- Centralized raid-role capability checks so loot, raid-warning,
  changes broadcast, ready-check, and raid-icon actions derive
  their enabled/disabled state from a shared policy.
- Published release metadata now uses SemVer forms
  (`x.y.z`, `x.y.z-alpha.N`, `x.y.z-beta.N`) in `Release-Version`
  and TOC versioning so workflows and packaged assets resolve
  consistently.
- Temporarily disabled the Logger Export tab again while the
  export workflow remains staged off.
- Extracted Logger Store/View/Actions into `Services/Logger/Store.lua`,
  `Services/Logger/View.lua`, and `Services/Logger/Actions.lua`;
  `Controllers/Logger.lua` now imports them via `addon.Services.Logger`.
  No behavior changes.
- Started the Changes slimdown implementation without adding new service files:
  raid-scoped changes CRUD, broadcast capability checks, and announce/demand
  text builders now live in `Services/Raid.lua`, while
  `Controllers/Changes.lua` is reduced to UI state, list rendering, and action
  wiring. No behavior changes.
- Continued slimdown with Spammer phase 2 without adding new service files:
  spam output building, duration normalization, channel send path, and
  runtime cycle state/timer control now live in `Services/Chat.lua`
  (`BuildSpammerOutput`, `NormalizeSpamDuration`, `SendSpamOutput`,
  `GetSpamRuntimeState`, `StartSpamCycle`, `PauseSpamCycle`,
  `StopSpamCycle`), while `Controllers/Spammer.lua` stays focused on
  refs/binding, localization, input lock visuals, countdown text, and refresh.
  No behavior changes.
- Continued with conservative Warnings phase 3: kept warning CRUD/UI ownership
  in `Controllers/Warnings.lua` and extracted only the announce path into
  `Services/Chat.lua` via `NormalizeWarningMessage` and
  `AnnounceWarningMessage` (including raid-warning permission fallback notice).
  No behavior changes.
- Started Master phase 4 micro-extractions without adding new service files:
  held-inventory loot slot matching/resolution moved to `Services/Raid.lua`
  (`MatchHeldInventoryLoot`, `ResolveHeldLootNid`), while winner/tie helpers
  and countdown lifecycle APIs are now exposed by `Services/Rolls/Service.lua`
  (`GetResolvedWinner`, `ShouldUseTieReroll`,
  `StartCountdown`, `StopCountdown`, `FinalizeRollSession`).
  `Controllers/Master.lua` now delegates to those services with local
  compatibility fallbacks. No behavior changes.
- Continued Master phase 4 countdown cleanup: `Controllers/Master.lua`
  no longer owns local countdown runtime state/timers and now derives
  countdown state from `Services/Rolls/Service.lua` (`IsCountdownRunning`) while
  delegating start/stop/finalize entirely to Rolls service APIs.
  No behavior changes.
- Completed dedicated Master hardening step before fallback removal:
  `Controllers/Master.lua` now validates required Raid/Rolls method contracts
  at load time and uses direct service calls for winner/tie resolution,
  held-loot resolution, candidate resolution, expected-winner sync, and
  countdown lifecycle (removed legacy compatibility fallback branches).
  No behavior changes.
- Applied the same dedicated hardening to the remaining slimdown controllers:
  `Controllers/Changes.lua`, `Controllers/Spammer.lua`, and
  `Controllers/Warnings.lua` now validate required service contracts at load
  time and use direct service calls (removed residual compatibility fallback
  branches to Raid/Chat). Test harness service defaults were aligned to the
  hardened contracts. No behavior changes.

### Fixed

- Fixed single-winner tie flow in Master UI: tie reroll is now available
  even when the winner list is in pick mode and no manual winner has been
  selected yet.
- Master roll intake now reopens correctly after `MS/OS/SR/FREE`
  announcements even when the Rolls service pre-bootstraps the roll session;
  opening roll intake restores the canonical `rollStarted` state so countdown
  can be started again from the Countdown button.
- Isolated passive Group Loot pending awards from Master Looter
  award resolution: switching from Group Loot/NBG to ML no
  longer reuses stale `GL:*` pending sessions on the first
  ML award.
- Hardened Master loot-slot resolution so award/trade flows keep matching
  the same item even when the live loot window hyperlink payload differs
  from the stored item link; multi-award slot scanning now uses the same
  itemId fallback.
- Hardened boss-context recovery for loot logging: boss events now populate
  a dedicated short-lived context independent from `lastBoss`; loot logging
  consumes that event context first, then falls back to recent real boss
  kills and only finally to the current target / `_TrashMob_`.

## [0.6.2b] - 2026-03-21

### Changed

- Disabled the Logger Export tab by default while the export workflow remains work in progress.

## [0.6.0b] - 2026-03-08

### Changed

- Added new feature
