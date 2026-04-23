# Changelog

This project follows a simple rule: every user-visible or behavior change gets an entry here.
Dates are in YYYY-MM-DD.

## Unreleased
- **Performance:** Loot-window fetch now defers tooltip-based item cache warming
  through a timer queue, reducing `LOOT_OPENED` frame spikes when many items
  are uncached.
- **UI:** Logger loot now shows the item tooltip on mouse over the item icon
  only and anchors it to the cursor, with an `itemId` fallback hyperlink when
  a stored `itemLink` is missing.
- **UI:** Master now disables `MS/OS/SR/FREE` while countdown is running,
  and roll-start actions are ignored until countdown is stopped/finalized.
- **Debugging:** `/krt debug raid rolls` now accepts optional `tie` mode
  (`/krt debug raid rolls tie`) to submit deterministic high-priority ties
  across a random 2-3 subset of synthetic players, making tie-resolution
  testing faster.
- **Behavior:** When `countdownRollsBlock` is disabled, rolls submitted after
  countdown expiry remain visible as `OOT` in the rolls `Info` column, but are
  excluded from resolver candidates, manual winner selection, and tie rerolls.
- **Bugfix:** Single-winner ties can now reroll correctly even while the
  Master UI winner list is in pick mode and no manual winner has been selected
  yet.
- **UI:** Master long workflow status lines now wrap instead of clipping, and
  the rolls header/list anchors were retuned to preserve spacing for longer
  messages.
- **Behavior:** Non-master clients no longer run master-loot loot/roll
  ingestion from `CHAT_MSG_LOOT` or `CHAT_MSG_SYSTEM`, and slash/minimap
  entrypoints now block master-only modules.
- **Behavior:** Passive Group Loot / Need Before Greed results now populate
  Logger history with `NE`, `GR`, and `DE` roll types, preserve numeric
  `rollValue` when available, deduplicate duplicate loot receipts, and
  backfill late numeric updates.
- **Bugfix:** Passive Group Loot pending awards are now isolated from Master
  Looter award resolution, so switching from Group Loot/NBG to ML no longer
  reuses stale `GL:*` pending sessions.
- **Behavior:** Raid-role capability checks are now centralized across loot,
  raid-warning, changes broadcast, ready-check, raid-icon, and grouped-count
  announce actions.
- **UI:** Loot Counter now exposes a `Spam Counter` button that announces grouped
  MS counts in chat using `+N` buckets (for example `+1: Name1, Name2`).
- **UI:** Loot Counter now includes a `Reset All` button with confirmation popup
  to prevent accidental full counter resets.
- **Behavior:** Loot Counter grouped-count announce now requires raid lead or
  assistant permission while in raid.
- **UI:** Loot Counter table styling is now clearer: stronger
  column header contrast, zebra rows, highlighted non-zero rows, and
  color-coded `MS/OS/FREE` counters for faster scanning.
- **UI:** Scroll-list panels now reserve the scrollbar column only when there
  is real vertical scroll range, removing the apparent right-side truncation
  on short lists across Loot Counter and other list-controller based frames.
- **UI:** Fine-tuned scroll-list right inset by 1px when scrollbar space is
  reserved, removing the residual hairline gap on list/table right edges.
- **UI:** Logger tables now force `rightInset = 0` in their list-controller
  config because Logger XML already reserves the scrollbar column; this avoids
  double right trimming in Logger list rows.
- **Tooling:** Release channel resolution is now driven by
  `!KRT/CHANGELOG.md` `Release-Version` SemVer values: `x.y.z-alpha.N`
  stays internal, `x.y.z-beta.N` publishes as a GitHub prerelease, and
  `x.y.z` publishes as a stable release.
- **Tooling:** Release publication now requires a strictly newer SemVer
  than the previous ref. `0.6.0-beta.1 -> 0.6.0-beta.2` and
  `0.6.0-beta.2 -> 0.6.0` publish, while unchanged or downgraded versions
  do not.
- **Tooling:** Added `tools/krt.py` as the canonical cross-platform entrypoint
  for repo workflows such as release packaging, hook install, Mechanic calls,
  MCP startup, and readiness checks on both Windows and Linux.
- **Tooling:** GitHub release packaging now uses
  `tools/krt.py build-release-zip`, and the repo-local pre-commit hook now
  enters through the same Python CLI before delegating to the existing
  PowerShell gates.
- **Release:** GitHub packaging now uploads both `KRT-<tag>.zip` and
  `KRT-<tag>.zip.sha256`; the legacy `tools/build-release-zip.ps1` path
  remains only as a compatibility shim around the same Python owner.
- **Release:** Published release tags and assets are now immutable per
  SemVer version: workflows refuse to move an existing version tag or
  clobber assets on an existing GitHub release.
- **Regression/Bugfix:** Manual release creation keeps strict tag validation
  (`--verify-tag`) to block non-tag refs.
- **Regression/Bugfix:** Release upload now falls back gracefully to ZIP-only
  when a checksum asset is unexpectedly missing.
- **Tooling:** `workflow_dispatch` no longer uses a stale default branch;
  empty `target_ref` now falls back to the current ref.
- **Docs:** GitHub release download/checksum instructions now live in
  `docs/RELEASE_DOWNLOAD.md` (instead of root `README.md`) and include a
  quick SHA-256 verification step.
- **Behavior:** SR announce lines in Master now exclude reserve names that are
  not part of the current raid roster.
- **UI:** Master `SR` button now lights/enables only when at least one reserve
  player for the selected item is present in the current raid roster.
- **UI:** Logger now shows panel-level empty states and orientation hints for
  history and export views, so raid, boss, attendee, loot, and CSV panes stay
  readable even before a selection exists.
- **UI:** Master action buttons now expose contextual tooltips that explain the
  current action, winner target, reserve availability, and countdown behavior.
- **UI:** Master now shows contextual workflow status under the selected item,
  and Logger panel titles now include live counts plus raid, boss, and player
  context for faster navigation.
- **Bugfix:** Master roll intake now reopens correctly after `MS/OS/SR/FREE`
  announcements even when the Rolls service pre-bootstraps the roll session;
  opening roll intake restores the canonical `rollStarted` state so countdown
  can be started again from the Countdown button.
- **Bugfix:** Rolls now materialize reserved candidates correctly even when the
  reserves adapter is exposed as plain functions, so closed reserved sessions
  render `TIMED_OUT` rows again; compact `TIE/PASS/CXL/OOT/OUT/BLK` info tags
  also fall back safely when localization tables are not fully bootstrapped.
- **Bugfix:** Master inventory award flow now treats roll rows as selectable
  unless explicitly disabled by the service contract, validates multi-copy
  inventory selections before trade, advances the next selected winner after
  each completed keep/trade step, and tolerates missing optional runtime
  helpers during lightweight test/harness loads.
- **Bugfix:** Logger now tolerates lightweight list-controller adapters,
  always emits the raw `itemId` vs `lootNid` guard-rail error, and refreshes
  export CSV content as soon as the export tab becomes visible.
- **UI:** Logger Export tab is temporarily disabled again while the export
  workflow remains staged off in the live logger UI.
- **UI:** Button glow now auto-scales by target button size in
  `Modules/UI/Effects.lua` (dynamic thickness/scale and proc lines/frequency),
  and recomputes on `OnSizeChanged` for responsive fitting.
