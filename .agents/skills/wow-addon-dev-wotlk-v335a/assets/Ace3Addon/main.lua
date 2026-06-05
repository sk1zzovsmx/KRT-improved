-- Ace3Addon - WoW 3.3.5a Ace3 starter template
--
-- Demonstrates the canonical Ace3 stack on 3.3.5:
--   AceAddon-3.0    - addon lifecycle (OnInitialize, OnEnable, OnDisable)
--   AceEvent-3.0    - event registration with method-name dispatch
--   AceDB-3.0       - profile/character/realm-scoped SavedVariables
--   AceConsole-3.0  - slash-command registration
--   AceTimer-3.0    - timer scheduling (use instead of OnUpdate accumulators)
--
-- IMPORTANT: this template assumes Ace3 r1198-era libraries embedded under
-- Libs/. Newer releases break on Lua 5.1 (see references/ace3-on-335.md).

local ADDON_NAME = "Ace3Addon"

local Ace3Addon = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceEvent-3.0",
    "AceConsole-3.0",
    "AceTimer-3.0"
)
_G[ADDON_NAME] = Ace3Addon

-- ========== Defaults ==========

local DEFAULTS = {
    profile = {
        enabled = true,
        debug = false,
        scale = 1.0,
    },
    char = {
        firstRun = true,
    },
}

-- ========== Lifecycle ==========

function Ace3Addon:OnInitialize()
    -- Called when the addon is loaded but before PLAYER_LOGIN.
    -- SavedVariables are accessible here.

    self.db = LibStub("AceDB-3.0"):New("Ace3AddonDB", DEFAULTS, true)

    -- AceConsole slash command registration (handles /aa and /ace3addon)
    self:RegisterChatCommand("aa", "OnSlashCommand")
    self:RegisterChatCommand("ace3addon", "OnSlashCommand")
end

function Ace3Addon:OnEnable()
    -- Called when the addon is enabled (after OnInitialize, before any events).

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("BAG_UPDATE", "OnBagUpdate")

    self:Print("loaded. Type /aa for commands.")

    if self.db.char.firstRun then
        self:Print("|cffffd100first run detected.|r Use /aa config to set up.")
        self.db.char.firstRun = false
    end
end

function Ace3Addon:OnDisable()
    -- Called when the addon is disabled. Unregister anything that needs
    -- explicit cleanup; AceEvent handles its own.
end

-- ========== Event handlers ==========

function Ace3Addon:OnPlayerEnteringWorld()
    self:Debug("entered world")
end

-- BAG_UPDATE coalescing via AceTimer (much cleaner than OnUpdate)
function Ace3Addon:OnBagUpdate(event, bagID)
    if self.bagTimer then
        self:CancelTimer(self.bagTimer)
    end
    self.bagTimer = self:ScheduleTimer("DoBagScan", 0.5)
end

function Ace3Addon:DoBagScan()
    self.bagTimer = nil
    self:Debug("bag scan")
    -- expensive work here; runs at most once per quiet 0.5s
end

-- ========== Helpers ==========

function Ace3Addon:Debug(...)
    if self.db.profile.debug then
        self:Print("|cffaaaaaa[debug]|r", ...)
    end
end

-- ========== Slash command ==========

function Ace3Addon:OnSlashCommand(msg)
    msg = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""

    if msg == "" or msg == "help" then
        self:Print("commands:")
        self:Print("  |cffffd100/aa toggle|r - enable/disable")
        self:Print("  |cffffd100/aa debug|r  - toggle debug logging")
        self:Print("  |cffffd100/aa status|r - show current state")
    elseif msg == "toggle" then
        self.db.profile.enabled = not self.db.profile.enabled
        self:Print("enabled:", tostring(self.db.profile.enabled))
    elseif msg == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        self:Print("debug:", tostring(self.db.profile.debug))
    elseif msg == "status" then
        self:Print("enabled:", tostring(self.db.profile.enabled),
                   "  debug:", tostring(self.db.profile.debug),
                   "  scale:", tostring(self.db.profile.scale))
    else
        self:Print("unknown command: " .. msg .. ". Try '/aa help'.")
    end
end
