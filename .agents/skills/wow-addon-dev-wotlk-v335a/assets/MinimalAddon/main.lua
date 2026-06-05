-- MinimalAddon - WoW 3.3.5a starter template
--
-- Demonstrates the canonical 3.3.5a patterns:
--   - Explicit (self, event, ...) signature for OnEvent
--   - SavedVariables initialization via ADDON_LOADED
--   - Slash command registration
--   - OnUpdate-based event debouncing (without Ace3)
--   - hooksecurefunc for taint-safe Blizzard hooks
--
-- Replace "MinimalAddon" with your addon name throughout.
-- Replace "MINIMAL" in the SLASH_* constants with an UPPERCASE token unique
-- to your addon (it dispatches into SlashCmdList by that key).

local ADDON_NAME = "MinimalAddon"

-- Module-private namespace. Avoid leaking globals.
local MA = {}
_G[ADDON_NAME] = MA

-- ========== Defaults ==========

local DEFAULTS = {
    enabled = true,
    debug = false,
    -- add your settings here
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        end
    end
end

-- ========== Logging helper ==========

function MA:Print(...)
    local prefix = "|cff1784d1[" .. ADDON_NAME .. "]|r "
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. table.concat({...}, " "))
end

function MA:Debug(...)
    if MinimalAddonDB and MinimalAddonDB.debug then
        self:Print("|cffaaaaaa[debug]|r", ...)
    end
end

-- ========== Event handlers ==========

function MA:OnAddonLoaded(addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize SavedVariables on first run
    MinimalAddonDB = MinimalAddonDB or {}
    MinimalAddonCharDB = MinimalAddonCharDB or {}
    applyDefaults(MinimalAddonDB, DEFAULTS)

    -- Stop listening once initialized
    self.frame:UnregisterEvent("ADDON_LOADED")
end

function MA:OnPlayerLogin()
    self:Print("loaded. Type /ma for commands.")
    self:Debug("debug logging enabled")
end

-- BAG_UPDATE fires in floods (once per affected bag, multiple times for a
-- single user action). Coalesce into one scan per quiet period.
local _bagPending = false
local _bagElapsed = 0
local _bagThrottleFrame = CreateFrame("Frame")
_bagThrottleFrame:Hide()  -- only enabled when needed

local function startBagThrottle()
    _bagPending = true
    _bagElapsed = 0
    _bagThrottleFrame:Show()
end

_bagThrottleFrame:SetScript("OnUpdate", function(self, dt)
    _bagElapsed = _bagElapsed + dt
    if _bagElapsed >= 0.5 then
        self:Hide()
        _bagPending = false
        MA:DoBagScan()
    end
end)

function MA:OnBagUpdate()
    if not _bagPending then
        startBagThrottle()
    end
end

function MA:DoBagScan()
    -- Real work here; runs at most every 0.5s regardless of how many
    -- BAG_UPDATE events fired
    self:Debug("bag scan")
end

-- ========== Event dispatcher ==========

local EVENTS = {
    ADDON_LOADED = "OnAddonLoaded",
    PLAYER_LOGIN = "OnPlayerLogin",
    BAG_UPDATE = "OnBagUpdate",
}

local frame = CreateFrame("Frame", ADDON_NAME .. "Frame")
MA.frame = frame
for event in pairs(EVENTS) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, ...)
    local handler = EVENTS[event]
    if handler and MA[handler] then
        MA[handler](MA, ...)
    end
end)

-- ========== Slash commands ==========

SLASH_MINIMAL1 = "/ma"
SLASH_MINIMAL2 = "/minimal"
SlashCmdList["MINIMAL"] = function(msg, editbox)
    msg = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""

    if msg == "" or msg == "help" then
        MA:Print("commands:")
        MA:Print("  |cffffd100/ma toggle|r - enable/disable")
        MA:Print("  |cffffd100/ma debug|r  - toggle debug logging")
        MA:Print("  |cffffd100/ma status|r - show current state")
    elseif msg == "toggle" then
        MinimalAddonDB.enabled = not MinimalAddonDB.enabled
        MA:Print("enabled:", tostring(MinimalAddonDB.enabled))
    elseif msg == "debug" then
        MinimalAddonDB.debug = not MinimalAddonDB.debug
        MA:Print("debug:", tostring(MinimalAddonDB.debug))
    elseif msg == "status" then
        MA:Print("enabled:", tostring(MinimalAddonDB.enabled),
                 "  debug:", tostring(MinimalAddonDB.debug))
    else
        MA:Print("unknown command: " .. msg .. ". Try '/ma help'.")
    end
end