- **UI:** Removed `Award/Trade` glow wiring from `Controllers/Master.lua`; the
  master frame no longer manages any glow path for `Award`.
- **Refactor:** Rewrote `Modules/UI/Effects.lua` into a stock single-module
  implementation with direct method-driven glow rendering (`ACShine`, `Pixel`,
  `Proc`, `buttonOverlay`), removing profile-name plumbing and defensive
  compatibility branches.
- **UI:** Removed glow profile-name plumbing from button glow APIs; methods now
  resolve by explicit glow type only (for example `ACShine`, `Pixel`, `Proc`,
  `buttonOverlay`) and no longer use names like `CombatPulse`.
- **UI:** Glow effects are now single-choice in `Modules/UI/Effects.lua`: only
  one method can be active at a time (`ACShine`, `Pixel`, `Proc`, or
  `buttonOverlay`), with no combinable style mixing.
- **UI:** Removed explicit `GLOW_PROFILES` presets (`SoftPulse` and
  `CombatPulse`) from `Modules/UI/Effects.lua`; glow tuning now resolves from
  the single default baseline in `DEFAULT_PROFILE_PARTS`.
- **UI:** Added explicit 3.3.5a-safe glow type support in
  `Modules/UI/Effects.lua` for `ACShine`, `Pixel`, `Proc`, and
  `buttonOverlay`, with default subglow settings aligned to the provided
  baseline (`duration=1`, `frequency=0.25`, `length=10`, `lines=8`,
  `scale=1`, `thickness=1`, `x/y offset=0`, white color).
- **UI:** Reduced default glow intensity in `Modules/UI/Effects.lua` (alpha,
  pulse strength, border thickness, and proc density/frequency) for a lighter
  visual footprint.
- **UI:** Added explicit glow/border method registry in
  `Modules/UI/Effects.lua` with canonical styles (`none`, `fill`, `ring`,
  `borderOnly`, `proc`, `button`) and aliases (`border`, `outline`, `pixel`,
  `autocast`, `shiny`, etc.).
- **UI:** Disabled glow on the Master `Award/Trade` button; only `SR` keeps
  contextual glow highlighting.
- **UI:** Added a new `button` glow style in `Modules/UI/Effects.lua` using
  `UI-ActionButton-Border` with pulse animation and button-size scaling; Master
  `SR` now uses this style for a sharper, more visible border glow.
- **Refactor:** Moved button glow/proc rendering internals from `Visuals.lua`
  into `Modules/UI/Effects.lua`; `UIPrimitives.SetButtonGlow` is now a thin
  bridge, keeping primitives and effects concerns separated.
- **Refactor:** Replaced SR proc glow backend with a local `Visuals.lua`
  LCG-like autocast/proc renderer (no full LibCustomGlow dependency), tuned for
  WoW 3.3.5a compatibility and precise button-bound animation.
- **UI:** Tuned `SR` `proc` glow to be tighter to the button and much faster,
  and switched to a local per-frame sparkle updater so animation remains smooth
  and independent from global `AutoCastShine` timing.
- **Bugfix:** FrameXML `proc` glow now creates a named `AutoCastShineTemplate`
  frame per button, preventing `UIParent.lua` nil-name errors on 3.3.5a.
- **UI:** `SR` button glow now supports a native FrameXML-style `proc` effect
  (`AutoCastShineTemplate`) for a stronger, animated highlight similar to
  WeakAuras proc glow behavior, while `Award/Trade` keeps the precise ring glow.
- **UI:** Tightened Master button glow geometry to the exact button border
  (`padding=0`) with profile-driven dynamic edge thickness, and increased pulse
  intensity for higher visibility on both `SR` (blue) and `Award/Trade`.
- **Bugfix:** Master button glow animations now use a Wrath-compatible alpha
  setup on 3.3.5a clients that do not expose `SetFromAlpha`/`SetToAlpha`.
- **UI:** Added pulsing glow cues on Master Loot controls: `SR` now glows when
  the selected item has reserves, and `Award/Trade` glows when an award can be
  executed.
- **UI:** Refined Master button glow visuals to a hybrid style (subtle
  rectangular frame plus shiny ring pulse) while preserving button-sized
  framing.
- **UI:** Removed the extra outer square from Master button glow visuals to
  avoid double-border appearance while keeping the shiny pulse effect.
- **UI:** Removed the top glossy `shine` strip from Master button glows to
  eliminate the visible white line above highlighted buttons.
- **UI:** Master glow styles now support `ring` or `fill` mode; `SR` uses ring
  glow, while `Award/Trade` uses fill-only glow to avoid oversized circular
  aura on wide buttons.
- **UI:** Restored ring glow on `Award/Trade` and adjusted ring sizing to scale
  by button width/height ratio, keeping wide-button highlights visible without
  oversized circular halos.
- **UI:** Ring glow is now anchored to button bounds (with a small fixed
  padding) so the aura follows each button size directly, including wide
  controls like `Award/Trade`.
- **UI:** Ring glow now selects square vs wide highlight textures by button
  aspect ratio, improving `Award/Trade` visual fit while keeping `SR` glow
  style unchanged.
- **UI:** Replaced texture-driven ring glow with a dynamic 4-edge geometric
  ring that is anchored to button bounds, so wide buttons (for example
  `Award/Trade`) keep a consistent border glow shape.
- **UI:** Added FrameXML glow profiles `SoftPulse` and `CombatPulse` for
  animation-group tuning (alpha ranges and pulse cadence). Master now uses
  `SoftPulse` on `SR` and `CombatPulse` on `Award/Trade`.
- **Tooling:** Added `tools/dev-stack-status.ps1` as a single readiness check
  for vendored skills, local Codex installs, Mechanic, and the repo-local MCP
  server.
- **Tooling:** The repo-local MCP server now exposes `dev_stack_status` for
  readiness inspection and `mechanic_bootstrap` for external Mechanic setup.
- **Docs:** Documented the canonical local AFD workflow around
  `dev-stack-status.ps1`, skill sync, Mechanic bootstrap, and MCP usage.
- **Behavior:** The Master Loot window is back to a `250x480` footprint, with its
  roll-table headers, scroll area, paired top/bottom action buttons, mode row,
  left-side action column, and inner control alignment retuned for the narrower
  layout; the `MS | OS | SR | Free | Countdown` row now shares the same left
  start as `Select Item` and `Open SoftRes`, the `Roll` button expands while
  `Clear` keeps its width, and the Hold/Bank/DE dropdowns now keep the same
  right-side gap as `Loot Counter`. The rolls table uses a fixed
  `Player | Info | Count | Rolls` grid,
  and shortens info tags to compact `TIE / OOT / OUT / BLK` codes.
- **Bugfix:** Synthetic `/krt debug raid` players now pass roll intake without
  live-unit checks, and rejected debug submissions no longer whisper fake names.
- **Behavior:** Added `/krt debug raid seed|clear|rolls|roll <1-4|name> [1-100]`
  to seed four synthetic players into the current raid and submit synthetic
  rolls against the active roll session for addon testing.
