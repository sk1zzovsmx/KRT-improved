# KRT – Development Standard (WotLK 3.3.5a • Lua 5.1)

This document defines the **standard patterns** to keep KRT consistent across all changes.
If a pattern conflicts with existing in-repo conventions, prefer the repo convention and update this doc.

## 0) Scope
Applies to:
- Lua modules in `KRT.lua` and `Modules/*.lua`
- XML UI in `KRT.xml` and `Templates.xml`
- Slash commands, SavedVariables, comms, logging, throttling

Non-goals:
- Re-architecting into multiple addons or introducing Ace3 UI frameworks

## 1) Golden rules (the “why”)
1. **Single namespace:** everything lives under `addon.*`
2. **Deterministic behavior:** same inputs -> same outcomes (especially rolls/winner logic)
3. **Event-driven first:** no heavy OnUpdate loops; if needed, throttle
4. **Low churn UI:** avoid rebuilding UI each tick; batch updates
5. **Stable SV & CLI:** never break existing keys/commands without changelog note

## 2) File & module structure
### 2.1 Namespace & locals
- Main file owns namespace:
  - `local ADDON_NAME, addon = ...`
  - `addon = addon or {}`  (defensive, if codebase requires)
- In each module file / do-block:
  - `addon.ModuleName = addon.ModuleName or {}`
  - `local module = addon.ModuleName`
  - `local L = addon.L` (only if strings are used)

### 2.2 Encapsulation
- Use `do ... end` blocks for modules to avoid leaking locals.
- Keep functions short; group private helpers above public API.

### 2.3 Naming
- Public module methods: `module:Init()`, `module:Enable()`, `module:Disable()`, `module:Refresh()`
- Event handlers: `module:OnEVENT_NAME(...)` or `module:OnLootOpened(...)`
- UI callbacks: `addon.UI:OnXxx(self, ...)` (UI code should be centralized)

## 3) Lifecycle (one standard entrypoint)
### 3.1 Core init sequence
1) `ADDON_LOADED` (check addonName, init SV, init modules, init UI)
2) `PLAYER_LOGIN` (optional: anything needing full UI or player data)
3) `PLAYER_ENTERING_WORLD` (optional: instance/zone dependent checks)

### 3.2 Standard init skeleton
See: `TemplatesLua/KRT_CoreTemplate.lua`

## 4) Event wiring (single event frame + dispatcher)
### 4.1 Rationale
- One registered frame avoids scattered RegisterEvent calls and makes auditing easy.

### 4.2 Standard
- `addon.EventFrame` is the only frame that registers WoW events.
- A small dispatcher maps `event -> list of handlers`.

See: `TemplatesLua/KRT_EventDispatcher.lua`

## 5) SavedVariables (SV) standard
### 5.1 Principles
- Never rename/remove SV keys silently.
- Use a **schema version** and migrations for structural changes.

### 5.2 Standard fields
- `KRT_Options.schemaVersion` (number)
- `KRT_Options.migrations` (optional table for audit)
- Defaulting:
  - create missing tables
  - fill missing keys with defaults
  - never overwrite user-set values

See: `TemplatesLua/KRT_SVTemplate.lua`

## 6) Logging & debug
- Use LibLogger (embedded on `addon`) for diagnostics.
- Gate verbose output behind `KRT_Debug` or `KRT_Options.debug`.
- Never spam chat in combat; prefer internal logger.

Standard:
- `addon:LogInfo(msg, ...)`
- `addon:LogWarn(msg, ...)`
- `addon:LogError(msg, ...)`
- `addon:LogDebug(msg, ...)` (requires debug flag)

If the repo has different names, keep repo names and update this section.

## 7) Throttling (chat/announces/UI refresh)
### 7.1 Pattern
- Use a small throttle utility:
  - key-based (string)
  - delay in seconds
  - uses `GetTime()`

See: `TemplatesLua/KRT_ThrottleTemplate.lua`

### 7.2 Rules
- Any repeated output (RW/RAID/SAY/WHISPER) must be throttled.
- UI refresh should be batched (e.g. 0.05–0.2s) during spammy events.

## 8) Localization (I18n)
- All user-facing text must be `L["KEY"]`.
- Keys are stable; values can change.
- Avoid string concatenation in hot paths; format with `string.format`.

## 9) UI standard (XML + Lua)
### 9.1 XML rules
- Use `Templates.xml` for shared look & feel.
- Name frames consistently (`KRT...`) and keep a single owner module for logic.

### 9.2 Lua rules
- UI callbacks should route into `addon.UI*` modules.
- No logic inside XML scripts beyond forwarding:
  - `<OnLoad> addon.UI:OnLoad(self) </OnLoad>`
  - `<OnClick> addon.UI:OnClick(self, button) </OnClick>`

See: `TemplatesLua/KRT_UITemplate.lua`

## 10) Slash commands standard
- One root handler for `/krt` and `/kraidtools`.
- Subcommands are registered in a table map:
  - `sub["config"] = function(args) ... end`

See: `TemplatesLua/KRT_SlashTemplate.lua`

## 11) Comms (SendAddonMessage)
- One prefix constant, e.g. `addon.COMM_PREFIX = "KRT"`
- Single dispatcher for inbound addon messages (CHAT_MSG_ADDON)
- Messages are versioned:
  - `v=1;type=...;payload=...` (or a compact delimiter format)

## 12) “How to add a feature” checklist (the standard workflow)
1. Pick module (or create `addon.NewModule` via template)
2. Add/adjust SV defaults + migration (if needed)
3. Add localization keys
4. Add UI (if needed) via Templates.xml + UI routing
5. Register events via dispatcher
6. Add throttle keys for any repeating outputs
7. Update `/krt` help text
8. Manual test checklist (login, reload, raid sim, loot events, SV persist)
9. Add note in `AGENTS.md` + `18) Change log` if public surface changed

---

## Appendix A) Canonical templates
- `TemplatesLua/KRT_CoreTemplate.lua`
- `TemplatesLua/KRT_EventDispatcher.lua`
- `TemplatesLua/KRT_ModuleTemplate.lua`
- `TemplatesLua/KRT_SVTemplate.lua`
- `TemplatesLua/KRT_ThrottleTemplate.lua`
- `TemplatesLua/KRT_UITemplate.lua`
- `TemplatesLua/KRT_SlashTemplate.lua`