- **Behavior:** Rolls now use a response-first resolver with centralized eligibility checks,
  explicit tie-at-cutoff handling, runtime participant states, explicit `PASS` / `CANCELLED`
  player responses, and award-time revalidation.
- **Behavior:** Roll response transitions are now explicitly hardened: `PASS` and
  `CANCELLED` stay reversible while the session is open, `TIMED_OUT` stays terminal
  for the current session, and only eligible `ROLL` responses may enter the resolver.
- **Bugfix:** Master Loot now consumes per-row `selectionAllowed` directly from the
  rolls service contract, so controller-side selection and award flows no longer
  reinterpret row pickability from local `status/isEligible` checks.
- **Bugfix:** Final winner validation for award/trade now lives in the rolls service,
  and `Master.lua` consumes the service result directly instead of remapping local
  winner reason codes.
- **Bugfix:** Accepted roll responses now stay candidate-eligible after consuming their
  last allowed roll; extra `/roll` attempts are still denied, but valid winners no longer
  disappear from resolution or award-time validation.
- **Bugfix:** Trade and loot-window multi-award execution now track their active winner
  outside the global compatibility mirror, reducing stale winner state during chained awards
  and inventory trade progress.
- **Behavior:** Rolls eligibility now supports opt-in `manual exclusion`
  checks through the service API, so future loot-ban rules can reuse the same
  intake/display/award validation path.
- **Behavior:** Roll winner selection now uses one unified selection flow for auto winners,
  inventory single-pick, and multi-pick, removing the old `selectedAuto` / `msPrefilled`
  state split inside the `Services/Rolls/*` service modules.
- **Behavior:** The Master Loot rolls frame now defaults to `showRollsOnly`, so non-rolling
  materialized candidates stay in the full runtime model but are hidden from the visible roll table
  until they actually submit a `/roll`.
- **Behavior:** Roll-row state tags such as `TIE`, `OUT`, `TIME`, and `BLOCK` now render in a
  dedicated `Info` column, leaving the `Counter` column for loot-count, reserve-count, and plus-priority
  values only; the Master Loot rolls table now reads left-to-right as `Player | Info | Counter | Rolls`.
- **Behavior:** Single-winner ties now switch the `Award` button to `Reroll`, which clears the
  current roll set, restricts the next intake to the tied players only, and reopens the session
  for a targeted reroll instead of silently blocking on manual resolution.
- **Bugfix:** Master Loot winner selection realigns single-award pick mode with the
  `MLRollWinners` multiselect state, restoring the original `CTRL+click` deselect/swap flow.
- **Behavior:** Inventory/trade winner rows now reuse the same selected-row marker (`> name <`)
  and selection visuals as the loot-window boss roll flow, including multi-copy winner selection.
- **Bugfix:** Inventory/trade multi-awards now execute one winner at a time from the selected
  winner queue, so `self-keep` and real trades both consume one copy, advance to the next
  selected winner, and keep `itemCount` progression symmetric.
- **Refactor:** Centralized loot/item and boss-add ignore lookups into `Modules/IgnoredItems.lua`
  and `Modules/IgnoredMobs.lua`, removing large hardcoded filter tables from `Services/Raid.lua`.
- **Behavior:** Boss filtering now uses the curated raid-only `IgnoredMobs` module to suppress
  LibBossIDs encounter adds, phase units, and support NPCs from Vanilla through Wrath.
- **Bugfix:** Boss filtering now treats `LibBossIDs` as a first-pass allowlist and ignores known
  encounter-helper false positives (for example `Death Knight Understudy`), while suppressing
  near-duplicate boss logs so loot stays attached to the real boss context.
- **Behavior:** `KRT_Reserves` now persists readable player-name keys and strips duplicated
  `playerNameDisplay`; lowercase reserve-name lookup keys remain runtime-only and legacy reserve
  name fields are normalized on load/save.
- **Refactor:** Legacy fallback sunset for raid loot winner resolution: runtime/query paths now resolve
  winners from `loot.looterNid` only; legacy `loot.looter` is diagnostics-only and stripped on normalize/save.
- **Refactor:** Legacy fallback sunset for reserves: canonical display resolution now uses
  `playerNameDisplay` only, and runtime reserve rows no longer use legacy `player` fallback fields.
- **Tooling:** Updated `tools/sv-roundtrip.lua` and `tools/sv-inspector.lua` to enforce strict canonical
  checks (no winner resolution fallback from legacy `loot.looter` and no reserve-name fallback from `original`).
- **Docs:** Marked SV contract with explicit "legacy sunset" status in `docs/RAID_SCHEMA.md` and
  `docs/SV_SANITY_CHECKLIST.md`, including the pre-release schema freeze gate.
- **Behavior:** `schemaVersion` stays at `3`; `v4` is deferred until a net structural simplification is needed.
- **Behavior:** Added a unified canonical SV save pipeline (`Core.PrepareSavedVariablesForSave`)
  executed at `PLAYER_LOGOUT`, so both `KRT_Raids` and `KRT_Reserves` are normalized before persistence.
- **Diagnostics:** Added explicit legacy-field warnings during SV load/save hardening:
  raid warnings now cover legacy runtime caches + `loot[].looter` + `bossKills[].attendanceMask`,
  and reserves warnings now cover legacy `original`/row `player` payload fields and dropped invalid rows.
- **Tooling:** Added `tools/sv-roundtrip.lua` and `tools/run-sv-roundtrip.ps1` for
  `load -> normalize -> save -> reload` no-drift validation on `KRT_Raids` + `KRT_Reserves`.
- **Tooling:** Added mixed legacy fixtures under `tests/fixtures/sv/` for automated
  compatibility validation against old/mixed SavedVariables payloads.
- **Behavior:** Reserves SV naming/storage was canonicalized: player containers now
  persist a single readable player-name key (replacing lowercase keys +
  duplicated `playerNameDisplay`), and reserve rows no longer persist duplicated
  `player` display-name fields; legacy data is migrated on load/save.
- **Behavior:** Raid schema bumped to `v3` with lean persistence compaction at logout:
  default-only/empty optional raid fields are omitted from SavedVariables while
  runtime readers continue applying defaults for backward-compatible behavior.
- **Behavior:** Raid schema bumped to `v2`; boss attendees are now stored as `playerNid` arrays
  (`bossKills[].players`) and loot winners are stored as `looterNid` (`loot[].looterNid`) to
  reduce SavedVariables duplication.
- **Behavior:** Added automatic migration from legacy name-based attendee/winner fields to the
  new `playerNid`-based schema, with Logger/queries/sync paths updated to resolve winner names
  from raid player records.
- **Bugfix:** Warnings save/edit now reads live edit-box text (not async cached draft state),
  and save keeps the affected warning selected with immediate list/preview refresh.
- **Bugfix:** Warnings delete no longer assumes all list row frames exist; removing a warning now
  updates data/refresh without nil-frame Lua errors.
- **Bugfix:** Warnings frame now hooks `OnShow/OnHide` without overriding scaffold/list-controller
  handlers, restoring left preset-list activation and immediate row rendering.
- **Bugfix:** Minimap menu raid actions now use robust raid-group detection and resilient module
  resolution for `Loot Counter` and `MS Changes` actions (`Demand`/`Announce`).
- **Bugfix:** Fixed Lua boolean-expression regression in minimap menu raid-action enabling
  (`cond and false or 1`), which incorrectly kept raid actions disabled even while in raid.
- **Behavior:** MS Changes `Demand`/`Announce` now run whenever the player is in a real raid group,
  independent from `currentRaid` session availability.
- **Bugfix:** `Chat:Announce(...)` now falls back to native raid/party detection when
  `GetGroupTypeAndCount()` does not return a stable group type.
- **Bugfix:** `/krt` with no arguments now shows command help instead of returning silently.
- **Bugfix:** `/krt rw <value>` no longer risks a Lua error on non-numeric input when no warning is selected.
- **Behavior:** `Chat:Announce(...)` now falls back to local `Print` when not in party/raid,
  avoiding unintended solo `SAY` output.
- **Behavior:** LFM spam fallback routing (when no channels are selected) now uses `RAID`/`PARTY`
  in group and local `Print` when solo, instead of forced `SAY`.
- **Bugfix:** Master `Spam Loot` now checks Ready Check permissions (leader/assistant) before calling
  `DoReadyCheck()`.
- **Bugfix:** `Comms.Sync(...)` now supports cores without `GetRealNumRaidMembers/GetRealNumPartyMembers`
  by falling back to `GetNumRaidMembers/GetNumPartyMembers`.
- **Behavior:** Reserve list `Query Item` button now has a short cooldown to avoid rapid repeated queries.
- **Refactor:** Removed unused `LFM period` localization keys that no longer had a slash-command handler.
- **Behavior:** Slash commands that target optional widgets now print a clear message when the widget is
  disabled by feature profile or not available.
- **Bugfix:** Master Loot awarding now verifies the selected winner is still in raid right before
  `GiveMasterLoot(...)`, and refreshes candidate dropdowns when roster drift is detected.
- **Bugfix:** Trade completion logging now attempts to recover missing `currentRollItem` from
  stored trade item context (`itemId/link`) before failing.
- **Behavior:** Reserves CSV import now warns with a format hint when no header is detected and rows
  are skipped.
- **Diagnostics:** Added actionable warnings for Sync chunk total-count changes mid-stream and
  pending-award consume traces (including remaining queue depth).
- **Refactor:** Pending-award TTL is now centralized as `C.PENDING_AWARD_TTL_SECONDS`
  and reused across Master/Loot/Raid flows.
- **Bugfix:** Logger Sync now binds incoming `req` snapshots to the explicit target sender
  to avoid cross-officer request collisions.
- **Bugfix:** Logger Sync `sync` requests now support responder failover: decode/parse/merge failures mark
  only that sender as failed (request stays open), and in raid only leader/assistant responders are accepted
  (officer check is evaluated once on first chunk, with a short roster-stabilization grace window); successful
  `sync` apply now also clears same-request incoming chunk states immediately, and cached unauthorized senders
  are fast-rejected without repeated roster scans.
- **Bugfix:** Master Loot now cancels delayed `LOOT_CLOSED` cleanup when `LOOT_OPENED` fires again,
  preventing stale close-timer cleanup from wiping a freshly opened loot session.
- **Bugfix:** `LOOT_CLOSED` cleanup now TTL-prunes pending awards (5s) instead of hard-resetting them,
  so delayed `CHAT_MSG_LOOT` events keep correct award source mapping.
- **Behavior:** Logger Sync now rate-limits incoming `req/sync` requests per sender
  (6 requests per 30 seconds) to prevent accidental request loops from flooding replies.
- **Bugfix:** Raid unknown-name guards now use a safe fallback
  (`UNKNOWNBEING` or `UKNOWNBEING`) across client variants.
- **Behavior:** Reserves import now reports row diagnostics in chat after success
  (`valid` and `skipped` rows) to make CSV cleanup easier.
- **Behavior:** LFM spam now has hard safety caps and auto-stop
  (max 30 messages or 1800 seconds per run).
- **Refactor:** `Core/DBManager.Mock.lua` is no longer loaded from `!KRT.toc`
  during normal runtime bootstrap.
- **Refactor:** Standardized `Controllers/*` and `Widgets/*` UI owner method declarations to
  `module:*` style (`BindUI`/`EnsureUI`) and aligned `ReservesUI` methods away from `UI=module` aliasing.
- **Bugfix:** Reserves Import window now runs its `OnLoad` initialization on first UI bind,
  restoring drag behavior and first-show setup when the frame is pre-cached.
- **Bugfix:** Fixed Reserves list refresh recursion in `Widgets/ReservesUI.lua` by
  removing a self-referential `UI:RequestRefresh` override that caused stack overflow.
- **UI:** Logger now has two tabs: `History` (existing full logger view) and
  `Export` (separate empty panel scaffold, ready for future export UI work).
- **UI:** Logger `Export` tab now renders two live panes: raid history list on
  the left and the selected raid CSV preview on the right.
- **Bugfix:** Logger Export pane frame naming now matches controller lookups,
  so the raid list and CSV preview populate correctly.
- **Bugfix:** Logger Export CSV editbox now uses the expected global frame name
  (`KRTLoggerExportCsvText`), restoring CSV preview rendering on raid selection.
- **UI:** Logger Export CSV preview is now view-only, auto-selects all text
  while visible, and keeps text layout constrained to the panel bounds.
- **Bugfix:** Logger Export CSV auto-select now uses deferred retry passes
  after content/layout refresh, making full-text selection reliable after raid-row clicks.
- **Bugfix:** Logger Export CSV editbox anchoring now clamps to the scrollframe
  inner bounds (including scrollbar inset), preventing text from rendering
  outside the panel background.
- **UI:** Logger Export CSV input frame chrome is now hidden (no visible input box border)
  while keeping copy/select behavior.
- **Bugfix:** Logger Export CSV now force-hides all InputBox template texture regions
  (including focus redraw) to avoid residual border artifacts on some clients.
- **Bugfix:** Logger Export CSV scrollframe geometry now aligns with panel backdrop insets,
  and CSV layout no longer forces editbox anchors outside the scroll content area.
- **Behavior:** Logger Export raid list now enforces single selection; CTRL/SHIFT
  multi-select and range-select are ignored in that panel.
- **Refactor:** Multi-select input handling now uses centralized scope policies in
  `Modules/UI/MultiSelect.lua`, so each panel can opt-in/out without ad-hoc key checks.
- **Bugfix:** Multi-select scope policies now have strict precedence; when a scope disables multi/range,
  CTRL/SHIFT are ignored even if per-call overrides are passed.
- **Bugfix:** Logger Export raid selection now forces single semantics and keeps one row focused;
  CTRL-click cannot toggle back to a previously selected raid.
- **UI:** Removed the disabled `Export` button from the Logger Raids list footer.
- **UI:** Logger Raids list footer buttons (`Set Current`, `Delete`) are now centered.
- **Refactor:** Unified core bootstrap and runtime event wiring into
  `!KRT/Init.lua`; removed `Core/Init.lua` and `KRT.lua`, and updated toc/tooling paths.
- **Refactor:** Introduced DB-ready raid data layers:
  `Core/DB.lua`, `Core/DBRaidMigrations.lua`, `Core/DBRaidStore.lua`, and
  `Core/DBRaidQueries.lua`. Core raid APIs now delegate to the raid store.
- **Refactor:** Centralized raid-history access behind `RaidStore`; direct
  `KRT_Raids` reads/writes were removed from Services/Controllers and kept in
  DB/bootstrap layers only.
- **Behavior:** Runtime raid caches are now standardized under `raid._runtime`
  and stripped before SavedVariables persistence.
- **Refactor:** Logger read projections now consume the raid query layer for
  boss/attendance/loot datasets.
- **Docs:** Added `docs/RAID_SCHEMA.md` with explicit versioned raid schema
  contract and runtime-cache persistence rules.
- **Tooling:** Added `tools/validate-raid-schema.lua` for offline raid schema
  validation and invariant reporting.
- **Tooling:** Added `tools/check-raid-hardening.ps1` (static hardening gate)
  and `tools/run-raid-validator.ps1` (SV validator runner via `lua`/`luajit`).
- **Refactor:** Added `Core/DBSchema.lua` as the single source of truth for
  `RAID_SCHEMA_VERSION`; core/store/migrations now read schema version from
  the DB schema module.
- **Behavior:** Added slash validation command `/krt validate raids
  [verbose]` backed by `Core/DBRaidValidator.lua` for in-game invariant
  checks with summary and detailed diagnostics.
- **Refactor:** Added `Core/DBManager.lua` and manager wiring in `Core/DB.lua`
  (`SetManager`/`GetManager`) so `DB.Get*Store()` now delegates through a
  pluggable manager with default SavedVariables-backed behavior.
- **Refactor:** Added `Core/DBManager.Mock.lua` with
  `DBManager.CreateInMemoryManager(...)` for tests/smoke scenarios that need a
  non-SavedVariables raid store.
- **Bugfix:** RaidStore consumers now resolve the store only through
  `DB.GetRaidStore()` (no direct module-table fallback), so custom
  DB managers and in-memory mock managers are consistently honored.
- **Refactor:** Added `Core.GetRaidStore()` as a shared accessor and removed
  duplicated local `getRaidStore` helpers across runtime modules; static
  hardening checks now enforce this.
- **Refactor:** Extended DB facade/manager with `GetRaidQueries()` and
  `GetRaidMigrations()` plus `Core.GetRaidQueries()`/
  `Core.GetRaidMigrations()`, and moved consumers to those accessors.
- **Refactor:** Added `GetRaidValidator()` to DB facade/manager
  (`DB.GetRaidValidator()` / `Core.GetRaidValidator()`) and moved slash
  validator lookup behind DB access.
- **Refactor:** Moved logger sync backend from `Services/Syncer.lua` to
  `Core/DBSyncer.lua` and routed Syncer resolution through DB facade
  (`DB.GetSyncer()` / `Core.GetSyncer()`).
- **Refactor:** `DBManager` now ships an explicit SavedVariables-backed default
  manager (`DBManager.SavedVariables`) and supports query/migration stores for
  custom managers and in-memory manager scenarios.
- **Bugfix:** Minimap drag now guards invalid cursor/minimap coordinates and zero-distance normalization,
  preventing rare divide-by-zero errors while Shift-dragging on the ring.
- **Behavior:** Minimap menu now disables the `LootCounter` entry when the optional widget is disabled
  by feature flags or not registered in the UI facade.
- **Behavior:** Minimap menu now disables `Demand` and `Announce` entries when the player is not in a
  raid group (`addon.IsInRaid() == false`).
- **Bugfix:** `Controllers/Changes.lua` now hardens frame-part lookups and raid-table access, avoiding nil
  index errors on early callbacks and raid-leave cleanup paths.
- **Refactor:** Scoped `InitChangesTable` as file-local in `Controllers/Changes.lua`; also removed
  Logger scope warnings (duplicate `Frames` local and module-scoped roster refresh helpers).
- **Bugfix:** Logger raid-selection callbacks now use a shared file-scoped
  `triggerSelectionEvent(...)` helper, fixing nil-global errors during `RaidCreate`
  and related raid-selection refresh flows.
- **Bugfix:** Replaced legacy `addon:SetTooltip(...)` calls with `Frames.setTooltip(...)` in
  `Spammer`, `Logger`, and `Master` to prevent nil-method crashes during UI `OnLoad` binding.
- **Refactor:** Added `Modules/Features.lua` with widget feature profiles (`full`/`core`) and
  `addon.Features` runtime flags (`Config`, `LootCounter`, `Reserves`).
- **Behavior:** `Modules/UIFacade.lua` is now feature-aware (`IsEnabled`, `IsRegistered`) and
  keeps widget calls/registers as no-op when a widget feature is disabled.
- **Behavior:** `Modules/UIBinder.lua` now skips widget script binding when widget APIs are not
  registered (or feature-disabled), and `KRTMasterConfigBtn` routes through `KRT.UI:Call(...)`.
- **Refactor:** Split UI include manifests into `KRT.Core.xml` and `KRT.Full.xml`
  (default `KRT.xml` now includes `KRT.Full.xml`) to support core/full build profiles.
- **Refactor:** Removed `KRT.Core.xml` and `KRT.Full.xml`; `KRT.xml` is now the
  single UI include manifest with direct feature XML includes.
- **Behavior:** Added baseline options bootstrap in `Modules/Utils.Options.lua`
  (`addon.LoadOptions` fallback) so core boot does not depend on `Widgets/Config.lua`.
- **Refactor:** `Modules/UIBinder.lua` no longer uses `loadstring` for UI script binding.
  Binder handlers are now parsed into direct Lua functions and normalized up front.
- **Refactor:** Added centralized event registry in `Modules/Events.lua` for internal bus event names
  and wow-forwarded events (`wow.*`), and migrated core call sites to use `addon.Events`.
- **Refactor:** Split `Modules/Utils.lua` into themed modules:
  `Modules/Utils.LegacyGlobals.lua`, `Modules/Utils.Options.lua`, `Modules/Utils.RaidState.lua`,
  `Modules/Utils.EventBusCompat.lua`, `Modules/Utils.Tooltip.lua`, and `Modules/Utils.UI.lua`.
  `Utils.lua` now acts as a compatibility facade/aggregator.
- **Behavior:** Added legacy alias lockdown in `Core/Init.lua`. Legacy reads like `addon.Raid`/
  `addon.Logger` now resolve through namespaced targets (`addon.Services.*` / `addon.Controllers.*` /
  `addon.Widgets.*`) and emit a debug-mode warning once per alias+callsite to prevent new regressions.
- **Docs:** Import window ownership is documented as `addon.ReservesUI.Import`.
  Legacy `ReservesImport` module was removed and XML now points to the Reserves Import widget.
- **UI:** Logger item context menu now opens a standard `StaticPopup` window with an
  inserted custom button row for direct roll-type selection (`MS/OS/SR/Free/Bank/DE/Hold`)
  plus standard `Cancel`.
- **Refactor:** Logger roll-type picker row was moved from runtime `CreateFrame(...)` construction
  to `UI/Logger.xml`, while keeping popup behavior/layout wiring in `Controllers/Logger.lua`.
- **Bugfix:** Logger roll-type inserted button row is now explicitly attached/anchored to the
  popup on show, preventing hidden or behind-popup button rendering.
- **UI:** Logger roll-type popup layout was polished: improved vertical spacing and centered
  alignment, with uniform button sizing derived from popup width and plain Blizzard-style labels.
- **Bugfix:** Logger roll-type popup now uses stricter side padding and tighter button sizing,
  keeping all seven buttons visually inside popup borders across common UI scales.
- **Bugfix:** Logger roll-type popup now follows a FrameXML-aligned resize path:
  it applies extra height before `StaticPopup_Resize(...)`, then anchors the custom row under
  popup text, keeping the row and standard `Cancel` inside the same window.
- **UI:** Logger roll-type popup vertical spacing was tightened (smaller extra-height and
  title-to-row offset) to reduce empty space while preserving containment.
- **UI:** Logger roll-type popup horizontal side padding was slightly reduced to trim
  left/right empty space around the 7-button row.
- **UI:** Logger roll-type popup spacing was further fine-tuned (about 2px) to tighten
  title/row/cancel vertical rhythm while keeping all controls inside the popup bounds.
- **Bugfix:** Logger UI now refreshes immediately after incoming Sync snapshots (`req`, `push`, `sync`),
  including the Raids list update without requiring manual reopen or reselection.
- **Behavior:** Added Logger Sync feature (`Core/DBSyncer.lua`) using addon-message request/response
  chunking with three commands:
  `/krt logger req <raidId|raidNid> <player>` requests a specific raid snapshot from one target player
  and imports it as a new raid, `/krt logger push <raidId|raidNid> <player>` pushes a selected raid
  snapshot to one target player, and
  `/krt logger sync` merges only into the current raid when zone/size/difficulty signature matches.
- **Behavior:** `req/push` now require an explicit raid reference and no longer fallback to selected/current
  raid; current-raid flows should use `/krt logger sync`.
- **Behavior:** Main event wiring now handles `CHAT_MSG_ADDON` in `KRT.lua` and forwards Sync protocol
  traffic to `addon.Syncer`, keeping slash handling isolated in `EntryPoints/SlashEvents.lua`.
- **Behavior:** Logger Loot sorting is now deterministic across all sortable headers; when primary values
  are equal, ordering falls back to loot name, then item ID, then loot NID to prevent random reshuffles.
- **Behavior:** Logger Loot `Item` header sorting now uses the displayed loot name text
  (item name/link label), with `itemId` as stable fallback tie-breaker.
- **Behavior:** Logger Loot `Source` header is now non-sortable while a boss filter is active
  (column rendered empty), and source sorting now follows the displayed boss name text.
- **Bugfix:** Logger sortable headers now use strict Lua comparators (no `asc and ... or ...` ambiguity),
  fixing broken/unstable ordering and sort-time errors when clicking list headers.
- **Bugfix:** Raid session switching no longer drops the previous current raid when roster data is
  temporarily unavailable (`GetNumRaidMembers()==0`); `Raid:Create(...)` now validates readiness
  before ending the previous session.
- **Behavior:** Added `UPDATE_INSTANCE_INFO` re-checks (plus `RequestRaidInfo()` on raid welcome)
  to catch delayed server-side raid difficulty/instance state updates.
- **Bugfix:** Raid session detection now self-heals on `RAID_ROSTER_UPDATE`: if no current raid
  exists while grouped in a recognized raid instance, KRT runs a live `Raid:Check(...)` and creates
  the session as soon as roster data is available.
- **Bugfix:** Added `PLAYER_DIFFICULTY_CHANGED` handling in `KRT.lua` to re-run raid session checks
  when raid difficulty changes or is adjusted by server fallback.
- **Refactor:** Main WoW event handlers moved back to `KRT.lua`; `EntryPoints/SlashEvents.lua`
  now contains slash-command routing only.
- **Bugfix:** Raid enter checks now re-read live instance data with short staged retries
  (0.3/0.8/1.5/2.5/3.5s) instead of relying on stale event payloads, so automatic unsupported-mode fallback
  (for example Naxx 25H -> 25N) correctly triggers a new raid session without long waits.
- **Bugfix:** Raid session auto-detection now correctly starts a new session on any raid difficulty
  switch (10/25 and Normal/Heroic), using normalized live raid difficulty (dynamic + heroic mode).
- **Refactor:** Fresh-SV canonical raid model finalized: `players[]` is canonical, `_playersByName`
  is derived runtime-only, legacy `playersByName` cleanup paths were removed, and runtime raid caches
  (`_playersByName`, `_playerIdxByNid`, `_bossIdxByNid`, `_lootIdxByNid`) are stripped on logout.
- **Refactor:** Raid schema normalization now enforces stable/unique `playerNid` / `bossNid` /
  `lootNid` and realigns `nextPlayerNid` / `nextBossNid` / `nextLootNid` to canonical data.
- **Refactor:** Added canonical stable `raidNid` for raid records; Logger raid selection/delete
  now resolves by `raidNid` instead of volatile array indices.
- **Refactor:** Raid read APIs are now side-effect free (`GetPlayers`, `GetLoot`) and stable-ID based
  (`GetPlayerID`, `GetPlayerName`).
- **Refactor:** Logger attendee selection/filter/delete flows are now fully stable-ID based
  (`playerNid`), with no fallback to volatile array indices in view-model IDs.
- **Bugfix:** Logger NID index lookups now validate cached index targets and rebuild stale maps after
  list mutations, preventing wrong-row resolutions.
- **Behavior:** Loot Counter now reads canonical raid rows (unique by player name), preserving
  historical `count` values when switching current raid.
- **Refactor:** Loot Counter mutations (`+/-/reset`) now target canonical `playerNid`
  (`Add/Get/SetPlayerCountByNid`) instead of volatile row/index assumptions.
- **Behavior:** Raid roster sync now publishes incremental `RaidRosterDelta` payloads and
  stabilizes transient unknown `raidN` slots with bounded retries to avoid false leave/join churn.
- **Refactor:** Removed legacy internal `RaidRosterUpdate` callback emission; roster listeners now
  consume `RaidRosterDelta` directly.
- **Refactor:** `addon.Raid:GetUnitID()` now uses a live name<->unit cache from roster scans with
  iterator fallback, reducing repeated full-group scans in Master Looter flows.
- **Refactor:** Strict UI controller uniformization for `Changes`, `Reserves`, and Reserves Import widget,
  and `Logger`: removed manual `Toggle/Hide` overrides and kept side effects in `hookOnShow/OnHide`.
- **Refactor:** Standardized top-level feature frame getters for `Logger` and `LootCounter` to
  `makeModuleFrameGetter(...)` (module-cached + global fallback pattern).
- **Behavior:** Debug mode is now runtime-only by policy. Debug state is tracked in runtime state
  (`Utils.isDebugEnabled()`), not persisted in `KRT_Options`; legacy `debug` key is cleared on load.
- **Refactor:** Continued UI API uniformization across feature modules by standardizing
  `initModuleFrame` callbacks to `hookOnShow/hookOnHide` for additive wiring and by removing
  the Warnings-only `Update()` public method in favor of the common `RequestRefresh()` path.
- **Bugfix:** `/krt minimap on|off` now writes `minimapButton` via `Utils.setOption(...)`, keeping
  runtime options (`addon.options`) and SavedVariables (`KRT_Options`) synchronized.
- **Localization:** Removed hardcoded fallback texts in Reserves Import widget popup/status paths and now
  always source those messages from `addon.L`.
- **Localization:** LFM preview output in `Spammer` now uses localized role labels and localized
  `Need` token (`L.StrSpammerNeedStr`).
- **Refactor:** Standardized runtime module file scaffolding around canonical section headers
  (`Internal state`, `Private helpers`, `Public methods`) and kept public module APIs in PascalCase
  (no mass rename/breaking API changes).
- **Refactor:** Added `Utils.setOption(key, value)` and migrated option writes in
  `Config`, `Minimap`, `Reserves`, and Reserves Import widget to keep runtime options and SV in sync centrally.
- **Refactor:** Added shared UI bootstrap helpers `Utils.initModuleFrame(...)` and
  `Utils.bootstrapModuleUi(...)`; migrated `Config`, `Warnings`, `Changes`, `Spammer`, Reserves Import widget,
  `Logger`, `Master`, `LootCounter`, and `Reserves` to reduce repeated OnLoad/controller wiring without
  behavior changes; same pattern also applied to Logger internal popups (`BossBox`, `AttendeesBox`).
- **Refactor:** Removed feature bootstrap migration fallbacks and standardized all
  runtime module files on direct `addon.Core.getFeatureShared()` usage.
- **Refactor:** Removed deprecated placeholder files `Features/CoreGameplay.lua` and
  `Features/LootStack.lua` (both were not loaded by TOC).
- **Refactor:** Renamed feature file paths `Features/ReserveImport.lua` -> `Features/ReservesImport.lua`
  and `UI/ReserveImport.xml` -> `UI/ReservesImport.xml`; import owner is now `addon.ReservesUI.Import`.
- **Behavior:** Simplified account SavedVariables to feature-scoped keys:
  `KRT_Raids`, `KRT_Players`, `KRT_Reserves`, `KRT_Warnings`, `KRT_Spammer`, and `KRT_Options`.
  Runtime session keys (`KRT_CurrentRaid`, `KRT_LastBoss`, `KRT_NextReset`) are no longer persisted.
- **Behavior:** SavedVariables now assume a fresh model only (no legacy import path).
- **Refactor:** Continued modular architecture migration (wave 4d). UI legacy XML was decomposed into
  `UI/Minimap.xml`, `UI/ReservesTemplates.xml`, `UI/Master.xml`, and `UI/LootCounter.xml`; `KRT.xml`
  now includes these feature files directly, with no behavior changes.
- **Refactor:** Completed wave 4d cleanup by removing deprecated `UI/LegacyHead.xml`,
  `UI/LegacyMid.xml`, and `UI/LegacyTail.xml` placeholders from the repository.
- **Refactor:** Continued modular architecture migration (wave 4c.1). Core feature headers now consume
  shared context from `addon.Core.getFeatureShared()` in `KRT.lua`, reducing repeated local/bootstrap blocks
  in `Raid/Chat/Minimap/Rolls/Loot/Master/LootCounter` files without behavior changes.
- **Refactor:** Continued modular architecture migration (wave 4c). `Features/LootStack.lua` was split into
  `Features/Rolls.lua`, `Features/Loot.lua`, and `Features/Master.lua`; `LootStack.lua` remains as placeholder.
- **Refactor:** Continued modular architecture migration (wave 4b). Runtime core split further into
  `Features/Raid.lua`, `Features/Chat.lua`, `Features/Minimap.lua`, `Features/LootStack.lua`,
  and `Features/LootCounter.lua`; `Features/CoreGameplay.lua` is now a migration placeholder.
- **Refactor:** Continued modular architecture migration (wave 4). Core gameplay runtime modules
  (`Raid/Chat/Minimap/Rolls/Loot/Master/LootCounter`) moved to `Features/CoreGameplay.lua`,
  and slash/event wiring moved to `Features/SlashEvents.lua`, leaving `KRT.lua` as thin bootstrap/glue.
- **Refactor:** Continued modular architecture migration (wave 3). Logger runtime stack
  (Store/View/Actions/lists/popups) moved to `Features/Logger.lua`, and Logger UI moved to `UI/Logger.xml`,
  with `KRT.lua`/`KRT.xml` keeping only migration placeholders and include orchestration.
- **Refactor:** Continued modular architecture migration (wave 2). `Reserves` and `ReserveImport` were
  extracted into `Features/Reserves.lua` and `Features/ReservesImport.lua` with matching `UI/Reserves.xml`
  and `UI/ReservesImport.xml`, preserving existing behavior and public module APIs.
- **Refactor:** Started modular architecture migration (wave 1). `KRT.lua`/`KRT.xml` are now split with
  `Features/*.lua` and `UI/*.xml` include files, preserving existing runtime behavior and public module APIs.
- **Bugfix:** SoftRes import mode is now synchronized between runtime reserves state and
  `addon.options/KRT_Options`, so ReserveImport slider/parsing always matches the active mode after load/import.
- **Bugfix:** Reserve List window now relies on the inherited `KRTFrameTemplate` background to prevent
  background bleed outside the panel border.
- **UI:** Reserve List rows now use a stronger odd/even stripe contrast and a subtle horizontal delimiter line
  on each row for better readability.
- **UI:** Reserve List now also draws the delimiter on top of the first visible row of each
  collapsible group.
- **UI:** Reserve List item and player lines are vertically re-aligned to better center on the icon middle.
- **UI:** Reserve List now uses slightly more spacing between item and player lines while keeping icon-centered
  alignment.
- **UI:** Reserve List tooltips no longer show the boss/source line (keeps tooltip content minimal).
- **Packaging:** GitHub source archives now export only the `!KRT` addon folder by marking
  repository docs and dev files as `export-ignore`.
- **Refactor:** Renamed `Localization/ErrorLog.en.lua` to `Localization/DiagnoseLog.en.lua` and
  migrated diagnostic storage from `addon.E` to `addon.Diagnose`.
- **Refactor:** Added local `Diag` wrappers and switched diagnostic callsites from `Diagnose.*` to
  `Diag.*`; reorganized `DiagnoseLog.en.lua` by feature categories.
- **Behavior:** Diagnostic templates are now categorized by severity buckets:
  `Diagnose.I`, `Diagnose.W`, `Diagnose.E`, `Diagnose.D`, with matching callsites in `KRT.lua`.
- **Refactor:** Moved remaining hardcoded diagnostic strings in `KRT.lua`/`Modules/Utils.lua` into
  `Localization/DiagnoseLog.en.lua` (LoggerSelect, LoggerUI, callback execution, manual loot tag).
- **Bugfix:** Removed the `table: XXXXXXXX:` chat prefix from logger output by overriding
  `addon:Print` to forward through LibCompat without the addon self-label.
- **Bugfix:** Fixed nil getFrame error in UI module factories (Reserves, ReserveImport, Config, Warnings, Changes, Logger). Each module now properly initializes getFrame with `Utils.makeFrameGetter()` before using it in `makeUIFrameController()`.
- **Bugfix:** Logger module had getFrame redefined after factory initialization; removed duplicate definition to preserve correct execution order.
- **Bugfix:** Added missing `Diagnose.D.LogReservesImportWrongModePlus` log template used by Reserves CSV validation.
- **Localization:** Moved hardcoded Reserves tooltip/display strings (item/source labels and summary lines) into `addon.L`.
- **Behavior:** Reserved-roll announce text now hides `(P+N)` and `(xN)` suffixes and shows only the player list.
- **Bugfix:** Master Looter `Import SoftRes/Open SoftRes` button now updates immediately
  after SoftRes import and list clear operations.
- **Refactor:** Loot Counter and Reserve List windows now use only coalesced event-driven refresh
  (`RequestRefresh`) and no longer perform redundant immediate redraw calls.
- **Behavior:** Loot Counter refresh is now driven by `RaidRosterDelta` and
  `PlayerCountChanged`; removed in-refresh `UpdateRaidRoster()` calls to prevent loop spam.
- **Behavior:** Removed standalone `/krtcounts`; Loot Counter is now toggled via `/krt counter`.

## 2026-02-08
**REFACTORING PROJECT COMPLETE** — Code consolidation initiative (3 phases) concluded.

### Consolidation Summary (Total: ~108-123 lines eliminated)
- **Phase 1 (High priority, Low risk):** 33 lines
  - Consolidated duplicated `GetPlus()` helper via `MakePlusGetter()` factory (8 lines)
  - Consolidated `GetMasterFrameName()` duplicate handling (10 lines)
  - Created `Utils.makeFrameGetter()` factory consolidating 3x identical frame getter patterns (15 lines)

- **Phase 2 (Medium risk, Significant impact):** 75-90 lines
  - Added `addon:makeUIFrameController()` factory consolidating Toggle/Hide/Show patterns across 9 UI modules
  - Applied to: Master Looter, LootCounter, Reserves, ReserveImport, Config, Warnings, Changes, Spammer, Logger

- **Phase 3 (Low priority, Optional):** Analysis completed; no additional consolidations identified
  - Verified CheckPlayer pattern already centralized in addon.Raid
  - Verified dropdown logic already parameterized via FindDropDownField
  - Verified all major consolidations already completed

### Changes
- Refactor: Moved `makeUIFrameController` factory from KRT.lua to Utils.lua (shared utility factory layer); added backwards-compatible alias in KRT.lua.
- Refactor: Master Looter dropdown handlers (holder/banker/disenchanter) consolidated to eliminate 3 identical branches via parameterized FindDropDownField.
- Refactor: Master Looter UpdateDropDowns consolidated from 3 repetitive if-elseif blocks to single loop via FindDropDownField (reduces code duplication).
- Master Looter: Hold/Bank/DE clears rolls only after completed assignment; inventory trade setup no longer wipes rolls early.
- Minimap: left-clicking the minimap icon now toggles the context menu open/closed.
- Docs: updated AGENTS.md with explicit `.luacheckrc` maintenance guidance for addon globals.
- Docs: fixed OVERVIEW.md repository links to use root-relative paths.
- Tooling: refreshed `.luacheckrc` with explicit KRT frame/global allowlist entries.

## 2026-02-05
- Docs: Split change log out of AGENTS.md into CHANGELOG.md (no runtime behavior change).

---

## Legacy entries (moved from the old AGENTS.md)

- 2026-03-15: Skip raid target icon on the master looter when they win their own trade.
- 2026-03-14: Master Loot roll button now respects multi-reserve roll counts for the local player.
- 2026-03-13: Converted Config/Warnings/Changes/Reserves/BossBox UI refresh to on-demand updates.
- 2026-03-12: Fixed Master Looter inventory insert to match cursor items by itemId fallback.
- 2026-03-12: Simplified Master Looter bag item selection (click drop, tradeable gate, bag scan).
- 2026-03-12: Localized XML UI strings from KRT.xml/Templates.xml via Lua.
- 2026-03-12: Loot Counter keeps scroll position and relies on localization strings.
- 2026-03-12: Loot Counter player names now use class colors.
- 2026-03-12: Loot Counter headers use the same grey styling as Master Looter.
- 2026-03-11: Deterministic changes list ordering and refresh after deletions.
- 2026-03-11: Improved list controller sorting, row sizing, and scroll inset safety.
- 2026-03-10: Localized Reserve List window buttons (clear, query item, close).
- 2026-03-10: Master Loot reserve list button toggles insert/open; Loot Counter uses former Raid List button.
- 2026-03-09: Master Looter uses GetContainerItemLink for inventory item links in 3.3.5a.
- 2026-03-08: Split log localization strings into Localization/ErrorLog.en.lua.
- 2026-03-07: Clear rolls when self-awarding stacked inventory items (multi-count trade keep path).
- 2026-03-06: Master Looter buttons: countdown gates item selection, roll start, SR gated by reserved item,
  roll/award gating, reset rolls on awards; selection now enables Hold/Bank/DE buttons.
- 2026-03-05: Removed Docs/KRT_STANDARD.md and Docs/WoW_Addons.pdf references and files.
- 2026-03-05: Removed TemplatesLua directory references from AGENTS and deleted TemplatesLua.
- 2026-03-02: Removed `/krt lfm period` command and default LFM period SV entry.
- 2026-03-01: Renamed History module to Logger (UI, strings, and references).
- 2026-02-21: Removed KRT_Debug SavedVariable (log levels are runtime-only).
- 2026-02-15: Parse pushed loot messages and refresh Loot Logger on new loot.
- 2026-02-01: Fixed CallbackHandler OnUsed/OnUnused wiring in event dispatcher and templates.
- 2026-01-13: Standardized repository language to English (AGENTS + codebase rules).
- 2026-01-13: Reaffirmed KRT.lua monolithic policy and in-file module skeleton.
- 2026-01-13: Codified Lua 5.1 style rules (globals, formatting, naming, errors/returns, iteration).
- 2026-01-07: Simplified SavedVariables: removed unused versioning/audit keys.
- 2026-01-02: Standardized module skeleton, updated templates/docs, and introduced addon.LootCounter (kept aliases).
- 2025-12-27: Hardened debug logger guard, trimmed slash args, removed unused CHAT_MSG_ADDON entry.
- 2025-12-24: Added BINDING docs/templates as canonical patterns for all work.
- 2025-09-27: SR roll button allows non-reserved players to roll once (SR priority remains).
- 2025-09-26: Load saved SR reserves during addon initialization.
- 2025-09-25: Reserve list rows place text to the right of icons; hide icons until item data loads.
- 2025-09-24: Reserve list row alignment + auto-query missing item icons on open.
- 2025-09-23: Reset Master Loot ItemCount on item change/award; refresh counts for loot sources.
- 2025-09-22: Expanded vendored library guidance into explicit bullet rules.
- 2025-09-21: Prefer vendored libs; avoid Utils/KRT duplicates; skip fallbacks when libs are vendored.
- 2025-09-20: Enlarged Loot Counter window, centered title, and enabled dragging.
- 2025-09-13: Updated nil-check and API fallback guidelines.
- 2025-09-10: Clarified proprietary WoW API requirement.
- 2025-09-09: Integrated new template; removed unused libs.
- 2025-09-08: Renamed Logger module to History to avoid conflict with debugging logger.
- 2025-09-07: Clarified monolithic structure and updated CLI command list.
- 2025-09-05: Initial lightweight version; removed binding “recipes”. Added dev-only branching policy.
